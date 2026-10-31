import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/user_figures_scope.dart';
import '../data/active_dialect_scope.dart';
import '../data/canonical_discouraged_terms_scope.dart';
import '../data/date_format_scope.dart';
import '../data/refresh_coalescer.dart';
import '../data/regional_formats.dart';
import '../data/repositories_scope.dart';
import '../data/app_theme_scope.dart';
import '../data/callersbox_online.dart';
import '../data/contradb_online.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/formation_colors_scope.dart';
import '../data/set_list_color_coding_scope.dart';
import '../data/mark_all_sets_status_scope.dart';
import '../data/show_performed_toggles_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../data/calling_history_caller_filter.dart';
import '../data/venue_label.dart';
import '../diagnostics/error_log.dart';
import '../editor/perform_adjustment_write.dart';
import '../editor/program_slot_rebase.dart';
import '../search/collection_data.dart';
import '../search/dance_detail_data.dart';
import '../search/facet_labels.dart';
import '../theme/app_spacing.dart';
import '../theme/set_list_accents.dart';
import '../utils/confirm_delete.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/program_export_menu.dart';
import '../widgets/program_status_chip.dart';
import 'dance_detail_screen.dart';
import 'dance_reimport_flow.dart';
import '../widgets/command_palette.dart';
import 'perform_program_screen.dart';
import 'program_editor_screen.dart';

/// How many times a row toggle re-reads and retries after losing a race with
/// another writer before it gives up and says so.
const int _kTogglePerformedAttempts = 3;

/// Full-screen, read-focused summary of a saved program, pushed on **narrow**
/// (phone / tablet-portrait) layouts when the user taps a program in the
/// programs list.
///
/// Mirrors the dance side's [DanceDetailScreen]: tapping a saved item opens a
/// **read view** — a Perform-first summary with a prominent "Perform this
/// program" action and an "Edit program" action — instead of dropping the
/// caller straight into the full-screen builder. Reuses the exact same
/// [ProgramSummaryPane] content the wide split-pane detail renders, so the two
/// layouts stay consistent.
///
/// The programs list reloads unconditionally when this route pops, so the
/// screen only self-manages what it must: **Edit** opens the builder (reloading
/// in place, or popping if the builder deleted the program), **Delete** pops
/// back to the list, and **Duplicate** re-targets this screen at the new copy.
class ProgramSummaryScreen extends StatefulWidget {
  const ProgramSummaryScreen({
    super.key,
    required this.programId,
    this.performResumeStore,
    this.callersBoxOnline,
    this.contraDbOnline,
    this.reimportPicker,
  });

  final String programId;

  /// See [ProgramSummaryPane.performResumeStore]. This screen is the open
  /// program, so it drops the program's resume state when it closes.
  final PerformResumeStore? performResumeStore;
  final OnlineSearchService? callersBoxOnline;
  final OnlineSearchService? contraDbOnline;
  final ImportPicker? reimportPicker;

  @override
  State<ProgramSummaryScreen> createState() => _ProgramSummaryScreenState();
}

class _ProgramSummaryScreenState extends State<ProgramSummaryScreen> {
  late String _programId = widget.programId;

  @override
  void dispose() {
    // This route is popped only when the caller leaves the program: a rotation
    // keeps it, since it sits on the root navigator.
    widget.performResumeStore?.forget(_programId);
    super.dispose();
  }

  Future<void> _openBuilder() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProgramEditorScreen(
          programId: _programId,
          callersBoxOnline: widget.callersBoxOnline,
          contraDbOnline: widget.contraDbOnline,
          reimportPicker: widget.reimportPicker,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      // The builder deleted the program; leave the summary and return to the
      // list (which reloads and drops the stale row).
      Navigator.of(context).pop();
    }
    // A save under the same id needs no tick: it writes `programs` /
    // `program_slots`, which are in the pane's watched set, so the stream has
    // already reloaded it (issue #768). Bumping a notifier here as well would
    // reload twice for one edit (issue #340) — and once the pane stopped
    // listening, would reload nothing at all while still looking wired.
  }

  @override
  Widget build(BuildContext context) {
    return ProgramSummaryPane(
      // Keyed on the program id so the pane fully resets (fresh load) when a
      // duplicate re-targets this screen.
      key: ValueKey('summary-screen-$_programId'),
      programId: _programId,
      showAppBar: true,
      prominentPerform: true,
      performResumeStore: widget.performResumeStore,
      onOpenBuilder: _openBuilder,
      onDeleted: () => Navigator.of(context).pop(),
      onNavigateTo: (id) {
        widget.performResumeStore?.forget(_programId);
        setState(() => _programId = id);
      },
      callersBoxOnline: widget.callersBoxOnline,
      contraDbOnline: widget.contraDbOnline,
      reimportPicker: widget.reimportPicker,
    );
  }
}

/// Read-only summary of the selected program shown in the wide detail pane. The
/// heavy building work happens in the full-screen [ProgramEditorScreen] route
/// launched by [onOpenBuilder]; this pane keeps quick duplicate/delete actions.
/// Raised into a pending first-value future when its subscription is replaced
/// or disposed (issue #768).
///
/// Deliberately not an error the user ever sees: being superseded is not a
/// failure. `_load` returns on it without touching `_error` or `_loading`,
/// because the load that replaced it owns those now — surfacing it would flash
/// an error banner in the middle of a successful refresh.
class _SupersededLoad implements Exception {
  const _SupersededLoad();
  @override
  String toString() => 'load superseded before its first snapshot';
}

class ProgramSummaryPane extends StatefulWidget {
  const ProgramSummaryPane({
    super.key,
    required this.programId,
    required this.onOpenBuilder,
    required this.onDeleted,
    required this.onNavigateTo,
    this.showAppBar = false,
    this.prominentPerform = false,
    this.performResumeStore,
    this.callersBoxOnline,
    this.contraDbOnline,
    this.reimportPicker,
  });

  final String programId;
  final VoidCallback onOpenBuilder;
  final VoidCallback onDeleted;
  final void Function(String id) onNavigateTo;

  /// Wraps the pane in a [Scaffold] [AppBar] (back button + generic title) when
  /// pushed as a full-screen route on narrow layouts. The wide detail pane
  /// leaves this `false` — its title lives in the body, not an app bar.
  final bool showAppBar;

  /// Renders a prominent full-width "Perform this program" button (Perform-first)
  /// in place of the compact perform icon button, for the narrow read view.
  final bool prominentPerform;

