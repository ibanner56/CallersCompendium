import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/collection_tile_fields_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/formation_colors_scope.dart';
import '../models/dance_list_entry.dart';
import '../screens/dance_detail_screen.dart';
import '../search/facet_labels.dart';
import '../theme/set_list_accents.dart';
import 'program_status_chip.dart';

/// One Collection result row: title, authors, formation chip, status/tag chips
/// and `showInList` custom fields (Phase 3.1 rendering). Tapping it opens
/// [DanceDetailScreen]. Pass an [onTap] to override the default navigation
/// (e.g. when the caller needs to await a result from the detail route).
///
/// When [selectionMode] is true (Collection batch-tag multi-select,
/// `docs/design/ux.md` §1) the leading avatar is replaced by a [Checkbox]
/// reflecting [selectedForBatch]; the row is also marked
/// [ListTile.selected] so the state is conveyed by a checkmark **and** a
/// highlight (never color alone), and the trailing chevron is hidden. Tapping
/// the row (via [onTap]) toggles selection; [onLongPress] lets a caller enter
/// selection mode from a normal (non-selection) row.
class DanceListTile extends StatelessWidget {
  const DanceListTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    this.selectedForBatch = false,
    this.onDelete,
    this.onDuplicate,
    this.onAddToProgram,
    this.onTagTap,
    this.visibleFields,
  }) : assert(
         !selectionMode || selected == selectedForBatch,
         'In selection mode the row highlight (selected) must match the '
         'checkbox state (selectedForBatch) so the state is never ambiguous.',
       );

  final DanceListEntry entry;

  /// Optional override for the tap action. When null, the default behaviour
  /// (push [DanceDetailScreen] without awaiting a result) is used.
  final VoidCallback? onTap;

  /// Optional long-press handler (e.g. to enter batch-selection mode).
  final VoidCallback? onLongPress;

  /// Whether this tile is the currently selected row (e.g. in split-pane mode,
  /// or the selected-for-batch row while [selectionMode] is active).
  final bool selected;

  /// Whether the list is in batch multi-select mode. When true the leading
  /// widget is a [Checkbox] and the trailing chevron is hidden.
  final bool selectionMode;

  /// Whether this row is currently checked in batch multi-select mode.
  final bool selectedForBatch;

  /// Soft-deletes this dance (same flow as swipe-to-delete, incl. the undo
  /// snackbar). When non-null and the row is not in [selectionMode], the
  /// trailing overflow (⋮) menu exposes a "Delete" action.
  final VoidCallback? onDelete;

  /// Duplicates this dance. When non-null (and not in [selectionMode]) the ⋮
  /// menu exposes a "Duplicate" action.
  final VoidCallback? onDuplicate;

  /// Opens the add-to-program flow for this dance. When non-null (and not in
  /// [selectionMode]) the ⋮ menu exposes an "Add to program" action.
  final VoidCallback? onAddToProgram;

  /// Called with a tag's id when its chip is tapped, to filter the Collection
  /// to that tag (issue #414). When null (e.g. the Programs dance picker) the
  /// tag chips stay non-interactive. Ignored while in [selectionMode], where
  /// the whole row drives batch selection.
  final void Function(String tagId)? onTagTap;

  /// Which data chips to render on this row. When null every chip is shown,
  /// which is the existing behaviour at all call sites that don't opt in.
  /// The collection screen passes [CollectionTileFieldsScope.of(context)] here;
  /// all other call sites leave this null so their rendering is unaffected.
  final Set<CollectionTileField>? visibleFields;

  @override
  Widget build(BuildContext context) {
    final dance = entry.dance;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Mirror the dance-detail calling history: when "Require mark-performed"
    // is on the count reflects performed-only occurrences, otherwise every
    // occurrence — so the card and the detail history never disagree. Reading
    // the scope here (rather than at load time) keeps the chip live as the
    // setting toggles, without reloading the list.
    final calledCount = entry.callCounts.countFor(
      RequirePerformedForHistoryScope.of(context),
    );
    // Which fields the user wants shown on this row (issue #767).
    // Null means show everything — the caller didn't opt in to the preference.
    final effectiveFields = visibleFields ?? CollectionTileField.all;
    // Per-formation label colour (issue #367): highlight the formation chip
    // only when the user explicitly overrode this shape (override-only). The
    // label text + icon stay, so colour remains a redundant cue.
    final formationColor = FormationColorsScope.of(
      context,
    )?.overrideFor(dance.formation.shape);
    final formationFg = formationColor == null
        ? null
        : readableForegroundOn(formationColor);
    return ListTile(
      selected: selected,
      visualDensity: VisualDensity.compact,
      onLongPress: onLongPress,
      leading: selectionMode
          ? Checkbox(
              key: ValueKey('batch-checkbox-${dance.id}'),
              value: selectedForBatch,
              // Toggled by tapping the row (ListTile.onTap); the checkbox
              // mirrors that so pointer taps on the box itself also work.
              onChanged: onTap == null ? null : (_) => onTap!(),
              semanticLabel: l10n.collectionSelectDanceLabel(dance.title),
            )
          : Tooltip(
              message: danceFormLabel(l10n, dance.form),
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
            if (effectiveFields.contains(CollectionTileField.authors) &&
                entry.authorNames.isNotEmpty)
              Text(
                entry.authorNames.join(', '),
                style: theme.textTheme.bodyMedium,
              ),
            if (effectiveFields.contains(CollectionTileField.calledCount) &&
                calledCount > 0)
              Chip(
                key: ValueKey('called-count-${dance.id}'),
                avatar: const Icon(Icons.campaign_outlined, size: 16),
                label: Text(
                  l10n.collectionCalledBadge(calledCount),
                  semanticsLabel: l10n.collectionCalledBadgeSemantic(
                    calledCount,
                  ),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (effectiveFields.contains(CollectionTileField.formation))
              Chip(
                avatar: Icon(formationIcon, size: 16, color: formationFg),
                label: Text(
                  formationLabel(l10n, dance.formation),
                  style: formationFg == null
                      ? null
                      : TextStyle(color: formationFg),
                ),
                backgroundColor: formationColor,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (effectiveFields.contains(CollectionTileField.status) &&
                dance.status != DanceStatus.active)
              DanceStatusChip(status: dance.status),
            if (effectiveFields.contains(CollectionTileField.level) &&
                dance.level != null)
              Chip(
                avatar: const Icon(
                  Icons.signal_cellular_alt_outlined,
                  size: 16,
                ),
                label: Text(danceLevelLabel(l10n, dance.level!)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (effectiveFields.contains(CollectionTileField.level) &&
                dance.mixedLevel)
              Chip(
                avatar: const Icon(Icons.swap_vert_outlined, size: 16),
                label: Text(l10n.commonMixedLevel),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (effectiveFields.contains(CollectionTileField.rating) &&
                dance.rating != null)
              Chip(
                key: const ValueKey('rating-indicator'),
                avatar: const Icon(Icons.star_outline, size: 16),
                label: Text(
                  '${dance.rating}',
                  semanticsLabel: l10n.collectionRatingSemantic(dance.rating!),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            if (effectiveFields.contains(CollectionTileField.tags))
              for (final tag in entry.tags)
                if (onTagTap != null && !selectionMode)
                  ActionChip(
                    key: ValueKey('tag-filter-chip-${tag.id}'),
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(tag.name),
                    tooltip: l10n.commonShowDancesTaggedTooltip(tag.name),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => onTagTap!(tag.id),
                  )
                else
                  Chip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(tag.name),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
            if (effectiveFields.contains(CollectionTileField.customFields))
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
      trailing: selectionMode ? null : _buildTrailing(l10n),
      onTap:
          onTap ??
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DanceDetailScreen(danceId: dance.id),
            ),
          ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  /// Trailing content for a normal (non-selection) row: the row action overflow
  /// (⋮) menu when any action callback is wired, followed by the drill-in
  /// chevron. Falls back to the chevron alone when no actions are provided.
  Widget _buildTrailing(AppLocalizations l10n) {
    final hasActions =
        onDelete != null || onDuplicate != null || onAddToProgram != null;
    if (!hasActions) return const Icon(Icons.chevron_right);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_actionsMenu(l10n), const Icon(Icons.chevron_right)],
    );
  }

  /// A keyboard- and screen-reader-reachable "⋮" menu exposing the row actions
  /// without a swipe. Each item is a first-class [PopupMenuItem] with an
  /// icon+text [ListTile] so its label is announced by assistive tech; the
  /// button itself is labelled by its [PopupMenuButton.tooltip].
  Widget _actionsMenu(AppLocalizations l10n) {
    final dance = entry.dance;
    return PopupMenuButton<_DanceRowAction>(
      key: ValueKey('dance-actions-${dance.id}'),
      tooltip: l10n.collectionRowActionsSemantic(dance.title),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _DanceRowAction.duplicate:
            onDuplicate?.call();
          case _DanceRowAction.addToProgram:
            onAddToProgram?.call();
          case _DanceRowAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onDuplicate != null)
          PopupMenuItem<_DanceRowAction>(
            key: const ValueKey('dance-action-duplicate'),
            value: _DanceRowAction.duplicate,
            child: ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.commonDuplicate),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onAddToProgram != null)
          PopupMenuItem<_DanceRowAction>(
            key: const ValueKey('dance-action-add-to-program'),
            value: _DanceRowAction.addToProgram,
            child: ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(l10n.commonAddToProgram),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onDelete != null) ...[
          if (onDuplicate != null || onAddToProgram != null)
            const PopupMenuDivider(),
          PopupMenuItem<_DanceRowAction>(
            key: const ValueKey('dance-action-delete'),
            value: _DanceRowAction.delete,
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

/// Row actions exposed by [DanceListTile]'s trailing overflow (⋮) menu.
enum _DanceRowAction { duplicate, addToProgram, delete }
