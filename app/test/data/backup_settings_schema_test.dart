import 'package:compendium_app/src/data/backup_settings_schema.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart'
    show kSoftDeleteRetentionKey;
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart'
    show kWalkthroughSnippetsKey;
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart'
    show kShorthandMappingsKey;
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kAppThemeKey, kSortIgnoreArticlesKey, kPerformTextScaleKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateBackupSettingValue (issue #609)', () {
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

    test('string keys accept only strings', () {
      expect(validateBackupSettingValue(kAppThemeKey, 'dark'), isTrue);
      expect(validateBackupSettingValue(kAppThemeKey, ''), isTrue);
      expect(validateBackupSettingValue(kAppThemeKey, 123), isFalse);
      expect(validateBackupSettingValue(kAppThemeKey, true), isFalse);
      expect(validateBackupSettingValue(kAppThemeKey, {'x': 1}), isFalse);
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

    test('unknown / forward-compatible keys pass through (null verdict)', () {
      expect(
        validateBackupSettingValue('some_future_key_v99', 'anything'),
        isNull,
      );
      expect(validateBackupSettingValue('another_unknown', 12345), isNull);
    });
  });
}
