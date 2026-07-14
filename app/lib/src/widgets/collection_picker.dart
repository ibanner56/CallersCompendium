import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/collection_query.dart';
import 'dance_list_tile.dart';
import 'facet_panel.dart';

/// A reusable dance picker that reuses the Collection search stack (full-text
/// search + [FacetPanel] + [DanceRepository.search]) so the Programs builder
/// can find and add dances with the same filtering as the Collection screen
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
    required this.onAddDance,
  });

  /// Preloaded collection vocabulary/dances (loaded once by the builder and
  /// shared, so the picker doesn't re-query on every open).
  final CollectionData data;

  /// Active dialect for search canonicalization.
  final Dialect dialect;

  /// Called with the tapped dance's id to add it to the program.
  final void Function(String danceId) onAddDance;

  @override
  State<CollectionPicker> createState() => _CollectionPickerState();
}

class _CollectionPickerState extends State<CollectionPicker> {
  static const Duration _debounce = Duration(milliseconds: 250);

  final _ftsController = TextEditingController();
  final _facets = FacetSelections();

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
      _runSearch();
    }
  }

  @override
  void didUpdateWidget(CollectionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The active dialect can change while the picker is open.
    if (oldWidget.dialect != widget.dialect) _runSearch();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ftsController.dispose();
    super.dispose();
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
      );
      final ids = await _repos.dances.search(filter, dialect: widget.dialect);
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
        _results = const [];
        _searching = false;
      });
    }
  }

  void _onFtsChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _runSearch);
    setState(() {});
  }

  void _onFacetsChanged() {
    setState(() {});
    _runSearch();
  }

  bool get _hasActiveQuery =>
      _ftsController.text.trim().isNotEmpty || !_facets.isEmpty;

  void _clearAll() {
    setState(() {
      _ftsController.clear();
      _facets.clear();
    });
    _runSearch();
  }

  int _activeFacetCount() {
    return _facets.forms.length +
        _facets.formations.length +
        _facets.progressions.length +
        _facets.statuses.length +
        _facets.authorIds.length +
        _facets.tagIds.length +
        _facets.choiceValues.values.fold<int>(0, (a, s) => a + s.length) +
        _facets.booleanValues.length +
        _facets.textValues.values.where((s) => s.isEffective).length +
        _facets.numberValues.values.where((s) => s.isEffective).length;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
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
              labelText: 'Find a dance to add',
              hintText: 'Search titles, authors, figures, notes…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasActiveQuery
                  ? IconButton(
                      tooltip: 'Clear search and filters',
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
            slivers: [
              SliverList(
                delegate: SliverChildListDelegate([
                  _buildFiltersPanel(data),
                  _buildResultCount(),
                  const Divider(height: 1),
                ]),
              ),
              _buildResultsSliver(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersPanel(CollectionData data) {
    final activeCount = _activeFacetCount();
    return ExpansionTile(
      key: const ValueKey('picker-filters-panel'),
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(
        activeCount == 0 ? 'Filters' : 'Filters ($activeCount active)',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        FacetPanel(
          facets: _facets,
          forms: data.forms,
          formations: data.formations,
          progressions: data.progressions,
          statuses: data.statuses,
          authors: data.authors,
          tags: data.tags,
          choiceFields: data.choiceFields,
          booleanFields: data.booleanFields,
          textFields: data.textFields,
          numberFields: data.numberFields,
          onChanged: _onFacetsChanged,
        ),
      ],
    );
  }

  Widget _buildResultCount() {
    final count = _results.length;
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
                '$count ${count == 1 ? 'dance' : 'dances'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_searching) ...[
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
    if (_searchError != null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Something went wrong running the search.'),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No dances match your search.')),
        ),
      );
    }
    return SliverList.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
        // Tapping a row adds the dance — a keyboard/AT-accessible add
        // affordance (announced via the builder's live region on add).
        return Semantics(
          button: true,
          label: 'Add ${entry.dance.title} to program',
          child: Stack(
            children: [
              DanceListTile(
                key: ValueKey('picker-tile-${entry.dance.id}'),
                entry: entry,
                onTap: () => widget.onAddDance(entry.dance.id),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  key: ValueKey('picker-add-${entry.dance.id}'),
                  tooltip: 'Add ${entry.dance.title}',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => widget.onAddDance(entry.dance.id),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
