import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/active_dialect_scope.dart';
import '../data/collection_refresh_scope.dart';
import '../data/display_defaults.dart';
import '../data/repositories_scope.dart';
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
  const DanceEditorScreen({super.key, this.danceId});

  /// The dance being edited, or `null` to create a new dance.
  final String? danceId;

  bool get isNew => danceId == null;

  @override
  State<DanceEditorScreen> createState() => _DanceEditorScreenState();
}

class _DanceEditorScreenState extends State<DanceEditorScreen> {
  late CompendiumRepositories _repos;
  late final DanceEditorController _controller;
  final _formKey = GlobalKey<FormState>();

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
  /// create/edit, mirroring the choreographer caches.
  Map<String, PublishedSource> _sourcesById = {};

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
      );
      _controller.addListener(_onControllerChanged);
      _load();
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

  @override
  void dispose() {
    if (_dependenciesInitialized) {
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
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
      _allDances = allDances;
      _publishedSources = publishedSources;
      _sourcesById = {for (final s in publishedSources) s.id: s};
      _danceNamesById = {for (final d in allDances) d.id: d.title};
      _choreographerNames = {for (final c in choreographers) c.id: c.name};
      _tagNames = {for (final t in tags) t.id: t.name};

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

      // Load the opt-in "Free-text entry" toggle (#419). A read/parse failure
      // falls back to off, so the Add flow keeps its structured behaviour.
      try {
        final stored = await _repos.settings.get(kFreeTextEntryKey);
        _freeTextEntry = stored is bool ? stored : false;
      } catch (_) {
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
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Ensure the user sees the first error even if it is above the fold.
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      final dance = _controller.buildDance();
      if (_controller.isExistingDance) {
        await _repos.dances.update(dance);
      } else {
        await _repos.dances.create(dance);
      }
      // Clear the autosave draft — work is now committed.
      await _controller.clearDraft();
      _controller.markSaved();
      if (mounted) {
        // A create (new author/tags) or edit changes the collection, so tell
        // the live Collection view to reload + re-derive its author filter
        // (issue #340). This is the single signal for every editor entry point
        // (list FAB, detail-pane edit, edit-before-import).
        CollectionRefreshScope.bump(context);
        Navigator.of(context).pop(dance.id);
      }
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
    final title = _controller.original?.title ?? 'Dance';
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
      message: '"$title" deleted.',
      undoLabel: 'Undo',
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
      _controller.applyRestoredDraft(draft);
    } else {
      await _controller.discardPendingDraft();
    }
  }

  /// Prompts before discarding unsaved edits when the user backs out of a dirty
  /// editor. Returns `true` when it is safe to leave (no unsaved changes, or the
  /// user confirmed the discard). Mirrors [ProgramEditorScreen._confirmDiscard]
  /// so the two editors share the same 'Discard changes?' affordance.
  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
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

  @override
  Widget build(BuildContext context) {
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
                title: Text(widget.isNew ? 'New dance' : 'Edit dance'),
                actions: [
                  if (_controller.loaded) ...[
                    Semantics(
                      label: 'Undo',
                      child: IconButton(
                        key: const ValueKey('undo-button'),
                        tooltip: 'Undo (Ctrl+Z)',
                        icon: const Icon(Icons.undo),
                        onPressed: _controller.canUndo
                            ? _controller.undo
                            : null,
                      ),
                    ),
                    Semantics(
                      label: 'Redo',
                      child: IconButton(
                        key: const ValueKey('redo-button'),
                        tooltip: 'Redo (Ctrl+Shift+Z)',
                        icon: const Icon(Icons.redo),
                        onPressed: _controller.canRedo
                            ? _controller.redo
                            : null,
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
      taxonomy: _taxonomy,
      moveParamDefaults: _moveParamDefaults,
      freeTextEntry: _freeTextEntry,
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
