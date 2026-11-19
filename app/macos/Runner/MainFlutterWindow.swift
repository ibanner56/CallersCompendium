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

    // Brand surface behind the first frame, so the window doesn't flash the
    // system grey before Flutter draws: light #F4F6FA / dark #121A24 (the
    // app's light and dark scheme surfaces). FlutterView's own layer defaults
    // to opaque black and takes a static colour, so it is set to clear to let
    // this appearance-aware window colour show through until the first frame.
    flutterViewController.backgroundColor = .clear
    self.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x12 / 255, green: 0x1A / 255, blue: 0x24 / 255, alpha: 1)
        : NSColor(srgbRed: 0xF4 / 255, green: 0xF6 / 255, blue: 0xFA / 255, alpha: 1)
    }

    super.awakeFromNib()
  }
}
