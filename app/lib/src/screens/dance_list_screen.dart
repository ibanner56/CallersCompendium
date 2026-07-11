import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../models/dance_list_entry.dart';
import 'dance_detail_screen.dart';

/// Collection screen: browse, sort, and lightly filter the dance library
/// (docs/design/ux.md §1). The unified full-text search bar and structured
/// query-builder filter panel described alongside this screen in ux.md are
/// out of scope here — they land in roadmap item 3.2. This screen offers a
/// simple client-side quick-filter (title/author text match) plus
/// tag/formation toggle chips over the already-loaded list.
class DanceListScreen extends StatefulWidget {
  const DanceListScreen({super.key});

  @override
  State<DanceListScreen> createState() => _DanceListScreenState();
}

class _DanceListScreenState extends State<DanceListScreen> {
  late Future<List<DanceListEntry>> _future;

  DanceSort _sort = DanceSort.title;
  final _filterController = TextEditingController();
  String _filterText = '';
  final Set<String> _selectedTags = {};
  final Set<FormationShape> _selectedFormations = {};

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filterText = _filterController.text.trim().toLowerCase());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load(RepositoriesScope.of(context));
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<List<DanceListEntry>> _load(CompendiumRepositories repos) async {
    final dances = await repos.dances.listAll();
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final listFieldDefs = (await repos.customFieldDefs.listAll())
        .where((def) => def.showInList)
        .toList();
    final lastCalled = await repos.programs.lastCalledByDance();

    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};

    return [
      for (final dance in dances)
        DanceListEntry(
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
        ),
    ];
  }

  void _retry() {
    setState(() => _future = _load(RepositoriesScope.of(context)));
  }

  List<DanceListEntry> _applyFilters(List<DanceListEntry> entries) {
    var result = entries.where((e) {
      if (_filterText.isNotEmpty && !e.filterText.contains(_filterText)) {
        return false;
      }
      if (_selectedTags.isNotEmpty && !e.tagNames.any(_selectedTags.contains)) {
        return false;
      }
      if (_selectedFormations.isNotEmpty &&
          !_selectedFormations.contains(e.dance.formation.shape)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) {
      switch (_sort) {
        case DanceSort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case DanceSort.author:
          final aName = a.authorNames.isEmpty
              ? ''
              : a.authorNames.first.toLowerCase();
          final bName = b.authorNames.isEmpty
              ? ''
              : b.authorNames.first.toLowerCase();
          final cmp = aName.compareTo(bName);
          return cmp != 0
              ? cmp
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case DanceSort.recentlyAdded:
          return b.dance.createdAt.compareTo(a.dance.createdAt);
        case DanceSort.lastCalled:
          // Never-called dances sort after called ones, most-recent first.
          if (a.lastCalled == null && b.lastCalled == null) {
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }
          if (a.lastCalled == null) return 1;
          if (b.lastCalled == null) return -1;
          return b.lastCalled!.compareTo(a.lastCalled!);
      }
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          PopupMenuButton<DanceSort>(
            tooltip: 'Sort by',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final option in DanceSort.values)
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
      ),
      body: FutureBuilder<List<DanceListEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading dances',
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  const Text('Could not load the collection.'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }

          final allEntries = snapshot.data ?? const [];
          if (allEntries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your collection is empty. Add or import a dance to '
                  'get started.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final availableTags =
              (allEntries.expand((e) => e.tagNames).toSet().toList())..sort();
          final availableFormations =
              allEntries.map((e) => e.dance.formation.shape).toSet().toList()
                ..sort(
                  (a, b) =>
                      formationShapeLabel(a).compareTo(formationShapeLabel(b)),
                );

          final visible = _applyFilters(allEntries);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _filterController,
                  decoration: const InputDecoration(
                    labelText: 'Filter dances',
                    hintText: 'Filter by title or author',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (availableTags.isNotEmpty || availableFormations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final formation in availableFormations)
                          FilterChip(
                            label: Text(formationShapeLabel(formation)),
                            avatar: const Icon(Icons.grid_view, size: 18),
                            selected: _selectedFormations.contains(formation),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _selectedFormations.add(formation)
                                  : _selectedFormations.remove(formation);
                            }),
                          ),
                        for (final tag in availableTags)
                          FilterChip(
                            label: Text(tag),
                            avatar: const Icon(Icons.label_outline, size: 18),
                            selected: _selectedTags.contains(tag),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _selectedTags.add(tag)
                                  : _selectedTags.remove(tag);
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${visible.length} '
                      '${visible.length == 1 ? 'dance' : 'dances'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text('No dances match the current filters.'),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _DanceListTile(entry: visible[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DanceListTile extends StatelessWidget {
  const _DanceListTile({required this.entry});

  final DanceListEntry entry;

  @override
  Widget build(BuildContext context) {
    final dance = entry.dance;
    final theme = Theme.of(context);

    return ListTile(
      title: Text(dance.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (entry.authorNames.isNotEmpty)
              Text(
                entry.authorNames.join(', '),
                style: theme.textTheme.bodyMedium,
              ),
            Chip(
              avatar: const Icon(Icons.grid_view, size: 16),
              label: Text(formationLabel(dance.formation)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            if (dance.status != DanceStatus.active)
              Chip(
                avatar: Icon(
                  dance.status == DanceStatus.deprecated
                      ? Icons.history_toggle_off
                      : Icons.report_problem_outlined,
                  size: 16,
                ),
                label: Text(
                  dance.status == DanceStatus.deprecated
                      ? 'Deprecated'
                      : 'Broken',
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            for (final tag in entry.tagNames)
              Chip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            for (final field in entry.listCustomFields)
              Chip(
                label: Text(field),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
      isThreeLine: false,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DanceDetailScreen(danceId: dance.id)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
