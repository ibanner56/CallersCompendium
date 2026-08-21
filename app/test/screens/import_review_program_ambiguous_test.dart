import 'package:compendium_app/src/data/program_ambiguous_review.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// One `ImportRecordPlan` seed for a program-ambiguity candidate, previewed as
/// a brand-new dance (the common case: the online candidate has no local
/// match), tagged with [id] so tests can tell which candidate committed.
ImportRecordPlan _plan(String title, String id) => ImportRecordPlan(
  draft: StructuredDraft(
    dance: Dance(
      id: '',
      title: title,
      authorIds: const [],
      tagIds: const [],
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: const [],
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    raw: RawRecord(
      source: ProvenanceSource.callersbox,
      externalId: id,
      payload: '{}',
    ),
  ),
  verdict: DedupeVerdict.isNew(),
);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required ProgramAmbiguousImport programAmbiguousImport,
  required void Function(Map<int, String>) onProgramCommitted,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          sources: defaultImportSources(),
          programAmbiguousImport: programAmbiguousImport,
          onProgramCommitted: onProgramCommitted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'seeding skips the input phase and lands directly on the grouped review, '
    'with a heading per line and every candidate defaulted to skip',
    (tester) async {
      final repos = openTestRepositories();
      final seed = ProgramAmbiguousImport(
        lines: [
          ProgramAmbiguousLine(
            originalLineIndex: 2,
            lineText: 'Petronella',
            candidates: [
              _plan('Petronella', 'cb-1'),
              _plan('Petronella', 'cd-1'),
            ],
          ),
        ],
      );

      await _pump(
        tester,
        repos,
        programAmbiguousImport: seed,
        onProgramCommitted: (_) {},
      );

      // No source dropdown / paste field — the manual input phase never shows.
      expect(find.byKey(const ValueKey('import-source-select')), findsNothing);
      expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('import-program-line-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('import-row-1')), findsOneWidget);
      // Both candidates default to skip: nothing pre-selected, so Import is
      // disabled until the user picks something.
      final commitButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-commit-button')),
      );
      expect(commitButton.onPressed, isNull);
    },
  );

  testWidgets(
    'picking one candidate and committing imports it and reports its line '
    'index back via onProgramCommitted',
    (tester) async {
      final repos = openTestRepositories();
      final seed = ProgramAmbiguousImport(
        lines: [
          ProgramAmbiguousLine(
            originalLineIndex: 0,
            lineText: 'Petronella',
            candidates: [
              _plan('Petronella', 'cb-1'),
              _plan('Petronella', 'cd-1'),
            ],
          ),
        ],
      );
      Map<int, String>? reported;

      await _pump(
        tester,
        repos,
        programAmbiguousImport: seed,
        onProgramCommitted: (result) => reported = result,
      );

      // Pick "New dance" for the first candidate row.
      await tester.tap(find.byKey(const ValueKey('import-row-0-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-done-button')));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.keys, [0]);
      final danceId = reported![0]!;
      final created = await repos.dances.getById(danceId);
      expect(created, isNotNull);
      expect(created!.title, 'Petronella');
    },
  );

  testWidgets(
    'leaving every candidate at skip and committing reports no line, and '
    'writes nothing',
    (tester) async {
      final repos = openTestRepositories();
      final seed = ProgramAmbiguousImport(
        lines: [
          ProgramAmbiguousLine(
            originalLineIndex: 0,
            lineText: 'Petronella',
            candidates: [_plan('Petronella', 'cb-1')],
          ),
        ],
      );
      Map<int, String>? reported;

      // This line has no other importable path (single candidate, defaulted
      // to skip) and no shared-bundle programs, so the Import button stays
      // disabled — there is nothing to commit. Confirm that directly rather
      // than trying to force a no-op commit.
      await _pump(
        tester,
        repos,
        programAmbiguousImport: seed,
        onProgramCommitted: (result) => reported = result,
      );

      final commitButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-commit-button')),
      );
      expect(commitButton.onPressed, isNull);
      expect(reported, isNull);
      expect(await repos.dances.listIdsAndTitles(), isEmpty);
    },
  );

  testWidgets(
    'picking two candidates in the same line: only the first-picked one '
    'commits, and the callback names only that one line',
    (tester) async {
      final repos = openTestRepositories();
      final seed = ProgramAmbiguousImport(
        lines: [
          ProgramAmbiguousLine(
            originalLineIndex: 0,
            lineText: 'Petronella',
            candidates: [
              _plan('Petronella', 'cb-1'),
              _plan('Petronella', 'cd-1'),
            ],
          ),
        ],
      );
      Map<int, String>? reported;

      await _pump(
        tester,
        repos,
        programAmbiguousImport: seed,
        onProgramCommitted: (result) => reported = result,
      );

      // Both candidates set to "New dance" — the UI itself has no mutual
      // exclusion, so this is exactly the backstop scenario.
      await tester.tap(find.byKey(const ValueKey('import-row-0-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-row-1-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-done-button')));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.keys, [0]);
      final titles = await repos.dances.listIdsAndTitles();
      expect(
        titles,
        hasLength(1),
        reason: 'only the first candidate for the line should ever commit',
      );
    },
  );

  testWidgets('two ambiguous lines each report their own originalLineIndex', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final seed = ProgramAmbiguousImport(
      lines: [
        ProgramAmbiguousLine(
          originalLineIndex: 0,
          lineText: 'Petronella',
          candidates: [_plan('Petronella', 'cb-1')],
        ),
        ProgramAmbiguousLine(
          originalLineIndex: 3,
          lineText: 'Chorus Jig',
          candidates: [_plan('Chorus Jig', 'cb-2')],
        ),
      ],
    );
    Map<int, String>? reported;

    await _pump(
      tester,
      repos,
      programAmbiguousImport: seed,
      onProgramCommitted: (result) => reported = result,
    );

    await tester.tap(find.byKey(const ValueKey('import-row-0-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-row-1-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-done-button')));
    await tester.pumpAndSettle();

    expect(reported, isNotNull);
    expect(reported!.keys.toSet(), {0, 3});
  });
}
