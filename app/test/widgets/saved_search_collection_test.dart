// Saved searches in the Collection (#2325): the dropdown under the search
// field loads one, and the ⋮ menu saves, updates, renames and deletes, against
// a real in-memory database. The picker's dropdown is tested in
// saved_search_picker_test.dart, the Settings list in
// screens/settings_collection_section_test.dart.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  ContraDbOnline? contraDbOnline,
  ValueNotifier<bool>? inView,
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
      // The app shell keeps every destination mounted and turns tickers off
      // in the hidden ones; [inView] does the same.
      home: ValueListenableBuilder<bool>(
        valueListenable: inView ?? ValueNotifier(true),
        builder: (context, visible, child) =>
            TickerMode(enabled: visible, child: child!),
        child: DanceListScreen(clock: _clock, contraDbOnline: contraDbOnline),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DanceListCommands _list(WidgetTester tester) =>
    tester.state(find.byType(DanceListScreen)) as DanceListCommands;

/// Whether [title] is listed as a result (not only in the dropdown).
bool _shows(String title) => find
    .descendant(of: find.byType(CustomScrollView), matching: find.text(title))
    .evaluate()
    .isNotEmpty;

final _field = find.byKey(const ValueKey('collection-search-field'));

FocusNode _ftsFocus(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('collection-search-field')))
    .focusNode!;
final _dropdown = find.byKey(const ValueKey('saved-search-dropdown'));
final _searchFor = find.byKey(const ValueKey('saved-search-search-for'));
Finder _row(String id) => find.byKey(ValueKey('saved-search-row-$id'));

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

CollectionSort _sort(WidgetTester tester) => tester
    .widget<CollectionSortMenuButton>(find.byType(CollectionSortMenuButton))
    .sort;

SortDirection _direction(WidgetTester tester) => tester
    .widget<SortDirectionButton>(find.byType(SortDirectionButton))
    .direction;

FullTextScope _scope(WidgetTester tester) =>
    tester.widget<SearchScopeField>(find.byType(SearchScopeField)).scope;

Future<void> _focusField(WidgetTester tester) async {
  await tester.tap(_field);
  await tester.pumpAndSettle();
}

/// Types [text], letting the Collection's own debounce run the search.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _tapOff(WidgetTester tester) async {
  await tester.tapAt(const Offset(1100, 2900));
  await tester.pumpAndSettle();
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<PopupMenuItem<Object>>(find.byKey(ValueKey(key))).enabled;

/// Loads [search] through the dropdown.
Future<void> _load(WidgetTester tester, SavedSearch search) async {
  await _focusField(tester);
  await tester.tap(_row(search.id));
  await tester.pumpAndSettle();
  // Loading leaves the results in view: the dropdown does not reopen over
  // them for the text the load put in the field.
  expect(_dropdown, findsNothing);
}

