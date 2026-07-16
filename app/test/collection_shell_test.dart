import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import 'support/test_repositories.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Dance _dance({
  required String id,
  required String title,
  List<String> authorIds = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: const [],
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Pump [CollectionShell] at a given surface [size].
/// Wide surface (≥ 900 wide) triggers the split-pane layout.
/// Use at least 1400 px wide for wide tests to give the 400 px list pane
/// enough room for its AppBar actions without overflow.
Future<void> _pumpShell(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: const CollectionShell(),
    ),
  );
}

// ── narrow layout ─────────────────────────────────────────────────────────────

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('narrow layout (< 900 px)', () {
    testWidgets('renders DanceListScreen (no split pane)', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Narrow Dance'));

      await _pumpShell(tester, repos, size: const Size(600, 900));
      await tester.pumpAndSettle();

      // Only a single DanceListScreen — no DanceDetailScreen visible
      expect(find.byType(DanceListScreen), findsOneWidget);
      expect(find.byType(DanceDetailScreen), findsNothing);
      expect(find.text('Narrow Dance'), findsOneWidget);
    });

    testWidgets('tapping a dance pushes detail as a full-screen route', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Push Me'));

      await _pumpShell(tester, repos, size: const Size(600, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push Me'));
      await tester.pumpAndSettle();

      // DanceDetailScreen pushed — list is no longer visible
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      expect(find.text('Push Me'), findsWidgets);
    });

    testWidgets('delete from detail pops back to list and removes dance', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Delete Narrow'));
      await repos.dances.create(_dance(id: 'd2', title: 'Stay Narrow'));

      await _pumpShell(tester, repos, size: const Size(600, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Narrow'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-dance')));
      await tester.pumpAndSettle();

      // Popped back to list; deleted dance gone
      expect(find.byType(DanceListScreen), findsOneWidget);
      expect(find.text('Delete Narrow'), findsNothing);
      expect(find.text('Stay Narrow'), findsOneWidget);
    });
  });

  // ── wide layout ─────────────────────────────────────────────────────────────

  group('wide layout (≥ 900 px)', () {
    testWidgets('shows list pane and empty-state detail pane side-by-side', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Wide Dance'));

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      // Both panes present simultaneously
      expect(find.byType(DanceListScreen), findsOneWidget);
      expect(find.text('Wide Dance'), findsOneWidget);

      // Empty-state placeholder (no selection yet)
      expect(find.text('Select a dance'), findsOneWidget);
      // No DanceDetailScreen yet
      expect(find.byType(DanceDetailScreen), findsNothing);
    });

    testWidgets('empty-detail pane body text uses onSurfaceVariant (AA)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      const bodyText = 'Choose a dance from the list to view its details.';
      final finder = find.text(bodyText);
      expect(finder, findsOneWidget);

      // Body text must use a text color role (onSurfaceVariant, ≥4.5:1) rather
      // than the hairline outlineVariant role it previously used.
      final textWidget = tester.widget<Text>(finder);
      final scheme = Theme.of(tester.element(finder)).colorScheme;
      expect(textWidget.style?.color, scheme.onSurfaceVariant);
      expect(textWidget.style?.color, isNot(scheme.outlineVariant));
    });

    testWidgets('selecting a dance shows detail pane without pushing a route', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Selectable Dance'));

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      expect(find.text('Select a dance'), findsOneWidget);

      await tester.tap(find.text('Selectable Dance'));
      await tester.pumpAndSettle();

      // Detail screen now visible inline (no full-screen route push)
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      // Placeholder is gone
      expect(find.text('Select a dance'), findsNothing);
      // List is still visible alongside detail
      expect(find.byType(DanceListScreen), findsOneWidget);
    });

    testWidgets('selecting a different dance swaps the detail pane content', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha Dance'));
      await repos.dances.create(_dance(id: 'd2', title: 'Beta Dance'));

      // Use a tall surface so both tiles are visible without scrolling.
      await _pumpShell(tester, repos, size: const Size(1400, 3000));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha Dance'));
      await tester.pumpAndSettle();

      // Detail shows Alpha
      expect(
        find.descendant(
          of: find.byType(DanceDetailScreen),
          matching: find.text('Alpha Dance'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Beta Dance'));
      await tester.pumpAndSettle();

      // Detail now shows Beta
      expect(
        find.descendant(
          of: find.byType(DanceDetailScreen),
          matching: find.text('Beta Dance'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'delete in wide detail pane refreshes list and clears selection',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'd1', title: 'Delete Wide'));
        await repos.dances.create(_dance(id: 'd2', title: 'Keep Wide'));

        await _pumpShell(tester, repos, size: const Size(1400, 3000));
        await tester.pumpAndSettle();

        // Select d1
        await tester.tap(find.text('Delete Wide'));
        await tester.pumpAndSettle();

        expect(find.byType(DanceDetailScreen), findsOneWidget);

        // Delete from detail pane
        await tester.tap(find.byKey(const ValueKey('delete-dance')));
        await tester.pumpAndSettle();

        // Detail clears back to empty-state placeholder
        expect(find.text('Select a dance'), findsOneWidget);
        expect(find.byType(DanceDetailScreen), findsNothing);

        // List refreshed — deleted dance gone, other dance remains
        expect(find.text('Delete Wide'), findsNothing);
        expect(find.text('Keep Wide'), findsOneWidget);

        // Confirm soft-delete in storage
        final deleted = await repos.dances.getById('d1', includeDeleted: true);
        expect(deleted?.deletedAt, isNotNull);
      },
    );

    testWidgets('undo after wide-mode delete restores dance to list', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Undo Wide'));

      await _pumpShell(tester, repos, size: const Size(1400, 3000));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo Wide'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-dance')));
      await tester.pumpAndSettle();

      // Dance is gone from list, placeholder shown
      expect(find.text('Undo Wide'), findsNothing);
      expect(find.text('Select a dance'), findsOneWidget);

      // Tap Undo — should restore and refresh the list
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Undo Wide'), findsOneWidget);

      // Storage confirms restore
      final dance = await repos.dances.getById('d1');
      expect(dance?.deletedAt, isNull);
    });

    testWidgets(
      'list pane remains visible and scrollable independently in split mode',
      (tester) async {
        final repos = openTestRepositories();
        // Create enough dances to require scrolling in the list pane
        for (var i = 1; i <= 5; i++) {
          await repos.dances.create(_dance(id: 'd$i', title: 'Dance $i'));
        }

        await _pumpShell(tester, repos, size: const Size(1400, 400));
        await tester.pumpAndSettle();

        // Both panes present — detail pane shows placeholder, list shows dances
        expect(find.byType(DanceListScreen), findsOneWidget);
        expect(find.text('Select a dance'), findsOneWidget);
      },
    );
  });
}
