import 'package:compendium_app/src/data/backup_service.dart'
    show
        isBackupEligibleSettingKey,
        kBackupSettingsDenylist,
        kBackupSettingsDenylistPrefixes,
        kModifierContainerCanonicalRebuildDoneKey;
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

    expect(exactDeviceScopedKeys, {
      'window_frame',
      'last_backup_at',
      'update_retirement_notice',
      derivedRebuildRequiredKey,
      purgeCorruptionRepairDoneKey,
      sectionRuleVersionKey,
      inversePairNormalisationDoneKey,
      starPromenadeHandRemovalDoneKey,
      gripSingleFileCanonicalInclusionDoneKey,
      chainHandBackfillDoneKey,
      promenadeTurnCircleWordingCanonicalRebuildDoneKey,
      compactDosidoSeesawCanonicalRebuildDoneKey,
      taxonomyV33CanonicalRebuildDoneKey,
      taxonomyV34CanonicalRebuildDoneKey,
      kModifierContainerCanonicalRebuildDoneKey,
      taxonomyV35FigureNormalizationDoneKey,
      callersBoxRollAwayRoleRepairDoneKey,
      normalisationDerivedIndexRepairDoneKey,
      'sync_last_used_fingerprint',
      'sync_enabled',
      'sync_endpoint',
      'sync_wifi_only',
      'sync_exclude_imports',
      'sync_last_success_at',
    });
    expect(kBackupSettingsDenylist, containsAll(exactDeviceScopedKeys));
    expect(
      kBackupSettingsDenylist,
      containsAll({'sync_id', 'sync_device_id', 'sync_last_used_fingerprint'}),
    );
    expect(isBackupEligibleSettingKey('sync_id'), isFalse);
    expect(isBackupEligibleSettingKey('sync_device_id'), isFalse);
    expect(isBackupEligibleSettingKey('sync_last_used_fingerprint'), isFalse);
    for (final key in [
      'sync_enabled',
      'sync_endpoint',
      'sync_wifi_only',
      'sync_exclude_imports',
      'sync_last_success_at',
    ]) {
      expect(isBackupEligibleSettingKey(key), isFalse, reason: key);
    }
    expect(
      isBackupEligibleSettingKey(taxonomyV33CanonicalRebuildDoneKey),
      isFalse,
    );
    expect(
      isBackupEligibleSettingKey(taxonomyV34CanonicalRebuildDoneKey),
      isFalse,
    );
    expect(
      isBackupEligibleSettingKey(taxonomyV35FigureNormalizationDoneKey),
      isFalse,
    );
    expect(
      isBackupEligibleSettingKey(callersBoxRollAwayRoleRepairDoneKey),
      isFalse,
    );

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

  test('every exact denylisted key is either structurally represented or '
      'classified non-shareable', () {
    // The other direction of the cross-check above. The test above asks
    // "is every deviceScoped key denylisted?"; this asks "is every denylisted
    // key one the registry agrees must not travel?". Without it a key can be
    // `_preference` ("the same on any device they own") in the registry and
    // "must not travel between machines" in the denylist at once, and the
    // next reader who infers "denylisted, so not shareable" is wrong.
    //
    // The one legitimate exception is the structurally represented group:
    // dialects and themes are `shareable` and DO travel, in the
    // BackupDocument's typed sections rather than the raw settings map, so
    // the denylist excludes their raw blobs for redundancy, not egress.
    const structurallyRepresented = {
      'custom_dialects',
      'active_dialect_ref',
      'active_dialect',
      'custom_themes',
      'active_custom_theme',
    };

    final shareableButDenylisted = [
      for (final key in kBackupSettingsDenylist)
        if (!structurallyRepresented.contains(key) &&
            settingsClassifications[key]?.egress == EgressClass.shareable)
          key,
    ]..sort();

    expect(
      shareableButDenylisted,
      isEmpty,
      reason:
          'These keys are `shareable` in settings_registry.dart but excluded '
          'from backups by kBackupSettingsDenylist (backup_service.dart). One '
          'of the two is wrong: either the key is installation state and '
          'needs a non-shareable classification, or it is a preference and '
          'must leave the denylist. If it travels in a typed section of the '
          'BackupDocument instead, add it to structurallyRepresented here.',
    );
  });
}
