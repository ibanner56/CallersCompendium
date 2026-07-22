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
/// run under `xcodebuild test`. NOTE: CI's `Build (ios)` job only *builds* the
/// Runner app (`flutter build ios --no-codesign`); it does not compile or run
/// `RunnerTests`. These are validated locally via Xcode / `xcodebuild test`.
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

  /// A re-entrant drain (an immediate wake racing the foreground drain) can
  /// never take the same payload twice: whichever drain removed the file owns
  /// delivery.
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

  func testDrainOnMissingDirectoryReturnsEmpty() {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
    XCTAssertTrue(SharedImportQueue.drain(from: missing).isEmpty)
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
