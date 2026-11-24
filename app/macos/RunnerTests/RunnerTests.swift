import Cocoa
import FlutterMacOS
import CoreText
import ImageIO
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

/// FAIL-16: the free-space answer behind the in-place backup write's check.
final class BackupVolumeTests: XCTestCase {
  func testExistingFileReportsFreeSpace() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("backup-volume-\(UUID().uuidString).json")
    try Data("{}".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = try XCTUnwrap(BackupVolume.availableBytes(path: url.path))
    XCTAssertGreaterThan(bytes, 0)
  }

  /// A path statfs cannot read answers "unknown", which lets the save go ahead.
  func testMissingPathIsUnknown() {
    XCTAssertNil(BackupVolume.availableBytes(path: "/nonexistent-\(UUID().uuidString)/b.json"))
  }
}

/// Apple Vision text recognition behind **From an image…** (#2327). The
/// "typed card" is drawn here with Core Text, so the test needs no image
/// resource in the bundle.
final class TextRecognizerTests: XCTestCase {
  /// A PNG of `lines` in black on white, drawn at `fontSize`.
  private func card(_ lines: [String], width: Int = 1200, fontSize: CGFloat = 48) -> Data {
    let lineHeight = Int(fontSize * 1.6)
    let height = lineHeight * (lines.count + 1)
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    for (index, text) in lines.enumerated() {
      let attributed = NSAttributedString(
        string: text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])
      let line = CTLineCreateWithAttributedString(attributed)
      context.textPosition = CGPoint(x: 40, y: height - lineHeight * (index + 1))
      CTLineDraw(line, context)
    }
    return png(context.makeImage()!)
  }

  private func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      data as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  func testATypedCardReadsAsItsLinesInOrder() throws {
    let data = card(["A1 (8) Neighbor balance and swing", "A2 (8) Long lines"])
    let text = try TextRecognizer.recognize(data: data, languages: ["en"])
    let lines = text.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, 2, text)
    XCTAssertTrue(lines[0].contains("Neighbor balance"), text)
    XCTAssertTrue(lines[1].contains("Long lines"), text)
  }

  func testAPictureStoredSidewaysIsReadUpright() throws {
    // Orientation 6: the stored pixels must turn 90° clockwise to display, so
    // the upright card is drawn turned 90° counter-clockwise.
    let upright = CGImageSourceCreateImageAtIndex(
      CGImageSourceCreateWithData(
        card(["A1 (8) Neighbor balance and swing", "A2 (8) Long lines"]) as CFData, nil)!,
      0, nil)!
    let context = CGContext(
      data: nil, width: upright.height, height: upright.width, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: CGFloat(upright.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(upright, in: CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      data as CFMutableData, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(
      destination, context.makeImage()!,
      [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))

    let text = try TextRecognizer.recognize(data: data as Data, languages: ["en"])
    let lines = text.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, 2, text)
    XCTAssertTrue(lines[0].contains("Neighbor balance"), text)
    XCTAssertTrue(lines[1].contains("Long lines"), text)
  }

  func testAPictureOverThePixelCapIsRefusedBeforeReading() {
    let context = CGContext(
      data: nil, width: TextRecognizer.maxSide + 1, height: 1, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let data = png(context.makeImage()!)
    XCTAssertThrowsError(try TextRecognizer.recognize(data: data, languages: ["en"])) {
      XCTAssertEqual($0 as? TextRecognitionError, .tooManyPixels)
    }
  }

  func testBytesThatAreNotAPictureAreUnreadable() {
    XCTAssertThrowsError(
      try TextRecognizer.recognize(data: Data([1, 2, 3, 4]), languages: ["en"])
    ) {
      XCTAssertEqual($0 as? TextRecognitionError, .unreadable)
    }
  }

  func testEnglishIsAvailableAndLanguageCodesMatchTags() {
    XCTAssertEqual(TextRecognizer.availableLanguages(["en"]), ["en"])
    let supported = ["en-US", "fr-FR", "zh-Hans"]
    XCTAssertEqual(
      TextRecognizer.availableLanguages(["ja", "fr", "en"], supported: supported), ["fr", "en"])
    XCTAssertEqual(TextRecognizer.tags(for: "zh", in: supported), ["zh-Hans"])
    XCTAssertEqual(TextRecognizer.tags(for: "e", in: supported), [])
  }

  func testPiecesAreOrderedTopToBottomThenLeftToRight() {
    let text = TextRecognizer.lines(of: [
      ("second", CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1)),
      ("right", CGRect(x: 0.5, y: 0.71, width: 0.3, height: 0.1)),
      ("left", CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1)),
    ])
    XCTAssertEqual(text, "left right\nsecond")
  }
}
