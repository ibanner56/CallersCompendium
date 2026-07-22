import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import 'program_status_chip.dart';

/// One Programs list row: title, event date, venue, slot count, and a status
/// chip (icon+text). Tapping calls [onTap]; [selected] highlights the row in
/// split-pane mode. Mirrors `DanceListTile` (`docs/design/ux.md` §4).
class ProgramListTile extends StatelessWidget {
  const ProgramListTile({
    super.key,
    required this.program,
    this.onTap,
    this.selected = false,
    this.onDelete,
    this.onDuplicate,
  });

  final Program program;
  final VoidCallback? onTap;
  final bool selected;

  /// Soft-deletes this program (same flow as swipe-to-delete, incl. the undo
  /// snackbar). When non-null, the trailing overflow (⋮) menu exposes "Delete".
  final VoidCallback? onDelete;

  /// Duplicates this program. When non-null, the ⋮ menu exposes "Duplicate".
  final VoidCallback? onDuplicate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final slotCount = program.slots.length;
    final eventDate = program.eventDate;
    final dateLabel = eventDate == null
        ? null
        : formatEventDate(
            eventDate,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
          );

    final venue = program.venue?.trim();
    final subtitleParts = <String>[
      ?dateLabel,
      if (venue != null && venue.isNotEmpty) venue,
      l10n.programsSlotCount(slotCount),
    ];

    return ListTile(
      selected: selected,
      title: Text(program.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleParts.join(' · '), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            ProgramStatusChip(status: program.status),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: _buildTrailing(l10n),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  /// Trailing content: the row action overflow (⋮) menu when any action
  /// callback is wired, followed by the drill-in chevron; the chevron alone
  /// when no actions are provided.
  Widget _buildTrailing(AppLocalizations l10n) {
    final hasActions = onDelete != null || onDuplicate != null;
    if (!hasActions) return const Icon(Icons.chevron_right);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_actionsMenu(l10n), const Icon(Icons.chevron_right)],
    );
  }

  /// A keyboard- and screen-reader-reachable "⋮" menu exposing the program's
  /// row actions without a swipe. Each item is a first-class [PopupMenuItem]
  /// with an icon+text [ListTile] so its label is announced by assistive tech;
  /// the button itself is labelled by its [PopupMenuButton.tooltip].
  Widget _actionsMenu(AppLocalizations l10n) {
    return PopupMenuButton<_ProgramRowAction>(
      key: ValueKey('program-actions-${program.id}'),
      tooltip: l10n.collectionRowActionsSemantic(program.title),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _ProgramRowAction.duplicate:
            onDuplicate?.call();
          case _ProgramRowAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onDuplicate != null)
          PopupMenuItem<_ProgramRowAction>(
            key: const ValueKey('program-action-duplicate'),
            value: _ProgramRowAction.duplicate,
            child: ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.commonDuplicate),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onDelete != null) ...[
          if (onDuplicate != null) const PopupMenuDivider(),
          PopupMenuItem<_ProgramRowAction>(
            key: const ValueKey('program-action-delete'),
            value: _ProgramRowAction.delete,
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.commonDelete),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}

/// Row actions exposed by [ProgramListTile]'s trailing overflow (⋮) menu.
enum _ProgramRowAction { duplicate, delete }
