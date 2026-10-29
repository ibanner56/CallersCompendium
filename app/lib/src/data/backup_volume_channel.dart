import 'package:flutter/services.dart';

/// The mockable seam to the macOS free-space query a backup save makes before
/// it overwrites an existing backup in place (audit finding FAIL-16). Native
/// side: `app/macos/Runner/BackupVolumeBridge.swift`.
class BackupVolumeChannel {
  BackupVolumeChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Platform-channel name shared with the native handler.
  static const String channelName = 'is.banner.callerscompendium/backup_volume';

  final MethodChannel _channel;

  /// The bytes free to this app on the volume holding the existing file at
  /// [path], or `null` when that is unknown. Any channel error, or a platform
  /// with no native implementation, reads as `null`, and the save then goes
  /// ahead as it did before the check existed: an unknown answer must not
  /// block a backup.
  Future<int?> availableBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('availableBytes', path);
    } on MissingPluginException {
      // diagnostics: silent — no native implementation on this platform; the save proceeds unchecked
      return null;
    } on PlatformException {
      // diagnostics: silent — the native query failed; the save proceeds unchecked
      return null;
    }
  }
}