  /// Where Perform's place and clock are kept between launches (GIG-14): the
  /// Programs shell's store, which outlives this pane, so a rotation across
  /// the split breakpoint does not lose them. `null` keeps them in this pane.
  final PerformResumeStore? performResumeStore;
  final OnlineSearchService? callersBoxOnline;
  final OnlineSearchService? contraDbOnline;
  final ImportPicker? reimportPicker;

  /// Pane width (logical pixels) below which the title row keeps Perform and
  /// Export and moves Mark all performed, Duplicate and Delete into a "⋮"
  /// menu. Matches `DanceDetailScreen.compactActionsBreakpoint`.
  static const double compactActionsBreakpoint = 600;

  @override
  State<ProgramSummaryPane> createState() => _ProgramSummaryPaneState();
}

class _ProgramSummaryPaneState extends State<ProgramSummaryPane> {
  late CompendiumRepositories _repos;
  late DanceReimportCoordinator _reimport;
  bool _started = false;

  /// Last-seen "track calling history for all callers" setting (issue #583),
  /// used to scope the embedded dance data's call counts.
  bool _trackHistoryForAllCallers = false;
  Program? _program;
  Map<String, String> _danceTitles = const {};
  Map<String, Dance> _dances = const {};
  Map<String, Venue> _venuesById = const {};
  CollectionData? _collectionData;
  List<DifficultyLevel> _difficultyLevels = const [];
  bool _loading = true;

  /// True while [_performProgram] resolves deleted dances, so a double tap
  /// cannot push two Perform screens.
  bool _resolvingPerform = false;

  /// Re-entrancy guard for [_delete]. The confirm now reads the history count
  /// before its dialog opens (LIFE-6), so a second tap can land in that gap and
  /// stack a second dialog; confirming the top one would then make a narrow
  /// layout's `onDeleted` pop that dialog instead of this route. Same pattern
  /// as the editor's `_deleting`.
  bool _deleting = false;
  Object? _error;

  /// In-memory Perform resume state (issue #434), used when the host passes no
  /// [ProgramSummaryPane.performResumeStore]. Perform is pushed on top of this
  /// summary, so this survives that navigation: the Perform view hands back
  /// its live position + clock on exit and the next launch threads it back
  /// in, so re-entry resumes rather than resetting to slot 1 with a fresh
  /// clock.
  final PerformResumeStore _ownPerformResume = PerformResumeStore();

  PerformResumeStore get _performResume =>
      widget.performResumeStore ?? _ownPerformResume;

  /// For prose and formation labels only; a dance's figures go to
  /// `UserFiguresScope.rendererOf`, which shows uses of the user's own
  /// figures live (#1023).
  static final FigureRenderer _proseRenderer = FigureRenderer(contraTaxonomy);
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bulkUndoSnackBar;

  /// Collapses a burst of refresh requests into a single [_load].
  ///
  /// It no longer collapses "the two bumps a dance+program write emits" — this
  /// pane moved to the stream (#768), and the shell's `refreshTrigger` went
  /// with the rest of that plumbing. **One source reaches it now:
  /// [CollectionData.watch].**
  ///
  /// A single source does not make it redundant, which is why it survives
  /// rather than retiring with the subscriptions. `CollectionData.watch`
  /// coalesces on a leading edge with a trailing flush, so one burst can still
  /// deliver two emits — and [_load] pulls the whole collection, so loading
  /// twice is expensive as well as wrong (issue #340).
  late final RefreshCoalescer _refreshCoalescer = RefreshCoalescer(() {
    if (mounted) _load();
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture the "track all callers" setting so the embedded dance data's
    // call counts are scoped consistently with the Collection list (issue
    // #583). This screen loads once; a live toggle change is picked up on its
    // next refresh.
    _trackHistoryForAllCallers = TrackHistoryForAllCallersScope.of(context);
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _reimport = DanceReimportCoordinator(
        repos: _repos,
        callersBox: widget.callersBoxOnline ?? CallersBoxOnline(),
        contraDb: widget.contraDbOnline ?? ContraDbOnline(),
        picker: widget.reimportPicker ?? pickImportFile,
      );
      _load();
    }

    // This pane was the app's only BOTH-channels subscriber — it renders
    // program data *and* dance fields (`dance?.level`, the slot titles), so it
    // went stale from either side. Both subscriptions are gone: the watched
    // source set behind [CollectionData.watch] spans the dance tables *and*
    // `programs`/`program_slots`, so one stream covers what two channels did.
    // Writes made here no longer broadcast either — `ProgramsRefreshScope` was
    // retired once its last reader became stream-driven (issue #768).
  }

  Future<void> _beginReimport(
    BuildContext routeContext,
    DanceDetailData detail,
  ) => _reimport.open(routeContext, detail);

  /// The slots whose toggle write is in flight. A second tap on the same row
  /// while its write is in flight is ignored (it would set the same state).
  /// Other rows are never blocked: their writes serialise through
  /// [ProgramRepository.replaceIfUnchanged] and its retry.
  final Set<String> _togglingSlots = {};

  void _invalidateBulkUndo() {
    _bulkUndoSnackBar?.close();
    _bulkUndoSnackBar = null;
  }

  void _openBuilder() {
    _invalidateBulkUndo();
    widget.onOpenBuilder();
  }

  /// The live Collection reference data for this pane (issue #768).
  ///
  /// Later emits re-run [_load] in full rather than only replacing
  /// `_collectionData`, because this pane renders the *program* too and the
  /// watched source set includes `programs` / `program_slots` — so a slot being
  /// marked performed, or the program renamed elsewhere, arrives on this same
  /// stream. Re-reading the program on emit is what let both refresh-scope
  /// subscriptions come out.
  ///
  /// Safe to reload wholesale here, unlike the program *editor*: this pane is
  /// read-focused and holds no unsaved working copy.
  StreamSubscription<CollectionData>? _dataSub;

  /// The most recent snapshot the stream has delivered, and the filter the
  /// live subscription was opened with.
  ///
  /// [_load] runs again on every emit, because this pane reloads wholesale —
  /// the program, its dances and its venue all have to be re-fetched. Without
  /// these two fields it would also re-enter [_watchCollectionData], which
  /// cancels and re-opens the subscription and therefore re-runs the whole
  /// [CollectionData.load]. One write would cost two full
  /// snapshot loads and a fresh coalescer, which is the issue #340 thrash this
  /// conversion is supposed to avoid rather than introduce.
  CollectionData? _latestData;
  String? _subCallerFilter;

