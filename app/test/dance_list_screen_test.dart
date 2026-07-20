import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/brand_mark.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/skeleton.dart';

import 'support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  DanceForm form = DanceForm.contra,
  Formation formation = const Formation(FormationShape.dupleImproper),
  DanceStatus status = DanceStatus.active,
  List<Figure> figures = const [],
  List<CustomFieldValue> customFields = const [],
  DateTime? createdAt,
  String hook = '',
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: tagIds,
  form: form,
  formation: formation,
  status: status,
  figures: figures,
  customFields: customFields,
  hook: hook,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos, {
  Dialect? activeDialect,
  ValueListenable<int>? refreshTrigger,
  ValueNotifier<int>? collectionRefresh,
  bool sortIgnoreArticles = true,
}) async {
  // A tall surface so the search bar, filter/advanced panels and results are
  // all laid out without scrolling, keeping chip/control taps stable.
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    AppThemeSelection.system,
  );
  addTearDown(themeNotifier.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  final sortIgnoreArticlesNotifier = ValueNotifier<bool>(sortIgnoreArticles);
  addTearDown(sortIgnoreArticlesNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: notifier,
              child: SortIgnoreArticlesScope(
                notifier: sortIgnoreArticlesNotifier,
                child: collectionRefresh == null
                    ? child!
                    : CollectionRefreshScope(
                        revision: collectionRefresh,
                        child: child!,
                      ),
              ),
            ),
          ),
        ),
      ),
      home: DanceListScreen(refreshTrigger: refreshTrigger),
    ),
  );
}

/// Enters full-text search and lets the 250 ms debounce + async query resolve.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

