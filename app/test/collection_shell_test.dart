import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/widgets/brand_mark.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

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

/// Picks the generic Caller's Compendium JSON source in the embedded import
/// pane. Needed because #823 changed the default selection to The Caller's Box:
/// order and default are now separate concerns, so a JSON archive must be routed
/// to its own adapter explicitly.
Future<void> _selectGenericJsonSource(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('import-source-select')));
  await tester.pumpAndSettle();
  await tester.tap(find.text("a Caller's Compendium JSON file").last);
  await tester.pumpAndSettle();
}

/// Pump [CollectionShell] at a given surface [size].
/// Wide surface (≥ 900 wide) triggers the split-pane layout.
/// Use at least 1400 px wide for wide tests to give the 400 px list pane
/// enough room for its AppBar actions without overflow.
///
/// [importPicker] / [urlFetcher] / [importSources] are forwarded to the shell
/// so import tests can drive the flow without real file-picking or network.
Future<void> _pumpShell(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Size size,
  ImportPicker? importPicker,
  UrlFetcher? urlFetcher,
  List<ImportSource>? importSources,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: notifier,
          // Mirror main.dart: import commit/undo bumps this so the live list
          // reloads. Optional in focused tests, required for the import flow.
          child: CollectionRefreshScope(revision: refresh, child: child!),
        ),
      ),
      home: CollectionShell(
        importPicker: importPicker,
        urlFetcher: urlFetcher,
        importSources: importSources,
      ),
    ),
  );
}

