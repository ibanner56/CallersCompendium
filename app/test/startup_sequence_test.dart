import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kAppThemeKey;

import 'support/test_repositories.dart';

/// A [WindowService] whose restore does nothing — the plugin glue is untestable
/// under `flutter test` (no real window), and these tests only care about the
/// bootstrap steps that follow the restore.
class _NoopWindowService extends WindowService {
  _NoopWindowService(super.settings);

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

/// A [WindowService] whose restore fails as if the database could not be opened.
/// Stage 1.6: such a failure must reach the AppBootstrap error/retry screen
/// instead of throwing out of `main` and leaving a blank window.
class _FailingWindowService extends WindowService {
  _FailingWindowService(super.settings);

  @override
  Future<void> initialize() async =>
      throw StateError('database could not be opened during window restore');

  @override
  void dispose() {}
}

/// A [CompendiumRepositories] whose derived-index rebuild throws on its first
/// invocation and succeeds thereafter. This is the same `runDerivedRebuild`
/// seam the core `migration_test` uses to prove `ensureMigrated` retries a
/// transient failure, here driven through the full [CompendiumApp] bootstrap so
/// a failing migration is exercised end-to-end (error screen → retry → recover).
class _FailOnceMigrationRepositories extends CompendiumRepositories {
  _FailOnceMigrationRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    if (rebuildAttempts == 1) {
      throw StateError('injected migration failure');
    }
    await super.runDerivedRebuild(onProgress: onProgress);
  }
}

/// An [AppData] that hands [CompendiumApp] the failing-once repositories over
/// the same database. The base [AppData] still builds a real facade into its
/// field, but this getter shadows it so the bootstrap's `ensureMigrated` call
/// routes through the flaky one — without touching any `lib/` production code.
class _FailOnceMigrationAppData extends AppData {
  _FailOnceMigrationAppData(super.db);

  late final _FailOnceMigrationRepositories _repositories =
      _FailOnceMigrationRepositories(db, contraTaxonomy);

  @override
  _FailOnceMigrationRepositories get repositories => _repositories;
}

