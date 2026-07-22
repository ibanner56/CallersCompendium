import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import '../../data/display_defaults.dart';
import '../../editor/editor_draft_codec.dart';
import '../../editor/editor_snapshot.dart';
import '../../editor/editor_undo_stack.dart';
import '../../editor/figure_draft.dart';
import '../../widgets/lingo_text_editing_controller.dart';
import 'link_draft.dart';
import 'source_citation_draft.dart';

/// Owns the dance editor's mutable working draft, its bounded [EditorUndoStack],
/// and the debounced undo/autosave machinery.
///
/// This is a plain [ChangeNotifier] with no dependency on the widget tree
/// (no [BuildContext]), so it can be unit-tested directly: construct it with a
/// set of repositories, [load] a dance (or `null` for a new dance), then drive
/// edits through its mutation methods and assert on [canUndo]/[buildDance]/etc.
///
/// Behavioural note: every public mutation method performs its edit, updates
/// the undo stack + autosave timers, and emits a single change notification —
/// mirroring the original screen's `setState` + `_pushUndoNow`/`_scheduleUndoPush`
/// + `_scheduleAutosave` chokepoints exactly.
class DanceEditorController extends ChangeNotifier {
  DanceEditorController({
    required CompendiumRepositories repositories,
    required this.danceId,
    required Dialect dialect,
  }) : _repos = repositories,
       _activeDialect = dialect,
       titleController = LingoTextEditingController(dialect: dialect),
       hookController = LingoTextEditingController(dialect: dialect),
       notesController = LingoTextEditingController(dialect: dialect),
       phraseController = LingoTextEditingController(dialect: dialect),
       formationDetailController = LingoTextEditingController(dialect: dialect),
       tuneController = LingoTextEditingController(dialect: dialect);

  final CompendiumRepositories _repos;
  final String? danceId;
  Dialect _activeDialect;

  bool _disposed = false;

  // ---- Prose (lingo-styled) text controllers ----
  final LingoTextEditingController titleController;
  final LingoTextEditingController hookController;
  final LingoTextEditingController notesController;
  final LingoTextEditingController phraseController;
  final LingoTextEditingController formationDetailController;
  final LingoTextEditingController tuneController;

  /// Custom text/number field editors, keyed by field id. Text fields get lingo
  /// styling; number fields carry the same controller type but never match a
  /// discouraged/role term, so they render as plain text.
  final Map<String, LingoTextEditingController> customTextControllers = {};

  /// Every lingo-styled prose controller, including the per-custom-field ones,
  /// so a dialect change can restyle them all in one pass.
  Iterable<LingoTextEditingController> get _proseLingoControllers => [
    titleController,
    hookController,
    notesController,
    phraseController,
    formationDetailController,
    tuneController,
    ...customTextControllers.values,
  ];

  // ---- Enum / scalar draft fields ----
  DanceForm _form = DanceForm.contra;
  FormationShape _formationShape = FormationShape.dupleImproper;
  Progression _progression = Progression.single;
  DanceStatus _status = DanceStatus.active;
  DanceLevel? _level;
  bool _mixedLevel = false;
  int? _rating;
  PartialDate? _composedOn;
  PartialDate? _revisedOn;

  DanceForm get form => _form;
  FormationShape get formationShape => _formationShape;
  Progression get progression => _progression;
  DanceStatus get status => _status;
  DanceLevel? get level => _level;
  bool get mixedLevel => _mixedLevel;
  int? get rating => _rating;
  PartialDate? get composedOn => _composedOn;
  PartialDate? get revisedOn => _revisedOn;

  // ---- Multi-value draft lists ----
  final List<String> authorIds = [];
  final List<String> tagIds = [];
  final List<String> tunes = [];
  final List<LinkDraft> links = [];

  /// Ordered per-dance source citations (mutable drafts; mirrors [links]).
  final List<SourceCitationDraft> sourceCitations = [];

  final Map<String, Object?> customValues = {};

  final List<FigureDraft> figureDrafts = [];

  List<Figure> get _figures => [
    for (final draft in figureDrafts) ?draft.toFigure(),
  ];

  PhraseStructure _phraseStructure = PhraseStructure.standard;
  PhraseStructure get phraseStructure => _phraseStructure;

  List<ValidationIssue> _warnings = const [];
  List<ValidationIssue> get warnings => _warnings;

  /// Existing custom-field definitions, needed to seed/capture custom values.
  List<CustomFieldDef> fieldDefs = const [];