  /// The first-value future of the LIVE subscription, while it is still
  /// pending.
  ///
  /// Held as a field so that whoever abandons the subscription can settle it.
  /// See [_replaceSubscription] for why that is necessary rather than tidy.
  Completer<CollectionData>? _pendingFirst;

  /// Cancels the live subscription, settling its first-value future first.
  ///
  /// ## The invariant, and the full set of exits (issue #768)
  ///
  /// `_load` awaits the stream's FIRST value, so **every path that abandons a
  /// pending first-value future must complete it** — otherwise that `await`
  /// never returns. There are five ways out, and three were already handled by
  /// the listener callbacks:
  ///
  /// 1. a value arrives — `onData` completes it;
  /// 2. the source errors — `onError` completes it;
  /// 3. the source ends unemitted — `onDone` completes it;
  /// 4. **the subscription is replaced** by a re-entrant `_load`;
  /// 5. **the subscription is cancelled** in [dispose].
  ///
  /// 4 and 5 are the ones a listener cannot see: **cancelling a
  /// `StreamSubscription` invokes none of its callbacks**, by design. So they
  /// have to be handled at the point of abandonment, which is here — and this
  /// method exists so that cancelling without settling is not expressible.
  ///
  /// Earlier fixes closed exits one at a time (3 in round 9, 4 reported in
  /// round 11). The exits were enumerated this time instead.
  void _replaceSubscription() {
    final pending = _pendingFirst;
    _pendingFirst = null;
    if (pending != null && !pending.isCompleted) {
      // A sentinel rather than a real error: the caller has been superseded,
      // which is not a failure to report to the user. `_load` returns quietly
      // on it, leaving the newer load to own the screen's state.
      pending.completeError(const _SupersededLoad());
    }
    unawaited(_dataSub?.cancel());
    _dataSub = null;
  }

