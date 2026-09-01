import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
import '../data/related_dance_links.dart';
import '../data/shorthand_mappings_scope.dart';
import '../diagnostics/error_log.dart';
import '../search/dance_editor_reference_data.dart';
import '../utils/confirm_delete.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/choreographer_details_dialog.dart';
import '../widgets/published_source_details_dialog.dart';
import 'dance_editor/dance_editor_controller.dart';
import 'dance_editor/dance_editor_form.dart';
import 'dance_editor/name_picker.dart';
import 'settings/settings_keys.dart';

/// Dance editor (`docs/design/ux.md` §3). Covers the metadata form — title,
/// authors (with inline choreographer/tag creation), formation, form/type,
/// progression, phrase structure, hook, calling notes, tunes, tags, status,
/// URL links, and values for existing custom fields — plus title-required hard
/// validation and non-blocking `validate()` warnings.
///
/// Structured figure entry (roadmap 3.3b) lives in the editable figure list
/// below the metadata; figure reordering affordances land with 3.3c.
///
/// This screen is a slim coordinator: the mutable draft, undo stack, and
/// autosave live in [DanceEditorController] (unit-testable, no [BuildContext]);
/// the scrolling metadata form is [DanceEditorForm]; and the metadata
/// sub-editors live under `screens/dance_editor/`. The screen owns only the
/// reference-data caches, inline shared-entity create/edit dialogs, load
/// orchestration, save/delete, and the app-bar/undo-redo/save chrome.
class DanceEditorScreen extends StatefulWidget {
  const DanceEditorScreen({super.key, this.danceId, this.initialTitle});

  /// The dance being edited, or `null` to create a new dance.
  final String? danceId;

  /// A title to seed a new dance's title field with (issue #881), e.g. when
  /// converting a program note slot to a dance. Ignored when [danceId] is
  /// non-null.
  final String? initialTitle;

  bool get isNew => danceId == null;

  @override
  State<DanceEditorScreen> createState() => _DanceEditorScreenState();
}

class _DanceEditorScreenState extends State<DanceEditorScreen> {
  late CompendiumRepositories _repos;
  late final DanceEditorController _controller;
  final _formKey = GlobalKey<FormState>();
  final _moreDetailsController = ExpansibleController();

  static final Taxonomy _taxonomy = contraTaxonomy;

  /// Per-move insert-time parameter overrides (ROADMAP DD.3), loaded once in
  /// [_load] from the saved Defaults. Empty until loaded (and on any read
  /// failure), so the editor falls back to pure taxonomy defaults rather than
  /// failing. Applies whenever the user inserts a move — for any dance.
  Map<String, Map<String, Object?>> _moveParamDefaults = {};

  /// Whether the opt-in "Free-text entry" dance-authoring toggle is on (issue
  /// #419), loaded once in [_load] from the saved Defaults. Defaults to `false`
  /// (off) until loaded and on any read failure, so the Add flow keeps its
  /// structured behaviour unless the caller has explicitly opted in.
  bool _freeTextEntry = false;

  /// Active dialect for lingo-line styling (discouraged strike-through + role
  /// underline) on the free-text prose fields. Seeded with the default and
  /// kept in sync with [ActiveDialectScope] in [didChangeDependencies], so the
  /// prose fields restyle live when the caller switches dialects — mirroring
  /// the figure/move field.
  Dialect _activeDialect = Dialect.larksRobins;

  bool _dependenciesInitialized = false;
  Object? _loadError;
  bool _saving = false;

  // ---- Reference-data caches (shared entities) ----
  //
  // Populated by [_subscribeReferenceData]'s live [DanceEditorReferenceData]
  // subscription (issue #768), not by [_load]. These fields are pure
  // reference/display data — never handed to [_controller] and never seeded
  // from it — so a write elsewhere (a choreographer renamed, a tag added, a
  // dance retitled) updates the picker options and lookups here without
  // touching the working draft. See [_subscribeReferenceData] for the
  // draft-safety reasoning.
  List<Dance> _allDances = [];
  Map<String, String> _danceNamesById = {};

  /// Dance options for the related-dance picker: all non-deleted dances except
  /// the dance currently being edited.
  List<NameOption> get _danceOptions => [
    for (final d in _allDances)
      if (d.id != widget.danceId) (id: d.id, name: d.title),
  ];

