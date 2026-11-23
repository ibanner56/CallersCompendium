// The picker's entry point: a host hands it a whole panel state to show
// (CollectionPicker.panelState, #2325). The program editor keeps its inline
// picker mounted and rebuilds it on every change to the program, and builds
// a new picker each time a sheet opens, so the request must be honoured on a
// rebuild as well as at mount, and only ever once.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/collection_search_controls.dart';
import 'package:compendium_app/src/widgets/online_search_toggle.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

Dance _dance(String id, String title, {List<String> tagIds = const []}) =>
    Dance(
      id: id,
      title: title,
      authorIds: const [],
      tagIds: tagIds,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: [
        testFigure(move: 'swing', params: const {'beats': 16}),
      ],
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A host that owns its picker's request in a field, as
/// [CollectionPicker.panelState] asks — unless [requestInBuild] is set, which
/// builds a fresh request on every build (the mistake the parameter's
/// documentation warns against).
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.data,
    this.enableOnlineSearch = false,
    this.contraDbOnline,
    this.requestInBuild,
  });

  final CollectionData data;
  final bool enableOnlineSearch;
  final ContraDbOnline? contraDbOnline;
  final CollectionPanelState? requestInBuild;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  CollectionPanelRequest? request;
  var pickerGeneration = 0;
  var programChanges = 0;

  /// Asks the picker to show [state].
  CollectionPanelRequest open(CollectionPanelState state) {
    final next = CollectionPanelRequest(state);
    setState(() => request = next);
    return next;
  }

  /// A new picker in place of the old one, given the same request: a sheet
  /// opened again, or the program editor switching between narrow and wide.
  void remount() => setState(() => pickerGeneration++);

  /// What the program editor does on every change to the program: rebuild
  /// the picker with new counts.
  void programChanged() => setState(() => programChanges++);

  @override
  Widget build(BuildContext context) => CollectionPicker(
    key: ValueKey(pickerGeneration),
    data: widget.data,
    dialect: Dialect.larksRobins,
    enrichment: SearchEnrichment.empty,
    onAddDance: (_) {},
    addedDanceCounts: {'program-change-$programChanges': 1},
    enableOnlineSearch: widget.enableOnlineSearch,
    contraDbOnline: widget.contraDbOnline,
    panelState: switch (widget.requestInBuild) {
      final state? => CollectionPanelRequest(state),
      null => request,
    },
  );
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool enableOnlineSearch = false,
  ContraDbOnline? contraDbOnline,
  CollectionPanelState? requestInBuild,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final ignoreArticles = ValueNotifier<bool>(true);
  addTearDown(ignoreArticles.dispose);
  final data = await CollectionData.load(repos);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: RepositoriesScope(
          repositories: repos,
          child: SortIgnoreArticlesScope(
            notifier: ignoreArticles,
            child: _Host(
              key: key,
              data: data,
              enableOnlineSearch: enableOnlineSearch,
              contraDbOnline: contraDbOnline,
              requestInBuild: requestInBuild,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<CompendiumRepositories> _library() async {
  final repos = openTestRepositories();
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
  await repos.dances.create(_dance('a', 'Petronella', tagIds: const ['t1']));
  await repos.dances.create(_dance('b', 'Chorus Jig'));
  return repos;
}

String _searchText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('picker-search')))
    .controller!
    .text;

CollectionSort _sort(WidgetTester tester) => tester
    .widget<CollectionSortMenuButton>(find.byKey(const ValueKey('picker-sort')))
    .sort;

SortDirection _direction(WidgetTester tester) => tester
    .widget<SortDirectionButton>(find.byType(SortDirectionButton))
    .direction;

bool _shows(String title) => find.text(title).evaluate().isNotEmpty;

Future<void> _openFilters(WidgetTester tester) async {
  final panel = find.byKey(const ValueKey('picker-filters-panel'));
  await tester.ensureVisible(panel);
  await tester.tap(panel);
  await tester.pumpAndSettle();
}

/// A state that is not from a saved search: the text, a tag filter, and a
/// sort with its direction.
CollectionPanelState _seeded() {
  final state = CollectionPanelState(
    text: 'Petronella',
    scope: FullTextScope.title,
    sort: CollectionSort.author,
    sortDirection: SortDirection.descending,
  );
  state.facets.setTag('t1', selected: true);
  return state;
}

void main() {
  testWidgets('the inline picker, already mounted, shows exactly a state '
      'handed to it later', (tester) async {
    final repos = await _library();
    final host = await _pump(tester, repos);
    expect(_shows('Chorus Jig'), isTrue);

    final state = _seeded();
    host.currentState!.open(state);
    await tester.pumpAndSettle();

    expect(_searchText(tester), 'Petronella');
    expect(_sort(tester), CollectionSort.author);
    expect(_direction(tester), SortDirection.descending);
    expect(_shows('Petronella'), isTrue);
    expect(_shows('Chorus Jig'), isFalse);
    // The picker edits the state's own objects from now on.
    await _openFilters(tester);
    final tagChip = find.byKey(const ValueKey('tag-t1'));
    expect(tester.widget<FilterChip>(tagChip).selected, isTrue);
    await tester.tap(tagChip);
    await tester.pumpAndSettle();
    expect(state.facets.tagIds, isEmpty);
  });

  testWidgets('a picker built with a state shows it, and the opening sort '
      'read does not replace its sort', (tester) async {
    final repos = await _library();
    // The Collection's opening sort, which the picker reads after mount.
    await repos.settings.set(kDefaultCollectionSortKey, 'lastCalled');
    final state = _seeded();
    await _pump(tester, repos, requestInBuild: state);
    expect(_searchText(tester), 'Petronella');
    expect(_sort(tester), CollectionSort.author);
    expect(_direction(tester), SortDirection.descending);
  });

  testWidgets('a picker built again with the same request does not put the '
      'state back', (tester) async {
    final repos = await _library();
    final host = await _pump(tester, repos);
    final request = host.currentState!.open(_seeded());
    await tester.pumpAndSettle();
    expect(request.applied, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Chorus',
    );
    await tester.pumpAndSettle();

    // A sheet opened again: a new picker, the host's same request. The user
    // has moved on from that search; putting it back would undo them.
    host.currentState!.remount();
    await tester.pumpAndSettle();
    expect(_searchText(tester), isEmpty);
    expect(_sort(tester), isNot(CollectionSort.author));
    expect(_shows('Chorus Jig'), isTrue);
  });

  testWidgets('a rebuild after the user edits keeps the edit', (tester) async {
    final repos = await _library();
    final host = await _pump(tester, repos);
    host.currentState!.open(_seeded());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Chorus',
    );
    await tester.pumpAndSettle();

    // The program changed: the editor rebuilds its picker.
    host.currentState!.programChanged();
    await tester.pumpAndSettle();
    expect(_searchText(tester), 'Chorus');
  });

  testWidgets('a state handed over while online search is on leaves online '
      'search, and none of the old tree\'s tag rows reach the new tree', (
    tester,
  ) async {
    final repos = await _library();
    final host = await _pump(
      tester,
      repos,
      enableOnlineSearch: true,
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
    host.currentState!.open(first);
    await tester.pumpAndSettle();

    // ContraDB has no tags: its search takes the tag row out of the tree.
    final toggle = find.byKey(const ValueKey('picker-online-search-enable'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ContraDB'));
    await tester.pumpAndSettle();
    expect(first.advanced.children.whereType<BuilderTag>(), isEmpty);

    final second = CollectionPanelState(
      advanced: BuilderGroup(children: [BuilderFigure(move: 'swing')]),
    );
    host.currentState!.open(second);
    await tester.pumpAndSettle();

    expect(tester.widget<OnlineSearchToggle>(toggle).enabled, isFalse);
    expect(second.advanced.children.whereType<BuilderTag>(), isEmpty);
    expect(second.advanced.children, hasLength(1));
    // The taken row went back where it came from.
    expect(first.advanced.children.whereType<BuilderTag>(), hasLength(1));
  });

  testWidgets('a stored Best match falls back to Title when the state is no '
      'longer a bare text search, and stays when it is', (tester) async {
    final repos = await _library();
    final host = await _pump(tester, repos);

    final narrowed = CollectionPanelState(
      text: 'Petronella',
      sort: CollectionSort.relevance,
    );
    narrowed.facets.setTag('t1', selected: true);
    host.currentState!.open(narrowed);
    await tester.pumpAndSettle();
    expect(_sort(tester), CollectionSort.title);
    expect(
      _direction(tester),
      CollectionSort.title.searchSort.defaultDirection,
    );

    // Best match is offered only for a bare search of at most two
    // characters (`isBareFullText`).
    host.currentState!.open(
      CollectionPanelState(text: 'Pe', sort: CollectionSort.relevance),
    );
    await tester.pumpAndSettle();
    expect(_sort(tester), CollectionSort.relevance);
  });

  group('a Within window none of the presets offers', () {
    CollectionPanelState window12({required bool fromSavedSearch}) {
      final state = CollectionPanelState(fromSavedSearch: fromSavedSearch);
      state.facets
        ..callStatuses.add(false)
        ..setHistoryMonths(12);
      return state;
    }

    testWidgets('says "saved" when it came from a saved search', (
      tester,
    ) async {
      final repos = await _library();
      final host = await _pump(tester, repos);
      host.currentState!.open(window12(fromSavedSearch: true));
      await tester.pumpAndSettle();
      await _openFilters(tester);
      final chip = find.byKey(const ValueKey('facet-history-within-other'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('12 months, saved')),
        findsOneWidget,
      );
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    });

    testWidgets('reads plainly otherwise, and another choice replaces it', (
      tester,
    ) async {
      final repos = await _library();
      final host = await _pump(tester, repos);
      final state = window12(fromSavedSearch: false);
      host.currentState!.open(state);
      await tester.pumpAndSettle();
      await _openFilters(tester);
      final chip = find.byKey(const ValueKey('facet-history-within-other'));
      expect(
        find.descendant(of: chip, matching: find.text('12 months')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('facet-history-within-3')));
      await tester.pumpAndSettle();
      expect(state.facets.historyMonths, 3);
      expect(chip, findsNothing);
    });
  });
}
