import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../models/dance_list_entry.dart';
import '../screens/dance_detail_screen.dart';

/// One Collection result row: title, authors, formation chip, status/tag chips
/// and `showInList` custom fields (Phase 3.1 rendering). Tapping it opens
/// [DanceDetailScreen].
class DanceListTile extends StatelessWidget {
  const DanceListTile({super.key, required this.entry});

  final DanceListEntry entry;

  @override
  Widget build(BuildContext context) {
    final dance = entry.dance;
    final theme = Theme.of(context);

    return ListTile(
      title: Text(dance.title),
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DanceDetailScreen(danceId: dance.id)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
