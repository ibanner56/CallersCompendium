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
/// for files, and Dart's supported program/dance URL classifiers for URLs; both
/// are untrusted input). Incoming files are copied into the app's temporary
/// directory first, so the path Dart receives is always readable.
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
  /// through the `SharedImportQueue` directory in its container.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

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

  /// Takes every pending shared URL and clears the container, so each payload is
  /// delivered exactly once even if both the wake and the foreground drain fire.
  ///
  /// The primary queue is a directory of per-payload files (`SharedImportQueue`):
  /// draining enumerates a snapshot and deletes each file as it's read, so a
  /// payload the extension appends mid-drain — its own atomically-renamed file —
  /// is either already visible (and taken now) or not yet visible (and taken on
  /// the next foreground). It can never be partially read or silently deleted
  /// (PR #484 review). Malformed / blank entries are dropped — fail closed, never
  /// crash — because a separate process writes them and they must be treated as
  /// untrusted before reaching Dart's validation gate.
  private func takePendingSharedURLs() -> [String] {
    var urls: [String] = []
    if let directory = SharedImportQueue.directory(forAppGroup: Self.appGroupId) {
      urls.append(contentsOf: SharedImportQueue.drain(from: directory))
    }
    // Legacy single-value slot written by pre-#428 builds: take-and-clear it too
    // so an old orphaned payload is recovered on the next launch.
    if let defaults = UserDefaults(suiteName: Self.appGroupId) {
      let rawLegacy = defaults.object(forKey: Self.legacySharedUrlKey)
      defaults.removeObject(forKey: Self.legacySharedUrlKey)
      if let normalized = SharedImportQueue.normalizedURLString(rawLegacy as? String) {
        urls.append(normalized)
      }
    }
    return urls
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

/// Cross-process-safe queue of shared-URL payloads backed by a directory in the
/// App Group container (issue #428, PR #484 review). Each payload is its own
/// uniquely-named `.ccurl` file. The Share Extension publishes a file with an
/// atomic write (temp + rename), so the host — a separate process draining
/// concurrently — only ever sees a fully-written file under its final name.
/// Draining enumerates the directory and deletes each file as it reads it, so a
/// payload appended after enumeration is simply picked up by the next drain:
/// nothing is ever partially read or lost, and take-and-delete keeps it
/// idempotent when a wake and a foreground drain race for the same payload.
///
/// `internal` (not `private`) so the `RunnerTests` target can exercise the
/// concurrent-append-during-drain behaviour via `@testable import Runner`.
enum SharedImportQueue {
  /// Directory name inside the App Group container. Must match the Share
  /// Extension's `queueDirectoryName`.
  static let directoryName = "SharedImportQueue"

  /// Extension marking a complete payload file; other entries (e.g. a transient
  /// atomic-write temp file) are ignored.
  static let payloadExtension = "ccurl"

  /// Queue directory inside the given App Group container, or `nil` when the
  /// container is unavailable.
  static func directory(forAppGroup appGroupId: String) -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  /// Publishes one payload as its own uniquely-named file, made visible via an
  /// atomic rename. Mirrors the Share Extension's writer (the two targets don't
  /// share a module, so the extension keeps its own copy). Returns `false` on
  /// I/O failure. Primarily used by tests here.
  @discardableResult
  static func enqueue(_ payload: String, into directory: URL) -> Bool {
    guard let data = payload.data(using: .utf8) else { return false }
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(
        "\(UUID().uuidString).\(payloadExtension)")
      try data.write(to: destination, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  /// Takes and deletes every complete payload currently visible, oldest first.
  /// A file that appears after enumeration is left for the next drain. Malformed
  /// / blank payloads are dropped (fail closed).
  static func drain(from directory: URL) -> [String] {
    let fileManager = FileManager.default
    guard
      let entries = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    let payloads =
      entries
      .filter { $0.pathExtension == payloadExtension }
      .sorted { creationDate(of: $0) < creationDate(of: $1) }
    var urls: [String] = []
    for file in payloads {
      let contents = try? String(contentsOf: file, encoding: .utf8)
      // Delete before yielding so a re-entrant drain (wake + foreground) can't
      // take the same file twice; whichever drain removed it owns delivery.
      try? fileManager.removeItem(at: file)
      if let normalized = normalizedURLString(contents) {
        urls.append(normalized)
      }
    }
    return urls
  }

  /// Coerces a payload to a trimmed, non-empty string, or `nil` to drop it. The
  /// authoritative trust boundary stays in Dart; this only stops junk (nil or
  /// blank) from reaching the channel.
  static func normalizedURLString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func creationDate(of url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
      ?? .distantPast
  }
}