/// Saves the search on screen as [name] through the ⋮ menu.
Future<void> _saveAs(WidgetTester tester, String name) async {
  await _openMore(tester);
  await _choose(tester, 'saved-search-save');
  await tester.enterText(
    find.byKey(const ValueKey('saved-search-name-field')),
    name,
  );
  await tester.pumpAndSettle();
  await _choose(tester, 'saved-search-name-save');
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
  group('the dropdown under the search field', () {
    testWidgets('lists the saved searches; typing narrows them by name and '
        'puts Search for first; an empty field has no Search for row', (
      tester,
    ) async {
      final repos = await _library();
      final pet = await _seed(
        repos,
        'Petronella only',
        CollectionPanelState(text: 'Petronella'),
      );
      final mixers = await _seed(
        repos,
        'Easy mixers',
        CollectionPanelState(text: 'Chorus'),
      );
      await _pump(tester, repos);

      await _focusField(tester);
      expect(_dropdown, findsOneWidget);
      expect(_searchFor, findsNothing);
      expect(_row(pet.id), findsOneWidget);
      expect(_row(mixers.id), findsOneWidget);

      await _type(tester, 'pet');
      expect(_searchFor, findsOneWidget);
      expect(find.text('Search for "pet"'), findsOneWidget);
      expect(_row(pet.id), findsOneWidget);
      expect(_row(mixers.id), findsNothing);
      // Search for comes first.
      expect(
        tester.getTopLeft(_searchFor).dy,
        lessThan(tester.getTopLeft(_row(pet.id)).dy),
      );
    });

    testWidgets('typing still searches as it always did, and Enter keeps the '
        'search typed', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);

      await _focusField(tester);
      await _type(tester, 'Chorus');
      // The debounce ran the search with the dropdown open.
      expect(_shows('Chorus Jig'), isTrue);
      expect(_shows('Petronella'), isFalse);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(_searchText(tester), 'Chorus');
      expect(_shows('Chorus Jig'), isTrue);
      expect(_shows('Petronella'), isFalse);
      expect(_dropdown, findsNothing);
    });

    testWidgets('Enter in an empty field does not load the first saved '
        'search', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);

      await _focusField(tester);
      expect(_dropdown, findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(_searchText(tester), '');
      expect(_shows('Chorus Jig'), isTrue);
    });

    testWidgets('the arrow keys and Enter load a saved search', (tester) async {
      final repos = await _library();
      final pet = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);

      await _focusField(tester);
      await _type(tester, 'p');
      // Row 0 is Search for "p"; down moves onto Pet.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(_searchText(tester), 'Petronella');
      expect(_shows('Chorus Jig'), isFalse);
      expect(pet.name, 'Pet');
    });

    testWidgets('choosing Search for keeps the text and searches it', (
      tester,
    ) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);
      await _focusField(tester);
      await tester.enterText(_field, 'Chorus');
      // Before the debounce: choosing the row runs the search now.
      await tester.pump();

      await tester.tap(_searchFor);
      await tester.pump();

      expect(_searchText(tester), 'Chorus');
      await tester.pumpAndSettle();
      expect(_shows('Chorus Jig'), isTrue);
      expect(_shows('Petronella'), isFalse);
      expect(_dropdown, findsNothing);
    });

    testWidgets('tapping off closes it and keeps the search', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);
      await _focusField(tester);
      await _type(tester, 'Chorus');

      await _tapOff(tester);

      expect(_dropdown, findsNothing);
      expect(_searchText(tester), 'Chorus');
      expect(_shows('Chorus Jig'), isTrue);
      expect(_shows('Petronella'), isFalse);
    });

    testWidgets('choosing a saved search shows all of it and runs it, and '
        'leaves the last-used sort alone', (tester) async {
      final repos = await _library();
      await repos.settings.set(kLastUsedCollectionSortKey, 'title');
      await repos.settings.set(
        kLastUsedCollectionSortDirectionKey,
        'ascending',
      );
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

      await _focusField(tester);
      // Typed text that names the search: what is loaded replaces it, and
      // the row's label never lands in the field.
      await _type(tester, 'bounc');
      await tester.tap(_row(search.id));
      await tester.pumpAndSettle();

      expect(_dropdown, findsNothing);
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

      await _focusField(tester);

      expect(_row(first.id), findsOneWidget);
      expect(_row(second.id), findsOneWidget);
    });

    testWidgets('a saved search this version cannot read is not listed', (
      tester,
    ) async {
      final repos = await _library();
      final pet = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await repos.settings.set('${savedSearchKeyPrefix}future', const {
        'v': 99,
        'name': 'Newer',
      });
      await _pump(tester, repos);

      await _focusField(tester);

      expect(_row(pet.id), findsOneWidget);
      expect(_row('future'), findsNothing);
      expect(find.text('Newer'), findsNothing);
    });

    testWidgets('there is no dropdown while Online search is on', (
      tester,
    ) async {
      final repos = await _library();
      final pet = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(
        tester,
        repos,
        contraDbOnline: ContraDbOnline(
          searchFetcher: (_) async => '{"numberMatching":0,"dances":[]}',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('online-search-enable')));
      await tester.pumpAndSettle();

      await _focusField(tester);
      await tester.enterText(_field, 'pe');
      await tester.pump();

      expect(_dropdown, findsNothing);
      expect(_row(pet.id), findsNothing);
    });

    testWidgets('a saved search that uses a deleted tag is shown with a '
        'notice naming the tag, and the tag stays in the search', (
      tester,
    ) async {
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

      await _load(tester, search);

      final notice = find.byKey(const ValueKey('saved-search-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.text('The tag Bouncey, which was deleted'),
        ),
        findsOneWidget,
      );
      // A screen-reader user is told what is missing, too.
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains(
          '"Not bouncey" uses things that are gone: '
          'The tag Bouncey, which was deleted',
        ),
      );
      // Nothing is dropped: the None of row is still there, and so is the
      // Filters tag.
      expect(find.text('Advanced (on)'), findsOneWidget);
      expect(find.text('Filters · 1'), findsOneWidget);
    });
  });

  group('the dropdown keeps the field working', () {
    testWidgets('Enter after a tap outside runs the search, with no error', (
      tester,
    ) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);
      await _focusField(tester);
      await tester.enterText(_field, 'Chorus');
      await tester.pump();
      await _tapOff(tester);
      expect(_dropdown, findsNothing);
      // Typed after the debounce would have run, so only Enter can search.
      await tester.enterText(_field, 'Chorus Jig');
      await tester.pump();
      await _tapOff(tester);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_searchText(tester), 'Chorus Jig');
      await tester.pumpAndSettle();
      expect(_shows('Chorus Jig'), isTrue);
      expect(_shows('Petronella'), isFalse);
    });

    testWidgets('Enter after Online search was turned on runs the online '
        'search, with no error', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      final queries = <String>[];
      await _pump(
        tester,
        repos,
        contraDbOnline: ContraDbOnline(
          searchFetcher: (query) async {
            queries.add('$query');
            return '{"numberMatching":0,"dances":[]}';
          },
        ),
      );
      await _focusField(tester);
      await tester.enterText(_field, 'pe');
      await tester.pump();
      expect(_dropdown, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('online-search-enable')));
      await tester.pump();
      _ftsFocus(tester).requestFocus();
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_dropdown, findsNothing);
      expect(_searchText(tester), 'pe');
    });

    testWidgets('a tap elsewhere while the field is not in use does not keep '
        'the dropdown shut when the keyboard focuses it', (tester) async {
      final repos = await _library();
      final pet = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _tapOff(tester);

      expect(_list(tester).focusSearch(), isTrue);
      await tester.pumpAndSettle();

      expect(_dropdown, findsOneWidget);
      expect(_row(pet.id), findsOneWidget);
    });

    testWidgets('typing after the arrow keys moves the highlight back to '
        'Search for, so Enter searches what is typed', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);
      await _focusField(tester);
      await tester.enterText(_field, 'pe');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.enterText(_field, 'pet');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Not the saved search ("Petronella"): what was typed.
      expect(_searchText(tester), 'pet');
    });

    testWidgets('the arrow keys then emptying the field: Enter searches, and '
        'no saved row is shown highlighted', (tester) async {
      final repos = await _library();
      await _seed(repos, 'Pet', CollectionPanelState(text: 'Petronella'));
      await _pump(tester, repos);
      await _focusField(tester);
      await tester.enterText(_field, 'p');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.enterText(_field, '');
      await tester.pump();

      final tiles = tester.widgetList<ListTile>(
        find.descendant(of: _dropdown, matching: find.byType(ListTile)),
      );
      // Row 0 is highlighted (where Enter would act), but with nothing typed
      // and no arrow key since, Enter searches.
      expect([for (final t in tiles) t.selected], [true]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(_searchText(tester), '');
      expect(_shows('Chorus Jig'), isTrue);
    });
  });

  group('a saved search changed elsewhere', () {
    testWidgets('renamed elsewhere, then Update here: the new name stays', (
      tester,
    ) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);
      // Renamed in Settings, or by sync from another device.
      await repos.savedSearches.save(
        SavedSearch(id: search.id, name: 'Renamed', spec: search.spec),
      );
      await _type(tester, 'Chorus');
      await _tapOff(tester);

      await _openMore(tester);
      await _choose(tester, 'saved-search-update');

      final stored = await repos.savedSearches.get(search.id);
      expect(stored!.name, 'Renamed');
      expect(stored.spec.toJson()['text'], 'Chorus');
    });

    testWidgets('updated elsewhere, then Rename here: what is stored stays', (
      tester,
    ) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);
      final newer = SavedSearchSpec.fromPanelState(
        CollectionPanelState(text: 'Chorus'),
        today: _day,
      ).value!;
      await repos.savedSearches.save(
        SavedSearch(id: search.id, name: 'Pet', spec: newer),
      );

      await _openMore(tester);
      await _choose(tester, 'saved-search-rename');
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-name-field')),
        'Chorus only',
      );
      await tester.pumpAndSettle();
      await _choose(tester, 'saved-search-name-save');

      final stored = await repos.savedSearches.get(search.id);
      expect(stored!.name, 'Chorus only');
      expect(stored.spec.toJson(), newer.toJson());
    });

    for (final entry in ['saved-search-update', 'saved-search-rename']) {
      testWidgets('deleted elsewhere, then $entry here: refused, not brought '
          'back, and forgotten', (tester) async {
        final repos = await _library();
        final search = await _seed(
          repos,
          'Pet',
          CollectionPanelState(text: 'Petronella'),
        );
        await _pump(tester, repos);
        await _load(tester, search);
        await repos.savedSearches.delete(search.id);
        await _type(tester, 'Chorus');
        await _tapOff(tester);

        await _openMore(tester);
        await _choose(tester, entry);

        expect(await repos.settings.get(search.settingsKey), isNull);
        expect(
          find.text(
            '"Pet" was deleted, here or on another device, so '
            'nothing was changed.',
          ),
          findsOneWidget,
        );
        await _openMore(tester);
        expect(find.byKey(ValueKey(entry)), findsNothing);
        expect(find.text('Save this search…'), findsOneWidget);
      });
    }

    testWidgets('when the Collection comes back into view, a rename made '
        'meanwhile shows in the ⋮ menu, and a delete is forgotten', (
      tester,
    ) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      final inView = ValueNotifier(true);
      addTearDown(inView.dispose);
      await _pump(tester, repos, inView: inView);
      await _load(tester, search);

      inView.value = false;
      await tester.pumpAndSettle();
      await repos.savedSearches.save(
        SavedSearch(id: search.id, name: 'Renamed', spec: search.spec),
      );
      inView.value = true;
      await tester.pumpAndSettle();
      await _openMore(tester);
      expect(find.text('Rename "Renamed"…'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      inView.value = false;
      await tester.pumpAndSettle();
      await repos.savedSearches.delete(search.id);
      inView.value = true;
      await tester.pumpAndSettle();
      await _openMore(tester);
      expect(find.byKey(const ValueKey('saved-search-rename')), findsNothing);
      expect(find.text('Save this search…'), findsOneWidget);
    });

    testWidgets('Undo of a delete makes it the loaded search again', (
      tester,
    ) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);
      await _openMore(tester);
      await _choose(tester, 'saved-search-delete');

      await tester.tap(find.byKey(const ValueKey('saved-search-undo')));
      await tester.pumpAndSettle();

      await _openMore(tester);
      expect(find.text('Rename "Pet"…'), findsOneWidget);
    });
  });

  group('the ⋮ menu', () {
    testWidgets('Save this search… is offered only once a query is set, and '
        'saves the name and the whole search', (tester) async {
      final repos = await _library();
      await _pump(tester, repos);

      await _openMore(tester);
      expect(_enabled(tester, 'saved-search-save'), isFalse);
      expect(find.text('Save this search…'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-search-update')), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _type(tester, 'Petronella');
      await _saveAs(tester, 'Just the one');

      final saved = await _readable(repos);
      expect(saved.map((s) => s.name), ['Just the one']);
      expect(saved.single.spec.toJson()['text'], 'Petronella');
      expect(find.text('Saved "Just the one"'), findsOneWidget);
      // Listed in the dropdown, found by its name.
      await _focusField(tester);
      await tester.enterText(_field, 'just');
      await tester.pump();
      expect(_row(saved.single.id), findsOneWidget);
    });

    testWidgets('the save dialog says what is kept of a chosen date: the '
        'whole months back from today', (tester) async {
      final repos = await _library();
      await _pump(tester, repos);
      final state = CollectionPanelState();
      state.facets.callStatuses.add(false);
      // A year before the caller's day, which is the 23rd in their zone.
      state.facets.setHistorySince(DateTime.utc(2025, 11, 23));
      _list(tester).applyPanelState(state);
      await tester.pumpAndSettle();

      await _openMore(tester);
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

    testWidgets('while a saved search is loaded: Update (only once changed), '
        'Save as a new search…, Rename and Delete; clearing the search '
        'takes them away', (tester) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);

      await _openMore(tester);
      expect(find.text('Update "Pet"'), findsOneWidget);
      expect(_enabled(tester, 'saved-search-update'), isFalse);
      expect(find.text('Save as a new search…'), findsOneWidget);
      expect(find.text('Save this search…'), findsNothing);
      expect(find.text('Rename "Pet"…'), findsOneWidget);
      expect(find.text('Delete "Pet"'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _type(tester, 'Chorus');
      await _tapOff(tester);
      await _openMore(tester);
      expect(_enabled(tester, 'saved-search-update'), isTrue);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear search and filters'));
      await tester.pumpAndSettle();
      await _tapOff(tester);
      await _openMore(tester);
      expect(find.byKey(const ValueKey('saved-search-update')), findsNothing);
      expect(find.byKey(const ValueKey('saved-search-rename')), findsNothing);
      expect(find.byKey(const ValueKey('saved-search-delete')), findsNothing);
      expect(find.text('Save this search…'), findsOneWidget);
    });

    testWidgets('Update writes the change back, and then is off again', (
      tester,
    ) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);
      await _type(tester, 'Chorus');
      await _tapOff(tester);

      await _openMore(tester);
      await _choose(tester, 'saved-search-update');

      final stored = await repos.savedSearches.get(search.id);
      expect(stored!.spec.toJson()['text'], 'Chorus');
      expect(stored.name, 'Pet');
      await _openMore(tester);
      expect(_enabled(tester, 'saved-search-update'), isFalse);
    });

    testWidgets('Save as a new search… keeps the loaded search and adds a '
        'second', (tester) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      await _pump(tester, repos);
      await _load(tester, search);
      await _type(tester, 'Chorus');
      await _tapOff(tester);

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
      await _load(tester, search);
      // An edit on screen is not part of a rename.
      await _type(tester, 'Chorus');
      await _tapOff(tester);

      await _openMore(tester);
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

    testWidgets('Delete tombstones the saved search and Undo brings back the '
        'same bytes', (tester) async {
      final repos = await _library();
      final search = await _seed(
        repos,
        'Pet',
        CollectionPanelState(text: 'Petronella'),
      );
      final key = search.settingsKey;
      final before = await repos.settings.get(key);
      await _pump(tester, repos);
      await _load(tester, search);

      await _openMore(tester);
      await _choose(tester, 'saved-search-delete');

      expect(await repos.settings.get(key), isNull);
      expect(
        await repos.settings.keysWithPrefix(savedSearchKeyPrefix),
        isEmpty,
      );
      expect(find.text('Deleted "Pet"'), findsOneWidget);
      // The search stays on screen, but nothing is loaded any more.
      expect(_searchText(tester), 'Petronella');
      await _openMore(tester);
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
      await _load(tester, search);

      await _openMore(tester);
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
      await _tapOff(tester);

      await _saveAs(tester, 'One more');

      expect(find.text('Too many saved searches'), findsOneWidget);
      expect(
        await repos.settings.keysWithPrefix(savedSearchKeyPrefix),
        hasLength(savedSearchMaxCount),
      );
    });

    testWidgets('none of it applies while Online search is on', (tester) async {
      final repos = await _library();
      await _pump(
        tester,
        repos,
        contraDbOnline: ContraDbOnline(
          searchFetcher: (_) async => '{"numberMatching":0,"dances":[]}',
        ),
      );
      await _type(tester, 'Petronella');
      await _tapOff(tester);
      await tester.tap(find.byKey(const ValueKey('online-search-enable')));
      await tester.pumpAndSettle();

      await _openMore(tester);

      expect(_enabled(tester, 'saved-search-save'), isFalse);
    });
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

      await _load(tester, search);

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
