import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/csv_import_mapping.dart';
import 'package:compendium_app/src/screens/import_csv_mapping.dart'
    show csvTargetLabel;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spreadsheet import's map-columns choices (#2329).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));
  final languages = [de, en];
  final season = CustomFieldDef(
    id: 'f-season',
    key: 'season',
    label: 'Saison',
    type: CustomFieldType.text,
  );

  test('headers in the UI language and in English are pre-mapped', () {
    final mapped = autoMapCsvColumns(
      [
        de.csvColumnTitle, // Titel
        en.csvColumnAuthors, // Authors
        de.csvColumnFigures, // Figuren
        'A2',
        'Saison',
        'Something else',
      ],
      6,
      languages,
      [season],
    );
    expect(mapped, [
      const CsvColumnMapping(CsvColumnTarget.title),
      const CsvColumnMapping(CsvColumnTarget.authors),
      const CsvColumnMapping(CsvColumnTarget.figures),
      const CsvColumnMapping.phrase('A2'),
      const CsvColumnMapping.customField('f-season'),
      CsvColumnMapping.ignore,
    ]);
  });

  test('a header in a language that is neither the UI language nor English '
      'is not guessed', () {
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(autoMapCsvColumns([fr.csvColumnTunes], 1, languages, const []), [
      CsvColumnMapping.ignore,
    ], reason: '"Airs" is French; the UI here is German');
  });

  test('a second column naming the same field starts as Ignore', () {
    expect(autoMapCsvColumns(['Title', 'Titel'], 2, languages, const []), [
      const CsvColumnMapping(CsvColumnTarget.title),
      CsvColumnMapping.ignore,
    ]);
  });

  test('a first row that names a field reads as a header; one of values '
      'does not', () {
    expect(csvRowLooksLikeHeader(['Title', 'x'], languages, const []), isTrue);
    expect(
      csvRowLooksLikeHeader(['Petronella', 'Swing'], languages, const []),
      isFalse,
    );
  });

  test('values read in the UI language and in English', () {
    final vocab = csvValueVocabulary(languages);
    expect(vocab.statuses[csvFold(de.commonYes)], isNull);
    expect(vocab.yes, contains(csvFold(de.commonYes)));
    expect(vocab.yes, contains('yes'));
    expect(vocab.forms.values.toSet(), DanceForm.values.toSet());
    expect(vocab.statuses.values.toSet(), DanceStatus.values.toSet());
  });

  test('levels read by their own label and the localized one; bar counts '
      'read in each language', () {
    final custom = DifficultyLevel(id: 'lvl-x', label: 'Wizard', position: 9);
    final vocab = csvValueVocabulary(languages, levels: [custom]);
    expect(vocab.levels[csvFold('wizard')], 'lvl-x');
    // A built-in level is read by its stored name even in a German-only
    // vocabulary, and by its German name.
    final german = csvValueVocabulary(
      [de],
      levels: [DifficultyLevel.intermediate],
    );
    expect(
      german.levels[csvFold(DifficultyLevel.intermediate.label)],
      DifficultyLevel.intermediateId,
    );
    expect(
      german.levels[csvFold(de.commonDanceLevelIntermediate)],
      DifficultyLevel.intermediateId,
    );
    for (final l10n in languages) {
      for (final halfBars in const [0, 1]) {
        final words = csvFold(
          l10n.danceFigureBars('8', halfBars).replaceAll(RegExp('[0-9]'), ''),
        );
        expect(words, isNotEmpty);
        expect(vocab.barWords, contains(words));
      }
    }
  });

  test('no target takes an author\'s email or location', () {
    // Third-party private details (registry `choreographers.email` and
    // `choreographers.location`, deviceLocal): never a mapping target.
    final private = RegExp(
      'email|e-mail|location|address',
      caseSensitive: false,
    );
    for (final target in CsvColumnTarget.values) {
      expect(target.name, isNot(matches(private)), reason: target.name);
    }
    for (final l10n in [en, de]) {
      for (final choice in csvTargetChoices([season])) {
        final label = csvTargetLabel(l10n, choice, {season.id: season});
        expect(label, isNot(matches(private)), reason: label);
      }
    }
  });
}
