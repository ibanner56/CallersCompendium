import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({required String id, required String title}) => Program(
  id: id,
  title: title,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpWide(WidgetTester tester, CompendiumRepositories repos) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'wide split-pane list and summary FABs coexist and survive a route '
    'transition without a duplicate hero-tag crash',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Barn Dance'));

      await _pumpWide(tester, repos);

      // Select the program so the summary pane (and its "Open builder" FAB)
      // renders alongside the list pane's "New program" FAB.
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // Both default-styled FABs are present in the same subtree. Before the
      // fix they shared the default Hero tag, which crashed on the next route
      // transition with "multiple heroes that share the same tag".
      expect(find.byKey(const ValueKey('new-program')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-builder')), findsOneWidget);

      // Opening the builder pushes a full-screen route, driving a Hero
      // transition that scans the outgoing subtree for heroes.
      await tester.tap(find.byKey(const ValueKey('open-builder')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ProgramEditorScreen), findsOneWidget);
    },
  );
}
