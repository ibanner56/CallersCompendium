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
/// so the path Dart receives is always readable; the shared URL is delivered by
/// the Share Extension through the shared App Group, then this app is woken via
/// its private custom URL scheme (not a universal link).
///
/// Registered manually from `AppDelegate.didInitializeImplicitFlutterEngine`.
/// It receives scene life-cycle events via `registrar.addSceneDelegate`, so the
/// stock `FlutterSceneDelegate` is left untouched.
public class IncomingFilesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?

  /// App Group shared with the Share Extension; the shared URL is handed over
  /// through its `UserDefaults` suite.
  private static let appGroupId = "group.org.callerscompendium.compendiumApp"

  /// Key under which the Share Extension writes the raw shared URL string.
  private static let sharedUrlKey = "SharedImportURL"

  /// Private custom scheme the Share Extension uses to wake this app.
  private static let hostScheme = "callerscompendium"

  /// Path captured from a launch (cold-start) file URL, consumed exactly once
  /// by the `getInitialFile` pull once the Dart UI is ready.
  private var pendingInitialPath: String?

  /// URL string captured from a launch (cold-start) share, consumed exactly
  /// once by the `getInitialUrl` pull.
  private var pendingInitialUrl: String?

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
      let url = pendingInitialUrl
      pendingInitialUrl = nil
      result(url)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterSceneLifeCycleDelegate

  /// Cold start: the app was launched to open a file or import a shared URL.
  /// Stash the first importable payload for the matching pull — the Dart UI
  /// opens first, then imports over the app shell.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else {
      return false
    }
    if let url = sharedImportURL(forContexts: contexts) {
      pendingInitialUrl = url
      return true
    }
    guard let path = localCopyPath(forContexts: contexts) else { return false }
    pendingInitialPath = path
    return true
  }

  /// Warm start: a file or shared URL arrives while the app is already running.
  /// Push it onto the matching Dart stream.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool {
    if let url = sharedImportURL(forContexts: URLContexts) {
      channel?.invokeMethod("urlShared", arguments: url)
      return true
    }
    guard let path = localCopyPath(forContexts: URLContexts) else { return false }
    channel?.invokeMethod("fileOpened", arguments: path)
    return true
  }

  // MARK: - Helpers

  /// If any context is our private custom-scheme wake-up (issue #343), reads and
  /// clears the URL the Share Extension stashed in the App Group and returns it.
  /// The string is forwarded verbatim; Dart validates it.
  @available(iOS 13.0, *)
  private func sharedImportURL(forContexts contexts: Set<UIOpenURLContext>) -> String? {
    let woken = contexts.contains { $0.url.scheme == Self.hostScheme }
    guard woken, let defaults = UserDefaults(suiteName: Self.appGroupId) else {
      return nil
    }
    guard let shared = defaults.string(forKey: Self.sharedUrlKey),
      !shared.isEmpty
    else {
      return nil
    }
    defaults.removeObject(forKey: Self.sharedUrlKey)
    return shared
  }

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
