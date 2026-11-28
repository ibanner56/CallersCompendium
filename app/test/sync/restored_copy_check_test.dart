import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/sync/restored_copy_check.dart';
import 'package:compendium_app/src/sync/sync_runtime.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// An in-memory [NoBackupMarker]: one installation's no-backup folder.
class _FakeMarker implements NoBackupMarker {
  _FakeMarker({this.present = false});

  bool present;
  bool failWrite = false;
  bool failRead = false;
  int writes = 0;

  @override
  Future<bool> exists() async {
    if (failRead) throw PlatformException(code: 'io');
    return present;
  }

  @override
  Future<void> write() async {
    if (failWrite) throw PlatformException(code: 'io');
    writes++;
    present = true;
  }
}

/// Copies every setting of [from] into [to]: what a device backup does to the
/// database file, seen from the settings table.
Future<void> _copyLibrary(
  CompendiumRepositories from,
  CompendiumRepositories to,
) async {
  for (final entry in (await from.settings.all()).entries) {
    await to.settings.set(entry.key, entry.value);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A library that has been syncing on a phone running this build.
  Future<(CompendiumRepositories, String)> syncingPhone() async {
    final repos = openTestRepositories();
    final marker = _FakeMarker();
    expect(
      await checkRestoredCopy(repos.settings, marker),
      RestoredCopyOutcome.firstRun,
    );
    await repos.settings.set(kSyncIdKey, 'store-one');
    await repos.settings.set(kSyncEnabledKey, true);
    final deviceId = await resolveSyncDeviceId(repos.settings);
    return (repos, deviceId);
  }

  group('checkRestoredCopy (spec §3.3)', () {
    test('fresh install: writes the marker, then the flag, and nothing '
        'else', () async {
      final repos = openTestRepositories();
      final marker = _FakeMarker();

      final outcome = await checkRestoredCopy(repos.settings, marker);

      expect(outcome, RestoredCopyOutcome.firstRun);
      expect(marker.present, isTrue);
      expect(await repos.settings.get(kNoBackupMarkerWrittenKey), isTrue);
      expect(await repos.settings.get(kSyncEnabledKey), isNull);
    });

    test('update from a build without the marker: a syncing library keeps '
        'its identity and stays on', () async {
      // Every install that updates has a library and no marker yet.
      final repos = openTestRepositories();
      await repos.settings.set(kSyncIdKey, 'store-one');
      await repos.settings.set(kSyncEnabledKey, true);
      final deviceId = await resolveSyncDeviceId(repos.settings);
      final marker = _FakeMarker();

      final outcome = await checkRestoredCopy(repos.settings, marker);

      expect(outcome, RestoredCopyOutcome.firstRun);
      expect(await repos.settings.get(kSyncDeviceIdKey), deviceId);
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
      expect(marker.present, isTrue);
      expect(await repos.settings.get(kNoBackupMarkerWrittenKey), isTrue);
    });

    test('ordinary relaunch: changes nothing and writes nothing', () async {
      final (repos, deviceId) = await syncingPhone();
      final marker = _FakeMarker(present: true);

      final outcome = await checkRestoredCopy(repos.settings, marker);

      expect(outcome, RestoredCopyOutcome.ordinary);
      expect(marker.writes, 0);
      expect(await repos.settings.get(kSyncDeviceIdKey), deviceId);
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
    });

    test('restored copy: a new phone set up from a syncing phone\'s backup '
        'gets its own identity, with Device Sync off', () async {
      final (oldPhone, oldId) = await syncingPhone();
      final newPhone = openTestRepositories();
      await _copyLibrary(oldPhone, newPhone);
      final newMarker = _FakeMarker(); // device backup never copies it

      final outcome = await checkRestoredCopy(newPhone.settings, newMarker);

      expect(outcome, RestoredCopyOutcome.restoredSyncTurnedOff);
      expect(await newPhone.settings.get(kSyncDeviceIdKey), isNull);
      expect(await newPhone.settings.get(kSyncEnabledKey), isFalse);
      expect(newMarker.present, isTrue);
      // Turning sync back on mints an identity of its own.
      final newId = await resolveSyncDeviceId(newPhone.settings);
      expect(newId, isNot(oldId));
      // The store it was attached to is kept, so turning sync on is enough.
      expect(await newPhone.settings.get(kSyncIdKey), 'store-one');
      // And the next start is an ordinary one.
      expect(
        await checkRestoredCopy(newPhone.settings, newMarker),
        RestoredCopyOutcome.ordinary,
      );
      expect(await newPhone.settings.get(kSyncDeviceIdKey), newId);
    });

    test('restored copy of a library that never synced: nothing to turn off, '
        'so nothing to say', () async {
      final oldPhone = openTestRepositories();
      await checkRestoredCopy(oldPhone.settings, _FakeMarker());
      final newPhone = openTestRepositories();
      await _copyLibrary(oldPhone, newPhone);

      final outcome = await checkRestoredCopy(newPhone.settings, _FakeMarker());

      expect(outcome, RestoredCopyOutcome.restored);
      expect(await newPhone.settings.get(kSyncEnabledKey), isNull);
    });

    test('restored copy with sync attached but off: the identity is still '
        'replaced', () async {
      final (oldPhone, oldId) = await syncingPhone();
      await oldPhone.settings.set(kSyncEnabledKey, false);
      final newPhone = openTestRepositories();
      await _copyLibrary(oldPhone, newPhone);

      final outcome = await checkRestoredCopy(newPhone.settings, _FakeMarker());

      expect(outcome, RestoredCopyOutcome.restored);
      expect(await newPhone.settings.get(kSyncDeviceIdKey), isNull);
      expect(await resolveSyncDeviceId(newPhone.settings), isNot(oldId));
    });

    test('a marker that cannot be written leaves the flag unwritten, so the '
        'next start is not taken for a restore', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kSyncEnabledKey, true);
      final marker = _FakeMarker()..failWrite = true;

      await expectLater(
        checkRestoredCopy(repos.settings, marker),
        throwsA(isA<PlatformException>()),
      );
      expect(await repos.settings.get(kNoBackupMarkerWrittenKey), isNull);

      // The next start, with the marker writable again, is a first run.
      marker.failWrite = false;
      expect(
        await checkRestoredCopy(repos.settings, marker),
        RestoredCopyOutcome.firstRun,
      );
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
    });

    test('a marker that cannot be read changes nothing', () async {
      final (repos, deviceId) = await syncingPhone();
      final marker = _FakeMarker()..failRead = true;

      await expectLater(
        checkRestoredCopy(repos.settings, marker),
        throwsA(isA<PlatformException>()),
      );
      expect(await repos.settings.get(kSyncDeviceIdKey), deviceId);
      expect(await repos.settings.get(kSyncEnabledKey), isTrue);
    });

    test('a restored copy whose marker cannot then be written still says '
        'what it did, and a sync turned back on is not turned off '
        'again', () async {
      final (oldPhone, _) = await syncingPhone();
      final newPhone = openTestRepositories();
      await _copyLibrary(oldPhone, newPhone);
      final marker = _FakeMarker()..failWrite = true;

      final outcome = await checkRestoredCopy(newPhone.settings, marker);

      expect(outcome, RestoredCopyOutcome.restoredSyncTurnedOff);
      expect(await newPhone.settings.get(kSyncEnabledKey), isFalse);
      expect(await newPhone.settings.get(kNoBackupMarkerWrittenKey), isNull);

      // The caller turns sync back on, and a new identity is minted.
      await newPhone.settings.set(kSyncEnabledKey, true);
      final newId = await resolveSyncDeviceId(newPhone.settings);
      marker.failWrite = false;

      expect(
        await checkRestoredCopy(newPhone.settings, marker),
        RestoredCopyOutcome.firstRun,
      );
      expect(marker.present, isTrue);
      expect(await newPhone.settings.get(kSyncEnabledKey), isTrue);
      expect(await newPhone.settings.get(kSyncDeviceIdKey), newId);
    });
  });

  group('ChannelNoBackupMarker', () {
    const channel = MethodChannel(ChannelNoBackupMarker.channelName);
    final messenger =
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads and writes through the platform channel', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'markerExists' ? false : null;
      });
      final marker = ChannelNoBackupMarker();

      expect(await marker.exists(), isFalse);
      await marker.write();

      expect(calls, ['markerExists', 'writeMarker']);
    });

    test(
      'an empty answer to markerExists is an error, not "missing"',
      () async {
        // A missing marker is what a restore looks like, so an answer that
        // says nothing must not read as one.
        messenger.setMockMethodCallHandler(channel, (call) async => null);

        await expectLater(ChannelNoBackupMarker().exists(), throwsStateError);
      },
    );

    test(
      'a platform without the channel throws rather than answering',
      () async {
        await expectLater(
          ChannelNoBackupMarker().exists(),
          throwsA(isA<MissingPluginException>()),
        );
      },
    );
  });
}
