import Flutter
import UIKit

/// Bridges the OS "open this file with the app" plumbing (AirDrop / "Open
/// with…" / a share intent — issue #298) **and** a URL shared from the browser
/// share sheet (issue #343) to Dart over the
/// `is.banner.callerscompendium/incoming_files` channel.
///
/// The native side does exactly one thing per payload: hand Dart either an
/// ownership-marked payload containing the **path** of a local copy of an
/// incoming file (#298), or the **raw URL string** shared into the app (#343).
/// It never parses, trusts, or interprets a payload — Dart owns every byte of
/// validation and import (`ArchiveIntake` for files, and Dart's supported
/// program/dance URL classifiers for URLs; both are untrusted input). Incoming
/// files are copied into the app's temporary directory first, so the path Dart
/// receives is always readable.
///
/// Shared URLs are delivered out-of-band: the Share Extension writes them into
/// the shared App Group, then the user dismisses the extension and opens this
/// app. The App Group is the source of truth, so this plugin **drains it on
/// every activation** (`sceneDidBecomeActive`); a payload shared while the app
/// was suspended or closed is recovered on the next activation. The drain is an
/// atomic take-and-clear, so repeated foreground activations never double-import
/// the same payload.
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
  /// drained so a payload orphaned by an old queue implementation is recovered
  /// on the next launch.
  private static let legacySharedUrlKey = "SharedImportURL"

  /// Custom scheme retained to drain payloads from legacy Share Extension
  /// releases that tried to wake the host app.
  private static let legacyHostScheme = "callerscompendium"

  /// Path captured from a launch (cold-start) file URL, consumed exactly once
  /// by the `getInitialFile` pull once the Dart UI is ready.
  private var pendingInitialPath: String?

  /// Set when a launch (cold-start) file was refused as over the size cap. The
  /// `getInitialFile` pull reports it only when no staged path is pending, so a
  /// rejection never displaces a file that was staged successfully.
  private var pendingInitialTooLarge = false

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
      let tooLarge = pendingInitialTooLarge
      pendingInitialPath = nil
      pendingInitialTooLarge = false
      if let path = path {
        result(filePayload(path))
      } else if tooLarge {
        result(tooLargePayload())
      } else {
        result(nil)
      }
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
  /// recovers a link queued before the host was launched.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else {
      return false
    }
    switch stagedCopy(forContexts: contexts) {
    case .copied(let path):
      if let previous = pendingInitialPath {
        deleteStagedCopy(at: previous)
      }
      pendingInitialPath = path
      pendingInitialTooLarge = false
      return true
    case .tooLarge:
      pendingInitialTooLarge = true
      return true
    case .failed:
      return false
    }
  }

  /// Warm start: a file or a legacy Share Extension custom-scheme wake arrives
  /// while the app is already running. A legacy wake drains the App Group
  /// immediately; `sceneDidBecomeActive` remains the authoritative foreground
  /// drain, and the take-and-clear makes that double-fire idempotent.
  @available(iOS 13.0, *)
  @objc public func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool {
    if URLContexts.contains(where: { $0.url.scheme == Self.legacyHostScheme }) {
      drainSharedURLs()
      return true
    }
    switch stagedCopy(forContexts: URLContexts) {
    case .copied(let path):
      channel?.invokeMethod("fileOpened", arguments: filePayload(path))
      return true
    case .tooLarge:
      channel?.invokeMethod("fileOpened", arguments: tooLargePayload())
      return true
    case .failed:
      return false
    }
  }

  /// Authoritative foreground drain (issue #428): fires on every activation, so
  /// any payload left in the App Group — including one shared while the app was
  /// suspended or closed — is always recovered.
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
  /// delivered exactly once even if both a legacy wake and the foreground drain
  /// fire.
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
      if let normalized = SharedImportQueue.normalizedURLString(rawLegacy as? String),
        normalized.utf8.count <= SharedImportQueue.maxPayloadBytes
      {
        urls.append(normalized)
      }
    }
    return urls
  }

  // MARK: - File helpers (issue #298)

  @available(iOS 13.0, *)
  private func stagedCopy(
    forContexts contexts: Set<UIOpenURLContext>
  ) -> IncomingFileStager.Outcome {
    var sawTooLarge = false
    for context in contexts {
      switch localCopy(for: context.url) {
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
  /// `.failed` on non-file URLs or any I/O error (intake then simply does
  /// nothing — the native side never crashes the app).
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
/// `@testable import Runner`.
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

  /// Upper bound on one queued payload, in UTF-8 bytes (see the Share
  /// Extension's `maxPayloadBytes`, which enforces it at write time; this
  /// enforces it again at read time because the queue is written by another
  /// process). Must match it; a Dart test (`incoming_native_limits_test.dart`)
  /// fails if they drift.
  static let maxPayloadBytes = 32_768

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
    guard let data = payload.data(using: .utf8), data.count <= maxPayloadBytes
    else { return false }
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
        includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    let payloads =
      entries
      .filter { $0.pathExtension == payloadExtension }
      .sorted { creationDate(of: $0) < creationDate(of: $1) }
    var urls: [String] = []
    for file in payloads {
      // The queue is written by another process, so bound the read itself: an
      // oversize (or unsized) file is deleted unread rather than loaded whole.
      let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
      let contents: String? =
        (size.map { $0 <= maxPayloadBytes } ?? false)
        ? (try? String(contentsOf: file, encoding: .utf8)) : nil
      // Delete before yielding so a re-entrant drain (legacy wake + foreground)
      // can't take the same file twice; whichever drain removed it owns delivery.
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