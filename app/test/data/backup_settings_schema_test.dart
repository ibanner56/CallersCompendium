import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart'
    show kAggressiveBeatsUpdateKey;
import 'package:compendium_app/src/data/backup_reminder.dart'
    show kBackupReminderCadenceKey;
import 'package:compendium_app/src/data/backup_service.dart'
    show isBackupEligibleSettingKey;
import 'package:compendium_app/src/data/backup_settings_schema.dart';
import 'package:compendium_app/src/data/seed_service.dart'
    show kInitialSeedCompletedKey;
import 'package:compendium_app/src/data/display_defaults.dart'
    show
        encodeStartingProgramTemplate,
        kCanonicalFigureTextKey,
        kDefaultImportTagIdsKey,
        kDefaultModifierFiguresKey,
        kDefaultStartingProgramKey,
        StartingProgramTemplateEntry;
import 'package:compendium_app/src/screens/settings/settings_keys.dart'
    show
        kCollectionHiddenFacetsKey,
        kCollectionTileVisibleFieldsKey,
        kCustomFieldSharingDisclosureKey,
        kEcdConvertPromptDismissedKey,
        kProgramDanceShareFieldsKey,
        kProgramMatrixColumnsKey,
        kShowIndividualPerformTimerKey,
        kVenueCallCountKey;
import 'package:compendium_core/compendium_core.dart'
    show
        MatrixColumnConfig,
        settingsClassifications,
        shareableTextNormalisationScopeKey;
import 'package:compendium_app/src/data/soft_delete_retention.dart'
    show kSoftDeleteRetentionKey;
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart'
    show kWalkthroughSnippetsKey;
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart'
    show kShorthandMappingsKey;
