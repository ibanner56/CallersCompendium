import FlutterMacOS
import Foundation

/// Tells Dart how much space is free on the volume holding an existing backup,
/// so a save that would overwrite it in place can refuse first rather than
/// truncate it on a full disk (audit finding FAIL-16). The sandbox forces that
/// in-place write; see `writeDesktopBackup` in `backup_io.dart`.
///
/// The query runs off the main thread and answers `nil` on any error, which
/// Dart treats as "unknown" and lets the save go ahead unchecked.
final class BackupVolumeBridge {
  static let shared = BackupVolumeBridge()
  private init() {}

  private var channel: FlutterMethodChannel?

  /// Wires the channel to the engine messenger once the Flutter view controller
  /// exists.
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/backup_volume",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "availableBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let bytes = BackupVolume.availableBytes(path: path)
        DispatchQueue.main.async { result(bytes) }
      }
    }
    self.channel = channel
  }
}

/// `internal` (not `private`) so the `RunnerTests` target can exercise it via
/// `@testable import Caller_s_Compendium`.
enum BackupVolume {
  /// The bytes available to an unprivileged process on the filesystem holding
  /// `path` (`statfs`'s `f_bavail` blocks of `f_bsize` bytes), or `nil` when
  /// `statfs` fails, for example because nothing exists at `path`.
  ///
  /// Purgeable space macOS could reclaim on demand is not counted, so this can
  /// under-report; that only makes the Dart check refuse sooner.
  static func availableBytes(path: String) -> Int64? {
    var info = statfs()
    guard statfs(path, &info) == 0 else { return nil }
    let (bytes, overflow) = UInt64(info.f_bavail).multipliedReportingOverflow(
      by: UInt64(info.f_bsize))
    return overflow || bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
  }
}
