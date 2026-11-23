import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/program_forms.dart';
import '../data/regional_formats.dart';
import '../data/venue_label.dart';
import '../theme/app_spacing.dart';
import '../theme/selected_row.dart';
import 'calendar_flag_label.dart';
import 'program_status_chip.dart';
import 'right_click_menu.dart';

/// One Programs list row: title, event date, venue, planned dance count
/// ([Program.plannedDanceCount]), and a status chip (icon+text). Tapping calls
/// [onTap]; [selected] highlights the row in split-pane mode with a primary bar
/// down its left edge ([selectedRowShape]). An archived program also shows a
/// [ProgramArchivedChip]. Mirrors
/// `DanceListTile` (`docs/design/ux.md` §4).
class ProgramListTile extends StatelessWidget {
  const ProgramListTile({
    super.key,
    required this.program,
    this.venuesById = const {},
    this.forms,
    this.onTap,
    this.selected = false,
    this.onDelete,
    this.onDuplicate,
    this.onArchive,
    this.onUnarchive,
  });

  final Program program;

  /// Saved venues keyed by id, used to resolve a linked `venueId` to its
  /// display name. Defaults to empty (callers that don't supply it fall back to
  /// the free-text [Program.venue], preserving back-compat).
  final Map<String, Venue> venuesById;

  /// The forms of the program's dances ([ProgramRepository.formsByProgram]),
  /// named first on the row; null or empty names none.
  final Set<DanceForm>? forms;
  final VoidCallback? onTap;
  final bool selected;

  /// Soft-deletes this program (same flow as swipe-to-delete, incl. the undo
  /// snackbar). When non-null, the trailing overflow (⋮) menu exposes "Delete".
  final VoidCallback? onDelete;

  /// Duplicates this program. When non-null, the ⋮ menu exposes "Duplicate".
  final VoidCallback? onDuplicate;

  /// Archives this program. When non-null and the program is not archived,
  /// the ⋮ menu exposes "Archive", after "Duplicate".
  final VoidCallback? onArchive;

  /// Unarchives this program. When non-null and the program is archived, the
  /// ⋮ menu exposes "Unarchive" where "Archive" would be.
  final VoidCallback? onUnarchive;

  /// The archive action this row offers, if any: Archive for a program that is
  /// not archived, Unarchive for one that is.
  VoidCallback? get _archiveAction =>
      program.isArchived ? onUnarchive : onArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final danceCount = program.plannedDanceCount;
    final eventDate = program.eventDate;
    final dateLabel = eventDate == null
        ? null
        : formatEventDate(
            eventDate,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
            l10n,
          );

    final venue = resolveVenueLabel(program, venuesById);
    final subtitleParts = <String>[
      ?programFormsLabel(l10n, forms),
      ?dateLabel,
      if (venue != null && venue.isNotEmpty) venue,
      l10n.programsDanceCount(danceCount),
    ];

    final tile = ListTile(
      selected: selected,
      shape: selectedRowShape(context, selected: selected),
      // Same style as a dance row's title. The explicit style carries its own
      // colour, which would hide ListTile's selected colour, so the selected
      // title is set to it here.
      title: Text(
        program.title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleParts.join(' · '), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ProgramStatusChip(status: program.status),
                if (program.isArchived) const ProgramArchivedChip(),
                // #2354: icon and text, never colour alone.
                if (program.calendarFlag != null)
                  CalendarFlagLabel(program: program),
              ],
            ),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: _buildTrailing(l10n),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
    );
    // A right-click on the row opens the ⋮ menu ([_actionsMenu]).
    return RightClickMenu(menuKey: _actionsMenuKey, child: tile);
  }

  Key get _actionsMenuKey => ValueKey('program-actions-${program.id}');

  /// Trailing content: the row action overflow (⋮) menu when any action
  /// callback is wired, followed by the drill-in chevron; the chevron alone
  /// when no actions are provided.
  Widget _buildTrailing(AppLocalizations l10n) {
    final hasActions =
        onDelete != null || onDuplicate != null || _archiveAction != null;
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
      key: _actionsMenuKey,
      tooltip: l10n.collectionRowActionsSemantic(program.title),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _ProgramRowAction.duplicate:
            onDuplicate?.call();
          case _ProgramRowAction.archive:
            _archiveAction?.call();
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
        if (_archiveAction != null)
          PopupMenuItem<_ProgramRowAction>(
            key: const ValueKey('program-action-archive'),
            value: _ProgramRowAction.archive,
            child: ListTile(
              leading: Icon(
                program.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(
                program.isArchived
                    ? l10n.programsUnarchive
                    : l10n.programsArchive,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onDelete != null) ...[
          if (onDuplicate != null || _archiveAction != null)
            const PopupMenuDivider(),
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
enum _ProgramRowAction { duplicate, archive, delete }
