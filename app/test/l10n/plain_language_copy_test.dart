import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the plain-language copy pass (UX3-1, UX3-3, UX3-6 plurals): the
/// strings a caller reads must not name developer concepts, and the three
/// "(s)" counters must be real ICU plurals in every shipped language.
///
/// Reads the ARBs directly, so it covers all six locales without wiring a
/// delegate for each.
const _locales = ['en', 'da', 'de', 'fr', 'ja', 'nl'];

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final en = _arb('en');

  group('English strings read in plain language', () {
    // key prefix -> terms a caller should not meet there.
    final banned = <String, List<Pattern>>{
      'syncReview': [RegExp('peer', caseSensitive: false), 'sync pass'],
      'importIssue': ['metadata-only', 'taxonomy', RegExp(r'\bstub\b')],
      'importGap': ['parse', 'verbatim'],
      'customFields': ['machine key', 'Boolean'],
      'settingsUpdates': ['sha256'],
      'updateDownloadFailure': ['sha256'],
      'reparse': ['parse', 're-parse'],
      'settingsGeneralReparse': ['parse'],
    };
    banned.forEach((prefix, terms) {
      test('$prefix* avoids ${terms.join(', ')}', () {
        final hits = <String>[];
        for (final entry in en.entries) {
          final value = entry.value;
          if (!entry.key.startsWith(prefix) || value is! String) continue;
          for (final term in terms) {
            if (value.contains(term)) hits.add('${entry.key}: $term');
          }
        }
        expect(hits, isEmpty);
      });
    });

    test('the startup error screen no longer has an error-type string', () {
      for (final locale in _locales) {
        expect(
          _arb(locale).containsKey('appBootstrapErrorType'),
          isFalse,
          reason: locale,
        );
      }
    });

    test('import review says title and author, as the matcher does', () {
      for (final key in [
        'onlineImportVariationDialogBody',
        'importReviewVariationBody',
      ]) {
        expect(en[key], contains('title and author match'), reason: key);
        expect(en[key], isNot(contains('caller')), reason: key);
      }
    });
  });

  group('every locale', () {
    for (final locale in _locales) {
      final arb = _arb(locale);

      test(
        '$locale: the quota button is named like the setting it turns on',
        () {
          expect(
            arb['settingsSyncQuotaExcludeImports'],
            arb['settingsSyncExcludeImportsTitle'],
          );
        },
      );

      test("$locale: the re-import source spells Caller's Compendium", () {
        expect(
          arb['danceReimportJson'],
          matches(RegExp('Caller.s Compendium')),
        );
      });

      test('$locale: the counters carry no "(s)" and are ICU plurals', () {
        for (final key in [
          'importReviewProgramNotes',
          'importReviewRecordsFailed',
          'importReviewBatchErrors',
        ]) {
          final value = arb[key] as String;
          expect(value, isNot(contains('(s)')), reason: key);
          expect(value, startsWith('{count, plural,'), reason: key);
        }
      });
    }

    test('en: the counters differ between one and many', () {
      for (final key in [
        'importReviewProgramNotes',
        'importReviewRecordsFailed',
        'importReviewBatchErrors',
      ]) {
        final value = en[key] as String;
        final one = RegExp(
          r'=1\{([^}]*(?:\{count\}[^}]*)?)\}',
        ).firstMatch(value);
        final other = RegExp(r'other\{(.*)\}\}$').firstMatch(value);
        expect(one, isNotNull, reason: key);
        expect(other, isNotNull, reason: key);
        expect(one!.group(1), isNot(other!.group(1)), reason: key);
      }
    });
  });
}
