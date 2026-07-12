import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../widgets/figure_list_editor.dart';

/// Dance editor (`docs/design/ux.md` §3). Covers the metadata form — title,
/// authors (with inline choreographer/tag creation), formation, form/type,
/// progression, phrase structure, hook, calling notes, tunes, tags, status,
/// URL links, and values for existing custom fields — plus title-required hard
/// validation and non-blocking `validate()` warnings.
///
/// Structured figure entry (roadmap 3.3b) lives in the editable figure list
/// below the metadata; figure reordering affordances land with 3.3c.
class DanceEditorScreen extends StatefulWidget {
  const DanceEditorScreen({super.key, this.danceId});

  /// The dance being edited, or `null` to create a new dance.
  final String? danceId;

  bool get isNew => danceId == null;

  @override
  State<DanceEditorScreen> createState() => _DanceEditorScreenState();
}

class _DanceEditorScreenState extends State<DanceEditorScreen> {
  late CompendiumRepositories _repos;
  final _formKey = GlobalKey<FormState>();

  static final Taxonomy _taxonomy = contraTaxonomy;

  final _titleController = TextEditingController();
  final _hookController = TextEditingController();
  final _notesController = TextEditingController();
  final _phraseController = TextEditingController();
  final _formationDetailController = TextEditingController();
  final _tuneController = TextEditingController();

  // Custom text/number field editors, keyed by field id.
  final Map<String, TextEditingController> _customTextControllers = {};

  bool _loaded = false;
  Object? _loadError;
  bool _saving = false;

  /// The dance being edited (null for a new dance); kept to preserve figures,
  /// createdAt, provenance, and schema version on save.
  Dance? _original;

  DanceForm _form = DanceForm.contra;
  FormationShape _formationShape = FormationShape.dupleImproper;
  Progression _progression = Progression.single;
  DanceStatus _status = DanceStatus.active;

  final List<String> _authorIds = [];
  final List<String> _tagIds = [];
  final List<String> _tunes = [];
  final List<_LinkDraft> _links = [];

  /// Existing links this editor can't edit yet (relatedDance target picking is
  /// deferred). Held verbatim so an edit-save round-trip never drops them.
  final List<DanceLink> _preservedLinks = [];
  final Map<String, Object?> _customValues = {};

  List<Choreographer> _choreographers = [];
  List<Tag> _tags = [];
  List<CustomFieldDef> _fieldDefs = [];
  Map<String, String> _choreographerNames = {};
  Map<String, String> _tagNames = {};