  /// The dance being edited (null for a new dance); kept to preserve figures,
  /// createdAt, provenance, and schema version on save.
  Dance? _original;
  bool get isExistingDance => _original != null;

  /// The dance being edited, or `null` for a new dance. Exposed so the
  /// coordinator can read provenance (e.g. the title for a delete snackbar).
  Dance? get original => _original;

  // ---- Undo / redo ----
  final _undoStack = EditorUndoStack();

  /// `true` while we are restoring a snapshot via [applySnapshot] so that
  /// [pushUndoNow] does not push a spurious extra entry.
  bool _applyingSnapshot = false;

  bool get canUndo => _undoStack.canUndo;
  bool get canRedo => _undoStack.canRedo;

  // ---- Autosave timers ----
  Timer? _undoTimer;
  Timer? _autosaveTimer;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// `true` once the user has made an unsaved edit. Drives the unsaved-changes
  /// guard (`PopScope`) so backing out of a dirty editor prompts before
  /// discarding. Reset on a successful save.
  bool _dirty = false;
  bool get dirty => _dirty;

  String get draftKey => '$kDanceEditorDraftKeyPrefix${danceId ?? 'new'}';

  /// A decoded draft snapshot waiting to be restored or discarded.
  /// Set by [load] when a draft exists; cleared by the restore flow.
  EditorSnapshot? _pendingDraft;
  EditorSnapshot? get pendingDraft => _pendingDraft;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Pushes the new active dialect into every lingo prose controller.
  void updateDialect(Dialect newDialect) {
    _activeDialect = newDialect;
    for (final c in _proseLingoControllers) {
      c.updateDialect(newDialect);
    }
  }

  // -------------------------------------------------------------------------
  // Hydration
  // -------------------------------------------------------------------------

  /// Loads the draft state: seeds from [dance] (or new-dance defaults), seeds
  /// custom-field controllers from [fieldDefs], recomputes warnings, detects a
  /// pending autosave draft, and pushes the initial undo entry. Throwing
  /// propagates to the caller, which surfaces the load error.
  Future<void> load({
    required Dance? dance,
    required List<CustomFieldDef> fieldDefs,
  }) async {
    this.fieldDefs = fieldDefs;

    if (dance != null) {
      _original = dance;
      titleController.text = dance.title;
      hookController.text = dance.hook;
      notesController.text = dance.callingNotes;
      phraseController.text = dance.phraseStructure.raw;
      formationDetailController.text = dance.formation.detail ?? '';
      _form = dance.form;
      _formationShape = dance.formation.shape;
      _progression = dance.progression;
      _status = dance.status;
      _level = dance.level;
      _mixedLevel = dance.mixedLevel;
      _rating = dance.rating;
      _composedOn = dance.composedOn;
      _revisedOn = dance.revisedOn;
      authorIds.addAll(dance.authorIds);
      tagIds.addAll(dance.tagIds);
      tunes.addAll(dance.tunes);
      for (final link in dance.links) {
        links.add(LinkDraft.fromLink(link));
      }
      for (final citation in dance.sourceCitations) {
        sourceCitations.add(SourceCitationDraft.fromCitation(citation));
      }
      for (final value in dance.customFields) {
        customValues[value.fieldId] = value.value;
      }
      figureDrafts.addAll(dance.figures.map(FigureDraft.fromFigure));
    } else {
      // New dance (ROADMAP DD.1): seed the initial metadata from the saved
      // dance-authoring defaults. Each read is independently guarded so a
      // settings failure falls back silently to today's hardcoded default
      // rather than failing the editor load.
      try {
        _form = danceFormFromStored(
          await _repos.settings.get(kDefaultDanceFormKey),
        );
      } catch (_) {
        /* keep the hardcoded DanceForm.contra default */
      }
      try {
        _formationShape = formationShapeFromStored(
          await _repos.settings.get(kDefaultDanceFormationShapeKey),
        );
      } catch (_) {
        /* keep the hardcoded FormationShape.dupleImproper default */
      }
      try {
        _progression = progressionFromStored(
          await _repos.settings.get(kDefaultDanceProgressionKey),
        );
      } catch (_) {
        /* keep the hardcoded Progression.single default */
      }
      try {
        final raw = dancePhraseStructureRawFromStored(
          await _repos.settings.get(kDefaultDancePhraseStructureKey),
        );
        // Empty ⇒ leave the historical standard 4×16 (blank controller).
        if (raw.isNotEmpty) phraseController.text = raw;
      } catch (_) {
        /* keep the hardcoded standard phrase structure */
      }
      // Seed the starting figures from the saved template (ROADMAP DD.2).
      // Unset ⇒ the default `stand_still × 8`; a read/decode failure also
      // falls back to the default rather than failing the editor load. This
      // runs BEFORE the draft-restore check + initial undo snapshot below, so
      // the first render shows the template, the initial undo entry captures
      // it, and a restored autosaved draft still overrides it.
      try {
        final template = danceFiguresTemplateFromStored(
          await _repos.settings.get(kDefaultDanceFiguresTemplateKey),
        );
        figureDrafts.addAll(template.map(FigureDraft.fromFigure));
      } catch (_) {
        figureDrafts.addAll(
          defaultNewDanceFigureTemplate().map(FigureDraft.fromFigure),
        );
      }
    }

    // Seed text controllers for custom text/number fields.
    for (final def in fieldDefs) {
      if (def.type == CustomFieldType.text ||
          def.type == CustomFieldType.number) {
        customTextControllers[def.id] = LingoTextEditingController(
          text: customValues[def.id]?.toString() ?? '',
          dialect: _activeDialect,
        );
      }
    }

    recomputeWarnings();

    // Check for an autosaved draft and stage it for a restore/discard prompt.
    if (!_disposed && await _repos.settings.contains(draftKey)) {
      final raw = await _repos.settings.get(draftKey);
      EditorSnapshot? draftSnapshot;
      try {
        draftSnapshot = decodeDraft(raw);
      } catch (_) {
        // Corrupt / unrecognised draft version — silently discard.
        await _repos.settings.remove(draftKey);
      }
      if (draftSnapshot != null && !_disposed) {
        _pendingDraft = draftSnapshot;
      }
    }

    // Seed the initial undo entry so the user can always undo back to the
    // loaded (or restored-draft) state.
    _undoStack.push(captureSnapshot());

    _loaded = true;
    _notify();
  }

