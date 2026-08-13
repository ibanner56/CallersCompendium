import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:printing/printing.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/date_format_scope.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/programs_refresh_scope.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../data/calling_history_caller_filter.dart';
import '../data/validation_issue_labels.dart';
import '../data/venue_entity_mode_scope.dart';
import '../data/venue_label.dart';

import '../editor/program_editor_draft_codec.dart';
import '../export/export_labels_l10n.dart';
import '../export/program_matrix_pdf.dart';
import '../search/collection_data.dart';
import '../search/facet_labels.dart' show formationLabel;
import '../theme/keyboard_dismiss.dart';
import '../utils/confirm_delete.dart';
import '../utils/safe_name.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/collection_picker.dart';
import '../widgets/venue_picker.dart';
import 'dance_editor_screen.dart';
import 'perform_program_screen.dart';
import '../widgets/program_export_menu.dart';
import '../widgets/program_matrix_table.dart';
import '../widgets/program_slot_list_editor.dart';
import '../widgets/program_status_chip.dart';

/// Full-screen Program Builder (`docs/design/ux.md` §4).
///
/// Builds on the Phase 4.1 metadata editor with the slot list, a dance picker,
/// CC-parity event metadata (band / caller / dancer level), per-slot structured
/// fields (guest caller, planned minutes), ALT grouping, and mark-performed.
///
/// It is pushed as a **focused full-screen route** so its two-pane layout
/// (slots | picker) gets the full content width. It also still supports the
/// Phase 4.1 embedded callbacks so existing callers keep working, but its own
/// [LayoutBuilder] drives the internal responsive behaviour: wide (≥ ~820 px)
/// shows an inline persistent picker pane; narrow opens the picker in a modal
/// bottom sheet.
///
/// Language-neutral sentinel stored in [_ProgramEditorScreenState._loadError]
/// when the requested program no longer exists. Kept locale-independent (rather
/// than a resolved string) so the message re-localizes if the app language is
/// switched live while this retained editor is off-screen.
enum _ProgramLoadError { missing }

/// [programId] null ⇒ create a new program; otherwise edit that program.
/// Raised into a pending first-value future when its subscription is replaced
/// or disposed (issue #768). Being superseded is not a user-visible failure,
/// so [_ProgramEditorScreenState._load] returns on it without setting state.
class _SupersededLoad implements Exception {
  const _SupersededLoad();
  @override
  String toString() => 'load superseded before its first snapshot';
}

class ProgramEditorScreen extends StatefulWidget {
  const ProgramEditorScreen({
    super.key,
    this.programId,
    this.onSaved,
    this.onDeleted,
    this.onNavigateTo,
  });

  final String? programId;

  /// Called after a successful save with the program's id (embedded mode).
  final void Function(String programId)? onSaved;

  /// Called after a successful soft-delete (embedded mode).
  final VoidCallback? onDeleted;

  /// Called after duplication with the new copy's id (embedded mode).
  final void Function(String programId)? onNavigateTo;

  /// Width (of the builder's own constraints) at/above which the picker shows
  /// as a persistent right pane instead of a modal sheet.
  static const double twoPaneBreakpoint = 820;

  bool get isNew => programId == null;
  bool get isEmbedded =>
      onSaved != null || onDeleted != null || onNavigateTo != null;

  @override
  State<ProgramEditorScreen> createState() => _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends State<ProgramEditorScreen>
    with SingleTickerProviderStateMixin {
  late CompendiumRepositories _repos;
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _venueController = TextEditingController();
  final _bandController = TextEditingController();
  final _callerController = TextEditingController();
  final _levelController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loaded = false;

  /// Last-seen "track calling history for all callers" setting (issue #583),
  /// used to scope the embedded dance picker's call counts.
  bool _trackHistoryForAllCallers = false;
  Object? _loadError;

  Program? _existing;
  DateTime? _eventDate;
  ProgramStatus _status = ProgramStatus.draft;
  bool _hideAlternates = false;
  List<ProgramSlot> _slotsBacking = const [];

  /// Live view of [_danceSlotCounts] for the modal picker sheet, which does not
  /// rebuild with this [State]. Kept in step by the `_slots` setter.
  final ValueNotifier<Map<String, int>> _pickerCounts = ValueNotifier(const {});

  CollectionData? _data;
  bool _saving = false;
  bool _dirty = false;

  /// Move-column indices the caller has hidden from the on-screen program
  /// matrix via each column header's hide glyph (#669). Purely an ephemeral
  /// view preference — session-only, not persisted with the program — and
  /// scoped to this screen instance, so it naturally resets whenever a
  /// different program is opened (each open creates a fresh
  /// `ProgramEditorScreen`/state, never reuses this one for another
  /// program id). Never affects the PDF export, which always renders every
  /// column regardless of what's hidden on screen.
  final Set<int> _hiddenMatrixColumns = {};

  /// Debounced autosave timer for the in-progress draft (issue #436). Persists
  /// the working set list to [SettingsRepository] so an OS background/kill
  /// before an explicit Save no longer silently loses it.
  Timer? _autosaveTimer;

  /// Chains every [_saveDraft] write onto its predecessor so writes to
  /// [_draftKey] never run concurrently. [_clearDraft] awaits the tail before
  /// removing the draft; because each link only starts once the previous one
  /// has finished, awaiting the *latest* tail transitively waits for *every*
  /// write scheduled so far — not just the most recent one — so an in-flight
  /// autosave (however many are queued) can never complete *after* the
  /// removal and resurrect a just-cleared draft (issue #616).
  Future<void> _saveQueueTail = Future<void>.value();

  /// Bumped by every [_clearDraft] call. A save started before the bump
  /// skips its write if it observes a newer generation, so a cleanup that
  /// races a save can never be undone by that save — without permanently
  /// disabling autosave for the rest of the session (e.g. after the
  /// corrupt-draft cleanup in [_maybeStageDraft]).
  int _draftGeneration = 0;

  /// `true` while [_applyRestoredDraft] repopulates state from a restored draft,
  /// so [_scheduleAutosave] doesn't re-arm a write mid-restore.
  bool _restoringDraft = false;

  /// A decoded draft staged by [_load] awaiting a restore/discard prompt; shown
  /// after the first frame by [_maybeShowRestoreDialog].
  ProgramEditorDraft? _pendingDraft;

  /// The program's linked venue id (enriched venue mode). Kept independently
  /// from [_venueController] (free-text simple mode) so flipping the venue
  /// entity mode is lossless — neither field clears the other.
  String? _venueId;

  /// The resolved [Venue] for [_venueId], loaded so the simple-mode read-only
  /// fallback can show its name. `null` when no venue is linked.
  Venue? _linkedVenue;

  /// In-memory Perform resume state (issue #434). Perform is pushed *on top* of
  /// this editor, so this field survives that navigation: on exit the Perform
  /// view hands back its live position + clock here, and the next launch threads
  /// it back in so re-entry resumes at the current slot with the clock intact
  /// instead of resetting to slot 1. Purely a UI concern, so it lives here
  /// rather than in the persisted program (ADR-001 keeps the domain Flutter-free).
  PerformResumeState? _performResume;

  Dialect _dialect = Dialect.larksRobins;

  /// Always-on search enrichment for the embedded [CollectionPicker], built
  /// from the union of every saved dialect (presets + custom) so the picker's
  /// search resolves saved-dialect vocabulary regardless of the active dialect
  /// — parity with the main Collection search. Rebuilt in
  /// [didChangeDependencies] when the library changes.
  SearchEnrichment _enrichment = SearchEnrichment.empty;

  /// The dialect list [_enrichment] was built from, used to avoid rebuilding
  /// the union when nothing changed.
  List<Dialect> _enrichmentDialects = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild so the save FAB can hide on the read-only Matrix tab.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the active dialect if a scope is present; tolerate its absence
    // (e.g. narrow embedded tests) with a sensible default.
    final scope = context
        .dependOnInheritedWidgetOfExactType<ActiveDialectScope>();
    if (scope?.notifier != null) _dialect = scope!.notifier!.value;

    // Build the always-on enrichment from the union of every saved dialect
    // (presets + custom). Registers a rebuild dependency on the library so a
    // dialect add/edit/delete updates the picker's search live.
    final library = DialectLibraryScope.maybeOf(context);
    final newDialects = library?.all ?? const <Dialect>[];
    if (!listEquals(newDialects, _enrichmentDialects)) {
      _enrichmentDialects = newDialects;
      _enrichment = SearchEnrichment.fromDialects(newDialects);
    }

    // Scope the picker's call counts consistently with the Collection list
    // (issue #583); [of] returns false when the scope is absent (narrow
    // embedded tests), i.e. track all callers.
    //
    // Read UNCONDITIONALLY, outside the first-load guard. It used to be read
    // only inside it, which meant the setting was captured once and never
    // again: `TrackHistoryForAllCallersScope` is an `InheritedNotifier`, so a
    // toggle did rebuild this screen and did call this method — the value was
    // simply never re-read, and the picker served the previous filter's call
    // counts for the rest of the screen's life (issue #948).
    _trackHistoryForAllCallers = TrackHistoryForAllCallersScope.of(context);

    if (!_loaded && _loadError == null && _data == null) {
      _repos = RepositoriesScope.of(context);
      _load();
    } else if (_loaded &&
        _subscribedTrackAllCallers != null &&
        _subscribedTrackAllCallers != _trackHistoryForAllCallers) {
      unawaited(_resubscribePicker());
    }
  }

