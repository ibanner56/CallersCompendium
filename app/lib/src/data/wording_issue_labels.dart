import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// Localized messages for a wording template's [WordingIssue]s
/// (`wording_conditions.dart`): what is wrong, quoting the words it is about,
/// and how to fix it, so a caller can mend a condition from the message alone.
///
/// Every [WordingIssueCode] has its own message here; the switch is
/// exhaustive, so a new code cannot ship without one. The words of a
/// condition (`if`, `then`, `else`, `is not`, …) are the language's own and
/// stay as written in every locale.
String wordingIssueMessage(AppLocalizations l10n, WordingIssue issue) {
  String d(String key) => issue.data[key] ?? '';
  final suggestion = issue.data['suggestion'];
  return switch (issue.code) {
    WordingIssueCode.unclosedGroup => l10n.wordingIssueUnclosedGroup(
      d('context'),
    ),
    WordingIssueCode.strayCloseBracket => l10n.wordingIssueStrayCloseBracket(
      d('context'),
    ),
    WordingIssueCode.unclosedSlot => l10n.wordingIssueUnclosedSlot(
      '{',
      '}',
      d('context'),
      d('example'),
    ),
    WordingIssueCode.strayCloseBrace => l10n.wordingIssueStrayCloseBrace(
      '{',
      '}',
      d('context'),
    ),
    WordingIssueCode.badSlot => l10n.wordingIssueBadSlot(d('found'), d('fix')),
    WordingIssueCode.conditionInBraces => l10n.wordingIssueConditionInBraces(
      d('found'),
      d('fix'),
    ),
    WordingIssueCode.tooLongStored => l10n.wordingIssueTooLongStored(d('max')),
    WordingIssueCode.tooLongTyped => l10n.wordingIssueTooLongTyped(d('max')),
    WordingIssueCode.tooDeep => l10n.wordingIssueTooDeep(d('max')),
    WordingIssueCode.missingCondition => l10n.wordingIssueMissingCondition(
      d('word'),
      d('example'),
    ),
    WordingIssueCode.missingThen => l10n.wordingIssueMissingThen(
      d('condition'),
    ),
    WordingIssueCode.colonForThen => l10n.wordingIssueColonForThen(
      d('condition'),
    ),
    WordingIssueCode.unknownName =>
      suggestion == null
          ? l10n.wordingIssueUnknownName(d('found'), d('names'))
          : l10n.wordingIssueUnknownNameSuggest(
              d('found'),
              suggestion,
              d('names'),
            ),
    WordingIssueCode.unknownNameAfterIf =>
      suggestion == null
          ? l10n.wordingIssueUnknownNameAfterIf(d('found'), d('names'))
          : l10n.wordingIssueUnknownNameAfterIfSuggest(
              d('found'),
              suggestion,
              d('names'),
            ),
    WordingIssueCode.nameInBraces => l10n.wordingIssueNameInBraces(
      d('name'),
      d('found'),
    ),
    WordingIssueCode.isntForIsNot => l10n.wordingIssueIsntForIsNot(
      d('found'),
      d('fix'),
    ),
    WordingIssueCode.symbolForWord => l10n.wordingIssueSymbolForWord(
      d('word'),
      d('found'),
      d('fix'),
    ),
    WordingIssueCode.quotedValue => l10n.wordingIssueQuotedValue(d('fix')),
    WordingIssueCode.unknownValue =>
      suggestion == null
          ? l10n.wordingIssueUnknownValue(d('found'), d('name'), d('values'))
          : l10n.wordingIssueUnknownValueSuggest(
              d('found'),
              d('name'),
              suggestion,
              d('values'),
            ),
    WordingIssueCode.expectedValue => l10n.wordingIssueExpectedValue(
      d('before'),
      d('name'),
      d('example'),
      d('values'),
    ),
    WordingIssueCode.listNeedsParens => l10n.wordingIssueListNeedsParens(
      d('fix'),
    ),
    WordingIssueCode.oneOfForIsIn => l10n.wordingIssueOneOfForIsIn(
      d('word'),
      d('found'),
      d('fix'),
    ),
    WordingIssueCode.emptyList => l10n.wordingIssueEmptyList(d('example')),
    WordingIssueCode.unclosedParen => l10n.wordingIssueUnclosedParen(
      d('context'),
      d('before'),
    ),
    WordingIssueCode.strayCloseParen => l10n.wordingIssueStrayCloseParen(
      d('context'),
    ),
    WordingIssueCode.emptyParens => l10n.wordingIssueEmptyParens,
    WordingIssueCode.expectedConnective =>
      issue.data['close'] == null
          ? l10n.wordingIssueExpectedConnective(d('before'), d('found'))
          : l10n.wordingIssueExpectedConnectiveInParens(
              d('before'),
              d('found'),
            ),
    WordingIssueCode.expectedConnectiveList =>
      l10n.wordingIssueExpectedConnectiveList(d('before'), d('fix')),
    WordingIssueCode.expectedListSeparator =>
      l10n.wordingIssueExpectedListSeparator(d('before'), d('found')),
    WordingIssueCode.valueAfterConnective =>
      l10n.wordingIssueValueAfterConnective(
        d('found'),
        d('word'),
        d('fixA'),
        d('fixB'),
      ),
    WordingIssueCode.mixedAndOr => l10n.wordingIssueMixedAndOr(
      d('found'),
      d('fixA'),
      d('fixB'),
    ),
    WordingIssueCode.flagCompare => l10n.wordingIssueFlagCompare(d('name')),
    WordingIssueCode.presenceOnly => l10n.wordingIssuePresenceOnly(d('name')),
    WordingIssueCode.notANumber => l10n.wordingIssueNotANumber(
      d('name'),
      d('op'),
    ),
    WordingIssueCode.expectedNumber => l10n.wordingIssueExpectedNumber(
      d('op'),
      d('example'),
      d('found'),
    ),
    WordingIssueCode.numberOutOfRange => l10n.wordingIssueNumberOutOfRange(
      d('name'),
      d('min'),
      d('max'),
      d('found'),
    ),
    WordingIssueCode.numberNotWhole => l10n.wordingIssueNumberNotWhole(
      d('name'),
      d('found'),
    ),
    WordingIssueCode.numberNotQuarter => l10n.wordingIssueNumberNotQuarter(
      d('name'),
      d('found'),
    ),
    WordingIssueCode.negatedComparison => l10n.wordingIssueNegatedComparison(
      d('fix'),
      d('found'),
    ),
    WordingIssueCode.ambiguous => l10n.wordingIssueAmbiguous(
      d('found'),
      d('readingA'),
      d('readingB'),
    ),
    WordingIssueCode.secondElse => l10n.wordingIssueSecondElse,
    WordingIssueCode.nothingToTest => l10n.wordingIssueNothingToTest,
    WordingIssueCode.elseAfterWord => l10n.wordingIssueElseAfterWord(
      d('phrase'),
    ),
    WordingIssueCode.otherwiseWord => l10n.wordingIssueOtherwiseWord(
      d('found'),
    ),
    WordingIssueCode.emptyMeansNoValue => l10n.wordingIssueEmptyMeansNoValue(
      d('name'),
      d('fix'),
    ),
  };
}
