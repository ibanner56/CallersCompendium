import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import 'support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  Formation formation = const Formation(FormationShape.dupleImproper),
  DateTime? createdAt,
  String hook = '',
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: tagIds,
  formation: formation,
  hook: hook,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  updatedAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const DanceListScreen(),
    ),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows a loading indicator before data resolves', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));

    await _pumpScreen(tester, repos);
    // First frame: the FutureBuilder hasn't resolved yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
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
    'renders title, authors, formation chip, and tags for each dance',
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
          of: find.byType(ListTile),
          matching: find.text('Becket (CW)'),
        ),
        findsOneWidget,
      );
      expect(find.text('Beginner-friendly'), findsNWidgets(2));
      expect(find.text('1 dance'), findsOneWidget);
    },
  );

  testWidgets('announces plural dance counts', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Beta'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(find.text('2 dances'), findsOneWidget);
  });

  testWidgets('sorts by title by default', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Zesty Reel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Autumn Waltz'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['Autumn Waltz', 'Zesty Reel']);
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

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['Newer Dance', 'Older Dance']);
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

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['Called Dance', 'Never Called']);
  });

  testWidgets('text quick-filter narrows the list by title/author', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Rambling Reel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chase');
    await tester.pumpAndSettle();

    expect(find.text('Chase the Squirrel'), findsOneWidget);
    expect(find.text('Rambling Reel'), findsNothing);
    expect(find.text('1 dance'), findsOneWidget);
  });

  testWidgets('tag chip filters the list', (tester) async {
    final repos = openTestRepositories();
    await repos.tags.upsert(Tag(id: 't1', name: 'Classic'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Chase the Squirrel', tagIds: const ['t1']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Rambling Reel'));

    await _pumpScreen(tester, repos);
    await tester.pumpAndSettle();

    expect(find.text('2 dances'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Classic'));
    await tester.pumpAndSettle();

    expect(find.text('Chase the Squirrel'), findsOneWidget);
    expect(find.text('Rambling Reel'), findsNothing);
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
}
