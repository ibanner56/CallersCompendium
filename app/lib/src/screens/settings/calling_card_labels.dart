import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../export/calling_card_layout.dart';

/// A side length as the user reads it: no trailing zeros, at most two
/// decimals, in the UI locale's decimal style.
String callingCardSideLabel(AppLocalizations l10n, double value) =>
    NumberFormat('0.##', l10n.localeName).format(value);

/// A card measurement, short side first: "3 × 5 in", "105 × 148 mm".
String callingCardSizeLabel(AppLocalizations l10n, CallingCardSize size) {
  final short = callingCardSideLabel(
    l10n,
    size.width < size.height ? size.width : size.height,
  );
  final long = callingCardSideLabel(
    l10n,
    size.width < size.height ? size.height : size.width,
  );
  return switch (size.unit) {
    CallingCardUnit.inch => l10n.settingsCallingCardsSizeInches(short, long),
    CallingCardUnit.millimetre => l10n.settingsCallingCardsSizeMillimetres(
      short,
      long,
    ),
  };
}

/// The name of a preset from [kCallingCardSizePresets].
String callingCardPresetLabel(AppLocalizations l10n, String id) {
  final size = kCallingCardSizePresets[id]!;
  final measurement = callingCardSizeLabel(l10n, size);
  return switch (id) {
    'a6' => l10n.settingsCallingCardsSizeIsoA('A6', measurement),
    'a7' => l10n.settingsCallingCardsSizeIsoA('A7', measurement),
    _ => l10n.settingsCallingCardsSizeIndexCard(measurement),
  };
}

/// The sentence the layout editor shows for [issue].
String callingCardIssueMessage(
  AppLocalizations l10n,
  CallingCardLayoutIssue issue,
) => switch (issue.kind) {
  CallingCardIssueKind.unknownBlock => l10n.callingCardIssueUnknownBlock(
    issue.line,
    issue.subject,
  ),
  CallingCardIssueKind.unknownOption => l10n.callingCardIssueUnknownOption(
    issue.line,
    issue.subject,
  ),
  CallingCardIssueKind.badValue => l10n.callingCardIssueBadValue(
    issue.line,
    issue.subject,
    issue.value,
  ),
  CallingCardIssueKind.unclosedQuote => l10n.callingCardIssueUnclosedQuote(
    issue.line,
  ),
  CallingCardIssueKind.missingText => l10n.callingCardIssueMissingText(
    issue.line,
  ),
  CallingCardIssueKind.cardNotAlone => l10n.callingCardIssueCardNotAlone(
    issue.line,
  ),
  CallingCardIssueKind.emptyBlock => l10n.callingCardIssueEmptyBlock(
    issue.line,
  ),
};

/// The name of an example from [kCallingCardLayoutExamples].
String callingCardExampleLabel(AppLocalizations l10n, String id) =>
    switch (id) {
      'bigPrint' => l10n.callingCardExampleBigPrint,
      'program' => l10n.callingCardExampleProgram,
      'teaching' => l10n.callingCardExampleTeaching,
      _ => l10n.callingCardExampleClassic,
    };