import 'package:compendium_app/src/screens/settings_screen.dart'
    show
        kAppThemeKey,
        kSortIgnoreArticlesKey,
        kPerformTextScaleKey,
        kShowProgramSlotCallerNotesKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateBackupSettingValue (issue #609)', () {
    test(
      'starting program templates require the validated versioned shape',
      () {
        expect(
          validateBackupSettingValue(
            kDefaultStartingProgramKey,
            encodeStartingProgramTemplate([
              const StartingProgramTemplateEntry(
                danceId: 'dance-1',
                text: 'Caller note',
              ),
            ]),
          ),
          isTrue,
        );
        expect(
          validateBackupSettingValue(
            kDefaultStartingProgramKey,
            '{"version":1,"slots":[{"id":"persisted"}]}',
          ),
          isFalse,
        );
        expect(
          validateBackupSettingValue(
            kDefaultStartingProgramKey,
            '{"version":1,"slots":[{}]}',
          ),
          isFalse,
        );
      },
    );

    test('program caller-note visibility setting accepts only bools', () {
      expect(
        validateBackupSettingValue(kShowProgramSlotCallerNotesKey, true),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kShowProgramSlotCallerNotesKey, false),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kShowProgramSlotCallerNotesKey, 'true'),
        isFalse,
      );
      expect(
        validateBackupSettingValue(kShowProgramSlotCallerNotesKey, null),
        isFalse,
      );
    });

    test('bool keys accept only bools', () {
      expect(validateBackupSettingValue(kSortIgnoreArticlesKey, true), isTrue);
      expect(validateBackupSettingValue(kSortIgnoreArticlesKey, false), isTrue);
      expect(
        validateBackupSettingValue(kSortIgnoreArticlesKey, 'true'),
        isFalse,
      );
      expect(validateBackupSettingValue(kSortIgnoreArticlesKey, 1), isFalse);
      expect(validateBackupSettingValue(kSortIgnoreArticlesKey, null), isFalse);
    });

    test('individual Perform timer setting accepts only bools', () {
      expect(
        validateBackupSettingValue(kShowIndividualPerformTimerKey, true),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kShowIndividualPerformTimerKey, false),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kShowIndividualPerformTimerKey, 'true'),
        isFalse,
      );
      expect(
        validateBackupSettingValue(kShowIndividualPerformTimerKey, 1),
        isFalse,
      );
      expect(
        validateBackupSettingValue(kShowIndividualPerformTimerKey, null),
        isFalse,
      );
    });

    test('aggressive beats update (#689) accepts only bools', () {
      expect(
        validateBackupSettingValue(kAggressiveBeatsUpdateKey, true),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kAggressiveBeatsUpdateKey, false),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kAggressiveBeatsUpdateKey, 'true'),
        isFalse,
      );
      expect(validateBackupSettingValue(kAggressiveBeatsUpdateKey, 1), isFalse);
      expect(
        validateBackupSettingValue(kAggressiveBeatsUpdateKey, null),
        isFalse,
      );
    });

    test('canonical figure text gate accepts only bools', () {
      expect(validateBackupSettingValue(kCanonicalFigureTextKey, true), isTrue);
      expect(
        validateBackupSettingValue(kCanonicalFigureTextKey, false),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kCanonicalFigureTextKey, 'true'),
        isFalse,
      );
      expect(validateBackupSettingValue(kCanonicalFigureTextKey, 1), isFalse);
      expect(
        validateBackupSettingValue(kCanonicalFigureTextKey, null),
        isFalse,
      );
    });

    test('string keys accept only strings', () {
      expect(validateBackupSettingValue(kAppThemeKey, 'dark'), isTrue);
      expect(validateBackupSettingValue(kAppThemeKey, ''), isTrue);
      expect(validateBackupSettingValue(kAppThemeKey, 123), isFalse);
      expect(validateBackupSettingValue(kAppThemeKey, true), isFalse);
      expect(validateBackupSettingValue(kAppThemeKey, {'x': 1}), isFalse);
    });

    test('default import tags (#1476) accept only a JSON list of strings', () {
      expect(
        validateBackupSettingValue(kDefaultImportTagIdsKey, '["a","b"]'),
        isTrue,
      );
      expect(validateBackupSettingValue(kDefaultImportTagIdsKey, '[]'), isTrue);
      for (final bad in <Object?>[
        'not json',
        '{"a":1}',
        '[1,2]',
        '[""]',
        ['a'],
        42,
        null,
      ]) {
        expect(
          validateBackupSettingValue(kDefaultImportTagIdsKey, bad),
          isFalse,
          reason: '$bad',
        );
      }
    });

    test('modifier defaults accept only encoded figure strings', () {
      expect(
        validateBackupSettingValue(kDefaultModifierFiguresKey, '[]'),
        isTrue,
      );
      expect(
        validateBackupSettingValue(
          kDefaultModifierFiguresKey,
          '[{"move":"swing"}]',
        ),
        isTrue,
      );
      expect(
        validateBackupSettingValue(kDefaultModifierFiguresKey, []),
        isFalse,
      );
      expect(
        validateBackupSettingValue(kDefaultModifierFiguresKey, true),
        isFalse,
      );
    });

    test(
      'perform text scale mirrors the reader: finite and >= minimum, no cap',
      () {
        expect(validateBackupSettingValue(kPerformTextScaleKey, 1.8), isTrue);
        expect(validateBackupSettingValue(kPerformTextScaleKey, 2), isTrue);
        // Intentionally unbounded above — a large finite low-vision scale is a
        // legitimate preference that must survive a restore.
        expect(
          validateBackupSettingValue(kPerformTextScaleKey, 1000.1),
          isTrue,
        );
        // Below the enforced minimum (kPerformMinScale == 1.0) is rejected.
        expect(validateBackupSettingValue(kPerformTextScaleKey, 0), isFalse);
        expect(validateBackupSettingValue(kPerformTextScaleKey, 0.5), isFalse);
        expect(validateBackupSettingValue(kPerformTextScaleKey, -1.0), isFalse);
        expect(
          validateBackupSettingValue(kPerformTextScaleKey, double.nan),
          isFalse,
        );
        expect(
          validateBackupSettingValue(kPerformTextScaleKey, double.infinity),
          isFalse,
        );
        expect(
          validateBackupSettingValue(kPerformTextScaleKey, 'big'),
          isFalse,
        );
      },
    );

    test('retention accepts only non-negative ints', () {
      expect(validateBackupSettingValue(kSoftDeleteRetentionKey, 0), isTrue);
      expect(validateBackupSettingValue(kSoftDeleteRetentionKey, 30), isTrue);
      expect(validateBackupSettingValue(kSoftDeleteRetentionKey, -5), isFalse);
      expect(validateBackupSettingValue(kSoftDeleteRetentionKey, 1.5), isFalse);
      expect(
        validateBackupSettingValue(kSoftDeleteRetentionKey, '30'),
        isFalse,
      );
    });

    test('venue call count accepts only bounded ints', () {
      expect(validateBackupSettingValue(kVenueCallCountKey, 0), isTrue);
      expect(validateBackupSettingValue(kVenueCallCountKey, 10), isTrue);
      expect(validateBackupSettingValue(kVenueCallCountKey, -1), isFalse);
      expect(validateBackupSettingValue(kVenueCallCountKey, 11), isFalse);
      expect(validateBackupSettingValue(kVenueCallCountKey, 1.5), isFalse);
      expect(validateBackupSettingValue(kVenueCallCountKey, '3'), isFalse);
    });

    test('map-blob keys accept only maps', () {
      expect(
        validateBackupSettingValue(kWalkthroughSnippetsKey, <String, Object?>{
          'snippets': <String, Object?>{},
        }),
        isTrue,
      );
      expect(validateBackupSettingValue(kWalkthroughSnippetsKey, []), isFalse);
      expect(
        validateBackupSettingValue(kWalkthroughSnippetsKey, 'nope'),
        isFalse,
      );
    });

    test('shorthand mappings accept a list or a string', () {
      expect(validateBackupSettingValue(kShorthandMappingsKey, []), isTrue);
      expect(validateBackupSettingValue(kShorthandMappingsKey, '[]'), isTrue);
      expect(validateBackupSettingValue(kShorthandMappingsKey, 42), isFalse);
      expect(
        validateBackupSettingValue(kShorthandMappingsKey, <String, int>{
          'a': 1,
        }),
        isFalse,
      );
    });

    test('program-matrix column config (#935): only a codec-parseable Map', () {
      // A valid config Map round-trips through the codec and is accepted.
      final valid = const MatrixColumnConfig(
        hidden: {'do_si_do'},
        renames: {'do_si_do': 'Dosido'},
      ).toJson();
      expect(
        validateBackupSettingValue(kProgramMatrixColumnsKey, valid),
        isTrue,
      );
      // An empty Map is a valid (default) config.
      expect(
        validateBackupSettingValue(
          kProgramMatrixColumnsKey,
          <String, Object?>{},
        ),
        isTrue,
      );
      // Non-Map values are rejected outright.
      expect(
        validateBackupSettingValue(kProgramMatrixColumnsKey, 'nope'),
        isFalse,
      );
      expect(
        validateBackupSettingValue(kProgramMatrixColumnsKey, <Object?>[]),
        isFalse,
      );
      // A Map the codec rejects (mis-namespaced custom id) is dropped rather
      // than reaching the throwing decode path at restore.
      expect(
        validateBackupSettingValue(kProgramMatrixColumnsKey, {
          'parameterized': [
            {'id': 'swing', 'baseMove': 'swing'},
          ],
        }),
        isFalse,
      );
    });

    test('the latches, the cadence, the list settings and the normalisation '
        'scope marker enforce their container kind', () {
      for (final key in [
        kInitialSeedCompletedKey,
        kCustomFieldSharingDisclosureKey,
        kEcdConvertPromptDismissedKey,
      ]) {
        expect(validateBackupSettingValue(key, true), isTrue, reason: key);
        expect(validateBackupSettingValue(key, 'true'), isFalse, reason: key);
        expect(validateBackupSettingValue(key, 1), isFalse, reason: key);
      }
      expect(
        validateBackupSettingValue(kBackupReminderCadenceKey, 'weekly'),
        isTrue,
      );
      expect(validateBackupSettingValue(kBackupReminderCadenceKey, 7), isFalse);
      for (final key in [
        kCollectionTileVisibleFieldsKey,
        kCollectionHiddenFacetsKey,
        kProgramDanceShareFieldsKey,
      ]) {
        expect(
          validateBackupSettingValue(key, ['title', 'tags']),
          isTrue,
          reason: key,
        );
        expect(validateBackupSettingValue(key, <Object?>[]), isTrue);
        expect(validateBackupSettingValue(key, 'title'), isFalse, reason: key);
        expect(
          validateBackupSettingValue(key, {'title': true}),
          isFalse,
          reason: key,
        );
      }
      expect(
        validateBackupSettingValue(shareableTextNormalisationScopeKey, {
          'version': 1,
          'columns': <String>[],
          'settings': <String>[],
          'settingsPrefixes': <String>[],
        }),
        isTrue,
      );
      expect(
        validateBackupSettingValue(
          shareableTextNormalisationScopeKey,
          '{"version":1}',
        ),
        isFalse,
      );
    });

    test('unknown / forward-compatible keys pass through (null verdict)', () {
      expect(
        validateBackupSettingValue('some_future_key_v99', 'anything'),
        isNull,
      );
      expect(validateBackupSettingValue('another_unknown', 12345), isNull);
    });
  });

  test('every backup-eligible key this build knows has a validator', () {
    // The null verdict above is a forward-compatibility contract for keys a
    // NEWER build wrote and this one has never heard of. It is not meant to
    // cover keys this build declares itself: for those, "no validator" is a
    // gap in the schema, and a hand-edited or crafted backup can restore any
    // JSON shape under the key. Every live reader is defensive today, so the
    // gap is latent rather than a crash — but the validator map was a
    // hand-maintained list with no reconciliation against the registry, and
    // hand-maintained lists drift. This turns it into a ratchet: a new
    // backup-eligible key must either get a validator or be exempted here by
    // name, with a reason.
    //
    // A `null` probe is enough to tell "has a validator" (bool verdict) from
    // "unknown to the schema" (null verdict); the per-key tests above check
    // what each validator accepts.
    const exempt = <String, String>{};

    final eligible = [
      for (final key in settingsClassifications.keys)
        if (isBackupEligibleSettingKey(key)) key,
    ];
    expect(
      eligible,
      isNotEmpty,
      reason:
          'the registry or the denylist has changed shape; this ratchet '
          'would be vacuous',
    );

    final unvalidated = [
      for (final key in eligible)
        if (!exempt.containsKey(key) &&
            validateBackupSettingValue(key, null) == null)
          key,
    ]..sort();

    expect(
      unvalidated,
      isEmpty,
      reason:
          'These settings keys are classified in settings_registry.dart and '
          'travel in backups (isBackupEligibleSettingKey), but '
          'backup_settings_schema.dart has no validator for them, so a '
          'restore writes whatever JSON the file carries. Add each to '
          '_backupSettingValidators, or exempt it above with a reason:\n  '
          '${unvalidated.join('\n  ')}',
    );

    final staleExemptions =
        exempt.keys.where((key) => !eligible.contains(key)).toList()..sort();
    expect(
      staleExemptions,
      isEmpty,
      reason:
          'These exemptions name keys that are no longer backup-eligible '
          'or no longer classified; delete them so the list stays honest:\n  '
          '${staleExemptions.join('\n  ')}',
    );
  });
}
