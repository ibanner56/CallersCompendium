import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var flutterViewController: FlutterViewController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.flutterViewController = flutterViewController
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Receive-side share import (issue #298): wire the incoming-file channel to
    // this engine's messenger so OS "Open With…" files reach the Dart intake.
    IncomingFilesBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    // Issue #1725: lets Dart ask whether the app is running from the disk
    // image (or a translocated copy) instead of an installed location.
    InstallLocationBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
