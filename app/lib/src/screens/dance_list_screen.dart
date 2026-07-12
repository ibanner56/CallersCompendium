import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_query.dart';
import '../widgets/advanced_query_builder.dart';
import '../widgets/dance_list_tile.dart';
import '../widgets/facet_panel.dart';
import '../screens/custom_fields_screen.dart';
import '../screens/recently_deleted_screen.dart';
import 'dance_detail_screen.dart';
import 'dance_editor_screen.dart';

/// Collection screen: browse and search the dance library
/// (`docs/design/ux.md` §1). A unified full-text search bar, a one-tap facet
/// filter panel, and an "Advanced" boolean-tree query builder all compose a
/// single [DanceFilter] that is run against the search core
/// ([DanceRepository.search], `docs/design/search.md`). Results reuse the
/// Phase 3.1 list rendering and open [DanceDetailScreen] on tap.
class DanceListScreen extends StatefulWidget {
  const DanceListScreen({super.key});

  @override
  State<DanceListScreen> createState() => _DanceListScreenState();
}

class _DanceListScreenState extends State<DanceListScreen> {
  /// The active dialect the compiler canonicalizes input against. No user
  /// dialect setting is persisted yet (later roadmap work), so the canonical
  /// dialect is the default; the compiler still canonicalizes against it.
  static final Dialect _dialect = Dialect.canonical;

  static const Duration _debounce = Duration(milliseconds: 250);

  final _ftsController = TextEditingController();
  final _facets = FacetSelections();
  final _advancedRoot = BuilderGroup();
  bool _advancedEnabled = false;

  CollectionSort _sort = CollectionSort.title;

  late CompendiumRepositories _repos;
  bool _started = false;

  _CollectionData? _data;
  Object? _loadError;