  List<Figure> get _figures => [
    for (final draft in _figureDrafts) ?draft.toFigure(),
  ];
  final List<FigureDraft> _figureDrafts = [];
  PhraseStructure _phraseStructure = PhraseStructure.standard;
  List<ValidationIssue> _warnings = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && _loadError == null) {
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _hookController.dispose();
    _notesController.dispose();
    _phraseController.dispose();
    _formationDetailController.dispose();
    _tuneController.dispose();
    for (final c in _customTextControllers.values) {
      c.dispose();
    }
    for (final l in _links) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final choreographers = await _repos.choreographers.listAll();
      final tags = await _repos.tags.listAll();
      final fieldDefs = await _repos.customFieldDefs.listAll();
      final dance = widget.danceId == null
          ? null
          : await _repos.dances.getById(widget.danceId!);

      _choreographers = choreographers;
      _tags = tags;
      _fieldDefs = fieldDefs;
      _choreographerNames = {for (final c in choreographers) c.id: c.name};
      _tagNames = {for (final t in tags) t.id: t.name};

      if (dance != null) {
        _original = dance;
        _titleController.text = dance.title;
        _hookController.text = dance.hook;
        _notesController.text = dance.callingNotes;
        _phraseController.text = dance.phraseStructure.raw;
        _formationDetailController.text = dance.formation.detail ?? '';
        _form = dance.form;
        _formationShape = dance.formation.shape;
        _progression = dance.progression;
        _status = dance.status;
        _authorIds.addAll(dance.authorIds);
        _tagIds.addAll(dance.tagIds);
        _tunes.addAll(dance.tunes);
        for (final link in dance.links) {
          if (link.kind == LinkKind.relatedDance) {
            _preservedLinks.add(link);
          } else {
            _links.add(_LinkDraft.fromLink(link));
          }
        }
        for (final value in dance.customFields) {
          _customValues[value.fieldId] = value.value;
        }
        _figureDrafts.addAll(dance.figures.map(FigureDraft.fromFigure));
      }

      // Seed text controllers for custom text/number fields.
      for (final def in fieldDefs) {
        if (def.type == CustomFieldType.text ||
            def.type == CustomFieldType.number) {
          _customTextControllers[def.id] = TextEditingController(
            text: _customValues[def.id]?.toString() ?? '',
          );
        }
      }

      _recomputeWarnings();
      if (mounted) setState(() => _loaded = true);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Recomputes the non-blocking phrase warnings from the current figures and
  /// phrase-structure text. Invalid phrase structure is surfaced by the field
  /// validator instead, so here it just leaves the last good warnings.
  void _recomputeWarnings() {
    try {
      _phraseStructure = PhraseStructure.parse(_phraseController.text);
    } on FormatException {
      return;
    }
    final issues = <ValidationIssue>[];
    deriveSections(_figures, _phraseStructure, issues: issues);
    _warnings = issues;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Ensure the user sees the first error even if it is above the fold.
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc();
      final formationDetail = _formationDetailController.text.trim();
      final formation = Formation(
        _formationShape,
        detail: formationDetail.isEmpty ? null : formationDetail,
      );
      final links = [..._preservedLinks, for (final l in _links) ?l.toLink()];
      final customFields = _collectCustomFields();

      final Dance dance;
      if (_original case final original?) {
        dance = original.copyWith(
          title: _titleController.text.trim(),
          authorIds: List.of(_authorIds),
          form: _form,
          formation: formation,
          progression: _progression,
          phraseStructure: _phraseController.text.trim(),
          hook: _hookController.text.trim(),
          callingNotes: _notesController.text.trim(),
          status: _status,
          tunes: List.of(_tunes),
          customFields: customFields,
          tagIds: List.of(_tagIds),
          links: links,
          figures: _figures,
          updatedAt: now,
        );
        await _repos.dances.update(dance);
      } else {
        dance = Dance(
          id: uuidV4(),
          title: _titleController.text.trim(),
          authorIds: List.of(_authorIds),
          form: _form,
          formation: formation,
          progression: _progression,
          phraseStructure: _phraseController.text.trim(),
          hook: _hookController.text.trim(),
          callingNotes: _notesController.text.trim(),
          status: _status,
          tunes: List.of(_tunes),
          customFields: customFields,
          tagIds: List.of(_tagIds),
          links: links,
          figures: _figures,
          createdAt: now,
          updatedAt: now,
        );
        await _repos.dances.create(dance);
      }
      if (mounted) Navigator.of(context).pop(dance.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  List<CustomFieldValue> _collectCustomFields() {
    final values = <CustomFieldValue>[];
    for (final def in _fieldDefs) {
      Object? value;
      switch (def.type) {
        case CustomFieldType.text:
          final text = _customTextControllers[def.id]?.text.trim() ?? '';
          if (text.isNotEmpty) value = text;
        case CustomFieldType.number:
          final text = _customTextControllers[def.id]?.text.trim() ?? '';
          if (text.isNotEmpty) value = num.tryParse(text);
        case CustomFieldType.boolean:
          // Only persist when the field actually has a value — either loaded
          // from the dance or toggled by the user. Otherwise an untouched
          // switch would write a spurious `false` for every boolean def.
          if (_customValues.containsKey(def.id)) {
            value = _customValues[def.id] as bool?;
          }
        case CustomFieldType.choice:
          value = _customValues[def.id] as String?;
      }
      if (value == null) continue;
      final field = CustomFieldValue(fieldId: def.id, value: value);
      if (field.matchesType(def)) values.add(field);
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New dance' : 'Edit dance'),
        actions: [
          if (_loaded)
            TextButton(
              key: const ValueKey('save-dance'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return const Center(child: Text('Could not load the dance.'));
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const ValueKey('title-field'),
            controller: _titleController,
            autofocus: widget.isNew,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Title *',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Title is required'
                : null,
          ),
          const SizedBox(height: 16),
          _Label('Authors'),
          _NamePicker(
            fieldKey: 'author',
            selectedIds: _authorIds,
            namesById: _choreographerNames,
            options: [
              for (final c in _choreographers) (id: c.id, name: c.name),
            ],
            onAdd: (id) => setState(() => _authorIds.add(id)),
            onRemove: (id) => setState(() => _authorIds.remove(id)),
            onCreate: _createChoreographer,
          ),
          const SizedBox(height: 16),
          _Label('Formation'),
          DropdownButtonFormField<FormationShape>(
            key: const ValueKey('formation-field'),
            initialValue: _formationShape,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final shape in FormationShape.values)
                DropdownMenuItem(
                  value: shape,
                  child: Text(formationShapeLabel(shape)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _formationShape = value);
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _formationDetailController,
            decoration: const InputDecoration(
              labelText: 'Formation detail (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _EnumDropdown<DanceForm>(
                  fieldKey: 'form',
                  label: 'Form',
                  value: _form,
                  values: DanceForm.values,
                  labelOf: danceFormLabel,
                  onChanged: (v) => setState(() => _form = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EnumDropdown<Progression>(
                  fieldKey: 'progression',
                  label: 'Progression',
                  value: _progression,
                  values: Progression.values,
                  labelOf: progressionLabel,
                  onChanged: (v) => setState(() => _progression = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EnumDropdown<DanceStatus>(
            fieldKey: 'status',
            label: 'Status',
            value: _status,
            values: DanceStatus.values,
            labelOf: danceStatusLabel,
            onChanged: (v) => setState(() => _status = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('phrase-field'),
            controller: _phraseController,
            decoration: const InputDecoration(
              labelText: 'Phrase structure',
              hintText: 'Blank = standard A1 A2 B1 B2; else e.g. 6*8*2',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(_recomputeWarnings),
            validator: (value) {
              try {
                PhraseStructure.parse(value ?? '');
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _hookController,
            decoration: const InputDecoration(
              labelText: 'Hook',
              hintText: 'One-line "why call this"',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Calling notes',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          _Label('Tags'),
          _NamePicker(
            fieldKey: 'tag',
            selectedIds: _tagIds,
            namesById: _tagNames,
            options: [for (final t in _tags) (id: t.id, name: t.name)],
            onAdd: (id) => setState(() => _tagIds.add(id)),
            onRemove: (id) => setState(() => _tagIds.remove(id)),
            onCreate: _createTag,
          ),
          const SizedBox(height: 16),
          _Label('Tunes'),
          _TuneEditor(
            tunes: _tunes,
            controller: _tuneController,
            onAdd: _addTune,
            onRemove: (tune) => setState(() => _tunes.remove(tune)),
          ),
          const SizedBox(height: 16),
          _Label('Links'),
          _LinksEditor(
            links: _links,
            onAdd: () => setState(() => _links.add(_LinkDraft.empty())),
            onRemove: (draft) => setState(() {
              _links.remove(draft);
              draft.dispose();
            }),
            onChanged: () => setState(() {}),
          ),
          if (_fieldDefs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Label('Custom fields'),
            for (final def in _fieldDefs) _buildCustomField(def),
          ],
          const SizedBox(height: 24),
          Text('Figures', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Type a move (e.g. "sw" → swing) and press Enter to add it with '
            'default params; unmatched text becomes a custom figure.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FigureListEditor(
            drafts: _figureDrafts,
            taxonomy: _taxonomy,
            phraseStructure: _phraseStructure,
            onChanged: () => setState(_recomputeWarnings),
            onAdd: () => setState(() => _figureDrafts.add(FigureDraft())),
            onDelete: (draft) => setState(() {
              _figureDrafts.remove(draft);
              _recomputeWarnings();
            }),
          ),
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WarningsCard(warnings: _warnings),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCustomField(CustomFieldDef def) {
    switch (def.type) {
      case CustomFieldType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            key: ValueKey('custom-${def.id}'),
            controller: _customTextControllers[def.id],
            decoration: InputDecoration(
              labelText: def.label,
              border: const OutlineInputBorder(),
            ),
          ),
        );
      case CustomFieldType.number:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            key: ValueKey('custom-${def.id}'),
            controller: _customTextControllers[def.id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: def.label,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              return num.tryParse(text) == null ? 'Enter a number' : null;
            },
          ),
        );
      case CustomFieldType.boolean:
        return SwitchListTile(
          key: ValueKey('custom-${def.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(def.label),
          value: _customValues[def.id] as bool? ?? false,
          onChanged: (v) => setState(() => _customValues[def.id] = v),
        );
      case CustomFieldType.choice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String?>(
            key: ValueKey('custom-${def.id}'),
            initialValue: _customValues[def.id] as String?,
            decoration: InputDecoration(
              labelText: def.label,
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final choice in def.choices ?? const <String>[])
                DropdownMenuItem(value: choice, child: Text(choice)),
            ],
            onChanged: (v) => setState(() => _customValues[def.id] = v),
          ),
        );
    }
  }

  Future<String> _createChoreographer(String name) async {
    final choreographer = Choreographer(id: uuidV4(), name: name.trim());
    await _repos.choreographers.upsert(choreographer);
    _choreographers = [..._choreographers, choreographer];
    _choreographerNames = {
      ..._choreographerNames,
      choreographer.id: name.trim(),
    };
    return choreographer.id;
  }

  Future<String> _createTag(String name) async {
    final tag = Tag(id: uuidV4(), name: name.trim());
    await _repos.tags.upsert(tag);
    _tags = [..._tags, tag];
    _tagNames = {..._tagNames, tag.id: name.trim()};
    return tag.id;
  }

  void _addTune() {
    final tune = _tuneController.text.trim();
    if (tune.isEmpty || _tunes.contains(tune)) return;
    setState(() {
      _tunes.add(tune);
      _tuneController.clear();
    });
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _EnumDropdown<T> extends StatelessWidget {
  const _EnumDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$fieldKey-field'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(labelOf(v))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

typedef _NameOption = ({String id, String name});

/// Chips of selected entities plus a type-ahead that adds an existing entity
/// or creates a new one inline (`docs/design/ux.md` §3 author autocomplete).
class _NamePicker extends StatelessWidget {
  const _NamePicker({
    required this.fieldKey,
    required this.selectedIds,
    required this.namesById,
    required this.options,
    required this.onAdd,
    required this.onRemove,
    required this.onCreate,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final Map<String, String> namesById;
  final List<_NameOption> options;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final Future<String> Function(String name) onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final id in selectedIds)
                Chip(
                  key: ValueKey('$fieldKey-chip-$id'),
                  label: Text(namesById[id] ?? id),
                  onDeleted: () => onRemove(id),
                ),
            ],
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
}

class _AddAutocomplete extends StatelessWidget {
  const _AddAutocomplete({
    required this.fieldKey,
    required this.selectedIds,
    required this.options,
    required this.onAdd,
    required this.onCreate,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final List<_NameOption> options;
  final ValueChanged<String> onAdd;
  final Future<String> Function(String name) onCreate;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_PickerChoice>(
      key: ValueKey('$fieldKey-autocomplete'),
      displayStringForOption: (choice) => choice.label,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<_PickerChoice>.empty();
        final lower = q.toLowerCase();
        final matches = options
            .where(
              (o) =>
                  !selectedIds.contains(o.id) &&
                  o.name.toLowerCase().contains(lower),
            )
            .map((o) => _PickerChoice.existing(o.id, o.name))
            .toList();
        final exact = options.any((o) => o.name.toLowerCase() == lower);
        if (!exact) matches.add(_PickerChoice.create(q));
        return matches;
      },
      onSelected: (choice) async {
        if (choice.isCreate) {
          final id = await onCreate(choice.name);
          onAdd(id);
        } else {
          onAdd(choice.id!);
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: ValueKey('$fieldKey-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Type to add or create…',
            isDense: true,
            border: OutlineInputBorder(),
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

class _TuneEditor extends StatelessWidget {
  const _TuneEditor({
    required this.tunes,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tunes;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tunes.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final tune in tunes)
                Chip(
                  key: ValueKey('tune-chip-$tune'),
                  label: Text(tune),
                  onDeleted: () => onRemove(tune),
                ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('tune-field'),
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Add a suggested tune…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('tune-add'),
              tooltip: 'Add tune',
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}

class _LinksEditor extends StatelessWidget {
  const _LinksEditor({
    required this.links,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<_LinkDraft> links;
  final VoidCallback onAdd;
  final ValueChanged<_LinkDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in links)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<LinkKind>(
                    key: ValueKey('link-kind-${draft.id}'),
                    initialValue: draft.kind,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LinkKind.source,
                        child: Text('Source'),
                      ),
                      DropdownMenuItem(
                        value: LinkKind.video,
                        child: Text('Video'),
                      ),
                      DropdownMenuItem(
                        value: LinkKind.other,
                        child: Text('Other'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        draft.kind = value;
                        onChanged();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        key: ValueKey('link-url-${draft.id}'),
                        controller: draft.urlController,
                        decoration: const InputDecoration(
                          labelText: 'URL',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: draft.labelController,
                        decoration: const InputDecoration(
                          labelText: 'Label (optional)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('link-remove-${draft.id}'),
                  tooltip: 'Remove link',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(draft),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('link-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add link'),
          ),
        ),
      ],
    );
  }
}

/// Mutable editing state for a single [DanceLink] (URL-based kinds only in
/// 3.3a; relatedDance target picking is deferred).
class _LinkDraft {
  _LinkDraft({
    required this.id,
    required this.kind,
    required this.urlController,
    required this.labelController,
  });

  factory _LinkDraft.empty() => _LinkDraft(
    id: uuidV4(),
    kind: LinkKind.source,
    urlController: TextEditingController(),
    labelController: TextEditingController(),
  );

  factory _LinkDraft.fromLink(DanceLink link) => _LinkDraft(
    id: link.id,
    kind: link.kind,
    urlController: TextEditingController(text: link.url ?? ''),
    labelController: TextEditingController(text: link.label ?? ''),
  );

  final String id;
  LinkKind kind;
  final TextEditingController urlController;
  final TextEditingController labelController;

  /// Builds a [DanceLink], or `null` when the URL is blank (skipped on save).
  DanceLink? toLink() {
    final url = urlController.text.trim();
    if (url.isEmpty) return null;
    final label = labelController.text.trim();
    return DanceLink(
      id: id,
      kind: kind,
      url: url,
      label: label.isEmpty ? null : label,
    );
  }

  void dispose() {
    urlController.dispose();
    labelController.dispose();
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('warnings-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text('Warnings', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${warning.message}'),
            ),
        ],
      ),
    );
  }
}