  /// Re-opens the picker's subscription under the current caller filter.
  ///
  /// **Reference data only.** The list screen answers the same change with a
  /// full `_boot`, and copying that here would be wrong: this screen holds a
  /// working copy of the program with debounced autosave, so re-running [_load]
  /// would re-read the program from the database and discard whatever the user
  /// has typed. The filter affects the picker's call counts and nothing else on
  /// this screen, so re-subscribing is both sufficient and the only safe scope.
  ///
  /// Gated on [_loaded] so it cannot supersede the initial load: that load
  /// awaits this same first-value future, and cancelling it mid-flight would
  /// raise `_SupersededLoad` into a caller that owns `_loaded` — leaving the
  /// editor on its loading state with nothing left to clear it. The residual
  /// window is a toggle landing *during* the initial load, which needs the user
  /// to reach Settings inside that load's own `await`; the subscription then
  /// keeps the filter it opened with. Left rather than closed with machinery,
  /// because the reconciliation would be unreachable code guarding a state no
  /// navigation can produce.
  Future<void> _resubscribePicker() async {
    try {
      final callerFilter = await resolveCallingHistoryCallerFilter(
        _repos.settings,
        trackAllCallers: _trackHistoryForAllCallers,
      );
      final data = await _watchCollectionData(callerFilter);
      if (!mounted) return;
      setState(() => _data = _latestData ?? data);
    } on _SupersededLoad {
      // A newer re-subscribe replaced this one; it owns `_data` now.
      return;
    } catch (_) {
      // Keep the last good picker data rather than blanking it, matching the
      // stream's own later-failure policy: this is reference data beside an
      // editor holding unsaved work.
    }
  }

  /// The live Collection reference data backing the dance picker (issue #768).
  ///
  /// Only the *picker's* data is reactive. The program being edited is
  /// deliberately NOT re-read from the database: this screen holds a working
  /// copy with debounced autosave, so refreshing it from underneath the user
  /// would discard in-flight edits. The split matters — the dances, tags and
  /// authors the picker offers are reference data that should stay current,
  /// while the program is the user's own document.
  StreamSubscription<CollectionData>? _dataSub;

  /// The most recent snapshot the stream has delivered.
  ///
  /// [_load] captures the stream's FIRST value and then awaits more work — the
  /// program fetch, the venue lookup, the default prefill — before assigning
  /// `_data`. A write landing in that gap would otherwise be overwritten by
  /// the older captured value, leaving the picker stale until the *next*
  /// write; this is read at assignment time instead, so the newest value wins.
  CollectionData? _latestData;

  /// Opens the subscription and resolves with its FIRST value, so the existing
  /// load sequence is unchanged while later emits flow into [_data].
  ///
  /// One subscription serves both, rather than a `load()` for the initial
  /// render plus a `watch()` for updates — that would run the whole snapshot
  /// load twice on open.
  /// The live subscription's first-value future, while still pending.
  ///
  /// Held so that whoever abandons the subscription can settle it — see
  /// [_replaceSubscription].
  Completer<CollectionData>? _pendingFirst;

