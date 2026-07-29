import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';

/// Localized label for a [CustomFieldType]. Mirrors the app-side enum-label
/// helper pattern (see `search/facet_labels.dart`): the enum lives in the
/// Flutter-free `compendium_core` package (ADR-001) so it cannot carry an
/// `AppLocalizations`-aware label itself.
String customFieldTypeLabel(AppLocalizations l10n, CustomFieldType type) =>
    switch (type) {
      CustomFieldType.text => l10n.customFieldsTypeText,
      CustomFieldType.number => l10n.customFieldsTypeNumber,
      CustomFieldType.boolean => l10n.customFieldsTypeBoolean,
      CustomFieldType.choice => l10n.customFieldsTypeChoice,
    };

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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.customFieldsDeleteTitle),
        content: Text(l10n.customFieldsDeleteBody(def.label)),
        actions: [
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repos.customFieldDefs.delete(def.id);
      await _load();
    } on StateError catch (e, st) {
      if (!mounted) return;
      // The repo throws StateError when values still exist on dances. Log the
      // raw error for diagnostics only (CWE-209: never surface it in the UI);
      // extract the dance count from the message to pluralize the clean message.
      debugPrint('custom field delete blocked: $e\n$st');
      final countMatch = RegExp(r'(\d+) dance').firstMatch(e.message);
      final String message;
      if (countMatch != null) {
        final n = int.tryParse(countMatch.group(1)!) ?? 0;
        message = l10n.customFieldsDeleteInUse(def.label, n);
      } else {
        message = l10n.customFieldsDeleteInUseUnknown(def.label);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('delete-in-use-snackbar'),
          content: Text(message),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.customFieldsTitle)),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-field'),
        heroTag: 'add-field',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: Text(l10n.customFieldsNewField),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
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
            Text(l10n.customFieldsLoadError),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    if (_defs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.customFieldsEmpty, textAlign: TextAlign.center),
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
    final l10n = AppLocalizations.of(context);
    final flags = <String>[];
    if (def.showInList) flags.add(l10n.customFieldsFlagInList);
    if (def.searchable) flags.add(l10n.customFieldsSearchable);
    final subtitle = [
      customFieldTypeLabel(l10n, def.type),
      ...flags,
    ].join(' · ');

    return ListTile(
      key: ValueKey('field-tile-${def.id}'),
      title: Text(def.label),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('edit-field-${def.id}'),
            tooltip: l10n.commonEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            key: ValueKey('delete-field-${def.id}'),
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
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
    final l10n = AppLocalizations.of(context);
    // Validate choices list before calling form.validate (it's not a FormField).
    setState(() {
      _choicesError = (_type == CustomFieldType.choice && _choices.isEmpty)
          ? l10n.customFieldsValidatorMinChoice
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
    final l10n = AppLocalizations.of(context);
    // Soft-clamp to the shared bound (OWASP): trim + cap length; empty is a
    // no-op. Duplicate (against the clamped value) surfaces an inline error so
    // the user understands why nothing was added.
    final normalized = normalizeChoiceOption(value);
    if (normalized == null) return;
    if (_choices.contains(normalized)) {
      setState(() => _choicesError = l10n.customFieldsChoiceDuplicate);
      return;
    }
    setState(() {
      _choices.add(normalized);
      _choicesError = null;
    });
  }

  void _removeChoice(String value) {
    if (widget.usedChoiceValues.contains(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('choice-in-use-snackbar'),
          content: Text(
            AppLocalizations.of(context).customFieldsRemoveValueError(value),
          ),
        ),
      );
      return;
    }
    setState(() => _choices.remove(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                _isNew
                    ? l10n.customFieldsEditorNewTitle
                    : l10n.customFieldsEditorEditTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('cf-label'),
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: l10n.customFieldsLabelLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.customFieldsLabelRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('cf-key'),
                controller: _keyController,
                enabled: _keyEditable,
                decoration: InputDecoration(
                  labelText: l10n.customFieldsKeyLabel,
                  helperText: _keyEditable
                      ? l10n.customFieldsKeyHelper
                      : l10n.customFieldsKeyLocked,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return l10n.customFieldsKeyRequired;
                  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(trimmed)) {
                    return l10n.customFieldsKeyInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CustomFieldType>(
                key: const ValueKey('cf-type'),
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.customFieldsTypeFieldLabel,
                  border: const OutlineInputBorder(),
                  helperText: _typeEditable
                      ? null
                      : l10n.customFieldsTypeLocked,
                ),
                items: [
                  for (final t in CustomFieldType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(customFieldTypeLabel(l10n, t)),
                    ),
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
                title: Text(l10n.customFieldsShowInList),
                subtitle: Text(l10n.customFieldsShowInListSubtitle),
                value: _showInList,
                onChanged: (v) => setState(() => _showInList = v),
              ),
              SwitchListTile(
                key: const ValueKey('cf-searchable'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.customFieldsSearchable),
                subtitle: Text(l10n.customFieldsSearchableSubtitle),
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
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('cf-form-save'),
                    onPressed: _save,
                    child: Text(l10n.commonSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.customFieldsChoicesLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
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
                        message: l10n.customFieldsChoiceInUseTooltip,
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
                      tooltip: inUse
                          ? l10n.customFieldsChoiceInUseTooltip
                          : l10n.commonRemove,
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
                maxLength: kMaxCustomFieldChoiceLength,
                decoration: InputDecoration(
                  hintText: l10n.customFieldsNewChoiceHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  counterText: '',
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
              tooltip: l10n.customFieldsAddChoiceTooltip,
            ),
          ],
        ),
      ],
    );
  }
}
