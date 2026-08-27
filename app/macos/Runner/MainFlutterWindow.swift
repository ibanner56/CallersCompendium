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

    super.awakeFromNib()
  }
}
