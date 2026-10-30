import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/callersbox_online.dart';
import '../data/collection_facets_scope.dart';
import '../data/collection_filter_scope.dart';
import '../data/collection_tile_fields_scope.dart';
import '../data/default_program_caller_scope.dart';
import '../data/contradb_online.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/related_dance_links.dart';
import '../data/online_search.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/repositories_scope.dart';
import '../data/seed_service.dart' show kBabyRoseSeedDanceId;
import '../data/sort_ignore_articles_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../data/calling_history_caller_filter.dart';
import '../diagnostics/error_log.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/collection_opening_sort.dart';
import '../search/collection_query.dart';
import '../search/collection_query_labels.dart';
import '../search/dance_detail_data.dart';
import '../theme/app_spacing.dart';
import '../theme/destructive_button_style.dart';
import '../theme/keyboard_dismiss.dart';
import '../utils/confirm_delete.dart';
import '../utils/shortcut_platform.dart';
import '../utils/undo_snack_bar.dart';
import '../widgets/add_to_program_sheet.dart';
import '../widgets/advanced_query_builder.dart';
import '../widgets/batch_custom_field_dialog.dart';
import '../widgets/batch_level_dialog.dart';
import '../widgets/batch_rating_dialog.dart';
import '../widgets/batch_tag_dialog.dart';
import '../widgets/batch_tunes_dialog.dart';
import '../widgets/brand_mark.dart';
import '../widgets/by_phrase_panel.dart';
import '../widgets/collection_search_controls.dart';
import '../widgets/dance_list_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/facet_panel.dart';
import '../widgets/load_error_view.dart';
import '../widgets/online_import_dialogs.dart';
import '../widgets/online_import_snack_bar.dart';
import '../widgets/online_result_tile.dart';
import '../widgets/online_search_toggle.dart';
import '../widgets/search_panel_bar.dart';
import '../widgets/skeleton.dart';
import '../sync/sync_scope.dart';
import '../widgets/sync_now_action.dart';
import '../screens/custom_fields_screen.dart';
import '../screens/recently_deleted_screen.dart';
import 'app_shell_search_scope.dart';
import 'dance_detail_screen.dart';
import 'dance_editor_screen.dart';
import 'dance_reimport_flow.dart';

/// Collection screen: browse and search the dance library
/// (`docs/design/ux.md` §1). A unified full-text search bar, a one-tap facet
/// filter panel, and an "Advanced" boolean-tree query builder all compose a
/// single [DanceFilter] that is run against the search core
/// ([DanceRepository.search], `docs/design/search.md`). Results reuse the
/// Phase 3.1 list rendering and open [DanceDetailScreen] on tap.
///
/// [onSelectDance] is an optional callback for split-pane callers (e.g.
/// [CollectionShell]). When provided, tapping a dance tile calls this instead
/// of pushing a [DanceDetailScreen] route, so the parent can display the
/// detail in a side pane. When null (default), the existing push-navigation
/// behavior is preserved.
///
/// [selectedDanceId] highlights the currently selected row in split-pane mode.
///
/// The list keeps itself current from the database (issue #768), so it takes
/// no `refreshTrigger`: a parent has nothing to request that the stream does
/// not already deliver. The parameter was removed rather than left in place,
/// because `_boot` is now idempotent — it would have accepted a parent's
/// reload request and silently done nothing.
///
/// **Caller's Box online search** (`docs/design/callersbox.md`): when the user
/// turns on the "Online search" icon beside the search tools, the search
/// text becomes a live query against The Caller's Box and [OnlineResultTile]
/// rows replace the local results. In split-pane mode the shell passes
/// [onSelectOnlineDance] so a tapped online result previews in the detail pane;
/// when null (narrow mode) the list pushes a preview route itself.
/// [selectedOnlineId] highlights the currently previewed online row.
/// [callersBoxOnline] is the (injectable) orchestration service; tests pass a
/// seam-backed instance so nothing hits the network.
class DanceListScreen extends StatefulWidget {
  const DanceListScreen({
    super.key,
    this.onSelectDance,
    this.onNewDance,
    this.selectedDanceId,
    this.onImport,
    this.onCustomFields,
    this.onRecentlyDeleted,
    this.onSelectOnlineDance,
    this.selectedOnlineId,
    this.callersBoxOnline,
    this.contraDbOnline,
  });

  /// Called with the tapped dance's id when the split-pane shell needs to
  /// control navigation. Null ⇒ use the standard [Navigator.push] route.
  final void Function(String danceId)? onSelectDance;

  /// Called with the id of a newly created dance after a successful save in
  /// split-pane mode. Null ⇒ has no effect (narrow mode or standalone use).
  final void Function(String danceId)? onNewDance;

  /// Id of the currently selected dance for row highlighting in split-pane
  /// mode. Has no effect when [onSelectDance] is null.
  final String? selectedDanceId;

  /// Called when the user taps the app-bar Import action. Null ⇒ the action is
  /// hidden (the list has no way to open import on its own). The owning shell
  /// (e.g. [CollectionShell]) supplies this and decides whether to embed the
  /// import view in a detail pane (wide) or push it as a route (narrow), so the
  /// list itself stays layout-agnostic (mirrors [onSelectDance]).
  final VoidCallback? onImport;

  /// Lets a split-pane owner show custom fields in its detail pane.
  final VoidCallback? onCustomFields;

  /// Lets a split-pane owner show recently deleted dances in its detail pane.
  final VoidCallback? onRecentlyDeleted;

  /// Called with a tapped online result when the split-pane shell owns the
  /// preview pane. Null ⇒ the list pushes its own preview route (narrow mode).
  final void Function(OnlineSearchResultRow result)? onSelectOnlineDance;

  /// Id of the currently previewed online result, for row highlighting in
  /// split-pane mode. Has no effect when [onSelectOnlineDance] is null.
  final String? selectedOnlineId;

  /// The Caller's Box online search + direct-import service. Injected in tests
  /// with a seam-backed instance; defaults to a network-backed [CallersBoxOnline].
  final CallersBoxOnline? callersBoxOnline;

  /// The ContraDB online search + direct-import service. Injected in tests with
  /// a seam-backed instance; defaults to a network-backed [ContraDbOnline].
  final ContraDbOnline? contraDbOnline;

  @override
  State<DanceListScreen> createState() => _DanceListScreenState();
}

/// Actions in the Collection multi-select "more" overflow menu (#423), holding
/// the batch-edit affordances that don't fit as top-level action-bar icons.
enum _BatchMoreAction { setRating, addTunes, clearTunes, editCustomField }

enum _CollectionCompactAction {
  importDances,
  batchSelect,
  manageCustomFields,
  recentlyDeleted,
  sortDirection,
}

/// The optional app-bar glyphs that give way to the ⋮ menu, as the bar narrows.
enum _CollectionBarGlyph { importDances, sort, sortDirection, groupBy }

class _CollectionCompactSortAction {
  const _CollectionCompactSortAction(this.value);

  final CollectionSort value;
}

class _CollectionCompactGroupAction {
  const _CollectionCompactGroupAction(this.value);

  final String value;
}

class _DanceListScreenState extends State<DanceListScreen> {
  /// Active dialect for search canonicalization — read from [ActiveDialectScope]
  /// in [didChangeDependencies] and updated live when the user changes it.
  Dialect _dialect = Dialect.larksRobins;

  /// Always-on search enrichment built from the union of every saved dialect
  /// (presets + custom), so a role/move term configured in *any* saved dialect
  /// resolves regardless of which one is active (mirrors the built-in legacy
  /// synonyms). Rebuilt in [didChangeDependencies] when the library changes.
  SearchEnrichment _enrichment = SearchEnrichment.empty;

  /// The dialect list the current [_enrichment] was built from, used to detect
  /// library changes and avoid rebuilding/re-searching when nothing changed.
  List<Dialect> _enrichmentDialects = const [];

  /// Whether the title sort ignores a leading article — read from
  /// [SortIgnoreArticlesScope] in [didChangeDependencies] and updated live when
  /// the user toggles the General setting.
  bool _sortIgnoreArticles = true;

  /// Whether calling history tracks all callers — read from
  /// [TrackHistoryForAllCallersScope] in [didChangeDependencies] and updated
  /// live when the user toggles the General setting (issue #583). When `false`
  /// and a default caller is configured, the per-dance "called ×N" / last-called
  /// data is scoped to that caller's programs, so a change re-runs [_boot].
  bool _trackHistoryForAllCallers = false;

  /// Whether calling-history filters use performed slots only.
  bool _requirePerformedForHistory = false;

  /// Whether calling-history filters leave out programs with no event date.
  bool _requireEventDateForHistory = false;

  /// The live default caller from [DefaultProgramCallerScope], or `null` when
  /// no scope is wired (then [_boot] reads the setting). While
  /// [_trackHistoryForAllCallers] is off it scopes the per-dance counts, so a
  /// change re-runs [_boot] — after [_callerRefreshDelay], because the
  /// Settings field reports every keystroke and each re-boot is a full
  /// Collection load (PRES-4).
  String? _defaultProgramCaller;
  Timer? _callerRefreshTimer;
  static const Duration _callerRefreshDelay = Duration(milliseconds: 500);

  /// Filter sections hidden in Settings → Defaults (issue #1419), mirrored from
  /// [CollectionFacetsScope] in [didChangeDependencies] so a newly hidden
  /// section's selection can be cleared (see [FacetSelections.clearFacets]).
  Set<String> _hiddenFacets = const {};

  static const Duration _debounce = Duration(milliseconds: 250);

  final _ftsController = TextEditingController();
  FullTextScope _ftsScope = FullTextScope.omni;
  FullTextScope _localFtsScope = FullTextScope.omni;
  final _facets = FacetSelections();
  final _byPhrase = ByPhraseSelections();
  final _advancedRoot = BuilderGroup();

  CollectionSort _sort = CollectionSort.title;

  /// The sort **direction**, seeded from the current sort key's historical
  /// default (`SearchSort.defaultDirection`) so the list opens exactly as
  /// before; a toggle button lets the user flip it. Reset to the new key's
  /// default whenever the sort key changes.
  SortDirection _sortDir = CollectionSort.title.searchSort.defaultDirection;

  /// Whether the user has explicitly chosen a sort this session. Once set, the
  /// saved default (ROADMAP G.6a) no longer seeds `_sort` — protecting an
  /// in-session choice from a late async read. Under a "Last used" default
  /// (issue #895) this guard's *purpose* shifts — it stops the async last-used
  /// read from clobbering a fresher in-session choice — but it does not
  /// disappear; the read is still async either way.
  bool _sortUserSet = false;

  /// Whether the saved-default sort seed has run (it runs at most once, on the
  /// first [_boot]).
  bool _defaultSortSeeded = false;

  /// The tag id the Collection is currently **grouped** by (issue #373), or
  /// `null` for no grouping (the default flat list). Session-only: this is never
  /// persisted, so relaunching the app returns to the ungrouped list. Grouping
  /// is orthogonal to [_sort] — the active sort still orders rows *within* each
  /// section. Only ids drawn from the current tag set ([CollectionData.tags])
  /// are ever honored (an allow-list; the id never reaches SQL — grouping is a
  /// pure app-layer partition of the already-sorted [_results]).
  String? _groupTagId;

  /// Sentinel value for the "No grouping" menu item. A `null`-valued
  /// [PopupMenuItem] is treated as a *cancel* by [PopupMenuButton] (its
  /// `onSelected` never fires), so the clear-grouping entry needs a non-null
  /// value; the empty string can never collide with a real (uuid) tag id.
  static const String _noGroupSentinel = '';

  late CompendiumRepositories _repos;

