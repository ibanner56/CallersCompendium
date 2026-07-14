import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  required String id,
  required String title,
  DateTime? eventDate,
  String? venue,
  ProgramStatus status = ProgramStatus.draft,
  DateTime? updatedAt,
  List<ProgramSlot> slots = const [],
}) => Program(
  id: id,
  title: title,
  eventDate: eventDate,
  venue: venue,
  status: status,
  slots: slots,
  createdAt: _now,
  updatedAt: updatedAt ?? _now,
);

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const ProgramsListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('empty state teaches and offers New program', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.text('No programs yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-new-program')), findsOneWidget);
  });

  testWidgets('lists non-deleted programs with status chip icon+text', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(id: 'p1', title: 'Friday Night', status: ProgramStatus.draft),
    );
    await repos.programs.create(
      _program(id: 'p2', title: 'Gone', status: ProgramStatus.performed),
    );
    await repos.programs.softDelete('p2', at: _now);

    await _pump(tester, repos);

    expect(find.text('Friday Night'), findsOneWidget);
    expect(find.text('Gone'), findsNothing);
    // Status chip pairs an icon with text.
    expect(find.text('Draft'), findsOneWidget);
    expect(find.byType(ProgramListTile), findsOneWidget);
    expect(find.text('1 program'), findsOneWidget);
  });

  testWidgets('sorts by title, recently updated, and event date', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program(
        id: 'p1',
        title: 'Zeta',
        eventDate: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repos.programs.create(
      _program(
        id: 'p2',
        title: 'Alpha',
        eventDate: DateTime.utc(2026, 3, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      ),
    );
    await _pump(tester, repos);

    List<String> titlesInOrder() => tester
        .widgetList<ProgramListTile>(find.byType(ProgramListTile))
        .map((t) => t.program.title)
        .toList();

    // Default: title A→Z.
    expect(titlesInOrder(), ['Alpha', 'Zeta']);

    // Recently updated: p2 (Feb) before p1 (Jan).
    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently updated').last);
    await tester.pumpAndSettle();
    expect(titlesInOrder(), ['Alpha', 'Zeta']);

    // Event date: p2 (Mar) before p1 (May).
    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event date').last);
    await tester.pumpAndSettle();
    expect(titlesInOrder(), ['Alpha', 'Zeta']);
  });

  testWidgets('swipe to delete soft-deletes with undo', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Swipe Me'));
    await _pump(tester, repos);

    await tester.drag(find.text('Swipe Me'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Swipe Me'), findsNothing);
    expect(
      find.byKey(const ValueKey('program-deleted-snackbar')),
      findsOneWidget,
    );
    expect((await repos.programs.listAll()), isEmpty);

    // Undo restores it.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repos.programs.listAll()), hasLength(1));
  });
}
