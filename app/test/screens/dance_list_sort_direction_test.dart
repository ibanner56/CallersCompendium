import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import '../support/test_repositories.dart';

/// The Collection list sort-direction toggle (issue #349): the default matches
/// the historical order and flipping the toggle reverses it.
void main() {
  Dance dance(String id, String title) {
    final now = DateTime.utc(2026);
    return Dance(id: id, title: title, createdAt: now, updatedAt: now);
  }

  Future<CompendiumRepositories> seed() async {
    final repos = openTestRepositories();
    await repos.ensureMigrated();
    await repos.dances.create(dance('a', 'Alpha'));
    await repos.dances.create(dance('b', 'Bravo'));
    await repos.dances.create(dance('c', 'Charlie'));
    return repos;
  }

  Future<void> pumpList(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: ValueNotifier<Dialect>(Dialect.larksRobins),
          child: const MaterialApp(home: DanceListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> tileTitles(WidgetTester tester) => [
    for (final tile in tester.widgetList<DanceListTile>(
      find.byType(DanceListTile),
    ))
      tile.entry.dance.title,
  ];

  Icon directionIcon(WidgetTester tester) =>
      tester
              .widget<IconButton>(
                find.byKey(const ValueKey('collection-sort-direction')),
              )
              .icon
          as Icon;

  testWidgets('title defaults to ascending (A→Z)', (tester) async {
    final repos = await seed();
    await pumpList(tester, repos);

    expect(tileTitles(tester), ['Alpha', 'Bravo', 'Charlie']);
    expect(directionIcon(tester).icon, Icons.arrow_upward);
  });

  testWidgets('flipping the toggle reverses to descending (Z→A)', (
    tester,
  ) async {
    final repos = await seed();
    await pumpList(tester, repos);

    await tester.tap(find.byKey(const ValueKey('collection-sort-direction')));
    await tester.pumpAndSettle();

    expect(tileTitles(tester), ['Charlie', 'Bravo', 'Alpha']);
    expect(directionIcon(tester).icon, Icons.arrow_downward);
  });
}
