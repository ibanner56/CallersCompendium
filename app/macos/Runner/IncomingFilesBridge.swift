import FlutterMacOS
import Foundation

/// Bridges macOS "Open With…" / share file-open events to Dart over the
/// `is.banner.callerscompendium/incoming_files` channel — issue #298, receive
/// side.
///
/// The native side only ever hands Dart an ownership-marked payload containing
/// the **path** of a private temp copy of the incoming file; Dart's
/// `ArchiveIntakeService` owns every byte of validation and import (the file is
/// untrusted input). Copying into the app's temporary directory (under
/// security-scoped access) means the path is always readable and nothing is
/// left behind where the file was dropped.
final class IncomingFilesBridge {
  static let shared = IncomingFilesBridge()
  private init() {}

  private var channel: FlutterMethodChannel?

  /// Path captured from a launch (cold-start) file open, consumed once by the
  /// `getInitialFile` pull.
  private var pendingInitialPath: String?

  /// Set once Dart pulls the cold-start file. Before this, a file open is
  /// treated as the launch file (retained for the pull); after it, a file open
  /// is a warm event pushed on the `files` stream. This guarantees exactly one
  /// import per opened file — never a cold/warm double.
  private var initialFilePulled = false

  /// Wires the channel to the engine messenger once the Flutter view controller
  /// exists. Any path captured earlier is retained for the cold-start pull.
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/incoming_files",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let path = self?.pendingInitialPath
      self?.pendingInitialPath = nil
      self?.initialFilePulled = true
      if let path = path, let owner = self {
        result(owner.filePayload(path))
      } else {
        result(nil)
      }
    }
    self.channel = channel
  }

  /// Handles one or more opened file URLs. Returns `true` if it took an
  /// importable file.
  @discardableResult
  func handleOpenedURLs(_ urls: [URL]) -> Bool {
    guard let path = firstLocalCopyPath(for: urls) else { return false }
    if initialFilePulled {
      channel?.invokeMethod("fileOpened", arguments: filePayload(path))
    } else {
      if let previous = pendingInitialPath {
        deleteStagedCopy(at: previous)
      }
      pendingInitialPath = path
    }
    return true
  }

  private func firstLocalCopyPath(for urls: [URL]) -> String? {
    for url in urls {
      if let path = localCopyPath(for: url) {
        return path
      }
    }
    return nil
  }

  private func filePayload(_ path: String) -> [String: Any] {
    ["path": path, "appOwned": true]
  }

  private func deleteStagedCopy(at path: String) {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return }
    try? fileManager.removeItem(atPath: path)
  }

  private func localCopyPath(for url: URL) -> String? {
    guard url.isFileURL else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory
      .appendingPathComponent("incoming_share", isDirectory: true)
    var destination: URL?
    do {
      try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
      let dest = tempDir.appendingPathComponent(
        UUID().uuidString + "-" + url.lastPathComponent)
      destination = dest
      if fileManager.fileExists(atPath: dest.path) {
        try fileManager.removeItem(at: dest)
      }
      try fileManager.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      if let destination = destination {
        deleteStagedCopy(at: destination.path)
      }
      return nil
    }
  }
}
