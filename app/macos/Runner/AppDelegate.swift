import Cocoa
import FlutterMacOS

private let applicationTerminationChannelName =
  "is.banner.callerscompendium/application_lifecycle"
private let requestApplicationShutdownMethod = "requestApplicationShutdown"

private enum ApplicationTerminationError: Error {
  case flutterWindowUnavailable
  case dartShutdownRejected
}

/// Defers AppKit termination until Dart has closed Drift's database isolate.
final class ApplicationTerminationCoordinator {
  typealias RequestShutdown =
    (@escaping (Result<Void, Error>) -> Void) -> Void

  private enum State {
    case idle
    case waitingForDart
    case permittingTermination
  }

  private let requestShutdown: RequestShutdown
  private var state = State.idle

  init(requestShutdown: @escaping RequestShutdown) {
    self.requestShutdown = requestShutdown
  }

  func requestTermination(
    reply: @escaping (NSApplication.TerminateReply) -> Void
  ) -> NSApplication.TerminateReply {
    switch state {
    case .waitingForDart:
      return .terminateLater
    case .permittingTermination:
      return .terminateNow
    case .idle:
      state = .waitingForDart
      requestShutdown { [weak self] result in
        guard let self, case .waitingForDart = self.state else {
          return
        }

        switch result {
        case .success:
          self.state = .permittingTermination
          reply(.terminateNow)
        case .failure:
          self.state = .idle
          reply(.terminateCancel)
        }
      }
      return .terminateLater
    }
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private lazy var terminationCoordinator = ApplicationTerminationCoordinator {
    [weak self] completion in
    guard let self else {
      completion(.failure(ApplicationTerminationError.flutterWindowUnavailable))
      return
    }
    self.requestDartShutdown(completion: completion)
  }

  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    terminationCoordinator.requestTermination { reply in
      sender.reply(toApplicationShouldTerminate: reply == .terminateNow)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Receive-side share import (issue #298): the OS handed us one or more files
  /// to open (AirDrop / "Open With…" / a share). Forward them to the Dart
  /// intake, then let Flutter's own plugin forwarding run.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFilesBridge.shared.handleOpenedURLs(urls)
    super.application(application, open: urls)
  }

  private func requestDartShutdown(
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard
      let flutterViewController =
        (mainFlutterWindow as? MainFlutterWindow)?.flutterViewController
    else {
      NSLog(
        "Application termination cancelled because the Flutter window is unavailable."
      )
      completion(.failure(ApplicationTerminationError.flutterWindowUnavailable))
      return
    }

    let channel = FlutterMethodChannel(
      name: applicationTerminationChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.invokeMethod(requestApplicationShutdownMethod, arguments: nil) {
      result in
      if result == nil {
        completion(.success(()))
      } else {
        NSLog(
          "Application termination cancelled because Dart shutdown did not succeed."
        )
        completion(.failure(ApplicationTerminationError.dartShutdownRejected))
      }
    }
  }
}