  List<DanceListEntry> _results = const [];
  bool _searching = false;
  Object? _searchError;
  int _searchSeq = 0;

  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repos = RepositoriesScope.of(context);
    _boot();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ftsController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final data = await _CollectionData.load(_repos);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadError = null;
      });
      await _runSearch();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _retryLoad() {
    setState(() {
      _data = null;
      _loadError = null;
    });
    _boot();
  }

  /// Whether the current query is a bare full-text search (relevance sort is
  /// only meaningful then, per `docs/design/search.md` decision 6).
  bool get _isBareFullText => isBareFullText(
    ftsText: _ftsController.text,
    facets: _facets,
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
        advancedRoot: _advancedEnabled ? _advancedRoot : null,
      );
      final ids = await _repos.dances.search(
        filter,
        sort: _sort.searchSort,
        dialect: _dialect,
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
    _debounceTimer = Timer(_debounce, _runSearch);
    // Reflect relevance availability immediately (before the debounce fires).
    setState(() {});
  }

  void _onFacetsChanged() {
    setState(() {});
    _runSearch();
  }

  void _onAdvancedChanged() {
    setState(() {});
    _runSearch();
  }

  void _clearAll() {
    setState(() {
      _ftsController.clear();
      _facets.clear();
      _advancedRoot.children.clear();
      _advancedRoot.kind = GroupKind.all;
      _advancedEnabled = false;
    });
    _runSearch();
  }

  bool get _hasActiveQuery =>
      _ftsController.text.trim().isNotEmpty ||
      !_facets.isEmpty ||
      (_advancedEnabled && _advancedRoot.toFilter() != null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          if (_data != null) ...[
            IconButton(
              key: const ValueKey('manage-custom-fields'),
              tooltip: 'Manage custom fields',
              icon: const Icon(Icons.list_alt_outlined),
              onPressed: _openCustomFields,
            ),
            IconButton(
              key: const ValueKey('recently-deleted'),
              tooltip: 'Recently deleted',
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: _openRecentlyDeleted,
            ),
            PopupMenuButton<CollectionSort>(
              tooltip: 'Sort by',
              initialValue: _sort,
              onSelected: (value) {
                setState(() => _sort = value);
                _runSearch();
              },
              itemBuilder: (context) => [
                for (final option in _availableSorts)
                  PopupMenuItem(value: option, child: Text(option.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 4),
                    Text('Sort: ${_sort.label}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _data == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('new-dance'),
              onPressed: _openNewDance,
              icon: const Icon(Icons.add),
              label: const Text('New dance'),
            ),
    );
  }

  Future<void> _openNewDance() async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DanceEditorScreen()),
    );
    // Reload the collection so a newly saved dance shows up in results.
    if (mounted && created != null) await _boot();
  }

  Future<void> _openCustomFields() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomFieldsScreen()));
    // Reload so newly-created/edited fields show up as facets.
    if (mounted) await _boot();
  }

  Future<void> _openRecentlyDeleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecentlyDeletedScreen()),
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
    setState(() => _results.removeWhere((e) => e.dance.id == danceId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('list-deleted-snackbar'),
        content: Text('"$title" deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _repos.dances.restore(danceId, at: DateTime.now().toUtc());
            if (mounted) await _boot();
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Could not load the collection.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _retryLoad, child: const Text('Retry')),
          ],
        ),
      );
    }

    final data = _data;
    if (data == null) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading dances'),
      );
    }

    if (data.dancesById.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your collection is empty. Add or import a dance to get started.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _ftsController,
            onChanged: _onFtsChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search dances',
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
                  _buildAdvancedPanel(data),
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

  Widget _buildFiltersPanel(_CollectionData data) {
    final activeCount = _activeFacetCount();
    return ExpansionTile(
      key: const ValueKey('filters-panel'),
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

  Widget _buildAdvancedPanel(_CollectionData data) {
    return ExpansionTile(
      key: const ValueKey('advanced-panel'),
      leading: const Icon(Icons.account_tree_outlined),
      title: const Text('Advanced'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SwitchListTile(
          key: const ValueKey('advanced-enable'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Use advanced query'),
          subtitle: const Text(
            'Combine figures and sequences with all / any / none groups.',
          ),
          value: _advancedEnabled,
          onChanged: (value) {
            setState(() => _advancedEnabled = value);
            _runSearch();
          },
        ),
        if (_advancedEnabled)
          AdvancedQueryBuilder(
            root: _advancedRoot,
            taxonomy: data.taxonomy,
            sectionLabels: data.sectionLabels,
            onChanged: _onAdvancedChanged,
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
    // Lazily built so large collections stay virtualized (only visible rows
    // are constructed).
    return SliverList.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
        return Dismissible(
          key: ValueKey('dismissible-${entry.dance.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) =>
              _softDeleteFromList(entry.dance.id, entry.dance.title),
          background: Container(
            alignment: Alignment.centerRight,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          child: DanceListTile(
            entry: entry,
            onTap: () async {
              // DanceDetailScreen pops with true when a dance is deleted so
              // the Collection can reload and remove the stale row immediately.
              final deleted = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => DanceDetailScreen(danceId: entry.dance.id),
                ),
              );
              if (mounted && deleted == true) await _boot();
            },
          ),
        );
      },
    );
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
}

/// Reference/vocabulary data loaded once for the Collection, used both to build
/// facet controls and to hydrate search-result ids into [DanceListEntry]s
/// without re-querying per row.
class _CollectionData {
  _CollectionData({
    required this.dancesById,
    required this.choreographerNames,
    required this.tagNames,
    required this.customFieldDefs,
    required this.listFieldDefs,
    required this.choiceFields,
    required this.booleanFields,
    required this.textFields,
    required this.numberFields,
    required this.lastCalled,
    required this.authors,
    required this.tags,
    required this.forms,
    required this.formations,
    required this.progressions,
    required this.statuses,
    required this.taxonomy,
    required this.sectionLabels,
  });

  final Map<String, Dance> dancesById;
  final Map<String, String> choreographerNames;
  final Map<String, String> tagNames;
  final List<CustomFieldDef> customFieldDefs;
  final List<CustomFieldDef> listFieldDefs;
  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
  final List<CustomFieldDef> textFields;
  final List<CustomFieldDef> numberFields;
  final Map<String, DateTime> lastCalled;
  final List<Choreographer> authors;
  final List<Tag> tags;
  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;

  static Future<_CollectionData> load(CompendiumRepositories repos) async {
    final dances = await repos.dances.listAll();
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final defs = await repos.customFieldDefs.listAll();
    final lastCalled = await repos.programs.lastCalledByDance();

    final dancesById = {for (final d in dances) d.id: d};
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};

    // Facet vocabularies: only values actually present in the collection, so
    // empty facets don't clutter the panel (matching the Phase 3.1 approach).
    final forms = dances.map((d) => d.form).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final formations = dances.map((d) => d.formation.shape).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final progressions = dances.map((d) => d.progression).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final statuses = dances.map((d) => d.status).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final usedAuthorIds = {for (final d in dances) ...d.authorIds};
    final usedTagIds = {for (final d in dances) ...d.tagIds};
    final authors =
        choreographers.where((c) => usedAuthorIds.contains(c.id)).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final tagList = tags.where((t) => usedTagIds.contains(t.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final searchable = defs.where((d) => d.searchable).toList();

    return _CollectionData(
      dancesById: dancesById,
      choreographerNames: choreographerNames,
      tagNames: tagNames,
      customFieldDefs: defs,
      listFieldDefs: defs.where((d) => d.showInList).toList(),
      choiceFields: searchable
          .where((d) => d.type == CustomFieldType.choice)
          .toList(),
      booleanFields: searchable
          .where((d) => d.type == CustomFieldType.boolean)
          .toList(),
      textFields: searchable
          .where((d) => d.type == CustomFieldType.text)
          .toList(),
      numberFields: searchable
          .where((d) => d.type == CustomFieldType.number)
          .toList(),
      lastCalled: lastCalled,
      authors: authors,
      tags: tagList,
      forms: forms,
      formations: formations,
      progressions: progressions,
      statuses: statuses,
      taxonomy: contraTaxonomy,
      sectionLabels: PhraseStructure.standard.labels,
    );
  }

  DanceListEntry entryFor(Dance dance) => DanceListEntry(
    dance: dance,
    authorNames: [
      for (final id in dance.authorIds)
        if (choreographerNames[id] != null) choreographerNames[id]!,
    ],
    tagNames: [
      for (final id in dance.tagIds)
        if (tagNames[id] != null) tagNames[id]!,
    ],
    listCustomFields: [
      for (final def in listFieldDefs)
        for (final value in dance.customFields)
          if (value.fieldId == def.id) '${def.label}: ${value.value}',
    ],
    lastCalled: lastCalled[dance.id],
  );
}
