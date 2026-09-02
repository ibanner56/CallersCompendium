import 'package:compendium_app/src/data/backup_service.dart'
    show
        isBackupEligibleSettingKey,
        kBackupSettingsDenylist,
        kBackupSettingsDenylistPrefixes;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-check between the two prefix lists that both decide whether a
/// dynamically-built settings key is device-scoped: the privacy registry
/// (`settingsPrefixClassifications`, in `compendium_core`) and the backup
/// filter's hand-written denylist (`kBackupSettingsDenylistPrefixes`, in
/// `backup_service.dart`).
///
/// These are deliberately not unified into one derived list (issue #923):
/// the backup denylist also contains structurally represented keys and backup
/// metadata, while the registry classifies values by their allowed egress.
///
/// The prefix assertion below guards the stronger correspondence needed by
/// transient editor drafts. The exact-key test also guards that every remaining
/// `deviceScoped` key is denylisted, without asserting the broader false rule
/// that every non-shareable key must be excluded from backups.
void main() {
  test('every deviceScoped settings-key prefix is excluded from backups, '
      'and vice versa', () {
    final deviceScopedPrefixes = {
      for (final entry in settingsPrefixClassifications.entries)
        if (entry.value.egress == EgressClass.deviceScoped) entry.key,
    };

    expect(
      kBackupSettingsDenylistPrefixes,
      deviceScopedPrefixes,
      reason:
          'kBackupSettingsDenylistPrefixes (backup_service.dart) and the '
          'deviceScoped prefixes in settingsPrefixClassifications '
          '(settings_registry.dart) have drifted apart. Update whichever '
          'is missing an entry — see the file doc comment on this test for '
          'why they are cross-checked rather than one being derived from '
          'the other.',
    );
  });

  test('exact deviceScoped settings are denylisted and portable local settings '
      'remain backup eligible', () {
    const backupLocalKeys = {
      'perform_text_scale',
      'seed.initialCollection.completed',
      'custom_fields.sharing.disclosed',
      'update_auto_check',
      'update_beta_channel',
      'update_dismissed_version',
      '__shareable_text_normalisation_scope__',
    };

    final exactDeviceScopedKeys = {
      for (final entry in settingsClassifications.entries)
        if (entry.value.egress == EgressClass.deviceScoped) entry.key,
    };

    expect(exactDeviceScopedKeys, {'window_frame', 'last_backup_at'});
    expect(kBackupSettingsDenylist, containsAll(exactDeviceScopedKeys));
    expect(
      kBackupSettingsDenylist,
      containsAll({'sync_id', 'sync_device_id'}),
    );
    expect(isBackupEligibleSettingKey('sync_id'), isFalse);
    expect(isBackupEligibleSettingKey('sync_device_id'), isFalse);

    for (final key in backupLocalKeys) {
      expect(
        settingsClassifications[key]?.egress,
        EgressClass.deviceLocal,
        reason: '$key must be classified as deviceLocal',
      );
      expect(
        isBackupEligibleSettingKey(key),
        isTrue,
        reason: '$key is intentionally retained in local backups',
      );
    }
  });
}
