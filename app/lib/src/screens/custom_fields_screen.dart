import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';

/// Manages the user-defined custom field schema (`docs/design/ux.md` §4).
///
/// Lists all [CustomFieldDef]s and lets the user create, edit, and delete them.
/// Reached from the Collection screen's app-bar "Manage custom fields" action.
///
/// **Mutability guards (flagged product decisions, implemented as defaults):**
/// - Type is immutable once a field has values on any dance (changing type would
///   strand/mis-decode stored values — no value-migration in v1).
/// - Key is editable only while the field is unused (it is the stable
///   storage/search key).
/// - Label, showInList, and searchable are always editable.
/// - For choice fields: adding choices is always fine; removing a choice that
///   is currently in use on any dance is blocked with a clear message.
class CustomFieldsScreen extends StatefulWidget {
  const CustomFieldsScreen({super.key});

  @override
  State<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends State<CustomFieldsScreen> {
  late CompendiumRepositories _repos;
  bool _started = false;

  List<CustomFieldDef> _defs = [];
  bool _loading = true;
  Object? _loadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repos = RepositoriesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    try {
      final defs = await _repos.customFieldDefs.listAll();
      if (!mounted) return;
      setState(() {
        _defs = defs;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _openForm({CustomFieldDef? existing}) async {
    // For edit mode, check usage directly on the customFieldValues table
    // (avoids loading the entire dance collection just for an in-use flag).
    Set<String> usedChoiceValues = {};
    bool inUse = false;
    if (existing != null) {
      inUse = await _repos.customFieldDefs.isInUse(existing.id);
      if (existing.type == CustomFieldType.choice && inUse) {
        usedChoiceValues = await _repos.customFieldDefs.listUsedChoiceValues(
          existing.id,
        );
      }
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<CustomFieldDef>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomFieldForm(
        existing: existing,
        inUse: inUse,
        usedChoiceValues: usedChoiceValues,
      ),
    );
    if (result != null) {
      await _repos.customFieldDefs.upsert(result);
      await _load();
    }
  }

  Future<void> _delete(CustomFieldDef def) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete custom field'),
        content: Text('Delete "${def.label}"? This cannot be undone.'),
        actions: [
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repos.customFieldDefs.delete(def.id);
      await _load();
    } on StateError catch (e) {
      if (!mounted) return;
      // The repo throws StateError when values still exist on dances.
      // Extract the dance count from the error message and pluralize correctly.
      final msg = e.message;
      final countMatch = RegExp(r'(\d+) dance').firstMatch(msg);
      final String countLabel;
      if (countMatch != null) {
        final n = int.tryParse(countMatch.group(1)!) ?? 0;
        countLabel = n == 1 ? '1 dance' : '$n dances';
      } else {
        countLabel = 'some dances';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('delete-in-use-snackbar'),
          content: Text(
            'Can\'t delete "${def.label}": still used by $countLabel. '
            'Remove the value from all dances first.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom fields')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-field'),
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New field'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Could not load custom fields.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_defs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No custom fields yet.\nTap + to define one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _defs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final def = _defs[index];
        return _FieldTile(
          def: def,
          onEdit: () => _openForm(existing: def),
          onDelete: () => _delete(def),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Field list tile
// ---------------------------------------------------------------------------

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.def,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomFieldDef def;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final flags = <String>[];
    if (def.showInList) flags.add('In list');
    if (def.searchable) flags.add('Searchable');
    final subtitle = [_typeLabel(def.type), ...flags].join(' · ');

    return ListTile(
      key: ValueKey('field-tile-${def.id}'),
      title: Text(def.label),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('edit-field-${def.id}'),
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            key: ValueKey('delete-field-${def.id}'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _typeLabel(CustomFieldType type) => switch (type) {
    CustomFieldType.text => 'Text',
    CustomFieldType.number => 'Number',
    CustomFieldType.boolean => 'Boolean',
    CustomFieldType.choice => 'Choice',
  };
}

// ---------------------------------------------------------------------------
// Create / edit form (modal bottom sheet)
// ---------------------------------------------------------------------------

class _CustomFieldForm extends StatefulWidget {
  const _CustomFieldForm({
    this.existing,
    required this.inUse,
    required this.usedChoiceValues,
  });

  /// `null` when creating a new field.
  final CustomFieldDef? existing;

  /// True when at least one dance has a value for this field.
  final bool inUse;

  /// The set of choice strings currently stored on some dance. Only meaningful
  /// for choice-type fields; empty for all other types.
  final Set<String> usedChoiceValues;

  @override
  State<_CustomFieldForm> createState() => _CustomFieldFormState();
}

class _CustomFieldFormState extends State<_CustomFieldForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelController;
  late final TextEditingController _keyController;
  late CustomFieldType _type;
  final List<String> _choices = [];
  bool _showInList = false;
  bool _searchable = true;

  // Inline error for the choices list (not a form field).
  String? _choicesError;

  @override
  void initState() {
    super.initState();
    final def = widget.existing;
    _labelController = TextEditingController(text: def?.label ?? '');
    _keyController = TextEditingController(text: def?.key ?? '');
    _type = def?.type ?? CustomFieldType.text;
    if (def?.choices != null) _choices.addAll(def!.choices!);
    _showInList = def?.showInList ?? false;
    _searchable = def?.searchable ?? true;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;
  bool get _typeEditable => _isNew || !widget.inUse;
  bool get _keyEditable => _isNew || !widget.inUse;

  void _save() {
    // Validate choices list before calling form.validate (it's not a FormField).
    setState(() {
      _choicesError = (_type == CustomFieldType.choice && _choices.isEmpty)
          ? 'Add at least one choice'
          : null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_choicesError != null) return;

    final id = widget.existing?.id ?? uuidV4();
    try {
      final def = CustomFieldDef(
        id: id,
        key: _keyController.text.trim(),
        label: _labelController.text.trim(),
        type: _type,
        choices: _type == CustomFieldType.choice
            ? List.unmodifiable(_choices)
            : null,
        showInList: _showInList,
        searchable: _searchable,
      );
      Navigator.of(context).pop(def);
    } on ArgumentError catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message.toString())));
    }
  }

  void _addChoice(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_choices.contains(trimmed)) return;
    setState(() {
      _choices.add(trimmed);
      _choicesError = null;
    });
  }

  void _removeChoice(String value) {
    if (widget.usedChoiceValues.contains(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('choice-in-use-snackbar'),
          content: Text(
            'Can\'t remove "$value": it\'s set on at least one dance.',
          ),
        ),
      );
      return;
    }
    setState(() => _choices.remove(value));
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isNew ? 'New custom field' : 'Edit custom field',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('cf-label'),
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Label is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('cf-key'),
                controller: _keyController,
                enabled: _keyEditable,
                decoration: InputDecoration(
                  labelText: 'Key *',
                  helperText: _keyEditable
                      ? 'Stable machine key (letters, digits, underscores; '
                            'must start with a letter or underscore)'
                      : 'Key is locked — field is in use on dances',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Key is required';
                  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(trimmed)) {
                    return 'Key must start with a letter or underscore and '
                        'contain only letters, digits, and underscores';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CustomFieldType>(
                key: const ValueKey('cf-type'),
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'Type',
                  border: const OutlineInputBorder(),
                  helperText: _typeEditable
                      ? null
                      : 'Type is locked — field has values on dances',
                ),
                items: [
                  for (final t in CustomFieldType.values)
                    DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                ],
                onChanged: _typeEditable
                    ? (v) {
                        if (v != null) setState(() => _type = v);
                      }
                    : null,
              ),
              if (_type == CustomFieldType.choice) ...[
                const SizedBox(height: 12),
                _ChoicesEditor(
                  choices: _choices,
                  usedChoices: widget.usedChoiceValues,
                  error: _choicesError,
                  onAdd: _addChoice,
                  onRemove: _removeChoice,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      final item = _choices.removeAt(oldIndex);
                      _choices.insert(newIndex, item);
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                key: const ValueKey('cf-show-in-list'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show in list'),
                subtitle: const Text(
                  'Display this field value in the dance list tile',
                ),
                value: _showInList,
                onChanged: (v) => setState(() => _showInList = v),
              ),
              SwitchListTile(
                key: const ValueKey('cf-searchable'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Searchable'),
                subtitle: const Text(
                  'Expose this field as a filter in the search panel',
                ),
                value: _searchable,
                onChanged: (v) => setState(() => _searchable = v),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('cf-form-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('cf-form-save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(CustomFieldType type) => switch (type) {
    CustomFieldType.text => 'Text',
    CustomFieldType.number => 'Number',
    CustomFieldType.boolean => 'Boolean',
    CustomFieldType.choice => 'Choice',
  };
}

// ---------------------------------------------------------------------------
// Choices editor sub-widget
// ---------------------------------------------------------------------------

class _ChoicesEditor extends StatefulWidget {
  const _ChoicesEditor({
    required this.choices,
    required this.usedChoices,
    required this.error,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  final List<String> choices;
  final Set<String> usedChoices;
  final String? error;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<_ChoicesEditor> createState() => _ChoicesEditorState();
}

class _ChoicesEditorState extends State<_ChoicesEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choices *', style: Theme.of(context).textTheme.labelLarge),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (widget.choices.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              widget.onReorder(oldIndex, newIndex);
            },
            itemCount: widget.choices.length,
            itemBuilder: (context, index) {
              final choice = widget.choices[index];
              final inUse = widget.usedChoices.contains(choice);
              return ListTile(
                key: ValueKey('choice-$choice'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
                title: Text(choice),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inUse)
                      Tooltip(
                        message: 'In use — cannot remove',
                        child: Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    IconButton(
                      key: ValueKey('remove-choice-$choice'),
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => widget.onRemove(choice),
                      tooltip: inUse ? 'In use — cannot remove' : 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('choice-input'),
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'New choice…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  widget.onAdd(value);
                  _controller.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('add-choice'),
              onPressed: () {
                widget.onAdd(_controller.text);
                _controller.clear();
              },
              icon: const Icon(Icons.add),
              tooltip: 'Add choice',
            ),
          ],
        ),
      ],
    );
  }
}
