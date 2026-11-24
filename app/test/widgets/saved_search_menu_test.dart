// The Saved menu in the Collection (#2325): save the search on screen, load a
// saved one, update, rename and delete it with Undo, against a real in-memory
// database. The picker's copy of the menu is tested in
// saved_search_picker_test.dart.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/widgets/collection_search_controls.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// 2026-11-22 11:05 UTC, in a zone 13 hours ahead: there it is already the
/// 23rd. Every test reads this clock, so none depends on the machine's.
final _clock = FixedSearchClock(
  DateTime.utc(2026, 11, 22, 11, 5),
  const Duration(hours: 13),
);

/// The caller's day on [_clock].
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
  return repos;
}

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  SearchClock? clock,
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
      home: DanceListScreen(
        clock: clock ?? _clock,
        contraDbOnline: contraDbOnline,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DanceListCommands _list(WidgetTester tester) =>
    tester.state(find.byType(DanceListScreen)) as DanceListCommands;

bool _shows(String title) => find.text(title).evaluate().isNotEmpty;

String _searchText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('collection-search-field')))
    .controller!
    .text;

CollectionSort _sort(WidgetTester tester) => tester
    .widget<CollectionSortMenuButton>(find.byType(CollectionSortMenuButton))
    .sort;

SortDirection _direction(WidgetTester tester) => tester
    .widget<SortDirectionButton>(find.byType(SortDirectionButton))
    .direction;

FullTextScope _scope(WidgetTester tester) =>
    tester.widget<SearchScopeField>(find.byType(SearchScopeField)).scope;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('saved-search-menu')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<MenuItemButton>(find.byKey(ValueKey(key))).onPressed != null;

/// Saves the search on screen as [name] through the menu.
Future<void> _saveAs(WidgetTester tester, String name, {String? entry}) async {
  await _openMenu(tester);
  await _choose(tester, entry ?? 'saved-search-save');
  await tester.enterText(
    find.byKey(const ValueKey('saved-search-name-field')),
    name,
  );
  await tester.pumpAndSettle();
  await _choose(tester, 'saved-search-name-save');
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('collection-search-field')),
    text,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<SavedSearch> _seed(
  CompendiumRepositories repos,
  String name,
  CollectionPanelState state,
) async => repos.savedSearches.create(
  name: name,
  spec: SavedSearchSpec.fromPanelState(state, today: _day).value!,
);

Future<List<SavedSearch>> _readable(CompendiumRepositories repos) async => [
  for (final s in await repos.savedSearches.list()) ?s.search,
];

