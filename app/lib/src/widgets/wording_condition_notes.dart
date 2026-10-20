import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/wording_issue_labels.dart';

/// The notes under a wording template's field: how to word it differently in
/// some cases, what a condition there may test, and the first reason the
/// wording as typed can't be saved, then its warnings. Each message says what
/// is wrong and how to fix it ([wordingIssueMessage]).
///
/// Shared by the dialect editor and a figure of your own's editor, so a
/// condition reads and fails the same way in both.
class WordingConditionNotes extends StatelessWidget {
  const WordingConditionNotes({
    required this.vocabulary,
    required this.check,
    required this.errorKey,
    this.showHelp = true,
    super.key,
  });

  /// Whether to show how to write a condition, and what it may test: not
  /// when nothing can be tested, as for a figure not on this device.
  final bool showHelp;

  /// What the wording may test.
  final WordingVocabulary vocabulary;

  /// The wording as typed, read against [vocabulary].
  final WordingCheck check;

  /// The key of the error's text, which tests find it by.
  final Key errorKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = check.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHelp) ...[
          Text(
            l10n.wordingConditionsHelp(wordingConditionExample(vocabulary)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.wordingConditionsNames(
              wordingTestableNames(vocabulary).join(', '),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (error != null)
          Text(
            wordingIssueMessage(l10n, error),
            key: errorKey,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        for (final warning in check.warnings)
          Text(
            wordingIssueMessage(l10n, warning),
            style: TextStyle(color: theme.colorScheme.tertiary),
          ),
      ],
    );
  }
}
