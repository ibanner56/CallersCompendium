import FlutterMacOS
import Foundation

/// Tells Dart whether the app is running from somewhere it was never installed
/// to — issue #1725, typically the app double-clicked inside the mounted `.dmg`
/// rather than dragged to Applications first. Dart shows a notice when it is.
///
/// The check runs off the main thread and answers `false` on any error, so it
/// can neither delay startup nor raise a false notice.
final class InstallLocationBridge {
  static let shared = InstallLocationBridge()
  private init() {}

  private var channel: FlutterMethodChannel?

  /// Wires the channel to the engine messenger once the Flutter view controller
  /// exists.
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/install_location",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "isRunningUninstalled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let bundleURL = Bundle.main.bundleURL
      DispatchQueue.global(qos: .utility).async {
        let uninstalled = InstallLocation.isUninstalled(bundleURL: bundleURL)
        DispatchQueue.main.async { result(uninstalled) }
      }
    }
    self.channel = channel
  }
}

/// `internal` (not `private`) so the `RunnerTests` target can exercise it via
/// `@testable import Caller_s_Compendium`.
enum InstallLocation {
  /// Whether the bundle at `bundleURL` sits on a read-only volume.
  ///
  /// That one property covers both ways an uninstalled app runs: from the
  /// mounted disk image itself (a read-only image), and from Gatekeeper's App
  /// Translocation copy (a randomised read-only mount). An installed copy in
  /// `/Applications` or `~/Applications` is on the writable data volume.
  ///
  /// Removable or ejectable volumes are deliberately **not** treated as a
  /// signal: an app kept on an external drive is installed, and flagging it
  /// would be a false notice. `SecTranslocateIsTranslocatedURL` is not called
  /// either: its header is not public, and the translocated mount is
  /// read-only anyway.
  static func isUninstalled(bundleURL: URL) -> Bool {
    guard
      let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
      let readOnly = values.volumeIsReadOnly
    else {
      return false
    }
    return readOnly
  }
}
