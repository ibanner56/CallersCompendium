import Flutter
import UIKit

/// Bridges the OS "open this file with the app" plumbing (AirDrop / "Open
/// with…" / a share intent) to Dart over the
/// `is.banner.callerscompendium/incoming_files` channel — issue #298, receive
/// side.
///
/// The native side does exactly one thing: hand Dart the **path** of a local
/// copy of the incoming file. It never parses, trusts, or interprets the
/// contents — Dart's `ArchiveIntakeService` owns every byte of validation and
/// import (the file is untrusted input). Incoming files are copied into the
/// app's temporary directory first, so the path Dart receives is always
/// readable regardless of security-scoping / open-in-place semantics, and no
/// file is left behind in the app's shared Inbox.
///
/// Registered manually from `AppDelegate.didInitializeImplicitFlutterEngine`.
/// It receives scene life-cycle events via `registrar.addSceneDelegate`, so the
/// stock `FlutterSceneDelegate` is left untouched.
public class IncomingFilesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?

  /// Path captured from a launch (cold-start) URL, consumed exactly once by the
  /// `getInitialFile` pull once the Dart UI is ready.
  private var pendingInitialPath: String?

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
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterSceneLifeCycleDelegate

  /// Cold start: the app was launched to open a file. Stash the first
  /// importable path for the `getInitialFile` pull — the Dart UI opens first,
  /// then imports over the app shell.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    willConnectToSession session: UISceneSession,
    options connectionOptions: UISceneConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else {
      return false
    }
    guard let path = localCopyPath(forContexts: contexts) else { return false }
    pendingInitialPath = path
    return true
  }

  /// Warm start: a file arrives while the app is already running. Push it onto
  /// the Dart `files` stream.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool {
    guard let path = localCopyPath(forContexts: URLContexts) else { return false }
    channel?.invokeMethod("fileOpened", arguments: path)
    return true
  }

  // MARK: - Helpers

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
