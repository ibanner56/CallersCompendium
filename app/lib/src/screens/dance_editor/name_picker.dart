import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/multi_select_dropdown.dart';

typedef NameOption = ({String id, String name});

/// A multi-select dropdown of named entities (authors, interpreters, tags):
/// a field that reads the chosen names as text, and opens a list of every
/// option with a checkbox, a search box that narrows it, and a row that
/// creates a new entity from the typed name (`docs/design/ux.md` §3).
///
/// On a wide window the list drops down under the field; on a phone, or a
/// short window, it is a bottom sheet padded above the keyboard, so typing
/// never hides it (issue #716).
///
/// The list reads [selectedIds], [namesById] and [options] live: a check runs
/// [onAdd] or [onRemove], and the boxes follow once the owner rebuilds this
/// widget with the new selection.
class NamePicker extends StatefulWidget {
  const NamePicker({
    super.key,
    required this.fieldKey,
    required this.selectedIds,
    required this.namesById,
    required this.options,
    required this.onAdd,
    required this.onRemove,
    required this.onCreate,
    this.onEdit,
    this.sheetSemanticLabel,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final Map<String, String> namesById;
  final List<NameOption> options;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// Returns the id the entity actually occupies, or `null` when the
  /// create did not happen and the caller has already told the user why
  /// (see `dance_editor_screen._createChoreographer`). `null` skips
  /// [onAdd] and leaves the typed text in place.
  final Future<String?> Function(String name) onCreate;

  /// When non-null, each row of the open list has an edit button that closes
  /// the list and invokes [onEdit] with the id: used by the Authors and
  /// Interpreted by pickers to edit the shared person record. When null (the
  /// Tags picker), rows have no edit button.
  final ValueChanged<String>? onEdit;

  /// The field's name for screen readers, and the announced name of the open
  /// list (e.g. "Authors" or "Tags"), matching the [FieldLabel] shown above
  /// this picker.
  final String? sheetSemanticLabel;

  @override
  State<NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<NamePicker> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiSelectDropdown(
      fieldKey: widget.fieldKey,
      semanticLabel: widget.sheetSemanticLabel,
      valueText: widget.selectedIds
          .map((id) => widget.namesById[id] ?? id)
          .join(', '),
      decoration: InputDecoration(hintText: l10n.danceEditorChooseHint),
      panelBuilder: (context, placement) => _NamePickerPanel(
        owner: this,
        picker: widget,
        autofocus: placement.autofocus,
        scrollController: placement.scrollController,
      ),
      onClosed: (editId) {
        if (editId is String) widget.onEdit?.call(editId);
      },
    );
  }
}

/// The open list: a search box, a checkbox row per option in [order], and a
/// create row for a typed name nobody has.
class _NamePickerPanel extends StatefulWidget {
  const _NamePickerPanel({
    required this.owner,
    required this.picker,
    required this.autofocus,
    this.scrollController,
  });

  /// The field this list belongs to. Once it is gone (the editor closed
  /// under the list), a create still in flight adds nothing.
  final State<NamePicker> owner;

  /// The field as the owner last built it: its selection and names.
  final NamePicker picker;
  final bool autofocus;
  final ScrollController? scrollController;

  @override
  State<_NamePickerPanel> createState() => _NamePickerPanelState();
}

class _NamePickerPanelState extends State<_NamePickerPanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  /// The rows' order: the chosen names first, in their order, then everyone
  /// else by name, plus anything created while the list is open. Fixed while
  /// the list is open, so a row does not jump when it is checked.
  late final List<String> _order = _initialOrder(widget.picker);

