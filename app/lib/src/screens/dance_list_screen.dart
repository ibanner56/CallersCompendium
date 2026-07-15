import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import '../search/collection_data.dart';
import '../search/collection_query.dart';
import '../widgets/advanced_query_builder.dart';
import '../widgets/batch_tag_dialog.dart';
import '../widgets/dance_list_tile.dart';
import '../widgets/facet_panel.dart';
import '../screens/custom_fields_screen.dart';
import '../screens/recently_deleted_screen.dart';
import '../screens/settings_screen.dart';
import 'dance_detail_screen.dart';
import 'dance_editor_screen.dart';

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
/// [refreshTrigger] allows a parent widget to request a full list reload by
/// incrementing the notifier value (e.g. after a detail-pane delete/restore).
class DanceListScreen extends StatefulWidget {
  const DanceListScreen({
    super.key,
    this.onSelectDance,
    this.selectedDanceId,
    this.refreshTrigger,
  });

  /// Called with the tapped dance's id when the split-pane shell needs to
  /// control navigation. Null ⇒ use the standard [Navigator.push] route.
  final void Function(String danceId)? onSelectDance;

  /// Id of the currently selected dance for row highlighting in split-pane
  /// mode. Has no effect when [onSelectDance] is null.
  final String? selectedDanceId;

  /// When non-null, the list calls [_boot] whenever this notifier's value
  /// changes — allowing the [CollectionShell] to trigger a refresh after a
  /// delete or restore in the detail pane.
  final ValueListenable<int>? refreshTrigger;

  @override
  State<DanceListScreen> createState() => _DanceListScreenState();
}

class _DanceListScreenState extends State<DanceListScreen> {
  /// Active dialect for search canonicalization — read from [ActiveDialectScope]
  /// in [didChangeDependencies] and updated live when the user changes it.
  Dialect _dialect = Dialect.larksRobins;

  static const Duration _debounce = Duration(milliseconds: 250);

  final _ftsController = TextEditingController();
  final _facets = FacetSelections();
  final _advancedRoot = BuilderGroup();
  bool _advancedEnabled = false;

  CollectionSort _sort = CollectionSort.title;

  late CompendiumRepositories _repos;
  bool _started = false;

  CollectionData? _data;
  Object? _loadError;

  List<DanceListEntry> _results = const [];
  bool _searching = false;
  Object? _searchError;
  int _searchSeq = 0;

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

    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
      _boot();
    } else if (dialectChanged) {
      _runSearch();
    }
  }

  @override
  void didUpdateWidget(DanceListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      oldWidget.refreshTrigger?.removeListener(_onRefreshTriggered);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
    }
  }

  void _onRefreshTriggered() {
    if (mounted) _boot();
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    _debounceTimer?.cancel();
    _ftsController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final data = await CollectionData.load(_repos);
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
    final count = priorTags.length;
    final message = count == 0
        ? 'No changes'
        : '${mode == BatchTagMode.add ? 'Tagged' : 'Removed tags from'} '
              '$count ${count == 1 ? 'dance' : 'dances'}';
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );

    _exitSelectionMode();
    await _boot();
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
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('batch-tag-snackbar'),
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoBatchTag(priorTags),
        ),
      ),
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
    if (mounted) await _boot();
  }

  @override
  Widget build(BuildContext context) {
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
              label: const Text('New dance'),
            ),
    );
  }

  PreferredSizeWidget _buildDefaultAppBar() {
    return AppBar(
      title: const Text('Collection'),
      actions: [
        if (_data != null) ...[
          IconButton(
            key: const ValueKey('batch-select'),
            tooltip: 'Select dances',
            icon: const Icon(Icons.checklist),
            onPressed: _results.isEmpty ? null : () => _enterSelectionMode(),
          ),
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
          IconButton(
            key: const ValueKey('settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          PopupMenuButton<CollectionSort>(
            tooltip: 'Sort by (${_sort.label})',
            initialValue: _sort,
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() => _sort = value);
              _runSearch();
            },
            itemBuilder: (context) => [
              for (final option in _availableSorts)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final count = _selectedIds.length;
    final hasSelection = count > 0;
    return AppBar(
      leading: IconButton(
        key: const ValueKey('batch-exit'),
        tooltip: 'Exit selection',
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Semantics(liveRegion: true, child: Text('$count selected')),
      actions: [
        IconButton(
          key: const ValueKey('batch-add-tags'),
          tooltip: 'Add tags',
          icon: const Icon(Icons.new_label_outlined),
          onPressed: hasSelection ? () => _batchTag(BatchTagMode.add) : null,
        ),
        IconButton(
          key: const ValueKey('batch-remove-tags'),
          tooltip: 'Remove tags',
          icon: const Icon(Icons.label_off_outlined),
          onPressed: hasSelection ? () => _batchTag(BatchTagMode.remove) : null,
        ),
      ],
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

  Future<void> _openSettings() async {
    final dialectBefore = _dialect;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    // didChangeDependencies fires a re-run when the dialect changes; only do
    // an extra re-run here if the dialect is unchanged (belt-and-suspenders
    // for edge cases where didChangeDependencies doesn't fire after pop).
    if (mounted && _dialect == dialectBefore) await _runSearch();
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

  Widget _buildFiltersPanel(CollectionData data) {
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
          levels: data.levels,
          hasMixedLevel: data.hasMixedLevel,
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

  Widget _buildAdvancedPanel(CollectionData data) {
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
        final tile = DanceListTile(
          entry: entry,
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
                  // onRestored is called if the user taps Undo, so the
                  // restored dance reappears in the list without a manual
                  // reload.
                  final deleted = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => DanceDetailScreen(
                        danceId: entry.dance.id,
                        onRestored: () {
                          if (mounted) _boot();
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
          return KeyedSubtree(
            key: ValueKey('row-${entry.dance.id}'),
            child: tile,
          );
        }
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
          child: tile,
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
        _facets.sourceIds.length +
        _facets.choiceValues.values.fold<int>(0, (a, s) => a + s.length) +
        _facets.booleanValues.length +
        _facets.textValues.values.where((s) => s.isEffective).length +
        _facets.numberValues.values.where((s) => s.isEffective).length;
  }
}
