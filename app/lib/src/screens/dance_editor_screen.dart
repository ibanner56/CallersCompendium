import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/active_dialect_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../editor/editor_draft_codec.dart';
import '../editor/editor_snapshot.dart';
import '../editor/editor_undo_stack.dart';
import '../models/dance_list_entry.dart';
import '../search/facet_labels.dart';
import '../utils/confirm_delete.dart';
import '../widgets/choreographer_details_dialog.dart';
import '../widgets/figure_list_editor.dart';
import '../widgets/lingo_text_editing_controller.dart';
import '../widgets/published_source_details_dialog.dart';

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

  /// Per-move insert-time parameter overrides (ROADMAP DD.3), loaded once in
  /// [_load] from the saved Defaults. Empty until loaded (and on any read
  /// failure), so the editor falls back to pure taxonomy defaults rather than
  /// failing. Applies whenever the user inserts a move — for any dance.
  Map<String, Map<String, Object?>> _moveParamDefaults = {};

  /// Active dialect for lingo-line styling (discouraged strike-through + role
  /// underline) on the free-text prose fields. Seeded with the default and
  /// kept in sync with [ActiveDialectScope] in [didChangeDependencies], so the
  /// prose fields restyle live when the caller switches dialects — mirroring
  /// the figure/move field.
  Dialect _activeDialect = Dialect.larksRobins;

  /// Prose (free-text) fields use [LingoTextEditingController] so discouraged
  /// terms are struck through as the user types, consistent with the figure
  /// move field. Non-prose inputs (year/month/day, URL, related-dance, level)
  /// keep plain controllers. Move-keyword dotting is intentionally left off
  /// here (`taxonomy: null`): these metadata fields describe the dance, not its
  /// choreography, so only the discouraged-strike + role-underline cues apply.
  final _titleController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );
  final _hookController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );
  final _notesController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );
  final _phraseController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );
  final _formationDetailController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );
  final _tuneController = LingoTextEditingController(
    dialect: Dialect.larksRobins,
  );

  // Custom text/number field editors, keyed by field id. Text fields get lingo
  // styling; number fields carry the same controller type but never match a
  // discouraged/role term, so they render as plain text.
  final Map<String, LingoTextEditingController> _customTextControllers = {};

  /// Every lingo-styled prose controller, including the per-custom-field ones,
  /// so a dialect change can restyle them all in one pass.
  Iterable<LingoTextEditingController> get _proseLingoControllers => [
    _titleController,
    _hookController,
    _notesController,
    _phraseController,
    _formationDetailController,
    _tuneController,
    ..._customTextControllers.values,
  ];

  bool _loaded = false;
  bool _loadStarted = false;
  Object? _loadError;
  bool _saving = false;

  /// `true` once the user has made an unsaved edit. Drives the unsaved-changes
  /// guard (`PopScope`/[_confirmDiscard]) so backing out of a dirty editor
  /// prompts before discarding, mirroring [ProgramEditorScreen]. Reset on a
  /// successful save.
  bool _dirty = false;

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
  DanceLevel? _level;
  bool _mixedLevel = false;
  int? _rating;
  PartialDate? _composedOn;
  PartialDate? _revisedOn;

  final List<String> _authorIds = [];
  final List<String> _tagIds = [];
  final List<String> _tunes = [];
  final List<_LinkDraft> _links = [];

  /// Ordered per-dance source citations (mutable drafts; mirrors [_links]).
  final List<_SourceCitationDraft> _sourceCitations = [];

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

  /// All reusable published sources (autocomplete options for the picker).
  List<PublishedSource> _publishedSources = [];

  /// Published-source lookup by id, for resolving a citation's display title
  /// (and author/year) without re-querying. Kept in sync after inline
  /// create/edit, mirroring the choreographer caches.
  Map<String, PublishedSource> _sourcesById = {};

  List<Figure> get _figures => [
    for (final draft in _figureDrafts) ?draft.toFigure(),
  ];
  final List<FigureDraft> _figureDrafts = [];
  PhraseStructure _phraseStructure = PhraseStructure.standard;
  List<ValidationIssue> _warnings = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the prose fields' lingo styling live: when the active dialect
    // changes, ActiveDialectScope (an InheritedNotifier) re-runs this, so we
    // push the new dialect into every prose controller. `Dialect` has deep
    // equality, so only walk the controllers when the dialect actually
    // changed (identity fast-path first) to avoid needless O(n) comparisons
    // and listener churn.
    final newDialect = ActiveDialectScope.of(context);
    if (!identical(newDialect, _activeDialect) &&
        newDialect != _activeDialect) {
      _activeDialect = newDialect;
      for (final c in _proseLingoControllers) {
        c.updateDialect(newDialect);
      }
    }
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
    for (final c in _sourceCitations) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final choreographers = await _repos.choreographers.listAll();
      final tags = await _repos.tags.listAll();
      final fieldDefs = await _repos.customFieldDefs.listAll();
      final allDances = await _repos.dances.listAll();
      final publishedSources = await _repos.publishedSources.listAll();
      final dance = widget.danceId == null
          ? null
          : await _repos.dances.getById(widget.danceId!);

      _choreographers = choreographers;
      _tags = tags;
      _fieldDefs = fieldDefs;
      _allDances = allDances;
      _publishedSources = publishedSources;
      _sourcesById = {for (final s in publishedSources) s.id: s};
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
        _level = dance.level;
        _mixedLevel = dance.mixedLevel;
        _rating = dance.rating;
        _composedOn = dance.composedOn;
        _revisedOn = dance.revisedOn;
        _authorIds.addAll(dance.authorIds);
        _tagIds.addAll(dance.tagIds);
        _tunes.addAll(dance.tunes);
        for (final link in dance.links) {
          _links.add(_LinkDraft.fromLink(link));
        }
        for (final citation in dance.sourceCitations) {
          _sourceCitations.add(_SourceCitationDraft.fromCitation(citation));
        }
        for (final value in dance.customFields) {
          _customValues[value.fieldId] = value.value;
        }
        _figureDrafts.addAll(dance.figures.map(FigureDraft.fromFigure));
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
          if (raw.isNotEmpty) _phraseController.text = raw;
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
          _figureDrafts.addAll(template.map(FigureDraft.fromFigure));
        } catch (_) {
          _figureDrafts.addAll(
            defaultNewDanceFigureTemplate().map(FigureDraft.fromFigure),
          );
        }
      }

      // Load the per-move insert-time param overrides (ROADMAP DD.3). Applies
      // to ANY dance (new or existing) — per-move defaults are about inserting
      // a move, not new-vs-existing. A read/parse failure falls back to an
      // empty map rather than failing the editor load.
      try {
        _moveParamDefaults = moveParamOverridesFromStored(
          await _repos.settings.get(kDefaultMoveParamOverridesKey),
        );
      } catch (_) {
        _moveParamDefaults = {};
      }

      // Seed text controllers for custom text/number fields.
      for (final def in fieldDefs) {
        if (def.type == CustomFieldType.text ||
            def.type == CustomFieldType.number) {
          _customTextControllers[def.id] = LingoTextEditingController(
            text: _customValues[def.id]?.toString() ?? '',
            dialect: _activeDialect,
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
      final sourceCitations = [
        for (final c in _sourceCitations) c.toCitation(),
      ];
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
          level: _level,
          clearLevel: _level == null,
          mixedLevel: _mixedLevel,
          rating: _rating,
          clearRating: _rating == null,
          composedOn: _composedOn,
          clearComposedOn: _composedOn == null,
          revisedOn: _revisedOn,
          clearRevisedOn: _revisedOn == null,
          tunes: List.of(_tunes),
          customFields: customFields,
          tagIds: List.of(_tagIds),
          links: links,
          sourceCitations: sourceCitations,
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
          level: _level,
          mixedLevel: _mixedLevel,
          rating: _rating,
          composedOn: _composedOn,
          revisedOn: _revisedOn,
          tunes: List.of(_tunes),
          customFields: customFields,
          tagIds: List.of(_tagIds),
          links: links,
          sourceCitations: sourceCitations,
          figures: _figures,
          createdAt: now,
          updatedAt: now,
        );
        await _repos.dances.create(dance);
      }
      // Clear the autosave draft — work is now committed.
      await _clearDraft();
      _dirty = false;
      if (mounted) Navigator.of(context).pop(dance.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  /// Soft-deletes the dance being edited and pops back (with no result) so the
  /// caller (dance detail / list) can reload. Mirrors [DanceDetailScreen]'s
  /// delete: an "Undo" snackbar restores the dance if tapped. Only reachable
  /// for an existing dance (the action is hidden while `widget.isNew`).
  Future<void> _delete() async {
    final id = widget.danceId;
    if (id == null) return;
    final title = _original?.title ?? 'Dance';
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    await _repos.dances.softDelete(id, at: now);
    if (!mounted) return;
    // Drop the autosave draft so it can't resurface for a deleted dance.
    await _clearDraft();
    if (!mounted) return;
    // Capture the messenger before popping so the snackbar is enqueued while
    // this Scaffold is still registered with it.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('deleted-snackbar'),
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              _repos.dances.restore(id, at: DateTime.now().toUtc()),
        ),
      ),
    );
    // Pop without a result: the editor's routes are typed `<void>`/`<String>`
    // and every caller reloads independently, so navigating back is enough.
    Navigator.of(context).pop();
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
    level: _level,
    mixedLevel: _mixedLevel,
    rating: _rating,
    composedOn: _composedOn,
    revisedOn: _revisedOn,
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
    sourceCitations: List.unmodifiable(
      _sourceCitations.map((c) => c.toCitation()),
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
    _level = s.level;
    _mixedLevel = s.mixedLevel;
    _rating = s.rating;
    _composedOn = s.composedOn;
    _revisedOn = s.revisedOn;

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
      ..addAll(s.links.map(_LinkDraft.fromSnapshot));

    // Source citations: dispose old drafts, reconstruct from the snapshot.
    for (final c in _sourceCitations) {
      c.dispose();
    }
    _sourceCitations
      ..clear()
      ..addAll(s.sourceCitations.map(_SourceCitationDraft.fromCitation));

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
    _markDirty();
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  /// Flags the editor as having unsaved changes. Called from the shared
  /// [_scheduleAutosave] chokepoint (every edit path runs through it) so the
  /// unsaved-changes guard stays in sync. Matches [ProgramEditorScreen].
  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
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
      // Restored content is unsaved work: guard the back gesture so it can't
      // be silently discarded.
      _dirty = true;
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

  /// Prompts before discarding unsaved edits when the user backs out of a dirty
  /// editor. Returns `true` when it is safe to leave (no unsaved changes, or the
  /// user confirmed the discard). Mirrors [ProgramEditorScreen._confirmDiscard]
  /// so the two editors share the same 'Discard changes?' affordance.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes to this dance.'),
        actions: [
          TextButton(
            key: const ValueKey('discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
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
      // canPop mirrors ProgramEditorScreen: when there are unsaved changes the
      // Back button / system gesture is intercepted so we can confirm before
      // discarding (and only then delete the autosave draft). Programmatic
      // Navigator.pop() (called by _save) bypasses canPop and is not affected.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (!ok) return;
        // User confirmed the discard: drop the autosave draft so it can't
        // resurface, then pop.
        await _clearDraft();
        if (!context.mounted) return;
        Navigator.of(context).pop();
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
                    if (!widget.isNew)
                      IconButton(
                        key: const ValueKey('delete-dance'),
                        tooltip: 'Delete dance',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _delete,
                      ),
                  ],
                ],
              ),
              body: _buildBody(),
              // Save mirrors the program builder: a bottom-right extended FAB
              // (`docs/design/ux.md` §3) rather than an AppBar action, so the
              // primary commit affordance is consistent across editors. Undo /
              // redo stay in the AppBar. The `_saving` disabled state and inline
              // spinner are preserved.
              floatingActionButton: _loaded
                  ? FloatingActionButton.extended(
                      key: const ValueKey('save-dance'),
                      heroTag: 'save-dance',
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    )
                  : null,
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
    // Registers a dependency so the whole editor rebuilds (and prose fields
    // restyle) when the active dialect changes; also passed down to the lingo
    // hints so they reflect the current dialect's discouraged terms.
    final dialect = ActiveDialectScope.of(context);
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
          _LingoDiscouragedHint(
            controller: _titleController,
            dialect: dialect,
            fieldKey: 'title',
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
            onEdit: _editChoreographer,
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
            key: const ValueKey('formation-detail-field'),
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
          _LingoDiscouragedHint(
            controller: _formationDetailController,
            dialect: dialect,
            fieldKey: 'formation-detail',
          ),
          const SizedBox(height: 16),
          // Progression and Rating share one line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(width: 12),
              Expanded(
                child: _RatingField(
                  value: _rating,
                  onChanged: (v) {
                    setState(() => _rating = v);
                    _pushUndoNow();
                    _scheduleAutosave();
                  },
                ),
              ),
            ],
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
          _LingoDiscouragedHint(
            controller: _phraseController,
            dialect: dialect,
            fieldKey: 'phrase',
          ),
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
            dialect: dialect,
            moveParamDefaults: _moveParamDefaults,
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
            onDuplicate: (draft) {
              setState(() {
                final index = _figureDrafts.indexOf(draft);
                if (index == -1) return;
                // Clone with a fresh id (stable-identity contract) but copied
                // move/params/note/progression, inserted right after source.
                final clone = FigureDraft(
                  move: draft.move,
                  params: Map<String, Object?>.of(draft.params),
                  note: draft.note,
                  progression: draft.progression,
                  schemaVersion: draft.schemaVersion,
                );
                _figureDrafts.insert(index + 1, clone);
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
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('notes-field'),
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
          _LingoDiscouragedHint(
            controller: _notesController,
            dialect: dialect,
            fieldKey: 'notes',
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('hook-field'),
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
          _LingoDiscouragedHint(
            controller: _hookController,
            dialect: dialect,
            fieldKey: 'hook',
          ),
          const SizedBox(height: 24),
          _buildMoreDetails(dialect),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// The collapsible "More details" drawer (Tier 2). Holds the less-frequently
  /// used metadata; collapsed by default so the always-visible Tier 1 fields
  /// stay above the fold. While collapsed the children are removed from the
  /// tree (the default `ExpansionTile` behavior); no edits are lost because
  /// every value lives in the parent [State] — text controllers, [_links],
  /// [_customValues], and the enum/date fields — and is re-seeded into the
  /// child widgets when the section is expanded again.
  Widget _buildMoreDetails(Dialect dialect) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sectionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colorScheme.outlineVariant),
    );
    return ExpansionTile(
      key: const ValueKey('more-details-tile'),
      leading: Icon(Icons.tune, color: colorScheme.primary),
      title: Text(
        'More details',
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      initiallyExpanded: false,
      backgroundColor: colorScheme.surfaceContainerHighest,
      collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
      shape: sectionShape,
      collapsedShape: sectionShape,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        _LevelDropdown(
          value: _level,
          onChanged: (v) {
            setState(() => _level = v);
            _pushUndoNow();
            _scheduleAutosave();
          },
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('mixed-level-field'),
          value: _mixedLevel,
          onChanged: (v) {
            setState(() => _mixedLevel = v ?? false);
            _pushUndoNow();
            _scheduleAutosave();
          },
          title: const Text('Mixed level'),
          subtitle: const Text('Spans the difficulty scale'),
          secondary: const Icon(Icons.swap_vert),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        _PartialDateField(
          fieldKey: 'composed-on',
          label: 'Composed',
          helperText: 'When the dance was composed (year, or add month/day)',
          value: _composedOn,
          onChanged: (v) {
            setState(() => _composedOn = v);
            _pushUndoNow();
            _scheduleAutosave();
          },
        ),
        const SizedBox(height: 16),
        _PartialDateField(
          fieldKey: 'revised-on',
          label: 'Revised',
          helperText: 'When the dance was last revised by its author',
          value: _revisedOn,
          onChanged: (v) {
            setState(() => _revisedOn = v);
            _pushUndoNow();
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
        _LingoDiscouragedHint(
          controller: _tuneController,
          dialect: dialect,
          fieldKey: 'tune',
        ),
        const SizedBox(height: 16),
        _Label('Links'),
        _LinksEditor(
          links: _links,
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
        const SizedBox(height: 16),
        _Label('Published sources'),
        _SourceCitationsEditor(
          citations: _sourceCitations,
          sourcesById: _sourcesById,
          sourceOptions: _publishedSources,
          onAttach: _attachSource,
          onCreate: _createSource,
          onEditSource: _editSource,
          onRemove: (draft) {
            setState(() {
              _sourceCitations.remove(draft);
              draft.dispose();
            });
            _pushUndoNow();
            _scheduleAutosave();
          },
          onChanged: () {
            _scheduleUndoPush();
            _scheduleAutosave();
          },
        ),
        const SizedBox(height: 16),
        _Label('Related dances'),
        _RelatedDancesEditor(
          links: _links,
          danceOptions: _danceOptions,
          danceNamesById: _danceNamesById,
          onAdd: () {
            setState(() => _links.add(_LinkDraft.relatedDance()));
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
          for (final def in _fieldDefs) _buildCustomField(def, dialect),
        ],
      ],
    );
  }

  Widget _buildCustomField(CustomFieldDef def, Dialect dialect) {
    switch (def.type) {
      case CustomFieldType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
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
              if (_customTextControllers[def.id] != null)
                _LingoDiscouragedHint(
                  controller: _customTextControllers[def.id]!,
                  dialect: dialect,
                  fieldKey: 'custom-${def.id}',
                ),
            ],
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

  /// Opens the shared-author details dialog for [id] and, on save, upserts the
  /// updated record and refreshes the in-memory caches. This is an immediate
  /// shared-entity write — independent of the dance draft/autosave/undo stack
  /// (author *selection* lives in the snapshot; contact data does not).
  Future<void> _editChoreographer(String id) async {
    final existing = _choreographers.firstWhere(
      (c) => c.id == id,
      orElse: () => Choreographer(id: id, name: _choreographerNames[id] ?? id),
    );
    final updated = await ChoreographerDetailsDialog.show(context, existing);
    if (updated == null || !mounted) return;
    await _repos.choreographers.upsert(updated);
    if (!mounted) return;
    setState(() {
      // Replace the existing cache entry, or append if the author wasn't
      // cached (mirrors the defensive `orElse` in the lookup above), so the
      // in-memory caches never go stale after a shared-entity edit.
      final hasEntry = _choreographers.any((c) => c.id == id);
      _choreographers = [
        for (final c in _choreographers)
          if (c.id == id) updated else c,
        if (!hasEntry) updated,
      ];
      _choreographerNames = {..._choreographerNames, id: updated.name};
    });
  }

  /// Attaches an existing [PublishedSource] as a new citation. Ignores a source
  /// already cited (dedup, mirroring the [_NamePicker] "exclude selected"
  /// behaviour) so the same source can't be double-cited.
  void _attachSource(String sourceId) {
    if (!mounted) return;
    if (_sourceCitations.any((c) => c.sourceId == sourceId)) return;
    setState(() {
      _sourceCitations.add(_SourceCitationDraft.forSource(sourceId));
    });
    _pushUndoNow();
    _scheduleAutosave();
  }

  /// Opens the source details dialog to create a new [PublishedSource] with the
  /// typed [title], upserts it, refreshes the caches, and returns its id (or
  /// `null` if the user cancels). Mirrors [_createChoreographer], but uses the
  /// richer details dialog since a source carries more than a name.
  Future<String?> _createSource(String title) async {
    final draft = PublishedSource(id: uuidV4(), title: title.trim());
    final created = await PublishedSourceDetailsDialog.show(context, draft);
    if (created == null || !mounted) return null;
    await _repos.publishedSources.upsert(created);
    if (!mounted) return null;
    setState(() {
      _publishedSources = [
        ..._publishedSources,
        created,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _sourcesById = {..._sourcesById, created.id: created};
    });
    return created.id;
  }

  /// Opens the shared-source details dialog for [id] and, on save, upserts the
  /// updated record and refreshes the in-memory caches. This is an immediate
  /// shared-entity write — independent of the dance draft/autosave/undo stack
  /// (which source a dance cites lives in the snapshot; the source's own
  /// bibliographic data does not). Mirrors [_editChoreographer].
  Future<void> _editSource(String id) async {
    final existing = _sourcesById[id];
    if (existing == null) return;
    final updated = await PublishedSourceDetailsDialog.show(context, existing);
    if (updated == null || !mounted) return;
    await _repos.publishedSources.upsert(updated);
    if (!mounted) return;
    setState(() {
      _publishedSources = [
        for (final s in _publishedSources)
          if (s.id == id) updated else s,
      ];
      _sourcesById = {..._sourcesById, id: updated};
    });
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

/// An accessible 1..5 star rating control with an explicit UNRATED affordance.
///
/// Accessibility (a11y is a merge gate for this control):
/// - Each star is a focusable, actionable [IconButton] with a semantic label
///   ('Set rating to N of 5 stars').
/// - The whole control is wrapped in [Semantics] with `label: 'Rating'` and a
///   value like '3 of 5 stars' or 'unrated' (announced as 'Rating, 3 of 5
///   stars'). The value deliberately omits a 'Rating:' prefix so the label
///   isn't announced twice.
/// - Filled vs empty stars differ by icon *shape* ([Icons.star] vs
///   [Icons.star_border]) and carry semantics — state is never conveyed by
///   colour alone.
/// - Clearing is available two ways: an explicit labelled clear button, and
///   tapping the currently-selected top star to unset it.
///
/// `null` is the unrated state; saved via `copyWith(clearRating: true)`.
class _RatingField extends StatelessWidget {
  const _RatingField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _max = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticValue = value == null ? 'unrated' : '$value of $_max stars';

    return Semantics(
      key: const ValueKey('rating-field'),
      container: true,
      label: 'Rating',
      value: semanticValue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text('Rating', style: theme.textTheme.bodySmall),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var star = 1; star <= _max; star++)
                IconButton(
                  key: ValueKey('rating-star-$star'),
                  // Tapping the current top star unsets; otherwise sets to it.
                  onPressed: () => onChanged(value == star ? null : star),
                  tooltip: 'Set rating to $star of $_max stars',
                  icon: Icon(
                    (value ?? 0) >= star ? Icons.star : Icons.star_border,
                    semanticLabel: 'Set rating to $star of $_max stars',
                    color: (value ?? 0) >= star
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              if (value != null)
                IconButton(
                  key: const ValueKey('rating-clear'),
                  onPressed: () => onChanged(null),
                  tooltip: 'Clear rating',
                  icon: const Icon(Icons.clear, semanticLabel: 'Clear rating'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A difficulty [DanceLevel] dropdown that includes an explicit "Unspecified"
/// (`null`) option. Mirrors [_EnumDropdown] but is nullable so a dance can have
/// no assigned level (saved via `copyWith(clearLevel: true)`).
class _LevelDropdown extends StatelessWidget {
  const _LevelDropdown({required this.value, required this.onChanged});

  final DanceLevel? value;
  final ValueChanged<DanceLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DanceLevel?>(
      // Value-based key so the FormField re-initialises when `value` changes
      // externally (e.g. via undo/redo), matching [_EnumDropdown].
      key: ValueKey('level-field-${value?.name ?? 'none'}'),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Level',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<DanceLevel?>(
          value: null,
          child: Text('Unspecified'),
        ),
        for (final v in DanceLevel.values)
          DropdownMenuItem<DanceLevel?>(
            value: v,
            child: Text(danceLevelLabel(v)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A precision-aware partial-date entry: a required 4-digit **Year** plus an
/// optional **Month** and (when a month is set) **Day**. Emits a [PartialDate]
/// via [onChanged] — `null` when the year is blank/invalid. A raw date picker
/// is deliberately avoided: it would force full year/month/day, but composition
/// dates are frequently known only to the year (or year+month).
class _PartialDateField extends StatefulWidget {
  const _PartialDateField({
    required this.fieldKey,
    required this.label,
    required this.helperText,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final String helperText;
  final PartialDate? value;
  final ValueChanged<PartialDate?> onChanged;

  @override
  State<_PartialDateField> createState() => _PartialDateFieldState();
}

class _PartialDateFieldState extends State<_PartialDateField> {
  late final TextEditingController _yearController;
  int? _month;
  int? _day;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.value?.year.toString() ?? '',
    );
    _month = widget.value?.month;
    _day = widget.value?.day;
  }

  @override
  void didUpdateWidget(covariant _PartialDateField old) {
    super.didUpdateWidget(old);
    // Re-sync when the value changes externally (undo/redo, draft restore),
    // but not when it merely echoes what this field just emitted (avoids
    // clobbering the caret mid-edit).
    if (widget.value != _compute()) {
      _yearController.text = widget.value?.year.toString() ?? '';
      _month = widget.value?.month;
      _day = widget.value?.day;
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  int? get _year {
    final y = int.tryParse(_yearController.text.trim());
    if (y == null || y < 1 || y > 9999) return null;
    return y;
  }

  /// The current value, or `null` when the year is blank/invalid.
  PartialDate? _compute() {
    final y = _year;
    if (y == null) return null;
    try {
      return PartialDate(y, _month, _day);
    } on ArgumentError {
      return null;
    }
  }

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  void _emit() => widget.onChanged(_compute());

  @override
  Widget build(BuildContext context) {
    final year = _year;
    final yearText = _yearController.text.trim();
    final showYearError = yearText.isNotEmpty && year == null;
    final dayEnabled = year != null && _month != null;
    final maxDay = dayEnabled ? _daysIn(year, _month!) : 31;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey('${widget.fieldKey}-year'),
                controller: _yearController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Year',
                  hintText: 'e.g. 1989',
                  border: const OutlineInputBorder(),
                  counterText: '',
                  errorText: showYearError ? '1–9999' : null,
                ),
                onChanged: (_) => setState(() {
                  // A year change can invalidate a chosen day (e.g. Feb 29 in a
                  // leap year, then a non-leap year). Clear it so the Day
                  // dropdown never gets an initialValue absent from its items.
                  final y = _year;
                  if (y != null &&
                      _month != null &&
                      _day != null &&
                      _day! > _daysIn(y, _month!)) {
                    _day = null;
                  }
                  _emit();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('${widget.fieldKey}-month-${_month ?? 0}'),
                initialValue: _month,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem<int?>(
                      value: m,
                      child: Text(_monthLabels[m - 1]),
                    ),
                ],
                onChanged: year == null
                    ? null
                    : (m) => setState(() {
                        _month = m;
                        // A day needs a month, and must stay valid for it.
                        if (m == null) {
                          _day = null;
                        } else if (_day != null && _day! > _daysIn(year, m)) {
                          _day = null;
                        }
                        _emit();
                      }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('${widget.fieldKey}-day-${_day ?? 0}'),
                initialValue: _day,
                decoration: const InputDecoration(
                  labelText: 'Day',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  for (var d = 1; d <= maxDay; d++)
                    DropdownMenuItem<int?>(value: d, child: Text('$d')),
                ],
                onChanged: dayEnabled
                    ? (d) => setState(() {
                        _day = d;
                        _emit();
                      })
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(widget.helperText, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

const List<String> _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

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
    this.onEdit,
  });

  final String fieldKey;
  final List<String> selectedIds;
  final Map<String, String> namesById;
  final List<_NameOption> options;
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

/// Live, accessible "Discouraged: `<terms>`" affordance shown beneath a lingo
/// prose field. The visual strikethrough drawn by [LingoTextEditingController]
/// is a color/decoration-only cue, so this text (and its [Semantics] label)
/// gives an equivalent non-visual signal — mirroring the figure editor's note
/// field. Renders nothing when the active dialect flags no terms. Rebuilds on
/// each keystroke via the controller and on dialect change via its parent.
class _LingoDiscouragedHint extends StatelessWidget {
  const _LingoDiscouragedHint({
    required this.controller,
    required this.dialect,
    required this.fieldKey,
  });

  final LingoTextEditingController controller;
  final Dialect dialect;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final discouraged = canonicalize(controller.text, dialect).discouraged;
        if (discouraged.isEmpty) return const SizedBox.shrink();
        final hint = discouraged.map((s) => s.text).toSet().join(', ');
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(Icons.warning_outlined, size: 13, color: scheme.error),
              const SizedBox(width: 4),
              Flexible(
                child: Semantics(
                  label: 'Discouraged term: $hint',
                  child: Text(
                    'Discouraged: $hint',
                    key: ValueKey('$fieldKey-lingo-hint'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
    // Related dances have their own dedicated subsection; the generic links
    // list handles only URL-bearing kinds (source/video/other).
    final urlLinks = [
      for (final draft in links)
        if (draft.kind != LinkKind.relatedDance) draft,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in urlLinks)
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

/// Callers-Companion-style "Related dances" subsection. Distinct from the
/// generic [_LinksEditor]: it lets the user pick another dance from the
/// collection and attach an optional free-text note.
///
/// Operates on the shared `_links` list, filtered to
/// [LinkKind.relatedDance] drafts, so save/load/undo wiring is unchanged. The
/// note reuses [DanceLink.label] — no schema change is required.
class _RelatedDancesEditor extends StatelessWidget {
  const _RelatedDancesEditor({
    required this.links,
    required this.danceOptions,
    required this.danceNamesById,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<_LinkDraft> links;

  /// Non-deleted dances eligible for selection (self excluded).
  final List<_NameOption> danceOptions;

  /// Title lookup for resolving a [_LinkDraft.targetDanceId] to its display
  /// name. A missing entry means the target dance was deleted/purged.
  final Map<String, String> danceNamesById;

  final VoidCallback onAdd;
  final ValueChanged<_LinkDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final relatedDrafts = [
      for (final draft in links)
        if (draft.kind == LinkKind.relatedDance) draft,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in relatedDrafts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _RelatedDancePicker(
                        key: ValueKey(
                          'related-dance-picker-${draft.id}-'
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
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        key: ValueKey('related-dance-note-${draft.id}'),
                        controller: draft.labelController,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('related-dance-remove-${draft.id}'),
                  tooltip: 'Remove related dance',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(draft),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('related-dance-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add related dance'),
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

  /// A blank relatedDance draft (no target selected yet) for the dedicated
  /// Related-dances subsection.
  factory _LinkDraft.relatedDance() => _LinkDraft(
    id: uuidV4(),
    kind: LinkKind.relatedDance,
    urlController: TextEditingController(),
    labelController: TextEditingController(),
  );

  factory _LinkDraft.fromLink(DanceLink link) => _LinkDraft(
    id: link.id,
    kind: link.kind,
    urlController: TextEditingController(text: link.url ?? ''),
    labelController: TextEditingController(text: link.label ?? ''),
    targetDanceId: link.targetDanceId,
  );

  /// Reconstructs a draft from an [EditorSnapshot]'s [LinkSnapshot], used
  /// when applying an undo/redo snapshot or restoring an autosave draft.
  factory _LinkDraft.fromSnapshot(LinkSnapshot s) => _LinkDraft(
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
// Source-citation editor.
// ---------------------------------------------------------------------------

/// Mutable editing state for a single [SourceCitation] (which source, plus the
/// freeform page/number the dance appears at). Mirrors [_LinkDraft]: the
/// [pageController]/[numberController] survive rebuilds and are read into an
/// immutable [SourceCitation] on capture/save.
class _SourceCitationDraft {
  _SourceCitationDraft({
    required this.sourceId,
    required this.pageController,
    required this.numberController,
  });

  factory _SourceCitationDraft.forSource(String sourceId) =>
      _SourceCitationDraft(
        sourceId: sourceId,
        pageController: TextEditingController(),
        numberController: TextEditingController(),
      );

  factory _SourceCitationDraft.fromCitation(SourceCitation c) =>
      _SourceCitationDraft(
        sourceId: c.sourceId,
        pageController: TextEditingController(text: c.page ?? ''),
        numberController: TextEditingController(text: c.number ?? ''),
      );

  final String sourceId;
  final TextEditingController pageController;
  final TextEditingController numberController;

  /// Builds the immutable citation. [SourceCitation] normalizes empty/blank
  /// page/number to `null` itself.
  SourceCitation toCitation() => SourceCitation(
    sourceId: sourceId,
    page: pageController.text,
    number: numberController.text,
  );

  void dispose() {
    pageController.dispose();
    numberController.dispose();
  }
}

/// A short bibliographic subtitle ("Author, Year") for a source, or `null`
/// when it has neither an author nor a year.
String? _sourceSubtitle(PublishedSource s) {
  final parts = <String>[
    if (s.author != null) s.author!,
    if (s.year != null) s.year!.toString(),
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// The per-dance source-citation section: a list of cited-source rows (each an
/// editable chip + freeform page/number) plus a type-ahead to attach an
/// existing source or create a new one inline. Mirrors [_LinksEditor] and the
/// [_NamePicker] create/attach precedent.
class _SourceCitationsEditor extends StatelessWidget {
  const _SourceCitationsEditor({
    required this.citations,
    required this.sourcesById,
    required this.sourceOptions,
    required this.onAttach,
    required this.onCreate,
    required this.onEditSource,
    required this.onRemove,
    required this.onChanged,
  });

  final List<_SourceCitationDraft> citations;
  final Map<String, PublishedSource> sourcesById;
  final List<PublishedSource> sourceOptions;

  /// Attaches an existing source by id.
  final ValueChanged<String> onAttach;

  /// Creates a new source with the typed title; resolves to its id, or `null`
  /// if the user cancels the create dialog.
  final Future<String?> Function(String title) onCreate;

  /// Opens the shared-source details dialog for the given source id.
  final ValueChanged<String> onEditSource;

  final ValueChanged<_SourceCitationDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final citedIds = {for (final c in citations) c.sourceId};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final draft in citations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildRow(context, draft),
          ),
        _AddSourceAutocomplete(
          citedIds: citedIds,
          options: sourceOptions,
          onAttach: onAttach,
          onCreate: onCreate,
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, _SourceCitationDraft draft) {
    final source = sourcesById[draft.sourceId];
    final title = source?.title ?? '(unknown source)';
    final subtitle = source == null ? null : _sourceSubtitle(source);
    final chipLabel = subtitle == null ? title : '$title — $subtitle';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: ValueKey('source-chip-${draft.sourceId}'),
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(chipLabel, overflow: TextOverflow.ellipsis),
                  tooltip: 'Edit $title',
                  onPressed: () => onEditSource(draft.sourceId),
                  onDeleted: () => onRemove(draft),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('source-page-${draft.sourceId}'),
                  controller: draft.pageController,
                  decoration: const InputDecoration(
                    labelText: 'Page (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey('source-number-${draft.sourceId}'),
                  controller: draft.numberController,
                  decoration: const InputDecoration(
                    labelText: 'Number (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddSourceAutocomplete extends StatelessWidget {
  const _AddSourceAutocomplete({
    required this.citedIds,
    required this.options,
    required this.onAttach,
    required this.onCreate,
  });

  final Set<String> citedIds;
  final List<PublishedSource> options;
  final ValueChanged<String> onAttach;
  final Future<String?> Function(String title) onCreate;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_SourceChoice>(
      key: const ValueKey('source-autocomplete'),
      displayStringForOption: (choice) => choice.label,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<_SourceChoice>.empty();
        final lower = q.toLowerCase();
        final matches = options
            .where(
              (o) =>
                  !citedIds.contains(o.id) &&
                  (o.title.toLowerCase().contains(lower) ||
                      (o.author?.toLowerCase().contains(lower) ?? false)),
            )
            .map((o) => _SourceChoice.existing(o.id, o.title, o.author))
            .toList();
        final exact = options.any((o) => o.title.toLowerCase() == lower);
        if (!exact) matches.add(_SourceChoice.create(q));
        return matches;
      },
      onSelected: (choice) async {
        if (choice.isCreate) {
          final id = await onCreate(choice.title);
          if (id != null) onAttach(id);
        } else {
          onAttach(choice.id!);
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: const ValueKey('source-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Cite a source: type to add or create…',
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
                      key: ValueKey('source-option-${choice.optionKey}'),
                      dense: true,
                      leading: Icon(
                        choice.isCreate ? Icons.add : Icons.menu_book_outlined,
                        size: 18,
                      ),
                      title: Text(
                        choice.isCreate
                            ? 'Create "${choice.title}"'
                            : choice.title,
                      ),
                      subtitle: choice.author == null
                          ? null
                          : Text(choice.author!),
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

class _SourceChoice {
  _SourceChoice.existing(this.id, this.title, this.author) : isCreate = false;
  _SourceChoice.create(this.title) : id = null, author = null, isCreate = true;

  final String? id;
  final String title;
  final String? author;
  final bool isCreate;

  /// Text shown in the field when this option is selected.
  String get label => title;

  /// Stable widget key for the option row: existing items by id, the sole
  /// "create" row by its typed title.
  String get optionKey => isCreate ? 'create:$title' : id!;
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
