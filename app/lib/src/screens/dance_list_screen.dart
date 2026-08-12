import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/callersbox_online.dart';
import '../data/collection_filter_scope.dart';
import '../data/collection_tile_fields_scope.dart';
import '../data/collection_refresh_scope.dart';
import '../data/contradb_online.dart';
import '../data/dialect_library_scope.dart';
import '../data/display_defaults.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/online_search_labels.dart';
import '../data/repositories_scope.dart';
import '../data/sort_ignore_articles_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../data/calling_history_caller_filter.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/collection_query.dart';
import '../search/collection_query_labels.dart';
import '../theme/app_spacing.dart';
import '../theme/keyboard_dismiss.dart';
import '../utils/confirm_delete.dart';
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
import '../widgets/dance_list_tile.dart';
import '../widgets/facet_panel.dart';
import '../widgets/online_result_tile.dart';
import '../widgets/skeleton.dart';
import '../screens/custom_fields_screen.dart';
import '../screens/recently_deleted_screen.dart';
import 'app_shell_search_scope.dart';
import 'dance_detail_screen.dart';
import 'dance_editor_screen.dart';
import 'online_import_variation_dialog.dart';

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
/// turns on the "Online search" switch inside the Advanced panel, the search
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

  static const Duration _debounce = Duration(milliseconds: 250);

  final _ftsController = TextEditingController();
  final _facets = FacetSelections();
  final _byPhrase = ByPhraseSelections();
  final _advancedRoot = BuilderGroup();
  bool _advancedEnabled = false;

  CollectionSort _sort = CollectionSort.title;

  /// The sort **direction**, seeded from the current sort key's historical
  /// default (`SearchSort.defaultDirection`) so the list opens exactly as
  /// before; a toggle button lets the user flip it. Reset to the new key's
  /// default whenever the sort key changes.
  SortDirection _sortDir = CollectionSort.title.searchSort.defaultDirection;

  /// Whether the user has explicitly chosen a sort this session. Once set, the
  /// saved default (ROADMAP G.6a) no longer seeds `_sort` — protecting an
  /// in-session choice from a late async read.
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
  bool _started = false;

  /// The app-level collection-refresh notifier (ROADMAP 6.3), if provided.
  /// Re-boots the list when an out-of-tab mutation (e.g. an import commit/undo
  /// from Settings) bumps it. Tracked so listeners are swapped correctly.
  ValueListenable<int>? _collectionRefresh;

  /// The live Collection snapshot (issue #768).
  ///
  /// Supersedes both the imperative `_boot()` reload and the narrower
  /// per-dance-tallies subscription this screen carried before: everything
  /// [CollectionData] is built from is now watched, so a dance, tag,
  /// choreographer, custom-field or program-side write reaches this list
  /// without any mutation site remembering to broadcast.
  ///
  /// There is deliberately no `ProgramsRefreshScope` subscription, and the
  /// `CollectionRefreshScope` one is gone with this change too — either would
  /// re-run the load on top of the stream's own emit, costing two reloads per
  /// write (issue #340). Both scopes remain for the screens not yet converted.
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

  /// The online service for the currently selected [_onlineSource].
  OnlineSearchService get _online =>
      _onlineSource == OnlineSource.contraDb ? _contraDb : _callersBox;

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

    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _boot();
    } else if (trackAllCallersChanged) {
      _boot();
    } else if (dialectChanged || ignoreArticlesChanged || enrichmentChanged) {
      _runSearch();
    }

    // Resolved to BUMP (see [_broadcastCollectionChange]), not to subscribe:
    // this list reads its data from a stream now, so listening here as well
    // would reload it twice per write (issue #340).
    _collectionRefresh = CollectionRefreshScope.maybeOf(context);

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

  /// Broadcasts "dance data changed" after a mutation made from this list, so
  /// the views rendering that dance elsewhere — notably the wide layout's
  /// detail pane, which is keyed on the *selection* and so never rebuilds for
  /// an edit (issue #768, gap 5) — reload too.
  ///
  /// Reloading this list is the broadcast's job, not the caller's: a site that
  /// both broadcasts and re-boots would load twice for one mutation (issue
  /// #340). Falls back to a direct [_boot] in focused tests that mount no
  /// scope.
  ///
  /// The broadcast deliberately does **not** depend on this widget's lifetime:
  /// it bumps the captured notifier rather than resolving one from `context`,
  /// so an undo callback — which by design outlives the snackbar's host — still
  /// refreshes every other view. Only the unscoped fallback needs the widget,
  /// because it reloads *this* screen.
  Future<void> _broadcastCollectionChange() async {
    final revision = _collectionRefresh;
    if (revision is ValueNotifier<int>) {
      revision.value++;
      return;
    }
    if (mounted) await _boot();
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
      _advancedEnabled = false;
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
    _ftsController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final callerFilter = await resolveCallingHistoryCallerFilter(
        _repos.settings,
        trackAllCallers: _trackHistoryForAllCallers,
      );
      if (!mounted) return;
      _watchCollectionData(callerFilter);
    } catch (error) {
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
      onError: (Object error) {
        if (mounted) setState(() => _loadError = error);
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
  /// exception is the last-called sort, whose ORDER BY those very tallies feed.
  void _onCollectionData(CollectionData data) {
    final previous = _data;
    final searchAffected =
        previous == null ||
        !mapEquals(previous.dancesById, data.dancesById) ||
        !listEquals(previous.customFieldDefs, data.customFieldDefs);
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

  /// Seeds `_sort` from the saved default Collection sort order (ROADMAP G.6a),
  /// at most once and only if the user hasn't already chosen a sort this
  /// session. A `null`/invalid stored value leaves the historical default
  /// (`title`) in place. Called before the first search so the list opens in
  /// the default sort; a no-op on subsequent [_boot]s (e.g. a refresh).
  Future<void> _seedDefaultSort() async {
    if (_defaultSortSeeded || _sortUserSet) return;
    _defaultSortSeeded = true;
    // A settings read/decode failure must not fail the whole Collection load:
    // fall back silently to the historical default (`title`).
    Object? stored;
    try {
      stored = await _repos.settings.get(kDefaultCollectionSortKey);
    } catch (_) {
      return;
    }
    if (!mounted || _sortUserSet) return;
    final sort = collectionSortFromName(stored);
    if (sort != null && sort != _sort) {
      setState(() {
        _sort = sort;
        _sortDir = sort.searchSort.defaultDirection;
      });
    }
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
    byPhrase: _byPhrase,
    advancedRoot: _advancedEnabled ? _advancedRoot : null,
  );

  List<CollectionSort> get _availableSorts => [
    if (_isBareFullText) CollectionSort.relevance,
    CollectionSort.title,
    CollectionSort.author,
    CollectionSort.recentlyAdded,
    CollectionSort.lastCalled,
  ];

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
        byPhrase: _byPhrase,
        advancedRoot: _advancedEnabled ? _advancedRoot : null,
      );
      final ids = await _repos.dances.search(
        filter,
        sort: _sort.searchSort,
        direction: _sortDir,
        dialect: _dialect,
        enrichment: _enrichment,
        ignoreLeadingArticles: _sortIgnoreArticles,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [
          for (final id in ids)
            if (data.dancesById[id] case final dance?) data.entryFor(dance),
        ];
        _searching = false;
      });
    } catch (error) {
      if (!mounted || seq != _searchSeq) return;
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
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      _debounceTimer = Timer(_debounce, _runSearch);
    }
    // Reflect relevance availability / clear-button immediately (before the
    // debounce fires).
    setState(() {});
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
    setState(() {
      _onlineEnabled = value;
      _onlineError = null;
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
  /// for title-only sources ([OnlineSource.supportsByPhrase] == false, e.g.
  /// ContraDB), so any residual by-phrase selection can't leak into a ContraDB
  /// query or keep an empty search "active".
  CallersBoxPhraseQuery? _effectivePhrases() =>
      _onlineSource.supportsByPhrase ? _onlinePhrases() : null;

  /// Runs a live search against the active online source for the current query
  /// text and/or by-phrase figures. Guarded by a sequence number so a slow
  /// response can't overwrite a newer query.
  Future<void> _runOnlineSearch() async {
    final title = _ftsController.text.trim();
    final phrases = _effectivePhrases();
    if (title.isEmpty && phrases == null) {
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
      final results = await _online.search(
        OnlineSearchQuery(title: title, phrases: phrases),
      );
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlineResults = results;
        _onlineSearching = false;
      });
    } on UrlFetchException catch (error) {
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlineError = importErrorMessage(l10n, error);
        _onlineResults = const [];
        _onlineSearching = false;
      });
    } catch (_) {
      if (!mounted || seq != _onlineSeq) return;
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

  Future<void> _pushOnlinePreview(OnlineSearchResultRow result) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final sourceLabel = _onlineSource.label;
    // A blocking loader while the tapped dance's JSON is fetched + parsed.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          key: ValueKey('online-preview-loading'),
        ),
      ),
    );
    OnlinePreview preview;
    try {
      preview = await _online.loadPreview(_repos, result);
    } on UrlFetchException catch (error) {
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
      return;
    } catch (_) {
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
    if (imported.danceCount == 1 && danceId != null) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailScreen(danceId: danceId),
        ),
      );
    }
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('online-import-snackbar'),
        content: Text(onlineImportMessage(l10n, imported)),
      ),
    );
  }

  /// Directly imports the previewed online dance into the local collection
  /// (dedup-aware). On success it pops the preview route, returning the outcome
  /// to [_pushOnlinePreview], which lands the user on the persisted dance. An
  /// [_importing] guard blocks a rapid double-tap before the commit resolves.
  ///
  /// When the service detects a confident title+author match with differing
  /// figures, it returns [OnlineImportKind.needsConfirmation] without writing
  /// anything. In that case, this method shows a resolution dialog and retries
  /// the import with the chosen [DedupeResolution] (issue #797).
  ///
  /// When the service detects a confident title+author match with identical
  /// figures from a different source, it returns
  /// [OnlineImportKind.needsConfirmationIdentical]. In that case, this method
  /// shows a cross-source duplicate dialog and retries if the user confirms
  /// (issue #811).
  Future<void> _importOnline(OnlinePreview preview) async {
    if (_importing) return;
    _importing = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      var result = await _online.import(_repos, preview.plan);
      if (result.kind == OnlineImportKind.needsConfirmation) {
        if (!mounted) return;
        final existingId = result.danceId;
        // needsConfirmation requires a candidate id — a null here is a service
        // bug. Assert in debug; silently cancel in release (better than crashing).
        assert(
          existingId != null,
          'needsConfirmation must carry an existing dance id',
        );
        if (existingId == null) return;
        final existingTitle =
            (await _repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportVariationDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return; // user cancelled
        result = await _online.import(
          _repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      } else if (result.kind == OnlineImportKind.needsConfirmationIdentical) {
        if (!mounted) return;
        final existingId = result.danceId;
        // needsConfirmationIdentical requires a candidate id — a null here is a
        // service bug. Assert in debug; silently cancel in release.
        assert(
          existingId != null,
          'needsConfirmationIdentical must carry an existing dance id',
        );
        if (existingId == null) return;
        final existingTitle =
            (await _repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportCrossSourceDuplicateDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return; // user cancelled
        result = await _online.import(
          _repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      }
      if (!mounted) return;
      if (result.kind == OnlineImportKind.created) {
        CollectionRefreshScope.bump(context);
        _boot();
      }
      // Hand the result back to the preview route's awaiter, which navigates to
      // the imported dance and shows the confirmation snackbar.
      if (navigator.canPop()) {
        navigator.pop(result);
      } else {
        messenger.showSnackBar(
          SnackBar(
            key: const ValueKey('online-import-snackbar'),
            content: Text(onlineImportMessage(l10n, result)),
          ),
        );
      }
    } on UrlFetchException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(importErrorMessage(l10n, error))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.onlineImportError)));
    } finally {
      _importing = false;
    }
  }

  void _clearAll() {
    _debounceTimer?.cancel();
    setState(() {
      _ftsController.clear();
      _facets.clear();
      _byPhrase.clear();
      _advancedRoot.children.clear();
      _advancedRoot.kind = GroupKind.all;
      _advancedEnabled = false;
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
      (_advancedEnabled && _advancedRoot.toFilter() != null);

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

  /// Applies a batch tag [mode] to the selected dances. Opens the tag picker,
  /// then for each affected dance persists the new tag set via
  /// [DanceRepository.update], announces the result to AT, and offers Undo.
  Future<void> _batchTag(BatchTagMode mode) async {
    final data = _data;
    if (data == null || _selectedIds.isEmpty) return;

    final selectedIds = Set<String>.of(_selectedIds);
    // Tags currently present on the selected dances (drives the Remove picker).
    final presentTagIds = <String>{
      for (final id in selectedIds)
        if (data.dancesById[id] case final dance?) ...dance.tagIds,
    };

    // Add lists all tags (even unused ones); Remove is narrowed by the dialog
    // to only the tags present on the selection.
    final allTags = await _repos.tags.listAll();
    if (!mounted) return;
    final chosen = await showBatchTagDialog(
      context,
      mode: mode,
      tags: allTags,
      presentTagIds: presentTagIds,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    // Capture prior tag sets so Undo can restore them.
    final priorTags = <String, List<String>>{};
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
      // Skip dances whose tags did not actually change. Because `next` is
      // built append-only (add) or subtract-only (remove) from `current`, an
      // equal length means the set is unchanged.
      if (next.length == current.length) continue;
      priorTags[id] = current.toList();
      await _repos.dances.update(
        dance.copyWith(tagIds: next, updatedAt: DateTime.now().toUtc()),
      );
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

    _exitSelectionMode();
    await _broadcastCollectionChange();
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
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () => _undoBatchTag(priorTags),
    );
  }

  /// Restores the captured [priorTags] for each affected dance (app-side undo;
  /// the repository has no batch-undo primitive).
  Future<void> _undoBatchTag(Map<String, List<String>> priorTags) async {
    for (final entry in priorTags.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(tagIds: entry.value, updatedAt: DateTime.now().toUtc()),
      );
    }
    await _broadcastCollectionChange();
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
    final choice = await showBatchLevelDialog(context);
    if (choice == null || !mounted) return;

    // Capture prior levels so Undo can restore each dance individually (the
    // batch write collapses them to a single target level).
    final priorLevels = <String, DanceLevel?>{};
    for (final id in selectedIds) {
      final dance = await _repos.dances.getById(id);
      if (dance == null) continue;
      priorLevels[id] = dance.level;
    }

    final count = await _repos.dances.setLevelForMany(
      priorLevels.keys,
      level: choice.level,
      clearLevel: choice.clear,
      now: DateTime.now().toUtc(),
    );

    // Narrow the captured priors to only the dances that actually changed, so
    // Undo doesn't rewrite (and re-stamp) untouched dances.
    final target = choice.clear ? null : choice.level;
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
    await _broadcastCollectionChange();
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
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
      onUndo: () => _undoBatchLevel(priorLevels),
    );
  }

  /// Restores the captured [priorLevels] for each affected dance (app-side undo;
  /// the repository has no batch-undo primitive).
  Future<void> _undoBatchLevel(Map<String, DanceLevel?> priorLevels) async {
    for (final entry in priorLevels.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(
          level: entry.value,
          clearLevel: entry.value == null,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    await _broadcastCollectionChange();
  }

  /// Shared tail of the batch handlers: announces [message] to AT, exits
  /// selection mode, reloads, then shows either a plain "no changes" snackbar
  /// (when [count] is 0) or an Undo prompt wired to [onUndo].
  Future<void> _finishBatch({
    required int count,
    required String message,
    required ValueKey<String> snackKey,
    required VoidCallback onUndo,
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
    await _broadcastCollectionChange();
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
    for (final id in selectedIds) {
      final dance = await _repos.dances.getById(id);
      if (dance == null) continue;
      priorRatings[id] = dance.rating;
    }

    final count = await _repos.dances.setRatingForMany(
      priorRatings.keys,
      rating: choice.rating,
      clearRating: choice.clear,
      now: DateTime.now().toUtc(),
    );

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
  Future<void> _undoBatchRating(Map<String, int?> priorRatings) async {
    for (final entry in priorRatings.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(
          rating: entry.value,
          clearRating: entry.value == null,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    await _broadcastCollectionChange();
  }

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
    for (final id in selectedIds) {
      final dance = await _repos.dances.getById(id);
      if (dance == null) continue;
      priorTunes[id] = dance.tunes.toList();
    }

    final count = await _repos.dances.addTunesForMany(
      priorTunes.keys,
      tunes: chosen,
      now: DateTime.now().toUtc(),
    );

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
    for (final id in selectedIds) {
      final dance = await _repos.dances.getById(id);
      if (dance == null) continue;
      priorTunes[id] = dance.tunes.toList();
    }

    final count = await _repos.dances.clearTunesForMany(
      priorTunes.keys,
      now: DateTime.now().toUtc(),
    );

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
  Future<void> _undoBatchTunes(Map<String, List<String>> priorTunes) async {
    for (final entry in priorTunes.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(tunes: entry.value, updatedAt: DateTime.now().toUtc()),
      );
    }
    await _broadcastCollectionChange();
  }

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
    final choice = await showBatchCustomFieldDialog(context, defs: defs);
    if (choice == null || !mounted) return;

    final selectedIds = Set<String>.of(_selectedIds);
    final priorFields = <String, List<CustomFieldValue>>{};
    for (final id in selectedIds) {
      final dance = await _repos.dances.getById(id);
      if (dance == null) continue;
      priorFields[id] = dance.customFields.toList();
    }

    final int count;
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

    // Keep only dances whose value for the chosen key actually changed.
    priorFields.removeWhere((_, prior) {
      final existing = prior
          .where((f) => f.fieldId == choice.def.id)
          .map((f) => f.value)
          .toList();
      if (choice.clear) return existing.isEmpty;
      return existing.length == 1 && existing.first == choice.value;
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
      onUndo: () => _undoBatchCustomField(priorFields),
    );
  }

  /// Restores the captured [priorFields] for each affected dance.
  Future<void> _undoBatchCustomField(
    Map<String, List<CustomFieldValue>> priorFields,
  ) async {
    for (final entry in priorFields.entries) {
      final dance = await _repos.dances.getById(entry.key);
      if (dance == null) continue;
      await _repos.dances.update(
        dance.copyWith(
          customFields: entry.value,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    await _broadcastCollectionChange();
  }

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

  PreferredSizeWidget _buildDefaultAppBar() {
    final l10n = AppLocalizations.of(context);
    final openSearch = AppShellSearchScope.of(context)?.openSearch;
    return AppBar(
      title: Text(l10n.collectionScreenTitle),
      actions: [
        // Phone-only: search lives in the app bar (the bottom-right FAB slot is
        // reserved for the "New dance" FAB). On wide layouts the nav rail owns
        // search, so no scope is present and this action is omitted.
        if (openSearch != null)
          IconButton(
            key: const ValueKey('collection-search'),
            tooltip: l10n.collectionSearchTooltip,
            icon: const Icon(Icons.search),
            onPressed: openSearch,
          ),
        if (_data != null) ...[
          if (widget.onImport != null)
            IconButton(
              key: const ValueKey('import-dances'),
              tooltip: l10n.importDances,
              icon: const Icon(Icons.download_outlined),
              onPressed: widget.onImport,
            ),
          IconButton(
            key: const ValueKey('batch-select'),
            tooltip: l10n.collectionSelectDancesTooltip,
            icon: const Icon(Icons.checklist),
            onPressed: _results.isEmpty ? null : () => _enterSelectionMode(),
          ),
          IconButton(
            key: const ValueKey('manage-custom-fields'),
            tooltip: l10n.collectionManageCustomFieldsTooltip,
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: _openCustomFields,
          ),
          IconButton(
            key: const ValueKey('recently-deleted'),
            tooltip: l10n.collectionRecentlyDeletedTooltip,
            icon: const Icon(Icons.restore_from_trash_outlined),
            onPressed: _openRecentlyDeleted,
          ),
          PopupMenuButton<CollectionSort>(
            tooltip: l10n.collectionSortByTooltip(
              collectionSortLabel(l10n, _sort),
            ),
            initialValue: _sort,
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                _sortUserSet = true;
                _sort = value;
                _sortDir = value.searchSort.defaultDirection;
              });
              _runSearch();
            },
            itemBuilder: (context) => [
              for (final option in _availableSorts)
                PopupMenuItem(
                  value: option,
                  child: Text(collectionSortLabel(l10n, option)),
                ),
            ],
          ),
          _buildGroupByButton(l10n),
          IconButton(
            key: const ValueKey('collection-sort-direction'),
            tooltip: _sortDir == SortDirection.ascending
                ? l10n.collectionSortAscendingTooltip
                : l10n.collectionSortDescendingTooltip,
            icon: Icon(
              _sortDir == SortDirection.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
            ),
            onPressed: () {
              setState(() {
                _sortUserSet = true;
                _sortDir = _sortDir == SortDirection.ascending
                    ? SortDirection.descending
                    : SortDirection.ascending;
              });
              _runSearch();
            },
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
        setState(() => _groupTagId = value == _noGroupSentinel ? null : value);
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
    // The editor bumps CollectionRefreshScope on save, which re-boots this list
    // (and re-derives the author filter), so no explicit reload is needed here
    // — doing both would double-load (issue #340).
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DanceEditorScreen()),
    );
    if (!mounted || id == null) return;
    widget.onNewDance?.call(id);
  }

  Future<void> _openCustomFields() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CustomFieldsScreen()));
    // Reload so newly-created/edited fields show up as facets.
    if (mounted) await _boot();
  }

  Future<void> _openRecentlyDeleted() async {
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
    final copy = await _repos.dances.duplicate(
      id: danceId,
      newId: uuidV4(),
      now: now,
    );
    final newTitle = l10n.commonDuplicateTitleSuffix(copy.title);
    await _repos.dances.update(copy.copyWith(title: newTitle, updatedAt: now));
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
    // can reach the "Online search" toggle (in the Advanced panel) and import
    // their first dance from The Caller's Box — so the empty-collection message
    // now renders inside the results area rather than replacing the whole body.
    final collectionEmpty = data.dancesById.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: TextField(
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
                  ? l10n.onlineSearchFieldHint
                  : l10n.collectionSearchFieldHint,
              prefixIcon: Icon(
                _onlineEnabled ? Icons.cloud_outlined : Icons.search,
              ),
              suffixIcon: _hasActiveQuery
                  ? IconButton(
                      tooltip: l10n.collectionClearSearchTooltip,
                      icon: const Icon(Icons.clear),
                      onPressed: _clearAll,
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: kTextEntryKeyboardDismiss,
            slivers: [
              SliverList(
                delegate: SliverChildListDelegate([
                  // Local facet panels don't apply to online search (and there's
                  // nothing to filter in an empty collection), so they're hidden
                  // in those cases. The Advanced panel stays — it hosts the
                  // "Online search" toggle, which must always be reachable.
                  // Local facet filters can't apply to online results, so the
                  // Filters panel stays local-only. By-phrase maps onto TCB's
                  // own "search by phrase" fields, so it's offered for the
                  // Caller's Box source (even with an empty local collection);
                  // it's hidden for title-only sources (ContraDB).
                  //
                  // The panels suppress their built-in ExpansionTile borders and
                  // rely on explicit dividers interleaved *between* visible
                  // panels only, so a hidden panel (e.g. By-phrase for ContraDB)
                  // never leaves a stray leading rule above the next panel.
                  ..._buildFilterPanels(data, collectionEmpty),
                  if (_onlineEnabled || !collectionEmpty) _buildResultCount(),
                  const Divider(height: 1),
                ]),
              ),
              if (_onlineEnabled)
                _buildOnlineResultsSliver()
              else if (collectionEmpty)
                _buildEmptyCollectionSliver()
              else
                _buildResultsSliver(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCollectionSliver() {
    final l10n = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.collectionEmpty, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the visible filter panels with hairline dividers interleaved only
  /// *between* them. Each panel suppresses its built-in ExpansionTile border
  /// (see [_buildFiltersPanel] etc.), so the first visible panel never carries
  /// a leading rule — even when an earlier panel (e.g. By-phrase for ContraDB)
  /// is hidden.
  List<Widget> _buildFilterPanels(CollectionData data, bool collectionEmpty) {
    final panels = <Widget>[
      if (!_onlineEnabled && !collectionEmpty) _buildFiltersPanel(data),
      if ((_onlineEnabled && _onlineSource.supportsByPhrase) ||
          (!_onlineEnabled && !collectionEmpty))
        _buildByPhrasePanel(data),
      _buildAdvancedPanel(data),
    ];

    final children = <Widget>[];
    for (var i = 0; i < panels.length; i++) {
      if (i > 0) {
        children.add(
          Divider(height: 1, key: ValueKey('filter-panel-divider-$i')),
        );
      }
      children.add(panels[i]);
    }
    return children;
  }

  Widget _buildFiltersPanel(CollectionData data) {
    final l10n = AppLocalizations.of(context);
    final activeCount = _activeFacetCount();
    return ExpansionTile(
      key: const ValueKey('filters-panel'),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(
        activeCount == 0
            ? l10n.collectionFiltersTitle
            : l10n.collectionFiltersActive(activeCount),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      children: [
        FacetPanel(
          facets: _facets,
          forms: data.forms,
          formations: data.formations,
          progressions: data.progressions,
          statuses: data.statuses,
          levels: data.levels,
          hasMixedLevel: data.hasMixedLevel,
          hasMixer: data.hasMixer,
          hasRating: data.hasRating,
          authors: data.authors,
          tags: data.tags,
          citedSources: data.citedSources,
          choiceFields: data.choiceFields,
          booleanFields: data.booleanFields,
          textFields: data.textFields,
          numberFields: data.numberFields,
          onChanged: _onFacetsChanged,
        ),
      ],
    );
  }

  Widget _buildByPhrasePanel(CollectionData data) {
    final l10n = AppLocalizations.of(context);
    final activeCount = _byPhraseActiveCount();
    return ExpansionTile(
      key: const ValueKey('by-phrase-panel'),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.grid_view_outlined),
      title: Text(
        activeCount == 0
            ? l10n.collectionByPhraseTitle
            : l10n.collectionByPhraseActive(activeCount),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      children: [
        ByPhrasePanel(
          selections: _byPhrase,
          taxonomy: data.taxonomy,
          sectionLabels: data.sectionLabels,
          onChanged: _onByPhraseChanged,
        ),
      ],
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
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      key: const ValueKey('advanced-panel'),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(l10n.collectionAdvancedTitle),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      children: [
        SwitchListTile(
          key: const ValueKey('online-search-enable'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.cloud_outlined),
          title: Text(l10n.onlineSearchToggleTitle),
          subtitle: Text(l10n.onlineSearchToggleSubtitle),
          value: _onlineEnabled,
          onChanged: _onOnlineToggled,
        ),
        if (_onlineEnabled)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<OnlineSource>(
                key: const ValueKey('online-source-selector'),
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
          ),
        SwitchListTile(
          key: const ValueKey('advanced-enable'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.collectionUseAdvancedQuery),
          subtitle: Text(l10n.collectionUseAdvancedQuerySubtitle),
          value: _advancedEnabled,
          // Disabled while online search is active — the advanced query is a
          // local-only facet that can't apply to Caller's Box results.
          onChanged: _onlineEnabled
              ? null
              : (value) {
                  setState(() => _advancedEnabled = value);
                  _runSearch();
                },
        ),
        if (_advancedEnabled && !_onlineEnabled)
          AdvancedQueryBuilder(
            root: _advancedRoot,
            taxonomy: data.taxonomy,
            dialect: _dialect,
            sectionLabels: data.sectionLabels,
            onChanged: _onAdvancedChanged,
          ),
      ],
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
          ? l10n.onlineSearchHintByPhrase(_onlineSource.label)
          : l10n.onlineSearchHintTitle(_onlineSource.label);
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
          child: Center(child: Text(l10n.collectionSearchError)),
        ),
      );
    }
    if (_results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(child: Text(l10n.collectionNoResults)),
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
              // The detail screen now broadcasts the undo itself, which
              // re-boots this list through its CollectionRefreshScope
              // subscription — so onRestored is the *fallback* for focused
              // tests that mount no scope, not the primary path. Reloading in
              // both would load twice for one undo (issue #340).
              final deleted = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => DanceDetailScreen(
                    danceId: entry.dance.id,
                    onRestored: () {
                      if (mounted && _collectionRefresh == null) _boot();
                    },
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

  int _activeFacetCount() {
    return _facets.forms.length +
        _facets.formations.length +
        _facets.progressions.length +
        _facets.statuses.length +
        _facets.authorIds.length +
        _facets.tagIds.length +
        _facets.sourceIds.length +
        _facets.choiceValues.values.fold<int>(0, (a, s) => a + s.length) +
        _facets.booleanValues.length +
        _facets.textValues.values.where((s) => s.isEffective).length +
        _facets.numberValues.values.where((s) => s.isEffective).length;
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
