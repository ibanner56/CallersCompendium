import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One form of address, and one word per thing, in each translation.
///
/// The English template has its own guard (`one_name_each_test.dart`); this
/// one holds the translations to the choices recorded in
/// `tools/ci/i18n_glossary.json` (`register` and `terms`), so a later
/// translation can't bring back a retired wording unnoticed.
///
/// German addresses the user as "du" (maintainer decision, 2026-11-27); Dutch
/// as "je", the majority voice before the audit that found three "u" strings.
void main() {
  Map<String, dynamic> load(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;

  // Locale -> pattern -> the wording that replaces it. Matched,
  // case-sensitively, against every value.
  final retired = <String, Map<RegExp, String>>{
    'de': {
      // Formal address. Capitalised, so "sie" (they) and "ihr" (her, you
      // all) mid-sentence don't match; see [sentenceInitial] for the start.
      RegExp(r'\b(Sie|Ihnen|Ihr|Ihre|Ihrem|Ihren|Ihrer|Ihres)\b'):
          'du / dich / dir / dein',
      // To call a dance is "callen" (gecallt), as Settings already said;
      // "aufrufen" reads as opening a page.
      RegExp(r'aufgerufen|[Aa]ufrufe?n?\b|aufrufst|[Aa]ufrufzahl'):
          'callen / gecallt',
      RegExp(r'\bBeats?\b'): 'Schlag / Schläge',
      RegExp(r'Perform eines'): 'im Perform-Modus',
    },
    'nl': {
      RegExp(r'\b[Uu]w?\b'): 'je / jouw',
      // Bellen is to telephone; a caller "callt" a dance.
      RegExp(r'gebeld|\b[Bb]el(t|len)?\b'): 'callen / gecalld',
      RegExp(r'\bgecald\b'): 'gecalld',
      RegExp(r'niet-herkend figuur'): 'niet-herkende figuur',
    },
    'da': {RegExp(r'Kaldsnotes'): 'Kaldsnoter'},
    'fr': {
      // One apostrophe: the typographic one most strings already used.
      RegExp(r"[A-Za-zÀ-ÿ]'[A-Za-zÀ-ÿ]"): '’',
      RegExp(r'liste de sets'): 'liste de danses',
    },
    'ja': {RegExp(r'休憩'): 'ブレイク'},
  };

  // German "Sie" or "Ihr" opening a sentence can mean "they" or "her"; those
  // keys are named here with what the word means, and must still have one.
  const sentenceInitial = <String, String>{};

  // Locale -> (English pattern, locale pattern, the word to use): where the
  // English names the thing, the translation must not use the retired word.
  final terms = <String, List<(RegExp, RegExp, String)>>{
    'de': [
      (RegExp(r'\b[Ss]lots?\b'), RegExp(r'Eintr[aä]g|Pl[aä]tz'), 'Slot'),
      (RegExp(r'\b[Ll]evels?\b'), RegExp(r'Stufe'), 'Niveau'),
      (RegExp(r'[Ff]ormations?\b'), RegExp(r'Aufstellung'), 'Formation'),
      (RegExp(r'custom field'), RegExp(r'eigene[sn]? Feld'), 'benutzerdefiniertes Feld'),
      (RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Tanzart'), 'Typ'),
    ],
    'da': [
      (RegExp(r'\b[Ss]lots?\b'), RegExp(r'[Pp]lads'), 'slot'),
      (RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Danseform'), 'type'),
    ],
    'fr': [
      (RegExp(r'\b[Ss]lots?\b'), RegExp(r'[Ee]mplacement'), 'créneau'),
      (RegExp(r'Custom Figures'), RegExp(r'vos figures'), 'figures personnalisées'),
    ],
    'nl': [
      (RegExp(r'\b[Ss]lots?\b'), RegExp(r'\b[Pp]lek'), 'slot'),
      (RegExp(r'\b[Bb]eats?\b'), RegExp(r'\b[Tt]ellen\b'), 'beats'),
      (RegExp(r'custom field'), RegExp(r'eigen veld'), 'aangepast veld'),
      (RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Danssoort'), 'type'),
    ],
    'ja': [
      (RegExp(r'\b[Ss]lots?\b'), RegExp(r'枠'), 'スロット'),
      (RegExp(r'\b[Nn]otes?\b'), RegExp(r'メモ'), 'ノート'),
      (RegExp(r'[Ff]ormations?\b'), RegExp(r'隊形'), 'フォーメーション'),
    ],
  };

  // A retired wording each pattern must catch, so none can rot into a
  // pattern that never fires.
  const retiredExamples = <String, List<String>>{
    'de': [
      'Wählen Sie die Tänze',
      'Am häufigsten aufgerufen',
      '{actual} Beats',
      'Timer beim Perform eines einzelnen Tanzes anzeigen',
    ],
    'nl': [
      'Auteurs die u bij een dans vermeldt',
      'Vaakst gebeld',
      'als hij wordt gecald',
      '1 niet-herkend figuur nu gelezen',
    ],
    'da': ['Kaldsnotes'],
    'fr': ["s'ajoutent", 'Partager la liste de sets'],
    'ja': ['休憩を挿入'],
  };
  const termExamples = <String, List<String>>{
    'de': [
      'Einträge',
      'Die Stufe {name}',
      'Ausgewogene Aufstellungen',
      'Neues eigenes Feld',
      'Tanzart',
    ],
    'da': ['Pladser', 'Danseform'],
    'fr': ['Emplacements', 'Copier dans vos figures'],
    'nl': ['Plekken', 'Tellen per maat', 'Nieuw eigen veld', 'Danssoort'],
    'ja': ['枠', 'メモ', '隊形のバランス'],
  };

  test('every retired pattern matches a known retired wording', () {
    retired.forEach((locale, patterns) {
      for (final pattern in patterns.keys) {
        expect(
          retiredExamples[locale]!.any(pattern.hasMatch),
          isTrue,
          reason: '[$locale] no example matches $pattern',
        );
      }
    });
    terms.forEach((locale, rules) {
      for (final (_, pattern, _) in rules) {
        expect(
          termExamples[locale]!.any(pattern.hasMatch),
          isTrue,
          reason: '[$locale] no example matches $pattern',
        );
      }
    });
  });

  test('translations keep one form of address and retired wordings out', () {
    final offenders = <String>[];
    retired.forEach((locale, patterns) {
      load(locale).forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        patterns.forEach((pattern, use) {
          for (final m in pattern.allMatches(value)) {
            if (locale == 'de' &&
                sentenceInitial.containsKey(key) &&
                _opensSentence(value, m.start)) {
              continue;
            }
            offenders.add('[$locale] $key: "$value" — use "$use"');
            break;
          }
        });
      });
    });
    expect(offenders, isEmpty);
  });

  test('every sentenceInitial key still opens a sentence with Sie or Ihr', () {
    final de = load('de');
    final pattern = retired['de']!.keys.first;
    for (final key in sentenceInitial.keys) {
      final value = de[key] as String;
      expect(
        pattern.allMatches(value).any((m) => _opensSentence(value, m.start)),
        isTrue,
        reason: '$key no longer needs its exception: drop it',
      );
    }
  });

  test('translations use one word for each thing the English names', () {
    final en = load('en');
    final offenders = <String>[];
    terms.forEach((locale, rules) {
      load(locale).forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        final source = en[key];
        if (source is! String) return;
        for (final (english, word, use) in rules) {
          if (english.hasMatch(source) && word.hasMatch(value)) {
            offenders.add('[$locale] $key: "$value" — use "$use"');
          }
        }
      });
    });
    expect(offenders, isEmpty);
  });
}

/// Whether [index] in [value] starts the text or follows a sentence end.
bool _opensSentence(String value, int index) {
  final before = value.substring(0, index).trimRight();
  return before.isEmpty || RegExp(r'[.!?:„"“]$').hasMatch(before);
}
