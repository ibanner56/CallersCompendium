import 'dart:ui' show Locale;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/export/export_labels_l10n.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// An English dance's named phrases print with the locale's punctuation
/// (ADR-006 leftovers): Japanese uses full-width parentheses and 、.
void main() {
  String phraseIn(String locale) {
    final l10n = lookupAppLocalizations(Locale(locale));
    return phraseStructureText(
      PhraseStructure.parse('A:2*4*2 + B:1*8*2'),
      danceExportLabels(l10n),
    );
  }

  test('English prints AAB (A 4 bars, B 8 bars)', () {
    expect(phraseIn('en'), 'AAB (A 4 bars, B 8 bars)');
  });

  test('Japanese uses full-width parentheses and the ideographic comma', () {
    expect(phraseIn('ja'), 'AAB（A 4小節、B 8小節）');
  });

  test('every other locale keeps the ASCII parentheses and comma', () {
    for (final locale in ['da', 'de', 'fr', 'nl']) {
      expect(
        phraseIn(locale),
        matches(RegExp(r'^AAB \(A 4 [^,()]+, B 8 [^,()]+\)$')),
        reason: locale,
      );
    }
  });
}