  // -------------------------------------------------------------------------
  // Draft restore
  // -------------------------------------------------------------------------

  /// Clears the pending draft marker (called once the restore prompt is shown).
  void clearPendingDraft() {
    _pendingDraft = null;
  }

  /// Applies a restored draft snapshot and resets the undo stack so the restored
  /// state IS the initial undo floor (the user cannot "undo the restore").
  void applyRestoredDraft(EditorSnapshot draft) {
    _applyingSnapshot = true;
    try {
      applySnapshot(draft);
    } finally {
      _applyingSnapshot = false;
    }
    _undoStack.clear();
    _undoStack.push(captureSnapshot());
    // Restored content is unsaved work: guard the back gesture.
    _dirty = true;
    _notify();
  }

  /// Discards a pending autosave draft from storage.
  Future<void> discardPendingDraft() async {
    await _repos.settings.remove(draftKey);
  }

  // -------------------------------------------------------------------------
  // Warnings
  // -------------------------------------------------------------------------

  /// Recomputes the non-blocking phrase warnings from the current figures and
  /// phrase-structure text. Invalid phrase structure is surfaced by the field
  /// validator instead, so here it just leaves the last good warnings.
  void recomputeWarnings() {
    try {
      _phraseStructure = PhraseStructure.parse(phraseController.text);
    } on FormatException {
      return;
    }
    final issues = <ValidationIssue>[];
    deriveSections(_figures, _phraseStructure, issues: issues);
    _warnings = issues;
  }

  // -------------------------------------------------------------------------
  // Snapshot capture / apply
  // -------------------------------------------------------------------------

  /// Captures an immutable snapshot of the current editor working state.
  EditorSnapshot captureSnapshot() => EditorSnapshot(
    title: titleController.text,
    hook: hookController.text,
    notes: notesController.text,
    phrase: phraseController.text,
    formationDetail: formationDetailController.text,
    form: _form,
    formationShape: _formationShape,
    progression: _progression,
    status: _status,
    level: _level,
    mixedLevel: _mixedLevel,
    rating: _rating,
    composedOn: _composedOn,
    revisedOn: _revisedOn,
    authorIds: List.unmodifiable(authorIds),
    tagIds: List.unmodifiable(tagIds),
    tunes: List.unmodifiable(tunes),
    links: List.unmodifiable(
      links.map(
        (l) => LinkSnapshot(
          id: l.id,
          kind: l.kind,
          url: l.urlController.text,
          label: l.labelController.text,
          targetDanceId: l.targetDanceId,
        ),
      ),
    ),
    sourceCitations: List.unmodifiable(
      sourceCitations.map((c) => c.toCitation()),
    ),
    // Custom text/number fields are edited via customTextControllers and do
    // not keep customValues in sync — read from the controllers directly so
    // the snapshot captures whatever the user has typed.
    customValues: Map.unmodifiable({
      ...customValues, // boolean / choice values
      for (final def in fieldDefs)
        if ((def.type == CustomFieldType.text ||
                def.type == CustomFieldType.number) &&
            customTextControllers.containsKey(def.id))
          def.id: customTextControllers[def.id]!.text,
    }),
    figureDrafts: List.unmodifiable(
      figureDrafts.map(FigureDraftSnapshot.fromDraft),
    ),
  );

