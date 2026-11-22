import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/export_labels_l10n.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A printed or shared card or set list puts the locale's punctuation between
/// a field's label and its value: Japanese uses the full-width colon, with no
/// space after it.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  List<String> danceLines(String locale) {
    final l10n = lookupAppLocalizations(Locale(locale));
    return danceToPlainText(
      Dance(
        id: 'd',
        title: 'Title',
        form: DanceForm.ecd,
        phraseStructure: 'A:2*4*2 + B:1*8*2',
        hook: 'Hook text',
        callingNotes: 'Notes text',
        createdAt: now,
        updatedAt: now,
      ),
      dialect: Dialect.canonical,
      authorNames: const [],
      formationLabel: 'F',
      statusLabel: 'S',
      labels: danceExportLabels(l10n),
      fields: DanceShareField.values.toSet(),
    ).split('\n');
  }

  List<String> programLines(String locale) {
    final l10n = lookupAppLocalizations(Locale(locale));
    return programToPlainText(
      Program(
        id: 'p',
        title: 'Program',
        band: 'Band name',
        slots: const [],
        createdAt: now,
        updatedAt: now,
      ),
      titleFor: (_) => null,
      labels: programExportLabels(l10n),
    ).split('\n');
  }

  test('English keeps the colon and space', () {
    final lines = danceLines('en');
    expect(lines, contains('Phrase: AAB (A 4 bars, B 8 bars)'));
    expect(lines, contains('Formation: F'));
    expect(lines, contains('Hook: Hook text'));
    expect(lines, contains('Calling notes:'));
    expect(programLines('en'), contains('Band: Band name'));
  });

  test('Japanese uses the full-width colon, with no space', () {
    final lines = danceLines('ja');
    expect(lines, contains('フレーズ：AAB（A 4小節、B 8小節）'));
    expect(lines, contains('フォーメーション：F'));
    expect(lines, contains('フック：Hook text'));
    expect(lines, contains('コーリングノート：'));
    expect(programLines('ja'), contains('バンド：Band name'));
    expect(
      [...lines, ...programLines('ja')].where((l) => l.contains(': ')),
      isEmpty,
      reason: 'no label keeps an ASCII colon',
    );
  });

  test('French puts a no-break space before the colon', () {
    final lines = danceLines('fr');
    expect(lines, contains('Formation\u00a0: F'));
    expect(lines, contains('Notes d’appel\u00a0:'));
    expect(programLines('fr'), contains('Orchestre\u00a0: Band name'));
  });

  test('Danish, German and Dutch keep the colon and space', () {
    for (final locale in ['da', 'de', 'nl']) {
      final label = lookupAppLocalizations(Locale(locale)).exportLabelFormation;
      expect(danceLines(locale), contains('$label: F'), reason: locale);
    }
  });
}
