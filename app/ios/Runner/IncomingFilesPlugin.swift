import Flutter
import UIKit

/// Bridges the OS "open this file with the app" plumbing (AirDrop / "Open
/// with…" / a share intent — issue #298) **and** a URL shared from the browser
/// share sheet (issue #343) to Dart over the
/// `is.banner.callerscompendium/incoming_files` channel.
///
/// The native side does exactly one thing per payload: hand Dart either the
/// **path** of a local copy of an incoming file (#298), or the **raw URL
/// string** shared into the app (#343). It never parses, trusts, or interprets
/// a payload — Dart owns every byte of validation and import (`ArchiveIntake`
/// for files, `validateSharedContraDbProgramUrl` for URLs; both are untrusted
/// input). Incoming files are copied into the app's temporary directory first,
/// so the path Dart receives is always readable.
///
/// Shared URLs are delivered out-of-band: the Share Extension writes them into
/// the shared App Group, then best-effort wakes this app via its custom scheme.
/// Because that wake is best-effort (issue #428), this app treats the App Group
/// as the source of truth and **drains it on every activation**
/// (`sceneDidBecomeActive`), so a payload left behind by a missed wake — or one
/// shared while the app was suspended/closed — is always recovered. The drain is
/// an atomic take-and-clear, so a wake (`openURLContexts`) and the foreground
/// drain firing for the same payload never double-imports it.
///
/// Registered manually from `AppDelegate.didInitializeImplicitFlutterEngine`.
/// It receives scene life-cycle events via `registrar.addSceneDelegate`, so the
/// stock `FlutterSceneDelegate` is left untouched.
public class IncomingFilesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?

  /// App Group shared with the Share Extension; shared URLs are handed over
  /// through its `UserDefaults` suite.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

  /// Key under which the Share Extension appends raw shared URL strings as a
  /// FIFO queue (issue #428).
  private static let sharedQueueKey = "SharedImportQueue"

  /// Legacy single-value slot written by pre-#428 Share Extension builds. Still
  /// drained so a payload orphaned by an old (broken-wake) build is recovered on
  /// the next launch.
  private static let legacySharedUrlKey = "SharedImportURL"

  /// Custom scheme the Share Extension uses to wake this app.
  private static let hostScheme = "callerscompendium"

  /// Path captured from a launch (cold-start) file URL, consumed exactly once
  /// by the `getInitialFile` pull once the Dart UI is ready.
  private var pendingInitialPath: String?

  /// Shared URLs drained from the App Group *before* Dart performed its
  /// one-time cold-start `getInitialUrl` pull. The UI isn't ready yet, so they
  /// wait here; the pull returns the first (opened over the app shell) and
  /// flushes any extras onto the warm `urlShared` stream.
  private var pendingInitialUrls: [String] = []

  /// Set once Dart pulls the cold-start URL. Before this the UI isn't ready, so
  /// drained URLs are buffered for the pull; afterwards they're pushed on the
  /// `urlShared` stream. This is what guarantees a cold orphan lands over the
  /// ready app shell rather than being dropped against a not-yet-built navigator.
  private var initialUrlPulled = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = IncomingFilesPlugin()
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/incoming_files",
      binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitialFile":
      let path = pendingInitialPath
      pendingInitialPath = nil
      result(path)
    case "getInitialUrl":
      result(takeInitialSharedURL())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterSceneLifeCycleDelegate

  /// Cold start: the app was launched to open a file. Stash it for the
  /// `getInitialFile` pull — the Dart UI opens first, then imports over the app
  /// shell. Shared URLs are NOT read here: they're delivered out-of-band via the
  /// App Group and drained on activation (`sceneDidBecomeActive`), which also
  /// recovers a cold orphan the wake never triggered.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else {
      return false
    }
    guard let path = localCopyPath(forContexts: contexts) else { return false }
    pendingInitialPath = path
    return true
  }

  /// Warm start: a file or the Share Extension's custom-scheme wake arrives
  /// while the app is already running. A wake drains the App Group immediately
  /// for responsiveness; `sceneDidBecomeActive` re-drains as the authoritative
  /// fallback, and the take-and-clear makes that double-fire idempotent.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool {
    if URLContexts.contains(where: { $0.url.scheme == Self.hostScheme }) {
      drainSharedURLs()
      return true
    }
    guard let path = localCopyPath(forContexts: URLContexts) else { return false }
    channel?.invokeMethod("fileOpened", arguments: path)
    return true
  }

  /// Authoritative foreground drain (issue #428): fires on every activation, so
  /// any payload left in the App Group — because the wake never fired, or the
  /// item was shared while the app was suspended/closed — is always recovered.
  @available(iOS 13.0, *)
  @objc public func sceneDidBecomeActive(_ scene: UIScene) {
    drainSharedURLs()
  }

  // MARK: - Shared-URL delivery

  /// Drains pending shared URLs and delivers each through the existing Dart
  /// path. Before Dart's cold-start pull the UI isn't ready, so they're buffered
  /// for `getInitialUrl`; afterwards they're pushed on the warm `urlShared`
  /// stream. Dart OWASP-validates every string before import — the native side
  /// forwards verbatim and interprets nothing.
  private func drainSharedURLs() {
    let urls = takePendingSharedURLs()
    guard !urls.isEmpty else { return }
    if initialUrlPulled {
      for url in urls {
        channel?.invokeMethod("urlShared", arguments: url)
      }
    } else {
      pendingInitialUrls.append(contentsOf: urls)
    }
  }

  /// Cold-start pull. Drains anything still in the container first (covers a
  /// pull that races ahead of `sceneDidBecomeActive`), returns the first
  /// buffered URL, and flushes any extras onto the warm stream now that the UI
  /// is ready. Marks the pull done so later drains use the stream.
  private func takeInitialSharedURL() -> String? {
    pendingInitialUrls.append(contentsOf: takePendingSharedURLs())
    initialUrlPulled = true
    guard !pendingInitialUrls.isEmpty else { return nil }
    let first = pendingInitialUrls.removeFirst()
    let extras = pendingInitialUrls
    pendingInitialUrls.removeAll()
    for url in extras {
      channel?.invokeMethod("urlShared", arguments: url)
    }
    return first
  }

  /// Atomically takes every pending shared URL from the App Group (new FIFO
  /// queue + legacy single key) and clears the container, so each payload is
  /// delivered exactly once even if both the wake and the foreground drain fire.
  /// Malformed (non-string / blank) entries are dropped — fail closed, never
  /// crash — because the App Group is written by a separate process and must be
  /// treated as untrusted before it reaches Dart's validation gate.
  private func takePendingSharedURLs() -> [String] {
    guard let defaults = UserDefaults(suiteName: Self.appGroupId) else { return [] }
    let rawQueue = defaults.array(forKey: Self.sharedQueueKey)
    let rawLegacy = defaults.object(forKey: Self.legacySharedUrlKey)
    // Take-and-clear first: a concurrent wake + foreground drain can then never
    // observe the same payload twice.
    defaults.removeObject(forKey: Self.sharedQueueKey)
    defaults.removeObject(forKey: Self.legacySharedUrlKey)

    var urls: [String] = []
    if let rawQueue {
      for entry in rawQueue {
        if let normalized = Self.normalizedURLString(entry) {
          urls.append(normalized)
        }
      }
    }
    if let normalized = Self.normalizedURLString(rawLegacy) {
      urls.append(normalized)
    }
    return urls
  }

  /// Coerces an App Group entry to a trimmed, non-empty string, or `nil` to drop
  /// it. The authoritative trust boundary stays in Dart; this only ensures we
  /// never enqueue junk (a non-string, or blank) that could crash the channel.
  private static func normalizedURLString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  // MARK: - File helpers (issue #298)

  @available(iOS 13.0, *)
  private func localCopyPath(forContexts contexts: Set<UIOpenURLContext>) -> String? {
    for context in contexts {
      if let path = localCopyPath(for: context.url) {
        return path
      }
    }
    return nil
  }

  /// Copies a file URL into a private temp directory and returns the copy's
  /// path. Returns `nil` for non-file URLs or on any I/O error (intake then
  /// simply does nothing — the native side never crashes the app).
  private func localCopyPath(for url: URL) -> String? {
    guard url.isFileURL else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory
      .appendingPathComponent("incoming_share", isDirectory: true)
    do {
      try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
      let dest = tempDir.appendingPathComponent(
        UUID().uuidString + "-" + url.lastPathComponent)
      if fileManager.fileExists(atPath: dest.path) {
        try fileManager.removeItem(at: dest)
      }
      try fileManager.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      return nil
    }
  }
}