  /// Restores working state from [s], resyncing all text controllers.
  ///
  /// Must be called inside an [_applyingSnapshot] guard so [pushUndoNow]
  /// is suppressed during the apply.
  void applySnapshot(EditorSnapshot s) {
    // Resync text controllers (guarded: don't clobber identical text).
    if (titleController.text != s.title) titleController.text = s.title;
    if (hookController.text != s.hook) hookController.text = s.hook;
    if (notesController.text != s.notes) notesController.text = s.notes;
    if (phraseController.text != s.phrase) phraseController.text = s.phrase;
    if (formationDetailController.text != s.formationDetail) {
      formationDetailController.text = s.formationDetail;
    }

    // Enum fields.
    _form = s.form;
    _formationShape = s.formationShape;
    _progression = s.progression;
    _status = s.status;
    _level = s.level;
    _mixedLevel = s.mixedLevel;
    _rating = s.rating;
    _composedOn = s.composedOn;
    _revisedOn = s.revisedOn;

    // Multi-value lists.
    authorIds
      ..clear()
      ..addAll(s.authorIds);
    tagIds
      ..clear()
      ..addAll(s.tagIds);
    tunes
      ..clear()
      ..addAll(s.tunes);

    // URL-kind and relatedDance links: dispose old drafts, reconstruct from snapshot.
    for (final l in links) {
      l.dispose();
    }
    links
      ..clear()
      ..addAll(s.links.map(LinkDraft.fromSnapshot));

    // Source citations: dispose old drafts, reconstruct from the snapshot.
    for (final c in sourceCitations) {
      c.dispose();
    }
    sourceCitations
      ..clear()
      ..addAll(s.sourceCitations.map(SourceCitationDraft.fromCitation));

    // Custom values.
    customValues
      ..clear()
      ..addAll(s.customValues);

    // Resync custom text/number controllers.
    for (final def in fieldDefs) {
      if (def.type == CustomFieldType.text ||
          def.type == CustomFieldType.number) {
        final controller = customTextControllers[def.id];
        final newText = customValues[def.id]?.toString() ?? '';
        if (controller != null && controller.text != newText) {
          controller.text = newText;
        }
      }
    }

    // Figure drafts: recreate from snapshots so FigureDraft identities change
    // and the FigureListEditor rebuilds cleanly.
    figureDrafts
      ..clear()
      ..addAll(s.figureDrafts.map((d) => d.toDraft()));

    recomputeWarnings();
  }

  // -------------------------------------------------------------------------
  // Undo / redo
  // -------------------------------------------------------------------------

  /// Pushes the current editor state onto the undo stack immediately.
  /// No-op while [_applyingSnapshot] is true (prevents undo-of-undo loops)
  /// and before the initial load completes.
  void pushUndoNow() {
    _undoTimer?.cancel();
    if (!_applyingSnapshot && _loaded) {
      _undoStack.push(captureSnapshot());
    }
  }

