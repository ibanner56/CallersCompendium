import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Guards [ProgramSummaryScreen]'s Perform entry point: it must hand the
/// soft-deleted slot dances it resolves to [PerformProgramScreen.danceOverrides]
/// (the editor's twin is in `program_editor_perform_deleted_dance_test.dart`).
void main() {
  testWidgets('Perform from the summary keeps a soft-deleted slot dance and '
      'marks it deleted', (tester) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
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
        home: const ProgramSummaryScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('summary-perform')));
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
}