/// Encodes a one-or-more-dance archive as the generic-JSON payload the
/// [GenericJsonAdapter] consumes (used by injected import pickers).
String _archivePayload(List<Dance> dances) => encodeArchive(
  CompendiumArchive(exportedAt: DateTime.utc(2026, 7, 15), dances: dances),
);

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
      // The empty detail pane leads with the brand mark (§4.4). The list pane
      // holds a dance, so this is the only mark on screen.
      expect(find.byType(BrandMark), findsOneWidget);
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

    testWidgets('saving a new dance selects it in the detail pane', (
      tester,
    ) async {
      final repos = openTestRepositories();

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      // Empty-state placeholder is visible; no detail screen yet.
      expect(find.text('Select a dance'), findsOneWidget);
      expect(find.byType(DanceDetailScreen), findsNothing);

      // Tap the new-dance FAB — DanceEditorScreen is pushed.
      await tester.tap(find.byKey(const ValueKey('new-dance')));
      await tester.pumpAndSettle();
      expect(find.byType(DanceEditorScreen), findsOneWidget);

      // Enter a title (minimum required to pass form validation) and save.
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Newly Created Dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      // Editor popped; detail pane now shows the new dance.
      expect(find.byType(DanceEditorScreen), findsNothing);
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      // Placeholder is gone — selection happened.
      expect(find.text('Select a dance'), findsNothing);
    });

    testWidgets(
      'cancelling the new-dance editor leaves the previous selection unchanged',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'd1', title: 'Existing Dance'));

        await _pumpShell(tester, repos, size: const Size(1400, 900));
        await tester.pumpAndSettle();

        // Select an existing dance first.
        await tester.tap(find.text('Existing Dance'));
        await tester.pumpAndSettle();
        expect(find.byType(DanceDetailScreen), findsOneWidget);

        // Open the new-dance editor.
        await tester.tap(find.byKey(const ValueKey('new-dance')));
        await tester.pumpAndSettle();
        expect(find.byType(DanceEditorScreen), findsOneWidget);

        // Cancel via real back navigation — goes through PopScope, matching
        // what a user can actually do.
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Editor is gone; original selection is intact.
        expect(find.byType(DanceEditorScreen), findsNothing);
        expect(find.byType(DanceDetailScreen), findsOneWidget);
      },
    );
  });

  // ── import button + flow ─────────────────────────────────────────────────────

  group('import', () {
    testWidgets('button renders in the app bar, left of batch-select', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'A Dance'));

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      final importFinder = find.byKey(const ValueKey('import-dances'));
      final batchFinder = find.byKey(const ValueKey('batch-select'));
      expect(importFinder, findsOneWidget);
      expect(batchFinder, findsOneWidget);
      // Import sits to the LEFT of Select dances in the same app bar row.
      expect(
        tester.getTopLeft(importFinder).dx,
        lessThan(tester.getTopLeft(batchFinder).dx),
      );
    });

    testWidgets('button is available with an empty collection', (tester) async {
      final repos = openTestRepositories();

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('import-dances')), findsOneWidget);
    });

    testWidgets('wide: tapping Import shows ImportReviewScreen in the detail '
        'pane (not a pushed route)', (tester) async {
      final repos = openTestRepositories();

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();

      // Import view is embedded: it appears WITH the list pane still visible
      // (a pushed route would cover the list) and shows the embedded close
      // affordance.
      expect(find.byType(ImportReviewScreen), findsOneWidget);
      expect(find.byType(DanceListScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('import-close')), findsOneWidget);
      expect(find.text('Select a dance'), findsNothing);
    });

    testWidgets('wide: selecting a dance exits import mode and shows detail', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Escape Dance'));

      await _pumpShell(tester, repos, size: const Size(1400, 3000));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewScreen), findsOneWidget);

      await tester.tap(find.text('Escape Dance'));
      await tester.pumpAndSettle();

      // Import is gone; the selected dance's detail is shown instead.
      expect(find.byType(ImportReviewScreen), findsNothing);
      expect(find.byType(DanceDetailScreen), findsOneWidget);
    });

    testWidgets('wide: the close button returns to the empty detail state', (
      tester,
    ) async {
      final repos = openTestRepositories();

      await _pumpShell(tester, repos, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-close')));
      await tester.pumpAndSettle();

      expect(find.byType(ImportReviewScreen), findsNothing);
      expect(find.text('Select a dance'), findsOneWidget);
    });

    testWidgets('narrow: tapping Import pushes the ImportReviewScreen route', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Narrow Dance'));

      await _pumpShell(tester, repos, size: const Size(600, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();

      // A full-screen route is pushed: the import screen is shown, the list is
      // covered (offstage), and there is no embedded close button (default back
      // arrow instead).
      expect(find.byType(ImportReviewScreen), findsOneWidget);
      expect(find.byType(DanceListScreen), findsNothing);
      expect(find.byKey(const ValueKey('import-close')), findsNothing);
    });

    testWidgets('wide: an end-to-end import commits and the dance appears in '
        'the list', (tester) async {
      final repos = openTestRepositories();
      // Injected picker returns a one-dance archive; no real file dialog.
      await _pumpShell(
        tester,
        repos,
        size: const Size(1400, 1600),
        importPicker: () async =>
            _archivePayload([_dance(id: 'imp1', title: 'Imported Reel')]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();

      // The screen now opens on The Caller's Box (#823 changed the default from
      // the generic-JSON source), so a Compendium archive has to be routed to
      // its own source explicitly.
      await _selectGenericJsonSource(tester);

      await tester.tap(find.byKey(const ValueKey('import-choose-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // Dismiss the result dialog (Done) — embedded, this closes import mode.
      await tester.tap(find.byKey(const ValueKey('import-done-button')));
      await tester.pumpAndSettle();

      // Import view closed and the committed dance now shows in the live list
      // (CollectionRefreshScope drove the reload).
      expect(find.byType(ImportReviewScreen), findsNothing);
      expect(find.text('Imported Reel'), findsOneWidget);

      final all = await repos.dances.listAll();
      expect(all.map((d) => d.title), contains('Imported Reel'));
    });

    testWidgets('wide: a multi-dance import shows the report and does NOT '
        'auto-open a dance', (tester) async {
      final repos = openTestRepositories();
      // A two-dance archive: the batch/URL import path must keep its result
      // summary + Done and never auto-open one of the dances (auto-open is
      // reserved for the single-dance online-search import).
      await _pumpShell(
        tester,
        repos,
        size: const Size(1400, 1600),
        importPicker: () async => _archivePayload([
          _dance(id: 'imp1', title: 'Imported Reel'),
          _dance(id: 'imp2', title: 'Imported Jig'),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-dances')));
      await tester.pumpAndSettle();
      await _selectGenericJsonSource(tester);
      await tester.tap(find.byKey(const ValueKey('import-choose-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // The result summary is shown with its Done affordance (not an auto-open).
      expect(find.byKey(const ValueKey('import-done-button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-done-button')));
      await tester.pumpAndSettle();

      // Import view closed and NO dance was auto-opened in the detail pane;
      // both imported dances land in the collection and show in the live list.
      expect(find.byType(ImportReviewScreen), findsNothing);
      expect(find.byType(DanceDetailScreen), findsNothing);
      final all = await repos.dances.listAll();
      expect(
        all.map((d) => d.title),
        containsAll(<String>['Imported Reel', 'Imported Jig']),
      );
    });
  });
}
