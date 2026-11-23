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

  test('the default sort direction settings are named distinctly from the '
      'last-used ones (issue #1841)', () {
    final names = {
      for (final key in [
        'default_collection_sort_direction',
        'default_program_sort_direction',
        'last_used_collection_sort_direction',
        'last_used_program_sort_direction',
      ])
        key: syncSettingLabel(l10n, key),
    };
    expect(names.values, everyElement(isNotNull));
    expect(names.values.toSet(), hasLength(4));
  });

  test('every synced settings prefix has a name for the keys under it', () {
    // The prefix counterpart of the ratchet above: a key under a shareable
    // prefix syncs too, so it needs a label the same way. Probed with a key
    // that is the prefix plus a suffix, as a stored one is.
    final shareable = [
      for (final MapEntry(key: prefix, value: classification)
          in settingsPrefixClassifications.entries)
        if (classification.egress == EgressClass.shareable) prefix,
    ];
    final unlabelled = [
      for (final prefix in shareable)
        if (syncSettingLabel(l10n, '${prefix}probe') == null) prefix,
    ]..sort();
    expect(
      unlabelled,
      isEmpty,
      reason:
          'These settings prefixes sync but have no label in '
          'syncSettingLabel:\n  ${unlabelled.join('\n  ')}',
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

    test('masks a gendered active dialect name, and only that', () {
      for (final key in [
        'active_dialect_ref',
        'active_dialect_ref_ecd',
        'active_dialect_ref_square',
      ]) {
        expect(
          syncSettingValueText(l10n, 'Gents Night', key: key),
          Dialect.customName,
          reason: key,
        );
        expect(syncSettingValueText(l10n, 'Mine', key: key), 'Mine');
      }
      expect(
        syncSettingValueText(l10n, [
          {'name': 'Gents Night', 'roles': <String, Object?>{}},
        ]),
        Dialect.customName,
      );
    });

    test(
      'names a saved search by its own name, not by a count of its parts',
      () {
        final value = <String, Object?>{
          'v': 1,
          'name': 'Easy mixers',
          'sort': 'title',
          'facets': {'mixer': true},
        };
        // The same value under another key is just a collection: 4 entries,
        // none of them a named one.
        expect(
          syncSettingValueText(l10n, value, key: 'saved_search:abc'),
          'Easy mixers',
        );
        expect(
          syncSettingValueText(l10n, value, key: 'custom_dialects'),
          '4 items',
        );
        // A value with no usable name falls back to the count.
        expect(
          syncSettingValueText(l10n, {
            ...value,
            'name': '  ',
          }, key: 'saved_search:abc'),
          '4 items',
        );
        expect(
          syncSettingValueText(
            l10n,
            {...value}..remove('name'),
            key: 'saved_search:abc',
          ),
          '3 items',
        );
      },
    );

    test('a saved search\'s setting is labelled as one', () {
      expect(
        syncSettingLabel(l10n, 'saved_search:abc'),
        l10n.syncSavedSearchLabel,
      );
    });
  });
}
