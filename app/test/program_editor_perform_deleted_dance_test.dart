import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Guards [ProgramEditorScreen]'s Perform entry point: it must hand the
/// soft-deleted slot dances it resolves to [PerformProgramScreen.danceOverrides]
/// (the summary's twin is in `program_summary_perform_deleted_dance_test.dart`).
/// Kept out of `program_editor_screen_test.dart` so it cannot conflict with
/// other edits to that file.
void main() {
  testWidgets('Perform from the editor keeps a soft-deleted slot dance and '
      'marks it deleted', (tester) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Gone Dance',
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.dances.softDelete('d1', at: _now);
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
        home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();

    final perform = find.byType(PerformProgramScreen);
    expect(perform, findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(perform));
    expect(tester.widget<PerformProgramScreen>(perform).danceOverrides.keys, [
      'd1',
    ]);
    expect(
      find.text('Gone Dance ${l10n.programsDeletedDanceFallback}'),
      findsOneWidget,
    );
    expect(find.text(l10n.programsDanceUnavailable), findsNothing);
  });

  testWidgets('Perform from the editor shows the author of a soft-deleted slot '
      'dance whose choreographer is also soft-deleted', (tester) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Gene Hubert'),
    );
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Gone Dance',
        authorIds: const ['c1'],
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.dances.softDelete('d1', at: _now);
    await repos.choreographers.delete('c1', at: _now);
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
        home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformProgramScreen), findsOneWidget);
    expect(find.text('Gene Hubert'), findsOneWidget);
  });
}