void main() {
  testWidgets('Save this search… is offered only once a query is set, and '
      'saves the name and the whole search', (tester) async {
    final repos = await _library();
    await _pump(tester, repos);

    await _openMenu(tester);
    expect(_enabled(tester, 'saved-search-save'), isFalse);
    expect(find.byKey(const ValueKey('saved-search-none')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _type(tester, 'Petronella');
    await _saveAs(tester, 'Just the one');

    final saved = await _readable(repos);
    expect(saved.map((s) => s.name), ['Just the one']);
    expect(saved.single.spec.toJson()['text'], 'Petronella');
    expect(find.text('Saved "Just the one"'), findsOneWidget);
  });

  testWidgets('the save dialog says what is kept of a chosen date: the whole '
      'months back from today', (tester) async {
    final repos = await _library();
    await _pump(tester, repos);
    final state = CollectionPanelState();
    state.facets.callStatuses.add(false);
    // A year before the caller's day, which is the 23rd in their zone.
    state.facets.setHistorySince(DateTime.utc(2025, 11, 23));
    _list(tester).applyPanelState(state);
    await tester.pumpAndSettle();

    await _openMenu(tester);
    await _choose(tester, 'saved-search-save');

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('saved-search-window')))
          .data,
      'Not called in the last 12 months',
    );
    await tester.enterText(
      find.byKey(const ValueKey('saved-search-name-field')),
      'A year',
    );
    await tester.pumpAndSettle();
    await _choose(tester, 'saved-search-name-save');
    final facets = (await _readable(repos)).single.spec.toJson()['facets'];
    expect((facets as Map)['historyMonths'], 12);
  });

  testWidgets('choosing a saved search shows all of it and runs it, and '
      'leaves the last-used sort alone', (tester) async {
    final repos = await _library();
    await repos.settings.set(kLastUsedCollectionSortKey, 'title');
    await repos.settings.set(kLastUsedCollectionSortDirectionKey, 'ascending');
    final state = CollectionPanelState(
      text: 'Petronella',
      scope: FullTextScope.title,
      sort: CollectionSort.recentlyAdded,
      sortDirection: SortDirection.ascending,
    );
    state.facets.setTag('t1', selected: true);
    final search = await _seed(repos, 'Bouncey ones', state);
    await _pump(tester, repos);
    expect(_shows('Chorus Jig'), isTrue);

    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    expect(_searchText(tester), 'Petronella');
    expect(_scope(tester), FullTextScope.title);
    expect(_sort(tester), CollectionSort.recentlyAdded);
    expect(_direction(tester), SortDirection.ascending);
    expect(find.text('Filters · 1'), findsOneWidget);
    expect(_shows('Petronella'), isTrue);
    expect(_shows('Chorus Jig'), isFalse);
    // A search someone opened is not a sort the user chose.
    expect(await repos.settings.get(kLastUsedCollectionSortKey), 'title');
    expect(
      await repos.settings.get(kLastUsedCollectionSortDirectionKey),
      'ascending',
    );
  });

  testWidgets('Update appears once the loaded search is changed, writes the '
      'change back, and then goes away again', (tester) async {
    final repos = await _library();
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    await _openMenu(tester);
    expect(find.byKey(const ValueKey('saved-search-update')), findsNothing);
    expect(find.text('Save this search…'), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-search-rename')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _type(tester, 'Chorus');
    await _openMenu(tester);
    expect(find.text('Update "Pet"'), findsOneWidget);
    expect(find.text('Save as new…'), findsOneWidget);
    await _choose(tester, 'saved-search-update');

    final stored = await repos.savedSearches.get(search.id);
    expect(stored!.spec.toJson()['text'], 'Chorus');
    expect(stored.name, 'Pet');
    await _openMenu(tester);
    expect(find.byKey(const ValueKey('saved-search-update')), findsNothing);
  });

  testWidgets('Save as new… keeps the loaded search and adds a second', (
    tester,
  ) async {
    final repos = await _library();
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');
    await _type(tester, 'Chorus');

    await _saveAs(tester, 'Chorus');

    final saved = await _readable(repos);
    expect(saved.map((s) => s.name), ['Chorus', 'Pet']);
    expect(saved.last.spec.toJson()['text'], 'Petronella');
    expect(saved.first.spec.toJson()['text'], 'Chorus');
  });

  testWidgets('Rename keeps what is saved and changes the name', (
    tester,
  ) async {
    final repos = await _library();
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');
    // An edit on screen is not part of a rename.
    await _type(tester, 'Chorus');

    await _openMenu(tester);
    await _choose(tester, 'saved-search-rename');
    await tester.enterText(
      find.byKey(const ValueKey('saved-search-name-field')),
      'Petronella only',
    );
    await tester.pumpAndSettle();
    await _choose(tester, 'saved-search-name-save');

    final stored = await repos.savedSearches.get(search.id);
    expect(stored!.name, 'Petronella only');
    expect(stored.spec.toJson()['text'], 'Petronella');
  });

  testWidgets('Delete tombstones the saved search and Undo brings the same '
      'one back', (tester) async {
    final repos = await _library();
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    final key = search.settingsKey;
    final before = await repos.settings.get(key);
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    await _openMenu(tester);
    await _choose(tester, 'saved-search-delete');

    expect(await repos.settings.get(key), isNull);
    expect(await repos.settings.keysWithPrefix(savedSearchKeyPrefix), isEmpty);
    expect(find.text('Deleted "Pet"'), findsOneWidget);
    // Nothing is loaded any more.
    await _openMenu(tester);
    expect(find.byKey(const ValueKey('saved-search-delete')), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('saved-search-undo')));
    await tester.pumpAndSettle();

    expect(await repos.settings.get(key), before);
    expect((await _readable(repos)).map((s) => s.id), [search.id]);
  });

  testWidgets('a saved search something uses is not deleted, and the '
      'message names each use', (tester) async {
    final repos = await _library();
    repos.savedSearches.usage.register(
      'test',
      (id) async => const [
        SavedSearchUse(kind: 'slotRule', label: 'Contra night, slot 3'),
        SavedSearchUse(kind: 'eventRule', label: 'Family dance rule'),
      ],
    );
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    await _openMenu(tester);
    await _choose(tester, 'saved-search-delete');

    expect(find.byKey(const ValueKey('saved-search-in-use')), findsOneWidget);
    expect(find.text('Contra night, slot 3'), findsOneWidget);
    expect(find.text('Family dance rule'), findsOneWidget);
    expect(await repos.savedSearches.get(search.id), isNotNull);
  });

  testWidgets('at the limit, saving another says so and adds nothing', (
    tester,
  ) async {
    final repos = await _library();
    final spec = SavedSearchSpec.fromPanelState(
      CollectionPanelState(text: 'x'),
      today: _day,
    ).value!;
    for (var i = 0; i < savedSearchMaxCount; i++) {
      await repos.savedSearches.create(name: 'Search $i', spec: spec);
    }
    await _pump(tester, repos);
    await _type(tester, 'Petronella');

    await _saveAs(tester, 'One more');

    expect(find.text('Too many saved searches'), findsOneWidget);
    expect(
      await repos.settings.keysWithPrefix(savedSearchKeyPrefix),
      hasLength(savedSearchMaxCount),
    );
  });

  testWidgets('two saved searches with the same name are both listed', (
    tester,
  ) async {
    final repos = await _library();
    final first = await _seed(
      repos,
      'Same',
      CollectionPanelState(text: 'Petronella'),
    );
    final second = await _seed(
      repos,
      'Same',
      CollectionPanelState(text: 'Chorus'),
    );
    await _pump(tester, repos);

    await _openMenu(tester);

    expect(
      find.byKey(ValueKey('saved-search-item-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('saved-search-item-${second.id}')),
      findsOneWidget,
    );
    expect(find.text('Same'), findsNWidgets(2));
  });

  testWidgets('a saved search that uses a deleted tag is shown with a notice '
      'naming the tag, and the tag stays in the search', (tester) async {
    final repos = await _library();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
    final state = CollectionPanelState(
      advanced: BuilderGroup(
        kind: GroupKind.none,
        children: [BuilderTag(tagId: 't1')],
      ),
    );
    state.facets.setTag('t2', selected: true);
    final search = await _seed(repos, 'Not bouncey', state);
    await repos.tags.delete('t1');
    await _pump(tester, repos);

    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    final notice = find.byKey(const ValueKey('saved-search-notice'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.text('The tag Bouncey, which was deleted'),
      ),
      findsOneWidget,
    );
    // Nothing is dropped: the None of row is still there, and so is the
    // Filters tag.
    expect(find.text('Advanced (on)'), findsOneWidget);
    expect(find.text('Filters · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('saved-search-notice-close')));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets('a saved search this version cannot read is listed as needing '
      'attention, never applied, and can be deleted and brought back', (
    tester,
  ) async {
    final repos = await _library();
    const key = '${savedSearchKeyPrefix}from-the-future';
    const value = {'v': 99, 'name': 'Newer', 'text': 'Petronella'};
    await repos.settings.set(key, value);
    await _pump(tester, repos);

    await _openMenu(tester);
    expect(find.text('Needs attention'), findsOneWidget);
    await _choose(tester, 'saved-search-unreadable-from-the-future');

    expect(find.byKey(const ValueKey('saved-search-unreadable')), findsOne);
    expect(_searchText(tester), '');
    await _choose(tester, 'saved-search-unreadable-delete');
    expect(await repos.settings.get(key), isNull);
    expect(_searchText(tester), '');

    await tester.tap(find.byKey(const ValueKey('saved-search-undo')));
    await tester.pumpAndSettle();
    expect(await repos.settings.get(key), value);
  });

  testWidgets('the menu is unavailable while Online search is on', (
    tester,
  ) async {
    final repos = await _library();
    await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
    await _pump(
      tester,
      repos,
      contraDbOnline: ContraDbOnline(
        searchFetcher: (_) async => '{"numberMatching":0,"dances":[]}',
      ),
    );
    IconButton menu() => tester.widget<IconButton>(
      find.byKey(const ValueKey('saved-search-menu')),
    );
    expect(menu().onPressed, isNotNull);

    final toggle = find.byKey(const ValueKey('online-search-enable'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(menu().onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('saved-search-menu')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-search-save')), findsNothing);
  });

  testWidgets('Clear all forgets which saved search was loaded', (
    tester,
  ) async {
    final repos = await _library();
    final search = await _seed(
      repos,
      'Pet',
      CollectionPanelState(text: 'Petronella'),
    );
    await _pump(tester, repos);
    await _openMenu(tester);
    await _choose(tester, 'saved-search-item-${search.id}');

    await tester.tap(find.byTooltip('Clear search and filters'));
    await tester.pumpAndSettle();

    await _openMenu(tester);
    expect(find.byKey(const ValueKey('saved-search-rename')), findsNothing);
    expect(find.byKey(const ValueKey('saved-search-delete')), findsNothing);
  });

  group("today is the caller's own day, from the Collection's clock", () {
    // 2026-11-22 11:05 UTC is 2026-11-23 at +13:00. "Not called in the last
    // month" then starts on 2026-10-23, so a dance last called on 2026-10-22
    // is in the list. Counted from the UTC day it would start on 2026-10-22,
    // and that dance would be left out.
    Future<CompendiumRepositories> called() async {
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
      return repos;
    }

    testWidgets('a saved "not called in the last month" search', (
      tester,
    ) async {
      final repos = await called();
      final state = CollectionPanelState();
      state.facets.callStatuses.add(false);
      state.facets.setHistoryMonths(1);
      final search = await _seed(repos, 'Not lately', state);
      await _pump(tester, repos);

      await _openMenu(tester);
      await _choose(tester, 'saved-search-item-${search.id}');

      expect(_shows('Edge Reel'), isTrue);
      expect(_shows('Recent Reel'), isFalse);
    });

    testWidgets('a window chosen on the panel', (tester) async {
      final repos = await called();
      await _pump(tester, repos);
      final state = CollectionPanelState();
      state.facets.callStatuses.add(false);
      state.facets.setHistoryMonths(1);

      _list(tester).applyPanelState(state);
      await tester.pumpAndSettle();

      expect(_shows('Edge Reel'), isTrue);
      expect(_shows('Recent Reel'), isFalse);
    });
  });
}