  /// Cancels the live subscription, settling its first-value future first.
  ///
  /// [_load] awaits the stream's FIRST value, so **every path that abandons a
  /// pending first-value future must complete it**. Three exits are handled by
  /// the listener (a value, an error, the source ending); the other two are
  /// invisible to it, because **cancelling a `StreamSubscription` invokes none
  /// of its callbacks**: replacing the subscription, and [dispose].
  ///
  /// Both paths are reachable here. The replace path became reachable when
  /// [_resubscribePicker] landed (issue #948) — before that this screen's
  /// `_load` ran once, guarded by `!_loaded`, and only dispose could abandon a
  /// pending future. The guard was written for the class rather than for the
  /// reachable half, which is why that change needed no new machinery; see
  /// `program_summary_screen`, where round 11 found the replace path live.
  void _replaceSubscription() {
    final pending = _pendingFirst;
    _pendingFirst = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const _SupersededLoad());
    }
    unawaited(_dataSub?.cancel());
    _dataSub = null;
  }

  /// Whether the LIVE subscription was opened under "track all callers".
  ///
  /// Compared against the scope's current value rather than against
  /// [_trackHistoryForAllCallers], which is updated on every dependency change
  /// and so cannot say what the open subscription is actually serving. Null
  /// until the first subscription exists.
  bool? _subscribedTrackAllCallers;

  Future<CollectionData> _watchCollectionData(String? callerFilter) {
    final first = Completer<CollectionData>();
    _replaceSubscription();
    _pendingFirst = first;
    _subscribedTrackAllCallers = _trackHistoryForAllCallers;
    _dataSub =
        CollectionData.watch(
          _repos,
          callerFilter: callerFilter,
          // The editor renders the linked venue's name in simple mode's
          // read-only fallback, from a table `CollectionData` does not carry
          // (issue #944).
          watchVenues: true,
        ).listen(
          (data) {
            _latestData = data;
            if (!first.isCompleted) {
              _pendingFirst = null;
              first.complete(data);
              return;
            }
            if (mounted) setState(() => _data = data);
            // Re-resolve the linked venue on every later emit (issue #944).
            //
            // Opting into `watchVenues` is necessary and not sufficient: it makes
            // the stream fire on a venue write, but `_linkedVenue` is populated by
            // `_load`, which runs once per editor. Without this the rename would
            // wake the picker and leave the label beside it showing the old name —
            // a *partially* refreshed screen, which is harder to notice than one
            // that never updates.
            //
            // `_refreshLinkedVenue` already drops a result whose id no longer
            // matches `_venueId`, so a rename landing while the user is changing
            // the link cannot resurrect the old selection.
            final linkedId = _venueId;
            if (linkedId != null) unawaited(_refreshLinkedVenue(linkedId));
          },
          onError: (Object error) {
            if (!first.isCompleted) {
              _pendingFirst = null;
              first.completeError(error);
              return;
            }
            // A LATER failure keeps the picker on its last good data rather than
            // blanking it: this is reference data beside an editor holding unsaved
            // work, so an empty picker would be worse than a slightly stale one.
            // Deliberately not silent — it surfaces through the screen's own error
            // state only if nothing has loaded yet, which the branch above covers.
          },
          onDone: () {
            // The source can end without ever emitting — the database closed while
            // this screen was opening, which happens in teardown. Completing the
            // future is what stops `_load` awaiting forever; the error routes to
            // the screen's existing load-failure branch.
            if (!first.isCompleted) {
              _pendingFirst = null;
              first.completeError(
                StateError('collection stream closed before its first value'),
              );
            }
          },
        );
    return first.future;
  }

  Future<void> _load() async {
    try {
      final callerFilter = await resolveCallingHistoryCallerFilter(
        _repos.settings,
        trackAllCallers: _trackHistoryForAllCallers,
      );
      final data = await _watchCollectionData(callerFilter);
      Program? program;
      if (!widget.isNew) {
        program = await _repos.programs.getById(widget.programId!);
        if (program == null) {
          if (!mounted) return;
          setState(() {
            _data = _latestData ?? data;
            _loadError = _ProgramLoadError.missing;
            _loaded = true;
          });
          return;
        }
      }
      if (!mounted) return;
      if (program != null) {
        _titleController.text = program.title;
        _venueController.text = program.venue ?? '';
        _bandController.text = program.band ?? '';
        _callerController.text = program.caller ?? '';
        _levelController.text = program.dancerLevel ?? '';
        _notesController.text = program.notes;
        // Resolve the linked venue (if any) up front so the simple-mode
        // read-only fallback can show its name without an async gap.
        if (program.venueId != null) {
          _linkedVenue = await _repos.venues.getById(program.venueId!);
        }
      } else if (widget.isNew) {
        // ROADMAP G.3: prefill a new program's caller/band from saved defaults.
        // Only seeds a still-blank field, never overrides; a settings read
        // failure falls back silently to a blank field.
        await _prefillNewProgramDefaults();
      }
      // Guard again: the venue lookup / defaults prefill above are async, so the
      // widget may have been disposed while they were in-flight.
      if (!mounted) return;
      setState(() {
        _data = _latestData ?? data;
        _existing = program;
        _eventDate = program?.eventDate;
        _venueId = program?.venueId;
        _status = program?.status ?? ProgramStatus.draft;
        _hideAlternates = program?.hideAlternates ?? false;
        _slots = program?.slots.toList() ?? const [];
        _loaded = true;
      });
      // Detect an autosaved draft from an interrupted prior session and stage a
      // restore/discard prompt (issue #436). Runs after the loaded-state
      // setState so the editor is fully built before any dialog appears.
      await _maybeStageDraft();
    } on _SupersededLoad {
      // Superseded before a snapshot arrived; the load that replaced this one
      // owns `_loaded`/`_loadError`. Returning leaves the editor on its
      // loading state for that load to clear.
      return;
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loaded = true;
        });
      }
    }
  }

  /// Seeds the caller/band controllers for a NEW program from the saved G.3
  /// defaults, only when the controller is still blank. Each key is read
  /// independently so a failure (or corrupt value) reading one never blocks the
  /// other, and a settings read failure is swallowed so the editor still opens
  /// (with that field blank).
  Future<void> _prefillNewProgramDefaults() async {
    await _prefillControllerFromDefault(
      _callerController,
      kDefaultProgramCallerKey,
    );
    await _prefillControllerFromDefault(
      _bandController,
      kDefaultProgramBandKey,
    );
  }

  Future<void> _prefillControllerFromDefault(
    TextEditingController controller,
    String key,
  ) async {
    if (controller.text.isNotEmpty) return;
    try {
      final stored = await _repos.settings.get(key);
      final value = stored is String ? stored.trim() : '';
      if (value.isNotEmpty) controller.text = value;
    } catch (_) {
      // Leave the field blank if this default can't be read.
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _replaceSubscription();
    _pickerCounts.dispose();
    _tabController.dispose();
    _titleController.dispose();
    _venueController.dispose();
    _bandController.dispose();
    _callerController.dispose();
    _levelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    _scheduleAutosave();
  }

  // --- Autosave / draft persistence (issue #436) ----------------------------

  /// Settings-table key for this editor's draft, keyed by program id (or `new`
  /// for an unsaved program), mirroring the dance editor's `editor_draft:<id>`.
  String get _draftKey =>
      '$kProgramEditorDraftKeyPrefix${widget.programId ?? 'new'}';

  /// Debounces autosave writes (500 ms after the last change), matching the
  /// dance editor. No-op before the initial load completes or while restoring a
  /// draft, so neither seeding defaults nor a restore triggers a spurious write.
  void _scheduleAutosave() {
    if (!_loaded || _restoringDraft) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  /// Captures the current working state as an immutable draft snapshot. The
  /// title is kept verbatim (may be empty for an in-progress build); slots are
  /// renumbered so positions stay contiguous.
  ProgramEditorDraft _captureDraft() {
    String? nn(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    return ProgramEditorDraft(
      title: _titleController.text,
      eventDate: _eventDate,
      venue: nn(_venueController),
      venueId: _venueId,
      band: nn(_bandController),
      caller: nn(_callerController),
      dancerLevel: nn(_levelController),
      notes: _notesController.text,
      status: _status,
      hideAlternates: _hideAlternates,
      slots: _renumber(_slots),
    );
  }

  Future<void> _saveDraft() {
    if (!_loaded || !mounted || _restoringDraft) return Future<void>.value();
    final generation = _draftGeneration;
    // Chain onto the tail (rather than racing a fresh write) so overlapping
    // autosaves never write concurrently, and so the tail always reflects
    // every write scheduled so far.
    final future = _saveQueueTail.then((_) => _writeDraft(generation));
    _saveQueueTail = future;
    return future;
  }

  Future<void> _writeDraft(int generation) async {
    if (!mounted) return;
    try {
      // A _clearDraft() ran since this save was scheduled — it will (or
      // did) remove the draft itself, so skip the write rather than race it.
      if (generation != _draftGeneration) return;
      final encoded = encodeProgramDraft(_captureDraft());
      await _repos.settings.set(_draftKey, encoded);
    } catch (_) {
      // A draft write failure must never disrupt editing, nor permanently
      // stall the save chain for later autosaves; the next edit retries.
    }
  }

  /// Cancels the pending autosave and removes the draft from storage. Called on
  /// every terminal path (explicit save, delete, confirmed discard) so a
  /// committed or abandoned program never leaves a stale draft behind.
  ///
  /// Awaits every autosave write scheduled so far (via the chained
  /// [_saveQueueTail]) before removing, so none of them can complete *after*
  /// the removal and resurrect the draft (issue #616).
  Future<void> _clearDraft() async {
    _autosaveTimer?.cancel();
    _draftGeneration++;
    await _saveQueueTail;
    try {
      await _repos.settings.remove(_draftKey, permanent: true);
    } catch (_) {
      // Best-effort cleanup; a failure here is non-fatal.
    }
  }

  /// Reads any autosaved draft for this program, decodes it (silently
  /// discarding a corrupt/unrecognised one), and stages a restore/discard
  /// prompt after the first frame.
  Future<void> _maybeStageDraft() async {
    if (!mounted) return;
    ProgramEditorDraft? draft;
    try {
      if (await _repos.settings.contains(_draftKey)) {
        draft = decodeProgramDraft(await _repos.settings.get(_draftKey));
      }
    } catch (_) {
      // Corrupt / unrecognised draft version — silently discard.
      await _clearDraft();
      draft = null;
    }
    if (draft == null || !mounted) return;
    _pendingDraft = draft;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowRestoreDialog(),
    );
  }

  /// Shows the restore/discard dialog for a staged draft. Restoring applies the
  /// draft and keeps it (it is still unsaved work); discarding removes it.
  Future<void> _maybeShowRestoreDialog() async {
    final draft = _pendingDraft;
    if (draft == null || !mounted) return;
    _pendingDraft = null;
    final l10n = AppLocalizations.of(context);
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.programsDraftTitle),
        content: Text(l10n.programsDraftBody),
        actions: [
          TextButton(
            key: const ValueKey('program-draft-discard'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.programsDraftDiscard),
          ),
          FilledButton(
            key: const ValueKey('program-draft-restore'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.programsDraftRestore),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restore == true) {
      _applyRestoredDraft(draft);
    } else {
      await _clearDraft();
    }
  }

  /// Repopulates the editor's working state from a restored [draft] and marks it
  /// dirty (restored content is unsaved work). The [_restoringDraft] guard stops
  /// the repopulation from re-arming autosave; the on-disk draft is left intact.
  void _applyRestoredDraft(ProgramEditorDraft draft) {
    _restoringDraft = true;
    try {
      _titleController.text = draft.title;
      _venueController.text = draft.venue ?? '';
      _bandController.text = draft.band ?? '';
      _callerController.text = draft.caller ?? '';
      _levelController.text = draft.dancerLevel ?? '';
      _notesController.text = draft.notes;
      setState(() {
        _eventDate = draft.eventDate;
        _venueId = draft.venueId;
        _linkedVenue = null;
        _status = draft.status;
        _hideAlternates = draft.hideAlternates;
        _slots = _renumber(draft.slots);
        _dirty = true;
      });
    } finally {
      _restoringDraft = false;
    }
    // Resolve the linked venue's display name off the restore path. This only
    // refreshes the read-only simple-mode fallback hint; it does not re-arm
    // autosave, and the on-disk draft is left intact.
    final restoredVenueId = draft.venueId;
    if (restoredVenueId != null) _refreshLinkedVenue(restoredVenueId);
  }

  /// Handles a change from the enriched-mode [VenuePicker]: records the new
  /// linked venue id (or `null` to unlink), marks the editor dirty, and
  /// refreshes [_linkedVenue] so the simple-mode read-only fallback stays in
  /// sync if the user flips the toggle back. Never touches [_venueController],
  /// keeping the free-text value intact (lossless).
  Future<void> _onVenueLinkChanged(String? id) async {
    setState(() {
      _venueId = id;
      _dirty = true;
      if (id == null) _linkedVenue = null;
    });
    _scheduleAutosave();
    if (id == null) return;
    await _refreshLinkedVenue(id);
  }

  /// Resolves [id] to its [Venue] and refreshes [_linkedVenue] so the
  /// simple-mode read-only fallback can show the name. Guards against a stale
  /// late result: if the selection changed again while this fetch was in
  /// flight, `_venueId` no longer matches [id], so the result is dropped.
  Future<void> _refreshLinkedVenue(String id) async {
    final venue = await _repos.venues.getById(id);
    if (!mounted || _venueId != id) return;
    setState(() => _linkedVenue = venue);
  }

  /// Renumbers positions contiguously (0..n-1) in list order.
  List<ProgramSlot> _renumber(List<ProgramSlot> slots) => [
    for (var i = 0; i < slots.length; i++)
      slots[i].position == i ? slots[i] : slots[i].copyWith(position: i),
  ];

  /// Dances created via "create a dance from this" (issue #881) during this
  /// screen's lifetime, keyed by id.
  ///
  /// [_data] is a *live but debounced* snapshot: [CollectionData.watch]
  /// coalesces on a short trailing window and then re-`load()`s the whole
  /// collection, so a dance created moments ago is briefly absent from
  /// `_data.dancesById`. Every dance lookup in this screen goes through
  /// [_danceById] rather than `_data` directly, so the slot row, the export
  /// menu, and the matrix tab all resolve a just-created dance immediately
  /// instead of rendering the deleted-dance placeholder until the snapshot
  /// catches up.
  final Map<String, Dance> _createdDances = {};

  /// Resolves [danceId] to a [Dance]: the live [_data] snapshot first, then
  /// [_createdDances] as a fallback for a dance the snapshot hasn't caught up
  /// to yet. Returns null only when neither has it (a genuinely unavailable —
  /// e.g. soft-deleted — dance).
  Dance? _danceById(String danceId) =>
      _data?.dancesById[danceId] ?? _createdDances[danceId];

  String? _titleForDance(String danceId) => _danceById(danceId)?.title;

  /// Resolves a dance's formation for the slot editor's redundant accent +
  /// formation text (issue #270). Null when the dance is unavailable.
  Formation? _formationForDance(String danceId) =>
      _danceById(danceId)?.formation;

  /// Resolves a dance's mixer flag for the slot editor (issue #732).
  /// Returns false when the dance is unavailable.
  bool _mixerForDance(String danceId) => _danceById(danceId)?.mixer ?? false;

  /// Shared renderer for the large-print Perform view (mirrors the dance
  /// detail / single-dance Perform screens).
  static final FigureRenderer _performRenderer = FigureRenderer(contraTaxonomy);

  /// The program to hand to the large-print Perform view, assembled from the
  /// current (possibly unsaved) edits. Falls back to a placeholder title for a
  /// brand-new, still-untitled program so performing always works when slots
  /// exist. Returns null when there is nothing to perform.
  Program? _programToPerform(AppLocalizations l10n) {
    if (_slots.isEmpty) return null;
    final draft = _draftProgram;
    if (draft != null) return draft;
    final now = _existing?.createdAt ?? DateTime.now().toUtc();
    try {
      return Program(
        id: _existing?.id ?? 'draft',
        title: l10n.programsFallbackTitle,
        slots: _renumber(_slots),
        createdAt: now,
        updatedAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  void _performProgram() {
    final data = _data;
    final program = _programToPerform(AppLocalizations.of(context));
    if (data == null || program == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformProgramScreen(
          program: program,
          data: data,
          renderer: _performRenderer,
          // Resume where the caller left off (issue #434): thread the last
          // position + clock back in, and capture the new one on exit. The
          // screen clamps a now-out-of-range group after edits.
          initialGroup: _performResume?.groupIndex ?? 0,
          initialElapsedSeconds: _performResume?.elapsedSeconds ?? 0,
          initialSlotStartSeconds: _performResume?.slotStartSeconds ?? 0,
          initialPaused: _performResume?.paused ?? false,
          onExit: (state) => _performResume = state,
          // In-event adjustments (`docs/design/ux.md` §5) fold back into the
          // builder's working slots. For an already-saved program this is the
          // real live-gig path (a tablet routed through the builder is the
          // primary Perform form factor), so — mirroring the wide summary
          // pane's persist callback in `programs_shell.dart` — we write the
          // change (e.g. a mark-performed stamp) straight to the repository
          // immediately. The editor has no autosave, so without this a
          // background/kill before an explicit Save would silently lose it.
          // A brand-new, still-unsaved program has nothing to update in the DB
          // yet, so its adjustments stay in the working slots to be saved
          // explicitly; a failed write falls back the same way rather than
          // dropping the change.
          onProgramChanged: (updated) async {
            if (!mounted) return;
            final slots = _renumber(updated.slots.toList());
            final existing = _existing;
            if (existing != null) {
              final persisted = existing.copyWith(
                slots: slots,
                updatedAt: DateTime.now().toUtc(),
              );
              try {
                await _repos.programs.update(persisted);
                if (!mounted) return;
                setState(() {
                  _existing = persisted;
                  _slots = slots;
                });
                // A mark-performed stamp changes the Collection's "called N
                // times" badge and any mounted dance detail's calling history
                // (issue #768, gap 3); this screen has already applied the
                // change to its own state.
                ProgramsRefreshScope.bump(context);
                return;
              } on Exception catch (_) {
                // Fall through to keep the change in the working slots.
              }
            }
            if (!mounted) return;
            setState(() {
              _slots = slots;
              _dirty = true;
            });
            _scheduleAutosave();
          },
        ),
      ),
    );
  }

  // --- Slot mutations -------------------------------------------------------

  /// The working slot list.
  ///
  /// Reads go through the getter; every assignment refreshes [_pickerCounts].
  /// That indirection exists because the dance picker is presented two ways,
  /// and only one of them rebuilds with this [State]: the two-pane inline pane
  /// is part of this widget's subtree, but the narrow-layout sheet is a
  /// separate `Navigator` route, so `setState` here never reaches it. The sheet
  /// deliberately stays open across several adds, so without a live channel its
  /// picker would keep the counts it was born with for the whole session.
  ///
  /// Routing through a setter rather than updating the notifier at each mutation
  /// site means a future slot mutation cannot forget to keep the two in step.
  List<ProgramSlot> get _slots => _slotsBacking;

  set _slots(List<ProgramSlot> value) {
    _slotsBacking = value;
    _pickerCounts.value = _danceSlotCounts();
  }

  /// How many times each dance already appears in the program being built.
  ///
  /// Keyed by dance id; dances absent from the program are absent from the map.
  /// Free-text and break slots carry no dance id and are skipped.
  Map<String, int> _danceSlotCounts() {
    final counts = <String, int>{};
    for (final slot in _slots) {
      final danceId = slot.danceId;
      if (danceId == null) continue;
      counts[danceId] = (counts[danceId] ?? 0) + 1;
    }
    return counts;
  }

  void _addDanceSlot(String danceId) {
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(id: uuidV4(), position: _slots.length, danceId: danceId),
      ]);
      _dirty = true;
    });
    _scheduleAutosave();
    final l10n = AppLocalizations.of(context);
    final title = _titleForDance(danceId) ?? l10n.programsUntitledDanceFallback;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.programsAddedDanceSnack(title))),
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.programsAddedDanceAnnounce(title),
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  Future<void> _addFreeTextSlot() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _FreeTextSlotDialog(),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(id: uuidV4(), position: _slots.length, text: text),
      ]);
      _dirty = true;
    });
    _scheduleAutosave();
    SemanticsService.sendAnnouncement(
      View.of(context),
      AppLocalizations.of(context).programsAddedNoteAnnounce,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  void _insertBreakSlot() {
    setState(() {
      _slots = _renumber([
        ..._slots,
        ProgramSlot(
          id: uuidV4(),
          position: _slots.length,
          text: Program.breakSlotText,
        ),
      ]);
      _dirty = true;
    });
    _scheduleAutosave();
    SemanticsService.sendAnnouncement(
      View.of(context),
      AppLocalizations.of(context).programsAddedBreakAnnounce,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  void _reorderSlot(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._slots];
      final item = list.removeAt(oldIndex);
      list.insert(newIndex.clamp(0, list.length), item);
      _slots = _renumber(list);
      _dirty = true;
    });
    _scheduleAutosave();
  }

  void _updateSlot(int index, ProgramSlot updated) {
    setState(() {
      final list = [..._slots];
      list[index] = updated;
      _slots = _renumber(list);
      _dirty = true;
    });
    _scheduleAutosave();
  }

  void _removeSlot(int index) {
    setState(() {
      final list = [..._slots]..removeAt(index);
      _slots = _renumber(list);
      _dirty = true;
    });
    _scheduleAutosave();
  }

  /// Opens the dance editor seeded from the note-slot at [index]'s text
  /// (issue #881's "create a dance from this" menu action), and — if a dance
  /// was saved — converts that slot to reference it. The note text is always
  /// discarded on conversion (Isaac decided: it only ever stood in for the
  /// missing dance). Cancelling the editor (a null pop) leaves the slot
  /// exactly as it was, still a note.
  ///
  /// Re-derives the slot's current index by id after the `await`, in case the
  /// list changed while the editor was open (reordered, cut, or removed) — an
  /// index captured before an `await` cannot be trusted afterward.
  Future<void> _createDanceFromSlot(int index) async {
    if (index < 0 || index >= _slots.length) return;
    final slot = _slots[index];
    final noteText = slot.text;
    if (slot.danceId != null || noteText == null) return;
    final seedTitle = danceTitleFromSlotNote(noteText);

    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => DanceEditorScreen(initialTitle: seedTitle),
      ),
    );
    if (newId == null || !mounted) return;

    final currentIndex = _slots.indexWhere((s) => s.id == slot.id);
    if (currentIndex == -1) return; // the slot was removed while we were away

    // Populate the created-dance overlay immediately: CollectionData.watch's
    // coalesced snapshot hasn't necessarily caught up to the new dance yet
    // (see _createdDances' doc comment), so every dance lookup in this
    // screen resolves it right away instead of showing the deleted-dance
    // placeholder.
    final dance = await _repos.dances.getById(newId);
    if (dance != null) _createdDances[newId] = dance;
    if (!mounted) return;

    final current = _slots[currentIndex];
    // Rebuild rather than `copyWith`: `copyWith` cannot clear `text` (only
    // guestCaller/plannedMinutes/performedAt have clear flags — see
    // ProgramSlot.copyWith), and the note is always cleared on conversion.
    final updated = ProgramSlot(
      id: current.id,
      position: current.position,
      danceId: newId,
      isAlt: current.isAlt,
      guestCaller: current.guestCaller,
      plannedMinutes: current.plannedMinutes,
      performedAt: current.performedAt,
    );
    _updateSlot(currentIndex, updated);

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.programsCreatedDanceFromNoteAnnounce(dance?.title ?? seedTitle),
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }

  Future<void> _markAllPerformed() async {
    final now = DateTime.now().toUtc();
    final l10n = AppLocalizations.of(context);
    setState(() {
      _slots = [
        for (final s in _slots)
          s.danceId != null && s.performedAt == null
              ? s.copyWith(performedAt: now)
              : s,
      ];
      _dirty = true;
    });
    _scheduleAutosave();
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.programsMarkedAllPerformed,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.programsMarkedAllPerformed)));
  }

  // --- Persistence ----------------------------------------------------------

  /// The live program assembled from the current form + slots, used to drive
  /// warning-level validation (`orphaned_alt`) and export (share/copy/PDF).
  Program? get _draftProgram {
    final title = _titleController.text.trim();
    if (title.isEmpty) return null;
    final now = _existing?.createdAt ?? DateTime.now().toUtc();
    String? nn(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    try {
      final base =
          _existing ??
          Program(id: 'draft', title: title, createdAt: now, updatedAt: now);
      // Only the ACTIVE venue mode mutates its field; the inactive field rides
      // through untouched so flipping the toggle is lossless (see _save).
      final enriched = VenueEntityModeScope.of(context);
      final venueText = nn(_venueController);
      return base.copyWith(
        title: title,
        eventDate: _eventDate,
        clearEventDate: _eventDate == null,
        venue: enriched ? null : venueText,
        clearVenue: enriched ? false : venueText == null,
        venueId: enriched ? _venueId : null,
        clearVenueId: enriched ? _venueId == null : false,
        band: nn(_bandController),
        clearBand: nn(_bandController) == null,
        caller: nn(_callerController),
        clearCaller: nn(_callerController) == null,
        dancerLevel: nn(_levelController),
        clearDancerLevel: nn(_levelController) == null,
        notes: _notesController.text,
        status: _status,
        hideAlternates: _hideAlternates,
        slots: _renumber(_slots),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    final band = _bandController.text.trim();
    final caller = _callerController.text.trim();
    final level = _levelController.text.trim();
    final notes = _notesController.text.trim();
    final slots = _renumber(_slots);
    // The toggle is entry-mode only; both venue columns persist independently.
    // CREATE writes both live values (each defaults to empty/null in the mode
    // that isn't shown). UPDATE mutates ONLY the active mode's field so the
    // inactive value survives a flip untouched (lossless guarantee).
    final enriched = VenueEntityModeScope.of(context);

    try {
      final String id;
      if (widget.isNew) {
        id = uuidV4();
        await _repos.programs.create(
          Program(
            id: id,
            title: title,
            eventDate: _eventDate,
            venue: venue.isEmpty ? null : venue,
            venueId: _venueId,
            band: band.isEmpty ? null : band,
            caller: caller.isEmpty ? null : caller,
            dancerLevel: level.isEmpty ? null : level,
            notes: notes,
            status: _status,
            hideAlternates: _hideAlternates,
            slots: slots,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        id = _existing!.id;
        final updated = _existing!.copyWith(
          title: title,
          eventDate: _eventDate,
          clearEventDate: _eventDate == null,
          venue: enriched ? null : (venue.isEmpty ? null : venue),
          clearVenue: enriched ? false : venue.isEmpty,
          venueId: enriched ? _venueId : null,
          clearVenueId: enriched ? _venueId == null : false,
          band: band.isEmpty ? null : band,
          clearBand: band.isEmpty,
          caller: caller.isEmpty ? null : caller,
          clearCaller: caller.isEmpty,
          dancerLevel: level.isEmpty ? null : level,
          clearDancerLevel: level.isEmpty,
          notes: notes,
          status: _status,
          hideAlternates: _hideAlternates,
          slots: slots,
          updatedAt: now,
        );
        await _repos.programs.update(updated);
        _existing = updated;
      }
      // Work is committed — drop the autosave draft so it can't resurface.
      await _clearDraft();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _slots = slots;
      });
      // Broadcast the committed save (issue #768). Deliberately here and not in
      // the debounced autosave (`_saveDraft`), which fires on every slot drag —
      // broadcasting from there would re-boot every subscriber per edit, which
      // is the thrash issue #340 warns against.
      ProgramsRefreshScope.bump(context);
      final messenger = ScaffoldMessenger.of(context);
      if (widget.isEmbedded) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.programsSavedSnack(title))),
        );
        widget.onSaved?.call(id);
      } else {
        Navigator.of(context).pop(id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.programsSaveError)));
    }
  }

  Future<void> _duplicate() async {
    final source = _existing;
    if (source == null) return;
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    final copy = await _repos.programs.duplicate(
      id: source.id,
      newId: uuidV4(),
      newSlotId: uuidV4,
      now: now,
      newTitle: l10n.commonDuplicateTitleSuffix(source.title),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.programsDuplicatedSnack(copy.title))),
    );
    // The copy carries the same dance slots, so every derived count moved.
    ProgramsRefreshScope.bump(context);
    if (widget.isEmbedded) {
      widget.onNavigateTo?.call(copy.id);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<String>(
          builder: (_) => ProgramEditorScreen(programId: copy.id),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final source = _existing;
    if (source == null) return;
    final title = source.title;
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteIfEnabled(context, itemLabel: title)) return;
    if (!mounted) return;
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    // Drop the autosave draft so it can't resurface for a deleted program.
    await _clearDraft();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    // Captured before the route pops, so undo can still broadcast.
    final programsRefresh = ProgramsRefreshScope.notifierOf(context);
    showUndoSnackBar(
      messenger,
      message: l10n.programsDeletedSnack(title),
      undoLabel: l10n.commonUndo,
      accessibleNavigation: accessibleNavigation,
      onUndo: () async {
        await _repos.programs.restore(source.id, at: DateTime.now().toUtc());
        programsRefresh?.value++;
      },
    );
    programsRefresh?.value++;
    if (widget.isEmbedded) {
      widget.onDeleted?.call();
    } else {
      Navigator.of(context).pop('deleted');
    }
  }

  // --- Unsaved-changes guard ------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.programsDiscardTitle),
        content: Text(l10n.programsDiscardBody),
        actions: [
          TextButton(
            key: const ValueKey('discard-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.programsKeepEditing),
          ),
          FilledButton(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.programsDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (!context.mounted) return;
        if (ok) {
          // User confirmed the discard: drop the autosave draft so it can't
          // resurface, then pop.
          await _clearDraft();
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isNew ? l10n.programsNewProgram : l10n.programsBuildProgram,
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                key: const ValueKey('program-build-tab'),
                icon: const Icon(Icons.list_alt_outlined),
                text: l10n.programsBuildTab,
              ),
              Tab(
                key: const ValueKey('program-matrix-tab'),
                icon: const Icon(Icons.grid_on_outlined),
                text: l10n.programsMatrixTab,
              ),
            ],
          ),
          actions: [
            if (_loaded &&
                _loadError == null &&
                _data != null &&
                _slots.isNotEmpty)
              IconButton(
                key: const ValueKey('perform-program'),
                tooltip: l10n.programsPerformTooltip,
                icon: const Icon(Icons.slideshow),
                onPressed: _performProgram,
              ),
            if (_loaded && _loadError == null && _draftProgram != null)
              ProgramExportMenu(
                program: _draftProgram!,
                titleFor: _titleForDance,
                venuesById: _exportVenuesById,
                danceFor: _danceById,
                choreographerFor: (id) => _data?.choreographersById[id],
              ),
            if (!widget.isNew && _existing != null) ...[
              if (_slots.any((s) => s.danceId != null))
                IconButton(
                  key: const ValueKey('mark-all-performed'),
                  tooltip: l10n.programsMarkAllPerformedTooltip,
                  icon: const Icon(Icons.done_all),
                  onPressed: _markAllPerformed,
                ),
              IconButton(
                key: const ValueKey('duplicate-program'),
                tooltip: l10n.commonDuplicate,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: _duplicate,
              ),
              IconButton(
                key: const ValueKey('delete-program'),
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            ],
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildBody(), _buildMatrixTab()],
        ),
        floatingActionButton:
            (_loaded && _loadError == null && _tabController.index == 0)
            ? FloatingActionButton.extended(
                key: const ValueKey('save-program'),
                heroTag: 'save-program',
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_dirty ? l10n.programsSaveDirty : l10n.commonSave),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (!_loaded) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError == _ProgramLoadError.missing
                ? l10n.programsNoLongerExists
                : l10n.programsLoadError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane =
            constraints.maxWidth >= ProgramEditorScreen.twoPaneBreakpoint;
        final left = _buildEditorColumn(twoPane: twoPane);
        if (!twoPane) return left;
        final data = _data;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const VerticalDivider(width: 1, thickness: 1),
            if (data != null)
              Expanded(
                child: CollectionPicker(
                  key: const ValueKey('inline-picker'),
                  data: data,
                  dialect: _dialect,
                  enrichment: _enrichment,
                  addedDanceCounts: _pickerCounts.value,
                  onAddDance: _addDanceSlot,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMatrixTab() {
    final l10n = AppLocalizations.of(context);
    if (!_loaded) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError == _ProgramLoadError.missing
                ? l10n.programsNoLongerExists
                : l10n.programsLoadError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    // Rows = dance slots in program order (flat). Free-text-only slots are
    // omitted; a slot referencing a soft-deleted dance renders a tombstone
    // row so the gap is still visible in the matrix. Per-row halves are
    // derived from the full ordered slot list (including the break and any
    // free-text slots) so the "1st"/"2nd" badge reflects the break position.
    final now = DateTime.now();
    final halvesForSlots = Program.halvesForSlots(_slots);
    final rows = <Dance>[];
    final rowHalves = <ProgramHalf?>[];
    final altDanceIds = <String>{};
    var omittedFreeText = 0;
    for (var i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final danceId = slot.danceId;
      if (danceId == null) {
        omittedFreeText++;
        continue;
      }
      final dance =
          _danceById(danceId) ??
          Dance(
            id: danceId,
            title: l10n.programsDeletedDanceFallback,
            createdAt: now,
            updatedAt: now,
          );
      rows.add(dance);
      rowHalves.add(halvesForSlots[i]);
      if (slot.isAlt) altDanceIds.add(danceId);
    }

    final matrix = buildProgramMatrix(
      rows,
      taxonomy: data.taxonomy,
      halves: rowHalves,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: const ValueKey('program-matrix-reset-hidden-columns'),
                icon: const Icon(Icons.visibility),
                tooltip: l10n.programsMatrixShowAllColumnsSemantic,
                onPressed:
                    _hiddenMatrixColumns.any((c) => c < matrix.columns.length)
                    ? () => setState(_hiddenMatrixColumns.clear)
                    : null,
              ),
              IconButton(
                key: const ValueKey('program-matrix-export-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: l10n.exportMatrixPdfTooltip,
                onPressed: matrix.isEmpty
                    ? null
                    : () => _exportMatrixPdf(
                        matrix,
                        data.taxonomy,
                        omittedFreeText,
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProgramMatrixTable(
            key: const ValueKey('program-matrix-table'),
            matrix: matrix,
            taxonomy: data.taxonomy,
            dialect: _dialect,
            omittedFreeTextCount: omittedFreeText,
            altDanceIds: altDanceIds,
            hiddenColumns: _hiddenMatrixColumns,
            onHideColumn: (c) => setState(() => _hiddenMatrixColumns.add(c)),
          ),
        ),
      ],
    );
  }

  Future<void> _exportMatrixPdf(
    ProgramMatrix matrix,
    Taxonomy taxonomy,
    int omittedFreeTextCount,
  ) async {
    final localizations = MaterialLocalizations.of(context);
    final l10n = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    // Prefer a linked venue's display label over the free-text field, matching
    // the set-list export and on-screen resolution.
    final venue = resolveVenueLabelParts(
      _venueId,
      _venueController.text,
      _exportVenuesById,
    );
    await Printing.layoutPdf(
      name: sanitizeExportName(title, fallback: l10n.exportMatrixPdfFilename),
      onLayout: (format) => buildProgramMatrixPdf(
        matrix,
        taxonomy: taxonomy,
        dialect: _dialect,
        programTitle: title,
        eventDate: _eventDate,
        venue: venue,
        omittedFreeTextCount: omittedFreeTextCount,
        formatDate: localizations.formatMediumDate,
        labels: programMatrixExportLabels(l10n),
        formatFormation: (formation) => formationLabel(l10n, formation),
      ),
    );
  }

  /// The loaded venue records needed to resolve this program's linked venue on
  /// export. A program links at most one venue, so only [_linkedVenue] (kept in
  /// sync with the current selection) need be threaded through — no full
  /// `venues.listAll()` load is required.
  Map<String, Venue> get _exportVenuesById => {
    ?_linkedVenue?.id: ?_linkedVenue,
  };

  Widget _buildEditorColumn({required bool twoPane}) {
    final l10n = AppLocalizations.of(context);
    final draft = _draftProgram;
    final warnings = draft?.validate() ?? const <ValidationIssue>[];

    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: kTextEntryKeyboardDismiss,
        padding: const EdgeInsets.all(16),
        children: [
          _buildMetadataSection(),
          const SizedBox(height: 24),
          if (warnings.isNotEmpty) ...[
            _ProgramWarningsCard(warnings: warnings),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Text(
                l10n.programsSlotsLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${_slots.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!twoPane)
                OutlinedButton.icon(
                  key: const ValueKey('add-dance-slot'),
                  onPressed: _openPickerSheet,
                  icon: const Icon(Icons.library_music_outlined),
                  label: Text(l10n.programsAddDanceButton),
                ),
              OutlinedButton.icon(
                key: const ValueKey('add-free-text-slot'),
                onPressed: _addFreeTextSlot,
                icon: const Icon(Icons.notes_outlined),
                label: Text(l10n.programsAddNoteBreakButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('insert-break-slot'),
                onPressed: _insertBreakSlot,
                icon: const Icon(Icons.free_breakfast_outlined),
                label: Text(l10n.programsInsertBreakButton),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgramSlotListEditor(
            slots: _slots,
            danceTitles: _titleForDance,
            formationFor: _formationForDance,
            mixerFor: _mixerForDance,
            onReorder: _reorderSlot,
            onSlotChanged: _updateSlot,
            onRemove: _removeSlot,
            onCreateDance: _createDanceFromSlot,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _openPickerSheet() async {
    final data = _data;
    if (data == null) return;
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      l10n.programsAddADanceSheetTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('picker-sheet-close'),
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                Expanded(
                  child: ValueListenableBuilder<Map<String, int>>(
                    valueListenable: _pickerCounts,
                    builder: (context, counts, _) => CollectionPicker(
                      key: const ValueKey('sheet-picker'),
                      data: data,
                      dialect: _dialect,
                      enrichment: _enrichment,
                      scrollController: scrollController,
                      addedDanceCounts: counts,
                      // Keep the sheet open so callers can add several dances.
                      onAddDance: _addDanceSlot,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Builds the venue editor for the active venue entity mode.
  ///
  /// SIMPLE (default): the free-text venue field, unchanged. If the program is
  /// also linked to a saved venue (`venueId`), a read-only hint shows the
  /// linked venue name so the link isn't silently hidden — the free text above
  /// is what this mode edits and persists (the link rides through untouched).
  ///
  /// ENRICHED: a [VenuePicker] that selects/creates a saved venue. If the
  /// program has legacy free-text but no link yet, that text is shown with an
  /// invitation to link a venue below; the typed text is preserved.
  Widget _buildVenueField(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final enriched = VenueEntityModeScope.of(context);
    if (!enriched) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('program-venue'),
            controller: _venueController,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _markDirty(),
            decoration: InputDecoration(
              labelText: l10n.programsVenueLabel,
              hintText: l10n.programsVenueHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_venueId != null)
            Padding(
              key: const ValueKey('program-venue-linked-hint'),
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.programsVenueLinkedHint(
                        _linkedVenue?.displayName ??
                            l10n.programsVenueLinkedHintFallbackName,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    final legacyText = _venueController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (legacyText.isNotEmpty && _venueId == null)
          Padding(
            key: const ValueKey('program-venue-legacy-text'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.programsVenueLegacyTextHint(legacyText),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Text(l10n.programsVenueLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        VenuePicker(
          key: const ValueKey('program-venue-picker'),
          selectedVenueId: _venueId,
          onChanged: _onVenueLinkChanged,
        ),
      ],
    );
  }

  Widget _buildMetadataSection() {
    final l10n = AppLocalizations.of(context);
    final dateLabel = _eventDate == null
        ? l10n.programsNoDateSet
        : formatEventDate(
            _eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
            l10n,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('program-title'),
          controller: _titleController,
          autofocus: widget.isNew,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsTitleLabel,
            hintText: l10n.programsTitleHint,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? l10n.programsTitleRequired
              : null,
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.programsEventDateLabel,
            border: const OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(child: Text(dateLabel)),
              TextButton.icon(
                key: const ValueKey('pick-event-date'),
                onPressed: _pickEventDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  _eventDate == null
                      ? l10n.programsSetDate
                      : l10n.programsChangeDate,
                ),
              ),
              if (_eventDate != null)
                IconButton(
                  key: const ValueKey('clear-event-date'),
                  tooltip: l10n.programsClearEventDate,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _eventDate = null;
                      _dirty = true;
                    });
                    _scheduleAutosave();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildVenueField(l10n),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-band'),
          controller: _bandController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsBandLabel,
            hintText: l10n.programsBandHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-caller'),
          controller: _callerController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsCallerLabel,
            hintText: l10n.programsCallerHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-dancer-level'),
          controller: _levelController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsDancerLevelLabel,
            hintText: l10n.programsDancerLevelHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('program-notes'),
          controller: _notesController,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            labelText: l10n.programsNotesLabel,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ProgramStatus>(
          key: const ValueKey('program-status'),
          initialValue: _status,
          decoration: InputDecoration(
            labelText: l10n.programsStatusFieldLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final status in ProgramStatus.values)
              DropdownMenuItem(
                value: status,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      programStatusPresentation(status, l10n).icon,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(programStatusPresentation(status, l10n).label),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _status = value;
                _dirty = true;
              });
              _scheduleAutosave();
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('program-hide-alternates'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.programsHideAlternatesTitle),
          subtitle: Text(l10n.programsHideAlternatesSubtitle),
          value: _hideAlternates,
          onChanged: (value) {
            setState(() {
              _hideAlternates = value;
              _dirty = true;
            });
            _scheduleAutosave();
          },
        ),
      ],
    );
  }

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final stored = _eventDate;
    final initial = stored == null
        ? now
        : DateTime(stored.year, stored.month, stored.day);
    // The date picker follows the platform locale's first day of week; a
    // configurable first-day-of-week preference is a future item (ROADMAP G.8).
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _eventDate = DateTime.utc(picked.year, picked.month, picked.day);
        _dirty = true;
      });
      _scheduleAutosave();
    }
  }
}

/// Non-blocking warnings card mirroring the dance editor's `_WarningsCard`,
/// surfacing `Program.validate()` issues (e.g. `orphaned_alt`) with icon+text.
class _ProgramWarningsCard extends StatelessWidget {
  const _ProgramWarningsCard({required this.warnings});

  final List<ValidationIssue> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('program-warnings-card'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.programsWarningCount(warnings.length),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    validationIssueMessage(l10n, w),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for adding a free-text slot (break / waltz / announcement). Owns its
/// [TextEditingController] so it is disposed only after the dialog is gone,
/// avoiding "controller used after dispose" during the exit animation.
class _FreeTextSlotDialog extends StatefulWidget {
  const _FreeTextSlotDialog();

  @override
  State<_FreeTextSlotDialog> createState() => _FreeTextSlotDialogState();
}

class _FreeTextSlotDialogState extends State<_FreeTextSlotDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.programsAddNoteBreakDialogTitle),
      content: TextField(
        key: const ValueKey('free-text-slot-input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.programsFreeTextLabel,
          hintText: l10n.programsFreeTextHint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('free-text-slot-add'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonAdd),
        ),
      ],
    );
  }
}
