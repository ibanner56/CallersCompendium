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

  /// Set when a launch (cold-start) file was refused as over the size cap. The
  /// `getInitialFile` pull reports it only when no staged path is pending, so a
  /// rejection never displaces a file that was staged successfully.
  private var pendingInitialTooLarge = false

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
      let tooLarge = self?.pendingInitialTooLarge ?? false
      self?.pendingInitialPath = nil
      self?.pendingInitialTooLarge = false
      self?.initialFilePulled = true
      if let path = path, let owner = self {
        result(owner.filePayload(path))
      } else if tooLarge, let owner = self {
        result(owner.tooLargePayload())
      } else {
        result(nil)
      }
    }
    self.channel = channel
  }

  /// Handles one or more opened file URLs. Returns `true` if it took an
  /// importable file (or reported one refused as too large).
  @discardableResult
  func handleOpenedURLs(_ urls: [URL]) -> Bool {
    switch stagedCopy(for: urls) {
    case .copied(let path):
      if initialFilePulled {
        channel?.invokeMethod("fileOpened", arguments: filePayload(path))
      } else {
        if let previous = pendingInitialPath {
          deleteStagedCopy(at: previous)
        }
        pendingInitialPath = path
        pendingInitialTooLarge = false
      }
      return true
    case .tooLarge:
      if initialFilePulled {
        channel?.invokeMethod("fileOpened", arguments: tooLargePayload())
      } else {
        pendingInitialTooLarge = true
      }
      return true
    case .failed:
      return false
    }
  }

  private func stagedCopy(for urls: [URL]) -> IncomingFileStager.Outcome {
    var sawTooLarge = false
    for url in urls {
      switch localCopy(for: url) {
      case .copied(let path):
        return .copied(path)
      case .tooLarge:
        sawTooLarge = true
      case .failed:
        break
      }
    }
    return sawTooLarge ? .tooLarge : .failed
  }

  private func filePayload(_ path: String) -> [String: Any] {
    ["path": path, "appOwned": true]
  }

  /// Payload telling Dart the file was refused for exceeding the size cap; there
  /// is no staged copy, so nothing for Dart to read or delete.
  private func tooLargePayload() -> [String: Any] {
    ["rejected": "tooLarge"]
  }

  private func deleteStagedCopy(at path: String) {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return }
    try? fileManager.removeItem(atPath: path)
  }

  /// Stages a file URL into a private temp directory (see `IncomingFileStager`).
  private func localCopy(for url: URL) -> IncomingFileStager.Outcome {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("incoming_share", isDirectory: true)
    return IncomingFileStager.stage(url, into: tempDir)
  }
}

/// Stages an incoming file into a private temp directory, refusing anything over
/// `maxBytes`. Incoming size limits used to be enforced only in Dart, after the
/// whole payload had already been copied. The source's size attribute is checked
/// first as a cheap early refusal, then the copy itself is chunked and counted, so
/// it stops once `maxBytes` is crossed even if the attribute is missing or the
/// source grows mid-copy. An oversize or failed copy is deleted.
///
/// `internal` (not `private`) so the `RunnerTests` target can exercise it via
/// `@testable import Caller_s_Compendium`.
enum IncomingFileStager {
  /// Must equal `kMaxIncomingArchiveBytes` in
  /// `lib/src/data/archive_intake_service.dart` (25 MiB); a Dart test
  /// (`incoming_native_limits_test.dart`) fails if they drift.
  static let maxBytes: Int64 = 26_214_400

  enum Outcome: Equatable {
    case copied(String)
    case tooLarge
    case failed
  }

  static func stage(
    _ url: URL,
    into directory: URL,
    maxBytes: Int64 = IncomingFileStager.maxBytes
  ) -> Outcome {
    guard url.isFileURL else { return .failed }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let fileManager = FileManager.default
    var destination: URL?
    do {
      if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        Int64(size) > maxBytes
      {
        return .tooLarge
      }
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let dest = directory.appendingPathComponent(
        UUID().uuidString + "-" + url.lastPathComponent)
      destination = dest
      if fileManager.fileExists(atPath: dest.path) {
        try fileManager.removeItem(at: dest)
      }
      guard try copyBounded(from: url, to: dest, maxBytes: maxBytes) else {
        try? fileManager.removeItem(at: dest)
        return .tooLarge
      }
      return .copied(dest.path)
    } catch {
      if let destination = destination {
        try? fileManager.removeItem(at: destination)
      }
      return .failed
    }
  }

  /// Copies `source` to `destination` in fixed-size chunks, stopping as soon as
  /// more than `maxBytes` have been read. Returns false (leaving a partial
  /// destination for the caller to delete) when the limit is crossed. This bounds
  /// the work even when the size attribute is missing or the source grows mid-copy.
  private static func copyBounded(
    from source: URL, to destination: URL, maxBytes: Int64
  ) throws -> Bool {
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    let chunkSize = 64 * 1024
    var total: Int64 = 0
    while true {
      let done: Bool = try autoreleasepool {
        guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
          return true
        }
        total += Int64(chunk.count)
        if total > maxBytes { return true }
        try output.write(contentsOf: chunk)
        return false
      }
      if done { break }
    }
    return total <= maxBytes
  }
}
