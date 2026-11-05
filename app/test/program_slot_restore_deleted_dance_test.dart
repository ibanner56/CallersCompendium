import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// A program slot whose dance is in Recently deleted offers Restore in the
/// builder and the summary (LIFE-8), and every surface drops the slot's
/// "deleted" marking once the dance is restored, wherever the restore was made.
void main() {
  Future<CompendiumRepositories> seed() async {
    final repos = openTestRepositories();
    for (final (id, title) in [('d1', 'Gone Dance'), ('d2', 'Live Dance')]) {
      await repos.dances.create(
        Dance(
          id: id,
          title: title,
          status: DanceStatus.active,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
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
    await repos.dances.softDelete('d1', at: _now);
    return repos;
  }

  Future<void> pump(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
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
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  group('the program builder', () {
    const editor = ProgramEditorScreen(programId: 'p1');
    String? slotTitle(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('slot-s1-title'))).data;

    testWidgets('restores the dance from the slot menu, and the slot drops '
        'its marking', (tester) async {
      final repos = await seed();
      await pump(tester, repos, editor);
      expect(slotTitle(tester), 'Gone Dance (deleted dance)');

      // A live dance's slot offers no Restore.
      await tester.tap(find.byKey(const ValueKey('slot-1-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-1-restore-dance')), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();
      expect(
        find.text(l10nOf(tester).programsRestoreDeletedDance),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('slot-0-restore-dance')));
      await tester.pumpAndSettle();

      expect((await repos.dances.getById('d1'))?.isDeleted, isFalse);
      expect(
        find.text(l10nOf(tester).recentlyDeletedRestoredDance('Gone Dance')),
        findsOneWidget,
      );
      expect(slotTitle(tester), 'Gone Dance');
      await tester.tap(find.byKey(const ValueKey('slot-0-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slot-0-restore-dance')), findsNothing);
    });

    testWidgets('drops the marking when the dance is restored elsewhere', (
      tester,
    ) async {
      final repos = await seed();
      await pump(tester, repos, editor);
      expect(slotTitle(tester), 'Gone Dance (deleted dance)');

      // Recently deleted, or a Device Sync apply, writes the restore.
      await repos.dances.restore('d1', at: _now);
      await tester.pumpAndSettle();

      expect(slotTitle(tester), 'Gone Dance');
    });
  });

  group('the program summary', () {
    const summary = ProgramSummaryScreen(programId: 'p1');
    const restore = ValueKey('summary-slot-s1-restore-dance');

    testWidgets('restores the dance from its row, and the row drops its '
        'marking', (tester) async {
      final repos = await seed();
      await pump(tester, repos, summary);
      expect(find.text('Gone Dance (deleted dance)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('summary-slot-s2-restore-dance')),
        findsNothing,
      );

      await tester.tap(find.byKey(restore));
      await tester.pumpAndSettle();

      expect((await repos.dances.getById('d1'))?.isDeleted, isFalse);
      expect(
        find.text(l10nOf(tester).recentlyDeletedRestoredDance('Gone Dance')),
        findsOneWidget,
      );
      expect(find.text('Gone Dance (deleted dance)'), findsNothing);
      expect(find.text('Gone Dance'), findsOneWidget);
      expect(find.byKey(restore), findsNothing);
    });

    testWidgets('drops the marking when the dance is restored elsewhere', (
      tester,
    ) async {
      final repos = await seed();
      await pump(tester, repos, summary);
      expect(find.byKey(restore), findsOneWidget);

      await repos.dances.restore('d1', at: _now);
      await tester.pumpAndSettle();

      expect(find.text('Gone Dance (deleted dance)'), findsNothing);
      expect(find.text('Gone Dance'), findsOneWidget);
      expect(find.byKey(restore), findsNothing);
    });
  });
}
