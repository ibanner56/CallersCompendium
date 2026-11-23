import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../data/callersbox_online.dart';
import '../data/collection_facets_scope.dart';
import '../data/collection_tile_fields_scope.dart';
import '../data/contradb_online.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_paging.dart';
import '../data/online_search.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/calling_history_tracking_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/repositories_scope.dart';
import '../data/sort_ignore_articles_scope.dart';
import '../data/matrix_collision_mode_scope.dart';
import '../data/program_matrix_column_config_scope.dart';
import '../data/suggestions_scope.dart';
import '../data/user_figures_scope.dart';
import '../diagnostics/error_log.dart';
import '../models/dance_list_entry.dart';
import '../search/called_venue_choices.dart';
import '../search/collection_data.dart';
import '../search/collection_opening_sort.dart';
import '../theme/app_spacing.dart';
import '../utils/slot_dance_title.dart';
import 'advanced_query_builder.dart';
import 'by_phrase_panel.dart';
import 'collection_search_controls.dart';
import 'dance_list_tile.dart';
import 'facet_panel.dart';
import 'online_import_dialogs.dart';
import 'online_more_footer.dart';
import 'online_result_count.dart';
import 'online_result_tile.dart';
import 'online_search_toggle.dart';
import 'picker_suggestions.dart';
import 'preview_hold_listener.dart';
import 'search_panel_bar.dart';

/// A reusable dance picker that reuses the Collection search stack (full-text
/// search with **Search in** + [FacetPanel] + [ByPhrasePanel] +
/// [AdvancedQueryBuilder] + [DanceRepository.search] with the Collection's
/// sorts) so the Programs builder can find and add dances with the same
/// figure-aware filtering as the Collection screen (`docs/design/ux.md` §4).
/// Rows show the fields chosen in Settings ▸ Defaults ▸ Collection card fields,
/// and online search takes the same Search in choices as the Collection's
/// (FIND-7, PRES-15).
///
/// The sort is the picker's own: it opens in the Collection's opening sort
/// ([readCollectionOpeningSort]) and a change lasts as long as this picker,
/// never written back to Settings.
///
/// With Settings ▸ Experimental ▸ Suggestions on and a [programContext] that
/// carries a position, the Sort menu also offers **Suggested** (#2343): the
/// current results, ranked off the UI thread for that position (the end of
/// the program, the place an add before or after a slot lands, or the slot
/// **Replace…** fills, #2344), each with a reason line and a **Why?**
/// action. The picker never
/// opens in it, and ranking only reorders: until it finishes the results show
/// in the plain order, and a tap adds a dance either way.
///
/// Unlike [DanceListScreen] this is a plain embeddable widget (no [Scaffold]/
/// app bar): it renders inline as the builder's right pane on wide layouts, or
/// inside a modal bottom sheet on narrow layouts. Tapping a result row calls
/// [onAddDance] with the dance id (keyboard-accessible add affordance).
class CollectionPicker extends StatefulWidget {
  const CollectionPicker({
    super.key,
    required this.data,
    required this.dialect,
    required this.enrichment,
    required this.onAddDance,
    this.addedDanceCounts = const {},
    this.scrollController,
    this.rowAction = PickerRowAction.add,
    this.enableOnlineSearch = false,
    this.callersBoxOnline,
    this.contraDbOnline,
    this.onDanceImported,
    this.onImportingChanged,
    this.danceOverrides = const {},
    this.choreographerNamesOverride = const {},
    this.onPreviewDanceStarted,
    this.onPreviewDanceEnded,
    this.onViewDanceDetails,
    this.onPreviewOnlineStarted,
    this.onPreviewOnlineEnded,
    this.onViewOnlineDetails,
    this.programContext,
    this.rankSuggestions,
    this.clock = const SearchClock(),
    this.panelState,
  });

  /// Preloaded collection vocabulary/dances (loaded once by the builder and
  /// shared, so the picker doesn't re-query on every open).
  final CollectionData data;

  /// Active dialect for search canonicalization.
  final Dialect dialect;

  /// Always-on search enrichment built by the parent from the union of every
  /// saved dialect (presets + custom), so a role/move term configured in *any*
  /// saved dialect resolves regardless of which one is active — matching the
  /// main Collection search. Pass [SearchEnrichment.empty] for no enrichment.
  final SearchEnrichment enrichment;

  /// Called with the tapped dance's id to add it to the program.
  final void Function(String danceId) onAddDance;

  /// How many times each dance already appears in the program being built,
  /// keyed by dance id and omitting dances that do not appear at all.
  ///
  /// Empty by default so hosts with no program context (e.g. Perform's insert
  /// sheet) need not supply it.
  final Map<String, int> addedDanceCounts;

  /// Optional controller for the results scroll view. When the picker is hosted
  /// in a [DraggableScrollableSheet], pass its controller so sheet dragging and
  /// list scrolling coordinate correctly.
  final ScrollController? scrollController;

  /// What tapping a row does, purely for the row's tooltip/semantic label/icon
  /// (issue #964). [onAddDance] fires identically either way — this only
  /// changes what the row *says* it does, so a host whose tap target replaces
  /// rather than adds a slot's dance doesn't mislabel the action for assistive
  /// technology (WCAG 4.1.2). Defaults to [PickerRowAction.add], matching every
  /// existing consumer.
  final PickerRowAction rowAction;

  /// Whether the search row offers the Online search icon, the Collection's
  /// online search mode.
  ///
  /// Hosts opt in because an online result imports before [onAddDance] runs,
  /// unlike a local result which is already persisted.
  final bool enableOnlineSearch;

  /// Online services used when [enableOnlineSearch] is true. They are optional
  /// test seams; the state creates the normal services when omitted.
  final OnlineSearchService? callersBoxOnline;
  final OnlineSearchService? contraDbOnline;

  /// Called after an online dance has been persisted and before [onAddDance].
  ///
  /// This also runs when the online service resolves the selection to an
  /// existing collection dance without creating a new record.
  final Future<void> Function(String danceId)? onDanceImported;

  /// Notifies hosts while an online import is in flight so they can prevent
  /// dismissing or navigating away before the dance is added to the program.
  ///
  /// [owner] is stable for this picker instance. Hosts must track owners
  /// independently: a replaced picker can finish after its replacement starts.
  final void Function(Object owner, bool active)? onImportingChanged;

  /// Temporary dance records the host has written but whose debounced
  /// [CollectionData] snapshot has not yet observed.
  final Map<String, Dance> danceOverrides;

  /// Names for authors referenced by [danceOverrides] while the collection
  /// snapshot has not yet observed those choreographers.
  final Map<String, String> choreographerNamesOverride;

  /// Optional Program-only lifecycle for a held saved-dance preview.
  final void Function(String danceId)? onPreviewDanceStarted;
  final void Function(String danceId)? onPreviewDanceEnded;

  /// Opens a persistent saved-dance preview for keyboard and AT users.
  final void Function(String danceId)? onViewDanceDetails;

  /// Optional Program-only lifecycle for a held online-dance preview.
  final void Function(OnlineSearchResultRow result)? onPreviewOnlineStarted;
  final void Function(OnlineSearchResultRow result)? onPreviewOnlineEnded;

