// The program-matrix column editor (issue #935, Phase 3). Lives inside the
// Program settings pane and lets the caller reorder, rename, and remove/restore
// the matrix's built-in columns (including the `customMove` bucket — decision
// D5), plus two reset controls (decision D4). It edits a [MatrixColumnConfig]
// and reports every change up via [onConfigChanged]; the parent persists it
// through the live scope + settings so an open matrix rebuilds immediately.
//
// Parameterized/compound custom columns (Phases 4/5) are not *created* here, but
// the ordered list is assembled to carry them: any entry in
// [MatrixColumnConfig.parameterized]/[compound] appears as a row so those phases
// only add a creation entry point, not new list plumbing.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';

/// Editor surface for the program matrix's built-in (and custom-bucket) columns.
///
/// Pure presentation over [config]: it computes the effective column order,
/// labels each column via [matrixColumnLabel] under [dialect], and calls
/// [onConfigChanged] with a new [MatrixColumnConfig] for every edit. The parent
/// owns persistence (the live scope + the settings key).
class MatrixColumnEditor extends StatelessWidget {
  const MatrixColumnEditor({
    super.key,
    required this.config,
    required this.dialect,
    required this.onConfigChanged,
    this.taxonomy,
  });

  /// The active column configuration to edit.
  final MatrixColumnConfig config;

  /// Active dialect, for dialect-aware default column labels.
  final Dialect dialect;

  /// Reports a new configuration after an edit. The parent persists it.
  final ValueChanged<MatrixColumnConfig> onConfigChanged;

  /// The taxonomy whose columns are listed. Defaults to [contraTaxonomy] — the
  /// same taxonomy the matrix builds from.
  final Taxonomy? taxonomy;

  Taxonomy get _taxonomy => taxonomy ?? contraTaxonomy;

  /// Every editable column — the built-in catalog plus any custom
  /// (parameterized/compound) columns declared in [config] — in the config's
  /// effective display order. Mirrors the matrix's stable partition (ids listed
  /// in [MatrixColumnConfig.order] first, the rest keeping catalog order after),
  /// but unlike the matrix it does **not** drop hidden columns: hidden rows stay
  /// visible here so the user can restore them.
  List<MatrixColumn> _orderedColumns() {
    final universe = <MatrixColumn>[
      ...builtInColumnCatalog(_taxonomy),
      for (final p in config.parameterized)
        MatrixColumn(moveId: p.id, kind: MatrixColumnKind.parameterized),
      for (final c in config.compound)
        MatrixColumn(moveId: c.id, kind: MatrixColumnKind.compound),
    ];
    if (config.order.isEmpty) return universe;

    final orderIndex = <String, int>{};
    for (var i = 0; i < config.order.length; i++) {
      orderIndex.putIfAbsent(config.order[i], () => i);
    }
    final listed = <MatrixColumn>[];
    final unlisted = <MatrixColumn>[];
    for (final c in universe) {
      (orderIndex.containsKey(c.moveId) ? listed : unlisted).add(c);
    }
    listed.sort(
      (a, b) => orderIndex[a.moveId]!.compareTo(orderIndex[b.moveId]!),
    );
    return [...listed, ...unlisted];
  }

  /// The effective (rename-applied) header a column currently shows.
  String _effectiveLabel(MatrixColumn column) =>
      matrixColumnLabel(column, _taxonomy, dialect, config: config);

  /// The dialect-aware default header, ignoring any rename — shown as the rename
  /// field's placeholder so the user sees what clearing the override restores.
  String _defaultLabel(MatrixColumn column) =>
      matrixColumnLabel(column, _taxonomy, dialect);

  void _reorder(int oldIndex, int newIndex) {
    final ids = [for (final c in _orderedColumns()) c.moveId];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    onConfigChanged(config.copyWith(order: ids));
  }

  void _toggleHidden(String id) {
    final hidden = Set<String>.of(config.hidden);
    if (!hidden.add(id)) hidden.remove(id);
    onConfigChanged(config.copyWith(hidden: hidden));
  }

  void _applyRename(String id, String? label) {
    final renames = Map<String, String>.of(config.renames);
    if (label == null || label.isEmpty) {
      renames.remove(id);
    } else {
      renames[id] = label;
    }
    onConfigChanged(config.copyWith(renames: renames));
  }

