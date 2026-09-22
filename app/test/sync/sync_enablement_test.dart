import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_runtime.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Spec §6.1: Device Sync is off until the user turns it on, and an off or
/// unconfigured installation makes no sync-related network call. The
/// coordinator is the only object that can reach the network, so "no
/// coordinator is constructed" is the no-network property.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final factory = ConfiguredSyncCoordinatorFactory(
    endpoint: Uri.parse('https://sync.example.test'),
  );

  test('a fresh installation constructs no coordinator', () async {
    final repos = openTestRepositories();
    expect(await factory(repos), isNull);
  });

  test('a stored sync ID alone does not enable sync', () async {
    final repos = openTestRepositories();
    await repos.settings.set(kSyncIdKey, 'correct horse battery staple');
    expect(await factory(repos), isNull);

    await repos.settings.set(kSyncEnabledKey, false);
    expect(await factory(repos), isNull);
  });

  test('enabled without a sync ID constructs no coordinator', () async {
    final repos = openTestRepositories();
    await repos.settings.set(kSyncEnabledKey, true);
    expect(await factory(repos), isNull);
  });

  test('a non-boolean enabled value is not consent', () async {
    final repos = openTestRepositories();
    await repos.settings.set(kSyncIdKey, 'correct horse battery staple');
    await repos.settings.set(kSyncEnabledKey, 'true');
    expect(await factory(repos), isNull);
  });

  test('restoring a backup taken on a syncing device leaves sync off, adopts '
      'no device ID and stores no credential', () async {
    final source = openTestRepositories();
    await source.settings.set(kSyncEnabledKey, true);
    await source.settings.set(kSyncWifiOnlyKey, false);
    await source.settings.set(kSyncExcludeImportsKey, true);
    await source.settings.set(kSyncIdKey, 'correct horse battery staple');
    await source.settings.set(kSyncDeviceIdKey, 'device_source');
    await source.settings.set(kSyncLastSuccessAtKey, '2026-09-01T00:00:00Z');
    await source.settings.set(kSyncLastUsedFingerprintKey, 'fingerprint');
    final backup = await BackupService(source).exportToJson();

    for (final key in [
      'sync_enabled',
      'sync_wifi_only',
      'sync_exclude_imports',
      'sync_id',
      'sync_device_id',
      'sync_last_success_at',
      'sync_last_used_fingerprint',
    ]) {
      expect(backup, isNot(contains('"$key"')), reason: 'exported $key');
    }

    final target = openTestRepositories();
    final outcome = await BackupService(target).restoreFromJson(backup);
    expect(outcome.applied, isTrue);

    expect(await target.settings.get(kSyncEnabledKey), isNull);
    expect(await target.settings.get(kSyncWifiOnlyKey), isNull);
    expect(await target.settings.get(kSyncExcludeImportsKey), isNull);
    expect(await target.settings.get(kSyncIdKey), isNull);
    expect(await target.settings.get(kSyncDeviceIdKey), isNull);
    expect(await target.settings.get(kSyncLastSuccessAtKey), isNull);
    expect(await factory(target), isNull);
  });

  test(
    'a restore does not clear consent already given on this device',
    () async {
      final source = openTestRepositories();
      final backup = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      await target.settings.set(kSyncEnabledKey, true);
      await target.settings.set(kSyncIdKey, 'correct horse battery staple');
      await BackupService(target).restoreFromJson(backup);

      expect(await target.settings.get(kSyncEnabledKey), isTrue);
      expect(await target.settings.get(kSyncIdKey), isNotNull);
    },
  );
}
