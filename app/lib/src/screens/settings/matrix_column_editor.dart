// The program-matrix column editor (issue #935, Phase 3). Lives inside the
// Program settings pane and lets the caller reorder, rename, and remove/restore
// the matrix's built-in columns (including the `customMove` bucket — decision
// D5), plus two reset controls (decision D4). It edits a [MatrixColumnConfig]
// and reports every change up via [onConfigChanged]; the parent persists it
// through the live scope + settings so an open matrix rebuilds immediately.
//
// Parameterized columns are created here; compound custom columns (Phase 5) are
// already carried by the ordered list so their creation flow can be added later.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';
import '../../widgets/figure_param_editors.dart';

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

  /// D4: restore all defaults — replace the whole config with the empty
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

  Future<void> _addParameterized(BuildContext context) async {
    final draft = await showDialog<_ParameterizedColumnDraft>(
      context: context,
      builder: (context) => _ParameterizedColumnDialog(taxonomy: _taxonomy),
    );
    if (draft == null) return;
    final id = '$parameterizedColumnIdPrefix${uuidV4()}';
    final parameterized = [
      ...config.parameterized,
      ParameterizedColumn(
        id: id,
        baseMove: draft.baseMove,
        params: draft.params,
      ),
    ];
    final renames = Map<String, String>.of(config.renames);
    if (draft.label.isEmpty) {
      renames.remove(id);
    } else {
      renames[id] = draft.label;
    }
    onConfigChanged(
      config.copyWith(parameterized: parameterized, renames: renames),
    );
  }

  Future<void> _editParameterized(
    BuildContext context,
    ParameterizedColumn column,
  ) async {
    final draft = await showDialog<_ParameterizedColumnDraft>(
      context: context,
      builder: (context) => _ParameterizedColumnDialog(
        taxonomy: _taxonomy,
        initial: column,
        initialLabel: config.renames[column.id] ?? '',
      ),
    );
    if (draft == null) return;
    final parameterized = [
      for (final current in config.parameterized)
        current.id == column.id
            ? ParameterizedColumn(
                id: column.id,
                baseMove: draft.baseMove,
                params: draft.params,
              )
            : current,
    ];
    final renames = Map<String, String>.of(config.renames);
    if (draft.label.isEmpty) {
      renames.remove(column.id);
    } else {
      renames[column.id] = draft.label;
    }
    onConfigChanged(
      config.copyWith(parameterized: parameterized, renames: renames),
    );
  }

  Future<void> _deleteParameterized(
    BuildContext context,
    ParameterizedColumn column,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsMatrixColumnsParameterizedDeleteTitle),
        content: Text(l10n.settingsMatrixColumnsParameterizedDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: ValueKey('matrix-column-delete-confirm-${column.id}'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsMatrixColumnsParameterizedDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final parameterized = [
      for (final current in config.parameterized)
        if (current.id != column.id) current,
    ];
    final order = [
      for (final id in config.order)
        if (id != column.id) id,
    ];
    final hidden = Set<String>.of(config.hidden)..remove(column.id);
    final renames = Map<String, String>.of(config.renames)..remove(column.id);
    onConfigChanged(
      config.copyWith(
        parameterized: parameterized,
        order: order,
        hidden: hidden,
        renames: renames,
      ),
    );
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
                _buildColumnRow(context, columns[i], i),
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
                key: const ValueKey('matrix-column-add-parameterized'),
                onPressed: () => _addParameterized(context),
                icon: const Icon(Icons.add),
                label: Text(l10n.settingsMatrixColumnsParameterizedAdd),
              ),
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

  Widget _buildColumnRow(BuildContext context, MatrixColumn column, int index) {
    ParameterizedColumn? parameterized;
    for (final candidate in config.parameterized) {
      if (candidate.id == column.moveId) {
        parameterized = candidate;
        break;
      }
    }
    final parameterizedColumn = parameterized;
    return _ColumnRow(
      key: ValueKey('matrix-column-row-${column.moveId}'),
      index: index,
      label: _effectiveLabel(column),
      hidden: config.hidden.contains(column.moveId),
      renamed: config.renames.containsKey(column.moveId),
      onRename: () => _promptRename(context, column),
      onToggleHidden: () => _toggleHidden(column.moveId),
      columnId: column.moveId,
      onEditDetails: parameterizedColumn == null
          ? null
          : () => _editParameterized(context, parameterizedColumn),
      onDelete: parameterizedColumn == null
          ? null
          : () => _deleteParameterized(context, parameterizedColumn),
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
    this.onEditDetails,
    this.onDelete,
  });

  final int index;
  final String label;
  final bool hidden;
  final bool renamed;
  final VoidCallback onRename;
  final VoidCallback onToggleHidden;
  final String columnId;
  final VoidCallback? onEditDetails;
  final VoidCallback? onDelete;

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
          if (onEditDetails != null)
            IconButton(
              key: ValueKey('matrix-column-edit-details-$columnId'),
              icon: const Icon(Icons.tune),
              tooltip: l10n.settingsMatrixColumnsParameterizedEdit,
              onPressed: onEditDetails,
            ),
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
          if (onDelete != null)
            IconButton(
              key: ValueKey('matrix-column-delete-$columnId'),
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsMatrixColumnsParameterizedDelete,
              onPressed: onDelete,
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

class _ParameterizedColumnDraft {
  const _ParameterizedColumnDraft({
    required this.baseMove,
    required this.params,
    required this.label,
  });

  final String baseMove;
  final Map<String, Object?> params;
  final String label;
}

class _ParameterizedColumnDialog extends StatefulWidget {
  const _ParameterizedColumnDialog({
    required this.taxonomy,
    this.initial,
    this.initialLabel = '',
  });

  final Taxonomy taxonomy;
  final ParameterizedColumn? initial;
  final String initialLabel;

  @override
  State<_ParameterizedColumnDialog> createState() =>
      _ParameterizedColumnDialogState();
}

class _ParameterizedColumnDialogState
    extends State<_ParameterizedColumnDialog> {
  late String _baseMove =
      widget.initial?.baseMove ?? widget.taxonomy.moves.keys.first;
  late final TextEditingController _label = TextEditingController(
    text: widget.initialLabel,
  );
  late Map<String, Object?> _params = {...?widget.initial?.params};
  late Set<String> _selected = _params.keys.toSet();

  MoveDef get _move => widget.taxonomy.moves[_baseMove]!;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _changeMove(String move) {
    setState(() {
      _baseMove = move;
      _params = {};
      _selected = {};
    });
  }

  void _toggleParam(String key, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(key);
        _params[key] = _move.params[key]!.defaultValue;
      } else {
        _selected.remove(key);
        _params.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final params = _move.params.entries.toList();
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l10n.settingsMatrixColumnsParameterizedTitle
            : l10n.settingsMatrixColumnsParameterizedEditTitle,
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('matrix-parameterized-move'),
                initialValue: _baseMove,
                decoration: InputDecoration(
                  labelText: l10n.settingsMatrixColumnsParameterizedMove,
                ),
                items: [
                  for (final move in widget.taxonomy.moves.values)
                    DropdownMenuItem(
                      value: move.id,
                      child: Text(move.displayName),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _changeMove(value);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.settingsMatrixColumnsParameterizedConstraints,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (params.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(l10n.settingsMatrixColumnsParameterizedNoParams),
                )
              else ...[
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final entry in params)
                      FilterChip(
                        key: ValueKey(
                          'matrix-parameterized-constraint-${entry.key}',
                        ),
                        label: Text(figureParamKeyLabel(entry.key)),
                        selected: _selected.contains(entry.key),
                        onSelected: (selected) =>
                            _toggleParam(entry.key, selected),
                      ),
                  ],
                ),
                for (final entry in params)
                  if (_selected.contains(entry.key))
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: FigureParamEditor(
                        key: ValueKey(
                          'matrix-parameterized-editor-${entry.key}',
                        ),
                        keyPrefix: 'matrix-parameterized',
                        paramKey: entry.key,
                        spec: entry.value,
                        value: _params[entry.key],
                        onChanged: (value) =>
                            setState(() => _params[entry.key] = value),
                        dialect: Dialect.canonical,
                      ),
                    ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('matrix-parameterized-label'),
                controller: _label,
                decoration: InputDecoration(
                  labelText: l10n.settingsMatrixColumnsParameterizedLabel,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const ValueKey('matrix-parameterized-save'),
          onPressed: () => Navigator.of(context).pop(
            _ParameterizedColumnDraft(
              baseMove: _baseMove,
              params: Map<String, Object?>.of(_params),
              label: _label.text.trim(),
            ),
          ),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