  List<Choreographer> _choreographers = [];
  List<Tag> _tags = [];
  Map<String, String> _choreographerNames = {};
  Map<String, String> _tagNames = {};

  /// All reusable published sources (autocomplete options for the picker).
  List<PublishedSource> _publishedSources = [];

  /// Published-source lookup by id, for resolving a citation's display title
  /// (and author/year) without re-querying. Kept in sync after inline
  /// create/edit (an optimistic patch reconciled by the next stream emission,
  /// below), mirroring the choreographer caches.
  Map<String, PublishedSource> _sourcesById = {};

  /// The live reference-data subscription, opened once in
  /// [didChangeDependencies] alongside [_load] and cancelled in [dispose].
  StreamSubscription<DanceEditorReferenceData>? _refDataSub;

  /// Resolves once the subscription above has delivered its first event
  /// (data or error). [_load] awaits this so the caches above are already
  /// populated — or the failure already surfaced via [_loadError] — before
  /// its first "loaded" render, rather than issuing a second, independent
  /// read of the same tables that would race the subscription's for no
  /// benefit (see [_subscribeReferenceData]'s doc). Completed defensively in
  /// [dispose] too, so a widget disposed before the first event arrives does
  /// not leave [_load]'s continuation suspended forever.
  final Completer<void> _initialReferenceDataReady = Completer<void>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the prose fields' lingo styling live: when the active dialect
    // changes, ActiveDialectScope (an InheritedNotifier) re-runs this, so we
    // push the new dialect into every prose controller. `Dialect` has deep
    // equality, so only walk the controllers when the dialect actually changed
    // (identity fast-path first) to avoid needless O(n) comparisons and
    // listener churn.
    final newDialect = ActiveDialectScope.of(context);
    if (!_dependenciesInitialized) {
      // Kick off exactly once per widget instance: `_load()` appends into the
      // controller's mutable collections, so a second run would duplicate
      // state and leak controllers.
      _dependenciesInitialized = true;
      _activeDialect = newDialect;
      _repos = RepositoriesScope.of(context);
      _controller = DanceEditorController(
        repositories: _repos,
        danceId: widget.danceId,
        dialect: newDialect,
        initialTitle: widget.initialTitle,
      );
      _controller.addListener(_onControllerChanged);
      _load();
      _subscribeReferenceData();
    } else if (!identical(newDialect, _activeDialect) &&
        newDialect != _activeDialect) {
      _activeDialect = newDialect;
      _controller.updateDialect(newDialect);
    }
  }

  /// Rebuilds the screen whenever the controller's draft/undo/autosave state
  /// changes. Guarded by [mounted] so a late notification (e.g. from a timer
  /// callback that outlived the route) is a no-op.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the live [DanceEditorReferenceData] subscription (issue #768):
  /// choreographers, tags, all dances and published sources, re-read whenever
  /// a write touches any of them.
  ///
  /// Started once, alongside [_load], which awaits
  /// [_initialReferenceDataReady] (completed below, on this subscription's
  /// first event) before proceeding to [DanceEditorController.load] — so the
  /// caches above are populated (or the failure already known) before the
  /// screen's first "loaded" render, without [_load] issuing its own,
  /// independent read of the same tables. A second, unsynchronized read would
  /// race this one for no benefit and, worse, could let the two disagree
  /// about whether the initial read failed (see the recovery discussion
  /// below) — one clean source of truth for the initial snapshot, reused for
  /// every later update too, avoids that.
  ///
  /// **Never touches [_controller].** Reassigning `fieldDefs` or re-running
  /// [DanceEditorController.load] from a stream emission would duplicate
  /// per-field text controllers (`load` is documented as safe to call exactly
  /// once) and — the more serious hazard — a `CustomFieldDef` mutated in place
  /// by [DanceEditorController.addChoiceOption] would be clobbered by a stale
  /// stream value racing the write that produced it. `fieldDefs` is therefore
  /// draft-adjacent state owned by the controller, not reference data, and
  /// stays one-shot.
  ///
  /// A stream error means reference data could not be re-read — most likely a
  /// query failure or a database closed under the widget. Since this screen
  /// (unlike the read-only dance detail screen) cannot render its editing
  /// surface meaningfully without a working reference-data channel — the
  /// author/tag/source pickers would silently go stale with no way to signal
  /// that — the error is treated the same way [_load]'s own catch block
  /// treats a failure: `_loadError` is set and the existing error body at
  /// `_buildBody` renders. The in-memory draft and autosave are untouched by
  /// this (only the *rendered* body changes), so nothing already typed is
  /// lost — but it is a UX regression, not a null bug, so it should be
  /// bounded in size the same way `_load` is if this class of failure ever
  /// turns out to be reachable mid-edit. `cancelOnError: false` so a
  /// subsequent write can still recover the subscription — including when the
  /// *first* event was the failure: `_controller.load` still runs (once
  /// [_initialReferenceDataReady] completes, error or not), so the screen
  /// isn't stuck showing a spinner while a later successful emission clears
  /// `_loadError` out from under it.
  void _subscribeReferenceData() {
    var isFirstEvent = true;
    void completeInitialReadyOnce() {
      if (isFirstEvent) {
        isFirstEvent = false;
        if (!_initialReferenceDataReady.isCompleted) {
          _initialReferenceDataReady.complete();
        }
      }
    }

    _refDataSub = DanceEditorReferenceData.watch(_repos).listen(
      (data) {
        if (mounted) {
          setState(() {
            _loadError = null;
            _choreographers = data.choreographers;
            _tags = data.tags;
            _allDances = data.dances;
            _publishedSources = data.publishedSources;
            _choreographerNames = data.choreographerNames;
            _tagNames = data.tagNames;
            _danceNamesById = data.danceNamesById;
            _sourcesById = data.sourcesById;
          });
        }
        completeInitialReadyOnce();
      },
      onError: (Object error, StackTrace stackTrace) {
        logCaughtError(
          error,
          stackTrace,
          source: 'dance_editor_screen._subscribeReferenceData',
        );
        if (mounted) setState(() => _loadError = error);
        completeInitialReadyOnce();
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    if (_dependenciesInitialized) {
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
      _moreDetailsController.dispose();
    }
    // Unblocks a still-suspended `_load()` continuation if the widget is
    // disposed before the subscription's first event ever arrives (e.g. the
    // route is popped mid-load): completing with no data is safe because
    // `_load()` checks `mounted` again after the await.
    if (!_initialReferenceDataReady.isCompleted) {
      _initialReferenceDataReady.complete();
    }
    unawaited(_refDataSub?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // `fieldDefs` and `dance` seed [_controller] below and are read once,
      // here — not from [_subscribeReferenceData]'s stream; see that method's
      // doc for why they stay one-shot draft-adjacent state.
      final fieldDefsFuture = _repos.customFieldDefs.listAll();
      final danceFuture = widget.danceId == null
          ? null
          : _repos.dances.getById(widget.danceId!);

      // Wait for [_subscribeReferenceData]'s first event (data or error)
      // before continuing to [DanceEditorController.load] below, so the
      // reference-data caches are already populated — or the failure is
      // already known via [_loadError] — by the time the screen's first
      // "loaded" render happens. See that method's doc for why this awaits
      // the *subscription's* read rather than issuing a second, independent
      // one of the same tables.
      await _initialReferenceDataReady.future;
      if (!mounted) return;

      final fieldDefs = await fieldDefsFuture;
      final dance = danceFuture == null ? null : await danceFuture;

      // Load the per-move insert-time param overrides (ROADMAP DD.3). Applies
      // to ANY dance (new or existing) — per-move defaults are about inserting
      // a move, not new-vs-existing. A read/parse failure falls back to an
      // empty map rather than failing the editor load.
      try {
        _moveParamDefaults = moveParamOverridesFromStored(
          await _repos.settings.get(kDefaultMoveParamOverridesKey),
        );
      } catch (_) {
        // diagnostics: silent — per-move param defaults read failed; falls back to empty map.
        _moveParamDefaults = {};
      }

      // Load the opt-in "Free-text entry" toggle (#419). A read/parse failure
      // falls back to off, so the Add flow keeps its structured behaviour.
      try {
        final stored = await _repos.settings.get(kFreeTextEntryKey);
        _freeTextEntry = stored is bool ? stored : false;
      } catch (_) {
        // diagnostics: silent — free-text entry toggle read failed; falls back to off (structured behaviour).
        _freeTextEntry = false;
      }

      // Hand off to the controller: it seeds the draft (from the dance or
      // new-dance defaults), seeds custom-field controllers, recomputes
      // warnings, detects a pending autosave draft, and pushes the initial
      // undo entry. Its final notify triggers the loaded-state rebuild.
      await _controller.load(dance: dance, fieldDefs: fieldDefs);

      // Show the restore/discard dialog AFTER the first build frame so
      // WidgetTester.pumpAndSettle() can settle on the loaded editor before
      // the dialog animation starts.
      if (mounted && _controller.pendingDraft != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeShowRestoreDialog(),
        );
      }
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'dance_editor_screen._load');
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _save() async {
    final hasInvalidCustomFieldNumber = _controller.hasInvalidCustomFieldNumber;
    final formIsValid = _formKey.currentState?.validate() ?? false;
    if (!formIsValid || hasInvalidCustomFieldNumber) {
      if (hasInvalidCustomFieldNumber) _moreDetailsController.expand();
      // Ensure the user sees the first error even if it is above the fold.
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      final dance = _controller.buildDance();
      await saveDanceWithRelatedLinks(
        _repos,
        dance: dance,
        original: _controller.original,
      );
      // Clear the autosave draft — work is now committed.
      await _controller.clearDraft();
      _controller.markSaved();
      if (mounted) {
        Navigator.of(context).pop(dance.id);
      }
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'dance_editor_screen._save');
      if (kDebugMode) {
        debugPrint('Could not save dance: $error\n$stackTrace');
      }
      if (!mounted) return;
      setState(() => _saving = false);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.danceEditorSaveError)));
    }
  }

  /// Soft-deletes the dance being edited and pops back (with no result) so the
  /// caller (dance detail / list) can reload. Mirrors [DanceDetailScreen]'s
  /// delete: an "Undo" snackbar restores the dance if tapped. Only reachable
  /// for an existing dance (the action is hidden while `widget.isNew`).
  Future<void> _delete() async {
    final id = widget.danceId;
    if (id == null) return;
    final l10n = AppLocalizations.of(context);
    final title =
        _controller.original?.title ?? l10n.danceEditorFallbackDanceTitle;
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    await _repos.dances.softDelete(id, at: now);
    if (!mounted) return;
    // Drop the autosave draft so it can't resurface for a deleted dance.
    await _controller.clearDraft();
    if (!mounted) return;
    // Capture the messenger before popping so the snackbar is enqueued while
    // this Scaffold is still registered with it.
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    showUndoSnackBar(
      messenger,
      key: const ValueKey('deleted-snackbar'),
      message: l10n.commonDeletedSnack(title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: accessibleNavigation,
      onUndo: () => _repos.dances.restore(id, at: DateTime.now().toUtc()),
    );
    // Pop without a result: the editor's routes are typed `<void>`/`<String>`
    // and every caller reloads independently, so navigating back is enough.
    Navigator.of(context).pop();
  }

  /// Shows the restore/discard dialog for a pending autosave draft.
  /// Called from a [WidgetsBinding.addPostFrameCallback] so it fires AFTER
  /// the first build, ensuring [WidgetTester.pumpAndSettle] can settle on the
  /// loaded editor state before the dialog animation begins.
  Future<void> _maybeShowRestoreDialog() async {
    final draft = _controller.pendingDraft;
    if (draft == null || !mounted) return;
    _controller.clearPendingDraft();

    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).danceEditorUnsavedDraftTitle),
        content: Text(AppLocalizations.of(ctx).danceEditorUnsavedDraftMessage),
        actions: [
          TextButton(
            key: const ValueKey('draft-discard'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).danceEditorDiscard),
          ),
          FilledButton(
            key: const ValueKey('draft-restore'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx).danceEditorRestore),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (restore == true) {
      _controller.applyRestoredDraft(draft);
    } else {
      await _controller.discardPendingDraft();
    }
  }

  /// Prompts before discarding unsaved edits when the user backs out of a dirty
  /// editor. Returns `true` when it is safe to leave (no unsaved changes, or the
  /// user confirmed the discard). Mirrors `_confirmDiscard` in the program
  /// editor (`program_editor_screen.dart`) so the two editors share the same
  /// 'Discard changes?' affordance. Named in prose because it is a private
  /// member of a private `State` class in another library, which a bracketed
  /// reference cannot resolve to.
  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).danceEditorDiscardChangesTitle,
        ),
        content: Text(
          AppLocalizations.of(context).danceEditorDiscardChangesMessage,
        ),
        actions: [
          TextButton(
            key: const ValueKey('discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).danceEditorKeepEditing),
          ),
          FilledButton(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).danceEditorDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// Mints (or, on a natural-key match, revives) a [Choreographer] for [name],
  /// upserts it, and returns its id. The in-memory cache update below is an
  /// optimistic patch reconciled a moment later by
  /// [_subscribeReferenceData]'s live stream, kept for the same immediate-
  /// appearance reason documented on [_createSource].
  Future<String> _createChoreographer(String name) async {
    final minted = Choreographer(id: uuidV4(), name: name.trim());
    // `upsert` returns the id the row actually occupies, which differs from the
    // minted one when a tombstone already holds this name (schema v25 natural-key
    // adoption). Caching the minted id would point the dance at a row that does
    // not exist, and `dance_authors.choreographer_id` is a real FK, so the save
    // fails rather than corrupting — but it fails on an ordinary action: delete a
    // choreographer, then type that name again.
    final id = await _repos.choreographers.upsert(minted);
    final choreographer = minted.id == id
        ? minted
        : Choreographer(id: id, name: minted.name);
    // The upsert is the durable effect; only touch in-memory caches if we're
    // still mounted (the create flow awaits this from the picker).
    if (mounted) {
      _choreographers = [..._choreographers, choreographer];
      _choreographerNames = {..._choreographerNames, id: name.trim()};
    }
    return id;
  }

  /// Opens the shared-author details dialog for [id] and, on save, upserts the
  /// updated record and patches the in-memory caches (optimistically — see
  /// [_createSource]). This is an immediate shared-entity write — independent
  /// of the dance draft/autosave/undo stack (author *selection* lives in the
  /// snapshot; contact data does not).
  Future<void> _editChoreographer(String id) async {
    final existing = _choreographers.firstWhere(
      (c) => c.id == id,
      orElse: () => Choreographer(id: id, name: _choreographerNames[id] ?? id),
    );
    final updated = await ChoreographerDetailsDialog.show(context, existing);
    if (updated == null || !mounted) return;
    // Safe discard: `updated` carries the id of the already-persisted
    // `existing` row. No fresh UUID is minted here, so tombstone adoption
    // cannot redirect the id; the returned id is always identical to updated.id.
    // ignore: unused_result
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

  /// Opens the source details dialog to create a new [PublishedSource] with the
  /// typed [title], upserts it, patches the caches, and returns its id (or
  /// `null` if the user cancels). Mirrors [_createChoreographer], but uses the
  /// richer details dialog since a source carries more than a name.
  ///
  /// The cache update below is an **optimistic patch**, not the only path the
  /// new source reaches these fields by: [_subscribeReferenceData]'s live
  /// stream will independently re-read and reconcile them a moment later (the
  /// write above lands in the same table it watches). It is kept anyway so the
  /// newly-created source appears in the picker immediately rather than after
  /// the next coalesced emission (issue #768) — this screen has editor tests
  /// that assert immediate appearance, and making the create flow visibly
  /// asynchronous would be a regression, not a simplification.
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
  /// updated record and patches the in-memory caches. This is an immediate
  /// shared-entity write — independent of the dance draft/autosave/undo stack
  /// (which source a dance cites lives in the snapshot; the source's own
  /// bibliographic data does not). Mirrors [_editChoreographer]. See
  /// [_createSource] for why the patch below is optimistic rather than the
  /// only update path.
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

  /// Mints (or, on a natural-key match, revives — schema v25, #898) a [Tag]
  /// for [name], upserts it, and returns its id. The cache patch below is
  /// optimistic, reconciled a moment later by [_subscribeReferenceData]'s
  /// stream — see [_createSource].
  Future<String> _createTag(String name) async {
    final minted = Tag(id: uuidV4(), name: name.trim());
    // Use the id the repository actually wrote, not the one minted here: if a
    // soft-deleted tag already held this name, the upsert revives that row and
    // returns its id (schema v25, #898). Adding the minted id to the dance
    // instead would reference a row that does not exist.
    final id = await _repos.tags.upsert(minted);
    final tag = Tag(id: id, name: minted.name, color: minted.color);
    if (mounted) {
      _tags = [..._tags, tag];
      _tagNames = {..._tagNames, tag.id: name.trim()};
    }
    return tag.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // canPop mirrors ProgramEditorScreen: when there are unsaved changes the
      // Back button / system gesture is intercepted so we can confirm before
      // discarding (and only then delete the autosave draft). Programmatic
      // Navigator.pop() (called by _save) bypasses canPop and is not affected.
      canPop: !_controller.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (!ok) return;
        // User confirmed the discard: drop the autosave draft so it can't
        // resurface, then pop.
        await _controller.clearDraft();
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
            _UndoIntent: CallbackAction<_UndoIntent>(
              onInvoke: (_) => _controller.undo(),
            ),
            _RedoIntent: CallbackAction<_RedoIntent>(
              onInvoke: (_) => _controller.redo(),
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  widget.isNew
                      ? l10n.danceEditorNewDanceTitle
                      : l10n.danceEditorEditDanceTitle,
                ),
                actions: [
                  if (_controller.loaded) ...[
                    Semantics(
                      label: l10n.commonUndo,
                      child: IconButton(
                        key: const ValueKey('undo-button'),
                        tooltip: l10n.danceEditorUndoShortcutTooltip,
                        icon: const Icon(Icons.undo),
                        onPressed: _controller.canUndo
                            ? _controller.undo
                            : null,
                      ),
                    ),
                    Semantics(
                      label: l10n.danceEditorRedoLabel,
                      child: IconButton(
                        key: const ValueKey('redo-button'),
                        tooltip: l10n.danceEditorRedoShortcutTooltip,
                        icon: const Icon(Icons.redo),
                        onPressed: _controller.canRedo
                            ? _controller.redo
                            : null,
                      ),
                    ),
                    if (!widget.isNew)
                      IconButton(
                        key: const ValueKey('delete-dance'),
                        tooltip: l10n.danceEditorDeleteDanceTooltip,
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
              floatingActionButton: _controller.loaded
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
                      label: Text(l10n.commonSave),
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
      return Center(
        child: Text(AppLocalizations.of(context).danceEditorLoadError),
      );
    }
    if (!_controller.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    // Registers a dependency so the whole editor rebuilds (and prose fields
    // restyle) when the active dialect changes; also passed down to the lingo
    // hints so they reflect the current dialect's discouraged terms.
    final dialect = ActiveDialectScope.of(context);
    return DanceEditorForm(
      controller: _controller,
      formKey: _formKey,
      moreDetailsController: _moreDetailsController,
      taxonomy: _taxonomy,
      moveParamDefaults: _moveParamDefaults,
      freeTextEntry: _freeTextEntry,
      shorthandMappings: ShorthandMappingsScope.maybeOf(context)?.store,
      dialect: dialect,
      isNew: widget.isNew,
      authorOptions: [
        for (final c in _choreographers) (id: c.id, name: c.name),
      ],
      choreographerNames: _choreographerNames,
      tagOptions: [for (final t in _tags) (id: t.id, name: t.name)],
      tagNames: _tagNames,
      publishedSources: _publishedSources,
      sourcesById: _sourcesById,
      danceOptions: _danceOptions,
      danceNamesById: _danceNamesById,
      onAddAuthor: (id) {
        // Reached after an await in the picker's onSelected (create flow), so
        // the editor may have been disposed meanwhile.
        if (!mounted) return;
        _controller.addAuthor(id);
      },
      onAddTag: (id) {
        if (!mounted) return;
        _controller.addTag(id);
      },
      onAttachSource: (sourceId) {
        // Reached after an await in the picker's create flow, so the editor may
        // have been disposed meanwhile.
        if (!mounted) return;
        _controller.attachSource(sourceId);
      },
      onCreateChoreographer: _createChoreographer,
      onEditChoreographer: _editChoreographer,
      onCreateSource: _createSource,
      onEditSource: _editSource,
      onCreateTag: _createTag,
    );
  }
}

/// Undo intent for the Ctrl/Cmd+Z keyboard shortcut.
class _UndoIntent extends Intent {
  const _UndoIntent();
}

/// Redo intent for the Ctrl/Cmd+Shift+Z (and Ctrl+Y) keyboard shortcuts.
class _RedoIntent extends Intent {
  const _RedoIntent();
}
