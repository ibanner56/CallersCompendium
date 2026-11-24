// Saved searches in the collection picker (#2325): the same dropdown as the
// Collection's, loading through the picker's one entry point for a panel
// state, so a search saved in one host loads the same in the other.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/collection_search_controls.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final _clock = FixedSearchClock(
  DateTime.utc(2026, 11, 22, 11, 5),
  const Duration(hours: 13),
);
final _day = DateTime.utc(2026, 11, 23);

Dance _dance(String id, String title, {List<String> tagIds = const []}) =>
    Dance(
      id: id,
      title: title,
      authorIds: const [],
      tagIds: tagIds,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: const [],
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<CompendiumRepositories> _library() async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'Bouncey'));
  await repos.dances.create(_dance('a', 'Petronella', tagIds: const ['t1']));
  await repos.dances.create(_dance('b', 'Chorus Jig'));
  await repos.dances.create(_dance('c', 'Rory O More'));
  return repos;
}

/// A host that rebuilds its picker on every change to the program, as the
/// program editor does.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.data,
    this.enableOnlineSearch = false,
    this.contraDbOnline,
  });

  final CollectionData data;
  final bool enableOnlineSearch;
  final ContraDbOnline? contraDbOnline;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var programChanges = 0;

  void programChanged() => setState(() => programChanges++);

  @override
  Widget build(BuildContext context) => CollectionPicker(
    data: widget.data,
    dialect: Dialect.larksRobins,
    enrichment: SearchEnrichment.empty,
    onAddDance: (_) {},
    addedDanceCounts: {'program-change-$programChanges': 1},
    enableOnlineSearch: widget.enableOnlineSearch,
    contraDbOnline: widget.contraDbOnline,
    clock: _clock,
  );
}

Widget _app(CompendiumRepositories repos, Widget home) {
  final ignoreArticles = ValueNotifier<bool>(true);
  return MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    builder: (context, child) => RepositoriesScope(
      repositories: repos,
      child: SortIgnoreArticlesScope(notifier: ignoreArticles, child: child!),
    ),
    home: home,
  );
}

Future<GlobalKey<_HostState>> _pumpPicker(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool enableOnlineSearch = false,
  ContraDbOnline? contraDbOnline,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final data = await CollectionData.load(repos);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    _app(
      repos,
      Scaffold(
        body: _Host(
          key: key,
          data: data,
          enableOnlineSearch: enableOnlineSearch,
          contraDbOnline: contraDbOnline,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> _pumpCollection(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  addTearDown(theme.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  final ignoreArticles = ValueNotifier<bool>(true);
  addTearDown(ignoreArticles.dispose);
  final filter = CollectionFilterController();
  addTearDown(filter.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: SortIgnoreArticlesScope(
                notifier: ignoreArticles,
                child: CollectionFilterScope(controller: filter, child: child!),
              ),
            ),
          ),
        ),
      ),
      home: DanceListScreen(clock: _clock),
    ),
  );
  await tester.pumpAndSettle();
}

bool _shows(String title) => find.text(title).evaluate().isNotEmpty;

String _pickerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('picker-search')))
    .controller!
    .text;

/// Loads [search] through the picker's search-field dropdown.
Future<void> _loadInPicker(WidgetTester tester, SavedSearch search) async {
  await tester.tap(find.byKey(const ValueKey('picker-search')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('saved-search-row-${search.id}')));
  await tester.pumpAndSettle();
}