  /// Opens the subscription and resolves with its FIRST value, so [_load]'s
  /// existing sequence is untouched while later emits drive a refresh.
  ///
  /// Reuses the live subscription when the caller filter is unchanged: a
  /// re-entry from an emit already has a newer snapshot in hand than a fresh
  /// subscription would produce, so re-subscribing would buy nothing and pay
  /// a second full load for it.
  ///
  /// ## Why the gate tests [_pendingFirst], and not just the filter
  ///
  /// The question the reuse branch must answer is **"has THIS subscription
  /// produced the snapshot I am about to hand back?"** — not the narrower
  /// "is the live subscription for this filter?". The two come apart in one
  /// window: between opening a subscription for a NEW filter and its first
  /// emit, [_subCallerFilter] already names the new filter while [_latestData]
  /// still holds the OLD filter's snapshot. A re-entrant [_load] landing in
  /// that window satisfied all three of the earlier conditions and was handed
  /// the previous filter's data — wrong call tallies, wrong last-called.
  ///
  /// `_pendingFirst == null` states the missing precondition directly: it is
  /// non-null exactly while a subscription has yet to deliver its first value,
  /// so requiring it to be null is requiring [_latestData] to have come from
  /// the live subscription. Clearing [_latestData] in [_replaceSubscription]
  /// would also have hidden the symptom, but would have left the gate asking
  /// the question that was wrong — the same shape as the author-sort miss,
  /// where a skip condition was narrower than the cases it had to cover.
  ///
  /// This does not weaken the issue #340 protection above: on the reuse path
  /// the subscription has emitted by definition, so `_pendingFirst` is null
  /// there and the branch still fires.
  ///
  /// ## No longer covered by a test on this screen, and why
  ///
  /// It was, until the Programs refresh plumbing came out (issue #768). The
  /// coalescer is now [_load]'s only caller, so re-entering it is a race inside
  /// the two DB reads that precede this method rather than something a test can
  /// ask for — and the clause only changes the outcome while the replacement
  /// subscription is still pending, which cannot be held open without leaving
  /// the pane with nothing to settle it. A test written for it passed with the
  /// clause deleted; it was withdrawn rather than kept as false coverage, with
  /// the reasoning in `refresh_scopes_test.dart` where it used to live.
  ///
  /// The clause stays. It is one comparison, it is correct, and
  /// `program_editor_screen` reaches this same path deliberately now
  /// (`_resubscribePicker`, issue #948) — so the class is live even though this
  /// screen's instance of it is not.
  Future<CollectionData> _watchCollectionData(String? callerFilter) {
    final cached = _latestData;
    if (_dataSub != null &&
        _pendingFirst == null &&
        _subCallerFilter == callerFilter &&
        cached != null) {
      return Future<CollectionData>.value(cached);
    }
    final first = Completer<CollectionData>();
    _replaceSubscription();
    _pendingFirst = first;
    _subCallerFilter = callerFilter;
    _dataSub =
        CollectionData.watch(
          _repos,
          callerFilter: callerFilter,
          // This pane renders the program's venue label, which is resolved from
          // a table `CollectionData` does not carry (issue #944). Opting in is
          // what makes a venue rename reach `_venuesById` below; the Collection
          // list renders no venue and deliberately does not opt in.
          watchVenues: true,
        ).listen(
          (data) {
            _latestData = data;
            if (!first.isCompleted) {
              _pendingFirst = null;
              first.complete(data);
              return;
            }
            if (mounted) _refreshCoalescer.request();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!first.isCompleted) {
              _pendingFirst = null;
              first.completeError(error);
              return;
            }
            // Unlike the program EDITOR, this pane can show an error and holds no
            // unsaved work, so a failed refresh is surfaced rather than left to
            // render stale data indefinitely.
            logCaughtError(
              error,
              stackTrace,
              source: 'program_summary_screen._watchCollectionData',
            );
            if (mounted) setState(() => _error = error);
          },
          onDone: () {
            // The source can end without ever emitting — the database closed while
            // this pane was opening. Completing the future is what stops `_load`
            // awaiting forever; the error routes to its existing catch.
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

  @override
  void dispose() {
    _replaceSubscription();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final program = await _repos.programs.getById(widget.programId);
      if (program == null) {
        if (!mounted) return;
        setState(() {
          _program = null;
          _danceTitles = const {};
          _dances = const {};
          _venuesById = const {};
          _collectionData = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      final callerFilter = await resolveCallingHistoryCallerFilter(
        _repos.settings,
        trackAllCallers: _trackHistoryForAllCallers,
      );
      final data = await _watchCollectionData(callerFilter);
      final difficultyLevels = await _repos.difficultyLevels.listAll();
      final titles = <String, String>{};
      final dances = <String, Dance>{};
      final ids = {
        for (final s in program.slots)
          if (s.danceId != null) s.danceId!,
      };
      // A dance in Recently deleted still renders, marked as deleted, and
      // still reaches the exports (GIG-11): the same lookup as
      // `resolveDeletedSlotDances`, which Perform uses.
      final loaded = await Future.wait(
        ids.map((id) => _repos.dances.getById(id, includeDeleted: true)),
      );
      for (final dance in loaded) {
        if (dance != null) {
          titles[dance.id] = dance.title;
          dances[dance.id] = dance;
        }
      }
      // Resolve only the linked venue (if any). The summary shows a single
      // program, so loading the whole catalogue just to look up one id is
      // wasteful; resolveVenueLabel falls back to free text when the map is
      // empty (no link, or the link no longer resolves).
      final venuesById = <String, Venue>{};
      final linkedVenueId = program.venueId;
      if (linkedVenueId != null) {
        final linked = await _repos.venues.getById(linkedVenueId);
        if (linked != null) venuesById[linkedVenueId] = linked;
      }
      if (!mounted) return;
      setState(() {
        _program = program;
        _danceTitles = titles;
        _dances = dances;
        _venuesById = venuesById;
        _collectionData = data;
        _difficultyLevels = difficultyLevels;
        _loading = false;
        _error = null;
      });
    } on _SupersededLoad {
      // diagnostics: silent — a newer `_load` replaced this one's
      // subscription before it produced a snapshot. It owns
      // `_loading`/`_error` now, so this call must leave both alone and
      // return — clearing `_loading` here would unblank the pane while the
      // newer load is still running.
      return;
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'program_summary_screen._load');
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _duplicate() async {
    final source = _program;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.programsDuplicatedSnack(copy.title))),
    );
    // The copy carries the same dance slots, so every derived count moved.
    widget.onNavigateTo(copy.id);
  }

  Future<void> _delete() async {
    final source = _program;
    if (source == null || _deleting) return;
    _deleting = true;
    try {
      await _deleteConfirmed(source);
    } finally {
      _deleting = false;
    }
  }

  Future<void> _deleteConfirmed(Program source) async {
    // ROADMAP G.7: optional confirm dialog before the (still-undoable) delete.
    if (!await confirmDeleteProgramIfEnabled(
      context,
      itemLabel: source.title,
      programId: source.id,
      repositories: _repos,
    )) {
      return;
    }
    if (!mounted) return;
    await _repos.programs.softDelete(source.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // Nothing is captured before the snackbar any more. [onDeleted] unmounts
    // this pane in BOTH layouts — the wide shell clears the selection and swaps
    // in the empty pane, the narrow route pops — so a broadcast from inside the
    // undo callback had to hold a notifier resolved up-front, and a
    // `mounted`-guarded bump would never have fired at all. The restore is now
    // its own notification: every program view watches `programs` (issue #768),
    // whether or not the screen that offered the Undo still exists.
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      message: l10n.programsDeletedSnack(source.title),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.programs.restore(source.id, at: DateTime.now().toUtc());
      },
    );
    widget.onDeleted();
  }

  /// Launches the large-print Perform view for the current saved program,
  /// mirroring [ProgramEditorScreen]'s perform launch. No-op when there is
  /// nothing to perform or the reference data has not finished loading.
  Future<void> _performProgram() async {
    final program = _program;
    final data = _collectionData;
    if (program == null || data == null || program.slots.isEmpty) return;
    if (_resolvingPerform) return;
    _resolvingPerform = true;
    _invalidateBulkUndo();
    final DeletedSlotDances deletedDances;
    try {
      deletedDances = await resolveDeletedSlotDances(
        _repos.dances,
        _repos.choreographers,
        program.slots,
        data,
      );
    } finally {
      _resolvingPerform = false;
    }
    if (!mounted) return;
    // Each Perform write, as stored: the token the post-exit Undo compares
    // the stored program against (flows-1). Keyed by the adjusted program's
    // identity, so a stale Undo cannot match a later adjustment's write.
    final storedAfterWrite = Expando<Program>();
    final resumeStore = _performResume;
    final resume = resumeStore[program.id];
    // The stored program Perform's copy is based on: the one it opens with,
    // then each adjustment's write as stored (GIG-6). Writes run one after
    // another, so each compares with the one before it rather than finding
    // its own earlier write "changed elsewhere".
    var performBase = program;
    Future<void> performWrites = Future<void>.value();
    // Resolved before the push: the route may rebuild after this screen has
    // gone, when its context can no longer be read.
    final renderer = UserFiguresScope.rendererOf(context);
    final repos = _repos;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Ctrl-K is suppressed while this route is on top ([performRouteName]).
        settings: const RouteSettings(name: performRouteName),
        builder: (_) => PerformProgramScreen(
          program: program,
          data: data,
          danceOverrides: deletedDances.dances,
          authorNameOverrides: deletedDances.authorNames,
          difficultyLevels: _difficultyLevels,
          renderer: renderer,
          // Resume where the caller left off (issue #434), from the shell's
          // store when there is one, so the place survives this pane being
          // rebuilt by a rotation across the breakpoint (GIG-14).
          initialGroup: resume?.groupIndex ?? 0,
          initialElapsedSeconds: resume?.elapsedSeconds ?? 0,
          initialSlotStartSeconds: resume?.slotStartSeconds ?? 0,
          initialPaused: resume?.paused ?? false,
          initialWalkthroughEndedAtSlotSeconds:
              resume?.walkthroughEndedAtSlotSeconds,
          initialWalkthroughEndedSlotId: resume?.walkthroughEndedSlotId,
          onExit: (state) => resumeStore[program.id] = state,
          // This is the real in-event path: the program is saved, so in-event
          // adjustments (`docs/design/ux.md` §5) persist immediately via the
          // repository (bumping `updatedAt`, and possibly the slot count). The
          // summary and the coexisting Programs list both re-render from their
          // own subscriptions, so neither needs telling.
          //
          // Only the adjustment's own change is written, onto the program as
          // stored and as a compare-and-replace, so a change that landed while
          // Perform was open (Device Sync, typically) is kept rather than
          // overwritten by Perform's copy; Perform is then handed the newer
          // program to show (GIG-6). Uses the repository rather than this
          // pane, which may itself have closed by then.
          onProgramChanged: (before, updated) async {
            final queued = performWrites.then(
              (_) =>
                  writePerformAdjustment(
                    repos.programs,
                    programId: program.id,
                    expected: performBase,
                    before: before.slots,
                    after: updated.slots,
                  ).then((write) {
                    performBase = write.stored;
                    return write;
                  }),
            );
            performWrites = queued.then<void>(
              (_) {},
              // diagnostics: silent — the failure is logged below, where this write is awaited; the next write only needs the queue to move on.
              onError: (_) {},
            );
            final PerformAdjustmentWrite write;
            try {
              write = await queued;
            } on Object catch (error, stackTrace) {
              // export-guard: exempt — Perform adjustment write, not an export
              // diagnostics: logged — Perform keeps the change on screen.
              // `Object`: a program deleted meanwhile fails with a StateError.
              logCaughtError(
                error,
                stackTrace,
                source: 'program_summary_screen._performPersist',
              );
              return null;
            }
            storedAfterWrite[updated] = write.stored;
            // The write itself is what reloads this pane and every other view
            // of these slots — the coexisting program list, the Collection's
            // "called N times" badge, a mounted dance detail's calling history.
            // Calling `_load` here as well would load this pane twice for one
            // adjustment (issue #340).
            return write.changedUnderneath ? write.stored : null;
          },
          // The "Program adjusted" Undo after leaving Perform restores only
          // while the stored program still equals, field for field, what that
          // adjustment's write stored; the compare and the restore are one
          // transaction, so no edit or sync apply can slip between them
          // (flows-1). It reverses only the adjustment's own change, so a
          // change from elsewhere that the write was applied on top of stays.
          restoreIfUnchanged: (previous, adjusted) async {
            final expected = storedAfterWrite[adjusted];
            if (expected == null) return false;
            return repos.programs.replaceIfUnchanged(
              expected: expected,
              replacement: expected.copyWith(
                slots: renumberSlots(
                  rebaseSlotEdits(
                    before: adjusted.slots,
                    after: previous.slots,
                    onto: expected.slots,
                  ),
                ),
              ),
              updatedAt: DateTime.now().toUtc(),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: Text(l10n.programsSummaryTitle))
          : null,
      // Below [ProgramSummaryPane.compactActionsBreakpoint] the title row
      // keeps Perform and Export; the rest fold into [_secondaryActionsMenu].
      body: LayoutBuilder(
        builder: (context, constraints) => _buildBody(
          compact:
              constraints.maxWidth <
              ProgramSummaryPane.compactActionsBreakpoint,
        ),
      ),
      floatingActionButton: (_program != null)
          ? FloatingActionButton.extended(
              key: const ValueKey('open-builder'),
              heroTag: 'open-builder',
              onPressed: _openBuilder,
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.programsEditProgram),
            )
          : null,
    );
  }

  Widget _buildBody({required bool compact}) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.programsLoading),
      );
    }
    final program = _program;
    if (_error != null || program == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.programsSummaryUnavailable),
        ),
      );
    }

    final theme = Theme.of(context);
    final danceCount = program.plannedDanceCount;
    final dateLabel = program.eventDate == null
        ? null
        : formatEventDate(
            program.eventDate!,
            DateFormatScope.of(context),
            MaterialLocalizations.of(context),
            l10n,
          );

    return ListView(
      // The bottom inset lets the last slot scroll clear of the Edit FAB.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.fabClearance,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(program.title, style: theme.textTheme.headlineSmall),
            ),
            if (!widget.prominentPerform) _buildPerformAction(program),
            ProgramExportMenu(
              program: program,
              titleFor: (id) => _danceTitles[id],
              venuesById: _venuesById,
              danceFor: (id) => _dances[id],
              choreographerFor: (id) => _collectionData?.choreographersById[id],
              tagFor: (id) => _collectionData?.tagFor(id),
              publishedSourceFor: (id) =>
                  _collectionData?.publishedSourceFor(id),
              customFieldFor: (id) => _collectionData?.customFieldFor(id),
              difficultyLevelFor: (id) => _difficultyLevelFor(_dances[id]),
            ),
            if (compact)
              _secondaryActionsMenu(program)
            else ...[
              if (program.slots.any((s) => s.danceId != null))
                IconButton(
                  key: const ValueKey('mark-all-performed'),
                  tooltip: l10n.programsMarkAllPerformedTooltip,
                  icon: const Icon(Icons.done_all),
                  onPressed: _markAllPerformed,
                ),
              IconButton(
                key: const ValueKey('summary-duplicate'),
                tooltip: l10n.commonDuplicate,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: _duplicate,
              ),
              IconButton(
                key: const ValueKey('summary-delete'),
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ProgramStatusChip(status: program.status),
        if (widget.prominentPerform) ...[
          const SizedBox(height: 16),
          _buildProminentPerform(program),
        ],
        const SizedBox(height: 16),
        if (dateLabel != null) _summaryRow(Icons.event_outlined, dateLabel),
        if (resolveVenueLabel(program, _venuesById) case final venueLabel?)
          _summaryRow(Icons.place_outlined, venueLabel),
        if (program.band != null)
          _summaryRow(
            Icons.music_note_outlined,
            l10n.programsSummaryBand(program.band!),
          ),
        if (program.caller != null)
          _summaryRow(
            Icons.campaign_outlined,
            l10n.programsSummaryCaller(program.caller!),
          ),
        if (program.dancerLevel != null)
          _summaryRow(
            Icons.signal_cellular_alt_outlined,
            l10n.programsSummaryLevel(_displayProse(program.dancerLevel!)),
          ),
        if ((program.payMinorUnits, program.payCurrency) case (
          final pay?,
          final currency?,
        ))
          _summaryRow(
            Icons.payments_outlined,
            l10n.programsSummaryPay(
              '${formatPayMinorUnits(pay, currency)} $currency',
            ),
          ),
        if (program.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.programsNotesLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(_displayProse(program.notes)),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.programsSetListHeader(danceCount),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ..._buildSetList(program),
        const SizedBox(height: 80),
      ],
    );
  }

  /// The narrow title row's "⋮" menu: Mark all performed, Duplicate and
  /// Delete, under the keys and labels of the buttons they replace.
  Widget _secondaryActionsMenu(Program program) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<void>(
      key: const ValueKey('summary-actions-overflow'),
      tooltip: l10n.programsMoreActions,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        if (program.slots.any((s) => s.danceId != null))
          PopupMenuItem<void>(
            key: const ValueKey('mark-all-performed'),
            onTap: _markAllPerformed,
            child: ListTile(
              leading: const Icon(Icons.done_all),
              title: Text(l10n.programsMarkAllPerformedTooltip),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem<void>(
          key: const ValueKey('summary-duplicate'),
          onTap: _duplicate,
          child: ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: Text(l10n.commonDuplicate),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<void>(
          key: const ValueKey('summary-delete'),
          onTap: _delete,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.commonDelete),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  /// "Perform this program" action shown in the summary's top action Row,
  /// mirroring the program builder's `perform-program` AppBar action. Disabled
  /// (with an explanatory tooltip) when the program has no slots or the
  /// reference data has not loaded yet, mirroring the editor's `_slots.isEmpty`
  /// guard — never a dead button. The disabled state is exposed to assistive
  /// technology via the button's own disabled semantics, not colour alone.
  Widget _buildPerformAction(Program program) {
    final l10n = AppLocalizations.of(context);
    final canPerform = program.slots.isNotEmpty && _collectionData != null;
    return IconButton(
      key: const ValueKey('summary-perform'),
      tooltip: canPerform
          ? l10n.programsPerformTooltip
          : l10n.programsPerformDisabledTooltip,
      icon: const Icon(Icons.slideshow),
      onPressed: canPerform ? _performProgram : null,
    );
  }

  /// Prominent, full-width "Perform this program" button for the narrow
  /// read-focused summary — the Perform-first primary action a caller reaches
  /// for at a gig. Shares the [ValueKey]`('summary-perform')` and disabled-state
  /// semantics of [_buildPerformAction] (only one is ever in the tree at a
  /// time), so the same dead-button guard and tooltip apply: disabled (never
  /// absent-and-tappable) with an explanatory tooltip when the program has no
  /// slots or the reference data has not loaded yet.
  Widget _buildProminentPerform(Program program) {
    final l10n = AppLocalizations.of(context);
    final canPerform = program.slots.isNotEmpty && _collectionData != null;
    return Tooltip(
      message: canPerform
          ? l10n.programsPerformTooltip
          : l10n.programsPerformDisabledTooltip,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('summary-perform'),
          onPressed: canPerform ? _performProgram : null,
          icon: const Icon(Icons.slideshow),
          label: Text(l10n.programsPerformTooltip),
        ),
      ),
    );
  }

  /// Marks every primary slot with a dance as performed (now) — alternates are
  /// skipped ([ProgramSlot.isBulkMarkPerformedTarget]) — persists the change,
  /// and reloads the summary. Mirrors [ProgramEditorScreen]'s
  /// `_markAllPerformed` (no confirm dialog), but writes through the repository
  /// immediately because the summary shows a saved program — there is no draft
  /// to fold into a later save. Only reachable when at least one slot has a
  /// dance, matching the builder's guard; with only alternates it marks nothing.
  ///
  /// While "Mark all performed sets the status" is on (the default, GIG-12), it
  /// also sets the status to Performed — even when every primary was already
  /// marked — and Undo puts the status back with the marks.
  Future<void> _markAllPerformed() async {
    final program = _program;
    if (program == null) return;
    final setsStatus =
        MarkAllSetsStatusScope.read(context) &&
        program.status != ProgramStatus.performed;
    final now = nextStoredTimestamp(
      now: DateTime.now().toUtc(),
      current: program.slots.map((s) => s.performedAt),
    );
    final markedSlotIds = <String>{};
    final updatedSlots = <ProgramSlot>[];
    for (final s in program.slots) {
      // Alternates are skipped: one counts as called only once the caller
      // marks it by hand (maintainer ruling, 2026-10-28).
      if (s.isBulkMarkPerformedTarget) {
        markedSlotIds.add(s.id);
        updatedSlots.add(s.copyWith(performedAt: now));
      } else {
        updatedSlots.add(s);
      }
    }
    if (markedSlotIds.isEmpty && !setsStatus) {
      // Every primary was already marked: say why the alternates still are not,
      // rather than doing nothing visible. There is nothing to undo.
      if (program.slots.any(_isUnmarkedAlternate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).programsMarkedAllPerformedExceptAlternates,
            ),
          ),
        );
      }
      return;
    }
    final updated = program.copyWith(
      slots: updatedSlots,
      updatedAt: now,
      status: setsStatus ? ProgramStatus.performed : null,
    );
    // Every stamp target is already marked, so the repository's stamp on the
    // move to Performed (#356) finds nothing left to stamp.
    await _repos.programs.update(updated);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final exceptAlternates = updatedSlots.any(_isUnmarkedAlternate);
    _bulkUndoSnackBar = showUndoSnackBar(
      messenger,
      message: switch ((exceptAlternates, setsStatus)) {
        (true, true) =>
          l10n.programsMarkedAllPerformedExceptAlternatesSetStatus,
        (true, false) => l10n.programsMarkedAllPerformedExceptAlternates,
        (false, true) => l10n.programsMarkedAllPerformedSetStatus,
        (false, false) => l10n.programsMarkedAllPerformed,
      },
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () => unawaited(
        _undoMarkAllPerformed(
          programId: program.id,
          markedSlotIds: markedSlotIds,
          actionTimestamp: now,
          restoreStatus: setsStatus ? program.status : null,
          messenger: messenger,
          errorMessage: l10n.programsUndoPerformedError,
        ),
      ),
    );
    // Mark-all-performed is exactly the write that made the Collection's
    // "called N times" badge stale (issue #768, gap 3). It used to broadcast
    // for that reason; the badge and the calling history watch `program_slots`
    // themselves now, so the write reaches them unaided and this pane's own
    // stream re-emits for it.
  }

  /// The per-row mark-performed toggle (shown while "Show mark-performed
  /// toggles" is on). A plain button in the row, so it needs no swipe or long
  /// press; the semantics name the dance and its state, and the 48dp target is
  /// the [IconButton] default.
  Widget _performedToggle(ProgramSlot slot, String title) {
    final l10n = AppLocalizations.of(context);
    final performed = slot.performedAt != null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      toggled: performed,
      label: performed
          ? l10n.programsSummaryPerformedToggleOn(title)
          : l10n.programsSummaryPerformedToggleOff(title),
      onTap: () => unawaited(_setPerformed(slot.id, title, !performed)),
      child: IconButton(
        key: ValueKey('summary-slot-${slot.id}-performed-toggle'),
        tooltip: performed
            ? l10n.programsSummaryClearPerformedTooltip(title)
            : l10n.programsSummaryMarkPerformedTooltip(title),
        isSelected: performed,
        icon: const Icon(Icons.radio_button_unchecked),
        selectedIcon: const Icon(Icons.check_circle_outline),
        onPressed: () => unawaited(_setPerformed(slot.id, title, !performed)),
      ),
    );
  }

  /// Sets one slot's performed mark to [marking] — what the tapped row
  /// showed, flipped — and offers Undo. A slot already in that state in the
  /// store (another device synced the same mark in, or a double tap) is left
  /// alone rather than flipped back, so a tap never does the opposite of what
  /// the caller saw.
  ///
  /// Marking stamps with [nextStoredTimestamp]; clearing removes the stamp —
  /// the same per-slot behaviour as the builder. The write is computed from the
  /// *stored* program, never [_program] (this pane's possibly stale loaded
  /// copy), and lands through [ProgramRepository.replaceIfUnchanged], so an edit
  /// or sync apply that landed since the read is neither overwritten nor
  /// silently dropped: the compare fails and the toggle re-reads and retries.
  Future<void> _setPerformed(String slotId, String title, bool marking) async {
    final programId = _program?.id;
    if (programId == null || !_togglingSlots.add(slotId)) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    _invalidateBulkUndo();
    try {
      for (var attempt = 0; attempt < _kTogglePerformedAttempts; attempt++) {
        final stored = await _repos.programs.getById(programId);
        final before = stored?.slots.where((s) => s.id == slotId).firstOrNull;
        // The program or the row is gone (deleted, or removed elsewhere).
        if (stored == null || before == null) return;
        if ((before.performedAt != null) == marking) return;
        final updatedSlots = [
          for (final s in stored.slots)
            if (s.id != slotId)
              s
            else if (marking)
              s.copyWith(
                performedAt: nextStoredTimestamp(
                  now: DateTime.now().toUtc(),
                  current: stored.slots.map((x) => x.performedAt),
                ),
              )
            else
              s.copyWith(clearPerformedAt: true),
        ];
        final wrote = await _repos.programs.replaceIfUnchanged(
          expected: stored,
          replacement: stored.copyWith(slots: updatedSlots),
          updatedAt: DateTime.now().toUtc(),
        );
        if (!wrote) continue;
        // The Undo token is the program as the write stored it. Read back now;
        // if something else already changed this slot there is nothing of ours
        // left to undo, so no Undo is offered.
        final after = await _repos.programs.getById(programId);
        final afterSlot = after?.slots.where((s) => s.id == slotId).firstOrNull;
        final message = marking
            ? l10n.programsSummaryMarkedPerformedSnack(title)
            : l10n.programsSummaryClearedPerformedSnack(title);
        if (!mounted) return;
        if (after == null ||
            afterSlot == null ||
            (afterSlot.performedAt == null) == marking) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
          return;
        }
        showUndoSnackBar(
          messenger,
          message: message,
          undoLabel: l10n.commonUndo,
          undoFailedMessage: l10n.commonUndoFailed,
          accessibleNavigation: accessibleNavigation,
          onUndo: () => unawaited(
            _undoTogglePerformed(
              token: after,
              slotId: slotId,
              restore: before,
              messenger: messenger,
              errorMessage: l10n.programsSummaryUndoPerformedToggleError,
            ),
          ),
        );
        return;
      }
      // Every attempt lost a race with another writer.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.programsSummaryPerformedToggleError)),
        );
      }
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_summary_screen._setPerformed',
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.programsSummaryPerformedToggleError)),
        );
      }
    } finally {
      _togglingSlots.remove(slotId);
    }
  }

  /// Puts one slot back to [restore]'s performed state, but only while the
  /// stored program is still [token] (what the toggle's write stored). The
  /// replacement is [token] with just that slot reverted, so nothing else is
  /// rewritten from an older snapshot.
  Future<void> _undoTogglePerformed({
    required Program token,
    required String slotId,
    required ProgramSlot restore,
    required ScaffoldMessengerState messenger,
    required String errorMessage,
  }) async {
    var restored = false;
    try {
      restored = await _repos.programs.replaceIfUnchanged(
        expected: token,
        replacement: token.copyWith(
          slots: [
            for (final s in token.slots)
              if (s.id != slotId)
                s
              else if (restore.performedAt == null)
                s.copyWith(clearPerformedAt: true)
              else
                s.copyWith(performedAt: restore.performedAt),
          ],
        ),
        updatedAt: DateTime.now().toUtc(),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_summary_screen._undoTogglePerformed',
      );
    }
    if (restored) return;
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!messenger.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    });
  }

  static bool _isUnmarkedAlternate(ProgramSlot s) =>
      s.danceId != null && s.isAlt && s.performedAt == null;

  Future<void> _undoMarkAllPerformed({
    required String programId,
    required Set<String> markedSlotIds,
    required DateTime actionTimestamp,
    required ProgramStatus? restoreStatus,
    required ScaffoldMessengerState messenger,
    required String errorMessage,
  }) async {
    try {
      await _repos.programs.clearPerformedAtIfMatches(
        programId: programId,
        slotIds: markedSlotIds,
        performedAt: actionTimestamp,
        updatedAt: DateTime.now().toUtc(),
        restoreStatus: restoreStatus,
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'program_summary_screen._undoMarkAllPerformed',
      );
      messenger
        ..clearSnackBars()
        ..removeCurrentSnackBar();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!messenger.mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
      });
    }
  }

  /// Builds the read-only, ordered set list. Planned dances are numbered 1..n
  /// and the break is not; ALT alternates render indented beneath their
  /// primary with an icon + text label (never colour alone), per
  /// `docs/design/ux.md` §4. Dance rows are tappable and open
  /// [DanceDetailScreen], except a dance in Recently deleted; free-text slots
  /// are plain, non-interactive text. Editing/reordering stays behind the builder FAB.
  List<Widget> _buildSetList(Program program) {
    if (program.slots.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            AppLocalizations.of(context).programsSummaryEmptySetList,
            key: const ValueKey('summary-set-list-empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    final rows = <Widget>[];
    // Planned dances are numbered and the break is not, as in the set list's
    // text and PDF (GIG-10).
    var ordinal = 0;
    for (final group in program.outputGrouped) {
      rows.add(
        _slotRow(
          group.primary,
          ordinalLabel: group.primary.isPlannedDance ? '${++ordinal}' : null,
        ),
      );
      for (final alt in group.alternates) {
        rows.add(_slotRow(alt, ordinalLabel: null, indented: true));
      }
    }
    return rows;
  }

  String _displayProse(String text) {
    if (!CanonicalDiscouragedTermsScope.of(context)) return text;
    final dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    return FigureRenderer(
      contraTaxonomy,
    ).renderFreeTextWithCanonicalDiscouragedTerms(text, dialect);
  }

  Widget _slotRow(
    ProgramSlot slot, {
    required String? ordinalLabel,
    bool indented = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final danceId = slot.danceId;
    // Colour-code accent (issue #270): a *redundant* cue paired with the
    // formation text below. Suppressed when the user disables it. High contrast
    // is either the app's high-contrast theme or the OS setting, in which case
    // we use the brighter high-contrast palette.
    final colorCodingEnabled = SetListColorCodingScope.of(context);
    final highContrast =
        (AppThemeScope.maybeOf(context)?.isHighContrast ?? false) ||
        MediaQuery.highContrastOf(context);

    Widget leading = SizedBox(
      width: 28,
      child: Text(
        ordinalLabel ?? '',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    // Secondary metadata line (guest caller / planned minutes), shared by all
    // slot types when present. Trimmed for display, matching the builder UI.
    final extras = <String>[
      if (slot.guestCaller != null && slot.guestCaller!.trim().isNotEmpty)
        l10n.programsSummaryGuest(slot.guestCaller!.trim()),
      if (slot.plannedTotalMinutes != null)
        l10n.programsPlannedMinutes(slot.plannedTotalMinutes!),
    ];

    final altBadge = slot.isAlt
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 2),
              Text(
                l10n.programsAltBadge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
            ],
          )
        : null;

    if (danceId != null) {
      final dance = _dances[danceId];
      final storedTitle = dance?.title ?? _danceTitles[danceId];
      // A dance in Recently deleted is marked as Perform marks it, and its row
      // opens nothing: the dance details read live dances only.
      final deleted = dance?.isDeleted ?? false;
      final title = storedTitle == null || !deleted
          ? storedTitle
          : '$storedTitle ${l10n.programsDeletedDanceFallback}';
      final performed = slot.performedAt != null;
      final showToggle = title != null && ShowPerformedTogglesScope.of(context);
      if (title == null) {
        // The dance no longer resolves (deleted/tombstoned). Render a graceful,
        // non-interactive fallback rather than a broken tappable row.
        return Padding(
          padding: EdgeInsets.only(left: indented ? 32 : 0, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              Icon(
                Icons.report_gmailerrorred_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?altBadge,
                    Text(
                      l10n.programsDanceUnavailable,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      final secondaryParts = <String>[
        if (dance != null)
          formationDisplayLabel(
            l10n,
            dance.formation,
            _proseRenderer,
            ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins,
            canonicalizeDiscouragedTerms: CanonicalDiscouragedTermsScope.of(
              context,
            ),
          ),
        if (dance != null)
          if (_difficultyLevelFor(dance) case final level?)
            danceLevelLabel(l10n, level),
        if (dance != null && dance.mixer) l10n.commonMixer,
        // A dance slot may also carry a per-slot caller note (per ProgramSlot
        // docs); surface it like the builder UI does.
        if (slot.text != null && slot.text!.trim().isNotEmpty)
          l10n.programsSummaryNote(_displayProse(slot.text!.trim())),
        ...extras,
      ];
      final secondary = secondaryParts.join(' · ');

      // Resolve the redundant formation accent (issue #270, extended for mixer
      // flag in issue #732). Only when a dance resolves, color-coding is on, and
      // the family has a themed accent. Mixer-flagged dances get the mixer accent
      // regardless of shape; otherwise the user's own formation colour wins
      // over the family tint (PRES-12) — see setListAccentForRow.
      final accent = (dance != null && colorCodingEnabled)
          ? setListAccentForRow(
              dance.formation.shape,
              dance.mixer,
              userColor: FormationColorsScope.of(
                context,
              )?.overrideFor(dance.formation.shape),
              highContrast: highContrast,
            )
          : null;
      // Expose the formation and, for mixer-flagged dances, the mixer term to AT
      // so the row is fully readable without colour (ux.md §4): the accent is
      // never the sole carrier of type/form — mixer-flagged dances append the
      // mixer term to both the visible secondary text and the semantics label.
      final semanticsLabel = [
        slot.isAlt ? l10n.programsSummaryAlternateSemantic(title) : title,
        if (dance != null)
          formationDisplayLabel(
            l10n,
            dance.formation,
            _proseRenderer,
            ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins,
            canonicalizeDiscouragedTerms: CanonicalDiscouragedTermsScope.of(
              context,
            ),
          ),
        if (dance != null && dance.mixer) l10n.commonMixer,
        // The toggle announces the state itself, so the row does not repeat it.
        if (performed && !showToggle) l10n.programsPerformed,
      ].join('. ');

      final rowBody = MergeSemantics(
        child: Semantics(
          button: !deleted,
          label: semanticsLabel,
          child: InkWell(
            key: ValueKey('summary-slot-${slot.id}'),
            onTap: deleted
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (routeContext) => DanceDetailScreen(
                        danceId: danceId,
                        onReimport: (detail) =>
                            _beginReimport(routeContext, detail),
                      ),
                    ),
                  ),
            child: ExcludeSemantics(
              child: Container(
                key: accent != null
                    ? ValueKey('summary-slot-${slot.id}-accent')
                    : null,
                decoration: accent != null
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(color: accent, width: 4),
                        ),
                      )
                    : null,
                padding: EdgeInsets.only(
                  left: accent != null ? 8 : 0,
                  top: 8,
                  bottom: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    Icon(
                      deleted
                          ? Icons.report_gmailerrorred_outlined
                          : Icons.music_note_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ?altBadge,
                          Text(title, style: theme.textTheme.bodyLarge),
                          if (secondary.isNotEmpty)
                            Text(
                              secondary,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (performed && !showToggle) ...[
                      Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (!deleted)
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.only(left: indented ? 32 : 0, top: 2, bottom: 2),
        child: showToggle
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: rowBody),
                  _performedToggle(slot, title),
                ],
              )
            : rowBody,
      );
    }

    // Free-text slot (break / waltz / announcement): non-interactive text.
    final text = (slot.text ?? '').trim();
    final displayText = slot.isPurgedDance != false
        ? text
        : _displayProse(text);
    return Padding(
      padding: EdgeInsets.only(left: indented ? 32 : 0, top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          Icon(
            Icons.notes_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?altBadge,
                Text(
                  displayText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (extras.isNotEmpty)
                  Text(
                    extras.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DifficultyLevel? _difficultyLevelFor(Dance? dance) {
    if (dance == null) return null;
    for (final level in _difficultyLevels) {
      if (level.id == dance.difficultyLevelId) return level;
    }
    for (final level in _collectionData?.levels ?? const <DifficultyLevel>[]) {
      if (level.id == dance.difficultyLevelId) return level;
    }
    return DifficultyLevel.knownForId(dance.difficultyLevelId);
  }

  Widget _summaryRow(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
