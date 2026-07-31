import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Renders a computed [FigureDiffResult] (issue #686) as an inline
/// added/removed figure-line diff, grouped by phrase label where one is
/// available.
///
/// Purely presentational and Flutter-only — the comparison itself
/// ([diffFigures]) is Flutter-free and lives in `compendium_core`; this widget
/// just lays out [FigureDiffResult.entries] plus the truncation footer
/// ([FigureDiffResult.truncated] / [FigureDiffResult.omittedCount]) so a
/// hostile/huge import can never make this widget lay out an unbounded
/// number of lines (both caps — [kMaxFiguresForDiff] and
/// [kMaxFigureDiffLines] — are enforced by the core engine, not here).
///
/// Callers should not render this at all when [FigureDiffResult.identical] is
/// true — there is nothing to show (see [ImportReviewScreen]'s usage).
class FigureDiffView extends StatelessWidget {
  const FigureDiffView({super.key, required this.result});

  final FigureDiffResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grouped = _groupByPhrase(result.entries);
    return Column(
      key: const ValueKey('figure-diff-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final group in grouped) ...[
          if (group.phraseLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                group.phraseLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          for (final entry in group.entries) _buildLine(context, entry),
        ],
        if (result.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.importReviewVariationMoreDifferences(result.omittedCount),
              key: const ValueKey('figure-diff-truncated'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLine(BuildContext context, FigureDiffEntry entry) {
    final theme = Theme.of(context);
    final added = entry.kind == FigureDiffKind.added;
    // Color is never the only signal (accessibility): the leading glyph
    // (+/−) and a semantic label carry the same information for
    // screen-reader/high-contrast users.
    final color = added ? Colors.green.shade700 : Colors.red.shade700;
    final glyph = added ? '+' : '\u2212';
    final label = added
        ? AppLocalizations.of(context).importReviewVariationAdded
        : AppLocalizations.of(context).importReviewVariationRemoved;
    return Semantics(
      label: '$label: ${entry.displayText}',
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: Text(
                glyph,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.displayText,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_PhraseGroup> _groupByPhrase(List<FigureDiffEntry> entries) {
    final groups = <_PhraseGroup>[];
    for (final entry in entries) {
      if (groups.isEmpty || groups.last.phraseLabel != entry.phraseLabel) {
        groups.add(_PhraseGroup(entry.phraseLabel, [entry]));
      } else {
        groups.last.entries.add(entry);
      }
    }
    return groups;
  }
}

class _PhraseGroup {
  _PhraseGroup(this.phraseLabel, this.entries);

  final String phraseLabel;
  final List<FigureDiffEntry> entries;
}
