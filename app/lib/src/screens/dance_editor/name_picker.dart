import 'package:flutter/material.dart';

typedef NameOption = ({String id, String name});

/// Chips of selected entities plus a type-ahead that adds an existing entity
/// or creates a new one inline (`docs/design/ux.md` §3 author autocomplete).
class NamePicker extends StatelessWidget {
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
  });

  final String fieldKey;
  final List<String> selectedIds;
  final Map<String, String> namesById;
  final List<NameOption> options;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final Future<String> Function(String name) onCreate;

  /// When non-null, each selected chip becomes tappable (an [InputChip]) and
  /// tapping its body invokes [onEdit] with the id — used by the Authors picker
  /// to edit the shared choreographer record. When null (e.g. the Tags picker),
  /// chips stay plain, non-editable [Chip]s.
  final ValueChanged<String>? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [for (final id in selectedIds) _buildChip(id)],
          ),
        _AddAutocomplete(
          fieldKey: fieldKey,
          selectedIds: selectedIds,
          options: options,
          onAdd: onAdd,
          onCreate: onCreate,
        ),
      ],
    );
  }

  Widget _buildChip(String id) {
    final label = namesById[id] ?? id;
    final key = ValueKey('$fieldKey-chip-$id');
    if (onEdit == null) {
      return Chip(key: key, label: Text(label), onDeleted: () => onRemove(id));
    }
    // Editable chip: tapping the body opens the details dialog; the delete
    // affordance still removes the author from the dance. The tooltip makes the
    // tap affordance discoverable for pointer and screen-reader users.
    return InputChip(
      key: key,
      label: Text(label),
      tooltip: 'Edit $label',
      onPressed: () => onEdit!(id),
      onDeleted: () => onRemove(id),
    );
  }
}

class _AddAutocomplete extends StatefulWidget {
  const _AddAutocomplete({
    required this.fieldKey,
    required this.selectedIds,
    required this.options,
    required this.onAdd,
    required this.onCreate,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final List<NameOption> options;
  final ValueChanged<String> onAdd;
  final Future<String> Function(String name) onCreate;

  @override
  State<_AddAutocomplete> createState() => _AddAutocompleteState();
}

class _AddAutocompleteState extends State<_AddAutocomplete> {
  // Owned so we can clear the field and keep focus after a tag is committed
  // (issue #402: the typed text lingered because Flutter's Autocomplete fills
  // the field with the selected option's label before onSelected runs).
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fieldKey = widget.fieldKey;
    return Autocomplete<_PickerChoice>(
      key: ValueKey('$fieldKey-autocomplete'),
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (choice) => choice.label,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<_PickerChoice>.empty();
        final lower = q.toLowerCase();
        final matches = widget.options
            .where(
              (o) =>
                  !widget.selectedIds.contains(o.id) &&
                  o.name.toLowerCase().contains(lower),
            )
            .map((o) => _PickerChoice.existing(o.id, o.name))
            .toList();
        final exact = widget.options.any((o) => o.name.toLowerCase() == lower);
        if (!exact) matches.add(_PickerChoice.create(q));
        return matches;
      },
      onSelected: (choice) async {
        if (choice.isCreate) {
          // Only clear after the create + add succeeds; a thrown onCreate
          // short-circuits before we touch the field.
          final id = await widget.onCreate(choice.name);
          // Guard against the widget being disposed during the await (e.g. the
          // editor route closed while the tag was being created).
          if (!mounted) return;
          widget.onAdd(id);
        } else {
          widget.onAdd(choice.id!);
        }
        // Reset the field and keep focus so the next tag can be typed straight
        // away. Clearing lives only here, so empty/duplicate/no-op submits
        // (which never reach onSelected) leave state untouched.
        _controller.clear();
        _focusNode.requestFocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: ValueKey('$fieldKey-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Type to add or create…',
            isDense: true,
          ),
          onSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, choices) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final choice in choices)
                    ListTile(
                      key: ValueKey('$fieldKey-option-${choice.optionKey}'),
                      dense: true,
                      leading: Icon(
                        choice.isCreate ? Icons.add : Icons.person_outline,
                        size: 18,
                      ),
                      title: Text(
                        choice.isCreate
                            ? 'Create "${choice.name}"'
                            : choice.name,
                      ),
                      onTap: () => onSelected(choice),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerChoice {
  _PickerChoice.existing(this.id, this.name) : isCreate = false;
  _PickerChoice.create(this.name) : id = null, isCreate = true;

  final String? id;
  final String name;
  final bool isCreate;

  /// Text shown in the field when this option is selected.
  String get label => name;

  /// Stable widget key for the option row. Existing items are keyed by id so
  /// two same-named entities (dedup is deferred) don't collide; the sole
  /// "create" row is keyed by its typed name.
  String get optionKey => isCreate ? 'create:$name' : id!;
}
