import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../models/dance_list_entry.dart';
import '../screens/dance_detail_screen.dart';
import '../search/facet_labels.dart';

/// One Collection result row: title, authors, formation chip, status/tag chips
/// and `showInList` custom fields (Phase 3.1 rendering). Tapping it opens
/// [DanceDetailScreen]. Pass an [onTap] to override the default navigation
/// (e.g. when the caller needs to await a result from the detail route).
class DanceListTile extends StatelessWidget {
  const DanceListTile({
    super.key,
    required this.entry,
    this.onTap,
    this.selected = false,
  });

  final DanceListEntry entry;

  /// Optional override for the tap action. When null, the default behaviour
  /// (push [DanceDetailScreen] without awaiting a result) is used.
  final VoidCallback? onTap;

  /// Whether this tile is the currently selected row (e.g. in split-pane mode).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dance = entry.dance;
    final theme = Theme.of(context);

    return ListTile(
      selected: selected,
      visualDensity: VisualDensity.compact,
      leading: Tooltip(
        message: danceFormLabel(dance.form),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(danceFormIcon(dance.form), size: 20),
        ),
      ),
      title: Text(dance.title, style: theme.textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (entry.authorNames.isNotEmpty)
              Text(
                entry.authorNames.join(', '),
                style: theme.textTheme.bodyMedium,
              ),
            Chip(
              avatar: const Icon(Icons.grid_view, size: 16),
              label: Text(formationLabel(dance.formation)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            if (dance.status != DanceStatus.active)
              Chip(
                avatar: Icon(
                  dance.status == DanceStatus.deprecated
                      ? Icons.history_toggle_off
                      : Icons.report_problem_outlined,
                  size: 16,
                ),
                label: Text(
                  dance.status == DanceStatus.deprecated
                      ? 'Deprecated'
                      : 'Broken',
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (dance.level != null)
              Chip(
                avatar: const Icon(Icons.signal_cellular_alt, size: 16),
                label: Text(danceLevelLabel(dance.level!)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (dance.mixedLevel)
              Chip(
                avatar: const Icon(Icons.swap_vert, size: 16),
                label: const Text('Mixed level'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (dance.rating != null)
              Chip(
                key: const ValueKey('rating-indicator'),
                avatar: const Icon(Icons.star, size: 16),
                label: Text(
                  '${dance.rating}',
                  semanticsLabel: 'Rating: ${dance.rating} of 5 stars',
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            for (final tag in entry.tagNames)
              Chip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            for (final field in entry.listCustomFields)
              Chip(
                label: Text(field),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
      isThreeLine: false,
      trailing: const Icon(Icons.chevron_right),
      onTap:
          onTap ??
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DanceDetailScreen(danceId: dance.id),
            ),
          ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
