import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../editor/editor_draft_codec.dart';
import '../editor/editor_snapshot.dart';
import '../editor/editor_undo_stack.dart';
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
  bool _loadStarted = false;
  Object? _loadError;
  bool _saving = false;

  // ---- Undo / redo ----
  final _undoStack = EditorUndoStack();

  /// `true` while we are restoring a snapshot via [_applySnapshot] so that
  /// [_pushUndoNow] does not push a spurious extra entry.
  bool _applyingSnapshot = false;

  // ---- Autosave timers ----
  Timer? _undoTimer;
  Timer? _autosaveTimer;

  String get _draftKey => 'editor_draft:${widget.danceId ?? 'new'}';

  /// A decoded draft snapshot waiting to be restored or discarded.
  /// Set by [_load] when a draft exists; cleared by [_maybeShowRestoreDialog].
  EditorSnapshot? _pendingDraft;

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

  final Map<String, Object?> _customValues = {};

  List<Dance> _allDances = [];
  Map<String, String> _danceNamesById = {};

  /// Dance options for the related-dance picker: all non-deleted dances except
  /// the dance currently being edited.
  List<_NameOption> get _danceOptions => [
    for (final d in _allDances)
      if (d.id != widget.danceId) (id: d.id, name: d.title),
  ];

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
    // Guard against `didChangeDependencies` firing again before the first
    // `_load()` future completes: `_load()` appends into mutable collections
    // (drafts, link controllers), so a second run would duplicate state and
    // leak controllers. Kick it off exactly once per widget instance.
    if (!_loadStarted) {
      _loadStarted = true;
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _autosaveTimer?.cancel();
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
      final allDances = await _repos.dances.listAll();
      final dance = widget.danceId == null
          ? null
          : await _repos.dances.getById(widget.danceId!);

      _choreographers = choreographers;
      _tags = tags;
      _fieldDefs = fieldDefs;
      _allDances = allDances;
      _danceNamesById = {for (final d in allDances) d.id: d.title};
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
          _links.add(
            _LinkDraft.fromLink(
              link,
              danceTitle: _danceNamesById[link.targetDanceId],
            ),
          );
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

      // Check for an autosaved draft and schedule a restore/discard prompt.
      if (mounted && await _repos.settings.contains(_draftKey)) {
        final raw = await _repos.settings.get(_draftKey);
        EditorSnapshot? draftSnapshot;
        try {
          draftSnapshot = decodeDraft(raw);
        } catch (_) {
          // Corrupt / unrecognised draft version — silently discard.
          await _repos.settings.remove(_draftKey);
        }
        if (draftSnapshot != null && mounted) {
          _pendingDraft = draftSnapshot;
        }
      }

      // Seed the initial undo entry so the user can always undo back to the
      // loaded (or restored-draft) state.
      _undoStack.push(_captureSnapshot());

      if (mounted) {
        setState(() => _loaded = true);
        // Show the restore/discard dialog AFTER the first build frame so
        // WidgetTester.pumpAndSettle() can settle on the loaded editor before
        // the dialog animation starts.
        if (_pendingDraft != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _maybeShowRestoreDialog(),
          );
        }
      }
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
      final links = [for (final l in _links) ?l.toLink()];
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
      // Clear the autosave draft — work is now committed.
      await _clearDraft();
      if (mounted) Navigator.of(context).pop(dance.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  // -------------------------------------------------------------------------
  // Undo / redo helpers
  // -------------------------------------------------------------------------

  /// Captures an immutable snapshot of the current editor working state.
  EditorSnapshot _captureSnapshot() => EditorSnapshot(
    title: _titleController.text,
    hook: _hookController.text,
    notes: _notesController.text,
    phrase: _phraseController.text,
    formationDetail: _formationDetailController.text,
    form: _form,
    formationShape: _formationShape,
    progression: _progression,
    status: _status,
    authorIds: List.unmodifiable(_authorIds),
    tagIds: List.unmodifiable(_tagIds),
    tunes: List.unmodifiable(_tunes),
    links: List.unmodifiable(
      _links.map(
        (l) => LinkSnapshot(
          id: l.id,
          kind: l.kind,
          url: l.urlController.text,
          label: l.labelController.text,
          targetDanceId: l.targetDanceId,
        ),
      ),
    ),
    // Custom text/number fields are edited via _customTextControllers and do
    // not keep _customValues in sync — read from the controllers directly so
    // the snapshot captures whatever the user has typed.
    customValues: Map.unmodifiable({
      ..._customValues, // boolean / choice values
      for (final def in _fieldDefs)
        if ((def.type == CustomFieldType.text ||
                def.type == CustomFieldType.number) &&
            _customTextControllers.containsKey(def.id))
          def.id: _customTextControllers[def.id]!.text,
    }),
    figureDrafts: List.unmodifiable(
      _figureDrafts.map(FigureDraftSnapshot.fromDraft),
    ),
  );

  /// Restores working state from [snapshot], resyncing all text controllers.
  ///
  /// Must be called inside an [_applyingSnapshot] guard so [_pushUndoNow]
  /// is suppressed during the apply.
  void _applySnapshot(EditorSnapshot s) {
    // Resync text controllers (guarded: don't clobber identical text).
    if (_titleController.text != s.title) _titleController.text = s.title;
    if (_hookController.text != s.hook) _hookController.text = s.hook;
    if (_notesController.text != s.notes) _notesController.text = s.notes;
    if (_phraseController.text != s.phrase) _phraseController.text = s.phrase;
    if (_formationDetailController.text != s.formationDetail) {
      _formationDetailController.text = s.formationDetail;
    }

    // Enum fields.
    _form = s.form;
    _formationShape = s.formationShape;
    _progression = s.progression;
    _status = s.status;

    // Multi-value lists.
    _authorIds
      ..clear()
      ..addAll(s.authorIds);
    _tagIds
      ..clear()
      ..addAll(s.tagIds);
    _tunes
      ..clear()
      ..addAll(s.tunes);

    // URL-kind and relatedDance links: dispose old drafts, reconstruct from snapshot.
    for (final l in _links) {
      l.dispose();
    }
    _links
      ..clear()
      ..addAll(
        s.links.map(
          (ls) => _LinkDraft.fromSnapshot(
            ls,
            danceTitle: _danceNamesById[ls.targetDanceId],
          ),
        ),
      );

    // Custom values.
    _customValues
      ..clear()
      ..addAll(s.customValues);

    // Resync custom text/number controllers.
    for (final def in _fieldDefs) {
      if (def.type == CustomFieldType.text ||
          def.type == CustomFieldType.number) {
        final controller = _customTextControllers[def.id];
        final newText = _customValues[def.id]?.toString() ?? '';
        if (controller != null && controller.text != newText) {
          controller.text = newText;
        }
      }
    }

    // Figure drafts: recreate from snapshots so FigureDraft identities change
    // and the FigureListEditor rebuilds cleanly.
    _figureDrafts
      ..clear()
      ..addAll(s.figureDrafts.map((d) => d.toDraft()));

    _recomputeWarnings();
  }

  /// Pushes the current editor state onto the undo stack immediately.
  /// No-op while [_applyingSnapshot] is true (prevents undo-of-undo loops)
  /// and before the initial load completes.
  void _pushUndoNow() {
    _undoTimer?.cancel();
    if (!_applyingSnapshot && _loaded) {
      _undoStack.push(_captureSnapshot());
    }
  }

  /// Debounces undo pushes for rapid text-field edits (500 ms).
  void _scheduleUndoPush() {
    if (_applyingSnapshot || !_loaded) return;
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_applyingSnapshot && _loaded) {
        _undoStack.push(_captureSnapshot());
        setState(() {}); // Refresh canUndo/canRedo button states.
      }
    });
  }

  /// Debounces autosave writes (500 ms after last change).
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  void _undo() {
    if (!_undoStack.canUndo) return;
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    _applyingSnapshot = true;
    try {
      _applySnapshot(_undoStack.undo());
    } finally {
      _applyingSnapshot = false;
    }
    setState(() {});
    _scheduleAutosave();
  }

  void _redo() {
    if (!_undoStack.canRedo) return;
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    _applyingSnapshot = true;
    try {
      _applySnapshot(_undoStack.redo());
    } finally {
      _applyingSnapshot = false;
    }
    setState(() {});
    _scheduleAutosave();
  }

  // -------------------------------------------------------------------------
  // Autosave draft helpers
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Draft restore dialog
  // -------------------------------------------------------------------------

  /// Shows the restore/discard dialog for a pending autosave draft.
  /// Called from a [WidgetsBinding.addPostFrameCallback] so it fires AFTER
  /// the first build, ensuring [WidgetTester.pumpAndSettle] can settle on the
  /// loaded editor state before the dialog animation begins.
  Future<void> _maybeShowRestoreDialog() async {
    final draft = _pendingDraft;
    if (draft == null || !mounted) return;
    _pendingDraft = null;

    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved draft'),
        content: const Text(
          'You have an unsaved draft for this dance. '
          'Would you like to restore it?',
        ),
        actions: [
          TextButton(
            key: const ValueKey('draft-discard'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Discard'),
          ),
          FilledButton(
            key: const ValueKey('draft-restore'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (restore == true) {
      _applyingSnapshot = true;
      try {
        _applySnapshot(draft);
      } finally {
        _applyingSnapshot = false;
      }
      // Reset the stack so the restored state IS the initial undo floor —
      // the user cannot "undo the restore" back to the pre-restore state.
      _undoStack.clear();
      _undoStack.push(_captureSnapshot());
      setState(() {});
    } else {
      await _repos.settings.remove(_draftKey);
    }
  }

  Future<void> _saveDraft() async {
    if (!_loaded || !mounted) return;
    final encoded = encodeDraft(_captureSnapshot());
    await _repos.settings.set(_draftKey, encoded);
  }

  Future<void> _clearDraft() async {
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    await _repos.settings.remove(_draftKey);
  }

  /// Called when the user navigates back without saving (Back button /
  /// system gesture). Clears the draft and then pops programmatically.
  Future<void> _clearAndPop() async {
    await _clearDraft();
    if (mounted) Navigator.of(context).pop();
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
    return PopScope(
      // canPop: false — Back button / system gesture is intercepted so we can
      // clear the autosave draft before leaving.  Programmatic Navigator.pop()
      // (called by _save) bypasses canPop and is not affected.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_clearAndPop());
      },
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              const _UndoIntent(),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              const _UndoIntent(),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): const _RedoIntent(),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): const _RedoIntent(),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true):
              const _RedoIntent(),
        },
        child: Actions(
          actions: {
            _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) => _undo()),
            _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) => _redo()),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: Text(widget.isNew ? 'New dance' : 'Edit dance'),
                actions: [
                  if (_loaded) ...[
                    Semantics(
                      label: 'Undo',
                      child: IconButton(
                        key: const ValueKey('undo-button'),
                        tooltip: 'Undo (Ctrl+Z)',
                        icon: const Icon(Icons.undo),
                        onPressed: _undoStack.canUndo ? _undo : null,
                      ),
                    ),
                    Semantics(
                      label: 'Redo',
                      child: IconButton(
                        key: const ValueKey('redo-button'),
                        tooltip: 'Redo (Ctrl+Shift+Z)',
                        icon: const Icon(Icons.redo),
                        onPressed: _undoStack.canRedo ? _redo : null,
                      ),
                    ),
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
                ],
              ),
              body: _buildBody(),
            ),
          ),
        ),
      ),
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
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
            onAdd: (id) {
              // Reached after an await in the picker's onSelected (create
              // flow), so the editor may have been disposed meanwhile.
              if (!mounted) return;
              setState(() => _authorIds.add(id));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onRemove: (id) {
              setState(() => _authorIds.remove(id));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onCreate: _createChoreographer,
          ),
          const SizedBox(height: 16),
          _Label('Formation'),
          // Key includes the value so a undo/redo that changes _formationShape
          // forces the DropdownButtonFormField to rebuild with the new state.
          DropdownButtonFormField<FormationShape>(
            key: ValueKey('formation-field-${_formationShape.name}'),
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
              if (value != null) {
                setState(() => _formationShape = value);
                _pushUndoNow();
                _scheduleAutosave();
              }
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _formationDetailController,
            decoration: const InputDecoration(
              labelText: 'Formation detail (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
                  onChanged: (v) {
                    setState(() => _form = v);
                    _pushUndoNow();
                    _scheduleAutosave();
                  },
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
                  onChanged: (v) {
                    setState(() => _progression = v);
                    _pushUndoNow();
                    _scheduleAutosave();
                  },
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
            onChanged: (v) {
              setState(() => _status = v);
              _pushUndoNow();
              _scheduleAutosave();
            },
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
            onChanged: (_) {
              setState(_recomputeWarnings);
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
          ),
          const SizedBox(height: 16),
          _Label('Tags'),
          _NamePicker(
            fieldKey: 'tag',
            selectedIds: _tagIds,
            namesById: _tagNames,
            options: [for (final t in _tags) (id: t.id, name: t.name)],
            onAdd: (id) {
              // Reached after an await in the picker's onSelected (create
              // flow), so the editor may have been disposed meanwhile.
              if (!mounted) return;
              setState(() => _tagIds.add(id));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onRemove: (id) {
              setState(() => _tagIds.remove(id));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onCreate: _createTag,
          ),
          const SizedBox(height: 16),
          _Label('Tunes'),
          _TuneEditor(
            tunes: _tunes,
            controller: _tuneController,
            onAdd: _addTune,
            onRemove: (tune) {
              setState(() => _tunes.remove(tune));
              _pushUndoNow();
              _scheduleAutosave();
            },
          ),
          const SizedBox(height: 16),
          _Label('Links'),
          _LinksEditor(
            links: _links,
            danceOptions: _danceOptions,
            danceNamesById: _danceNamesById,
            onAdd: () {
              setState(() => _links.add(_LinkDraft.empty()));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onRemove: (draft) {
              setState(() {
                _links.remove(draft);
                draft.dispose();
              });
              _pushUndoNow();
              _scheduleAutosave();
            },
            onChanged: () {
              setState(() {});
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
            dialect: ActiveDialectScope.of(context),
            onChanged: () {
              setState(_recomputeWarnings);
              _scheduleUndoPush();
              _scheduleAutosave();
            },
            onAdd: () {
              setState(() => _figureDrafts.add(FigureDraft()));
              _pushUndoNow();
              _scheduleAutosave();
            },
            onDelete: (draft) {
              setState(() {
                _figureDrafts.remove(draft);
                _recomputeWarnings();
              });
              _pushUndoNow();
              _scheduleAutosave();
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                // onReorder uses pre-adjusted (onReorderItem) semantics —
                // newIndex is the final insertion position after removal.
                final draft = _figureDrafts.removeAt(oldIndex);
                _figureDrafts.insert(newIndex, draft);
                _recomputeWarnings();
              });
              _pushUndoNow();
              _scheduleAutosave();
            },
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
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
            onChanged: (_) {
              _scheduleUndoPush();
              _scheduleAutosave();
            },
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
          onChanged: (v) {
            setState(() => _customValues[def.id] = v);
            _pushUndoNow();
            _scheduleAutosave();
          },
        );
      case CustomFieldType.choice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String?>(
            // Value-based key so undo/redo forces a rebuild with new state.
            key: ValueKey('custom-${def.id}-${_customValues[def.id]}'),
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
            onChanged: (v) {
              setState(() => _customValues[def.id] = v);
              _pushUndoNow();
              _scheduleAutosave();
            },
          ),
        );
    }
  }

  Future<String> _createChoreographer(String name) async {
    final choreographer = Choreographer(id: uuidV4(), name: name.trim());
    await _repos.choreographers.upsert(choreographer);
    // The upsert is the durable effect; only touch in-memory caches if we're
    // still mounted (the create flow awaits this from the picker).
    if (mounted) {
      _choreographers = [..._choreographers, choreographer];
      _choreographerNames = {
        ..._choreographerNames,
        choreographer.id: name.trim(),
      };
    }
    return choreographer.id;
  }

  Future<String> _createTag(String name) async {
    final tag = Tag(id: uuidV4(), name: name.trim());
    await _repos.tags.upsert(tag);
    if (mounted) {
      _tags = [..._tags, tag];
      _tagNames = {..._tagNames, tag.id: name.trim()};
    }
    return tag.id;
  }

  void _addTune() {
    final tune = _tuneController.text.trim();
    if (tune.isEmpty || _tunes.contains(tune)) return;
    setState(() {
      _tunes.add(tune);
      _tuneController.clear();
    });
    _pushUndoNow();
    _scheduleAutosave();
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
      // Value-based key: forces the FormField to rebuild with fresh state when
      // the parent changes `value` externally (e.g. via undo/redo), since
      // DropdownButtonFormField does not re-initialize its state from
      // `initialValue` after construction.
      key: ValueKey('$fieldKey-field-$value'),
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
    required this.danceOptions,
    required this.danceNamesById,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<_LinkDraft> links;

  /// Non-deleted dances eligible for relatedDance selection (self excluded).
  final List<_NameOption> danceOptions;

  /// Title lookup for resolving a [_LinkDraft.targetDanceId] to its display
  /// name. A missing entry means the target dance was deleted/purged.
  final Map<String, String> danceNamesById;

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
                      DropdownMenuItem(
                        value: LinkKind.relatedDance,
                        child: Text('Related'),
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
                      if (draft.kind == LinkKind.relatedDance)
                        _RelatedDancePicker(
                          key: ValueKey(
                            'link-dance-picker-${draft.id}-'
                            '${draft.targetDanceId ?? 'null'}',
                          ),
                          initialTitle: draft.targetDanceId == null
                              ? ''
                              : (danceNamesById[draft.targetDanceId!] ??
                                    '(missing dance)'),
                          danceOptions: danceOptions,
                          onSelected: (id) {
                            draft.targetDanceId = id;
                            onChanged();
                          },
                        )
                      else
                        TextField(
                          key: ValueKey('link-url-${draft.id}'),
                          controller: draft.urlController,
                          decoration: const InputDecoration(
                            labelText: 'URL',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      const SizedBox(height: 4),
                      TextField(
                        key: ValueKey('link-label-${draft.id}'),
                        controller: draft.labelController,
                        decoration: const InputDecoration(
                          labelText: 'Label (optional)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => onChanged(),
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

/// Dance type-ahead for selecting a related dance in a link row.
///
/// Keyed externally on `draft.id + targetDanceId` so it is recreated (and
/// [initialTitle] applied) whenever the selection changes via undo/redo.
class _RelatedDancePicker extends StatelessWidget {
  const _RelatedDancePicker({
    super.key,
    required this.initialTitle,
    required this.danceOptions,
    required this.onSelected,
  });

  final String initialTitle;
  final List<_NameOption> danceOptions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_NameOption>(
      initialValue: TextEditingValue(text: initialTitle),
      displayStringForOption: (opt) => opt.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<_NameOption>.empty();
        return danceOptions.where((o) => o.name.toLowerCase().contains(q));
      },
      onSelected: (choice) => onSelected(choice.id),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Related dance',
            hintText: 'Type to search…',
            isDense: true,
            border: OutlineInputBorder(),
          ),
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
                      key: ValueKey('link-dance-option-${choice.id}'),
                      dense: true,
                      leading: const Icon(Icons.link, size: 18),
                      title: Text(choice.name),
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

/// Mutable editing state for a single [DanceLink] (all four [LinkKind]s).
///
/// URL-kind links (source/video/other) use [urlController]; relatedDance links
/// use [targetDanceId]. The [labelController] is shared by all kinds.
class _LinkDraft {
  _LinkDraft({
    required this.id,
    required LinkKind kind,
    required this.urlController,
    required this.labelController,
    this.targetDanceId,
  }) : _kind = kind; // ignore: prefer_initializing_formals

  factory _LinkDraft.empty() => _LinkDraft(
    id: uuidV4(),
    kind: LinkKind.source,
    urlController: TextEditingController(),
    labelController: TextEditingController(),
  );

  factory _LinkDraft.fromLink(DanceLink link, {String? danceTitle}) =>
      _LinkDraft(
        id: link.id,
        kind: link.kind,
        urlController: TextEditingController(text: link.url ?? ''),
        labelController: TextEditingController(text: link.label ?? ''),
        targetDanceId: link.targetDanceId,
      );

  /// Reconstructs a draft from an [EditorSnapshot]'s [LinkSnapshot], used
  /// when applying an undo/redo snapshot or restoring an autosave draft.
  /// [danceTitle] is the resolved title for a relatedDance link, used only
  /// as an initial value for the picker field (looked up by the caller).
  factory _LinkDraft.fromSnapshot(LinkSnapshot s, {String? danceTitle}) =>
      _LinkDraft(
        id: s.id,
        kind: s.kind,
        urlController: TextEditingController(text: s.url),
        labelController: TextEditingController(text: s.label),
        targetDanceId: s.targetDanceId,
      );

  final String id;
  LinkKind _kind;

  LinkKind get kind => _kind;

  set kind(LinkKind value) {
    if (_kind == value) return;
    _kind = value;
    // Clear incompatible state when switching between URL and relatedDance.
    if (value == LinkKind.relatedDance) {
      urlController.clear();
    } else {
      targetDanceId = null;
    }
  }

  final TextEditingController urlController;
  final TextEditingController labelController;

  /// Set when [kind] is [LinkKind.relatedDance]; `null` otherwise.
  String? targetDanceId;

  /// Builds a [DanceLink], or `null` when the required target is absent.
  ///
  /// For relatedDance: returns `null` if no dance has been selected yet.
  /// For URL kinds: returns `null` if the URL field is blank.
  DanceLink? toLink() {
    final label = labelController.text.trim();
    if (kind == LinkKind.relatedDance) {
      final target = targetDanceId;
      if (target == null || target.isEmpty) return null;
      return DanceLink(
        id: id,
        kind: kind,
        targetDanceId: target,
        label: label.isEmpty ? null : label,
      );
    } else {
      final url = urlController.text.trim();
      if (url.isEmpty) return null;
      return DanceLink(
        id: id,
        kind: kind,
        url: url,
        label: label.isEmpty ? null : label,
      );
    }
  }

  void dispose() {
    urlController.dispose();
    labelController.dispose();
  }
}

// ---------------------------------------------------------------------------
// Keyboard-shortcut intent classes for undo / redo.
// ---------------------------------------------------------------------------

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
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