/// Types [text] into the keyed By-Phrase move input and picks the [option]
/// from the type-ahead overlay.
Future<void> _addPhraseMove(
  WidgetTester tester,
  String inputKey,
  String text,
  String option,
) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(inputKey)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows a loading skeleton before data resolves', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    // Content-shaped skeleton (not a bare spinner) with a "Loading…" label for
    // screen readers while the collection loads.
    expect(find.byType(SkeletonListView), findsOneWidget);
    expect(find.bySemanticsLabel('Loading\u2026'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Chase the Squirrel'), findsOneWidget);
  });

  testWidgets('shows an empty-collection message with no dances', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(find.textContaining('collection is empty'), findsOneWidget);
    // The empty-collection state leads with the brand mark above the copy (§4.4).
    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets(
    'renders title, authors, formation chip, and tags, with a live count',
    (tester) async {
      final repos = openTestRepositories();
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Ada Lovelace'),
      );
      await repos.tags.upsert(Tag(id: 't1', name: 'Beginner-friendly'));
      await repos.dances.create(
        _dance(
          id: 'd1',
          title: 'Chase the Squirrel',
          authorIds: const ['c1'],
          tagIds: const ['t1'],
          formation: const Formation(FormationShape.becketCw),
        ),
      );

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      expect(find.text('Chase the Squirrel'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DanceListTile),
          matching: find.text('Becket (CW)'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 dance'), findsOneWidget);
    },
  );

  testWidgets('announces plural counts in a live region', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Beta'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(find.text('2 dances'), findsOneWidget);
    // The count sits in a polite live region for AT.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false),
      ),
      findsWidgets,
    );
  });

  testWidgets('sorts by title by default', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Zesty Reel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Autumn Waltz'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(_titles(tester), ['Autumn Waltz', 'Zesty Reel']);
  });

  testWidgets('opens in the saved default sort order (ROADMAP G.6a)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultCollectionSortKey,
      CollectionSort.recentlyAdded.name,
    );
    await repos.dances.create(
      _dance(id: 'd1', title: 'Older Dance', createdAt: DateTime.utc(2025)),
    );
    await repos.dances.create(
      _dance(id: 'd2', title: 'Newer Dance', createdAt: DateTime.utc(2026)),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    // No user interaction: the list opens already sorted recently-added, not
    // the hardcoded title default.
    expect(_titles(tester), ['Newer Dance', 'Older Dance']);
  });

  testWidgets(
    'a refresh does not re-seed over an in-session user sort (ROADMAP G.6a)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultCollectionSortKey,
        CollectionSort.recentlyAdded.name,
      );
      // Titles chosen so title-sort and recency-sort produce opposite orders:
      // "Aardvark" is older (title-first), "Zephyr" is newer (recency-first).
      await repos.dances.create(
        _dance(id: 'd1', title: 'Aardvark', createdAt: DateTime.utc(2025)),
      );
      await repos.dances.create(
        _dance(id: 'd2', title: 'Zephyr', createdAt: DateTime.utc(2026)),
      );

      final refreshTrigger = ValueNotifier<int>(0);
      addTearDown(refreshTrigger.dispose);
      await _pumpScreen(tester, repos, refreshTrigger: refreshTrigger);
      await tester.pumpAndSettle();

      // Opens in the seeded default (recently-added ⇒ newest first).
      expect(_titles(tester), ['Zephyr', 'Aardvark']);

      // User switches to Title in-session (⇒ alphabetical).
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Aardvark', 'Zephyr']);

      // A refresh re-runs _boot; the user's in-session sort must survive (the
      // saved default must not re-seed over it).
      refreshTrigger.value = 1;
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Aardvark', 'Zephyr']);
    },
  );

  testWidgets(
    'issue #340: a dance added externally with a new author appears — and the '
    'new author joins the filter — after CollectionRefreshScope fires, without '
    'a manual reload',
    (tester) async {
      final repos = openTestRepositories();
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Ada Lovelace'),
      );
      await repos.dances.create(
        _dance(id: 'd1', title: 'Chase the Squirrel', authorIds: const ['c1']),
      );

      final collectionRefresh = ValueNotifier<int>(0);
      addTearDown(collectionRefresh.dispose);
      await _pumpScreen(tester, repos, collectionRefresh: collectionRefresh);
      await tester.pumpAndSettle();

      // Baseline: only the seeded dance and its author are present.
      expect(find.text('Chase the Squirrel'), findsOneWidget);
      expect(find.text('1 dance'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const ValueKey('filters-panel')));
      // #341: the author facet is now a searchable multi-select. The seeded
      // author is discoverable via the search field; the not-yet-imported
      // author is not.
      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'Grace',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('author-facet-option-c2')),
        findsNothing,
      );
      // Reset the query so it doesn't constrain the post-import search below.
      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        '',
      );
      await tester.pumpAndSettle();

      // Simulate an import: a new dance by a brand-new author lands in the
      // collection out-of-band, then the app-level signal fires.
      await repos.choreographers.upsert(
        Choreographer(id: 'c2', name: 'Grace Hopper'),
      );
      await repos.dances.create(
        _dance(id: 'd2', title: 'Petronella', authorIds: const ['c2']),
      );
      collectionRefresh.value++;
      await tester.pumpAndSettle();

      // The list re-booted: the imported dance shows and the count updated,
      // with no navigation or manual reload.
      expect(find.text('Petronella'), findsOneWidget);
      expect(find.text('2 dances'), findsOneWidget);

      // The author facet re-derived: the new author is now searchable...
      await tester.enterText(
        find.byKey(const ValueKey('author-facet-search')),
        'Grace',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('author-facet-option-c2')),
        findsOneWidget,
      );

      // ...and genuinely filter-able: selecting it narrows the collection to
      // that author's dance (the actual #340 guarantee).
      await tester.tap(find.byKey(const ValueKey('author-facet-option-c2')));
      await tester.pumpAndSettle();
      expect(find.text('Petronella'), findsOneWidget);
      expect(find.text('Chase the Squirrel'), findsNothing);
      expect(find.text('1 dance'), findsOneWidget);
    },
  );

  testWidgets('title sort ignores leading articles by default', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'The Zesty Reel'));
    await repos.dances.create(_dance(id: 'd2', title: 'A Nice Combination'));
    await repos.dances.create(_dance(id: 'd3', title: 'Midtown Swing'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    // Keys: 'midtown swing', 'nice combination', 'zesty reel'.
    expect(_titles(tester), [
      'Midtown Swing',
      'A Nice Combination',
      'The Zesty Reel',
    ]);
  });

  testWidgets('title sort respects the literal text when the setting is off', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'The Zesty Reel'));
    await repos.dances.create(_dance(id: 'd2', title: 'A Nice Combination'));
    await repos.dances.create(_dance(id: 'd3', title: 'Midtown Swing'));

    await _pumpScreen(tester, repos, sortIgnoreArticles: false);
    await tester.pumpAndSettle();

    // Literal: 'A Nice Combination' < 'Midtown Swing' < 'The Zesty Reel'.
    expect(_titles(tester), [
      'A Nice Combination',
      'Midtown Swing',
      'The Zesty Reel',
    ]);
  });

  testWidgets('sorts by recently-added when selected', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Older Dance', createdAt: DateTime.utc(2025)),
    );
    await repos.dances.create(
      _dance(id: 'd2', title: 'Newer Dance', createdAt: DateTime.utc(2026)),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently added').last);
    await tester.pumpAndSettle();

    expect(_titles(tester), ['Newer Dance', 'Older Dance']);
  });

  testWidgets('sorts by last-called, never-called dances last', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Never Called'));
    await repos.dances.create(_dance(id: 'd2', title: 'Called Dance'));
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'A Night Out',
        slots: [
          ProgramSlot(
            id: 's1',
            position: 0,
            danceId: 'd2',
            performedAt: DateTime.utc(2026, 5, 1),
          ),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last called').last);
    await tester.pumpAndSettle();

    expect(_titles(tester), ['Called Dance', 'Never Called']);
  });

  testWidgets('full-text search narrows the list', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Rambling Reel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _search(tester, 'chase');

    expect(find.text('Chase the Squirrel'), findsOneWidget);
    expect(find.text('Rambling Reel'), findsNothing);
    expect(find.text('1 dance'), findsOneWidget);
  });

  testWidgets('a facet chip filters the list', (tester) async {
    final repos = openTestRepositories();
    await repos.tags.upsert(Tag(id: 't1', name: 'Classic'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Chase the Squirrel', tagIds: const ['t1']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Rambling Reel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();
    expect(find.text('2 dances'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('filters-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('tag-t1')));

    expect(find.text('Chase the Squirrel'), findsOneWidget);
    expect(find.text('Rambling Reel'), findsNothing);
  });

  testWidgets('different facets AND together', (tester) async {
    final repos = openTestRepositories();
    await repos.tags.upsert(Tag(id: 't1', name: 'Classic'));
    // contra + t1  → matches; square + t1 → no; contra + no tag → no.
    await repos.dances.create(
      _dance(id: 'a', title: 'Contra With Tag', tagIds: const ['t1']),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'Square With Tag',
        form: DanceForm.square,
        tagIds: const ['t1'],
      ),
    );
    await repos.dances.create(_dance(id: 'c', title: 'Contra No Tag'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('filters-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('form-contra')));
    await _tapVisible(tester, find.byKey(const ValueKey('tag-t1')));

    expect(_titles(tester), ['Contra With Tag']);
  });

  testWidgets('multiple tags OR within the tag facet', (tester) async {
    final repos = openTestRepositories();
    await repos.tags.upsert(Tag(id: 't1', name: 'Alpha'));
    await repos.tags.upsert(Tag(id: 't2', name: 'Beta'));
    await repos.tags.upsert(Tag(id: 't3', name: 'Gamma'));
    await repos.dances.create(
      _dance(id: 'a', title: 'Has Alpha', tagIds: const ['t1']),
    );
    await repos.dances.create(
      _dance(id: 'b', title: 'Has Beta', tagIds: const ['t2']),
    );
    await repos.dances.create(
      _dance(id: 'c', title: 'Has Gamma', tagIds: const ['t3']),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('filters-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('tag-t1')));
    await _tapVisible(tester, find.byKey(const ValueKey('tag-t2')));

    expect(_titles(tester)..sort(), ['Has Alpha', 'Has Beta']);
    expect(find.text('Has Gamma'), findsNothing);
  });

  testWidgets('a choice custom-field facet filters the list', (tester) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'diff',
        key: 'difficulty',
        label: 'Difficulty',
        type: CustomFieldType.choice,
        choices: const ['easy', 'hard'],
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'Easy One',
        customFields: [CustomFieldValue(fieldId: 'diff', value: 'easy')],
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'Hard One',
        customFields: [CustomFieldValue(fieldId: 'diff', value: 'hard')],
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('filters-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('cf-diff-easy')));

    expect(_titles(tester), ['Easy One']);
  });

  testWidgets('relevance sort is offered only for a bare full-text search', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    // No query yet → no relevance option.
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.text('Best match'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // dismiss the menu
    await tester.pumpAndSettle();

    // Bare full-text query → relevance offered.
    await _search(tester, 'chase');
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.text('Best match'), findsOneWidget);
  });

  testWidgets('advanced builder: add a figure row filters by figure', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'Has Petronella',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}),
        ],
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'Just Swing',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}),
        ],
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('advanced-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('advanced-enable')));
    await _tapVisible(tester, find.text('Add'));
    await _tapVisible(tester, find.text('Has figure'));

    final moveField = find.byType(TextField).last;
    await tester.ensureVisible(moveField);
    await tester.enterText(moveField, 'petro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('petronella').last);
    await tester.pumpAndSettle();

    expect(_titles(tester), ['Has Petronella']);
  });

  testWidgets('advanced builder: add and remove a condition group', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'a', title: 'Alpha'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('advanced-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('advanced-enable')));

    // Root group only.
    expect(find.byType(DropdownButton<GroupKind>), findsOneWidget);

    await _tapVisible(tester, find.text('Add'));
    await _tapVisible(tester, find.text('Condition group'));
    expect(find.byType(DropdownButton<GroupKind>), findsNWidgets(2));

    // The nested group's remove (close) button.
    await _tapVisible(tester, find.byIcon(Icons.close).last);
    expect(find.byType(DropdownButton<GroupKind>), findsOneWidget);
  });

  testWidgets('advanced builder: add a "then" sequence row', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'a', title: 'Alpha'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('advanced-panel')));
    await _tapVisible(tester, find.byKey(const ValueKey('advanced-enable')));
    await _tapVisible(tester, find.text('Add'));
    await _tapVisible(tester, find.text('Sequence (then)'));

    expect(find.text('then'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('by phrase: match figure in A1 returns only dances with that '
      'figure in A1', (tester) async {
    final repos = openTestRepositories();
    // petronella in A1 (first 16-beat figure).
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'beats': 16}), // A2
          Figure(move: 'balance', params: const {'beats': 16}), // B1
          Figure(move: 'long_lines', params: const {'beats': 16}), // B2
        ],
      ),
    );
    // petronella in B1, not A1.
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'B1 Petronella',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'beats': 16}), // A2
          Figure(move: 'petronella', params: const {'beats': 16}), // B1
          Figure(move: 'long_lines', params: const {'beats': 16}), // B2
        ],
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('by-phrase-panel')));
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    expect(_titles(tester), ['A1 Petronella']);
  });

  testWidgets('by phrase: do not match figure in B1 excludes dances with that '
      'figure in B1', (tester) async {
    final repos = openTestRepositories();
    // balance in B1 → should be excluded.
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'B1 Balance',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'beats': 16}), // A2
          Figure(move: 'balance', params: const {'beats': 16}), // B1
          Figure(move: 'long_lines', params: const {'beats': 16}), // B2
        ],
      ),
    );
    // balance in A1 (not B1) → survives the B1 exclusion.
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'A1 Balance',
        figures: [
          Figure(move: 'balance', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'beats': 16}), // A2
          Figure(move: 'petronella', params: const {'beats': 16}), // B1
          Figure(move: 'long_lines', params: const {'beats': 16}), // B2
        ],
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('by-phrase-panel')));
    await _addPhraseMove(tester, 'exclude-B1-input-0', 'balance', 'balance');

    expect(_titles(tester), ['A1 Balance']);
  });

  testWidgets('by phrase: composes with a full-text query', (tester) async {
    final repos = openTestRepositories();
    for (final (id, title) in [('a', 'Reel Alpha'), ('b', 'Jig Beta')]) {
      await repos.dances.create(
        _dance(
          id: id,
          title: title,
          figures: [
            Figure(move: 'petronella', params: const {'beats': 16}), // A1
            Figure(move: 'swing', params: const {'beats': 16}), // A2
            Figure(move: 'balance', params: const {'beats': 16}), // B1
            Figure(move: 'long_lines', params: const {'beats': 16}), // B2
          ],
        ),
      );
    }

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _search(tester, 'Reel');
    await _tapVisible(tester, find.byKey(const ValueKey('by-phrase-panel')));
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    // Both have petronella in A1, but only "Reel Alpha" matches the text.
    expect(_titles(tester), ['Reel Alpha']);
  });

  testWidgets('by phrase: clear resets the by-phrase constraint', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'beats': 16}), // A2
        ],
      ),
    );
    await repos.dances.create(_dance(id: 'b', title: 'No Figures'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('by-phrase-panel')));
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');
    expect(_titles(tester), ['A1 Petronella']);

    await _tapVisible(tester, find.byTooltip('Clear search and filters'));

    expect(_titles(tester)..sort(), ['A1 Petronella', 'No Figures']);
    // The chip is gone after clearing.
    expect(
      find.byKey(const ValueKey('match-A1-chip-petronella')),
      findsNothing,
    );
  });

  testWidgets('by phrase: inputs are labeled and reachable for AT', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'a', title: 'A'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('by-phrase-panel')));

    final matchField = find.descendant(
      of: find.byKey(const ValueKey('match-A1-input-0')),
      matching: find.byType(TextField),
    );
    final excludeField = find.descendant(
      of: find.byKey(const ValueKey('exclude-A1-input-0')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(matchField);

    expect(
      tester.getSemantics(matchField),
      isSemantics(
        label: 'first phrase (usually A1), figures match',
        isTextField: true,
      ),
    );
    expect(
      tester.getSemantics(excludeField),
      isSemantics(
        label: 'first phrase (usually A1), but do not match',
        isTextField: true,
      ),
    );
  });

  testWidgets('shows a no-match message when nothing matches', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await _search(tester, 'nonexistentword');

    expect(find.text('No dances match your search.'), findsOneWidget);
    expect(find.text('0 dances'), findsOneWidget);
  });

  testWidgets('surfaces a search error without crashing', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    // Simulate a backend failure at query time: close the database so the
    // next search throws. (User input can no longer trigger an FTS syntax
    // error now that queries are sanitized, so we fault the store directly.)
    await repos.db.close();
    await _search(tester, 'chase');

    expect(
      find.text('Something went wrong running the search.'),
      findsOneWidget,
    );
    // The stale count is cleared so the live region matches the error state.
    expect(find.text('0 dances'), findsOneWidget);
    expect(find.byType(DanceListTile), findsNothing);
  });

  testWidgets('punctuation-only query degrades to no-match, not an error', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    // A lone double quote used to be an FTS MATCH syntax error; sanitized
    // queries now match nothing gracefully instead of surfacing an error.
    await _search(tester, '"');

    expect(find.text('Something went wrong running the search.'), findsNothing);
    expect(find.text('No dances match your search.'), findsOneWidget);
    expect(find.text('0 dances'), findsOneWidget);
  });

  testWidgets('tapping a dance navigates to its detail screen', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chase the Squirrel'));
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailScreen), findsOneWidget);
    expect(find.text('Chase the Squirrel'), findsOneWidget);
  });

  // ── Swipe-to-reveal Delete (issue #352) ────────────────────────────────────

  testWidgets(
    'swiping reveals a Delete button; tapping it removes the dance and shows '
    'undo snackbar',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Swipe Me'));
      await repos.dances.create(_dance(id: 'd2', title: 'Stay Here'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);

      // Swipe left to reveal the Delete action; the swipe alone must NOT delete.
      await tester.drag(
        find.byKey(const ValueKey('slidable-d1')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);
      var stillThere = await repos.dances.getById('d1');
      expect(stillThere, isNotNull);
      expect(stillThere!.deletedAt, isNull);

      // Tapping the revealed Delete button confirms the delete.
      await tester.tap(find.byKey(const ValueKey('slide-delete-d1')));
      await tester.pumpAndSettle();

      // Dance is gone from the list view.
      expect(find.text('Swipe Me'), findsNothing);
      expect(find.text('Stay Here'), findsOneWidget);

      // Undo snackbar appears.
      expect(find.text('"Swipe Me" deleted.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Dance is soft-deleted in storage, not hard-deleted.
      final deleted = await repos.dances.getById('d1', includeDeleted: true);
      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, isNotNull);

      final visible = await repos.dances.listAll();
      expect(visible.where((d) => d.id == 'd1'), isEmpty);
    },
  );

  testWidgets('undo on the revealed-Delete snackbar restores the dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Restore Me'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('slidable-d1')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide-delete-d1')));
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final dance = await repos.dances.getById('d1');
    expect(dance, isNotNull);
    expect(dance!.deletedAt, isNull);
  });

  // ── Row action menu (⋮, non-swipe) ─────────────────────────────────────────

  testWidgets(
    'row overflow menu Delete removes the dance and shows the undo snackbar',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Menu Delete'));
      await repos.dances.create(_dance(id: 'd2', title: 'Stay Here'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      // Open the row's ⋮ menu (no swipe) and invoke Delete.
      await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-action-delete')));
      await tester.pumpAndSettle();

      // Same delete + undo flow as the swipe.
      expect(find.text('Menu Delete'), findsNothing);
      expect(find.text('Stay Here'), findsOneWidget);
      expect(find.text('"Menu Delete" deleted.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Soft-deleted in storage, not hard-deleted.
      final deleted = await repos.dances.getById('d1', includeDeleted: true);
      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, isNotNull);
    },
  );

  testWidgets('row overflow menu Duplicate adds a "(copy)" to the list', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Copy Me'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dance-action-duplicate')));
    await tester.pumpAndSettle();

    expect(find.text('Copy Me (copy)'), findsOneWidget);
    final all = await repos.dances.listAll();
    expect(all.where((d) => d.title == 'Copy Me (copy)'), isNotEmpty);
  });

  testWidgets('row overflow menu Add to program opens the picker sheet', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Add Me'));
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Friday Night',
        slots: const [],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dance-action-add-to-program')));
    await tester.pumpAndSettle();

    // The shared add-to-program sheet lists the existing program.
    expect(find.byKey(const ValueKey('program-pick-p1')), findsOneWidget);
    // Modal pickers use a standard drag-handle bottom sheet (no hand-built
    // header/close button) for consistency across the app's picker flows.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isTrue,
    );
    expect(find.byKey(const ValueKey('add-to-program-close')), findsNothing);
  });

  // ── Recently Deleted navigation ────────────────────────────────────────────

  testWidgets(
    'recently-deleted button navigates to the RecentlyDeletedScreen',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Any Dance'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('recently-deleted')));
      await tester.pumpAndSettle();

      expect(find.text('Recently Deleted'), findsOneWidget);
    },
  );

  // ── Delete from detail screen: collection reloads ──────────────────────────

  testWidgets(
    'deleting from the detail screen removes the dance from the collection',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Delete From Detail'));
      await repos.dances.create(_dance(id: 'd2', title: 'Stay Here'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      // Navigate to the detail screen via the list tile.
      await tester.tap(find.text('Delete From Detail'));
      await tester.pumpAndSettle();

      expect(find.byType(DanceDetailScreen), findsOneWidget);

      // Delete from the detail screen.
      await tester.tap(find.byKey(const ValueKey('delete-dance')));
      await tester.pumpAndSettle();

      // Back on the collection; deleted dance is gone, other dance remains.
      expect(find.text('Delete From Detail'), findsNothing);
      expect(find.text('Stay Here'), findsOneWidget);
    },
  );

  testWidgets(
    'undo on the detail-delete snackbar restores the dance in the collection',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Undo Detail Delete'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      // Navigate to detail, delete, then undo.
      await tester.tap(find.text('Undo Detail Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-dance')));
      await tester.pumpAndSettle();

      // Dance is gone from the collection (delete took effect).
      expect(find.text('Undo Detail Delete'), findsNothing);
      expect(find.text('"Undo Detail Delete" deleted.'), findsOneWidget);

      // Tap Undo — triggers restore() + onRestored callback → _boot().
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Dance reappears in the collection after reload.
      expect(find.text('Undo Detail Delete'), findsOneWidget);

      // Storage confirms restore.
      final dance = await repos.dances.getById('d1');
      expect(dance, isNotNull);
      expect(dance!.deletedAt, isNull);
    },
  );
}
