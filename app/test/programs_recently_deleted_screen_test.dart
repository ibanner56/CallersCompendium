import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart';
import 'package:compendium_app/src/screens/recently_deleted_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({required String id, required String title}) =>
    Program(id: id, title: title, createdAt: _now, updatedAt: _now);

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: RecentlyDeletedScreen.programs(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows empty state when nothing is deleted', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.textContaining('No recently deleted'), findsOneWidget);
  });

  testWidgets('lists only soft-deleted programs', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Active'));
    await repos.programs.create(_program(id: 'p2', title: 'Deleted'));
    await repos.programs.softDelete('p2', at: _now);

    await _pump(tester, repos);

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('restore brings a program back', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Bring Me Back'));
    await repos.programs.softDelete('p1', at: _now);
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('restore-p1')));
    await tester.pumpAndSettle();

    expect(await repos.programs.listAll(), hasLength(1));
  });

  testWidgets('permanent delete removes after confirmation', (tester) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Purge Me'));
    await repos.programs.softDelete('p1', at: _now);
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('permanent-delete-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
    await tester.pumpAndSettle();

    expect(await repos.programs.getById('p1', includeDeleted: true), isNull);
  });

  testWidgets(
    'permanent delete removes only the chosen program, not other expired ones '
    '(LIFE-1)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kSoftDeleteRetentionKey,
        kSoftDeleteRetentionNever,
      );
      final now = DateTime.now().toUtc();
      for (final (id, daysAgo) in [('a', 5), ('b', 60), ('c', 10)]) {
        await repos.programs.create(_program(id: id, title: 'Program $id'));
        await repos.programs.softDelete(
          id,
          at: now.subtract(Duration(days: daysAgo)),
        );
      }
      await _pump(tester, repos);

      await tester.tap(find.byKey(const ValueKey('permanent-delete-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
      await tester.pumpAndSettle();

      expect(await repos.programs.getById('a', includeDeleted: true), isNull);
      expect(
        await repos.programs.getById('b', includeDeleted: true),
        isNotNull,
      );
      expect(
        await repos.programs.getById('c', includeDeleted: true),
        isNotNull,
      );
    },
  );

  testWidgets('never-auto-purge hides the program countdown (LIFE-3)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kSoftDeleteRetentionKey,
      kSoftDeleteRetentionNever,
    );
    await repos.programs.create(_program(id: 'p1', title: 'Kept Forever'));
    await repos.programs.softDelete('p1', at: _now);

    await _pump(tester, repos);

    expect(find.textContaining('Auto-deleted in'), findsNothing);
    expect(find.text('Kept until you delete it'), findsOneWidget);
  });

  testWidgets('program purge ETA reflects the configured 90-day retention '
      '(LIFE-3)', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kSoftDeleteRetentionKey, 90);
    await repos.programs.create(_program(id: 'p1', title: 'Kept Longer'));
    // Half-day offset keeps the countdown away from an inDays boundary.
    final deletedAt = DateTime.now().toUtc().subtract(
      const Duration(days: 20, hours: 12),
    );
    await repos.programs.softDelete('p1', at: deletedAt);

    await _pump(tester, repos);

    expect(find.textContaining('Auto-deleted in 69 days'), findsOneWidget);
  });

  testWidgets('program empty-state copy reflects never-auto-purge (LIFE-3)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kSoftDeleteRetentionKey,
      kSoftDeleteRetentionNever,
    );

    await _pump(tester, repos);

    expect(
      find.textContaining('Deleted programs are kept here until you remove'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Permanently delete on a synced program hides it and says a deletion '
    'record stays (LIFE-2)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Synced Gig'));
      await repos.syncLocal.markPublished(
        kind: SyncRecordKind.program,
        recordId: 'p1',
      );
      await repos.programs.softDelete('p1', at: _now);
      await _pump(tester, repos);

      await tester.tap(find.byKey(const ValueKey('permanent-delete-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('restore-p1')), findsNothing);
      expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
      final kept = await repos.programs.getById('p1', includeDeleted: true);
      expect(kept!.title, blankedRecordTitle);
      expect(find.textContaining('deletion record is kept'), findsOneWidget);
    },
  );
}