  static List<String> _initialOrder(NamePicker picker) {
    final selected = picker.selectedIds.toSet();
    // Each sort key is worked out once: a long people list would otherwise
    // normalise every name many times over.
    final rest = [
      for (final o in picker.options)
        if (!selected.contains(o.id))
          (key: naturalKeyMatchKey(o.name), id: o.id),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return [...picker.selectedIds, for (final o in rest) o.id];
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Rows for [picker] matching the typed text, in list order, then the
  /// create row when the typed name matches nobody exactly.
  List<_Row> _rows(NamePicker picker) {
    final q = _query.text.trim();
    // `naturalKeyMatchKey`, not `toLowerCase()`, for the filter and the exact
    // test alike: the repositories look an incumbent up by
    // `normalizeShareableText`, so comparing case-folded raw text would offer
    // a create that the repository then refuses as a duplicate (found in
    // review on #1410).
    final wanted = naturalKeyMatchKey(q);
    final names = {
      for (final o in picker.options) o.id: o.name,
      ...picker.namesById,
    };
    final known = {..._order};
    final ids = [
      ..._order,
      // Options that arrived while the list was open (another device's sync).
      for (final o in picker.options)
        if (!known.contains(o.id)) o.id,
    ];
    final rows = [
      for (final id in ids)
        if (names[id] case final name?)
          if (wanted.isEmpty || naturalKeyMatchKey(name).contains(wanted))
            _Row.existing(id, name),
    ];
    if (q.isNotEmpty &&
        !picker.options.any((o) => naturalKeyMatchKey(o.name) == wanted)) {
      rows.add(_Row.create(q));
    }
    return rows;
  }

  void _toggle(NamePicker picker, String id) {
    if (picker.selectedIds.contains(id)) {
      picker.onRemove(id);
      return;
    }
    picker.onAdd(id);
    // A name found by typing is added; the search box empties and keeps
    // focus, so the next name can be typed straight away (issue #402).
    if (_query.text.isNotEmpty) {
      _query.clear();
      _queryFocus.requestFocus();
    }
  }

  Future<void> _create(NamePicker picker, String name) async {
    final id = await picker.onCreate(name);
    // `null` is "the create did not happen, and the user has been told": the
    // typed name stays, so the next step is to pick the row it collided with.
    if (!mounted || !widget.owner.mounted || id == null) return;
    // Listed after the names already chosen, where a checked name sits.
    final chosen = picker.selectedIds.toSet();
    final at = _order.takeWhile(chosen.contains).length;
    picker.onAdd(id);
    setState(() {
      if (!_order.contains(id)) _order.insert(at, id);
    });
    _query.clear();
    _queryFocus.requestFocus();
  }

  /// Enter in the search box: checks the first match not yet chosen, or
  /// creates the typed name when it matches nobody, then clears the box for
  /// the next name. With nothing left to check or create, Enter does nothing
  /// and the typed text stays.
  void _submit(NamePicker picker) {
    if (_query.text.trim().isEmpty) return;
    final chosen = picker.selectedIds.toSet();
    final rows = _rows(picker);
    final first = rows
        .where((r) => r.isCreate || !chosen.contains(r.id))
        .firstOrNull;
    if (first == null) return;
    if (first.isCreate) {
      _create(picker, first.name);
      return;
    }
    picker.onAdd(first.id!);
    _query.clear();
    _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final picker = widget.picker;
    final rows = _rows(picker);
    final selected = picker.selectedIds.toSet();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: TextField(
            key: ValueKey('${picker.fieldKey}-input'),
            controller: _query,
            focusNode: _queryFocus,
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              hintText: l10n.danceEditorTypeToAddOrCreateHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
            onSubmitted: (_) => _submit(picker),
          ),
        ),
        Flexible(
          child: ListView.builder(
            key: ValueKey('${picker.fieldKey}-options'),
            controller: widget.scrollController,
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row.isCreate) {
                return ListTile(
                  key: ValueKey('${picker.fieldKey}-option-create:${row.name}'),
                  dense: true,
                  leading: const Icon(Icons.add),
                  title: Text(l10n.danceEditorCreateQuotedName(row.name)),
                  onTap: () => _create(picker, row.name),
                );
              }
              final id = row.id!;
              return CheckboxListTile(
                key: ValueKey('${picker.fieldKey}-option-$id'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(id),
                title: Text(row.name),
                onChanged: (_) => _toggle(picker, id),
                secondary: picker.onEdit == null
                    ? null
                    : IconButton(
                        key: ValueKey('${picker.fieldKey}-edit-$id'),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: l10n.danceEditorEditItemTooltip(row.name),
                        onPressed: () => Navigator.of(context).pop(id),
                      ),
              );
            },
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: TextButton(
              key: ValueKey('${picker.fieldKey}-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonDone),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row {
  _Row.existing(this.id, this.name) : isCreate = false;
  _Row.create(this.name) : id = null, isCreate = true;

  final String? id;
  final String name;
  final bool isCreate;
}
