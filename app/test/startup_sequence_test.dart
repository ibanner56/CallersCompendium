import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/application_shutdown_controller.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/editor_draft_shutdown_scope.dart';
import 'package:compendium_app/src/data/sync_writer_lifecycle_scope.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/screens/app_shell.dart';

import 'support/test_repositories.dart';
import 'support/noop_sync_transport.dart';
import 'support/sync_test_network.dart';

class _TrackingSyncCoordinator extends SyncCoordinator {
  _TrackingSyncCoordinator(
    CompendiumRepositories repositories, {
    required this.onDispose,
  }) : super(
         syncId: 'configured',
         deviceId: 'device',
         store: CompendiumSyncCoordinatorStore(repositories),
         transport: NoopSyncCoordinatorTransport(),
         passOperation: ({initialStore}) async =>
             const SyncPassResult(SyncPassStatus.completed),
       );

  final void Function(SyncCoordinator) onDispose;

  @override
  Future<void> dispose() {
    onDispose(this);
    return super.dispose();
  }
}

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

class _RecordingCrashLogSink implements CrashLogSink {
  final List<String> sources = [];

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    sources.add(source);
  }
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

class _RecordingAppData extends AppData {
  _RecordingAppData(super.db, this.closeEvents, this.closeLabel);

  final List<String> closeEvents;
  final String closeLabel;

  @override
  Future<void> close() async {
    closeEvents.add(closeLabel);
    await super.close();
  }
}

