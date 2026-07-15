import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart';
import 'package:compendium_app/src/screens/recently_deleted_screen.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Test Dance',
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const RecentlyDeletedScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows empty state when nothing is deleted', (tester) async {
    final repos = openTestRepositories();

    await _pumpScreen(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.textContaining('Nothing in the trash'), findsOneWidget);
  });

  testWidgets('shows soft-deleted dances and not active dances', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Active Dance'));
    await repos.dances.create(_dance(id: 'd2', title: 'Deleted Dance'));
    await repos.dances.softDelete('d2', at: _now);

    await _pumpScreen(tester, repos);

    expect(find.text('Deleted Dance'), findsOneWidget);
    expect(find.text('Active Dance'), findsNothing);
  });

  testWidgets('shows purge ETA for each deleted dance', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Expiring Soon'));
    // Deleted 20 days ago → 10 days left; ample margin so the
    // DateTime.now() call in the widget stays well away from an inDays boundary.
    final deletedAt = DateTime.now().toUtc().subtract(const Duration(days: 20));
    await repos.dances.softDelete('d1', at: deletedAt);

    await _pumpScreen(tester, repos);

    expect(find.textContaining('Auto-deleted in'), findsOneWidget);
    expect(find.textContaining('days'), findsOneWidget);
  });

  testWidgets('purge ETA reflects the configured 90-day retention (G.4)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kSoftDeleteRetentionKey, 90);
    await repos.dances.create(_dance(id: 'd1', title: 'Kept Longer'));
    // Deleted 20.5 days ago: a 30-day window would leave ~9 days, but the
    // 90-day window leaves ~69 — proving the screen reads the configured value.
    // The half-day offset keeps the countdown mid-integer, away from an inDays
    // boundary that a few ms of test execution could tip.
    final deletedAt = DateTime.now().toUtc().subtract(
      const Duration(days: 20, hours: 12),
    );
    await repos.dances.softDelete('d1', at: deletedAt);

    await _pumpScreen(tester, repos);

    expect(find.textContaining('Auto-deleted in 69 days'), findsOneWidget);
  });

  testWidgets('never-auto-purge hides the countdown (G.4)', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kSoftDeleteRetentionKey,
      kSoftDeleteRetentionNever,
    );
    await repos.dances.create(_dance(id: 'd1', title: 'Kept Forever'));
    await repos.dances.softDelete('d1', at: _now);

    await _pumpScreen(tester, repos);

    expect(find.textContaining('Auto-deleted in'), findsNothing);
    expect(find.text('Kept until you delete it'), findsOneWidget);
  });

  testWidgets('empty-state copy reflects never-auto-purge (G.4)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kSoftDeleteRetentionKey,
      kSoftDeleteRetentionNever,
    );

    await _pumpScreen(tester, repos);

    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(
      find.textContaining('kept here until you remove them'),
      findsOneWidget,
    );
  });

  testWidgets('Restore button moves the dance back to the active collection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Bring Me Back'));
    await repos.dances.softDelete('d1', at: _now);

    await _pumpScreen(tester, repos);

    expect(find.text('Bring Me Back'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-d1')));
    await tester.pumpAndSettle();

    // After restore, dance is no longer in the deleted list.
    expect(find.text('Bring Me Back'), findsNothing);
    // Empty state is shown.
    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);

    // Dance is active in storage.
    final dance = await repos.dances.getById('d1');
    expect(dance, isNotNull);
    expect(dance!.deletedAt, isNull);

    // Snackbar confirms restoration.
    expect(find.textContaining('restored'), findsOneWidget);
  });

  testWidgets('multiple dances can be restored independently', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'First Deleted'));
    await repos.dances.create(_dance(id: 'd2', title: 'Second Deleted'));
    await repos.dances.softDelete('d1', at: _now);
    await repos.dances.softDelete('d2', at: _now);

    await _pumpScreen(tester, repos);

    expect(find.text('First Deleted'), findsOneWidget);
    expect(find.text('Second Deleted'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-d1')));
    await tester.pumpAndSettle();

    // Only d2 remains in the list.
    expect(find.text('First Deleted'), findsNothing);
    expect(find.text('Second Deleted'), findsOneWidget);
  });

  testWidgets(
    'Permanently delete button shows a confirm dialog and hard-deletes on confirm',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Gone Forever'));
      await repos.dances.softDelete('d1', at: _now);

      await _pumpScreen(tester, repos);

      await tester.tap(find.byKey(const ValueKey('permanent-delete-d1')));
      await tester.pumpAndSettle();

      // Confirm dialog appears.
      expect(find.text('Delete permanently?'), findsOneWidget);
      expect(find.textContaining('cannot be recovered'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
      await tester.pumpAndSettle();

      // Dance is gone from the recently-deleted list.
      expect(find.text('Gone Forever'), findsNothing);
      expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);

      // Dance is hard-deleted from storage.
      final dance = await repos.dances.getById('d1', includeDeleted: true);
      expect(dance, isNull);

      // Snackbar confirms permanent deletion.
      expect(find.textContaining('permanently deleted'), findsOneWidget);
    },
  );

  testWidgets('Permanently delete dialog cancel leaves the dance in place', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Safe Dance'));
    await repos.dances.softDelete('d1', at: _now);

    await _pumpScreen(tester, repos);

    await tester.tap(find.byKey(const ValueKey('permanent-delete-d1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Dance is still in the list.
    expect(find.text('Safe Dance'), findsOneWidget);

    // Dance is still soft-deleted in storage.
    final dance = await repos.dances.getById('d1', includeDeleted: true);
    expect(dance, isNotNull);
    expect(dance!.deletedAt, isNotNull);
  });
}
