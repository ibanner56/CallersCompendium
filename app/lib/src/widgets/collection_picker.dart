import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../data/callersbox_online.dart';
import '../data/contradb_online.dart';
import '../data/import_error_labels.dart';
import '../data/import_io.dart';
import '../data/online_search.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/collection_query.dart';
import '../screens/online_import_variation_dialog.dart';
import 'advanced_query_builder.dart';
import 'by_phrase_panel.dart';
import 'dance_list_tile.dart';
import 'facet_panel.dart';
import 'online_result_tile.dart';

/// A reusable dance picker that reuses the Collection search stack (full-text
/// search + [FacetPanel] + [ByPhrasePanel] + [AdvancedQueryBuilder] +
/// [DanceRepository.search]) so the Programs builder can find and add dances
/// with the same figure-aware filtering as the Collection screen
/// (`docs/design/ux.md` §4).
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

  /// Whether the Advanced panel offers the Collection's online search mode.
  ///
  /// Hosts opt in because an online result imports before [onAddDance] runs,
  /// unlike a local result which is already persisted.
  final bool enableOnlineSearch;

  /// Online services used when [enableOnlineSearch] is true. They are optional
  /// test seams; the state creates the normal services when omitted.
  final OnlineSearchService? callersBoxOnline;
  final OnlineSearchService? contraDbOnline;

  /// Called after an online dance has been persisted and before [onAddDance].
  final Future<void> Function(String danceId)? onDanceImported;

  @override
  State<CollectionPicker> createState() => _CollectionPickerState();
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
  final _facets = FacetSelections();
  final _byPhrase = ByPhraseSelections();
  final _advancedRoot = BuilderGroup();
  bool _advancedEnabled = false;

  late OnlineSearchService _callersBox;
  late OnlineSearchService _contraDb;
  OnlineSource _onlineSource = OnlineSource.callersBox;
  bool _onlineEnabled = false;
  List<OnlineSearchResultRow> _onlineResults = const [];
  bool _onlineSearching = false;
  String? _onlineError;
  String? _onlineImportError;
  int _onlineSeq = 0;
  bool _onlineImporting = false;
  final Set<({OnlineSource source, String id})> _onlineAddedIds = {};
  final Map<String, Dance> _importedDances = {};

  static const Duration _onlineDebounce = Duration(milliseconds: 500);

  /// Dance ids whose row is currently showing its post-add check, each mapped
  /// to the timer that will clear it.
  final Map<String, Timer> _confirmTimers = {};

  late CompendiumRepositories _repos;
  bool _started = false;

  List<DanceListEntry> _results = const [];
  bool _searching = false;
  Object? _searchError;
  int _searchSeq = 0;
  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _callersBox = widget.callersBoxOnline ?? CallersBoxOnline();
      _contraDb = widget.contraDbOnline ?? ContraDbOnline();
      _runSearch();
    }
  }

  @override
  void didUpdateWidget(CollectionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    var dataChanged = false;
    var onlineDisabled = false;
    if (oldWidget.enableOnlineSearch &&
        !widget.enableOnlineSearch &&
        _onlineEnabled) {
      _debounceTimer?.cancel();
      _searchSeq++;
      _onlineSeq++;
      setState(() {
        _onlineEnabled = false;
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
      dataChanged = true;
    }
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
    if (searchInputsChanged) {
      _runSearch();
    }
    if (onlineDisabled ||
        (dataChanged && !_onlineEnabled && !searchInputsChanged)) {
      _runSearch();
    }
    if (onlineServiceChanged && _onlineEnabled) {
      _onlineSeq++;
      _runOnlineSearch();
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

  Future<void> _runSearch() async {
    final data = widget.data;
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
        dialect: widget.dialect,
        enrichment: widget.enrichment,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [
          for (final id in ids)
            if ((_importedDances[id] ?? data.dancesById[id]) case final dance?)
              data.entryFor(dance),
        ];
        _searching = false;
      });
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

  void _onFtsChanged(String _) {
    _debounceTimer?.cancel();
    if (_onlineEnabled) {
      _onlineSeq++;
      _debounceTimer = Timer(_onlineDebounce, _runOnlineSearch);
    } else {
      _searchSeq++;
      _debounceTimer = Timer(_debounce, _runSearch);
    }
    setState(() {});
  }

  void _onFacetsChanged() {
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

  void _onAdvancedChanged() {
    setState(() {});
    _runSearch();
  }

  bool get _hasActiveQuery =>
      _ftsController.text.trim().isNotEmpty ||
      !_facets.isEmpty ||
      !_byPhrase.isEmpty ||
      (_advancedEnabled && _advancedRoot.toFilter() != null);

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
      _advancedEnabled = false;
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

  void _onOnlineToggled(bool value) {
    _debounceTimer?.cancel();
    _searchSeq++;
    _onlineSeq++;
    setState(() {
      _onlineEnabled = value;
      _onlineError = null;
      _onlineImportError = null;
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

  void _onOnlineSourceChanged(OnlineSource source) {
    if (source == _onlineSource) return;
    _debounceTimer?.cancel();
    _onlineSeq++;
    setState(() {
      _onlineSource = source;
      _onlineResults = const [];
      _onlineError = null;
      _onlineImportError = null;
      _onlineSearching = false;
    });
    if (_ftsController.text.trim().isNotEmpty || _effectivePhrases() != null) {
      _runOnlineSearch();
    }
  }

  Future<void> _runOnlineSearch() async {
    final title = _ftsController.text.trim();
    final phrases = _effectivePhrases();
    if (title.isEmpty && phrases == null) {
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
      _onlineSearching = true;
      _onlineError = null;
      _onlineImportError = null;
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
    final l10n = AppLocalizations.of(context);
    final service = _online;
    try {
      final preview = await service.loadPreview(_repos, onlineResult);
      if (!mounted) return;
      var result = await service.import(_repos, preview.plan);
      if (result.kind == OnlineImportKind.needsConfirmation) {
        final existingId = result.danceId;
        assert(
          existingId != null,
          'needsConfirmation must carry an existing dance id',
        );
        if (existingId == null || !mounted) return;
        final existingTitle =
            (await _repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportVariationDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return;
        result = await service.import(
          _repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      } else if (result.kind == OnlineImportKind.needsConfirmationIdentical) {
        final existingId = result.danceId;
        assert(
          existingId != null,
          'needsConfirmationIdentical must carry an existing dance id',
        );
        if (existingId == null || !mounted) return;
        final existingTitle =
            (await _repos.dances.getById(existingId))?.title ?? result.title;
        if (!mounted) return;
        final resolution = await showOnlineImportCrossSourceDuplicateDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
        );
        if (resolution == null || !mounted) return;
        result = await service.import(
          _repos,
          preview.plan,
          ambiguousResolution: resolution,
        );
      }
      if (!mounted) return;
      final danceId = result.danceId;
      if ((result.kind == OnlineImportKind.created ||
              result.kind == OnlineImportKind.alreadyInCollection) &&
          danceId != null) {
        final dance = await _repos.dances.getById(danceId);
        if (!mounted) return;
        if (dance != null) _importedDances[danceId] = dance;
        await widget.onDanceImported?.call(danceId);
        if (!mounted) return;
        setState(
          () => _onlineAddedIds.add((
            source: onlineResult.source,
            id: onlineResult.id,
          )),
        );
        widget.onAddDance(danceId);
      }
    } on UrlFetchException catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'collection_picker._importOnlineResult',
      );
      if (mounted) {
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
        setState(() {
          _onlineImportError = l10n.onlineImportError;
          _onlineSearching = false;
        });
      }
    } finally {
      if (mounted) setState(() => _onlineImporting = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final l10n = AppLocalizations.of(context);
    // Picker call sites pass no visibleFields to DanceListTile, so they
    // default to all-visible — no scope override needed here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            key: const ValueKey('picker-search'),
            controller: _ftsController,
            onChanged: _onFtsChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: l10n.collectionPickerSearchLabel,
              hintText: l10n.collectionSearchFieldHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasActiveQuery
                  ? IconButton(
                      tooltip: l10n.collectionClearSearchTooltip,
                      icon: const Icon(Icons.clear),
                      onPressed: _clearAll,
                    )
                  : null,
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
                  if (!_onlineEnabled) _buildFiltersPanel(data),
                  if (!_onlineEnabled || _onlineSource.supportsByPhrase)
                    _buildByPhrasePanel(data),
                  _buildAdvancedPanel(data),
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
    );
  }

  Widget _buildFiltersPanel(CollectionData data) {
    final l10n = AppLocalizations.of(context);
    final activeCount = _activeFacetCount();
    return ExpansionTile(
      key: const ValueKey('picker-filters-panel'),
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(l10n.collectionPickerFilters(activeCount)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
      key: const ValueKey('picker-by-phrase-panel'),
      leading: const Icon(Icons.grid_view_outlined),
      title: Text(l10n.collectionPickerByPhrase(activeCount)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
      key: const ValueKey('picker-advanced-panel'),
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(l10n.collectionPickerAdvanced),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (widget.enableOnlineSearch) ...[
          SwitchListTile(
            key: const ValueKey('picker-online-search-enable'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.cloud_outlined),
            title: Text(l10n.onlineSearchToggleTitle),
            subtitle: Text(l10n.onlineSearchToggleSubtitle),
            value: _onlineEnabled,
            onChanged: _onOnlineToggled,
          ),
          if (_onlineEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<OnlineSource>(
                  key: const ValueKey('picker-online-source-selector'),
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
        ],
        SwitchListTile(
          key: const ValueKey('picker-advanced-enable'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.collectionPickerUseAdvancedQuery),
          subtitle: Text(l10n.collectionPickerAdvancedQueryHelp),
          value: _advancedEnabled,
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
            dialect: widget.dialect,
            sectionLabels: data.sectionLabels,
            onChanged: _onAdvancedChanged,
          ),
      ],
    );
  }

  Widget _buildResultCount() {
    final l10n = AppLocalizations.of(context);
    final count = _onlineEnabled ? _onlineResults.length : _results.length;
    final searching = _onlineEnabled ? _onlineSearching : _searching;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _onlineEnabled
                    ? l10n.onlineResultCount(count)
                    : l10n.collectionDanceCount(count),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (searching || _onlineImporting) ...[
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
    );
  }

  Widget _buildResultsSliver() {
    final l10n = AppLocalizations.of(context);
    if (_searchError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(l10n.collectionSearchError)),
        ),
      );
    }
    if (_results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(l10n.collectionNoResults)),
        ),
      );
    }
    return SliverList.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
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
          child: Stack(
            children: [
              DanceListTile(
                key: ValueKey('picker-tile-${entry.dance.id}'),
                entry: entry,
                onTap: () => _handleAdd(entry.dance.id),
              ),
              // Persistent in-program marker: visible whenever the dance
              // already appears in the program being built, whether or not
              // the user added it this session. Shape-based (icon + optional
              // count), never colour-only (`docs/design/ux.md` §4, WCAG 1.4.1).
              // Coexists with the transient add-button to the right; each
              // signals something different — this one says "is in the
              // program", the button says "you just tapped add".
              if (inProgramCount > 0)
                Positioned(
                  top: 12,
                  right: 56,
                  child: Semantics(
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
                ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
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
              ),
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
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(_onlineError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_onlineSearching && _onlineResults.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
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
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(hint, textAlign: TextAlign.center)),
        ),
      );
    }
    if (_onlineResults.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              _onlineImportError ?? l10n.onlineNoResults(_onlineSource.label),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: _onlineResults.length + (_onlineImportError == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (_onlineImportError != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(_onlineImportError!, textAlign: TextAlign.center),
          );
        }
        final resultIndex = index - (_onlineImportError == null ? 0 : 1);
        final result = _onlineResults[resultIndex];
        return Semantics(
          button: true,
          enabled: !_onlineImporting,
          label: widget.rowAction == PickerRowAction.replace
              ? l10n.collectionPickerReplaceSemantic(result.name)
              : l10n.collectionPickerAddSemantic(result.name),
          child: Stack(
            children: [
              OnlineResultTile(
                key: ValueKey(
                  'picker-online-result-${result.source.name}-${result.id}',
                ),
                result: result,
                onTap: _onlineImporting
                    ? null
                    : () => _importOnlineResult(result),
              ),
              if (_onlineAddedIds.contains((
                source: result.source,
                id: result.id,
              )))
                Positioned(
                  top: 12,
                  right: 16,
                  child: IgnorePointer(
                    child: Tooltip(
                      message: l10n.collectionPickerAddedTooltip(result.name),
                      child: Icon(
                        key: ValueKey(
                          'picker-online-added-${result.source.name}-${result.id}',
                        ),
                        Icons.check_circle,
                      ),
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
