// The Collection opening a whole panel state (DanceListCommands
// .applyPanelState, #2325): every part replaced, the sort included, and the
// user's last-used Collection sort left as it was.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/widgets/collection_search_controls.dart';
import 'package:compendium_app/src/widgets/online_search_toggle.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

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

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos, {
  ContraDbOnline? contraDbOnline,
}) async {
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
      home: DanceListScreen(contraDbOnline: contraDbOnline),
    ),
  );
  await tester.pumpAndSettle();
}

DanceListCommands _list(WidgetTester tester) =>
    tester.state(find.byType(DanceListScreen)) as DanceListCommands;

CollectionSort _sort(WidgetTester tester) => tester
    .widget<CollectionSortMenuButton>(find.byType(CollectionSortMenuButton))
    .sort;

SortDirection _direction(WidgetTester tester) => tester
    .widget<SortDirectionButton>(find.byType(SortDirectionButton))
    .direction;

bool _shows(String title) => find.text(title).evaluate().isNotEmpty;

FullTextScope _scope(WidgetTester tester) =>
    tester.widget<SearchScopeField>(find.byType(SearchScopeField)).scope;

Future<void> _openFilters(WidgetTester tester) async {
  final panel = find.byKey(const ValueKey('filters-panel'));
  await tester.ensureVisible(panel);
  await tester.tap(panel);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening a state with a sort leaves the last-used sort alone', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(_dance('a', 'Petronella', tagIds: const ['t1']));
    await repos.dances.create(_dance('b', 'Chorus Jig'));
    await repos.settings.set(kLastUsedCollectionSortKey, 'title');
    await repos.settings.set(kLastUsedCollectionSortDirectionKey, 'ascending');
    await _pumpScreen(tester, repos);
    expect(_shows('Chorus Jig'), isTrue);

    // Its own default direction, so only what is written can differ.
    final state = CollectionPanelState(sort: CollectionSort.recentlyAdded);
    state.facets.setTag('t1', selected: true);
    _list(tester).applyPanelState(state);
    await tester.pumpAndSettle();

    expect(_sort(tester), CollectionSort.recentlyAdded);
    expect(
      _direction(tester),
      CollectionSort.recentlyAdded.searchSort.defaultDirection,
    );
    expect(_shows('Petronella'), isTrue);
    expect(_shows('Chorus Jig'), isFalse);
    // A search someone opened is not a sort the user chose.
    expect(await repos.settings.get(kLastUsedCollectionSortKey), 'title');
    expect(
      await repos.settings.get(kLastUsedCollectionSortDirectionKey),
      'ascending',
    );
  });

  testWidgets('every part is replaced, including the sort and Search in that '
      'Clear all leaves alone', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(_dance('a', 'Petronella', tagIds: const ['t1']));
    await repos.dances.create(_dance('b', 'Chorus Jig'));
    await _pumpScreen(tester, repos);
    // The user picks a sort, as from the Sort menu.
    tester
        .widget<CollectionSortMenuButton>(find.byType(CollectionSortMenuButton))
        .onSelected(CollectionSort.recentlyAdded);
    await tester.pumpAndSettle();
    expect(_sort(tester), CollectionSort.recentlyAdded);

    expect(_scope(tester), FullTextScope.omni);
    final first = CollectionPanelState(
      text: 'Petronella',
      scope: FullTextScope.title,
      sort: CollectionSort.author,
      sortDirection: SortDirection.descending,
    );
    first.facets.setTag('t1', selected: true);
    _list(tester).applyPanelState(first);
    await tester.pumpAndSettle();
    expect(_shows('Chorus Jig'), isFalse);
    expect(_sort(tester), CollectionSort.author);
    expect(_direction(tester), SortDirection.descending);
    expect(_scope(tester), FullTextScope.title);

    // An empty state: nothing of the first survives.
    _list(tester).applyPanelState(CollectionPanelState());
    await tester.pumpAndSettle();
    expect(_sort(tester), CollectionSort.title);
    expect(_direction(tester), SortDirection.ascending);
    expect(_scope(tester), FullTextScope.omni);
    expect(_shows('Chorus Jig'), isTrue);
    expect(_shows('Petronella'), isTrue);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .any((f) => f.controller?.text == 'Petronella'),
      isFalse,
    );
  });

  testWidgets('a state naming a tag, level, author and source no dance has '
      'shows each by its name', (tester) async {
    // Proves CollectionData.load reads every name and the Collection hands
    // them to the Filters panel.
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 'fam', name: 'family'));
    final level = await repos.difficultyLevels.createCustom(
      label: 'Gnarly',
      position: 9,
    );
    await repos.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Gene Hubert'),
    );
    await repos.publishedSources.upsert(
      PublishedSource(id: 's1', title: 'Zesty Contras'),
    );
    await repos.dances.create(_dance('b', 'Chorus Jig'));
    await _pumpScreen(tester, repos);

    final state = CollectionPanelState();
    state.facets
      ..setTag('fam', selected: true)
      ..levels.add(level.id)
      ..authorIds.add('c1')
      ..sourceIds.add('s1');
    _list(tester).applyPanelState(state);
    await tester.pumpAndSettle();
    await _openFilters(tester);

    String chipText(String key) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;
    expect(chipText('tag-fam'), 'family');
    expect(chipText('level-id-${level.id}'), 'Gnarly');
    expect(chipText('author-facet-chip-c1'), 'Gene Hubert');
    expect(chipText('source-s1'), 'Zesty Contras');
    // Kept through the data emits since: a search for a tag nobody has yet.
    expect(state.facets.tagIds, {'fam'});
  });

  testWidgets('a state handed over while online search is on leaves it, '
      'and none of the old tree\'s tag rows reach the new tree', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(_dance('a', 'Petronella', tagIds: const ['t1']));
    await _pumpScreen(
      tester,
      repos,
      contraDbOnline: ContraDbOnline(
        searchFetcher: (_) async => '{"numberMatching":0,"dances":[]}',
      ),
    );
    final first = CollectionPanelState(
      advanced: BuilderGroup(
        children: [
          BuilderTag(tagId: 't1'),
          BuilderFigure(move: 'swing'),
        ],
      ),
    );
    _list(tester).applyPanelState(first);
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('online-search-enable'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ContraDB'));
    await tester.pumpAndSettle();
    expect(first.advanced.children.whereType<BuilderTag>(), isEmpty);

    final second = CollectionPanelState(
      advanced: BuilderGroup(children: [BuilderFigure(move: 'swing')]),
    );
    _list(tester).applyPanelState(second);
    await tester.pumpAndSettle();

    expect(tester.widget<OnlineSearchToggle>(toggle).enabled, isFalse);
    expect(second.advanced.children.whereType<BuilderTag>(), isEmpty);
    expect(second.advanced.children, hasLength(1));
    expect(first.advanced.children.whereType<BuilderTag>(), hasLength(1));
  });
}