  /// D4: restore removed defaults — un-hide every built-in, reset the built-in
  /// portion of order to catalog order, keep renames and all custom columns,
  /// appending customs after the built-ins sorted by displayed label.
  void _restoreRemovedDefaults() {
    final catalogOrder = [
      for (final c in builtInColumnCatalog(_taxonomy)) c.moveId,
    ];
    final customs = <CustomColumnLabel>[
      for (final p in config.parameterized)
        (
          id: p.id,
          label: _effectiveLabel(
            MatrixColumn(moveId: p.id, kind: MatrixColumnKind.parameterized),
          ),
        ),
      for (final c in config.compound)
        (
          id: c.id,
          label: _effectiveLabel(
            MatrixColumn(moveId: c.id, kind: MatrixColumnKind.compound),
          ),
        ),
    ];
    onConfigChanged(
      config.copyWith(
        order: restoreRemovedDefaultsOrder(
          catalogOrder: catalogOrder,
          customs: customs,
        ),
        hidden: const <String>{},
      ),
    );
  }

  /// D4: restore true defaults — replace the whole config with the empty
  /// (today's) config. Destructive, so the caller gates it behind a confirm.
  void _restoreTrueDefaults() => onConfigChanged(MatrixColumnConfig.empty);

  Future<void> _promptRename(BuildContext context, MatrixColumn column) async {
    final id = column.moveId;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => _RenameDialog(
        initialValue: config.renames[id] ?? '',
        defaultLabel: _defaultLabel(column),
      ),
    );
    // A dismissed dialog (null) leaves the rename unchanged; an explicit empty
    // string clears the override.
    if (result != null) _applyRename(id, result.trim());
  }

  Future<void> _confirmRestoreTrueDefaults(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsMatrixColumnsResetTrueTitle),
        content: Text(l10n.settingsMatrixColumnsResetTrueBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('matrix-column-reset-true-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsMatrixColumnsResetTrueConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) _restoreTrueDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final columns = _orderedColumns();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsMatrixColumnsHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.settingsMatrixColumnsSubtitle,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ReorderableListView(
            onReorderItem: _reorder,
            buildDefaultDragHandles: false,
            children: [
              for (var i = 0; i < columns.length; i++)
                _ColumnRow(
                  key: ValueKey('matrix-column-row-${columns[i].moveId}'),
                  index: i,
                  label: _effectiveLabel(columns[i]),
                  hidden: config.hidden.contains(columns[i].moveId),
                  renamed: config.renames.containsKey(columns[i].moveId),
                  onRename: () => _promptRename(context, columns[i]),
                  onToggleHidden: () => _toggleHidden(columns[i].moveId),
                  columnId: columns[i].moveId,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('matrix-column-reset-removed'),
                onPressed: _restoreRemovedDefaults,
                icon: const Icon(Icons.restore),
                label: Text(l10n.settingsMatrixColumnsResetRemoved),
              ),
              OutlinedButton.icon(
                key: const ValueKey('matrix-column-reset-true'),
                onPressed: () => _confirmRestoreTrueDefaults(context),
                icon: const Icon(Icons.settings_backup_restore),
                label: Text(l10n.settingsMatrixColumnsResetTrue),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One reorderable column row: drag handle, label (struck through when hidden),
/// a rename action, and a remove/restore toggle.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    super.key,
    required this.index,
    required this.label,
    required this.hidden,
    required this.renamed,
    required this.onRename,
    required this.onToggleHidden,
    required this.columnId,
  });

  final int index;
  final String label;
  final bool hidden;
  final bool renamed;
  final VoidCallback onRename;
  final VoidCallback onToggleHidden;
  final String columnId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: ReorderableDragStartListener(
        index: index,
        child: Semantics(
          label: l10n.settingsMatrixColumnsDragToReorder(label),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
      title: Text(
        label,
        style: hidden
            ? theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : theme.textTheme.bodyMedium,
      ),
      subtitle: renamed ? Text(l10n.settingsMatrixColumnsRenamedBadge) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('matrix-column-rename-$columnId'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.settingsMatrixColumnsRenameTooltip,
            onPressed: onRename,
          ),
          IconButton(
            key: ValueKey(
              hidden
                  ? 'matrix-column-restore-$columnId'
                  : 'matrix-column-remove-$columnId',
            ),
            icon: Icon(
              hidden ? Icons.add_circle_outline : Icons.remove_circle_outline,
            ),
            tooltip: hidden
                ? l10n.settingsMatrixColumnsRestoreTooltip
                : l10n.settingsMatrixColumnsRemoveTooltip,
            onPressed: onToggleHidden,
          ),
        ],
      ),
    );
  }
}

/// The column-rename dialog. Owns its [TextEditingController] so it is disposed
/// only after the dialog's exit transition completes (disposing it eagerly in
/// the caller tears it down while the closing frame still rebuilds the field).
/// Pops the entered text on save (empty clears the rename) or `null` on cancel.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialValue, required this.defaultLabel});

  final String initialValue;
  final String defaultLabel;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsMatrixColumnsRenameTitle),
      content: TextField(
        key: const ValueKey('matrix-column-rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.settingsMatrixColumnsRenameLabel,
          hintText: widget.defaultLabel,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('matrix-column-rename-confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
