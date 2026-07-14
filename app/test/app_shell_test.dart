import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/app_shell.dart';

import 'support/test_repositories.dart';

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('narrow layout uses a bottom NavigationBar', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Collection is the default tab.
    expect(find.text('Collection'), findsWidgets);
  });

  testWidgets('wide layout uses a NavigationRail', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('switching to Programs shows the Programs screen', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Nav Target Program',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(500, 900));

    // Tap the Programs destination in the bottom bar.
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();

    expect(find.text('Nav Target Program'), findsOneWidget);

    // Switching back keeps the Collection alive.
    await tester.tap(find.text('Collection').last);
    await tester.pumpAndSettle();
    expect(find.text('Nav Target Program'), findsNothing);
  });

  testWidgets('Ctrl-K opens the global search palette', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });

  testWidgets('the rail search button opens the palette (wide)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.tap(find.byKey(const ValueKey('global-search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });

  testWidgets('the search FAB opens the palette (narrow)', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    await tester.tap(find.byKey(const ValueKey('global-search-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });
}
