import 'package:compendium_app/src/data/backup_service.dart'
    show kBackupSettingsDenylistPrefixes;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-check between the two prefix lists that both decide whether a
/// dynamically-built settings key is device-scoped: the privacy registry
/// (`settingsPrefixClassifications`, in `compendium_core`) and the backup
/// filter's hand-written denylist (`kBackupSettingsDenylistPrefixes`, in
/// `backup_service.dart`).
///
/// These are deliberately **not** unified into one derived list (issue #923,
/// maintainer decision): only 2 of the registry's 8 `deviceScoped` settings
/// entries are actually excluded from backups today (`window_frame`,
/// `last_backup_at`) — the other six device-scoped keys (`perform_text_scale`,
/// `seed.initialCollection.completed`, `custom_fields.sharing.disclosed`,
/// `update_auto_check`, `update_beta_channel`, `update_dismissed_version`) are
/// intentionally included in backups. So "non-shareable ⇒ excluded from
/// backups" is not a rule this codebase follows, and deriving the backup
/// denylist from `EgressClass` would encode a rule that is false for 6 of the
/// 8 cases it would apply to.
///
/// What *is* true, and worth guarding, is the narrower claim: every
/// **prefix** classified `deviceScoped` is also denylisted from backups, and
/// vice versa. This test asserts that narrower claim without asserting the
/// broader (false) one.
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
}
