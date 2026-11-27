import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../data/settings_keys.dart'
    show kNoBackupMarkerWrittenKey, kSyncDeviceIdKey, kSyncEnabledKey;

/// A file this installation keeps where device backup never copies it, so a
/// library restored from a device backup arrives without it (spec §3.3,
/// *A library restored from a device backup*).
///
/// Android keeps it in `noBackupFilesDir`, which Auto Backup and
/// device-to-device transfer skip; iOS keeps it in Application Support with
/// `isExcludedFromBackup` set. Neither place is one the system clears on its
/// own, which matters more than anything else here: a marker that vanished on
/// a phone that was never restored would read as a restore.
abstract interface class NoBackupMarker {
  /// Whether the marker is present. Throws when that cannot be told.
  Future<bool> exists();

  /// Creates the marker if it is missing and makes sure it is excluded from
  /// device backup. Completes only once both hold; throws otherwise.
  Future<void> write();
}

/// The platform-channel [NoBackupMarker]. Native side: `MainActivity.kt` on
/// Android and `AppDelegate.swift` on iOS.
class ChannelNoBackupMarker implements NoBackupMarker {
  ChannelNoBackupMarker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Platform-channel name shared with the native handlers.
  static const String channelName = 'is.banner.callerscompendium/no_backup';

  final MethodChannel _channel;

  @override
  Future<bool> exists() async {
    final present = await _channel.invokeMethod<bool>('markerExists');
    if (present == null) {
      throw StateError('no_backup markerExists returned no answer');
    }
    return present;
  }

  @override
  Future<void> write() => _channel.invokeMethod<void>('writeMarker');
}

/// The marker for this platform, or null where device backup cannot restore
/// the library onto another device unnoticed and the check does not run.
///
/// Only Android and iOS have it. A desktop library is moved by copying files
/// or by the app's own backup file, neither of which this check is about, and
/// a desktop has no platform folder that its backup tools are known to skip.
NoBackupMarker? platformNoBackupMarker() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => ChannelNoBackupMarker(),
    _ => null,
  };
}

/// What [checkRestoredCopy] found.
enum RestoredCopyOutcome {
  /// The library had not yet run under a build that keeps the marker: a
  /// fresh install, or the first start after an update to this build. The
  /// marker and the library flag were written and nothing else changed.
  firstRun,

  /// The library flag and the marker are both present: an ordinary start.
  ordinary,

  /// The library came from a device backup, and Device Sync had never been
  /// turned on in it, so there was nothing to turn off. Any stored device ID
  /// was erased.
  restored,

  /// The library came from a device backup with Device Sync on. The stored
  /// device ID was erased and Device Sync turned off; the caller says why.
  restoredSyncTurnedOff,
}

/// Recognises a library restored from a device backup and stops it syncing
/// under the identity of the device it was copied from (spec §3.3).
///
/// Runs at start-up, after the database has migrated and before anything
/// reads the Device Sync settings.
///
/// - **No library flag** ([kNoBackupMarkerWrittenKey] is not `true`): this is
///   the first start of a build that keeps the marker, on a fresh install or
///   after an update. Every install that updates has a library and no marker
///   yet, so the absent marker means nothing here. The marker is written
///   first and the flag only once the marker is in place: a flag beside a
///   missing marker is what a restored copy looks like, so the flag must never
///   be written when the marker could not be.
/// - **Flag and marker present:** an ordinary start; nothing is written.
/// - **Flag present, marker missing:** the library was carried here by a
///   device backup. The stored device ID is erased, so the next coordinator
///   mints a new one (`resolveSyncDeviceId`), and Device Sync is turned off
///   until the caller turns it on again. The marker is written last, so a
///   start interrupted part-way is recognised again next time rather than
///   left half-done. Nothing is sent anywhere: the copied library's store
///   address, its baseline and the old device's manifest on the store are
///   left as they are.
///
/// Throws if the marker cannot be read or written, or a setting cannot be;
/// the caller logs that and starts normally. A failure therefore never turns
/// sync off, and leaves the library flag unwritten if it was unwritten.
Future<RestoredCopyOutcome> checkRestoredCopy(
  SettingsRepository settings,
  NoBackupMarker marker,
) async {
  if (await settings.get(kNoBackupMarkerWrittenKey) != true) {
    await marker.write();
    await settings.set(kNoBackupMarkerWrittenKey, true);
    return RestoredCopyOutcome.firstRun;
  }
  if (await marker.exists()) return RestoredCopyOutcome.ordinary;
  // One transaction: the identity is erased and sync turned off together, or
  // neither is, and a failure leaves the copy to be recognised next start.
  final syncWasOn = await settings.transaction(() async {
    if (await settings.get(kSyncDeviceIdKey) != null) {
      await settings.remove(kSyncDeviceIdKey, permanent: true);
    }
    if (await settings.get(kSyncEnabledKey) != true) return false;
    await settings.set(kSyncEnabledKey, false);
    return true;
  });
  await marker.write();
  return syncWasOn
      ? RestoredCopyOutcome.restoredSyncTurnedOff
      : RestoredCopyOutcome.restored;
}
