import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

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
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
      ),
      home: const DanceListScreen(),
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows a loading indicator before data resolves', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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

    // An unterminated FTS phrase is a MATCH syntax error at query time.
    await _search(tester, '"');

    expect(
      find.text('Something went wrong running the search.'),
      findsOneWidget,
    );
    // The stale count is cleared so the live region matches the error state.
    expect(find.text('0 dances'), findsOneWidget);
    expect(find.byType(DanceListTile), findsNothing);
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

  // ── Swipe-to-delete ────────────────────────────────────────────────────────

  testWidgets(
    'swiping a dance removes it from the list and shows undo snackbar',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Swipe Me'));
      await repos.dances.create(_dance(id: 'd2', title: 'Stay Here'));

      await _pumpScreen(tester, repos);
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);

      // Fling the Dismissible widget (by key) end-to-start to trigger dismiss.
      await tester.fling(
        find.byKey(const ValueKey('dismissible-d1')),
        const Offset(-300, 0),
        1000,
      );
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

  testWidgets('undo on the list swipe snackbar restores the dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Restore Me'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(const ValueKey('dismissible-d1')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final dance = await repos.dances.getById('d1');
    expect(dance, isNotNull);
    expect(dance!.deletedAt, isNull);
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

  // ── Settings entry ─────────────────────────────────────────────────────────

  testWidgets('Settings button is present in the app bar', (tester) async {
    final repos = openTestRepositories();
    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings')), findsOneWidget);
  });

  testWidgets('Settings button navigates to SettingsScreen', (tester) async {
    final repos = openTestRepositories();
    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });
}