  /// Whether one-time setup has run. **A contract between two changes that
  /// arrived from opposite directions, and neither states it alone.**
  ///
  /// The subscription is opened exactly once per [State] — issue #768, so that
  /// a rebuild neither drops nor duplicates it. Issue #895 then gave
  /// [CollectionShell] a [GlobalKey] so this State *survives* being reparented
  /// across the 900 px breakpoint (`collection_shell.dart`), which is what
  /// preserves the sort, search text, filters and scroll position through a
  /// rotation.
  ///
  /// Together those mean: **a rotation must not re-open the subscription.** It
  /// does not today, because a reparented Element is moved rather than
  /// destroyed — `deactivate` then `activate`, never `dispose` — so this flag
  /// stays true and the only cancel paths ([dispose] and `_replaceSubscription`,
  /// which immediately re-opens) are unreachable from a breakpoint crossing.
  ///
  /// What would falsify it: moving the subscription to `initState` and dropping
  /// the flag (correct before #895, a leak after it), or overriding
  /// `deactivate` to cancel — which would leave this flag true with no stream,
  /// i.e. a list that silently stops updating after the first rotation. The
  /// same contract is recorded on `programs_list_screen.dart`'s `_started`.
  bool _started = false;

  /// The live Collection snapshot (issue #768).
  ///
  /// Supersedes both the imperative `_boot()` reload and the narrower
  /// per-dance-tallies subscription this screen carried before: everything
  /// [CollectionData] is built from is now watched, so a dance, tag,
  /// choreographer, custom-field or program-side write reaches this list
  /// without any mutation site remembering to broadcast.
  ///
  /// This screen subscribes to no refresh scope: either would re-run the load
  /// on top of the stream's own emit, costing two reloads per write (issue
  /// #340). The database stream is the only refresh path left.
  StreamSubscription<CollectionData>? _dataSub;

  /// The caller filter [_dataSub] was opened with. A change to the "track all
  /// callers" setting (issue #583) changes the query, so it reopens the stream;
  /// anything else must not, or an ordinary rebuild would re-subscribe.
  String? _dataCallerFilter;
  bool _dataSubscribed = false;

  /// The app-level tag-filter coordinator (issue #414). When a tag chip is
  /// tapped (here, on a dance detail, or on a list row), this list applies a
  /// single-tag filter. Tracked so the listener is swapped correctly.
  CollectionFilterController? _filterController;

  /// The seq of the last tag-filter request applied, so a repeat request (even
  /// for the same tag) re-applies exactly once.
  int _lastFilterSeq = 0;

  CollectionData? _data;
  Object? _loadError;

  List<DanceListEntry> _results = const [];
  bool _searching = false;
  Object? _searchError;
  int _searchSeq = 0;

  /// Online search state. Active only while [_onlineEnabled]. Two services are
  /// held so the source selector can switch between them without re-injection;
  /// [_online] resolves the currently selected one.
  late CallersBoxOnline _callersBox;
  late ContraDbOnline _contraDb;
  OnlineSource _onlineSource = OnlineSource.callersBox;
  bool _onlineEnabled = false;
  List<OnlineSearchResultRow> _onlineResults = const [];
  bool _onlineSearching = false;
  String? _onlineError;
  int _onlineSeq = 0;

  /// The online *search* service for the currently selected [_onlineSource].
  /// Importing a previewed result resolves its service with [_serviceFor].
  OnlineSearchService get _online => _serviceFor(_onlineSource);

  /// Resolves the online service for a given [source], so a tapped result / its
  /// preview is loaded and imported through the source it came from.
  OnlineSearchService _serviceFor(OnlineSource source) =>
      source == OnlineSource.contraDb ? _contraDb : _callersBox;

  /// Guards the narrow-mode direct-import commit so a rapid double-tap of the
  /// preview Import button cannot commit the same plan twice.
  bool _importing = false;

  /// Online search runs on a longer debounce than local FTS so a live query
  /// isn't fired against The Caller's Box on every keystroke.
  static const Duration _onlineDebounce = Duration(milliseconds: 500);

  /// Batch multi-select (Collection batch-tag, `docs/design/ux.md` §1).
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the active dialect from the scope (registers rebuild dependency so
    // didChangeDependencies fires again when the dialect changes).
    final newDialect = ActiveDialectScope.of(context);
    final dialectChanged = _started && newDialect != _dialect;
    _dialect = newDialect;

    // Build the always-on enrichment from the union of every saved dialect
    // (presets + custom). Registers a rebuild dependency on the library so a
    // dialect add/edit/delete re-runs the search live.
    final library = DialectLibraryScope.maybeOf(context);
    final newDialects = library?.all ?? const <Dialect>[];
    final dialectsChanged = !listEquals(newDialects, _enrichmentDialects);
    if (dialectsChanged) {
      _enrichmentDialects = newDialects;
      _enrichment = SearchEnrichment.fromDialects(newDialects);
    }
    final enrichmentChanged = _started && dialectsChanged;

    // Read the sort-ignore-articles setting (registers a rebuild dependency so
    // this fires again when the user toggles it).
    final newIgnoreArticles = SortIgnoreArticlesScope.of(context);
    final ignoreArticlesChanged =
        _started && newIgnoreArticles != _sortIgnoreArticles;
    _sortIgnoreArticles = newIgnoreArticles;

    // Read the "track calling history for all callers" setting (issue #583;
    // registers a rebuild dependency). A change alters the per-dance call
    // counts/last-called data themselves, so it needs a full [_boot] reload
    // rather than a re-filter of the already-loaded collection.
    final newTrackAllCallers = TrackHistoryForAllCallersScope.of(context);
    final trackAllCallersChanged =
        _started && newTrackAllCallers != _trackHistoryForAllCallers;
    _trackHistoryForAllCallers = newTrackAllCallers;
    final newDefaultCaller = DefaultProgramCallerScope.maybeOf(context);
    final defaultCallerChanged =
        _started && newDefaultCaller != _defaultProgramCaller;
    _defaultProgramCaller = newDefaultCaller;
    final newRequirePerformed = RequirePerformedForHistoryScope.of(context);
    final requirePerformedChanged =
        _started && newRequirePerformed != _requirePerformedForHistory;
    _requirePerformedForHistory = newRequirePerformed;
    final newRequireEventDate = RequireEventDateForHistoryScope.of(context);
    final requireEventDateChanged =
        _started && newRequireEventDate != _requireEventDateForHistory;
    _requireEventDateForHistory = newRequireEventDate;

    // A section hidden while it holds a selection would keep narrowing the list
    // with no control to clear it, so hiding it clears it (issue #1419). Only
    // *newly* hidden sections are cleared: one that is still visible because a
    // tag chip selected it while hidden must not be wiped by an unrelated
    // change to the hidden set.
    final newHiddenFacets = CollectionFacetsScope.of(context);
    final facetsCleared =
        _started &&
        _facets.clearFacets(newHiddenFacets.difference(_hiddenFacets));
    _hiddenFacets = newHiddenFacets;

    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _boot();
    } else if (trackAllCallersChanged) {
      _boot();
    } else {
      if (defaultCallerChanged && !_trackHistoryForAllCallers) {
        _callerRefreshTimer?.cancel();
        _callerRefreshTimer = Timer(_callerRefreshDelay, _boot);
      }
      if ((requirePerformedChanged || requireEventDateChanged) &&
          !_onlineEnabled &&
          _data != null) {
        _runSearch();
      } else if (dialectChanged ||
          ignoreArticlesChanged ||
          enrichmentChanged ||
          facetsCleared) {
        _runSearch();
      }
    }

