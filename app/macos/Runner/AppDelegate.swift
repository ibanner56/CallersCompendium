import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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
}