AppData _openAppData() {
  final appData = AppData(openWidgetTestDatabase(closeOnTearDown: false));
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

      final db = openWidgetTestDatabase(closeOnTearDown: false);
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
    'a shareable-settings write schedules a pass; the controller\'s own '
    'bookkeeping write does not (routed through the real change stream)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      var passes = 0;
      final passStarted = <Completer<void>>[];

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async => SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          passes++;
          passStarted.removeAt(0).complete();
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );

      await appData.repositories.settings.set(kSyncEnabledKey, true);
      passStarted.add(Completer<void>());
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: const UnmeteredSyncNetwork(),
          syncDebounce: const Duration(milliseconds: 20),
        ),
      );
      await tester.pumpAndSettle();
      expect(passes, 1, reason: 'the app-start pass');

      // A shareable preference write is a real sync record (its own emitted
      // `settings` write) and must schedule the debounced pass.
      passStarted.add(Completer<void>());
      await appData.repositories.settings.set(kAppThemeKey, 'dark');
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(passes, 2);

      // A sync-internal bookkeeping write to a sync-local table (no other
      // table touched) must not schedule another pass.
      await appData.repositories.syncLocal.markPublished(
        kind: SyncRecordKind.dance,
        recordId: 'irrelevant',
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(passes, 2, reason: 'bookkeeping alone must not trigger a pass');
    },
  );

  testWidgets(
    'overlapping sync reconfigurations run one at a time and the last wins',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final gates = <Completer<void>>[];
      var factoryCalls = 0;
      var running = 0;
      var maxRunning = 0;
      final created = <SyncCoordinator>[];
      final disposed = <SyncCoordinator>[];

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async {
        factoryCalls++;
        final isStartup = factoryCalls == 1;
        running++;
        if (running > maxRunning) maxRunning = running;
        if (!isStartup) {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
        }
        running--;
        final coordinator = _TrackingSyncCoordinator(
          repositories,
          onDispose: disposed.add,
        );
        created.add(coordinator);
        return coordinator;
      }

      await appData.repositories.settings.set(kSyncEnabledKey, true);
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: const UnmeteredSyncNetwork(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(created, hasLength(1), reason: 'startup created one coordinator');

      // Disable then re-enable before either reconfiguration's factory call
      // has resolved.
      final controller = SyncScope.of(tester.element(find.byType(AppShell)));
      final off = controller.setEnabled(false);
      await tester.pump();
      final on = controller.setEnabled(true);
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        gates,
        hasLength(1),
        reason: 'the second reconfiguration waits for the first to finish',
      );

      // Release the disable's factory call; only then may the enable's begin.
      gates[0].complete();
      await off;
      while (gates.length < 2) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      gates[1].complete();
      await on;
      await tester.pumpAndSettle();

      expect(maxRunning, 1, reason: 'reconfigurations never overlap');
      expect(created, hasLength(3));
      expect(
        disposed.toSet(),
        created.take(2).toSet(),
        reason: 'every superseded coordinator is disposed, the last is kept',
      );
      addTearDown(() => created.last.dispose());
    },
  );

  testWidgets(
    'a failing sync configuration does not block startup and is logged',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sink = _RecordingCrashLogSink();
      installCaughtErrorLog(sink);
      addTearDown(resetCaughtErrorLogForTesting);
      final appData = _openAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          // A malformed persisted sync setting can throw synchronously before
          // the factory returns a Future. Device Sync is optional, so this
          // must not abort the rest of startup.
          syncCoordinatorFactory: (_) {
            throw const FormatException('stored sync ID must be a string');
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(sink.sources, contains('main.sync-configure'));
    },
  );

  testWidgets(
    'backup restore serializes and recreates the production sync coordinator',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final source = openTestRepositories();
      await source.dances.create(
        Dance(
          id: 'restored',
          title: 'Restored Dance',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final backupJson = await BackupService(source).exportToJson();

      final firstPassGate = Completer<void>();
      final firstPassStarted = Completer<void>();
      final replacementPassStarted = Completer<void>();
      var factoryCalls = 0;
      SyncCoordinator? replacement;

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async {
        factoryCalls++;
        final isFirst = factoryCalls == 1;
        final started = isFirst ? firstPassStarted : replacementPassStarted;
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: isFirst ? 'device-a' : 'device-b',
          store: CompendiumSyncCoordinatorStore(repositories),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({SyncStoreResult? initialStore}) async {
            if (!started.isCompleted) started.complete();
            if (isFirst) await firstPassGate.future;
            return const SyncPassResult(SyncPassStatus.completed);
          },
        );
        if (!isFirst) replacement = coordinator;
        return coordinator;
      }

      addTearDown(() async {
        await replacement?.dispose();
      });

      // A production coordinator exists only once the user has turned sync on
      // (spec §6.1); the app-start trigger honors that consent.
      await appData.repositories.settings.set(kSyncEnabledKey, true);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: const UnmeteredSyncNetwork(),
        ),
      );
      await tester.pumpAndSettle();
      await firstPassStarted.future;
      expect(find.byType(AppShell), findsOneWidget);

      final scope = tester.widget<SyncWriterLifecycleScope>(
        find.byType(SyncWriterLifecycleScope),
      );
      final lifecycle = <String>[];
      var restoreStarted = false;
      final runWrite = scope.runWrite;
      expect(runWrite, isNotNull);

      final restoreFuture = runWrite!(() async {
        restoreStarted = true;
        final outcome = await BackupService(
          appData.repositories,
        ).restoreFromJson(backupJson);
        lifecycle.add('restored');
        return outcome;
      });
      expect(
        restoreStarted,
        isFalse,
        reason: 'the writer must await the active startup pass',
      );

      firstPassGate.complete();
      final outcome = await restoreFuture;
      expect(outcome.applied, isTrue);
      lifecycle.add('replacement-factory');
      expect(factoryCalls, 2);

      await replacementPassStarted.future;
      lifecycle.add('replacement-onAppStart');
      expect(lifecycle, [
        'restored',
        'replacement-factory',
        'replacement-onAppStart',
      ]);
    },
  );

  testWidgets(
    'shutdown shares coordinator disposal with an in-progress restore hook',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final firstPassGate = Completer<void>();
      final firstPassStarted = Completer<void>();
      final shutdownController = ApplicationShutdownController(() async {});
      var factoryCalls = 0;

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async {
        factoryCalls++;
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: CompendiumSyncCoordinatorStore(repositories),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({SyncStoreResult? initialStore}) async {
            if (!firstPassStarted.isCompleted) firstPassStarted.complete();
            await firstPassGate.future;
            return const SyncPassResult(SyncPassStatus.completed);
          },
        );
        return coordinator;
      }

      await appData.repositories.settings.set(kSyncEnabledKey, true);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          applicationShutdownController: shutdownController,
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: const UnmeteredSyncNetwork(),
        ),
      );
      await tester.pumpAndSettle();
      await firstPassStarted.future;

      final scope = tester.widget<SyncWriterLifecycleScope>(
        find.byType(SyncWriterLifecycleScope),
      );
      final runWrite = scope.runWrite;
      expect(runWrite, isNotNull);
      var writerStarted = false;
      final writerFuture = runWrite!(() async {
        writerStarted = true;
      });
      var shutdownCompleted = false;
      final shutdownFuture = shutdownController.close().then((_) {
        shutdownCompleted = true;
      });

      await tester.pump();
      expect(
        shutdownCompleted,
        isFalse,
        reason: 'shutdown must await the writer disposal',
      );

      firstPassGate.complete();
      await expectLater(writerFuture, throwsA(isA<StateError>()));
      await shutdownFuture;
      expect(shutdownCompleted, isTrue);
      expect(writerStarted, isFalse);
      expect(factoryCalls, 1);
    },
  );

  testWidgets(
    'a writer boundary started while a reconfigure is still awaiting its '
    'factory prevents that reconfigure from starting a pass until the '
    'writer completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final events = <String>[];
      var factoryCalls = 0;
      Completer<void>? racingFactoryGate;

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async {
        factoryCalls++;
        final callNumber = factoryCalls;
        if (callNumber == 1) {
          // Startup: sync is off, matching spec §6.1 — no coordinator.
          return null;
        }
        if (callNumber == 2) {
          // The reconfigure a writer boundary starts during (its factory
          // call is held open exactly like a settings toggle whose repository
          // reads/HTTP client setup have not resolved yet).
          await racingFactoryGate!.future;
        }
        return SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-$callNumber',
          store: CompendiumSyncCoordinatorStore(repositories),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({SyncStoreResult? initialStore}) async {
            events.add('pass-ran-$callNumber');
            return const SyncPassResult(SyncPassStatus.completed);
          },
        );
      }

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: const UnmeteredSyncNetwork(),
        ),
      );
      await tester.pumpAndSettle();
      expect(factoryCalls, 1, reason: 'startup: sync is off');

      final controller = SyncScope.of(tester.element(find.byType(AppShell)));
      racingFactoryGate = Completer<void>();
      // Turning sync on starts the second (racing) reconfigure; its factory
      // call is held open by the gate above.
      final enableFuture = controller.setEnabled(true);
      await tester.pump();
      expect(factoryCalls, 2);

      final scope = tester.widget<SyncWriterLifecycleScope>(
        find.byType(SyncWriterLifecycleScope),
      );
      final runWrite = scope.runWrite;
      expect(runWrite, isNotNull);

      final writerOperationGate = Completer<void>();
      final writerFuture = runWrite!(() async {
        events.add('writer-started');
        await writerOperationGate.future;
        events.add('writer-finished');
      });
      await tester.pump();
      expect(
        events,
        contains('writer-started'),
        reason:
            'nothing is installed yet to dispose, so the writer proceeds '
            'straight into its operation',
      );

      // Release the racing reconfigure's factory while the writer's
      // operation is still in progress. Spec §6.11: this must not install a
      // coordinator that a concurrent trigger could reach, and must not
      // start a pass, while the writer owns exclusivity.
      racingFactoryGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        events.where((event) => event.startsWith('pass-ran')),
        isEmpty,
        reason:
            'the racing reconfigure must not start a pass while the writer '
            'is still running',
      );
      expect(factoryCalls, 2, reason: 'no further reconfigure has run yet');

      writerOperationGate.complete();
      await writerFuture;
      await enableFuture;
      await tester.pumpAndSettle();

      expect(
        factoryCalls,
        3,
        reason:
            "the writer's own post-operation reconfigure builds a fresh "
            'coordinator once it is safe',
      );
      expect(
        events.indexOf('writer-finished'),
        lessThan(events.indexWhere((event) => event.startsWith('pass-ran'))),
        reason: 'no pass ran before the writer completed',
      );
    },
  );

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
      var replacementWindowServiceCount = 0;
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
          initialRequirePerformedForHistory: true,
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
          windowServiceFactory: (settings) {
            replacementWindowServiceCount++;
            return _NoopWindowService(settings);
          },
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
      expect(replacementWindowServiceCount, 1);
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

  testWidgets(
    'restoring a backup without a preference resets its live notifier',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = openTestRepositories();
      await source.dances.create(
        Dance(
          id: 'restored',
          title: 'Restored Dance',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final backupJson = await BackupService(source).exportToJson();

      final appData = _openAppData();
      await appData.repositories.settings.set(
        kRequirePerformedForHistoryKey,
        true,
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      var context = tester.element(find.byType(AppShell));
      expect(RequirePerformedForHistoryScope.of(context), isTrue);

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        backupJson,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pumpAndSettle();

      expect(
        await appData.repositories.settings.get(kRequirePerformedForHistoryKey),
        isNull,
      );
      context = tester.element(find.byType(AppShell));
      expect(RequirePerformedForHistoryScope.of(context), isFalse);
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
    final closeEvents = <String>[];
    final initialAppData = _RecordingAppData(
      openWidgetTestDatabase(closeOnTearDown: false),
      closeEvents,
      'initial-db-close',
    );
    addTearDown(initialAppData.close);
    final draftShutdownController = EditorDraftShutdownController();
    draftShutdownController.register(() {
      closeEvents.add('draft-flush');
      return () async {};
    });
    final applicationShutdownController = ApplicationShutdownController(
      () async => closeEvents.add('initial-shutdown'),
    );

    await tester.pumpWidget(
      CompendiumApp(
        appData: initialAppData,
        windowService: _NoopWindowService(initialAppData.repositories.settings),
        applicationShutdownController: applicationShutdownController,
        editorDraftShutdownController: draftShutdownController,
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
          final replacementAppData = _RecordingAppData(
            openWidgetTestDatabase(closeOnTearDown: false),
            closeEvents,
            'replacement-db-close',
          );
          addTearDown(replacementAppData.close);
          return replacementAppData;
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
    await applicationShutdownController.close();
    expect(
      closeEvents,
      containsAllInOrder([
        'initial-db-close',
        'draft-flush',
        'replacement-db-close',
      ]),
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
