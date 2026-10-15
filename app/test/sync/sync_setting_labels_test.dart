import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/sync/sync_setting_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('every synced setting has a name the conflict choice can show', () {
    // A conflict on a setting asks the user to pick a version; "Setting"
    // alone gives them nothing to decide with. A key newly classified
    // shareable must get a label in sync_setting_labels.dart in the same
    // change.
    final shareable = [
      for (final key in settingsClassifications.keys)
        if (classifySettingsKey(key)?.egress == EgressClass.shareable) key,
    ];
    expect(
      shareable,
      isNotEmpty,
      reason: 'the registry changed shape; this ratchet would be vacuous',
    );

    final unlabelled = [
      for (final key in shareable)
        if (syncSettingLabel(l10n, key) == null) key,
    ]..sort();

    expect(
      unlabelled,
      isEmpty,
      reason:
          'These settings sync but have no label in syncSettingLabel, so a '
          'conflict on one would be shown as a bare "Setting":\n  '
          '${unlabelled.join('\n  ')}',
    );
  });

  test('the whole-collection keys are synced settings with labels', () {
    for (final key in syncWholeCollectionSettingKeys) {
      expect(
        classifySettingsKey(key)?.egress,
        EgressClass.shareable,
        reason: '$key is routed to review by the merge, so it must sync',
      );
      expect(syncSettingLabel(l10n, key), isNotNull, reason: key);
    }
  });

  group('syncSettingValueText', () {
    test('names on/off, empty and scalar values', () {
      expect(syncSettingValueText(l10n, true), 'On');
      expect(syncSettingValueText(l10n, false), 'Off');
      expect(syncSettingValueText(l10n, null), 'Not set');
      expect(syncSettingValueText(l10n, ''), 'Not set');
      expect(syncSettingValueText(l10n, 'dark'), 'dark');
      expect(syncSettingValueText(l10n, 30), '30');
    });

    test('summarises a collection by its entries\' names, never as data', () {
      expect(
        syncSettingValueText(l10n, [
          {'name': 'Larks/Robins', 'roles': <Object?>[]},
          {'name': 'Leads/Follows', 'roles': <Object?>[]},
        ]),
        'Larks/Robins, Leads/Follows',
      );
      expect(
        syncSettingValueText(l10n, [
          for (var i = 1; i <= 6; i++) {'name': 'Dialect $i'},
        ]),
        'Dialect 1, Dialect 2, Dialect 3, Dialect 4 and 2 more',
      );
      expect(
        syncSettingValueText(l10n, [
          {'a': 1},
          {'b': 2},
        ]),
        '2 items',
      );
      expect(syncSettingValueText(l10n, <Object?>[]), 'None');
    });
  });
}
