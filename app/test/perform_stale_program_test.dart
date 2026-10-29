import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Guards GIG-6: Perform runs on the copy of the program it opened with, so a
/// change that lands while it is open (Device Sync, typically) must not be
/// overwritten by an adjustment written from that copy. The adjustment is
/// applied on top of the newer program instead, Perform shows the newer
/// program, and the caller is told.
void main() {
  Dance dance(String id, String title) => Dance(
    id: id,
    title: title,
    figures: [
      Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
    ],
    status: DanceStatus.active,
    createdAt: _now,
    updatedAt: _now,
  );

  Future<void> seed(CompendiumRepositories repos) async {
    await repos.dances.create(dance('d1', 'First Dance'));
    await repos.dances.create(dance('d2', 'Second Dance'));
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
  }

  Future<void> pumpHome(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget home,
  ) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final autoCommit = ValueNotifier<bool>(false);
    addTearDown(autoCommit.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ProgramAutoCommitScope(notifier: autoCommit, child: child!),
          ),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The change a Device Sync apply makes while Perform is open: the program
  /// renamed and a break added at the end, stamped later.
  Future<void> changeElsewhere(CompendiumRepositories repos) async {
    final stored = (await repos.programs.getById('p1'))!;
    await repos.programs.update(
      stored.copyWith(
        title: 'Renamed Night',
        slots: [
          ...stored.slots,
          ProgramSlot(id: 's3', position: stored.slots.length, text: 'Break'),
        ],
        updatedAt: stored.updatedAt.add(const Duration(minutes: 5)),
      ),
    );
  }

  Future<void> markCurrentPerformed(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('perform-adjust')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-done')));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(PerformProgramScreen)));

  String position(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('perform-position'))).data!;

  void expectBothChangesKept(Program stored) {
    expect(stored.title, 'Renamed Night');
    expect(stored.slots.map((s) => s.id), ['s1', 's2', 's3']);
    expect(stored.slots.first.performedAt, isNotNull);
  }

  group('from the summary', () {
    testWidgets('an adjustment after a change elsewhere keeps that change, and '
        'Perform shows it and says so', (tester) async {
      final repos = openTestRepositories();
      await seed(repos);
      await pumpHome(
        tester,
        repos,
        const ProgramSummaryScreen(programId: 'p1'),
      );
      await tester.tap(find.byKey(const ValueKey('summary-perform')));
      await tester.pumpAndSettle();
      expect(position(tester), 'Slot 1 of 2');

      await changeElsewhere(repos);
      await tester.pumpAndSettle();
      await markCurrentPerformed(tester);

      expect(tester.takeException(), isNull);
      expectBothChangesKept((await repos.programs.getById('p1'))!);
      expect(position(tester), 'Slot 1 of 3');
      expect(
        find.text(l10nOf(tester).performProgramChangedElsewhere),
        findsOneWidget,
      );
    });

    testWidgets('a change landing while the adjustment is being written is not '
        'overwritten', (tester) async {
      final delayed = openTestRepositoriesWithDelayedPrograms();
      final repos = delayed.repos;
      await seed(repos);
      await pumpHome(
        tester,
        repos,
        const ProgramSummaryScreen(programId: 'p1'),
      );
      await tester.tap(find.byKey(const ValueKey('summary-perform')));
      await tester.pumpAndSettle();

      delayed.programs.holdNextWrite();
      await tester.tap(find.byKey(const ValueKey('perform-adjust')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-done')));
      await tester.pump();
      await delayed.programs.writeStarted;
      await changeElsewhere(repos);
      delayed.programs.releaseWrite();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectBothChangesKept((await repos.programs.getById('p1'))!);
      expect(
        find.text(l10nOf(tester).performProgramChangedElsewhere),
        findsOneWidget,
      );
    });

    testWidgets('an adjustment with nothing changed elsewhere says nothing', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await seed(repos);
      await pumpHome(
        tester,
        repos,
        const ProgramSummaryScreen(programId: 'p1'),
      );
      await tester.tap(find.byKey(const ValueKey('summary-perform')));
      await tester.pumpAndSettle();

      await markCurrentPerformed(tester);
      // A second adjustment compares with the first one's write, not with the
      // program Perform opened with.
      await tester.tap(find.byKey(const ValueKey('perform-next')));
      await tester.pump();
      await markCurrentPerformed(tester);

      final stored = (await repos.programs.getById('p1'))!;
      expect(stored.slots.map((s) => s.performedAt != null), [true, true]);
      expect(
        find.text(l10nOf(tester).performProgramChangedElsewhere),
        findsNothing,
      );
    });

    testWidgets('Undo, in Perform and after it, reverses only the adjustment '
        'and keeps the change from elsewhere', (tester) async {
      final repos = openTestRepositories();
      await seed(repos);
      await pumpHome(
        tester,
        repos,
        const ProgramSummaryScreen(programId: 'p1'),
      );
      await tester.tap(find.byKey(const ValueKey('summary-perform')));
      await tester.pumpAndSettle();
      await changeElsewhere(repos);
      await tester.pumpAndSettle();
      await markCurrentPerformed(tester);

      // The notice offers the adjustment's Undo.
      await tester.tap(find.text(l10nOf(tester).commonUndo));
      await tester.pumpAndSettle();
      var stored = (await repos.programs.getById('p1'))!;
      expect(stored.title, 'Renamed Night');
      expect(stored.slots.map((s) => s.id), ['s1', 's2', 's3']);
      expect(stored.slots.first.performedAt, isNull);
      expect(position(tester), 'Slot 1 of 3');

      // Again, and this time Undo after leaving Perform.
      await markCurrentPerformed(tester);
      await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(PerformProgramScreen), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      stored = (await repos.programs.getById('p1'))!;
      expect(stored.title, 'Renamed Night');
      expect(stored.slots.map((s) => s.id), ['s1', 's2', 's3']);
      expect(stored.slots.first.performedAt, isNull);
    });
  });

  group('from the builder', () {
    testWidgets('an adjustment after a change elsewhere keeps that change, and '
        'Perform shows it and says so', (tester) async {
      final repos = openTestRepositories();
      await seed(repos);
      await pumpHome(tester, repos, const ProgramEditorScreen(programId: 'p1'));
      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();

      await changeElsewhere(repos);
      await tester.pumpAndSettle();
      await markCurrentPerformed(tester);

      expect(tester.takeException(), isNull);
      expectBothChangesKept((await repos.programs.getById('p1'))!);
      expect(position(tester), 'Slot 1 of 3');
      expect(
        find.text(l10nOf(tester).performProgramChangedElsewhere),
        findsOneWidget,
      );
    });

    testWidgets('a change landing while the adjustment is being written is not '
        'overwritten', (tester) async {
      final delayed = openTestRepositoriesWithDelayedPrograms();
      final repos = delayed.repos;
      await seed(repos);
      await pumpHome(tester, repos, const ProgramEditorScreen(programId: 'p1'));
      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();

      delayed.programs.holdNextWrite();
      await tester.tap(find.byKey(const ValueKey('perform-adjust')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-done')));
      await tester.pump();
      await delayed.programs.writeStarted;
      await changeElsewhere(repos);
      delayed.programs.releaseWrite();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectBothChangesKept((await repos.programs.getById('p1'))!);
      expect(
        find.text(l10nOf(tester).performProgramChangedElsewhere),
        findsOneWidget,
      );
    });
  });
}