  /// Opens a persistent online-dance preview for keyboard and AT users.
  final void Function(OnlineSearchResultRow result)? onViewOnlineDetails;

  /// The program this picker adds to (history-filters Q3), or null for a
  /// host with none (Perform, a template). Its id keeps the program's own
  /// slots out of every calling-history filter here (N1-6), and its position,
  /// when set, makes Suggested available and is what Suggested ranks for.
  final PickerProgramContext? programContext;

  /// Ranks for Suggested. A test seam: when null, as in the app, the picker
  /// ranks on a [SuggestionWorker] of its own, which keeps the candidates it
  /// was sent so a re-rank after an add sends only the program and ids.
  final SuggestionRanker? rankSuggestions;

  /// Where "today" comes from, for the venue window. A test seam.
  final SearchClock clock;

  /// A search for the picker to show: its text, **Search in**, every filter,
  /// the By phrase rows, the Advanced tree and the sort with its direction,
  /// exactly ([CollectionPanelState]), in place of whatever it shows.
  ///
  /// Applied **once**: when the picker is built with it, or when a rebuild
  /// passes a request it has not applied yet. A request is marked applied by
  /// the first picker to take it ([CollectionPanelRequest.applied]), so a
  /// rebuild of the same picker keeps what the user has since changed, and a
  /// picker built again with the same request — remounted by a narrow/wide
  /// layout change, a sheet opened again — is a new picker that starts blank,
  /// as it would without a request: it does not put the search back. To show
  /// the search in a new picker, pass a new request.
  ///
  /// The owner must therefore **hold the request in a field** and pass that
  /// same object on every build. A request created inside `build()` is a new,
  /// unapplied one on every rebuild, and each would put the search back over
  /// the user's edits (a program editor rebuilds its picker on every change
  /// to the program).
  final CollectionPanelRequest? panelState;

  @override
  State<CollectionPicker> createState() => _CollectionPickerState();
}

/// A one-shot request to show [state] in a [CollectionPicker]; see
/// [CollectionPicker.panelState].
///
/// The picker takes [state]'s objects as its own and edits them from then on,
/// so a request is not reusable, and the owner should not keep editing
/// [state] after passing it.
class CollectionPanelRequest {
  CollectionPanelRequest(this.state);

  final CollectionPanelState state;

  bool _applied = false;

  /// Whether a picker has applied this request.
  bool get applied => _applied;
}

/// What a [CollectionPicker] row's tap target does, driving its tooltip,
/// semantic label and icon (issue #964). Never changes [CollectionPicker]'s
/// behaviour — [CollectionPicker.onAddDance] fires the same way regardless.
enum PickerRowAction { add, replace }

class _CollectionPickerState extends State<CollectionPicker> {
  static const Duration _debounce = Duration(milliseconds: 250);

  /// How long a row's add affordance shows a check before returning to a plus.
  /// Long enough to register, short enough not to obstruct a second add.
  static const Duration _addConfirmation = Duration(milliseconds: 1200);

  final _ftsController = TextEditingController();
  FullTextScope _ftsScope = FullTextScope.omni;

  /// The local Search in choice, restored when online search is turned off
  /// (online search maps All fields to Title).
  FullTextScope _localFtsScope = FullTextScope.omni;
  // Replaced, not edited, when a panel state is applied ([_applyPanelState]).
  var _facets = FacetSelections();
  var _byPhrase = ByPhraseSelections();
  var _advancedRoot = BuilderGroup();

  /// Whether the panel state last applied came from a saved search.
  bool _panelFromSavedSearch = false;

  CollectionSort _sort = CollectionSort.title;
  SortDirection _sortDir = CollectionSort.title.searchSort.defaultDirection;

  /// Whether the user picked a sort or direction in this picker, or a panel
  /// state set one, so the async opening-sort read cannot overwrite it.
  bool _sortUserSet = false;

  late OnlineSearchService _callersBox;
  late OnlineSearchService _contraDb;
  OnlineSource _onlineSource = OnlineSource.callersBox;
  bool _onlineEnabled = false;
  List<OnlineSearchResultRow> _onlineResults = const [];

  // Paging through a source that pages (ContraDB). `_onlineQuery` is the
  // query behind `_onlineResults`; `_onlinePagesLoaded` how many pages of it
  // are in; `_onlinePagingSeq` the `_onlineSeq` they belong to, so a page for a
  // search that has since been replaced is dropped.
  OnlineSearchQuery? _onlineQuery;
  int _onlinePagesLoaded = 1;
  int _onlinePagingSeq = -1;
  bool _onlineHasMore = false;
  bool _onlineLoadingMore = false;
  bool _onlineMoreFailed = false;
  bool _onlineSearching = false;
  String? _onlineError;
  String? _onlineImportError;
  int _onlineSeq = 0;
  bool _onlineImporting = false;
  final Set<({OnlineSource source, String id})> _onlineAddedIds = {};
  final Map<String, Dance> _importedDances = {};
  final Map<String, Choreographer> _importedChoreographers = {};
  final Object _importActivityOwner = Object();

  static const Duration _onlineDebounce = Duration(milliseconds: 500);

  /// Dance ids whose row is currently showing its post-add check, each mapped
  /// to the timer that will clear it.
  final Map<String, Timer> _confirmTimers = {};

  late CompendiumRepositories _repos;
  bool _started = false;
  bool _requirePerformedForHistory = false;
  CallingHistoryTracking _tracking = CallingHistoryTracking.defaults;
  bool _requireEventDateForHistory = false;

  /// Filter sections hidden in Settings → Defaults (issue #1419), mirrored from
  /// [CollectionFacetsScope] so a newly hidden section's selection is cleared.
  Set<String> _hiddenFacets = const {};
  bool _ignoreLeadingArticles = true;

  List<DanceListEntry> _results = const [];

  // Suggested (#2343). [_suggested] is the chosen order; [_sort] and
  // [_sortDir] stay the plain order underneath it, which the search runs in
  // and which shows until [_ranking] is ready. [_rankedFor] is the result
  // list [_ranking] orders and [_rankedAt] the position it ranks for: a new
  // search, or a new position (#2344), shows plain again until re-ranked, so
  // a ranking for one place never shows for another.
  bool _suggested = false;
  SuggestionRanking? _ranking;
  Map<String, RankedSuggestion> _rankById = const {};
  List<DanceListEntry>? _rankedFor;
  SuggestionPosition? _rankedAt;
  bool _rankPending = false;
  // The last ranking failed: the plain order shows, with a notice.
  bool _rankFailed = false;
  int _rankSeq = 0;
  SuggestionWorker? _worker;
  bool _suggestionsEnabled = false;
  SuggestionSettingsRead _suggestionSettings = (
    settings: SuggestionSettings.defaults,
    isNewer: false,
  );
  bool _exactBeatCollision = true;
  MatrixColumnConfig _matrixConfig = MatrixColumnConfig.empty;
  UserFigureCatalog _userFigures = UserFigureCatalog.empty;

