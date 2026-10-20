import 'dart:ui';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/wording_issue_labels.dart';

/// Every wording issue has a message in every language, and the message
/// quotes the words it is about: a caller fixes a condition from the message
/// alone.
void main() {
  // A value for every key a message may quote, each one distinct, so a
  // message that drops the words it is about is caught.
  const data = {
    'found': 'FOUND',
    'name': 'NAME',
    'names': 'NAMES',
    'values': 'VALUES',
    'suggestion': 'SUGGESTION',
    'fix': 'FIX',
    'word': 'WORD',
    'op': 'OP',
    'example': 'EXAMPLE',
    'min': 'MIN',
    'max': 'MAX',
    'context': 'CONTEXT',
    'readingA': 'READING_A',
    'readingB': 'READING_B',
    'phrase': 'PHRASE',
    'condition': 'CONDITION',
    'before': 'BEFORE',
    'fixA': 'FIX_A',
    'fixB': 'FIX_B',
  };

  // What each message must quote: the words that say where, and the fix.
  const quoted = <WordingIssueCode, List<String>>{
    WordingIssueCode.unclosedGroup: ['CONTEXT'],
    WordingIssueCode.strayCloseBracket: ['CONTEXT'],
    WordingIssueCode.unclosedSlot: ['CONTEXT', 'EXAMPLE'],
    WordingIssueCode.strayCloseBrace: ['CONTEXT'],
    WordingIssueCode.badSlot: ['FOUND', 'FIX'],
    WordingIssueCode.conditionInBraces: ['FOUND', 'FIX'],
    WordingIssueCode.tooLongStored: ['MAX'],
    WordingIssueCode.tooLongTyped: ['MAX'],
    WordingIssueCode.tooDeep: ['MAX'],
    WordingIssueCode.missingCondition: ['WORD', 'EXAMPLE'],
    WordingIssueCode.missingThen: ['CONDITION'],
    WordingIssueCode.colonForThen: ['CONDITION'],
    WordingIssueCode.unknownName: ['FOUND', 'SUGGESTION', 'NAMES'],
    WordingIssueCode.unknownNameAfterIf: ['FOUND', 'SUGGESTION', 'NAMES'],
    WordingIssueCode.nameInBraces: ['NAME', 'FOUND'],
    WordingIssueCode.isntForIsNot: ['FOUND', 'FIX'],
    WordingIssueCode.symbolForWord: ['WORD', 'FOUND', 'FIX'],
    WordingIssueCode.quotedValue: ['FIX'],
    WordingIssueCode.unknownValue: ['FOUND', 'NAME', 'SUGGESTION', 'VALUES'],
    WordingIssueCode.expectedValue: ['BEFORE', 'NAME', 'EXAMPLE', 'VALUES'],
    WordingIssueCode.listNeedsParens: ['FIX'],
    WordingIssueCode.oneOfForIsIn: ['WORD', 'FOUND', 'FIX'],
    WordingIssueCode.emptyList: ['EXAMPLE'],
    WordingIssueCode.unclosedParen: ['CONTEXT', 'BEFORE'],
    WordingIssueCode.strayCloseParen: ['CONTEXT'],
    WordingIssueCode.emptyParens: [],
    WordingIssueCode.expectedConnective: ['BEFORE', 'FOUND'],
    WordingIssueCode.expectedConnectiveList: ['BEFORE', 'FIX'],
    WordingIssueCode.expectedListSeparator: ['BEFORE', 'FOUND'],
    WordingIssueCode.valueAfterConnective: ['FOUND', 'WORD', 'FIX_A', 'FIX_B'],
    WordingIssueCode.mixedAndOr: ['FOUND', 'FIX_A', 'FIX_B'],
    WordingIssueCode.flagCompare: ['NAME'],
    WordingIssueCode.presenceOnly: ['NAME'],
    WordingIssueCode.notANumber: ['NAME', 'OP'],
    WordingIssueCode.expectedNumber: ['OP', 'EXAMPLE', 'FOUND'],
    WordingIssueCode.numberOutOfRange: ['NAME', 'MIN', 'MAX', 'FOUND'],
    WordingIssueCode.numberNotWhole: ['NAME', 'FOUND'],
    WordingIssueCode.numberNotQuarter: ['NAME', 'FOUND'],
    WordingIssueCode.negatedComparison: ['FIX', 'FOUND'],
    WordingIssueCode.ambiguous: ['FOUND', 'READING_A', 'READING_B'],
    WordingIssueCode.secondElse: [],
    WordingIssueCode.nothingToTest: [],
    WordingIssueCode.elseAfterWord: ['PHRASE'],
    WordingIssueCode.otherwiseWord: ['FOUND'],
    WordingIssueCode.emptyMeansNoValue: ['NAME', 'FIX'],
  };

  test('every code says what each message quotes', () {
    expect(quoted.keys.toSet(), WordingIssueCode.values.toSet());
  });

  for (final locale in AppLocalizations.supportedLocales) {
    test('every message in ${locale.toLanguageTag()} quotes its words', () {
      final l10n = lookupAppLocalizations(Locale(locale.languageCode));
      for (final code in WordingIssueCode.values) {
        final message = wordingIssueMessage(
          l10n,
          WordingIssue(code, 0, 0, data),
        );
        expect(message.trim(), isNotEmpty, reason: '$code');
        for (final words in quoted[code]!) {
          expect(message, contains(words), reason: '$locale $code: $message');
        }
      }
    });
  }

  test('a message without a suggestion still names every choice', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final noSuggestion = Map.of(data)..remove('suggestion');
    for (final code in [
      WordingIssueCode.unknownName,
      WordingIssueCode.unknownNameAfterIf,
      WordingIssueCode.unknownValue,
    ]) {
      final message = wordingIssueMessage(
        en,
        WordingIssue(code, 0, 0, noSuggestion),
      );
      expect(message, isNot(contains('Did you mean')), reason: '$code');
      expect(
        message,
        contains(code == WordingIssueCode.unknownValue ? 'VALUES' : 'NAMES'),
      );
    }
  });
}
