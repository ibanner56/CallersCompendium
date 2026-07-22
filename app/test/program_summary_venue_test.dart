import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('summary shows the linked venue name when venueId resolves', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(
      Venue(id: 'v1', name: 'Grange Hall', city: 'Amherst'),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        venue: 'Ignored free text',
        venueId: 'v1',
        status: ProgramStatus.draft,
        slots: const [],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos, 'p1');

    expect(find.textContaining('Grange Hall'), findsOneWidget);
    expect(find.text('Ignored free text'), findsNothing);
  });

  testWidgets('summary falls back to free text without a resolved link', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        venue: 'The Grange',
        status: ProgramStatus.draft,
        slots: const [],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos, 'p1');

    expect(find.text('The Grange'), findsOneWidget);
  });
}
