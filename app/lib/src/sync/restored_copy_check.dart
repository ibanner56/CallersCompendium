import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../data/settings_keys.dart'
    show kNoBackupMarkerWrittenKey, kSyncDeviceIdKey, kSyncEnabledKey;
import '../diagnostics/error_log.dart' show logCaughtError;

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
///   device backup, or restored onto this same device after a reinstall or a
///   reset. In one transaction the stored device ID is erased, so the next
///   coordinator mints a new one (`resolveSyncDeviceId`), Device Sync is
///   turned off until the caller turns it on again, and the flag is removed.
///   Then the marker and the flag are written as on a first run. If that
///   fails, it is logged and the outcome still says what was done: with the
///   flag gone, the next start is a first run, which writes them and changes
///   nothing, so a sync the caller turns back on is not turned off again.
///   Nothing is sent anywhere: the copied library's store address, its
///   baseline and the old device's manifest on the store are left as they
///   are.
///
/// Throws, having changed nothing, if the flag or the marker cannot be read,
/// if the marker cannot be written on a first run, or if the restored copy's
/// transaction fails; the caller logs that and starts with Device Sync as it
/// was. A first run whose marker cannot be written leaves the flag
/// unwritten, so the next start is a first run again, not a restore.
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
  // One transaction: the identity is erased, sync turned off and the flag
  // removed together, or none of them is, and a failure leaves the copy to be
  // recognised next start.
  final syncWasOn = await settings.transaction(() async {
    if (await settings.get(kSyncDeviceIdKey) != null) {
      await settings.remove(kSyncDeviceIdKey, permanent: true);
    }
    await settings.remove(kNoBackupMarkerWrittenKey, permanent: true);
    if (await settings.get(kSyncEnabledKey) != true) return false;
    await settings.set(kSyncEnabledKey, false);
    return true;
  });
  try {
    await marker.write();
    await settings.set(kNoBackupMarkerWrittenKey, true);
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'sync.restored_copy_marker');
  }
  return syncWasOn
      ? RestoredCopyOutcome.restoredSyncTurnedOff
      : RestoredCopyOutcome.restored;
}
