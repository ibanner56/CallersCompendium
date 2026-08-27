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
