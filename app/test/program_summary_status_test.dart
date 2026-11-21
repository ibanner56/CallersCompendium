import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: const ProgramSummaryScreen(programId: 'p1'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CompendiumRepositories> _repos() async {
  final repos = openTestRepositories();
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Barn Dance',
      status: ProgramStatus.draft,
      slots: const [],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'the status reads as a start-aligned line under the title, not a chip '
      '(text scale $scale)',
      (tester) async {
        await _pump(tester, await _repos(), textScale: scale);

        // A Chip is a button-shaped control; the status must not be one.
        expect(find.byType(Chip), findsNothing);
        expect(find.text('Draft'), findsOneWidget);

        final status = find.byKey(const ValueKey('program-summary-status'));
        final titleLeft = tester.getTopLeft(find.text('Barn Dance')).dx;
        expect(tester.getTopLeft(status).dx, titleLeft);
        expect(
          tester.getTopLeft(find.byIcon(Icons.edit_note_outlined)).dx,
          titleLeft,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
