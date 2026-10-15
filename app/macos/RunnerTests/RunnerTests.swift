import Cocoa
import FlutterMacOS
import XCTest

@testable import Caller_s_Compendium

class RunnerTests: XCTestCase {

  func testTerminationWaitsForDartShutdownBeforeReplying() {
    var completion: ((Result<Void, Error>) -> Void)?
    var replies: [NSApplication.TerminateReply] = []
    let coordinator = ApplicationTerminationCoordinator {
      completion = $0
    }

    XCTAssertEqual(
      coordinator.requestTermination { replies.append($0) },
      .terminateLater
    )
    XCTAssertNotNil(completion)
    XCTAssertTrue(replies.isEmpty)

    completion?(.success(()))

    XCTAssertEqual(replies, [.terminateNow])
  }

  func testRepeatedTerminationWaitsForTheOriginalDartShutdown() {
    var requestCount = 0
    var completion: ((Result<Void, Error>) -> Void)?
    let coordinator = ApplicationTerminationCoordinator {
      requestCount += 1
      completion = $0
    }

    XCTAssertEqual(coordinator.requestTermination { _ in }, .terminateLater)
    XCTAssertEqual(coordinator.requestTermination { _ in }, .terminateLater)
    XCTAssertEqual(requestCount, 1)

    completion?(.success(()))

    XCTAssertEqual(coordinator.requestTermination { _ in }, .terminateNow)
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

/// Issue #1725: the not-installed notice keys off a read-only volume.
final class InstallLocationTests: XCTestCase {
  /// The answer for an installed app. `/Applications` is a firmlink into the
  /// writable data volume; if it ever read as read-only, every installed user
  /// would see a false notice.
  func testApplicationsFolderIsNotFlagged() {
    XCTAssertFalse(
      InstallLocation.isUninstalled(
        bundleURL: URL(fileURLWithPath: "/Applications", isDirectory: true)))
  }

  func testWritableTemporaryDirectoryIsNotFlagged() {
    XCTAssertFalse(
      InstallLocation.isUninstalled(bundleURL: FileManager.default.temporaryDirectory))
  }

  /// The signed system volume is read-only, standing in for a mounted `.dmg`
  /// (which a unit test cannot mount). On failure the message reports what
  /// the mount itself says, so a runner whose system volume is not mounted
  /// read-only is told apart from a broken check.
  func testReadOnlySystemVolumeIsFlagged() {
    let url = URL(
      fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
    XCTAssertTrue(InstallLocation.isUninstalled(bundleURL: url), Self.mountReport(url))
  }

  private static func mountReport(_ url: URL) -> String {
    var info = statfs()
    let rc = statfs(url.path, &info)
    let errorCode = rc == 0 ? 0 : errno
    func text<T>(_ field: inout T) -> String {
      withUnsafePointer(to: &field) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
          String(cString: $0)
        }
      }
    }
    let readOnlyKey = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
    return "statfs rc=\(rc) errno=\(errorCode) on=\(text(&info.f_mntonname)) "
      + "from=\(text(&info.f_mntfromname)) flags=0x\(String(info.f_flags, radix: 16)) "
      + "volumeIsReadOnly=\(String(describing: readOnlyKey))"
  }

  /// An unreadable location reports "not detected" rather than a false notice.
  func testMissingPathIsNotFlagged() {
    XCTAssertFalse(
      InstallLocation.isUninstalled(
        bundleURL: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/App.app")))
  }
}
