import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  String programId,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
      home: ProgramSummaryScreen(programId: programId),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summary shows pay with its currency alongside the details', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        band: 'The Fiddleheads',
        status: ProgramStatus.draft,
        slots: const [],
        payMinorUnits: 25050,
        payCurrency: 'USD',
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos, 'p1');

    expect(find.text('Band: The Fiddleheads'), findsOneWidget);
    expect(find.text('Pay: 250.50 USD'), findsOneWidget);
  });

  testWidgets('pay is formatted by the currency exponent', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: const [],
        payMinorUnits: 5000,
        payCurrency: 'JPY',
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos, 'p1');

    expect(find.text('Pay: 5000 JPY'), findsOneWidget);
  });

  testWidgets('summary shows no pay row when no pay is recorded', (
    tester,
  ) async {
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
    await _pump(tester, repos, 'p1');

    expect(find.textContaining('Pay:'), findsNothing);
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
  });
}
