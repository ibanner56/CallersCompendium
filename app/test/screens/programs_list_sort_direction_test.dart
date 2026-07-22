import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

/// The Programs list sort-direction toggle (issue #349). Verifies the default
/// (ascending) matches the historical order and that flipping reverses it —
/// directly covering the reporter's "Event date, latest first" case.
void main() {
  Program program(String id, String title, DateTime eventDate) {
    final now = DateTime.utc(2026);
    return Program(
      id: id,
      title: title,
      eventDate: eventDate,
      slots: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<CompendiumRepositories> seed() async {
    final repos = openTestRepositories();
    await repos.ensureMigrated();
    // Event-date order (B < C < A) deliberately differs from title order so the
    // assertions prove we sort by event date, not alphabetically.
    await repos.programs.create(program('a', 'A', DateTime.utc(2026, 3)));
    await repos.programs.create(program('b', 'B', DateTime.utc(2026, 1)));
    await repos.programs.create(program('c', 'C', DateTime.utc(2026, 2)));
    return repos;
  }

  Future<void> pumpList(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: const MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: ProgramsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> tileTitles(WidgetTester tester) => [
    for (final tile in tester.widgetList<ProgramListTile>(
      find.byType(ProgramListTile),
    ))
      tile.program.title,
  ];

  Future<void> selectEventDateSort(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('programs-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event date').last);
    await tester.pumpAndSettle();
  }

  testWidgets('event date defaults to ascending (soonest first)', (
    tester,
  ) async {
    final repos = await seed();
    await pumpList(tester, repos);

    await selectEventDateSort(tester);

    expect(tileTitles(tester), ['B', 'C', 'A']);
    // The toggle starts in the ascending state for event date.
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('programs-sort-direction')),
          )
          .icon,
      isA<Icon>().having((i) => i.icon, 'icon', Icons.arrow_upward),
    );
  });

  testWidgets('flipping event date to descending shows latest first', (
    tester,
  ) async {
    final repos = await seed();
    await pumpList(tester, repos);

    await selectEventDateSort(tester);
    await tester.tap(find.byKey(const ValueKey('programs-sort-direction')));
    await tester.pumpAndSettle();

    // Reporter's case: latest event first.
    expect(tileTitles(tester), ['A', 'C', 'B']);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('programs-sort-direction')),
          )
          .icon,
      isA<Icon>().having((i) => i.icon, 'icon', Icons.arrow_downward),
    );
  });

  testWidgets('changing the sort key resets direction to that key default', (
    tester,
  ) async {
    final repos = await seed();
    await pumpList(tester, repos);

    // Flip title to descending first…
    await tester.tap(find.byKey(const ValueKey('programs-sort-direction')));
    await tester.pumpAndSettle();
    expect(tileTitles(tester), ['C', 'B', 'A']);

    // …then switch to Event date: direction resets to its (ascending) default.
    await selectEventDateSort(tester);
    expect(tileTitles(tester), ['B', 'C', 'A']);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('programs-sort-direction')),
          )
          .icon,
      isA<Icon>().having((i) => i.icon, 'icon', Icons.arrow_upward),
    );
  });
}
