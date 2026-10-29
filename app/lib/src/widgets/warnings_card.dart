import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/validation_issue_labels.dart';
import 'notice_card.dart';

/// The non-blocking warnings of a dance, such as figures whose beats do not
/// add up to the phrase structure. Shown by the dance editor while it edits,
/// and by the dance detail view for a saved dance (AUTH-12, October behaviour
/// audit), so a mismatch is visible outside the editor, in the same words.
class WarningsCard extends StatelessWidget {
  const WarningsCard({super.key, required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NoticeCard(
      key: const ValueKey('warnings-card'),
      kind: NoticeKind.warning,
      title: l10n.danceEditorWarningsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Padding(
              // intentional: 2px optical inset, below the 4px AppSpacing grid
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${validationIssueMessage(l10n, warning)}'),
            ),
        ],
      ),
    );
  }
}