  /// True from the start: the first search waits for the opening-sort read.
  bool _searching = true;
  Object? _searchError;
  int _searchSeq = 0;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Before the first search: the opening-sort read that runs it leaves a
    // sort set here alone (`_sortUserSet`).
    _applyPanelState(widget.panelState);
  }

  /// Shows [request]'s state, if no picker has applied it yet; returns whether
  /// it did. Every part is replaced, the sort included, never only the parts
  /// [_clearAll] resets.
  ///
  /// The order matters while online search is on: online is turned off
  /// **first**, which puts any tag rows a ContraDB search took out back into
  /// the tree they came from — the old one — then those taken rows are
  /// forgotten, and only then is the tree replaced, so none of them lands in
  /// the new one. Online is left because an online source cannot search most
  /// of what a panel state holds.
  ///
  /// Sets state directly: the caller is `initState` or `didUpdateWidget`,
  /// both followed by a build.
  bool _applyPanelState(CollectionPanelRequest? request) {
    if (request == null || request._applied) return false;
    request._applied = true;
    final state = request.state;
    if (_onlineEnabled) {
      _onlineEnabled = false;
      _syncAdvancedTagRows();
      _onlineResults = const [];
      _onlineError = null;
      _onlineImportError = null;
      _onlineSearching = false;
    }
    _removedTags.clear();
    _ftsController.text = state.text;
    _ftsScope = state.scope;
    _localFtsScope = state.scope;
    // A tag the state names stays selected even if no dance carries it yet.
    state.facets.keepSelectedTags();
    _facets = state.facets;
    _byPhrase = state.byPhrase;
    _advancedRoot = state.advanced;
    _panelFromSavedSearch = state.fromSavedSearch;
    _leaveSuggested();
    // Best match that is no longer offered falls back to Title.
    final (:sort, :direction) = state.effectiveSort;
    _sort = sort;
    _sortDir = direction;
    _sortUserSet = true;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newRequirePerformed = RequirePerformedForHistoryScope.of(context);
    final requirePerformedChanged =
        _started && newRequirePerformed != _requirePerformedForHistory;
    _requirePerformedForHistory = newRequirePerformed;
    final newRequireEventDate = RequireEventDateForHistoryScope.of(context);
    final requireEventDateChanged =
        _started && newRequireEventDate != _requireEventDateForHistory;
    _requireEventDateForHistory = newRequireEventDate;
    final newTracking = callingHistoryTrackingOf(context);
    final trackingChanged = _started && newTracking != _tracking;
    _tracking = newTracking;
    final newIgnoreLeadingArticles = SortIgnoreArticlesScope.of(context);
    final ignoreLeadingArticlesChanged =
        _started && newIgnoreLeadingArticles != _ignoreLeadingArticles;
    _ignoreLeadingArticles = newIgnoreLeadingArticles;
    // Hiding a section clears its selection (issue #1419); see the same hook in
    // DanceListScreen.didChangeDependencies for why only newly hidden sections.
    final newHiddenFacets = CollectionFacetsScope.of(context);
    final facetsCleared =
        _started &&
        _facets.clearFacets(newHiddenFacets.difference(_hiddenFacets));
    _hiddenFacets = newHiddenFacets;
    final suggestionInputsChanged = _readSuggestionInputs();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      unawaited(_seedSortThenSearch());
    } else if ((requirePerformedChanged ||
            requireEventDateChanged ||
            trackingChanged ||
            ignoreLeadingArticlesChanged ||
            facetsCleared) &&
        !_onlineEnabled) {
      _runSearch();
    } else if (suggestionInputsChanged && _suggested) {
      unawaited(_rank());
    }
  }

  /// Reads what Suggested depends on from the tree; true when any of it
  /// changed. Turning Suggestions off leaves Suggested for the plain order.
  bool _readSuggestionInputs() {
    final enabled = SuggestionsEnabledScope.of(context);
    final settings = SuggestionSettingsScope.of(context);
    final exact = MatrixCollisionModeScope.of(context);
    final config = ProgramMatrixColumnConfigScope.of(context);
    final userFigures = UserFiguresScope.shownCatalogOf(context);
    final changed =
        settings != _suggestionSettings ||
        exact != _exactBeatCollision ||
        config != _matrixConfig ||
        userFigures != _userFigures;
    _suggestionSettings = settings;
    _exactBeatCollision = exact;
    _matrixConfig = config;
    _userFigures = userFigures;
    _suggestionsEnabled = enabled;
    if (!enabled && _suggested) _leaveSuggested();
    return changed;
  }

  /// Whether the Sort menu offers Suggested.
  bool get _suggestedAvailable =>
      _suggestionsEnabled && widget.programContext?.position != null;

  /// Back to the plain order, dropping any ranking in flight.
  void _leaveSuggested() {
    _suggested = false;
    _ranking = null;
    _rankById = const {};
    _rankedFor = null;
    _rankedAt = null;
    _rankPending = false;
    _rankFailed = false;
    _rankSeq++;
  }

  @override
  void didUpdateWidget(CollectionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    var dataChanged = false;
    var onlineDisabled = false;
    // A request this picker (or another) has applied is left alone, so a
    // rebuild never puts it back over the user's edits.
    final panelApplied = _applyPanelState(widget.panelState);
    if (panelApplied) {
      _debounceTimer?.cancel();
      _searchSeq++;
      _onlineSeq++;
    }
    if (oldWidget.enableOnlineSearch &&
        !widget.enableOnlineSearch &&
        _onlineEnabled) {
      _debounceTimer?.cancel();
      _searchSeq++;
      _onlineSeq++;
      setState(() {
        _onlineEnabled = false;
        _syncAdvancedTagRows();
        _ftsScope = _localFtsScope;
        _onlineResults = const [];
        _onlineError = null;
        _onlineImportError = null;
        _onlineSearching = false;
      });
      onlineDisabled = true;
    }
    if (oldWidget.data != widget.data) {
      _importedDances.removeWhere((id, imported) {
        final current = widget.data.dancesById[id];
        return current != null &&
            !current.updatedAt.isBefore(imported.updatedAt);
      });
      _importedChoreographers.removeWhere((id, imported) {
        final current = widget.data.choreographersById[id];
        if (current == imported) return true;
        return current != null &&
            !_importedDances.values.any(
              (dance) => dance.authorIds.contains(id),
            );
      });
      // A tag picked by hand that no live dance carries any more is dropped;
      // one a panel state brought is kept (see retainTags). The search below
      // re-runs for any data change.
      _facets.retainTags([for (final t in widget.data.tags) t.id]);
      dataChanged = true;
    }
    final hostOverrideAdvanced = _results.any((entry) {
      final override = widget.danceOverrides[entry.dance.id];
      return override != null &&
          override.updatedAt.isAfter(entry.dance.updatedAt);
    });
    var onlineServiceChanged = false;
    if (oldWidget.callersBoxOnline != widget.callersBoxOnline) {
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      onlineServiceChanged = true;
    }
    if (oldWidget.contraDbOnline != widget.contraDbOnline) {
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      onlineServiceChanged = true;
    }
    // The active dialect or the saved-dialect enrichment can change while the
    // picker is open (e.g. the user edits their dialect library).
    final searchInputsChanged =
        oldWidget.dialect != widget.dialect ||
        oldWidget.enrichment != widget.enrichment;
    if (searchInputsChanged && !_onlineEnabled) {
      _runSearch();
    }
    if (panelApplied ||
        onlineDisabled ||
        ((dataChanged || hostOverrideAdvanced) &&
            !_onlineEnabled &&
            !searchInputsChanged)) {
      _runSearch();
    }
    if (onlineServiceChanged && _onlineEnabled) {
      _onlineSeq++;
      _runOnlineSearch();
    }
    if (oldWidget.programContext != widget.programContext && _suggested) {
      if (widget.programContext?.position == null) {
        setState(_leaveSuggested);
      } else if (!dataChanged && !searchInputsChanged) {
        // A data change re-runs the search above, which re-ranks.
        unawaited(_rank());
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final timer in _confirmTimers.values) {
      timer.cancel();
    }
    _confirmTimers.clear();
    _ftsController.dispose();
    _worker?.dispose();
    super.dispose();
  }

  /// Adds [danceId] and flags its row as just-added.
  ///
  /// The picker's own row is the only confirmation a user reliably sees: on
  /// narrow layouts the picker is a bottom sheet covering 85–95% of the screen,
  /// so the SnackBar the host fires draws behind it (#796). The host's SnackBar
  /// and semantics announcement are left alone — outside the sheet both are
  /// visible and correct, and the announcement is what carries this to assistive
  /// technology either way.
  ///
  /// State is set *before* [CollectionPicker.onAddDance] because one host pops
  /// its sheet synchronously inside that callback.
  void _handleAdd(String danceId) {
    setState(() {
      // Re-tapping mid-confirmation restarts the linger instead of leaving an
      // older timer to cut the new confirmation short.
      _confirmTimers.remove(danceId)?.cancel();
      _confirmTimers[danceId] = Timer(_addConfirmation, () {
        if (!mounted) return;
        setState(() => _confirmTimers.remove(danceId));
      });
    });
    widget.onAddDance(danceId);
  }

  /// Opens in the Collection's opening sort, then runs the first search.
  Future<void> _seedSortThenSearch() async {
    final opening = await readCollectionOpeningSort(_repos.settings);
    if (!mounted) return;
    if (opening != null && !_sortUserSet) {
      _sort = opening.sort;
      _sortDir = opening.direction;
    }
    if (!_onlineEnabled) await _runSearch();
  }

  /// Whether the query is a bare full-text search, the only case where Best
  /// match is offered (`docs/design/search.md` decision 6).
  bool get _isBareFullText => isBareFullText(
    ftsText: _ftsController.text,
    facets: _facets,
    scope: _ftsScope,
    byPhrase: _byPhrase,
    advancedRoot: _advancedRoot,
  );

  Future<void> _runSearch() async {
    final data = widget.data;
    // Best match is only valid for a bare full-text search; fall back as the
    // Collection does if the query stopped being one.
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
        tracking: _tracking,
        today: widget.clock.today(),
        currentProgramId: widget.programContext?.programId,
      );
      final ids = await _repos.dances.search(
        filter,
        sort: _sort.searchSort,
        direction: _sortDir,
        dialect: widget.dialect,
        enrichment: widget.enrichment,
        ignoreLeadingArticles: _ignoreLeadingArticles,
        // The Last-called sort reads the same history as the Called filter
        // above, as the Collection's does (FIND-2).
        callerFilter: data.callerFilter,
        performedOnly: _requirePerformedForHistory,
        requireEventDate: _requireEventDateForHistory,
        tracking: _tracking,
        currentProgramId: widget.programContext?.programId,
      );
      if (!mounted || seq != _searchSeq) return;
      final choreographerNamesOverride = {
        ...widget.choreographerNamesOverride,
        for (final entry in _importedChoreographers.entries)
          entry.key: entry.value.name,
      };
      setState(() {
        _results = [
          for (final id in ids)
            if (_latestDanceFor(id, data) case final dance?)
              data.entryFor(
                dance,
                choreographerNamesOverride: choreographerNamesOverride,
              ),
        ];
        _searching = false;
      });
      if (_suggested) unawaited(_rank());
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'collection_picker._runSearch');
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchError = error;
        _results = const [];
        _searching = false;
      });
    }
  }

  Dance? _latestDanceFor(String id, CollectionData data) {
    final dances = [
      ?data.dancesById[id],
      ?widget.danceOverrides[id],
      ?_importedDances[id],
    ];
    if (dances.isEmpty) return null;
    return dances.reduce(
      (latest, dance) =>
          dance.updatedAt.isAfter(latest.updatedAt) ? dance : latest,
    );
  }

  void _onFtsChanged(String _) {
    _debounceTimer?.cancel();
    if (_onlineEnabled) {
      _prepareDebouncedOnlineSearch();
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      _searchSeq++;
      _debounceTimer = Timer(_debounce, _runSearch);
      setState(() {});
    }
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
      if (!_onlineEnabled) _localFtsScope = scope;
    });
    unawaited(_onlineEnabled ? _runOnlineSearch() : _runSearch());
  }

  void _selectSort(CollectionSort value) {
    setState(() {
      _sortUserSet = true;
      _leaveSuggested();
      _sort = value;
      _sortDir = value.searchSort.defaultDirection;
    });
    _runSearch();
  }

  /// Chooses Suggested. The results stay as they are, in the plain order,
  /// until the ranking arrives.
  void _selectSuggested() {
    if (_suggested) return;
    setState(() {
      _sortUserSet = true;
      _suggested = true;
    });
    unawaited(_rank());
  }

  /// Ranks the current results for the context's position, off the UI
  /// thread. A newer call, a new search, a new position or leaving Suggested
  /// drops it.
  Future<void> _rank() async {
    final programContext = widget.programContext;
    final position = programContext?.position;
    if (!_suggested || programContext == null || position == null) return;
    final seq = ++_rankSeq;
    final results = _results;
    final data = widget.data;
    final settings = _suggestionSettings.settings;
    setState(() => _rankPending = true);
    try {
      final venueKey = programContext.venueKey;
      var calledHere = const <String, DateTime?>{};
      if (venueKey != null && settings.venueRecency != SuggestionWeight.off) {
        // "Called here" is the Called filter's own selection: the history
        // settings, this venue, and never this program (N1-6).
        calledHere = await _repos.programs.latestCallByDance(
          CalledFilter(
            called: true,
            callerFilter: data.callerFilter,
            performedOnly: _requirePerformedForHistory,
            requireEventDate: _requireEventDateForHistory,
            tracking: _tracking,
            venue: venueKey,
            currentProgramId: programContext.programId,
          ),
        );
        if (!mounted || seq != _rankSeq) return;
      }
      final rank =
          widget.rankSuggestions ?? (_worker ??= SuggestionWorker()).rank;
      final ranking = await rank(
        SuggestionRequest(
          slotsBefore: position.slotsBefore,
          slotsAfter: position.slotsAfter,
          candidateIsAlternate: position.isAlternate,
          programDances: {
            for (final id in [
              ...position.slotsBefore,
              ...position.slotsAfter,
            ].map((slot) => slot.danceId).nonNulls)
              if (_latestDanceFor(id, data) case final dance?)
                id: SuggestionCandidate.fromDance(dance),
          },
          candidates: [
            for (final entry in results)
              SuggestionCandidate.fromDance(entry.dance),
          ],
          settings: settings,
          today: widget.clock.today(),
          collisionMode: _exactBeatCollision
              ? MatrixCollisionMode.exactBeats
              : MatrixCollisionMode.phrase,
          taxonomy: data.taxonomy,
          matrixConfig: _matrixConfig,
          userFigures: _userFigures,
          levels: data.levels,
          hasVenue: venueKey != null,
          calledHere: calledHere,
        ),
      );
      if (!mounted || seq != _rankSeq) return;
      setState(() {
        _ranking = ranking;
        _rankById = {for (final r in ranking.order) r.danceId: r};
        _rankedFor = results;
        _rankedAt = position;
        _rankPending = false;
        _rankFailed = false;
      });
    } on SuggestionRankSuperseded {
      // diagnostics: silent — a newer ranking replaced this one and reports
      // for both. Not a failure; only if none is running does the spinner
      // stop.
      if (mounted && seq == _rankSeq) setState(() => _rankPending = false);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'collection_picker._rank');
      if (!mounted || seq != _rankSeq) return;
      // Back to the plain order, and say so. An earlier ranking of these same
      // results (before a dance was added) is dropped too: it would no longer
      // be the order the notice calls "usual".
      setState(() {
        _ranking = null;
        _rankById = const {};
        _rankedFor = null;
        _rankedAt = null;
        _rankPending = false;
        _rankFailed = true;
      });
    }
  }

  /// Whether the ranking held is for exactly the results and the position
  /// showing now.
  bool get _rankingIsCurrent =>
      _suggested &&
      _ranking != null &&
      identical(_rankedFor, _results) &&
      _rankedAt == widget.programContext?.position;

  /// The results as shown: ranked when Suggested has a ranking for exactly
  /// these results at this position, else in the plain order.
  List<DanceListEntry> get _shownResults {
    final ranking = _ranking;
    if (!_rankingIsCurrent || ranking == null) return _results;
    final byId = {for (final entry in _results) entry.dance.id: entry};
    return [for (final ranked in ranking.order) ?byId[ranked.danceId]];
  }

  /// [danceId]'s place in the ranking being shown, or null when none is.
  RankedSuggestion? _shownRankFor(String danceId) =>
      _rankingIsCurrent ? _rankById[danceId] : null;

  SuggestionReasonLabels _reasonLabels(BuildContext context) =>
      SuggestionReasonLabels.of(
        context,
        taxonomy: widget.data.taxonomy,
        dialect: widget.dialect,
        matrixConfig: _matrixConfig,
        userFigures: _userFigures,
        venueLabel: widget.programContext?.venueLabel,
        danceTitle: (id) {
          final dance = _latestDanceFor(id, widget.data);
          return dance == null
              ? null
              : slotDanceTitle(
                  AppLocalizations.of(context),
                  dance,
                  markDeleted: true,
                );
        },
      );

  void _toggleSortDirection() {
    setState(() {
      _sortUserSet = true;
      _sortDir = _sortDir == SortDirection.ascending
          ? SortDirection.descending
          : SortDirection.ascending;
    });
    _runSearch();
  }

  void _onFacetsChanged() {
    setState(() {});
    _runSearch();
  }

  void _onByPhraseChanged() {
    if (_onlineEnabled) {
      _debounceTimer?.cancel();
      _prepareDebouncedOnlineSearch();
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      setState(() {});
      _runSearch();
    }
  }

  void _prepareDebouncedOnlineSearch() {
    _onlineSeq++;
    setState(() {
      _onlineResults = const [];
      _onlineError = null;
      _onlineImportError = null;
      _onlineSearching = _hasOnlineCriteria;
    });
  }

  void _onAdvancedChanged() {
    if (_onlineEnabled) {
      // Online, the Advanced query narrows an online source that accepts it
      // (ContraDB); for one that does not, the panel is greyed out, so this
      // is only reached for a source whose search it affects.
      _debounceTimer?.cancel();
      _prepareDebouncedOnlineSearch();
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      setState(() {});
      _runSearch();
    }
  }

  bool get _hasActiveQuery =>
      _ftsController.text.trim().isNotEmpty ||
      !_facets.isEmpty ||
      !_byPhrase.isEmpty ||
      _advancedRoot.toFilter() != null;

  void _clearAll() {
    _debounceTimer?.cancel();
    _searchSeq++;
    _onlineSeq++;
    setState(() {
      _ftsController.clear();
      _facets.clear();
      _byPhrase.clear();
      _advancedRoot.children.clear();
      _removedTags.clear();
      _advancedRoot.kind = GroupKind.all;
      _panelFromSavedSearch = false;
      _onlineResults = const [];
      _onlineError = null;
      _onlineImportError = null;
      _onlineSearching = false;
    });
    if (!_onlineEnabled) _runSearch();
  }

  OnlineSearchService get _online =>
      _onlineSource == OnlineSource.contraDb ? _contraDb : _callersBox;

  CallersBoxPhraseQuery? _onlinePhrases() {
    if (_byPhrase.isEmpty) return null;
    final phrases = CallersBoxPhraseQuery.fromSelections(
      _byPhrase,
      widget.data.taxonomy,
    );
    return phrases.isEmpty ? null : phrases;
  }

  CallersBoxPhraseQuery? _effectivePhrases() =>
      _onlineSource.supportsByPhrase ? _onlinePhrases() : null;

  /// The Advanced builder's filter as it applies to the active online source:
  /// `null` for sources without Advanced support
  /// ([OnlineSource.supportsAdvanced], i.e. The Caller's Box), so a residual
  /// local Advanced query can't leak into its search or keep an empty search
  /// "active". Mirrors [_effectivePhrases].
  DanceFilter? _effectiveAdvanced() =>
      _onlineSource.supportsAdvanced ? _advancedRoot.toFilter() : null;

  /// Whether the online search has anything to search for: query text, by-phrase
  /// figures, or an Advanced query the active source accepts.
  bool get _hasOnlineCriteria =>
      _ftsController.text.trim().isNotEmpty ||
      _effectivePhrases() != null ||
      _effectiveAdvanced() != null;

  /// Tag rows taken out of the Advanced query while ContraDB (which has no
  /// tags) is searched, so they can come back when it is not.
  final _removedTags = RemovedTagRows();

  /// Keeps the Advanced query's tag rows in line with the source searched: out
  /// while it cannot carry a tag (ContraDB has none; one left in would make the
  /// search fail), back in their place otherwise. Call inside `setState`,
  /// after `_onlineEnabled` or `_onlineSource` changes.
  void _syncAdvancedTagRows() {
    if (_onlineEnabled && _onlineSource.hidesAdvancedTags) {
      _removedTags.take(_advancedRoot);
    } else {
      _removedTags.restoreInto(_advancedRoot);
    }
  }

  void _onOnlineToggled(bool value) {
    _debounceTimer?.cancel();
    _searchSeq++;
    _onlineSeq++;
    setState(() {
      _onlineEnabled = value;
      _syncAdvancedTagRows();
      _onlineError = null;
      _onlineImportError = null;
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
      if (_hasOnlineCriteria) {
        _runOnlineSearch();
      }
    } else {
      _runSearch();
    }
  }

  void _onOnlineSourceChanged(OnlineSource source) {
    if (source == _onlineSource) return;
    _debounceTimer?.cancel();
    _onlineSeq++;
    setState(() {
      _onlineSource = source;
      _syncAdvancedTagRows();
      _onlineResults = const [];
      _onlineError = null;
      _onlineImportError = null;
      _onlineSearching = false;
    });
    if (_hasOnlineCriteria) {
      _runOnlineSearch();
    }
  }

  /// Fetches the next page of the current online search and appends it. Called
  /// by the list's last item once the end is near; one request at a time, and
  /// a page for a search that has since been replaced is dropped.
  Future<void> _loadMoreOnline() async {
    final base = _onlineQuery;
    if (base == null ||
        !_onlineHasMore ||
        _onlineLoadingMore ||
        _onlineMoreFailed ||
        _onlinePagingSeq != _onlineSeq) {
      return;
    }
    final seq = _onlineSeq;
    setState(() => _onlineLoadingMore = true);
    try {
      final page = await _online.search(
        base.withOffset(_onlinePagesLoaded * contraDbSearchCount),
      );
      if (!mounted || seq != _onlineSeq) return;
      final merged = appendOnlinePage(_onlineResults, page);
      setState(() {
        final grew = merged.length > _onlineResults.length;
        _onlineResults = merged;
        _onlinePagesLoaded++;
        _onlineHasMore = grew && onlineHasMore(merged, page);
        _onlineLoadingMore = false;
      });
    } on Object catch (error, stackTrace) {
      if (!mounted || seq != _onlineSeq) return;
      if (error is UrlFetchException) {
        logCaughtError(
          error,
          stackTrace,
          source: 'collection_picker._loadMoreOnline',
        );
      } else {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'collection_picker._loadMoreOnline',
        );
      }
      setState(() {
        _onlineLoadingMore = false;
        _onlineMoreFailed = true;
      });
    }
  }

  Future<void> _runOnlineSearch() async {
    final query = OnlineSearchQuery.forScope(
      _ftsController.text,
      _ftsScope,
      phrases: _effectivePhrases(),
      advanced: _effectiveAdvanced(),
    );
    if (query.isEmpty) {
      setState(() {
        _onlineResults = const [];
        _onlineError = null;
        _onlineImportError = null;
        _onlineSearching = false;
      });
      return;
    }
    final seq = ++_onlineSeq;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _onlineResults = const [];
      _onlineSearching = true;
      _onlineError = null;
      _onlineImportError = null;
    });
    try {
      final results = await _online.search(query);
      if (!mounted || seq != _onlineSeq) return;
      setState(() {
        _onlineResults = results;
        _onlineSearching = false;
        _onlineQuery = query;
        _onlinePagesLoaded = 1;
        _onlinePagingSeq = seq;
        _onlineHasMore = onlineHasMore(results, results);
        _onlineLoadingMore = false;
        _onlineMoreFailed = false;
      });
    } on UrlFetchException catch (error, stackTrace) {
      if (!mounted || seq != _onlineSeq) return;
      logCaughtError(
        error,
        stackTrace,
        source: 'collection_picker._runOnlineSearch',
      );
      setState(() {
        _onlineError = importErrorMessage(l10n, error);
        _onlineResults = const [];
        _onlineSearching = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || seq != _onlineSeq) return;
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_picker._runOnlineSearch',
      );
      setState(() {
        _onlineError = l10n.onlineSearchFailed(_onlineSource.label);
        _onlineResults = const [];
        _onlineSearching = false;
      });
    }
  }

  Future<void> _importOnlineResult(OnlineSearchResultRow onlineResult) async {
    if (_onlineImporting) return;
    setState(() {
      _onlineImporting = true;
      _onlineImportError = null;
    });
    final onImportingChanged = widget.onImportingChanged;
    final onDanceImported = widget.onDanceImported;
    final onAddDance = widget.onAddDance;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final service = _online;
    final searchGeneration = _onlineSeq;
    var importReported = false;
    try {
      importReported = true;
      onImportingChanged?.call(_importActivityOwner, true);
      final preview = await service.loadPreview(_repos, onlineResult);
      // The navigator's context, not the picker's: the picker can be removed
      // mid-import (a responsive layout change) while its route lives on, and
      // the import must still complete (program_editor_screen_test).
      if (!navigator.mounted) return;
      final result = await resolveAndImportOnline(
        navigator.context,
        service: service,
        repos: _repos,
        preview: preview,
        l10n: l10n,
      );
      if (result == null) return;
      final danceId = result.danceId;
      if ((result.kind == OnlineImportKind.created ||
              result.kind == OnlineImportKind.alreadyInCollection) &&
          danceId != null) {
        try {
          final dance = await _repos.dances.getById(danceId);
          if (dance != null) {
            final choreographers = await Future.wait(
              dance.authorIds.map(_repos.choreographers.getById),
            );
            if (mounted) {
              _importedDances[danceId] = dance;
              for (final choreographer in choreographers) {
                if (choreographer != null) {
                  _importedChoreographers[choreographer.id] = choreographer;
                }
              }
            }
          }
        } catch (error, stackTrace) {
          logCaughtErrorTypeOnly(
            error,
            stackTrace,
            source: 'collection_picker.importedMetadata',
          );
        }
        try {
          await onDanceImported?.call(danceId);
        } catch (error, stackTrace) {
          logCaughtErrorTypeOnly(
            error,
            stackTrace,
            source: 'collection_picker.onDanceImported',
          );
        }
        if (mounted) {
          setState(
            () => _onlineAddedIds.add((
              source: onlineResult.source,
              id: onlineResult.id,
            )),
          );
        }
        onAddDance(danceId);
      }
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'collection_picker._importOnlineResult',
      );
      if (mounted) {
        if (searchGeneration != _onlineSeq) return;
        setState(() {
          _onlineImportError = importErrorMessage(l10n, error);
          _onlineSearching = false;
        });
      }
    } catch (error, stackTrace) {
      logCaughtErrorTypeOnly(
        error,
        stackTrace,
        source: 'collection_picker._importOnlineResult',
      );
      if (mounted) {
        if (searchGeneration != _onlineSeq) return;
        setState(() {
          _onlineImportError = l10n.onlineImportError;
          _onlineSearching = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _onlineImporting = false);
      }
      if (importReported) {
        onImportingChanged?.call(_importActivityOwner, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final l10n = AppLocalizations.of(context);
    final searchField = TextField(
      key: const ValueKey('picker-search'),
      controller: _ftsController,
      onChanged: _onFtsChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: _onlineEnabled
            ? l10n.onlineSearchFieldLabel(_onlineSource.label)
            : l10n.collectionPickerSearchLabel,
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
        border: const OutlineInputBorder(),
      ),
    );
    return ExcludeFocus(
      excluding: _onlineImporting,
      child: IgnorePointer(
        ignoring: _onlineImporting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: SearchFieldWithScope(
                searchField: searchField,
                scopeField: SearchScopeField(
                  fieldKey: const ValueKey('picker-search-scope'),
                  scope: _ftsScope,
                  online: _onlineEnabled,
                  onChanged: _onFtsScopeChanged,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                controller: widget.scrollController,
                slivers: [
                  SliverList(
                    delegate: SliverChildListDelegate([
                      _buildSearchPanels(data),
                      _buildResultCount(),
                      const Divider(height: 1),
                    ]),
                  ),
                  _onlineEnabled
                      ? _buildOnlineResultsSliver()
                      : _buildResultsSliver(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The same compact row of search tools as the Collection
  /// ([SearchPanelBar]): Filters is local-only, By phrase and Advanced are also
  /// available for online sources that support them, and a tool the active
  /// source does not support stays in the row greyed out while online. The Online search
  /// icon ends the row in both modes (when the picker offers online search);
  /// while online, the source selector sits full-width under the row.
  Widget _buildSearchPanels(CollectionData data) {
    final l10n = AppLocalizations.of(context);
    final filtersActive = _facets.activeCount;
    final byPhraseActive = _byPhraseActiveCount();
    final panelBar = SearchPanelBar(
      storageId: 'picker',
      trailing: widget.enableOnlineSearch
          ? OnlineSearchToggle(
              key: const ValueKey('picker-online-search-enable'),
              enabled: _onlineEnabled,
              onChanged: _onlineImporting ? null : _onOnlineToggled,
            )
          : null,
      panels: [
        SearchPanelSpec(
          key: const ValueKey('picker-filters-panel'),
          enabled: !_onlineEnabled,
          label: filtersActive == 0
              ? l10n.collectionPickerFilters(0)
              : l10n.searchToolActiveCount(
                  l10n.collectionPickerFilters(0),
                  filtersActive,
                ),
          semanticsLabel: filtersActive == 0
              ? null
              : l10n.collectionPickerFilters(filtersActive),
          builder: (_) => _buildFiltersPanel(data),
        ),
        SearchPanelSpec(
          key: const ValueKey('picker-by-phrase-panel'),
          enabled: !_onlineEnabled || _onlineSource.supportsByPhrase,
          label: byPhraseActive == 0
              ? l10n.collectionPickerByPhrase(0)
              : l10n.searchToolActiveCount(
                  l10n.collectionPickerByPhrase(0),
                  byPhraseActive,
                ),
          semanticsLabel: byPhraseActive == 0
              ? null
              : l10n.collectionPickerByPhrase(byPhraseActive),
          builder: (_) => _buildByPhrasePanel(data),
        ),
        SearchPanelSpec(
          key: const ValueKey('picker-advanced-panel'),
          enabled: !_onlineEnabled || _onlineSource.supportsAdvanced,
          label: _advancedRoot.toFilter() != null
              ? l10n.collectionAdvancedActive
              : l10n.collectionPickerAdvanced,
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
              key: const ValueKey('picker-online-source-selector'),
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
              onSelectionChanged: _onlineImporting
                  ? null
                  : (selection) => _onOnlineSourceChanged(selection.first),
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
      venueChoices: VenueChoiceSource(
        repos: _repos,
        callerFilter: data.callerFilter,
        performedOnly: _requirePerformedForHistory,
        requireEventDate: _requireEventDateForHistory,
      ),
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
      meters: data.meters,
      musicalKeys: data.musicalKeys,
      choiceFields: data.choiceFields,
      booleanFields: data.booleanFields,
      textFields: data.textFields,
      numberFields: data.numberFields,
      allLevels: data.allLevels,
      authorNames: data.choreographerNames,
      allTagNames: data.allTagNames,
      sourceTitles: data.sourceTitles,
      allCustomFields: data.customFieldDefs,
      historyFromSavedSearch: _panelFromSavedSearch,
      onChanged: _onFacetsChanged,
    );
  }

  Widget _buildByPhrasePanel(CollectionData data) {
    return ByPhrasePanel(
      selections: _byPhrase,
      taxonomy: data.taxonomy,
      sectionLabels: data.sectionLabels,
      dialect: widget.dialect,
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
      dialect: widget.dialect,
      sectionLabels: data.sectionLabels,
      tags: data.tags,
      allTagNames: data.allTagNames,
      tagsUnavailableFor: _onlineEnabled && _onlineSource.hidesAdvancedTags
          ? _onlineSource.label
          : null,
      onChanged: _onAdvancedChanged,
    );
  }

  Widget _buildResultCount() {
    final l10n = AppLocalizations.of(context);
    final count = _onlineEnabled ? _onlineResults.length : _results.length;
    final searching = _onlineEnabled ? _onlineSearching : _searching;
    // The sort sits at the end of the count row, the picker's nearest thing to
    // the Collection's app bar. Online results come in the source's own order,
    // so it is local-only, like the Filters panel. While local, the sort
    // buttons' own 48 px height spaces the row.
    return Padding(
      padding: _onlineEnabled
          ? const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            )
          : const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xs, 0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _onlineEnabled
                          ? onlineResultCountLabel(
                              l10n,
                              _onlineResults,
                              hasMore: _onlineHasMore,
                              loadFailed: _onlineMoreFailed,
                            )
                          : l10n.collectionDanceCount(count),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                if (searching ||
                    _onlineImporting ||
                    (!_onlineEnabled && _suggested && _rankPending)) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          if (!_onlineEnabled) ...[
            CollectionSortMenuButton(
              key: const ValueKey('picker-sort'),
              sort: _sort,
              sorts: availableCollectionSorts(bareFullText: _isBareFullText),
              onSelected: _selectSort,
              suggested: _suggestedAvailable
                  ? SuggestedSortChoice(
                      selected: _suggested,
                      onSelected: _selectSuggested,
                    )
                  : null,
            ),
            // A ranking has no direction.
            if (!_suggested)
              SortDirectionButton(
                buttonKey: const ValueKey('picker-sort-direction'),
                direction: _sortDir,
                onPressed: _toggleSortDirection,
              ),
          ],
        ],
      ),
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
    final shown = _shownResults;
    final labels = _rankById.isEmpty ? null : _reasonLabels(context);
    final list = _buildResultRows(shown, labels);
    if (!(_suggested && _rankFailed)) return list;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            key: const ValueKey('picker-suggested-failed'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.suggestionRankingFailed,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        list,
      ],
    );
  }

  Widget _buildResultRows(
    List<DanceListEntry> shown,
    SuggestionReasonLabels? labels,
  ) {
    final l10n = AppLocalizations.of(context);
    return SliverList.builder(
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final entry = shown[index];
        final ranked = _shownRankFor(entry.dance.id);
        final confirming = _confirmTimers.containsKey(entry.dance.id);
        final inProgramCount = widget.addedDanceCounts[entry.dance.id] ?? 0;
        // Tapping a row adds the dance — a keyboard/AT-accessible add
        // affordance (announced via the builder's live region on add).
        //
        // The row's semantic label deliberately does not change while
        // confirming: the host already announces the add, and mutating the
        // label would make a screen reader re-read the row to say the same
        // thing twice.
        return Semantics(
          button: true,
          label: widget.rowAction == PickerRowAction.replace
              ? l10n.collectionPickerReplaceSemantic(entry.dance.title)
              : l10n.collectionPickerAddSemantic(entry.dance.title),
          // The tile takes the width left over by the row's action buttons
          // rather than having them painted over its title (UX4-5): at 360px
          // the buttons used to cover up to ~130px of the first line.
          child: Row(
            children: [
              Expanded(
                child: PreviewHoldListener(
                  onPreviewStarted: widget.onPreviewDanceStarted == null
                      ? null
                      : () => widget.onPreviewDanceStarted!(entry.dance.id),
                  onPreviewEnded: widget.onPreviewDanceEnded == null
                      ? null
                      : () => widget.onPreviewDanceEnded!(entry.dance.id),
                  child: DanceListTile(
                    key: ValueKey('picker-tile-${entry.dance.id}'),
                    entry: entry,
                    // The Collection card fields setting covers the picker's
                    // rows too, like its sibling Collection filters (PRES-15).
                    visibleFields: CollectionTileFieldsScope.of(context),
                    onTap: () => _handleAdd(entry.dance.id),
                    showChevron: false,
                    reasonLine: ranked == null ? null : labels?.line(ranked),
                  ),
                ),
              ),
              // Persistent in-program marker: visible whenever the dance
              // already appears in the program being built, whether or not
              // the user added it this session. Shape-based (icon + optional
              // count), never colour-only (`docs/design/ux.md` §4, WCAG 1.4.1).
              // Coexists with the transient add-button to the right; each
              // signals something different — this one says "is in the
              // program", the button says "you just tapped add".
              if (inProgramCount > 0)
                Semantics(
                  label: inProgramCount > 1
                      ? l10n.collectionPickerInProgramCountSemantic(
                          entry.dance.title,
                          inProgramCount,
                        )
                      : l10n.collectionPickerInProgramSemantic(
                          entry.dance.title,
                        ),
                  excludeSemantics: true,
                  child: Row(
                    key: ValueKey('picker-in-program-${entry.dance.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (inProgramCount > 1)
                        Text(
                          '$inProgramCount',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      const Icon(Icons.playlist_add_check, size: 20),
                    ],
                  ),
                ),
              if (ranked != null && labels != null)
                IconButton(
                  key: ValueKey('picker-why-${entry.dance.id}'),
                  tooltip: l10n.suggestionWhyTooltip(entry.dance.title),
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => showSuggestionWhyDialog(
                    context,
                    title: entry.dance.title,
                    suggestion: ranked,
                    labels: labels,
                  ),
                ),
              if (widget.onViewDanceDetails != null)
                IconButton(
                  key: ValueKey('picker-details-${entry.dance.id}'),
                  tooltip: l10n.viewDetails,
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () => widget.onViewDanceDetails!(entry.dance.id),
                ),
              IconButton(
                key: ValueKey('picker-add-${entry.dance.id}'),
                tooltip: widget.rowAction == PickerRowAction.replace
                    ? l10n.collectionPickerReplaceTooltip(entry.dance.title)
                    : confirming
                    ? l10n.collectionPickerAddedTooltip(entry.dance.title)
                    : l10n.collectionPickerAddTooltip(entry.dance.title),
                // Both this button and the persistent marker above use
                // shape changes, not colour changes — colour is never the
                // only signal (`docs/design/ux.md` §4, WCAG 1.4.1). The
                // button stays enabled throughout — a dance may legitimately
                // appear in a program more than once.
                icon: Icon(
                  widget.rowAction == PickerRowAction.replace
                      ? Icons.swap_horiz
                      : confirming
                      ? Icons.check_circle
                      : Icons.add_circle_outline,
                ),
                onPressed: () => _handleAdd(entry.dance.id),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOnlineResultsSliver() {
    final l10n = AppLocalizations.of(context);
    if (_onlineError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(_onlineError!, textAlign: TextAlign.center),
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
    if (!_hasOnlineCriteria) {
      final hint = _onlineSource.supportsByPhrase
          ? l10n.onlineSearchHintByPhrase(_onlineSource.label)
          : l10n.onlineSearchHintTitle(_onlineSource.label);
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(child: Text(hint, textAlign: TextAlign.center)),
        ),
      );
    }
    if (_onlineResults.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Text(
              _onlineImportError ?? l10n.onlineNoResults(_onlineSource.label),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final showFooter = _onlineHasMore || _onlineMoreFailed;
    final leading = _onlineImportError == null ? 0 : 1;
    return SliverList.builder(
      itemCount: _onlineResults.length + leading + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (_onlineImportError != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xxs,
            ),
            child: Text(_onlineImportError!, textAlign: TextAlign.center),
          );
        }
        if (index == _onlineResults.length + leading) {
          return OnlineMoreFooter(
            key: ValueKey(
              'online-more-$_onlinePagingSeq-${_onlineResults.length}',
            ),
            failed: _onlineMoreFailed,
            failedMessage: l10n.onlineSearchFailed(_onlineSource.label),
            onLoad: _loadMoreOnline,
            onRetry: () {
              setState(() => _onlineMoreFailed = false);
              _loadMoreOnline();
            },
          );
        }
        final resultIndex = index - leading;
        final result = _onlineResults[resultIndex];
        return Semantics(
          button: true,
          enabled: !_onlineImporting,
          label: widget.rowAction == PickerRowAction.replace
              ? l10n.collectionPickerReplaceSemantic(result.name)
              : l10n.collectionPickerAddSemantic(result.name),
          // Same layout as the local rows: the trailing icons take their own
          // width instead of covering the title (UX4-5).
          child: Row(
            children: [
              Expanded(
                child: PreviewHoldListener(
                  onPreviewStarted:
                      _onlineImporting || widget.onPreviewOnlineStarted == null
                      ? null
                      : () => widget.onPreviewOnlineStarted!(result),
                  onPreviewEnded: widget.onPreviewOnlineEnded == null
                      ? null
                      : () => widget.onPreviewOnlineEnded!(result),
                  child: OnlineResultTile(
                    key: ValueKey(
                      'picker-online-result-${result.source.name}-${result.id}',
                    ),
                    result: result,
                    onTap: _onlineImporting
                        ? null
                        : () => _importOnlineResult(result),
                  ),
                ),
              ),
              if (_onlineAddedIds.contains((
                source: result.source,
                id: result.id,
              )))
                IgnorePointer(
                  child: Tooltip(
                    message: l10n.collectionPickerAddedTooltip(result.name),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        key: ValueKey(
                          'picker-online-added-${result.source.name}-${result.id}',
                        ),
                        Icons.check_circle_outline,
                      ),
                    ),
                  ),
                ),
              if (widget.onViewOnlineDetails != null)
                IconButton(
                  key: ValueKey(
                    'picker-online-details-${result.source.name}-${result.id}',
                  ),
                  tooltip: l10n.viewDetails,
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: _onlineImporting
                      ? null
                      : () => widget.onViewOnlineDetails!(result),
                ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        );
      },
    );
  }
}