    // Subscribe to the app-level tag-filter coordinator (issue #414). A tag tap
    // anywhere publishes a request; this list reacts by applying a single-tag
    // filter. Registers a rebuild dependency; the controller is stable across
    // the app's lifetime, so this attaches once.
    final filter = CollectionFilterScope.maybeOf(context);
    if (!identical(filter, _filterController)) {
      _filterController?.removeListener(_onTagFilterRequested);
      _filterController = filter;
      _filterController?.addListener(_onTagFilterRequested);
      // Apply any request that arrived before we subscribed (e.g. the very
      // first frame), so a tag tap on the initial screen isn't missed.
      _onTagFilterRequested();
    }
  }

  @override
  void didUpdateWidget(DanceListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.callersBoxOnline, oldWidget.callersBoxOnline)) {
      // Sync when the injected service changes, including when it is removed
      // (non-null -> null) so we revert to the default network-backed instance
      // rather than keeping the stale one.
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
    }
    if (!identical(widget.contraDbOnline, oldWidget.contraDbOnline)) {
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
    }
  }

  /// Reacts to an app-level "filter the Collection to this tag" request (issue
  /// #414). Applies a **single-tag** filter that *replaces* the current query:
  /// arriving from a dance detail with unknown prior filter state, a clean
  /// "show every dance with this tag" result is the predictable behavior (the
  /// user can then clear it via the Filters panel). Handled once per request.
  void _onTagFilterRequested() {
    final request = _filterController?.pending;
    if (request == null || request.seq == _lastFilterSeq) return;
    _lastFilterSeq = request.seq;
    if (!mounted) return;
    _applyExternalTagFilter(request.tagId);
  }

  /// Replaces the current search with a single-tag facet filter for [tagId] and
  /// re-runs the search. Clears the text query, other facets, by-phrase and
  /// advanced state, and exits online mode so the (local) filtered list is what
  /// the user lands on.
  void _applyExternalTagFilter(String tagId) {
    _debounceTimer?.cancel();
    setState(() {
      _ftsController.clear();
      _facets.clear();
      _byPhrase.clear();
      _advancedRoot.children.clear();
      _advancedRoot.kind = GroupKind.all;
      _ftsScope = _localFtsScope;
      _onlineEnabled = false;
      // Invalidate any in-flight online search so a late response can't
      // repopulate _onlineResults/_onlineError after we've left online mode.
      _onlineSeq++;
      _onlineResults = const [];
      _onlineError = null;
      _onlineSearching = false;
      _facets.tagIds.add(tagId);
    });
    _runSearch();
  }

  @override
  void dispose() {
    unawaited(_dataSub?.cancel());
    _filterController?.removeListener(_onTagFilterRequested);
    _debounceTimer?.cancel();
    _callerRefreshTimer?.cancel();
    _ftsController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    _callerRefreshTimer?.cancel();
    try {
      final callerFilter = await resolveCallingHistoryCallerFilter(
        _repos.settings,
        trackAllCallers: _trackHistoryForAllCallers,
        defaultCaller: _defaultProgramCaller,
      );
      if (!mounted) return;
      _watchCollectionData(callerFilter);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'dance_list_screen._boot');
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Opens (or reopens) the live Collection subscription for [callerFilter].
  ///
  /// A no-op when one is already open for the same filter, so an ordinary
  /// rebuild does not tear down and re-establish the stream — that would cost a
  /// full reload per rebuild.
  void _watchCollectionData(String? callerFilter) {
    if (_dataSubscribed && callerFilter == _dataCallerFilter) return;
    _dataSubscribed = true;
    _dataCallerFilter = callerFilter;
    unawaited(_dataSub?.cancel());
    _dataSub = CollectionData.watch(_repos, callerFilter: callerFilter).listen(
      _onCollectionData,
      onError: (Object error, StackTrace stackTrace) {
        logCaughtError(
          error,
          stackTrace,
          source: 'dance_list_screen._watchCollectionData',
        );
        if (mounted) setState(() => _loadError = error);
      },
      onDone: () {
        // The source can end without ever emitting — the database closed while
        // this screen was opening. Nothing else moves the screen off its
        // loading state: [_buildBody] renders the skeleton whenever `_data` and
        // `_loadError` are both null, so without this the list spins forever
        // with no throw, no log and no error surface.
        //
        // This screen has no first-value Completer, unlike the two program
        // panes, so there is no future to complete with an error — the guard
        // has to be on the loading STATE rather than on a future. That is
        // precisely why an audit that searched for `Completer` did not find
        // this site: the hazard is "a loading state with no terminal
        // transition when the stream ends", and the Completer is only one way
        // to express it.
        if (mounted && _data == null && _loadError == null) {
          setState(
            () => _loadError = StateError(
              'collection stream closed before its first value',
            ),
          );
        }
      },
    );
  }

  /// Applies a snapshot from [_dataSub].
  ///
  /// The search is re-run only when the incoming snapshot could actually change
  /// its result set or its order. A program-side write — marking a slot
  /// performed, say — changes only the per-dance tallies, and re-running the
  /// FTS query for a badge is the thrash issue #340 records; the rows are
  /// re-derived in memory from the dances already loaded instead. The one
  /// exception is the last-called sort, whose ORDER BY is derived from the same
  /// program rows as those tallies (it runs its own query over them in
  /// `DanceRepository.search`), so a program-side write can reorder it.
  ///
  /// ## What this skip list must be complete with respect to (issue #768)
  ///
  /// Write the **completeness claim**, not just the exceptions — because the
  /// claim is what a later change invalidates, and the code that depends on it
  /// will not look any different afterwards.
  ///
  /// On `main` this optimisation lived on the per-dance-tallies subscription,
  /// where the exception list was *provably* complete: that channel could
  /// deliver only `callCounts` and `lastCalled`, and the one sort those feed
  /// was the one exception listed. Converting to [CollectionData.watch] merged
  /// six channels into one — dances, choreographers, tags, field defs, sources
  /// and tallies — and the optimisation was carried across **with its exception
  /// list intact**. The implementation travelled; the proof did not. A snapshot
  /// can now differ in ways that never previously arrived alone, and the author
  /// rename below is the case that found it.
  ///
  /// So: this list is complete with respect to the **seven tables**
  /// `watchCollectionSources` reads. Widen that set and every exception here
  /// must be re-derived, not merely reviewed.
  ///
  /// ## Why a half-refreshed view is worse than a stale one
  ///
  /// The failure mode to weigh is not "the list goes stale". A stale list looks
  /// *unchanged*, so nothing invites the user to trust it. Getting this wrong
  /// produces a list that **visibly updates while being wrongly ordered** — and
  /// the freshly-correct labels are precisely what make the wrong order
  /// credible. Partial freshness beats uniform staleness at doing damage.
  ///
  /// Hence the test to apply when converting the next screen: when a snapshot
  /// updates one thing derived from a source, does it update **everything**
  /// derived from that same source?
  void _onCollectionData(CollectionData data) {
    final previous = _data;
    final searchAffected =
        previous == null ||
        !mapEquals(previous.dancesById, data.dancesById) ||
        !listEquals(previous.customFieldDefs, data.customFieldDefs) ||
        (_facets.callStatuses.isNotEmpty &&
            (!mapEquals(previous.callCounts, data.callCounts) ||
                previous.callerFilter != data.callerFilter)) ||
        // Both author sorting and author-scoped FTS depend on the display-name
        // map rather than the ids stored on each dance. A rename therefore
        // changes either the order or the result set while every dance row is
        // byte-identical.
        ((!_onlineEnabled &&
                    (_ftsScope == FullTextScope.omni ||
                        _ftsScope == FullTextScope.author)) ||
                _sort == CollectionSort.author) &&
            !mapEquals(previous.choreographerNames, data.choreographerNames);
    setState(() {
      _data = data;
      _loadError = null;
      if (!searchAffected) {
        _results = [for (final e in _results) data.entryFor(e.dance)];
      }
    });
    if (searchAffected || _sort == CollectionSort.lastCalled) {
      unawaited(_afterFirstData());
    }
  }

  /// Seeds the default sort once, then runs the search.
  Future<void> _afterFirstData() async {
    await _seedDefaultSort();
    if (mounted) await _runSearch();
  }

  /// Seeds `_sort` and `_sortDir` from the saved default Collection sort order
  /// (ROADMAP G.6a; extended to a "Last used" mode by issue #895 / ROADMAP
  /// G.6c), at most once and only if the user hasn't already chosen a sort this
  /// session. The direction comes from the last-used keys under "Last used",
  /// otherwise from the default's own direction key (issue #1841), falling back
  /// to the sort's natural direction. A `null`/invalid stored sort leaves the
  /// historical default (`title`, ascending) in place. Called before the first search so
  /// the list opens in the default sort; a no-op on subsequent [_boot]s (e.g.
  /// a refresh).
  Future<void> _seedDefaultSort() async {
    if (_defaultSortSeeded || _sortUserSet) return;
    _defaultSortSeeded = true;
    // A settings read failure must not fail the whole Collection load: the
    // reader returns null and the historical default (title, ascending) stays.
    final opening = await readCollectionOpeningSort(_repos.settings);
    if (opening == null || !mounted || _sortUserSet) return;
    final (:sort, :direction) = opening;

    // Compare the (sort, direction) PAIR, not just the sort key: a key-only
    // comparison skips this `setState` whenever the resolved sort equals the
    // initial `_sort` (title) even when the direction differs — silently
    // dropping a stored non-default direction under "Last used". Traced
    // against issue #895 as `dance_list_screen.dart:589`'s original
    // `sort != _sort` guard, harmless before this change because direction was
    // always *derived* from the key, never read independently.
    if (sort != _sort || direction != _sortDir) {
      setState(() {
        _sort = sort;
        _sortDir = direction;
      });
    }
  }

  /// Persists the Collection list's own last-used sort + direction (issue
  /// #895), read back by [_seedDefaultSort] when the configured default is
  /// "Last used". Fire-and-forget: neither write is on the UI's critical path,
  /// mirroring how every other in-place Settings write in this screen behaves.
  ///
  /// Skips [CollectionSort.relevance]: it is only meaningful for an active
  /// bare-FTS query, never a durable choice, so persisting it would silently
  /// erase whatever concrete sort the user had actually been using before the
  /// query became a bare full-text search.
  void _persistLastUsedSort() {
    if (_sort == CollectionSort.relevance) return;
    unawaited(_repos.settings.set(kLastUsedCollectionSortKey, _sort.name));
    unawaited(
      _repos.settings.set(kLastUsedCollectionSortDirectionKey, _sortDir.name),
    );
  }

  void _retryLoad() {
    setState(() {
      _data = null;
      _loadError = null;
    });
    // Force a fresh subscription: the previous one may have errored, and a
    // no-op reopen would leave the list on its failure state.
    _dataSubscribed = false;
    _boot();
  }

  /// Whether the current query is a bare full-text search (relevance sort is
  /// only meaningful then, per `docs/design/search.md` decision 6).
  bool get _isBareFullText => isBareFullText(
    ftsText: _ftsController.text,
    facets: _facets,
    scope: _ftsScope,
    byPhrase: _byPhrase,
    advancedRoot: _advancedRoot,
  );

  List<CollectionSort> get _availableSorts =>
      availableCollectionSorts(bareFullText: _isBareFullText);

  Future<void> _runSearch() async {
    final data = _data;
    if (data == null) return;

    // Relevance is only valid for a bare full-text search; fall back if the
    // query stopped being one.
    if (_sort == CollectionSort.relevance && !_isBareFullText) {
      _sort = CollectionSort.title;
      _sortDir = CollectionSort.title.searchSort.defaultDirection;
    }

    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final filter = buildCollectionFilter(
        ftsText: _ftsController.text,
        facets: _facets,
        defs: data.customFieldDefs,
        scope: _ftsScope,
        byPhrase: _byPhrase,
        advancedRoot: _advancedRoot,
        callerFilter: data.callerFilter,
        performedOnly: _requirePerformedForHistory,
        requireEventDate: _requireEventDateForHistory,
      );
      final ids = await _repos.dances.search(
        filter,
        sort: _sort.searchSort,
        direction: _sortDir,
        dialect: _dialect,
        enrichment: _enrichment,
        ignoreLeadingArticles: _sortIgnoreArticles,
        // The Last-called sort reads the same history as the count and the
        // Called filter above (FIND-2).
        callerFilter: data.callerFilter,
        performedOnly: _requirePerformedForHistory,
        requireEventDate: _requireEventDateForHistory,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [
          for (final id in ids)
            if (data.dancesById[id] case final dance?) data.entryFor(dance),
        ];
        _searching = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || seq != _searchSeq) return;
      logCaughtError(error, stackTrace, source: 'dance_list_screen._runSearch');
      setState(() {
        _searchError = error;
        // Clear stale results so the live count matches the error state rather
        // than announcing the previous (now incorrect) count.
        _results = const [];
        _searching = false;
      });
    }
  }

  void _onFtsChanged(String _) {
    _debounceTimer?.cancel();
    if (_onlineEnabled) {
      _onlineSeq++;
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      _searchSeq++;
      _debounceTimer = Timer(_debounce, _runSearch);
    }

    // Reflect relevance availability / clear-button immediately (before the
    // debounce fires).
    setState(() {});
  }

  void _onFtsScopeChanged(FullTextScope? scope) {
    if (scope == null || scope == _ftsScope) return;
    _debounceTimer?.cancel();
    if (_onlineEnabled) {
      _onlineSeq++;
    } else {
      _searchSeq++;
    }
    setState(() {
      _ftsScope = scope;
      if (!_onlineEnabled) {
        _localFtsScope = scope;
      }
    });
    unawaited(_onlineEnabled ? _runOnlineSearch() : _runSearch());
  }

  /// Fires the current search immediately (on keyboard "search" / enter). In
  /// online mode this skips the debounce so submitting runs the query now.
  void _onFtsSubmitted(String _) {
    _debounceTimer?.cancel();
    if (_onlineEnabled) {
      _runOnlineSearch();
    } else {
      _runSearch();
    }
  }

  void _onFacetsChanged() {
    setState(() {});
    _runSearch();
  }

  void _onAdvancedChanged() {
    setState(() {});
    _runSearch();
  }

  void _onByPhraseChanged() {
    setState(() {});
    if (_onlineEnabled) {
      _debounceTimer?.cancel();
      _onlineSeq++;
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      _runSearch();
    }
  }

  /// Toggles online search mode. Turning it on runs an immediate search if a
  /// query is present; turning it off clears the online results and restores the
  /// local list.
  void _onOnlineToggled(bool value) {
    _debounceTimer?.cancel();
    _searchSeq++;
    _onlineSeq++;
    setState(() {
      _onlineEnabled = value;
      _onlineError = null;
      if (value) {
        _localFtsScope = _ftsScope;
        _ftsScope = onlineFullTextScope(_ftsScope);
      } else {
        _ftsScope = _localFtsScope;
      }
      if (!value) {
        _onlineResults = const [];
        _onlineSearching = false;
      }
    });
    if (value) {
      if (_ftsController.text.trim().isNotEmpty ||
          _effectivePhrases() != null) {
        _runOnlineSearch();
      }
    } else {
      _runSearch();
    }
  }

  /// Switches the active online source (e.g. via the source selector). Clears
  /// the current source's results/error and re-runs the search against the new
  /// source when a query is present.
  void _onOnlineSourceChanged(OnlineSource source) {
    if (source == _onlineSource) return;
    _debounceTimer?.cancel();
    _onlineSeq++;
    setState(() {
      _onlineSource = source;
      _onlineResults = const [];
      _onlineError = null;
      _onlineSearching = false;
    });
    if (_ftsController.text.trim().isNotEmpty || _effectivePhrases() != null) {
      _runOnlineSearch();
    }
  }

  /// Resolves the current by-phrase selections into a TCB phrase query, or
  /// `null` when there's nothing to send (no data loaded yet, or no figures
  /// selected). Reused by the online search runner and the toggle.
  CallersBoxPhraseQuery? _onlinePhrases() {
    final data = _data;
    if (data == null || _byPhrase.isEmpty) return null;
    final phrases = CallersBoxPhraseQuery.fromSelections(
      _byPhrase,
      data.taxonomy,
    );
    return phrases.isEmpty ? null : phrases;
  }

  /// By-phrase criteria that actually apply to the active online source: `null`
  /// for sources without by-phrase support
  /// ([OnlineSource.supportsByPhrase] == false, e.g.
  /// ContraDB), so any residual by-phrase selection can't leak into a ContraDB
  /// query or keep an empty search "active".
  CallersBoxPhraseQuery? _effectivePhrases() =>
      _onlineSource.supportsByPhrase ? _onlinePhrases() : null;

  /// Runs a live search against the active online source for the current query
  /// text and/or by-phrase figures. Guarded by a sequence number so a slow
  /// response can't overwrite a newer query.
  Future<void> _runOnlineSearch() async {
    final query = OnlineSearchQuery.forScope(
      _ftsController.text,
      _ftsScope,
      phrases: _effectivePhrases(),
    );
    if (query.isEmpty) {
      setState(() {
        _onlineResults = const [];
        _onlineError = null;
        _onlineSearching = false;
      });
      return;
    }
    final seq = ++_onlineSeq;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _onlineSearching = true;
      _onlineError = null;
    });
    try {
      final results = await _online.search(query);
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlineResults = results;
        _onlineSearching = false;
      });
    } on UrlFetchException catch (error, stackTrace) {
      if (!mounted || seq != _onlineSeq) return;
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._runOnlineSearch',
      );
      setState(() {
        _onlineError = importErrorMessage(l10n, error);
        _onlineResults = const [];
        _onlineSearching = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || seq != _onlineSeq) return;
      // Unlike the typed branch above, an arbitrary caught error here is not
      // known to be log-safe (it may originate from an online transport's raw
      // response), so only its shape is recorded (issue #963), mirroring the
      // same CWE-209-motivated caution as `contradb_program_import_screen`'s
      // fetch catch.
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'dance_list_screen._runOnlineSearch',
      );
      setState(() {
        _onlineError = l10n.onlineSearchFailed(_onlineSource.label);
        _onlineResults = const [];
        _onlineSearching = false;
      });
    }
  }

  /// Handles a tap on an online result. In split-pane mode the shell owns the
  /// preview pane ([onSelectOnlineDance]); in narrow mode the list fetches the
  /// dance and pushes a preview route itself.
  void _onOnlineResultTap(OnlineSearchResultRow result) {
    final onSelect = widget.onSelectOnlineDance;
    if (onSelect != null) {
      onSelect(result);
    } else {
      _pushOnlinePreview(result);
    }
  }

  /// Preview fetches that have not finished, by source and dance id.
  ///
  /// A fetch cannot be aborted, so Cancel only stops waiting for it; it keeps
  /// running until it answers or times out. Tapping the same result again in
  /// that window joins the running fetch instead of starting a second one.
  final Map<String, Future<OnlinePreview>> _previewFetches = {};

  Future<OnlinePreview> _previewFetchFor(OnlineSearchResultRow result) {
    final key = '${result.source.name}/${result.id}';
    return _previewFetches[key] ??= _online
        .loadPreview(_repos, result)
        // A block body: `remove` returns this very future, which
        // `whenComplete` would then wait on forever.
        .whenComplete(() {
          _previewFetches.remove(key);
        });
  }

  Future<void> _pushOnlinePreview(OnlineSearchResultRow result) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final sourceLabel = _onlineSource.label;
    // A loader while the tapped dance's JSON is fetched + parsed. It can be
    // dismissed (Cancel, Back, or a tap outside), which abandons the fetch.
    final cancelled = Completer<void>();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => PopScope(
          // Fires the moment the loader is popped (Cancel, Back, barrier), not
          // after its exit animation, so the code below never pops it twice.
          onPopInvokedWithResult: (_, _) {
            if (!cancelled.isCompleted) cancelled.complete();
          },
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      key: ValueKey('online-preview-loading'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      key: const ValueKey('online-preview-cancel'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final fetch = _previewFetchFor(result);
    // `Future.any` leaves the fetch running after a cancel; it cannot be
    // aborted, so its eventual outcome is dropped (type-only log on failure).
    unawaited(
      fetch.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!cancelled.isCompleted) return;
          logCaughtErrorTypeOnly(
            error,
            stackTrace,
            source: 'dance_list_screen._pushOnlinePreview.abandoned',
          );
        },
      ),
    );
    OnlinePreview preview;
    try {
      final raced = await Future.any<OnlinePreview?>([
        fetch,
        cancelled.future.then((_) => null),
      ]);
      if (raced == null || cancelled.isCompleted) return;
      preview = raced;
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._pushOnlinePreview',
      );
      if (cancelled.isCompleted) return;
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
      return;
    } catch (error, stackTrace) {
      // See `_runOnlineSearch` above: an arbitrary online-transport error is
      // not known log-safe, so only its shape is recorded.
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'dance_list_screen._pushOnlinePreview',
      );
      if (cancelled.isCompleted) return;
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.onlineLoadError(sourceLabel))),
      );
      return;
    }

    if (!mounted) return;
    navigator.pop();
    // The preview route pops with the import result once the user taps Import
    // (see [_importOnline]); a plain back gesture pops with null.
    final imported = await navigator.push<OnlineImportResult>(
      MaterialPageRoute<OnlineImportResult>(
        builder: (_) => DanceDetailScreen.preview(
          data: preview.detail,
          onImport: () => _importOnline(preview),
        ),
      ),
    );
    if (!mounted || imported == null) return;
    // Land the user on the now-persisted dance (full collection actions) rather
    // than leaving them to hunt for it in the list. Guarded on a single-dance
    // import (always true for this online preview path) so it can never
    // auto-open for a multi-dance result; an unresolved re-import (no id) just
    // confirms with the snackbar.
    final danceId = imported.danceId;
    Route<void>? landed;
    if (imported.danceCount == 1 && danceId != null) {
      landed = MaterialPageRoute<void>(
        builder: (_) => DanceDetailScreen(
          danceId: danceId,
          onReimport: _beginReimportRoute,
        ),
      );
      navigator.push(landed);
    }
    showOnlineImportSnackBar(
      messenger,
      l10n: l10n,
      result: imported,
      repos: _repos,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      // Undo took the new dance away: leave its page rather than show "not
      // found" where it was. Only while that page is on top: under another
      // route (its editor, say) removing it would strand that route over a
      // dance that no longer exists, so it is left to show "not found".
      onDanceRemoved: () {
        final route = landed;
        if (route != null && route.isCurrent) navigator.removeRoute(route);
      },
    );
  }

  Future<void> _beginReimportRoute(DanceDetailData target) async {
    await DanceReimportCoordinator(
      repos: _repos,
      callersBox: _callersBox,
      contraDb: _contraDb,
    ).open(context, target);
  }

  /// Directly imports the previewed online dance into the local collection
  /// (dedup-aware). On success it pops the preview route, returning the outcome
  /// to [_pushOnlinePreview], which lands the user on the persisted dance. An
  /// [_importing] guard blocks a rapid double-tap before the commit resolves.
  ///
  /// The confirmation outcomes (#797 variation, #811 cross-source duplicate,
  /// #1907 possible match under another title) are resolved by
  /// [resolveAndImportOnline]; a `null` result means the user
  /// cancelled or this screen went away, and nothing more happens here.
  Future<void> _importOnline(OnlinePreview preview) async {
    if (_importing) return;
    _importing = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final service = _serviceFor(preview.result.source);
    try {
      final result = await resolveAndImportOnline(
        context,
        service: service,
        repos: _repos,
        preview: preview,
        l10n: l10n,
      );
      if (result == null) return; // cancelled, or the screen went away
      if (!mounted) return;
      if (result.kind == OnlineImportKind.created) {
        _boot();
      }
      // Hand the result back to the preview route's awaiter, which navigates to
      // the imported dance and shows the confirmation snackbar.
      if (navigator.canPop()) {
        navigator.pop(result);
      } else {
        showOnlineImportSnackBar(
          messenger,
          l10n: l10n,
          result: result,
          repos: _repos,
          accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
        );
      }
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._importOnline',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
    } catch (error, stackTrace) {
      // See `_runOnlineSearch` above: an arbitrary online-transport/import
      // error is not known log-safe, so only its shape is recorded.
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'dance_list_screen._importOnline',
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.onlineImportError)));
    } finally {
      _importing = false;
    }
  }

  void _clearAll() {
    _debounceTimer?.cancel();
    _searchSeq++;
    _onlineSeq++;
    setState(() {
      _ftsController.clear();
      _facets.clear();
      _byPhrase.clear();
      _advancedRoot.children.clear();
      _advancedRoot.kind = GroupKind.all;
      _onlineResults = const [];
      _onlineError = null;
      _onlineSearching = false;
    });
    if (!_onlineEnabled) _runSearch();
  }

  bool get _hasActiveQuery =>
      _ftsController.text.trim().isNotEmpty ||
      !_facets.isEmpty ||
      !_byPhrase.isEmpty ||
      _advancedRoot.toFilter() != null;

  void _enterSelectionMode([String? initialId]) {
    setState(() {
      _selectionMode = true;
      if (initialId != null) _selectedIds.add(initialId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String danceId) {
    setState(() {
      if (!_selectedIds.remove(danceId)) _selectedIds.add(danceId);
    });
  }

  /// Says that a batch write failed (the caller has logged it): selection mode
  /// stays open so the caller can simply try again. Shared by every batch
  /// handler, so none of them fails silently.
  void _reportBatchFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('batch-apply-error-snackbar'),
          content: Text(AppLocalizations.of(context).collectionBatchApplyError),
        ),
      );
  }

  /// Applies a batch tag [mode] to the selected dances.
  Future<void> _batchTag(BatchTagMode mode) =>
      _applyTags(mode, Set<String>.of(_selectedIds));

  /// Applies a tag [mode] to [selectedIds]: the multi-select selection, or the
  /// single row whose ⋮ menu opened it (issue #1416). Opens the tag picker,
  /// then persists the new tag sets and staged tags in one transaction,
  /// announces the result to AT, and offers Undo.
  Future<void> _applyTags(BatchTagMode mode, Set<String> selectedIds) async {
    final data = _data;
    if (data == null || selectedIds.isEmpty) return;

    // Tags currently present on the selected dances (drives the Remove picker).
    final presentTagIds = <String>{
      for (final id in selectedIds)
        if (data.dancesById[id] case final dance?) ...dance.tagIds,
    };

    // Add lists tags used by live dances; Remove is narrowed by the dialog to
    // only the tags present on the selection. Inline creations remain staged
    // until the dialog is confirmed.
    final allTags = await _repos.tags.listReferencedByLiveDances();
    if (!mounted) return;
    final selection = await showBatchTagDialog(
      context,
      mode: mode,
      tags: allTags,
      presentTagIds: presentTagIds,
    );
    if (selection == null || selection.tagIds.isEmpty || !mounted) return;
    final chosen = selection.tagIds;

    // Capture prior tag sets so Undo can restore them.
    final priorTags = <String, List<String>>{};
    final newlyCreatedTagIds = <String>{};
    try {
      await _repos.transaction(() async {
        final pending = <({Dance dance, List<String> next})>[];
        for (final id in selectedIds) {
          final dance = await _repos.dances.getById(id);
          if (dance == null) continue;
          final current = dance.tagIds;
          final List<String> next;
          if (mode == BatchTagMode.add) {
            next = [
              ...current,
              for (final tagId in chosen)
                if (!current.contains(tagId)) tagId,
            ];
          } else {
            next = [
              for (final tagId in current)
                if (!chosen.contains(tagId)) tagId,
            ];
          }
          if (next.length != current.length) {
            pending.add((dance: dance, next: next));
          }
        }
        if (pending.isEmpty) return;

        final tagIds = <String, String>{};
        for (final tag in selection.stagedTags) {
          final existed = await _repos.tags.idByName(
            tag.name,
            includeDeleted: true,
          );
          tagIds[tag.id] = await _repos.tags.upsertStaged(
            tag,
            localUserEdit: true,
          );
          if (existed == null) newlyCreatedTagIds.add(tagIds[tag.id]!);
        }
        for (final (:dance, :next) in pending) {
          priorTags[dance.id] = dance.tagIds.toList();
          final committedTagIds = <String>[];
          final seenTagIds = <String>{};
          for (final id in next) {
            final resolvedId = tagIds[id] ?? id;
            if (seenTagIds.add(resolvedId)) committedTagIds.add(resolvedId);
          }
          await _repos.dances.update(
            dance.copyWith(
              tagIds: committedTagIds,
              updatedAt: DateTime.now().toUtc(),
            ),
            localUserEdit: true,
          );
        }
      });
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'dance_list_screen._applyTags');
      _reportBatchFailure();
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final count = priorTags.length;
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : mode == BatchTagMode.add
        ? l10n.collectionBatchTagged(count)
        : l10n.collectionBatchUntagged(count);
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );

    // A row-menu tag is not in selection mode; leave any selection alone.
    if (_selectionMode) _exitSelectionMode();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (count == 0) {
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('batch-tag-snackbar'),
          content: Text(message),
        ),
      );
      return;
    }
    showUndoSnackBar(
      messenger,
      key: const ValueKey('batch-tag-snackbar'),
      message: message,
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () => _undoBatchTag(priorTags, newlyCreatedTagIds),
    );
  }

  /// Restores the captured [priorTags] for each affected dance (app-side undo;
  /// the repository has no batch-undo primitive). Tags created by this batch
  /// are tombstoned when Undo leaves them unreferenced; adopted rows are kept.
  Future<void> _undoBatchTag(
    Map<String, List<String>> priorTags,
    Set<String> newlyCreatedTagIds,
  ) async {
    await _repos.transaction(() async {
      for (final entry in priorTags.entries) {
        final dance = await _repos.dances.getById(entry.key);
        if (dance == null) continue;
        await _repos.dances.update(
          dance.copyWith(
            tagIds: entry.value,
            updatedAt: DateTime.now().toUtc(),
          ),
          localUserEdit: true,
        );
      }
      for (final id in newlyCreatedTagIds) {
        if (!await _repos.tags.isInUse(id)) {
          await _repos.tags.delete(id);
        }
      }
    });
  }

  /// Sets the difficulty level on the selected dances. Opens the level picker,
  /// persists the choice via the batched, single-transaction
  /// [DanceRepository.setLevelForMany], announces the result to AT, and offers
  /// Undo. Unlike batch tagging (additive), setting a level replaces it, so the
  /// picker is single-choice and includes an explicit "clear" option.
  Future<void> _batchSetLevel() async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final selectedIds = Set<String>.of(_selectedIds);
    final levels = await _repos.difficultyLevels.listAll();
    if (!mounted) return;
    final choice = await showBatchLevelDialog(context, levels: levels);
    if (choice == null || !mounted) return;

    // Capture prior levels so Undo can restore each dance individually (the
    // batch write collapses them to a single target level).
    final priorLevels = <String, String?>{};
    final int count;
    try {
      for (final id in selectedIds) {
        final dance = await _repos.dances.getById(id);
        if (dance == null) continue;
        priorLevels[id] = dance.difficultyLevelId;
      }

      count = await _repos.dances.setLevelForMany(
        priorLevels.keys,
        difficultyLevelId: choice.level?.id,
        clearDifficultyLevel: choice.clear,
        now: DateTime.now().toUtc(),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._batchSetLevel',
      );
      _reportBatchFailure();
      return;
    }

    // Narrow the captured priors to only the dances that actually changed, so
    // Undo doesn't rewrite (and re-stamp) untouched dances.
    final target = choice.clear ? null : choice.level?.id;
    priorLevels.removeWhere((_, prior) => prior == target);

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : choice.clear
        ? l10n.collectionBatchLevelCleared(count)
        : l10n.collectionBatchLevelSet(count);
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );

    _exitSelectionMode();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (count == 0) {
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey('batch-level-snackbar'),
          content: Text(message),
        ),
      );
      return;
    }
    showUndoSnackBar(
      messenger,
      key: const ValueKey('batch-level-snackbar'),
      message: message,
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () => _undoBatchLevel(priorLevels),
    );
  }

  /// Restores the captured [priorLevels] for each affected dance (app-side undo;
  /// the repository has no batch-undo primitive).
  Future<void> _undoBatchLevel(Map<String, String?> priorLevels) =>
      _repos.transaction(() async {
        for (final entry in priorLevels.entries) {
          final dance = await _repos.dances.getById(entry.key);
          if (dance == null) continue;
          await _repos.dances.update(
            dance.copyWith(
              difficultyLevelId: entry.value,
              clearDifficultyLevel: entry.value == null,
              updatedAt: DateTime.now().toUtc(),
            ),
            localUserEdit: true,
          );
        }
      });

  /// Shared tail of the batch handlers: announces [message] to AT, exits
  /// selection mode, then shows either a plain "no changes" snackbar (when
  /// [count] is 0) or an Undo prompt wired to [onUndo].
  Future<void> _finishBatch({
    required int count,
    required String message,
    required ValueKey<String> snackKey,
    required FutureOr<void> Function() onUndo,
  }) async {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
    final l10n = AppLocalizations.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);

    _exitSelectionMode();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (count == 0) {
      messenger.showSnackBar(SnackBar(key: snackKey, content: Text(message)));
      return;
    }
    showUndoSnackBar(
      messenger,
      key: snackKey,
      message: message,
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: accessibleNavigation,
      onUndo: onUndo,
    );
  }

  /// Sets the star rating on the selected dances via the batched,
  /// single-transaction [DanceRepository.setRatingForMany] (parallel to
  /// [_batchSetLevel]). Captures prior per-dance ratings for Undo.
  Future<void> _batchSetRating() async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final selectedIds = Set<String>.of(_selectedIds);
    final choice = await showBatchRatingDialog(context);
    if (choice == null || !mounted) return;

    final priorRatings = <String, int?>{};
    final int count;
    try {
      for (final id in selectedIds) {
        final dance = await _repos.dances.getById(id);
        if (dance == null) continue;
        priorRatings[id] = dance.rating;
      }

      count = await _repos.dances.setRatingForMany(
        priorRatings.keys,
        rating: choice.rating,
        clearRating: choice.clear,
        now: DateTime.now().toUtc(),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._batchSetRating',
      );
      _reportBatchFailure();
      return;
    }

    // Narrow the captured priors to only the dances that actually changed.
    final target = choice.clear ? null : choice.rating;
    priorRatings.removeWhere((_, prior) => prior == target);

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : choice.clear
        ? l10n.collectionBatchRatingCleared(count)
        : l10n.collectionBatchRatingSet(count);
    await _finishBatch(
      count: count,
      message: message,
      snackKey: const ValueKey('batch-rating-snackbar'),
      onUndo: () => _undoBatchRating(priorRatings),
    );
  }

  /// Restores the captured [priorRatings] for each affected dance.
  Future<void> _undoBatchRating(Map<String, int?> priorRatings) =>
      _repos.transaction(() async {
        for (final entry in priorRatings.entries) {
          final dance = await _repos.dances.getById(entry.key);
          if (dance == null) continue;
          await _repos.dances.update(
            dance.copyWith(
              rating: entry.value,
              clearRating: entry.value == null,
              updatedAt: DateTime.now().toUtc(),
            ),
            localUserEdit: true,
          );
        }
      });

  /// Merges tunes into the selected dances (additive union) via the batched,
  /// single-transaction [DanceRepository.addTunesForMany]. Captures prior
  /// per-dance tune lists for Undo.
  Future<void> _batchAddTunes() async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final selectedIds = Set<String>.of(_selectedIds);
    final chosen = await showBatchTunesDialog(context);
    if (chosen == null || chosen.isEmpty || !mounted) return;

    final priorTunes = <String, List<String>>{};
    final int count;
    try {
      for (final id in selectedIds) {
        final dance = await _repos.dances.getById(id);
        if (dance == null) continue;
        // Deliberately not captured for an undecodable list. The snapshot is a
        // `List<String>`, so it would capture `[]` and Undo would write `[]`
        // back — destroying stored text the batch itself skipped. Omitting the
        // entry means Undo never touches that dance, which matches the
        // repository skipping it.
        final priors = switch (dance.tunesSource) {
          DecodedTunes(:final tunes) => tunes.toList(),
          UnreadableTunes() => null,
        };
        if (priors == null) continue;
        priorTunes[id] = priors;
      }

      count = await _repos.dances.addTunesForMany(
        priorTunes.keys,
        tunes: chosen,
        now: DateTime.now().toUtc(),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._batchAddTunes',
      );
      _reportBatchFailure();
      return;
    }

    // Keep only dances that actually gained a tune (union grew the set).
    priorTunes.removeWhere((_, prior) => chosen.every(prior.contains));

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : l10n.collectionBatchTunesAdded(count);
    await _finishBatch(
      count: count,
      message: message,
      snackKey: const ValueKey('batch-tunes-snackbar'),
      onUndo: () => _undoBatchTunes(priorTunes),
    );
  }

  /// Removes all tunes from the selected dances via the batched,
  /// single-transaction [DanceRepository.clearTunesForMany], after a
  /// confirmation prompt (this is a destructive removal). Captures prior
  /// per-dance tune lists for Undo.
  Future<void> _batchClearTunes() async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('batch-clear-tunes-confirm'),
        title: Text(l10n.collectionBatchClearTunesConfirmTitle),
        content: Text(l10n.collectionBatchClearTunesConfirmBody),
        actions: [
          TextButton(
            key: const ValueKey('batch-clear-tunes-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(Theme.of(ctx).colorScheme),
            key: const ValueKey('batch-clear-tunes-confirm-button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.collectionBatchClearTunesConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final selectedIds = Set<String>.of(_selectedIds);
    final priorTunes = <String, List<String>>{};
    final int count;
    try {
      for (final id in selectedIds) {
        final dance = await _repos.dances.getById(id);
        if (dance == null) continue;
        // Deliberately not captured for an undecodable list. The snapshot is a
        // `List<String>`, so it would capture `[]` and Undo would write `[]`
        // back — destroying stored text the batch itself skipped. Omitting the
        // entry means Undo never touches that dance, which matches the
        // repository skipping it.
        final priors = switch (dance.tunesSource) {
          DecodedTunes(:final tunes) => tunes.toList(),
          UnreadableTunes() => null,
        };
        if (priors == null) continue;
        priorTunes[id] = priors;
      }

      count = await _repos.dances.clearTunesForMany(
        priorTunes.keys,
        now: DateTime.now().toUtc(),
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._batchClearTunes',
      );
      _reportBatchFailure();
      return;
    }

    // Keep only dances that actually had tunes to clear.
    priorTunes.removeWhere((_, prior) => prior.isEmpty);

    if (!mounted) return;
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : l10n.collectionBatchTunesCleared(count);
    await _finishBatch(
      count: count,
      message: message,
      snackKey: const ValueKey('batch-tunes-snackbar'),
      onUndo: () => _undoBatchTunes(priorTunes),
    );
  }

  /// Restores the captured [priorTunes] for each affected dance.
  Future<void> _undoBatchTunes(Map<String, List<String>> priorTunes) =>
      _repos.transaction(() async {
        for (final entry in priorTunes.entries) {
          final dance = await _repos.dances.getById(entry.key);
          if (dance == null) continue;
          await _repos.dances.update(
            dance.copyWith(
              tunes: entry.value,
              updatedAt: DateTime.now().toUtc(),
            ),
            localUserEdit: true,
          );
        }
      });

  /// Sets or clears ONE custom field across the selected dances (upsert
  /// per-key) via the batched, single-transaction
  /// [DanceRepository.upsertCustomFieldForMany] /
  /// [DanceRepository.clearCustomFieldForMany]. Captures prior per-dance
  /// custom-field lists for Undo.
  Future<void> _batchCustomField() async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final defs = await _repos.customFieldDefs.listAll();
    if (!mounted) return;
    final choice = await showBatchCustomFieldDialog(
      context,
      defs: defs,
      repos: _repos,
    );
    if (choice == null || !mounted) return;

    final selectedIds = Set<String>.of(_selectedIds);
    // Only the chosen field's entries are captured: Undo puts back that one
    // field, so another field edited in the meantime (by hand, or arriving by
    // sync) is not overwritten with a stale copy of the whole list.
    final priorFields = <String, List<CustomFieldValue>>{};
    final int count;
    try {
      for (final id in selectedIds) {
        final dance = await _repos.dances.getById(id);
        if (dance == null) continue;
        priorFields[id] = [
          for (final f in dance.customFields)
            if (f.fieldId == choice.def.id) f,
        ];
      }

      if (choice.clear) {
        count = await _repos.dances.clearCustomFieldForMany(
          priorFields.keys,
          fieldId: choice.def.id,
          now: DateTime.now().toUtc(),
        );
      } else {
        count = await _repos.dances.upsertCustomFieldForMany(
          priorFields.keys,
          def: choice.def,
          value: choice.value!,
          now: DateTime.now().toUtc(),
        );
      }
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'dance_list_screen._batchCustomField',
      );
      _reportBatchFailure();
      return;
    }

    // Keep only dances whose value for the chosen key actually changed.
    priorFields.removeWhere((_, prior) {
      if (choice.clear) return prior.isEmpty;
      return prior.length == 1 && prior.first.value == choice.value;
    });

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = count == 0
        ? l10n.collectionBatchNoChanges
        : choice.clear
        ? l10n.collectionBatchCustomFieldCleared(count)
        : l10n.collectionBatchCustomFieldSet(count);
    await _finishBatch(
      count: count,
      message: message,
      snackKey: const ValueKey('batch-custom-field-snackbar'),
      onUndo: () => _undoBatchCustomField(choice.def.id, priorFields),
    );
  }

  /// Restores the chosen field's captured entries ([priorFields], keyed by
  /// dance id) on each affected dance, leaving every other field as it is now.
  Future<void> _undoBatchCustomField(
    String fieldId,
    Map<String, List<CustomFieldValue>> priorFields,
  ) => _repos.transaction(() async {
    for (final entry in priorFields.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(
          customFields: [
            for (final f in dance.customFields)
              if (f.fieldId != fieldId) f,
            ...entry.value,
          ],
          updatedAt: DateTime.now().toUtc(),
        ),
        localUserEdit: true,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      body: _buildBody(),
      floatingActionButton: _data == null || _selectionMode
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('new-dance'),
              heroTag: 'new-dance',
              onPressed: _openNewDance,
              icon: const Icon(Icons.add),
              label: Text(l10n.collectionNewDance),
            ),
    );
  }

  /// Width of one app-bar action slot (an [IconButton]'s default hit target).
  static const double _actionSlotWidth = 48;

  PreferredSizeWidget _buildDefaultAppBar() {
    // The bar is sized by its pane, not the window: the wide layout hosts this
    // list in a fixed-width column, so the actions that fit are measured
    // against the width the bar is actually given.
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _buildAppBar(context, constraints.maxWidth),
      ),
    );
  }

  /// How many optional glyphs ([_CollectionBarGlyph]) fit beside the title.
  ///
  /// Search and Sync are not counted as optional (they stay visible, as they
  /// are the only way to reach those actions), but they do spend slots, as does
  /// the ⋮ menu, which is always present.
  Set<_CollectionBarGlyph> _glyphsThatFit(
    BuildContext context,
    AppLocalizations l10n,
    double barWidth, {
    required bool hasSearch,
    required bool hasSync,
    required bool hasTags,
  }) {
    final theme = Theme.of(context);
    final titleStyle =
        AppBarTheme.of(context).titleTextStyle ?? theme.textTheme.titleLarge;
    final titleWidth = (TextPainter(
      text: TextSpan(text: l10n.collectionScreenTitle, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout()).width;
    // NavigationToolbar's 16 dp middle spacing on each side of the title.
    var slots =
        ((barWidth - 32 - titleWidth) / _actionSlotWidth).floor() - 1; // ⋮
    if (hasSearch) slots--;
    if (hasSync) slots--;

    // Highest priority first: what stays on the bar as slots run out. The
    // rest moves into the ⋮ menu.
    final wanted = <_CollectionBarGlyph>[
      if (widget.onImport != null) _CollectionBarGlyph.importDances,
      _CollectionBarGlyph.sort,
      _CollectionBarGlyph.sortDirection,
      if (hasTags) _CollectionBarGlyph.groupBy,
    ];
    return wanted.take(slots < 0 ? 0 : slots).toSet();
  }

  Widget _buildAppBar(BuildContext context, double barWidth) {
    final l10n = AppLocalizations.of(context);
    final openSearch = AppShellSearchScope.of(context)?.openSearch;
    final sync = SyncScope.maybeOf(context);
    final hasTags = _data?.tags.isNotEmpty ?? false;
    final onBar = _glyphsThatFit(
      context,
      l10n,
      barWidth,
      hasSearch: openSearch != null,
      hasSync: sync != null && sync.enabled && sync.paired,
      hasTags: hasTags,
    );
    return AppBar(
      title: Text(l10n.collectionScreenTitle),
      actions: [
        // Search lives in the app bar on narrow layouts (the bottom-right FAB
        // slot is reserved for the "New dance" FAB). On wide layouts the nav
        // rail owns search, so no scope is present and this action is omitted.
        if (openSearch != null)
          IconButton(
            key: const ValueKey('collection-search'),
            tooltip: l10n.collectionSearchTooltip(shortcutPlatform(context)),
            icon: const Icon(Icons.search),
            onPressed: openSearch,
          ),
        // Second entry to Settings ▸ Sync now; renders nothing unless Device
        // Sync is on and paired.
        const SyncNowAction(),
        if (_data != null) ...[
          if (onBar.contains(_CollectionBarGlyph.importDances))
            IconButton(
              key: const ValueKey('import-dances'),
              tooltip: l10n.importDances,
              icon: const Icon(Icons.file_download_outlined),
              onPressed: widget.onImport,
            ),
          if (onBar.contains(_CollectionBarGlyph.sort))
            CollectionSortMenuButton(
              sort: _sort,
              sorts: _availableSorts,
              onSelected: _selectSort,
            ),
          if (onBar.contains(_CollectionBarGlyph.groupBy))
            _buildGroupByButton(l10n),
          if (onBar.contains(_CollectionBarGlyph.sortDirection))
            SortDirectionButton(
              buttonKey: const ValueKey('collection-sort-direction'),
              direction: _sortDir,
              onPressed: _toggleSortDirection,
            ),
          _buildMoreActions(l10n, onBar),
        ],
      ],
    );
  }

  void _selectSort(CollectionSort value) {
    setState(() {
      _sortUserSet = true;
      _sort = value;
      _sortDir = value.searchSort.defaultDirection;
    });
    _persistLastUsedSort();
    _runSearch();
  }

  void _toggleSortDirection() {
    setState(() {
      _sortUserSet = true;
      _sortDir = _sortDir == SortDirection.ascending
          ? SortDirection.descending
          : SortDirection.ascending;
    });
    _persistLastUsedSort();
    _runSearch();
  }

  void _selectGroup(String value) {
    setState(() => _groupTagId = value == _noGroupSentinel ? null : value);
  }

  /// The ⋮ menu: always holds Select dances, Manage custom fields and Recently
  /// deleted, plus whichever of the [_CollectionBarGlyph]s did not fit on the
  /// bar ([onBar] is what did).
  Widget _buildMoreActions(
    AppLocalizations l10n,
    Set<_CollectionBarGlyph> onBar,
  ) {
    final tags = _data?.tags ?? const <Tag>[];
    return PopupMenuButton<Object>(
      key: const ValueKey('collection-more-actions'),
      tooltip: l10n.danceMoreActions,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        if (action is _CollectionCompactSortAction) {
          _selectSort(action.value);
        } else if (action is _CollectionCompactGroupAction) {
          _selectGroup(action.value);
        } else if (action == _CollectionCompactAction.sortDirection) {
          _toggleSortDirection();
        } else if (action == _CollectionCompactAction.importDances) {
          widget.onImport?.call();
        } else if (action == _CollectionCompactAction.batchSelect) {
          if (_results.isNotEmpty) _enterSelectionMode();
        } else if (action == _CollectionCompactAction.manageCustomFields) {
          _openCustomFields();
        } else if (action == _CollectionCompactAction.recentlyDeleted) {
          _openRecentlyDeleted();
        }
      },
      itemBuilder: (context) => [
        if (widget.onImport != null &&
            !onBar.contains(_CollectionBarGlyph.importDances))
          PopupMenuItem<Object>(
            value: _CollectionCompactAction.importDances,
            child: Text(l10n.importDances),
          ),
        PopupMenuItem<Object>(
          key: const ValueKey('batch-select'),
          enabled: _results.isNotEmpty,
          value: _CollectionCompactAction.batchSelect,
          child: Text(l10n.collectionSelectDancesTooltip),
        ),
        PopupMenuItem<Object>(
          key: const ValueKey('manage-custom-fields'),
          value: _CollectionCompactAction.manageCustomFields,
          child: Text(l10n.collectionManageCustomFieldsTooltip),
        ),
        PopupMenuItem<Object>(
          key: const ValueKey('recently-deleted'),
          value: _CollectionCompactAction.recentlyDeleted,
          child: Text(l10n.collectionRecentlyDeletedTooltip),
        ),
        if (!onBar.contains(_CollectionBarGlyph.sort)) ...[
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            enabled: false,
            child: Text(
              l10n.collectionSortByTooltip(collectionSortLabel(l10n, _sort)),
            ),
          ),
          for (final option in _availableSorts)
            PopupMenuItem<Object>(
              value: _CollectionCompactSortAction(option),
              child: Text(collectionSortLabel(l10n, option)),
            ),
        ],
        if (!onBar.contains(_CollectionBarGlyph.sortDirection))
          PopupMenuItem<Object>(
            value: _CollectionCompactAction.sortDirection,
            child: Text(
              _sortDir == SortDirection.ascending
                  ? l10n.collectionSortAscendingTooltip
                  : l10n.collectionSortDescendingTooltip,
            ),
          ),
        if (tags.isNotEmpty &&
            !onBar.contains(_CollectionBarGlyph.groupBy)) ...[
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            enabled: false,
            child: Text(l10n.collectionGroupByHeader),
          ),
          PopupMenuItem<Object>(
            value: const _CollectionCompactGroupAction(_noGroupSentinel),
            child: Text(l10n.collectionGroupByNone),
          ),
          for (final tag in tags)
            PopupMenuItem<Object>(
              value: _CollectionCompactGroupAction(tag.id),
              child: Text(tag.name),
            ),
        ],
      ],
    );
  }

  /// The group-by-category selector: picks a single tag ("category") to group
  /// the list under, or clears grouping. Session-only — the choice is never
  /// persisted. Rendered only when the collection has tags to group by; grouping
  /// is a pure app-layer partition, so selecting a tag just re-renders (no new
  /// search). A stale [_groupTagId] (e.g. its tag was deleted) reads as inactive.
  Widget _buildGroupByButton(AppLocalizations l10n) {
    final data = _data;
    final tags = data?.tags ?? const <Tag>[];
    if (tags.isEmpty) return const SizedBox.shrink();

    final activeTag = _groupTagId == null
        ? null
        : tags.where((t) => t.id == _groupTagId).firstOrNull;
    final isActive = activeTag != null;

    return PopupMenuButton<String>(
      key: const ValueKey('collection-group-by'),
      tooltip: isActive
          ? l10n.collectionGroupByCategoryActiveTooltip(activeTag.name)
          : l10n.collectionGroupByCategoryTooltip,
      initialValue: _groupTagId ?? _noGroupSentinel,
      icon: Icon(isActive ? Icons.category : Icons.category_outlined),
      onSelected: (value) {
        // A null-valued PopupMenuItem is treated as a *cancel* by
        // PopupMenuButton (onSelected never fires), so "No grouping" carries a
        // non-null sentinel that we map back to null here.
        _selectGroup(value);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: _noGroupSentinel,
          child: Text(l10n.collectionGroupByNone),
        ),
        const PopupMenuDivider(),
        // A non-interactive header labelling the tag list below as the set of
        // categories to group by.
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            l10n.collectionGroupByHeader,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final tag in tags)
          PopupMenuItem<String>(value: tag.id, child: Text(tag.name)),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final l10n = AppLocalizations.of(context);
    final count = _selectedIds.length;
    final hasSelection = count > 0;
    return AppBar(
      leading: IconButton(
        key: const ValueKey('batch-exit'),
        tooltip: l10n.collectionExitSelectionTooltip,
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Semantics(
        liveRegion: true,
        child: Text(l10n.collectionSelectedCount(count)),
      ),
      actions: [
        IconButton(
          key: const ValueKey('batch-add-tags'),
          tooltip: l10n.collectionAddTags,
          icon: const Icon(Icons.new_label_outlined),
          onPressed: hasSelection ? () => _batchTag(BatchTagMode.add) : null,
        ),
        IconButton(
          key: const ValueKey('batch-remove-tags'),
          tooltip: l10n.collectionRemoveTags,
          icon: const Icon(Icons.label_off_outlined),
          onPressed: hasSelection ? () => _batchTag(BatchTagMode.remove) : null,
        ),
        IconButton(
          key: const ValueKey('batch-set-level'),
          tooltip: l10n.collectionSetLevel,
          icon: const Icon(Icons.signal_cellular_alt),
          onPressed: hasSelection ? _batchSetLevel : null,
        ),
        PopupMenuButton<_BatchMoreAction>(
          key: const ValueKey('batch-more'),
          enabled: hasSelection,
          tooltip: l10n.collectionBatchMore,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case _BatchMoreAction.setRating:
                _batchSetRating();
              case _BatchMoreAction.addTunes:
                _batchAddTunes();
              case _BatchMoreAction.clearTunes:
                _batchClearTunes();
              case _BatchMoreAction.editCustomField:
                _batchCustomField();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              key: const ValueKey('batch-set-rating'),
              value: _BatchMoreAction.setRating,
              child: Text(l10n.collectionSetRating),
            ),
            PopupMenuItem(
              key: const ValueKey('batch-add-tunes'),
              value: _BatchMoreAction.addTunes,
              child: Text(l10n.collectionAddTunes),
            ),
            PopupMenuItem(
              key: const ValueKey('batch-clear-tunes'),
              value: _BatchMoreAction.clearTunes,
              child: Text(l10n.collectionClearTunes),
            ),
            PopupMenuItem(
              key: const ValueKey('batch-edit-custom-field'),
              value: _BatchMoreAction.editCustomField,
              child: Text(l10n.collectionEditCustomField),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openNewDance() async {
    // No explicit reload is needed here, and the reason is the stream rather
    // than the broadcast: a save writes `dances`, which this list watches, so
    // the row and the derived author filter arrive on their own. The editor
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DanceEditorScreen()),
    );
    if (!mounted || id == null) return;
    widget.onNewDance?.call(id);
  }

  Future<void> _openCustomFields() async {
    final onCustomFields = widget.onCustomFields;
    if (onCustomFields != null) {
      onCustomFields();
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CustomFieldsScreen()));
    // Reload so newly-created/edited fields show up as facets.
    if (mounted) await _boot();
  }

  Future<void> _openRecentlyDeleted() async {
    final onRecentlyDeleted = widget.onRecentlyDeleted;
    if (onRecentlyDeleted != null) {
      onRecentlyDeleted();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecentlyDeletedScreen.dances()),
    );
    // Reload so any restored dances re-appear in the collection.
    if (mounted) await _boot();
  }

  /// Soft-deletes a dance from the collection list and shows an "Undo" snackbar.
  Future<void> _softDeleteFromList(String danceId, String title) async {
    await _repos.dances.softDelete(danceId, at: DateTime.now().toUtc());
    // Remove from local results immediately so the list updates without a full
    // reload (the full _boot() is expensive). On undo, trigger a full reload.
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _results.removeWhere((e) => e.dance.id == danceId));
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      key: const ValueKey('list-deleted-snackbar'),
      message: l10n.commonDeletedSnack(title),
      undoLabel: l10n.commonUndo,
      undoFailedMessage: l10n.commonUndoFailed,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () async {
        await _repos.dances.restore(danceId, at: DateTime.now().toUtc());
        if (mounted) await _boot();
      },
    );
  }

  /// Duplicates a dance from the collection list. Mirrors the detail screen's
  /// Duplicate (appends " (copy)" to the copy's title), then reloads so the
  /// copy appears in the list and confirms with a snackbar.
  Future<void> _duplicateFromList(String danceId) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    final copy = await duplicateDanceWithRelatedLinks(
      _repos,
      id: danceId,
      newId: uuidV4(),
      now: now,
      copyTitle: l10n.commonDuplicateTitleSuffix,
    );
    final newTitle = copy.title;
    if (!mounted) return;
    await _boot();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('list-duplicated-snackbar'),
        content: Text(l10n.collectionDuplicatedSnack(newTitle)),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.collectionLoadError),
            const SizedBox(height: AppSpacing.xs),
            FilledButton(onPressed: _retryLoad, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }

    final data = _data;
    if (data == null) {
      return const SkeletonListView();
    }

    // A brand-new user with no local dances still needs the search UI so they
    // can reach the "Online search" icon (beside the search tools) and import
    // their first dance from The Caller's Box — so the empty-collection message
    // now renders inside the results area rather than replacing the whole body.
    final collectionEmpty = data.dancesById.isEmpty;

    final searchField = TextField(
      key: const ValueKey('collection-search-field'),
      controller: _ftsController,
      onChanged: _onFtsChanged,
      onSubmitted: _onFtsSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: _onlineEnabled
            ? l10n.onlineSearchFieldLabel(_onlineSource.label)
            : l10n.collectionSearchFieldLabel,
        hintText: _onlineEnabled
            ? l10n.collectionOnlineSearchFieldHint
            : l10n.collectionSearchFieldHint,
        // Dense, like Search in beside it, so the two line up in one row.
        isDense: true,
        prefixIcon: Icon(_onlineEnabled ? kOnlineSearchIcon : Icons.search),
        suffixIcon: _hasActiveQuery
            ? IconButton(
                tooltip: l10n.collectionClearSearchTooltip,
                icon: const Icon(Icons.clear),
                onPressed: _clearAll,
              )
            : null,
      ),
    );
    final searchScope = SearchScopeField(
      fieldKey: const ValueKey('collection-search-scope'),
      scope: _ftsScope,
      online: _onlineEnabled,
      onChanged: _onFtsScopeChanged,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          // Search in sits beside the search box, saving a row above the
          // results, whenever the pane is wide enough at the current text size;
          // a narrow pane or large text stacks it above the box as before.
          child: SearchFieldWithScope(
            searchField: searchField,
            scopeField: searchScope,
          ),
        ),
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: kTextEntryKeyboardDismiss,
            slivers: [
              SliverList(
                delegate: SliverChildListDelegate([
                  // Which tools appear in which mode is documented on
                  // [_buildSearchPanels]. By-phrase maps onto TCB's own "search
                  // by phrase" fields, so it's offered for the Caller's Box
                  // source even with an empty local collection; for sources
                  // without by-phrase support (ContraDB) it is greyed out, or
                  // absent when the collection is empty.
                  _buildSearchPanels(data, collectionEmpty),
                  if (_onlineEnabled || !collectionEmpty) _buildResultCount(),
                  const Divider(height: 1),
                ]),
              ),
              if (_onlineEnabled)
                _buildOnlineResultsSliver()
              else if (collectionEmpty)
                _buildEmptyCollectionSliver()
              else ...[
                if (_onlyTheSampleDance(data) && !_hasActiveQuery)
                  _buildImportCardSliver(),
                _buildResultsSliver(),
              ],
              // Lets the last row scroll clear of the "New dance" FAB.
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.fabClearance),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether the first-run sample is the only dance in the Collection. Judged
  /// from the dance's fixed seed id, so no marker is stored: deleting the
  /// sample, or adding any dance of one's own, ends it.
  bool _onlyTheSampleDance(CollectionData data) =>
      data.dancesById.length == 1 &&
      data.dancesById.containsKey(kBabyRoseSeedDanceId);

  /// Import and New dance, the two ways to start filling the Collection; shared
  /// by the empty state and the sample-only card.
  List<Widget> _startActions(AppLocalizations l10n) => [
    if (widget.onImport != null)
      OutlinedButton.icon(
        key: const ValueKey('collection-empty-import'),
        onPressed: widget.onImport,
        icon: const Icon(Icons.file_download_outlined),
        label: Text(l10n.importDances),
      ),
    FilledButton.icon(
      key: const ValueKey('collection-empty-new-dance'),
      onPressed: _openNewDance,
      icon: const Icon(Icons.add),
      label: Text(l10n.collectionNewDance),
    ),
  ];

  Widget _buildEmptyCollectionSliver() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyState(
        key: const ValueKey('collection-empty'),
        icon: BrandMark(
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: l10n.collectionEmptyTitle,
        body: l10n.collectionEmptyBody,
        actions: _startActions(l10n),
      ),
    );
  }

  /// Shown above the list while only the sample dance is present, so a first
  /// launch points at importing rather than leaving the sample to read as the
  /// whole app.
  Widget _buildImportCardSliver() {
    final l10n = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Card(
        key: const ValueKey('collection-import-card'),
        margin: const EdgeInsets.all(AppSpacing.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.collectionImportCardTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.collectionImportCardBody),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _startActions(l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The search tools that apply to the current mode, as one compact row of
  /// toggles ([SearchPanelBar]). Local filters can't apply to online results,
  /// so while online Filters and Advanced stay in the row greyed out (the row
  /// does not jump, and a choice made in them is still shown as in force for
  /// when the user returns); an empty collection has nothing to filter, so
  /// Filters is left out then. By phrase is enabled for local search and for
  /// online sources that support it, and greyed out for those that do not.
  ///
  /// The Online search icon ends the row in both modes: it is how a user
  /// enters and leaves online mode, so it must not depend on the mode. While
  /// online, the source selector sits full-width under the row.
  Widget _buildSearchPanels(CollectionData data, bool collectionEmpty) {
    final l10n = AppLocalizations.of(context);
    final filtersActive = _facets.activeCount;
    final byPhraseActive = _byPhraseActiveCount();
    final panelBar = SearchPanelBar(
      storageId: 'collection',
      trailing: OnlineSearchToggle(
        key: const ValueKey('online-search-enable'),
        enabled: _onlineEnabled,
        onChanged: _onOnlineToggled,
      ),
      panels: [
        if (!collectionEmpty)
          SearchPanelSpec(
            key: const ValueKey('filters-panel'),
            enabled: !_onlineEnabled,
            label: filtersActive == 0
                ? l10n.collectionFiltersTitle
                : l10n.searchToolActiveCount(
                    l10n.collectionFiltersTitle,
                    filtersActive,
                  ),
            semanticsLabel: filtersActive == 0
                ? null
                : l10n.collectionFiltersActive(filtersActive),
            builder: (_) => _buildFiltersPanel(data),
          ),
        if (!collectionEmpty ||
            (_onlineEnabled && _onlineSource.supportsByPhrase))
          SearchPanelSpec(
            key: const ValueKey('by-phrase-panel'),
            enabled: !_onlineEnabled || _onlineSource.supportsByPhrase,
            label: byPhraseActive == 0
                ? l10n.collectionByPhraseTitle
                : l10n.searchToolActiveCount(
                    l10n.collectionByPhraseTitle,
                    byPhraseActive,
                  ),
            semanticsLabel: byPhraseActive == 0
                ? null
                : l10n.collectionByPhraseActive(byPhraseActive),
            builder: (_) => _buildByPhrasePanel(data),
          ),
        SearchPanelSpec(
          key: const ValueKey('advanced-panel'),
          enabled: !_onlineEnabled,
          label: _advancedRoot.toFilter() != null
              ? l10n.collectionAdvancedActive
              : l10n.collectionAdvancedTitle,
          builder: (_) => _buildAdvancedPanel(data),
        ),
      ],
    );
    // The bar is always the Column's first child, so toggling online keeps its
    // state (open tool, scroll and focus inside a panel) instead of rebuilding it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panelBar,
        if (_onlineEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: SegmentedButton<OnlineSource>(
              key: const ValueKey('online-source-selector'),
              // Full width, so the sources read as the row's second line.
              expandedInsets: EdgeInsets.zero,
              segments: [
                for (final source in OnlineSource.values)
                  ButtonSegment<OnlineSource>(
                    value: source,
                    label: Text(source.label),
                  ),
              ],
              selected: {_onlineSource},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _onOnlineSourceChanged(selection.first),
            ),
          ),
      ],
    );
  }

  Widget _buildFiltersPanel(CollectionData data) {
    return FacetPanel(
      facets: _facets,
      forms: data.forms,
      formations: data.formations,
      progressions: data.progressions,
      statuses: data.statuses,
      levels: data.levels,
      hasMixedLevel: data.hasMixedLevel,
      hasMixer: data.hasMixer,
      hasRating: data.hasRating,
      hasCallingHistory: data.callCounts.values.any(
        (counts) =>
            counts.countFor(
              _requirePerformedForHistory,
              requireEventDate: _requireEventDateForHistory,
            ) >
            0,
      ),
      authors: data.authors,
      tags: data.tags,
      citedSources: data.citedSources,
      tunes: data.tunes,
      choiceFields: data.choiceFields,
      booleanFields: data.booleanFields,
      textFields: data.textFields,
      numberFields: data.numberFields,
      onChanged: _onFacetsChanged,
    );
  }

  Widget _buildByPhrasePanel(CollectionData data) {
    return ByPhrasePanel(
      selections: _byPhrase,
      taxonomy: data.taxonomy,
      sectionLabels: data.sectionLabels,
      onChanged: _onByPhraseChanged,
    );
  }

  int _byPhraseActiveCount() {
    var count = 0;
    for (final moves in _byPhrase.match.values) {
      count += moves.length;
    }
    for (final moves in _byPhrase.exclude.values) {
      count += moves.length;
    }
    return count;
  }

  Widget _buildAdvancedPanel(CollectionData data) {
    return AdvancedQueryBuilder(
      root: _advancedRoot,
      taxonomy: data.taxonomy,
      dialect: _dialect,
      sectionLabels: data.sectionLabels,
      tags: data.tags,
      onChanged: _onAdvancedChanged,
    );
  }

  Widget _buildResultCount() {
    final l10n = AppLocalizations.of(context);
    final bool online = _onlineEnabled;
    final int count = online ? _onlineResults.length : _results.length;
    final bool busy = online ? _onlineSearching : _searching;
    final String label = online
        ? l10n.onlineResultCount(count)
        : l10n.collectionDanceCount(count);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (busy) ...[
              const SizedBox(width: AppSpacing.xs),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Results sliver for online mode: a loading placeholder while searching, a
  /// clear inline error on fetch failure, an empty-query hint, a "no matches"
  /// message, or the [OnlineResultTile] rows.
  Widget _buildOnlineResultsSliver() {
    final l10n = AppLocalizations.of(context);
    if (_onlineError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              _onlineError!,
              key: const ValueKey('online-error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_onlineSearching && _onlineResults.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_ftsController.text.trim().isEmpty && _effectivePhrases() == null) {
      final hint = _onlineSource.supportsByPhrase
          ? l10n.collectionOnlineSearchHintByPhrase(_onlineSource.label)
          : l10n.collectionOnlineSearchHintTitle(_onlineSource.label);
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              hint,
              key: const ValueKey('online-empty-query'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_onlineResults.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              l10n.onlineNoResults(_onlineSource.label),
              key: const ValueKey('online-no-results'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: _onlineResults.length,
      itemBuilder: (context, index) {
        final result = _onlineResults[index];
        return OnlineResultTile(
          key: ValueKey('online-result-${result.id}'),
          result: result,
          selected:
              widget.onSelectOnlineDance != null &&
              widget.selectedOnlineId == result.id,
          onTap: () => _onOnlineResultTap(result),
        );
      },
    );
  }

  Widget _buildResultsSliver() {
    final l10n = AppLocalizations.of(context);
    if (_searchError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LoadErrorView(
            message: l10n.collectionSearchError,
            onRetry: _runSearch,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Text(l10n.collectionNoResults, textAlign: TextAlign.center),
              if (_hasActiveQuery) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('collection-no-results-clear'),
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear),
                  label: Text(l10n.collectionClearSearchTooltip),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Grouping (issue #373): when a category tag is active, render the list as
    // two labeled sections — the selected tag's dances, then everyone else —
    // instead of a flat list. Grouping is a pure app-layer partition over the
    // already-sorted [_results], so the active sort still orders rows *within*
    // each section. Selection mode suppresses grouping so the batch flow stays
    // a single flat, uninterrupted list.
    final groupItems = _selectionMode ? null : _buildGroupedItems();
    if (groupItems != null) {
      return SliverList.builder(
        itemCount: groupItems.length,
        itemBuilder: (context, index) {
          final item = groupItems[index];
          return switch (item) {
            _SectionHeaderItem(:final keySuffix, :final label, :final count) =>
              _buildSectionHeader(keySuffix, label, count, l10n),
            _DanceRowItem(:final entry) => _buildDanceRow(entry, l10n),
          };
        },
      );
    }

    // Lazily built so large collections stay virtualized (only visible rows
    // are constructed).
    return SliverList.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildDanceRow(_results[index], l10n),
    );
  }

  /// Partitions [_results] into the two category sections when grouping is
  /// active, or returns `null` when it isn't (so the caller renders the flat
  /// list). Order within each section is preserved from [_results], i.e. the
  /// active sort. A section with no dances is omitted (e.g. every dance carries
  /// the tag → no "Other" section). Returns `null` when [_groupTagId] doesn't
  /// resolve to a current tag (stale selection after a tag delete).
  List<_CollectionListItem>? _buildGroupedItems() {
    final groupTagId = _groupTagId;
    if (groupTagId == null) return null;
    final tags = _data?.tags ?? const <Tag>[];
    final tag = tags.where((t) => t.id == groupTagId).firstOrNull;
    if (tag == null) return null;

    final withTag = <DanceListEntry>[];
    final other = <DanceListEntry>[];
    for (final entry in _results) {
      (entry.dance.tagIds.contains(groupTagId) ? withTag : other).add(entry);
    }

    final l10n = AppLocalizations.of(context);
    final items = <_CollectionListItem>[];
    if (withTag.isNotEmpty) {
      items.add(_SectionHeaderItem('tag', tag.name, withTag.length));
      items.addAll(withTag.map(_DanceRowItem.new));
    }
    if (other.isNotEmpty) {
      items.add(
        _SectionHeaderItem('other', l10n.collectionGroupOther, other.length),
      );
      items.addAll(other.map(_DanceRowItem.new));
    }
    return items;
  }

  /// A sticky-styled section header for the grouped view. Announces its label
  /// and dance count as a single AT node (a11y) and is marked as a heading.
  /// [keySuffix] gives each header a stable, collision-free widget key even if a
  /// user's tag happens to be named the same as the "Other" section label.
  Widget _buildSectionHeader(
    String keySuffix,
    String label,
    int count,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      container: true,
      label: l10n.collectionGroupSectionSemantics(label, count),
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('group-header-$keySuffix'),
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a single dance row (tile + swipe-to-delete affordance), shared by
  /// the flat and grouped list paths so row interaction stays identical
  /// everywhere (issue #373: tap → detail → Perform; long-press → multi-select).
  Widget _buildDanceRow(DanceListEntry entry, AppLocalizations l10n) {
    final tile = DanceListTile(
      entry: entry,
      visibleFields: CollectionTileFieldsScope.of(context),
      // Row action menu (⋮): non-swipe access to the row actions for
      // mouse/keyboard/AT users. Delete routes through the identical
      // confirm + soft-delete + undo flow as the Dismissible swipe below.
      onDelete: () async {
        if (await confirmDeleteIfEnabled(
          context,
          itemLabel: entry.dance.title,
        )) {
          await _softDeleteFromList(entry.dance.id, entry.dance.title);
        }
      },
      onDuplicate: () => _duplicateFromList(entry.dance.id),
      onAddTags: () => _applyTags(BatchTagMode.add, {entry.dance.id}),
      onTagTap: _applyExternalTagFilter,
      // No reload when the sheet closes: the sheet's write goes to
      // `program_slots`, which the live tallies subscription watches, so the
      // "called ×N" badge updates itself (issue #768, gap 2 — this used to
      // depend on a broadcast reaching a mounted scope).
      onAddToProgram: () => showAddToProgramSheet(
        context,
        repositories: _repos,
        danceId: entry.dance.id,
        danceTitle: entry.dance.title,
      ),
      selectionMode: _selectionMode,
      selectedForBatch: _selectedIds.contains(entry.dance.id),
      onLongPress: _selectionMode
          ? null
          : () => _enterSelectionMode(entry.dance.id),
      // In selection mode a tap toggles the row's checkbox. Highlight
      // reflects batch selection (paired with the checkbox, never color
      // alone); outside selection mode it reflects the split-pane
      // selection as before.
      selected: _selectionMode
          ? _selectedIds.contains(entry.dance.id)
          : (widget.onSelectDance != null &&
                widget.selectedDanceId == entry.dance.id),
      onTap: _selectionMode
          ? () => _toggleSelected(entry.dance.id)
          : widget.onSelectDance != null
          ? () => widget.onSelectDance!(entry.dance.id)
          : () async {
              // DanceDetailScreen pops with true when a dance is deleted
              // so the Collection can reload and remove the stale row.
              // The detail screen broadcasts the undo itself — but that
              final deleted = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => DanceDetailScreen(
                    danceId: entry.dance.id,
                    onReimport: _beginReimportRoute,
                  ),
                ),
              );
              if (mounted && deleted == true) await _boot();
            },
    );
    // Swipe-to-delete is disabled while selecting to avoid gesture
    // conflicts with tap-to-toggle.
    if (_selectionMode) {
      return KeyedSubtree(key: ValueKey('row-${entry.dance.id}'), child: tile);
    }
    // Swipe left to reveal a Delete button (issue #352). Tapping the
    // revealed Delete button is the confirmation — a swipe alone never
    // deletes. The tap routes into the same soft-delete + Undo flow as the
    // ⋮ menu; there is no extra dialog on this path (the reveal + tap is
    // the safeguard). The "Confirm before delete" setting continues to gate
    // only the ⋮ overflow-menu Delete above.
    return Slidable(
      key: ValueKey('slidable-${entry.dance.id}'),
      groupTag: 'dance-list',
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            key: ValueKey('slide-delete-${entry.dance.id}'),
            onPressed: (_) =>
                _softDeleteFromList(entry.dance.id, entry.dance.title),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            icon: Icons.delete_outline,
            label: l10n.commonDelete,
          ),
        ],
      ),
      child: tile,
    );
  }
}

/// An item in the grouped Collection list: either a section header or a dance
/// row. Used only when a category grouping is active (issue #373).
sealed class _CollectionListItem {
  const _CollectionListItem();
}

class _SectionHeaderItem extends _CollectionListItem {
  const _SectionHeaderItem(this.keySuffix, this.label, this.count);

  /// Stable, collision-free key part ('tag' or 'other'), independent of the
  /// display [label] (which could clash — e.g. a tag literally named "Other").
  final String keySuffix;
  final String label;
  final int count;
}

class _DanceRowItem extends _CollectionListItem {
  const _DanceRowItem(this.entry);
  final DanceListEntry entry;
}
