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
      RegExp(r'[Aa]ufgerufen|[Aa]ufrufe?n?\b|aufrufst|[Aa]ufrufzahl|[Aa]nsag'):
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

  // German "Sie" or "Ihre" opening a sentence can mean "they", "it" or
  // "its"; each key where it does is named here, and must still have one.
  // A formal "Sie" opening a sentence in any other key still fails.
  const sentenceInitial = <String, String>{
    'figureTextSheetUnrecognizedSummary': 'Sie: they, it or its',
    'backupExportSubtitle': 'Sie: they, it or its',
    'danceEditorCompoundUnavailable': 'Sie: they, it or its',
    'danceEditorFiguresUnreadable': 'Sie: they, it or its',
    'danceEditorTunesUnreadable': 'Sie: they, it or its',
    'danceEditorUnrecognizedMoveReadOnly': 'Sie: they, it or its',
    'eventRuleAttentionSearchGone': 'Ihre: they, it or its',
    'eventRuleAttentionUnresolvable': 'Ihre: they, it or its',
    'exportCsvDialogMessage': 'Sie: they, it or its',
    'exportVenueContactBody': 'Sie: they, it or its',
    'glossaryCustomDeleteBody': 'Sie: they, it or its',
    'glossaryCustomDeleteUses': 'Sie: they, it or its',
    'importCcTermsFailed': 'Sie: they, it or its',
    'importFileNotText': 'Sie: they, it or its',
    'importReviewReimportWarning': 'Ihre: they, it or its',
    'importUserFiguresNameTaken': 'Ihr: they, it or its',
    'importUserFiguresUseTheirs': 'Ihre: they, it or its',
    'onlineImportVariationDialogLinkWarning': 'Sie: they, it or its',
    'programTemplateSlotRuleSearchGone': 'Ihre: they, it or its',
    'programTemplateSlotRuleSearchUnreadable': 'Ihre: they, it or its',
    'programsFillSearchUnreadable': 'Sie: they, it or its',
    'savedSearchInUseBody': 'Sie: they, it or its',
    'savedSearchUnreadableBody': 'Sie: they, it or its',
    'settingsAboutFontsBody': 'Ihre: they, it or its',
    'settingsSyncNoticeAwaitingDevice': 'Sie: they, it or its',
    'settingsSyncNoticeKeptNewerItems': 'Sie: they, it or its',
    'settingsSyncNoticePeerNotTaking': 'Sie: they, it or its',
    'settingsSyncPairingCompleteFailed': 'Sie: they, it or its',
    'userFigureSwitchConfirmUses': 'Sie: they, it or its',
    'validationOtherFormFigures': 'Sie: they, it or its',
  };

  // Locale -> the words that must not translate what the English names. A
  // "slot" in a move-wording template is a placeholder, not a program slot,
  // so those keys are left out of the slot rule.
  final notWordingSlot = RegExp(r'^(?!dialectEditorMoveWording|wordingIssue)');
  final slot = RegExp(r'\b[Ss]lots?\b');
  final programKey = RegExp(r'^program');
  final terms = <String, List<_Term>>{
    'de': [
      _Term(
        slot,
        RegExp(r'Eintr[aä]g|Pl[aä]tz(?!halter)'),
        'Slot',
        keys: notWordingSlot,
      ),
      _Term(RegExp(r'\b[Ll]evels?\b'), RegExp(r'Stufe'), 'Niveau'),
      _Term(RegExp(r'[Ff]ormations?\b'), RegExp(r'Aufstellung'), 'Formation'),
      _Term(
        RegExp(r'custom field'),
        RegExp(r'eigene[sn]? Feld'),
        'benutzerdefiniertes Feld',
      ),
      _Term(RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Tanzart'), 'Typ'),
    ],
    'da': [
      _Term(slot, RegExp(r'[Pp]lads(?!holder)'), 'slot', keys: notWordingSlot),
      _Term(RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Danseform'), 'type'),
    ],
    'fr': [
      _Term(slot, RegExp(r'[Ee]mplacement'), 'créneau', keys: notWordingSlot),
      // "Étiquette" stays where the English says label.
      _Term(RegExp(r'\b[Tt]ags?\b'), RegExp(r'[ÉéEe]tiquette'), 'tag'),
      _Term(
        RegExp(r'Custom Figures'),
        RegExp(r'vos figures'),
        'figures personnalisées',
      ),
    ],
    'nl': [
      _Term(slot, RegExp(r'\b[Pp]lek'), 'slot', keys: notWordingSlot),
      // userFigureEditorParamNames lists reserved names typed in English.
      _Term(
        RegExp(r'\b[Bb]eats?\b'),
        RegExp(r'\b[Bb]eats?\b'),
        'tellen',
        keys: RegExp(r'^(?!userFigureEditorParamNames$)'),
      ),
      _Term(RegExp(r'custom field'), RegExp(r'eigen veld'), 'aangepast veld'),
      _Term(RegExp(r'\b[Tt]ypes?\b'), RegExp(r'Danssoort'), 'type'),
    ],
    'ja': [
      _Term(slot, RegExp(r'枠'), 'スロット', keys: notWordingSlot),
      // In the program builder a note slot is a ノート, as its buttons say.
      _Term(RegExp(r'\b[Nn]otes?\b'), RegExp(r'メモ'), 'ノート', keys: programKey),
      _Term(RegExp(r'[Ff]ormations?\b'), RegExp(r'隊形'), 'フォーメーション'),
    ],
  };

  // A retired wording each pattern must catch, so none can rot into a
  // pattern that never fires.
  const retiredExamples = <String, List<String>>{
    'de': [
      'Wählen Sie die Tänze',
      'Am häufigsten aufgerufen',
      'Der Ansageverlauf',
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
    'fr': ['Emplacements', '1 étiquette', 'Copier dans vos figures'],
    'nl': ['Plekken', '{beats} beats te veel', 'Nieuw eigen veld', 'Danssoort'],
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
      for (final rule in rules) {
        expect(
          termExamples[locale]!.any(rule.word.hasMatch),
          isTrue,
          reason: '[$locale] no example matches ${rule.word}',
        );
      }
    });
  });

  test('translations keep one form of address and retired wordings out', () {
    final offenders = <String>[];
    retired.forEach((locale, patterns) {
      load(locale).forEach((key, raw) {
        if (key.startsWith('@') || raw is! String) return;
        // Product names keep their straight apostrophe in every language.
        final value = _words(raw).replaceAll("Caller's", 'Caller');
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
      load(locale).forEach((key, raw) {
        if (key.startsWith('@') || raw is! String) return;
        final value = _words(raw);
        final source = en[key];
        if (source is! String) return;
        for (final rule in rules) {
          if (rule.keys.hasMatch(key) &&
              rule.english.hasMatch(source) &&
              rule.word.hasMatch(value)) {
            offenders.add('[$locale] $key: "$value" — use "${rule.use}"');
          }
        }
      });
    });
    expect(offenders, isEmpty);
  });
}

/// [value] without ICU argument names and select or plural keywords
/// (`{beats}`, `beats{`), which are code, not words a person reads.
String _words(String value) =>
    value.replaceAll(RegExp(r'\{\s*\w+|\b\w+\{'), '{');

/// Whether [index] in [value] starts the text or follows a sentence end.
bool _opensSentence(String value, int index) {
  final before = value.substring(0, index).trimRight();
  return before.isEmpty || RegExp(r'[.!?:„"“{]$').hasMatch(before);
}

/// Where the English matches [english] (in a key matching [keys]), the
/// translation must not match [word]; [use] is the word that replaces it.
class _Term {
  _Term(this.english, this.word, this.use, {RegExp? keys})
    : keys = keys ?? RegExp('');

  final RegExp english;
  final RegExp word;
  final String use;
  final RegExp keys;
}
