import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

/// Unit tests for the cross-process shared-URL queue behind the iOS "Share via
/// browser" import (issue #428, PR #484 review).
///
/// These drive `SharedImportQueue` against a throwaway temp directory rather
/// than the real App Group container (unavailable to unit tests), so they can
/// run under `xcodebuild test`. CI's `Build (ios)` job runs them on a simulator
/// when `tools/ci/classify_changes.py` sets `apple_native_changed` (a change
/// under `app/ios/` or `app/macos/`, or to `.fvmrc`, in a diff that is not
/// Markdown-only), and on every push to main that is not Markdown-only.
final class SharedImportQueueTests: XCTestCase {
  private var queueDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    queueDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SharedImportQueueTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: queueDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let queueDirectory {
      try? FileManager.default.removeItem(at: queueDirectory)
    }
    queueDirectory = nil
    try super.tearDownWithError()
  }

  /// Every enqueued payload is drained exactly once, and the queue is emptied.
  func testDrainDeliversEveryPayloadOnceThenEmpties() {
    let payloads = [
      "https://contradb.com/programs/1",
      "https://contradb.com/programs/2",
      "https://contradb.com/programs/3",
    ]
    for payload in payloads {
      XCTAssertTrue(SharedImportQueue.enqueue(payload, into: queueDirectory))
    }

    let drained = SharedImportQueue.drain(from: queueDirectory)

    XCTAssertEqual(Set(drained), Set(payloads))
    XCTAssertEqual(drained.count, payloads.count, "No payload should be duplicated")
    XCTAssertTrue(
      SharedImportQueue.drain(from: queueDirectory).isEmpty,
      "A second drain must find nothing — take-and-delete is idempotent")
  }

  /// A re-entrant drain (a legacy wake racing the foreground drain) can never
  /// take the same payload twice: whichever drain removed the file owns delivery.
  func testReentrantDrainNeverDoubleDelivers() {
    XCTAssertTrue(
      SharedImportQueue.enqueue("https://contradb.com/programs/42", into: queueDirectory))

    let first = SharedImportQueue.drain(from: queueDirectory)
    let second = SharedImportQueue.drain(from: queueDirectory)

    XCTAssertEqual(first, ["https://contradb.com/programs/42"])
    XCTAssertTrue(second.isEmpty)
  }

  /// A payload appended after a drain has taken its snapshot is a brand-new
  /// atomically-published file, so it is delivered whole by the *next* drain —
  /// never lost, never partially read, never duplicated. This is the exact
  /// concurrent-append-during-drain case raised in review.
  func testPayloadAppendedAfterSnapshotIsDeliveredByNextDrain() {
    XCTAssertTrue(SharedImportQueue.enqueue("https://contradb.com/programs/1", into: queueDirectory))
    XCTAssertTrue(SharedImportQueue.enqueue("https://contradb.com/programs/2", into: queueDirectory))

    // First foreground drain takes the {1, 2} snapshot and clears those files.
    let first = SharedImportQueue.drain(from: queueDirectory)
    XCTAssertEqual(
      Set(first),
      [
        "https://contradb.com/programs/1",
        "https://contradb.com/programs/2",
      ])

    // The extension appends a new share once draining has already begun.
    XCTAssertTrue(SharedImportQueue.enqueue("https://contradb.com/programs/3", into: queueDirectory))

    // The next drain delivers exactly the new payload: nothing from the first
    // batch reappears, and the new one is not lost.
    let second = SharedImportQueue.drain(from: queueDirectory)
    XCTAssertEqual(second, ["https://contradb.com/programs/3"])
    XCTAssertTrue(SharedImportQueue.drain(from: queueDirectory).isEmpty)
  }

  /// Concurrent enqueue (extension) and drain (host foreground) deliver each
  /// payload exactly once — no loss, no duplicates — even under heavy
  /// interleaving, because publishing is an atomic rename and draining is a
  /// per-file take-and-delete.
  func testConcurrentAppendDuringDrainDeliversEachPayloadExactlyOnce() {
    let total = 500
    let expected = (0..<total).map { "https://contradb.com/programs/\($0)" }
    let collected = SynchronizedStrings()
    let producerFinished = AtomicFlag()

    let producing = expectation(description: "producer finished")
    DispatchQueue.global(qos: .userInitiated).async {
      DispatchQueue.concurrentPerform(iterations: total) { index in
        _ = SharedImportQueue.enqueue(expected[index], into: self.queueDirectory)
      }
      producerFinished.set()
      producing.fulfill()
    }

    let draining = expectation(description: "drainer finished")
    DispatchQueue.global(qos: .userInitiated).async {
      // Drain repeatedly while the producer runs. Once the producer has
      // finished, every enqueue has returned (its file is renamed into place
      // and visible), so a final sweep that comes back empty means the queue is
      // fully drained.
      while true {
        collected.append(SharedImportQueue.drain(from: self.queueDirectory))
        if producerFinished.isSet {
          let sweep = SharedImportQueue.drain(from: self.queueDirectory)
          collected.append(sweep)
          if sweep.isEmpty { break }
        }
      }
      draining.fulfill()
    }

    wait(for: [producing, draining], timeout: 30)

    let values = collected.values
    XCTAssertEqual(values.count, total, "Every payload delivered exactly once (no loss/dup)")
    XCTAssertEqual(Set(values), Set(expected), "Exactly the expected payload set was delivered")
  }

  /// Malformed / blank payloads are dropped (fail closed) and non-payload files
  /// in the directory are ignored, so junk written by a separate process can
  /// never crash the drain or reach Dart.
  func testMalformedEntriesFailClosed() throws {
    XCTAssertTrue(SharedImportQueue.enqueue("https://contradb.com/programs/7", into: queueDirectory))
    // A blank payload file: must be dropped.
    XCTAssertTrue(SharedImportQueue.enqueue("   \n ", into: queueDirectory))
    // An unrelated file (wrong extension): must be ignored, not returned.
    try "ignore me".data(using: .utf8)!.write(
      to: queueDirectory.appendingPathComponent("note.txt"))

    let drained = SharedImportQueue.drain(from: queueDirectory)

    XCTAssertEqual(drained, ["https://contradb.com/programs/7"])
    // The `.ccurl` payloads were cleared; the unrelated file is left untouched.
    let remaining = try FileManager.default.contentsOfDirectory(
      at: queueDirectory, includingPropertiesForKeys: nil)
    XCTAssertEqual(remaining.map { $0.lastPathComponent }, ["note.txt"])
  }

  func testNormalizedURLStringTrimsAndDropsBlanks() {
    XCTAssertEqual(
      SharedImportQueue.normalizedURLString("  https://contradb.com/programs/9 \n"),
      "https://contradb.com/programs/9")
    XCTAssertNil(SharedImportQueue.normalizedURLString("   "))
    XCTAssertNil(SharedImportQueue.normalizedURLString(nil))
  }

  /// An oversize payload is deleted without being delivered, while a normal
  /// payload beside it still is (the size gate must not fail open or closed for
  /// the rest of the queue). The oversize payload is a valid URL padded past the
  /// cap, so an unbounded read would deliver it.
  func testDrainDeletesOversizePayloadUnreadAndStillDeliversOthers() throws {
    let oversize =
      "https://contradb.com/programs/5 "
      + String(repeating: "a", count: SharedImportQueue.maxPayloadBytes)
    let destination = queueDirectory.appendingPathComponent(
      "\(UUID().uuidString).\(SharedImportQueue.payloadExtension)")
    try oversize.data(using: .utf8)!.write(to: destination)
    XCTAssertTrue(SharedImportQueue.enqueue("https://contradb.com/programs/6", into: queueDirectory))

    let drained = SharedImportQueue.drain(from: queueDirectory)

    XCTAssertEqual(drained, ["https://contradb.com/programs/6"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  /// A payload of exactly the cap is delivered (the bound is inclusive).
  func testDrainDeliversPayloadAtTheCap() throws {
    let prefix = "https://contradb.com/programs/8 "
    let atCap = prefix + String(repeating: "a", count: SharedImportQueue.maxPayloadBytes - prefix.utf8.count)
    XCTAssertEqual(atCap.utf8.count, SharedImportQueue.maxPayloadBytes)
    XCTAssertTrue(SharedImportQueue.enqueue(atCap, into: queueDirectory))

    XCTAssertEqual(SharedImportQueue.drain(from: queueDirectory).count, 1)
  }

  /// The queue writer refuses an over-cap payload rather than persisting it.
  func testEnqueueRefusesOversizePayload() {
    let oversize = String(repeating: "a", count: SharedImportQueue.maxPayloadBytes + 1)

    XCTAssertFalse(SharedImportQueue.enqueue(oversize, into: queueDirectory))
    XCTAssertTrue(SharedImportQueue.drain(from: queueDirectory).isEmpty)
  }

  func testDrainOnMissingDirectoryReturnsEmpty() {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
    XCTAssertTrue(SharedImportQueue.drain(from: missing).isEmpty)
  }
}

/// Bounded staging of incoming files (`IncomingFileStager`): an over-cap file is
/// refused without leaving a staged copy behind, and an at-cap file still stages.
/// Runs against throwaway temp directories.
final class IncomingFileStagerTests: XCTestCase {
  private var workDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    workDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("IncomingFileStagerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: workDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let workDirectory {
      try? FileManager.default.removeItem(at: workDirectory)
    }
    workDirectory = nil
    try super.tearDownWithError()
  }

  private func makeSource(bytes: Int) throws -> URL {
    let url = workDirectory.appendingPathComponent("source-\(UUID().uuidString).json")
    try Data(repeating: 0x61, count: bytes).write(to: url)
    return url
  }

  private var stagingDirectory: URL {
    workDirectory.appendingPathComponent("staging", isDirectory: true)
  }

  private func stagedFiles() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: stagingDirectory, includingPropertiesForKeys: nil)) ?? []
  }

  func testFileAtTheCapIsStaged() throws {
    let source = try makeSource(bytes: 100)

    let outcome = IncomingFileStager.stage(source, into: stagingDirectory, maxBytes: 100)

    guard case .copied(let path) = outcome else {
      return XCTFail("expected .copied, got \(outcome)")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testFileOverTheCapIsRefusedAndNothingIsStaged() throws {
    let source = try makeSource(bytes: 101)

    let outcome = IncomingFileStager.stage(source, into: stagingDirectory, maxBytes: 100)

    XCTAssertEqual(outcome, .tooLarge)
    XCTAssertTrue(stagedFiles().isEmpty)
  }

  func testNonFileURLFails() {
    let outcome = IncomingFileStager.stage(
      URL(string: "https://example.com/a.json")!, into: stagingDirectory)

    XCTAssertEqual(outcome, .failed)
  }

  /// The cap in the stager is the same 25 MiB Dart enforces.
  func testDefaultCapIs25MiB() {
    XCTAssertEqual(IncomingFileStager.maxBytes, 25 * 1024 * 1024)
  }
}

// MARK: - Test helpers

/// Minimal lock-guarded string accumulator for the concurrency test.
private final class SynchronizedStrings {
  private let lock = NSLock()
  private var storage: [String] = []

  func append(_ items: [String]) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(contentsOf: items)
  }

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

/// Minimal lock-guarded one-way flag (false → true).
private final class AtomicFlag {
  private let lock = NSLock()
  private var flag = false

  func set() {
    lock.lock()
    defer { lock.unlock() }
    flag = true
  }

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return flag
  }
}
