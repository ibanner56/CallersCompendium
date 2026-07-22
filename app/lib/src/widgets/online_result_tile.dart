import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/online_search.dart';
import '../data/online_search_labels.dart';
import '../theme/app_spacing.dart';

/// One online search result row: the dance title, its author and formation, and
/// a subtle per-source "From … (online)" attribution.
///
/// Source-agnostic: it renders any [OnlineSearchResultRow] (Caller's Box or
/// ContraDB) and takes its attribution line from [OnlineSource.attribution], so
/// a new source needs no tile change.
///
/// Deliberately simpler than the collection `DanceListTile`: an online result is
/// not yet in the collection, so it has no delete / duplicate / add-to-program
/// actions. Tapping it ([onTap]) previews the dance (the caller fetches its full
/// record and shows it in the detail pane / a preview route). [selected]
/// highlights the row in split-pane mode.
class OnlineResultTile extends StatelessWidget {
  const OnlineResultTile({
    super.key,
    required this.result,
    this.onTap,
    this.selected = false,
  });

  final OnlineSearchResultRow result;
  final VoidCallback? onTap;

  /// Whether this row is the currently previewed result (split-pane highlight).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitleParts = <String>[
      if (result.author.isNotEmpty) result.author,
      if (result.formation.isNotEmpty) result.formation,
    ];
    return ListTile(
      leading: const Icon(Icons.cloud_outlined),
      selected: selected,
      title: Text(result.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitleParts.isNotEmpty) Text(subtitleParts.join(' • ')),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            onlineSourceAttribution(l10n, result.source),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: subtitleParts.isNotEmpty,
      onTap: onTap,
    );
  }
}
