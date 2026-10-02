import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_runtime.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

  group('resolveSyncDeviceId (spec §3.3)', () {
    test('mints and persists a well-formed identifier when none is '
        'stored', () async {
      final minted = await resolveSyncDeviceId(repos.settings);

      expect(minted, matches(RegExp(r'^[A-Za-z0-9_-]{24}$')));
      expect(await repos.settings.get(kSyncDeviceIdKey), minted);
    });

    test('announces a mint, and only a '
        'mint', () async {
      final observed = <Object?>[];
      await resolveSyncDeviceId(
        repos.settings,
        beforeMint: () => observed.add('mint'),
      );
      await resolveSyncDeviceId(
        repos.settings,
        beforeMint: () => observed.add('reuse'),
      );

      expect(observed, ['mint']);
    });

    test('returns the stored identifier unchanged while one exists', () async {
      await repos.settings.set(kSyncDeviceIdKey, 'device_1');

      expect(await resolveSyncDeviceId(repos.settings), 'device_1');
      expect(await repos.settings.get(kSyncDeviceIdKey), 'device_1');
    });

    test('mints a different identifier once the stored one is '
        'removed', () async {
      final first = await resolveSyncDeviceId(repos.settings);
      await repos.settings.remove(kSyncDeviceIdKey, permanent: true);

      final second = await resolveSyncDeviceId(repos.settings);

      expect(
        second,
        isNot(first),
        reason:
            'a new attachment must not be linkable to the previous one '
            'through its device ID',
      );
    });

    test('refuses a stored value that is not an identifier rather than '
        'replacing it', () async {
      for (final invalid in <Object>['', 'has space', 42]) {
        await repos.settings.set(kSyncDeviceIdKey, invalid);
        await expectLater(
          resolveSyncDeviceId(repos.settings),
          throwsFormatException,
          reason: '$invalid',
        );
        expect(await repos.settings.get(kSyncDeviceIdKey), invalid);
      }
    });
  });
}
