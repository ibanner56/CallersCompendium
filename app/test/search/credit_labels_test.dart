import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/l10n/app_localizations_ja.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();

  group('authorsWithYearLabel', () {
    test('names and year', () {
      expect(
        authorsWithYearLabel(en, ['Pat Shaw', 'Tom Cook'], PartialDate(1951)),
        'Pat Shaw, Tom Cook (1951)',
      );
    });
    test('shows only the year of a full date', () {
      expect(
        authorsWithYearLabel(en, ['Pat Shaw'], PartialDate(1951, 3, 4)),
        'Pat Shaw (1951)',
      );
    });
    test('names only', () {
      expect(authorsWithYearLabel(en, ['Pat Shaw'], null), 'Pat Shaw');
    });
    test('year only', () {
      expect(authorsWithYearLabel(en, [], PartialDate(1651)), 'Composed 1651');
    });
    test('neither', () {
      expect(authorsWithYearLabel(en, [], null), isNull);
    });
    test('a year is written as digits, not a grouped number', () {
      expect(
        authorsWithYearLabel(en, ['A'], PartialDate(1234)),
        isNot(contains(',2')),
      );
    });
  });

  group('interpretersWithYearLabel', () {
    test('names and year', () {
      expect(
        interpretersWithYearLabel(en, ['Cecil Sharp'], PartialDate(1916)),
        'Interpreted by Cecil Sharp (1916)',
      );
    });
    test('names only', () {
      expect(
        interpretersWithYearLabel(en, ['Cecil Sharp'], null),
        'Interpreted by Cecil Sharp',
      );
    });
    test('year only', () {
      expect(
        interpretersWithYearLabel(en, [], PartialDate(1916)),
        'Interpreted 1916',
      );
    });
    test('neither', () {
      expect(interpretersWithYearLabel(en, [], null), isNull);
    });
    test('Japanese uses full-width parentheses', () {
      expect(
        interpretersWithYearLabel(AppLocalizationsJa(), [
          'Cecil Sharp',
        ], PartialDate(1916)),
        '解釈：Cecil Sharp（1916年）',
      );
    });
  });
}
