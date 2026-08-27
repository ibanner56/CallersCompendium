import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/recently_deleted_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({required String id, required String title}) =>
    Program(id: id, title: title, createdAt: _now, updatedAt: _now);

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: RecentlyDeletedScreen.programs(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows empty state when nothing is deleted', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.textContaining('Nothing in the trash'), findsOneWidget);
  });

  testWidgets('lists only soft-deleted programs', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Active'));
    await repos.programs.create(_program(id: 'p2', title: 'Deleted'));
    await repos.programs.softDelete('p2', at: _now);

    await _pump(tester, repos);

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('restore brings a program back', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Bring Me Back'));
    await repos.programs.softDelete('p1', at: _now);
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('restore-p1')));
    await tester.pumpAndSettle();

    expect(await repos.programs.listAll(), hasLength(1));
  });

  testWidgets('permanent delete removes after confirmation', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Purge Me'));
    await repos.programs.softDelete('p1', at: _now);
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('permanent-delete-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
    await tester.pumpAndSettle();

    expect(await repos.programs.getById('p1', includeDeleted: true), isNull);
  });
}
