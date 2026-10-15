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

/// Guards the "Program adjusted" Undo once Perform has been left (flows-1).
///
/// The undo restores a whole-program snapshot taken before the adjustment. If
/// the program changed after the adjustment, restoring that snapshot would
/// overwrite the later change, so the undo must be refused instead.
void main() {
  Future<CompendiumRepositories> pumpSummary(
    WidgetTester tester, {
    CompendiumRepositories? using,
  }) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = using ?? openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'First Dance',
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
    return repos;
  }

  /// Opens Perform from the summary, marks the current dance performed, and
  /// leaves Perform, so the "Program adjusted" Undo outlives the screen.
  Future<void> adjustAndLeave(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-adjust')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsNothing);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ProgramSummaryScreen)));

  testWidgets('Undo after leaving Perform is refused when the program changed '
      'since, and the later change is kept', (tester) async {
    final repos = await pumpSummary(tester);
    await adjustAndLeave(tester);

    final adjusted = (await repos.programs.getById('p1'))!;
    expect(adjusted.slots.single.performedAt, isNotNull);
    // An edit made after leaving Perform (from the editor, or a Device Sync
    // apply): a rename, stamped later than the adjustment.
    await repos.programs.update(
      adjusted.copyWith(
        title: 'Renamed Night',
        updatedAt: adjusted.updatedAt.add(const Duration(minutes: 1)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10nOf(tester).commonUndo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.title, 'Renamed Night');
    expect(stored.slots.single.performedAt, isNotNull);
    expect(
      find.text(l10nOf(tester).performUndoNoLongerAvailable),
      findsOneWidget,
    );
  });

  testWidgets('Undo after leaving Perform still restores the program when '
      'nothing changed since', (tester) async {
    final repos = await pumpSummary(tester);
    await adjustAndLeave(tester);
    expect(
      (await repos.programs.getById('p1'))!.slots.single.performedAt,
      isNotNull,
    );

    await tester.tap(find.text(l10nOf(tester).commonUndo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.title, 'Barn Dance');
    expect(stored.slots.single.performedAt, isNull);
    expect(
      find.text(l10nOf(tester).performUndoNoLongerAvailable),
      findsNothing,
    );
  });

  testWidgets('Undo after leaving Perform is refused when the program was '
      'changed within the same second as the adjustment', (tester) async {
    final repos = await pumpSummary(tester);
    await adjustAndLeave(tester);

    final adjusted = (await repos.programs.getById('p1'))!;
    // Same stored second as the adjustment: a stamp comparison at the store's
    // one-second precision cannot see this edit.
    await repos.programs.update(
      adjusted.copyWith(title: 'Renamed Night', updatedAt: adjusted.updatedAt),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10nOf(tester).commonUndo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.title, 'Renamed Night');
    expect(stored.slots.single.performedAt, isNotNull);
    expect(
      find.text(l10nOf(tester).performUndoNoLongerAvailable),
      findsOneWidget,
    );
  });

  testWidgets('a write that lands while the Undo after leaving Perform is in '
      'flight is not overwritten', (tester) async {
    final delayed = openTestRepositoriesWithDelayedPrograms();
    final repos = await pumpSummary(tester, using: delayed.repos);
    await adjustAndLeave(tester);
    final adjusted = (await repos.programs.getById('p1'))!;

    // Hold the Undo's write, land another edit, then let the Undo finish.
    delayed.programs.holdNextWrite();
    await tester.tap(find.text(l10nOf(tester).commonUndo));
    await tester.pump();
    await delayed.programs.writeStarted;
    await repos.programs.update(
      adjusted.copyWith(
        title: 'Renamed Night',
        updatedAt: adjusted.updatedAt.add(const Duration(minutes: 1)),
      ),
    );
    delayed.programs.releaseWrite();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.title, 'Renamed Night');
    expect(stored.slots.single.performedAt, isNotNull);
    expect(
      find.text(l10nOf(tester).performUndoNoLongerAvailable),
      findsOneWidget,
    );
  });
}