AppData _openAppData() {
  final appData = AppData(openWidgetTestDatabase());
  // The database is also closed by CompendiumApp.dispose(); sqlite3's close is
  // idempotent, so this teardown just guarantees cleanup even for the last test
  // in the file (whose widget tree is never unmounted).
  addTearDown(appData.close);
  return appData;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Booting the full app mounts [AppShell], which now keeps the User Guide
  // alive as a shell destination — so its doc FutureBuilder builds (offstage)
  // on startup. The root bundle caches parsed results as `SynchronousFuture`s
  // after the first load, which stalls that FutureBuilder (leaving its spinner
  // animating so `pumpAndSettle` never settles); clearing the cache before each
  // test makes the guide load fresh and settle.
  setUp(rootBundle.clear);

  testWidgets(
    'startup sweep purges programs soft-deleted past the retention window '
    '(Stage 1.2)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      // A FIXED sweep instant (injected via nowOverride) so this
      // retention-window assertion is fully deterministic and never depends on
      // real wall-clock timing (issue #459 de-flake). All timestamps below are
      // absolute and expressed relative to this same instant.
      final fixedNow = DateTime.utc(2026, 6, 1);
      // Soft-deleted 31 days before the sweep instant: past the default 30-day
      // retention → purged.
      await appData.repositories.programs.create(
        Program(
          id: 'old',
          title: 'Ancient Program',
          createdAt: fixedNow.subtract(const Duration(days: 60)),
          updatedAt: fixedNow.subtract(const Duration(days: 31)),
          deletedAt: fixedNow.subtract(const Duration(days: 31)),
        ),
      );
      // Soft-deleted the day before the sweep instant: still inside the window
      // → kept.
      await appData.repositories.programs.create(
        Program(
          id: 'recent',
          title: 'Recent Program',
          createdAt: fixedNow.subtract(const Duration(days: 2)),
          updatedAt: fixedNow.subtract(const Duration(days: 1)),
          deletedAt: fixedNow.subtract(const Duration(days: 1)),
        ),
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          nowOverride: () => fixedNow,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        await appData.repositories.programs.getById(
          'old',
          includeDeleted: true,
        ),
        isNull,
      );
      expect(
        await appData.repositories.programs.getById(
          'recent',
          includeDeleted: true,
        ),
        isNotNull,
      );
    },
  );

  testWidgets(
    'a DB-open failure during window restore reaches the error/retry screen '
    '(Stage 1.6)',
    (tester) async {
      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _FailingWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      // The window-restore failure is now inside the bootstrapped future, so it
      // renders the error/retry screen rather than blanking the window.
      expect(
        find.textContaining('Could not prepare the collection'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    },
  );

  testWidgets(
    'a failing migration reaches the error/retry screen, then retry recovers '
    'into the app (Stage 1 bootstrap)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = openWidgetTestDatabase();
      final appData = _FailOnceMigrationAppData(db);
      addTearDown(appData.close);

      // Durably mark that a derived-index rebuild is owed so ensureMigrated()
      // invokes runDerivedRebuild() (which throws on its first attempt).
      // Reading/writing here forces the fresh in-memory schema to be created.
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
        [derivedRebuildRequiredKey, 'true'],
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          // Keep the (advisory) integrity probe green so the only failure under
          // test is the migration itself.
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      // First bootstrap: the derived rebuild threw, so the migration failure
      // reaches the AppBootstrap error/retry screen and the app is gated.
      expect(
        find.textContaining('Could not prepare the collection'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(appData.repositories.rebuildAttempts, 1);

      // Retry: ensureMigrated cleared its memo and the durable marker survived,
      // so the rebuild runs again — now succeeding — and the app recovers.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not prepare the collection'),
        findsNothing,
      );
      expect(find.byType(AppShell), findsOneWidget);
      expect(appData.repositories.rebuildAttempts, 2);
    },
  );

  testWidgets('a failed integrity check warns the user but still opens the app '
      '(Stage 1.7)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = _openAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: _NoopWindowService(appData.repositories.settings),
        integrityCheck: () async => false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('integrity check failed'), findsOneWidget);
    // The warning is advisory — the collection still opens.
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets(
    'a THROWN integrity check is advisory: warns but still opens the app, '
    'not the error screen (Stage 1.7)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          // Throw *synchronously* (before any Future is returned). This escapes
          // a `.catchError` on the probe's result — the throw happens before
          // there is a Future to attach the handler to — so it is the clearest
          // regression against the old guard and is only handled by the
          // try/catch around the probe.
          integrityCheck: () => throw StateError('quick_check failed to run'),
        ),
      );
      await tester.pumpAndSettle();

      // A thrown probe is caught and treated as a failed (advisory) check: the
      // warning is shown and the collection still opens. It must NOT reach the
      // error/retry screen — that path is reserved for a genuine DB-open
      // failure during window restore (Stage 1.6).
      expect(find.textContaining('integrity check failed'), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
      expect(
        find.textContaining('Could not prepare the collection'),
        findsNothing,
      );
    },
  );

  testWidgets('a healthy database opens without a corruption warning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = _openAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: _NoopWindowService(appData.repositories.settings),
        // No injected check → uses the real CompendiumDatabase.quickCheck,
        // which reports ok on a fresh in-memory database.
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('integrity check failed'), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets(
    'a downgrade preflight failure shows the update-app message and gates the '
    'app, with no Retry (Phase 7 migration safety)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      const error = DatabaseDowngradeError(fileVersion: 99, appVersion: 9);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          // The preflight runs first; a downgrade rejection must reach the
          // AppBootstrap error screen with a tailored, non-retryable message.
          migrationPreflight: (_) async => throw error,
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This data was created by a newer version of Caller\u2019s Compendium '
          '\u2014 please update the app.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AppShell), findsNothing);
      // Retrying can't help — the fix is to update the app — so it's hidden.
      expect(find.text('Retry'), findsNothing);
      // This is not the generic failure path.
      expect(
        find.textContaining('Could not prepare the collection'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a successful below-floor reset reopens the app without relaunch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var preflightRuns = 0;
      var replacementAppDataCount = 0;
      const error = DatabaseBelowFloorError(
        fileVersion: 5,
        minSupportedVersion: 11,
        bridgeTag: 'v0.1.0-beta.6',
      );
      final initialAppData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: initialAppData,
          windowService: _NoopWindowService(
            initialAppData.repositories.settings,
          ),
          migrationPreflight: (_) async {
            preflightRuns++;
            if (preflightRuns == 1) throw error;
          },
          integrityCheck: () async => true,
          databaseFileResolver: () async => File('unused.sqlite'),
          databaseResetter: (_) async => const ResetComplete(),
          appDataFactory: () {
            replacementAppDataCount++;
            return _openAppData();
          },
          windowServiceFactory: (settings) => _NoopWindowService(settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This data is from a version too old to open'),
        findsOneWidget,
      );
      expect(find.byType(AppShell), findsNothing);

      await tester.tap(find.text('Reset Only'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset Only'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(
        find.text('This data is from a version too old to open'),
        findsNothing,
      );
      expect(preflightRuns, 2);
      expect(replacementAppDataCount, 1);
      // The replacement database has no persisted value, so the notifier must
      // use the declared off-by-default value rather than a stale value.
      expect(
        RequirePerformedForHistoryScope.of(
          tester.element(find.byType(AppShell)),
        ),
        isFalse,
      );
    },
  );

  testWidgets('a failed below-floor reset restores the recovery screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const error = DatabaseBelowFloorError(
      fileVersion: 5,
      minSupportedVersion: 11,
      bridgeTag: 'v0.1.0-beta.6',
    );
    var replacementAppDataCount = 0;
    final initialAppData = _openAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: initialAppData,
        windowService: _NoopWindowService(initialAppData.repositories.settings),
        migrationPreflight: (_) async {
          // Keep the failure asynchronous so FutureBuilder can subscribe to
          // the replacement bootstrap future before it completes.
          await Future<void>.delayed(Duration.zero);
          throw error;
        },
        integrityCheck: () async => true,
        databaseFileResolver: () async => File('unused.sqlite'),
        databaseResetter: (_) async =>
            const ResetFailed('injected reset failure'),
        appDataFactory: () {
          replacementAppDataCount++;
          return _openAppData();
        },
        windowServiceFactory: (settings) => _NoopWindowService(settings),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This data is from a version too old to open'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reset Only'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset Only'));
    await tester.pumpAndSettle();

    expect(find.text('Reset failed'), findsOneWidget);
    expect(replacementAppDataCount, 1);
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsNothing);
    expect(
      find.text('This data is from a version too old to open'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a failed pre-migration snapshot prompts for consent; Proceed runs the '
    'migration and opens the app (issue #442)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final failure = SnapshotFailure(
        fromVersion: 1,
        toVersion: 2,
        cause: SnapshotFailureCause.diskFull,
        error: const FileSystemException('no space left on device'),
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          // Stand in for a real snapshot failure: drive the injected consent
          // seam exactly as runMigrationPreflight would, so the app's real
          // dialog + gating is exercised end-to-end.
          migrationPreflight: (onSnapshotFailure) async {
            final proceed = await onSnapshotFailure(failure);
            if (!proceed) throw MigrationSnapshotAborted(failure);
          },
          integrityCheck: () async => true,
        ),
      );
      // Can't pumpAndSettle while the dialog is up: the bootstrap loading
      // spinner behind it animates forever. Pump explicit frames to let the
      // guard reach endOfFrame and open the dialog.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Couldn\u2019t back up your data'), findsOneWidget);
      expect(find.textContaining('low on storage'), findsOneWidget);
      expect(find.text('Quit'), findsOneWidget);
      expect(find.text('Proceed without a backup'), findsOneWidget);

      await tester.tap(find.text('Proceed without a backup'));
      await tester.pumpAndSettle();

      // Consent given → migration ran and the app opened normally.
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Couldn\u2019t back up your data'), findsNothing);
    },
  );

  testWidgets(
    'a failed pre-migration snapshot with Quit aborts to a non-retryable '
    'screen, before any schema change (issue #442)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final failure = SnapshotFailure(
        fromVersion: 1,
        toVersion: 2,
        cause: SnapshotFailureCause.unwritableBackupsDir,
        error: const FileSystemException('permission denied'),
      );
      var migrated = false;

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          migrationPreflight: (onSnapshotFailure) async {
            final proceed = await onSnapshotFailure(failure);
            if (!proceed) throw MigrationSnapshotAborted(failure);
            migrated = true;
          },
          integrityCheck: () async => true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Quit'), findsOneWidget);
      await tester.tap(find.text('Quit'));
      await tester.pumpAndSettle();

      // Declining aborts startup before any schema change: the terminal
      // message shows, the app never opens, and Retry is hidden (retrying
      // can't create the backup — the fix is to free space / fix permissions).
      expect(migrated, isFalse);
      expect(find.textContaining('create an automatic backup'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.text('Retry'), findsNothing);
      // The terminal icon reflects the actual cause (unwritable backups dir),
      // not the always-on disc_full glyph the review flagged (issue #442).
      expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.disc_full), findsNothing);
    },
  );

  testWidgets(
    'a wrong-typed theme_mode preference does not brick startup (issue #609)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      // Simulate a restored/corrupt backup that persisted a non-string under
      // the theme key. The old startup read cast this with `as String?`, which
      // threw here and — because the value stays on disk — re-threw on every
      // subsequent launch, bricking the app. Startup must now tolerate it and
      // fall back to the default theme.
      await appData.repositories.settings.set(kAppThemeKey, 123);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      // The app opens normally instead of throwing out of `_loadPreferences`.
      expect(find.byType(AppShell), findsOneWidget);
      expect(
        find.textContaining('Could not prepare the collection'),
        findsNothing,
      );
    },
  );
}