/// Loads [search] through the Collection's search-field dropdown.
Future<void> _loadInCollection(WidgetTester tester, SavedSearch search) async {
  await tester.tap(find.byKey(const ValueKey('collection-search-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('saved-search-row-${search.id}')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Saves the Collection's search as [name] through its ⋮ menu.
Future<void> _saveAs(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
  await _choose(tester, 'saved-search-save');
  await tester.enterText(
    find.byKey(const ValueKey('saved-search-name-field')),
    name,
  );
  await tester.pumpAndSettle();
  await _choose(tester, 'saved-search-name-save');
}

Future<SavedSearch> _byName(CompendiumRepositories repos, String name) async =>
    [
      for (final s in await repos.savedSearches.list()) ?s.search,
    ].singleWhere((s) => s.name == name);

/// A search touching text, Search in, a filter, an Advanced row and the
/// sort with its direction.
CollectionPanelState _rich() {
  final state = CollectionPanelState(
    text: 'Petronella',
    scope: FullTextScope.title,
    sort: CollectionSort.recentlyAdded,
    sortDirection: SortDirection.ascending,
    advanced: BuilderGroup(children: [BuilderTag(tagId: 't1')]),
  );
  state.facets.setTag('t1', selected: true);
  return state;
}

CollectionSort _pickerSort(WidgetTester tester) => tester
    .widget<CollectionSortMenuButton>(find.byKey(const ValueKey('picker-sort')))
    .sort;

FullTextScope _pickerScope(WidgetTester tester) =>
    tester.widget<SearchScopeField>(find.byType(SearchScopeField)).scope;

void main() {
  testWidgets('a search saved in the Collection loads in the picker as the '
      'same search, with the same dances, and back again', (tester) async {
    final repos = await _library();
    await _pumpCollection(tester, repos);
    (tester.state(find.byType(DanceListScreen)) as DanceListCommands)
        .applyPanelState(_rich());
    await tester.pumpAndSettle();
    await _saveAs(tester, 'Rich');
    final saved = await _byName(repos, 'Rich');

    await _pumpPicker(tester, repos);
    expect(_shows('Chorus Jig'), isTrue);
    await _loadInPicker(tester, saved);

    expect(_pickerText(tester), 'Petronella');
    expect(_pickerScope(tester), FullTextScope.title);
    expect(_pickerSort(tester), CollectionSort.recentlyAdded);
    expect(find.text('Filters · 1'), findsOneWidget);
    expect(find.text('Advanced (on)'), findsOneWidget);
    expect(_shows('Petronella'), isTrue);
    expect(_shows('Chorus Jig'), isFalse);
    expect(_shows('Rory O More'), isFalse);

    // Back in the Collection, the same search loads, and saved again it is
    // the same search, byte for byte.
    await _pumpCollection(tester, repos);
    await _loadInCollection(tester, saved);
    await tester.tapAt(const Offset(1100, 2900));
    await tester.pumpAndSettle();
    await _saveAs(tester, 'Copy');
    expect((await _byName(repos, 'Copy')).spec.toJson(), saved.spec.toJson());
  });

  testWidgets('the picker only loads: it has no way to save or manage', (
    tester,
  ) async {
    final repos = await _library();
    await _pumpPicker(tester, repos);

    expect(find.byKey(const ValueKey('saved-search-save')), findsNothing);
    expect(find.byKey(const ValueKey('collection-more-actions')), findsNothing);
  });

  testWidgets('a loaded search is not put back over an edit when the '
      'program changes', (tester) async {
    final repos = await _library();
    final saved = await repos.savedSearches.create(
      name: 'Pet',
      spec: SavedSearchSpec.fromPanelState(
        CollectionPanelState(text: 'Petronella'),
        today: _day,
      ).value!,
    );
    final host = await _pumpPicker(tester, repos);
    await _loadInPicker(tester, saved);
    expect(_pickerText(tester), 'Petronella');

    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Chorus',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    host.currentState!.programChanged();
    await tester.pumpAndSettle();
    host.currentState!.programChanged();
    await tester.pumpAndSettle();

    expect(_pickerText(tester), 'Chorus');
    expect(_shows('Chorus Jig'), isTrue);
    expect(_shows('Petronella'), isFalse);
  });

  testWidgets('there is no dropdown while Online search is on', (tester) async {
    final repos = await _library();
    final saved = await repos.savedSearches.create(
      name: 'Pet',
      spec: SavedSearchSpec.fromPanelState(
        CollectionPanelState(text: 'Petronella'),
        today: _day,
      ).value!,
    );
    await _pumpPicker(
      tester,
      repos,
      enableOnlineSearch: true,
      contraDbOnline: ContraDbOnline(
        searchFetcher: (_) async => '{"numberMatching":0,"dances":[]}',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('picker-online-search-enable')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('picker-search')));
    await tester.enterText(find.byKey(const ValueKey('picker-search')), 'pe');
    await tester.pump();

    expect(find.byKey(const ValueKey('saved-search-dropdown')), findsNothing);
    expect(find.byKey(ValueKey('saved-search-row-${saved.id}')), findsNothing);
  });

  testWidgets("the picker counts a window back from the caller's own day", (
    tester,
  ) async {
    // 2026-11-22 11:05 UTC is 2026-11-23 at +13:00: "Not called in the last
    // month" starts on 2026-10-23, so a dance last called on 2026-10-22 is
    // listed. From the UTC day it would start on 2026-10-22 and leave it out.
    final repos = openTestRepositories();
    await repos.dances.create(_dance('edge', 'Edge Reel'));
    await repos.dances.create(_dance('recent', 'Recent Reel'));
    Program program(String id, String danceId, DateTime date) => Program(
      id: id,
      title: id,
      eventDate: date,
      slots: [ProgramSlot(id: '$id-s', position: 0, danceId: danceId)],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await repos.programs.create(
      program('p1', 'edge', DateTime.utc(2026, 10, 22)),
    );
    await repos.programs.create(
      program('p2', 'recent', DateTime.utc(2026, 11, 20)),
    );
    final state = CollectionPanelState();
    state.facets.callStatuses.add(false);
    state.facets.setHistoryMonths(1);
    final saved = await repos.savedSearches.create(
      name: 'Not lately',
      spec: SavedSearchSpec.fromPanelState(state, today: _day).value!,
    );
    await _pumpPicker(tester, repos);

    await _loadInPicker(tester, saved);

    expect(_shows('Edge Reel'), isTrue);
    expect(_shows('Recent Reel'), isFalse);
  });
}
