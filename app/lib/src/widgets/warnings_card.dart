import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/validation_issue_labels.dart';
import '../theme/app_spacing.dart';

/// The non-blocking warnings of a dance, such as figures whose beats do not
/// add up to the phrase structure. Shown by the dance editor while it edits,
/// and by the dance detail view for a saved dance (AUTH-12, October behaviour
/// audit), so a mismatch is visible outside the editor, in the same words.
class WarningsCard extends StatelessWidget {
  const WarningsCard({super.key, required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('warnings-card'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.danceEditorWarningsTitle,
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
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