  /// Debounces undo pushes for rapid text-field edits (500 ms).
  void scheduleUndoPush() {
    if (_applyingSnapshot || !_loaded) return;
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_disposed && !_applyingSnapshot && _loaded) {
        _undoStack.push(captureSnapshot());
        _notify(); // Refresh canUndo/canRedo button states.
      }
    });
  }

  void undo() {
    if (!_undoStack.canUndo) return;
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    _applyingSnapshot = true;
    try {
      applySnapshot(_undoStack.undo());
    } finally {
      _applyingSnapshot = false;
    }
    _notify();
    scheduleAutosave();
  }

  void redo() {
    if (!_undoStack.canRedo) return;
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    _applyingSnapshot = true;
    try {
      applySnapshot(_undoStack.redo());
    } finally {
      _applyingSnapshot = false;
    }
    _notify();
    scheduleAutosave();
  }

  // -------------------------------------------------------------------------
  // Autosave
  // -------------------------------------------------------------------------

  /// Debounces autosave writes (500 ms after last change).
  void scheduleAutosave() {
    _markDirty();
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  /// Flags the editor as having unsaved changes. Called from the shared
  /// [scheduleAutosave] chokepoint (every edit path runs through it) so the
  /// unsaved-changes guard stays in sync.
  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      _notify();
    }
  }

  Future<void> _saveDraft() async {
    if (!_loaded || _disposed) return;
    final encoded = encodeDraft(captureSnapshot());
    await _repos.settings.set(draftKey, encoded);
  }

  /// Cancels pending timers and removes the autosave draft from storage.
  Future<void> clearDraft() async {
    _autosaveTimer?.cancel();
    _undoTimer?.cancel();
    await _repos.settings.remove(draftKey);
  }

  /// Marks the draft as saved (no unsaved changes) after a successful commit.
  void markSaved() {
    _dirty = false;
  }

  // -------------------------------------------------------------------------
  // Save assembly
  // -------------------------------------------------------------------------

  List<CustomFieldValue> collectCustomFields() {
    final values = <CustomFieldValue>[];
    for (final def in fieldDefs) {
      Object? value;
      switch (def.type) {
        case CustomFieldType.text:
          final text = customTextControllers[def.id]?.text.trim() ?? '';
          if (text.isNotEmpty) value = text;
        case CustomFieldType.number:
          final text = customTextControllers[def.id]?.text.trim() ?? '';
          if (text.isNotEmpty) value = num.tryParse(text);
        case CustomFieldType.boolean:
          // Only persist when the field actually has a value — either loaded
          // from the dance or toggled by the user. Otherwise an untouched
          // switch would write a spurious `false` for every boolean def.
          if (customValues.containsKey(def.id)) {
            value = customValues[def.id] as bool?;
          }
        case CustomFieldType.choice:
          value = customValues[def.id] as String?;
      }
      if (value == null) continue;
      final field = CustomFieldValue(fieldId: def.id, value: value);
      if (field.matchesType(def)) values.add(field);
    }
    return values;
  }

  /// Assembles the [Dance] to persist from the current draft. For an existing
  /// dance this is `original.copyWith(...)`; for a new dance a fresh [Dance]
  /// with a generated id. Caller decides update-vs-create via [isExistingDance].
  Dance buildDance() {
    final now = DateTime.now().toUtc();
    final formationDetail = formationDetailController.text.trim();
    final formation = Formation(
      _formationShape,
      detail: formationDetail.isEmpty ? null : formationDetail,
    );
    final linkList = [for (final l in links) ?l.toLink()];
    final citationList = [for (final c in sourceCitations) c.toCitation()];
    final customFields = collectCustomFields();

    if (_original case final original?) {
      return original.copyWith(
        title: titleController.text.trim(),
        authorIds: List.of(authorIds),
        form: _form,
        formation: formation,
        progression: _progression,
        phraseStructure: phraseController.text.trim(),
        hook: hookController.text.trim(),
        callingNotes: notesController.text.trim(),
        status: _status,
        level: _level,
        clearLevel: _level == null,
        mixedLevel: _mixedLevel,
        rating: _rating,
        clearRating: _rating == null,
        composedOn: _composedOn,
        clearComposedOn: _composedOn == null,
        revisedOn: _revisedOn,
        clearRevisedOn: _revisedOn == null,
        tunes: List.of(tunes),
        customFields: customFields,
        tagIds: List.of(tagIds),
        links: linkList,
        sourceCitations: citationList,
        figures: _figures,
        updatedAt: now,
      );
    }
    return Dance(
      id: uuidV4(),
      title: titleController.text.trim(),
      authorIds: List.of(authorIds),
      form: _form,
      formation: formation,
      progression: _progression,
      phraseStructure: phraseController.text.trim(),
      hook: hookController.text.trim(),
      callingNotes: notesController.text.trim(),
      status: _status,
      level: _level,
      mixedLevel: _mixedLevel,
      rating: _rating,
      composedOn: _composedOn,
      revisedOn: _revisedOn,
      tunes: List.of(tunes),
      customFields: customFields,
      tagIds: List.of(tagIds),
      links: linkList,
      sourceCitations: citationList,
      figures: _figures,
      createdAt: now,
      updatedAt: now,
    );
  }

  // -------------------------------------------------------------------------
  // Draft mutations (each mirrors the original screen's edit chokepoints)
  // -------------------------------------------------------------------------

  void setForm(DanceForm value) {
    _form = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setFormationShape(FormationShape value) {
    _formationShape = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setProgression(Progression value) {
    _progression = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setStatus(DanceStatus value) {
    _status = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setLevel(DanceLevel? value) {
    _level = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setMixedLevel(bool value) {
    _mixedLevel = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setRating(int? value) {
    _rating = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setComposedOn(PartialDate? value) {
    _composedOn = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void setRevisedOn(PartialDate? value) {
    _revisedOn = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void addAuthor(String id) {
    authorIds.add(id);
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void removeAuthor(String id) {
    authorIds.remove(id);
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void addTag(String id) {
    tagIds.add(id);
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void removeTag(String id) {
    tagIds.remove(id);
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  /// Adds the trimmed contents of [tuneController] as a tune, then clears it.
  /// No-op (no notification) when the field is blank or the tune is a dupe.
  void addTune() {
    final tune = tuneController.text.trim();
    if (tune.isEmpty || tunes.contains(tune)) return;
    tunes.add(tune);
    tuneController.clear();
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void removeTune(String tune) {
    tunes.remove(tune);
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void addLink() {
    links.add(LinkDraft.empty());
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void addRelatedDance() {
    links.add(LinkDraft.relatedDance());
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void removeLink(LinkDraft draft) {
    links.remove(draft);
    draft.dispose();
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  /// A link row's inline field (kind/url/label/target/note) changed.
  void onLinksChanged() {
    scheduleUndoPush();
    scheduleAutosave();
    _notify();
  }

  /// Attaches an existing [PublishedSource] as a new citation. Ignores a source
  /// already cited (dedup) so the same source can't be double-cited.
  void attachSource(String sourceId) {
    if (sourceCitations.any((c) => c.sourceId == sourceId)) return;
    sourceCitations.add(SourceCitationDraft.forSource(sourceId));
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void removeSourceCitation(SourceCitationDraft draft) {
    sourceCitations.remove(draft);
    draft.dispose();
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  /// A citation's inline page/number field changed (no forced rebuild — the
  /// text fields manage their own display).
  void onSourceCitationsChanged() {
    scheduleUndoPush();
    scheduleAutosave();
  }

  void setCustomValue(String fieldId, Object? value) {
    customValues[fieldId] = value;
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void addFigure() {
    figureDrafts.add(FigureDraft());
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void deleteFigure(FigureDraft draft) {
    figureDrafts.remove(draft);
    recomputeWarnings();
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void duplicateFigure(FigureDraft draft) {
    final index = figureDrafts.indexOf(draft);
    if (index != -1) {
      // Clone with a fresh id (stable-identity contract) but every other field
      // copied — including the assumed-subject provenance marker (#460) — via
      // the centralized [FigureDraft.clone], inserted right after the source.
      final clone = draft.clone();
      figureDrafts.insert(index + 1, clone);
      recomputeWarnings();
    }
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  void reorderFigure(int oldIndex, int newIndex) {
    // onReorder uses pre-adjusted (onReorderItem) semantics — newIndex is the
    // final insertion position after removal.
    final draft = figureDrafts.removeAt(oldIndex);
    figureDrafts.insert(newIndex, draft);
    recomputeWarnings();
    pushUndoNow();
    scheduleAutosave();
    _notify();
  }

  /// A figure row's inline field changed.
  void onFiguresChanged() {
    recomputeWarnings();
    _notify();
    scheduleUndoPush();
    scheduleAutosave();
  }

  /// The phrase-structure field changed.
  void onPhraseChanged() {
    recomputeWarnings();
    _notify();
    scheduleUndoPush();
    scheduleAutosave();
  }

  /// A prose / custom text or number field changed (title, hook, notes,
  /// formation detail, tune, or a custom text/number field).
  void onTextEdited() {
    scheduleUndoPush();
    scheduleAutosave();
  }

  @override
  void dispose() {
    _disposed = true;
    _undoTimer?.cancel();
    _autosaveTimer?.cancel();
    titleController.dispose();
    hookController.dispose();
    notesController.dispose();
    phraseController.dispose();
    formationDetailController.dispose();
    tuneController.dispose();
    for (final c in customTextControllers.values) {
      c.dispose();
    }
    for (final l in links) {
      l.dispose();
    }
    for (final c in sourceCitations) {
      c.dispose();
    }
    super.dispose();
  }
}
