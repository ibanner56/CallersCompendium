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

    // Issue #1725: lets Dart ask whether the app is running from a read-only
    // volume (the disk image or a translocated copy), usually because it was
    // never installed.
    InstallLocationBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    // FAIL-16: lets Dart check free space before a backup save overwrites an
    // existing backup in place.
    BackupVolumeBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
