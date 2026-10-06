import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show LazyDatabase, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/application_shutdown_controller.dart';
import 'package:compendium_app/src/data/backup_document.dart'
    show
        defaultBackupCodecRunner,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/data/collection_tile_fields_scope.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/first_day_of_week_scope.dart';
import 'package:compendium_app/src/data/program_matrix_column_config_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/venue_call_count_scope.dart';
import 'package:compendium_app/src/data/dance_share_fields_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart'
    show kCustomDialectsKey;
import 'package:compendium_app/src/data/editor_draft_shutdown_scope.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart'
    show kSoftDeleteRetentionKey;
import 'package:compendium_app/src/data/sync_writer_lifecycle_scope.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'package:compendium_app/src/data/migration_error_labels.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/data/canonical_discouraged_terms_scope.dart';
import 'package:compendium_app/src/data/colour_dance_theme_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/decimal_turns_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart'
    show kCanonicalDiscouragedTermsKey;
import 'package:compendium_app/src/data/matrix_collision_mode_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/data/track_history_for_all_callers_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/screens/app_shell.dart';

import 'support/full_app_harness.dart';
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
final class _SwitchableNetwork implements SyncNetworkClassifier {
  _SwitchableNetwork(this.kind);
  SyncNetworkKind kind;
  @override
  Future<SyncNetworkKind> current() async => kind;
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

/// A [SettingsRepository] whose `get`/`contains` throw for chosen keys, as if
/// that one row were corrupt or the database were locked during the read.
class _FlakySettings extends SettingsRepository {
  _FlakySettings(super.db, this.failingKeys);

  final Set<String> failingKeys;

  /// While non-null, `get(gateKey)` waits on it: lets a test hold one startup
  /// read open and look at the live notifiers while it is in flight.
  Completer<void>? gate;
  String? gateKey;

  @override
  Future<Object?> get(String key) async {
    if (gate != null && key == gateKey) await gate!.future;
    if (failingKeys.contains(key)) {
      throw StateError('injected read failure: $key');
    }
    return super.get(key);
  }

  @override
  Future<bool> contains(String key) {
    if (failingKeys.contains(key)) {
      return Future<bool>.error(StateError('injected read failure: $key'));
    }
    return super.contains(key);
  }
}

/// An [AppData] whose settings reads fail for [failingKeys]. Same shape as
/// [_FailOnceMigrationAppData]: the getter shadows the base facade.
class _FlakySettingsAppData extends AppData {
  _FlakySettingsAppData(super.db, Set<String> failingKeys)
    : _repositories = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: _FlakySettings(db, failingKeys),
      );

  final CompendiumRepositories _repositories;

  _FlakySettings get flakySettings => _repositories.settings as _FlakySettings;

  @override
  CompendiumRepositories get repositories => _repositories;
}

_FlakySettingsAppData _openFlakySettingsAppData(Set<String> failingKeys) {
  final appData = _FlakySettingsAppData(
    openWidgetTestDatabase(closeOnTearDown: false),
    failingKeys,
  );
  addTearDown(appData.close);
  return appData;
}

/// Drives Settings › General › Restore with [backupJson], which ends in
/// `reloadFromSettings`.
Future<void> _restoreFromPaste(
  WidgetTester tester,
  String backupJson, {
  Future<void> Function()? whileReloading,
}) async {
  // By icon, not label: the language under test may not be English.
  await tester.tap(find.byIcon(Icons.settings_outlined).last);
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
  if (whileReloading != null) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await whileReloading();
  }
  await tester.pumpAndSettle();
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
  // testWidgets' fake async never delivers a worker isolate's reply, so the
  // service's codec runs inline here (production runs it on an isolate).
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  testWidgets(
    'startup sweep purges programs soft-deleted past the retention window '
    '(Stage 1.2)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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
    'an unreadable soft-delete retention setting starts the app and skips '
    'the sweep rather than assuming the 30-day default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sink = _RecordingCrashLogSink();
      installCaughtErrorLog(sink);
      addTearDown(resetCaughtErrorLogForTesting);

      final appData = _openFlakySettingsAppData({kSoftDeleteRetentionKey});
      final fixedNow = DateTime.utc(2026, 6, 1);
      // Past the 30-day default: a default-on-failure would purge it, which is
      // wrong for a user whose stored choice was "never auto-purge".
      await appData.repositories.programs.create(
        Program(
          id: 'old',
          title: 'Ancient Program',
          createdAt: fixedNow.subtract(const Duration(days: 60)),
          updatedAt: fixedNow.subtract(const Duration(days: 31)),
          deletedAt: fixedNow.subtract(const Duration(days: 31)),
        ),
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          nowOverride: () => fixedNow,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(
        await appData.repositories.programs.getById(
          'old',
          includeDeleted: true,
        ),
        isNotNull,
      );
      expect(sink.sources, contains('startup.soft_delete_retention_read'));
    },
  );

  testWidgets(
    'a DB-open failure during window restore reaches the error/retry screen '
    '(Stage 1.6)',
    (tester) async {
      final appData = openTestAppData();

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

  testWidgets('a failed database open is logged, offers Copy details, and Retry '
      'reopens the database', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sink = _RecordingCrashLogSink();
    installCaughtErrorLog(sink);
    addTearDown(resetCaughtErrorLogForTesting);

    // drift caches a failed open inside LazyDatabase, so every later query on
    // this instance rethrows the same error — exactly the production shape.
    final failingAppData = AppData(
      CompendiumDatabase(
        LazyDatabase(() async => throw StateError('open failed')),
      ),
    );
    final healthyAppData = openTestAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: failingAppData,
        appDataFactory: () => healthyAppData,
        windowService: NoopWindowService(failingAppData.repositories.settings),
        windowServiceFactory: (settings) => NoopWindowService(settings),
        integrityCheck: () async => true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not prepare the collection'),
      findsOneWidget,
    );
    expect(sink.sources, ['main.bootstrap']);
    expect(
      find.byKey(const ValueKey('bootstrap-copy-details')),
      findsOneWidget,
    );
    // The type is shown; the message is withheld (#1469, CWE-209).
    expect(find.textContaining('StateError'), findsOneWidget);
    expect(find.textContaining('open failed'), findsNothing);

    // Copy details puts the type and stack on the clipboard, never the message
    // (#1469, CWE-209).
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('bootstrap-copy-details')));
    await tester.pumpAndSettle();
    expect(copied, startsWith('StateError\n\n'));
    expect(copied, isNot(contains('open failed')));
    expect(find.text('Copied'), findsOneWidget);

    // Retry must reopen the database: the failed LazyDatabase never recovers.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(sink.sources, ['main.bootstrap']);
  });

  testWidgets(
    'a failing migration reaches the error/retry screen, then retry recovers '
    'into the app (Stage 1 bootstrap)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = openWidgetTestDatabase(closeOnTearDown: false);
      final appData = _FailOnceMigrationAppData(db);
      addTearDown(appData.close);
      final retryAppData = openTestAppData();

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
          windowService: NoopWindowService(appData.repositories.settings),
          // Retry now reopens the database (see the failed-open test above), so
          // it asks for a replacement AppData rather than reusing the failed
          // one; hand it a fresh healthy in-memory one instead of the real
          // on-disk database.
          appDataFactory: () => retryAppData,
          windowServiceFactory: (settings) => NoopWindowService(settings),
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

      // Retry rebuilds the database-backed world from appDataFactory; the fresh
      // healthy AppData migrates cleanly and the app recovers.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not prepare the collection'),
        findsNothing,
      );
      expect(find.byType(AppShell), findsOneWidget);
      // The flaky instance is no longer in use after Retry, so its attempt
      // count stays at 1; the cross-instance `== 2` assertion this test used to
      // make (same AppData re-run) no longer describes Retry.
      expect(appData.repositories.rebuildAttempts, 1);
    },
  );

  testWidgets('a failed integrity check warns the user but still opens the app '
      '(Stage 1.7)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = openTestAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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

  testWidgets('the shell renders before a slow integrity check completes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = openTestAppData();
    final probe = Completer<bool>();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () => probe.future,
      ),
    );
    await tester.pumpAndSettle();

    expect(probe.isCompleted, isFalse);
    expect(find.byType(AppShell), findsOneWidget);

    probe.complete(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('integrity check failed'), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('a failed deferred integrity check still shows the advisory '
      'banner exactly once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = openTestAppData();
    final probe = Completer<bool>();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () => probe.future,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.textContaining('integrity check failed'), findsNothing);

    probe.complete(false);
    await tester.pumpAndSettle();

    expect(find.textContaining('integrity check failed'), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('a thrown deferred probe is advisory', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sink = _RecordingCrashLogSink();
    installCaughtErrorLog(sink);
    addTearDown(resetCaughtErrorLogForTesting);

    final appData = openTestAppData();
    final probe = Completer<bool>();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () => probe.future,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    probe.completeError(StateError('quick_check failed to run'));
    await tester.pumpAndSettle();

    expect(find.textContaining('integrity check failed'), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      find.textContaining('Could not prepare the collection'),
      findsNothing,
    );
    expect(sink.sources, ['integrity-probe']);
  });

  testWidgets('a healthy database opens without a corruption warning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = openTestAppData();

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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
    'returning to the foreground starts a pass, at most once per interval '
    '(spec §6.12)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
      var passes = 0;
      final network = _SwitchableNetwork(SyncNetworkKind.offline);

      Future<SyncCoordinator?> factory(
        CompendiumRepositories repositories,
      ) async => SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async {
          passes++;
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );

      await appData.repositories.settings.set(kSyncEnabledKey, true);
      await appData.repositories.settings.set(
        kSyncIdKey,
        'correct horse battery staple',
      );
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
          syncCoordinatorFactory: factory,
          syncNetworkClassifier: network,
        ),
      );
      await tester.pumpAndSettle();
      // Offline at start, so the app-start pass was suppressed and started
      // nothing the resume interval could count from.
      expect(passes, 0);

      network.kind = SyncNetworkKind.unmetered;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(passes, 1, reason: 'the resume pass');

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(passes, 1, reason: 'a second resume inside the interval');
    },
  );

  testWidgets(
    'overlapping sync reconfigurations run one at a time and the last wins',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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
      final appData = openTestAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
      const error = DatabaseDowngradeError(fileVersion: 99, appVersion: 9);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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
      final initialAppData = openTestAppData();

      await tester.pumpWidget(
        CompendiumApp(
          appData: initialAppData,
          windowService: NoopWindowService(
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
            return openTestAppData();
          },
          windowServiceFactory: (settings) {
            replacementWindowServiceCount++;
            return NoopWindowService(settings);
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

      final appData = openTestAppData();
      await appData.repositories.settings.set(
        kRequirePerformedForHistoryKey,
        true,
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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

  // Ratchet for the boolean-preference descriptor list in `main.dart`: every
  // preference on it must return to its default when a restored backup lacks
  // its key. A preference left off the list would keep its pre-restore value.
  group('restoring a backup without a boolean preference resets it', () {
    final cases =
        <({String key, bool Function(BuildContext) read, bool defaultValue})>[
          (
            key: kRequirePerformedForHistoryKey,
            read: RequirePerformedForHistoryScope.of,
            defaultValue: false,
          ),
          (
            key: kTrackHistoryForAllCallersKey,
            read: TrackHistoryForAllCallersScope.of,
            defaultValue: false,
          ),
          (
            key: kSortIgnoreArticlesKey,
            read: SortIgnoreArticlesScope.of,
            defaultValue: true,
          ),
          // Tri-state: the stored value is an explicit override; with no key
          // the scope follows the OS setting, which is off under test.
          (
            key: kReduceMotionKey,
            read: ReduceMotionScope.of,
            defaultValue: false,
          ),
          (
            key: kVerboseFigureRenderingKey,
            read: VerboseFigureRenderingScope.of,
            defaultValue: false,
          ),
          (
            key: kCanonicalDiscouragedTermsKey,
            read: CanonicalDiscouragedTermsScope.of,
            defaultValue: true,
          ),
          (
            key: kDecimalTurnsKey,
            read: DecimalTurnsScope.of,
            defaultValue: false,
          ),
          (
            key: kAggressiveBeatsUpdateKey,
            read: AggressiveBeatsUpdateScope.of,
            defaultValue: false,
          ),
          (
            key: kConfirmBeforeDeleteKey,
            read: ConfirmBeforeDeleteScope.of,
            defaultValue: false,
          ),
          (
            key: kVenueEntityModeKey,
            read: VenueEntityModeScope.of,
            defaultValue: false,
          ),
          (
            key: kAutoCommitProgramChangesKey,
            read: ProgramAutoCommitScope.of,
            defaultValue: false,
          ),
          (
            key: kColourDanceThemeKey,
            read: ColourDanceThemeScope.of,
            defaultValue: false,
          ),
          (
            key: kSetListColorCodingKey,
            read: SetListColorCodingScope.of,
            defaultValue: true,
          ),
          (
            key: kMatrixExactBeatCollisionKey,
            read: MatrixCollisionModeScope.of,
            defaultValue: true,
          ),
        ];

    for (final c in cases) {
      testWidgets('without ${c.key}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = openTestRepositories();
        final backupJson = await BackupService(source).exportToJson();

        final appData = openTestAppData();
        await appData.repositories.settings.set(c.key, !c.defaultValue);

        await tester.pumpWidget(
          CompendiumApp(
            appData: appData,
            windowService: NoopWindowService(appData.repositories.settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          c.read(tester.element(find.byType(AppShell))),
          !c.defaultValue,
          reason: 'the stored non-default value is applied at startup',
        );

        await _restoreFromPaste(tester, backupJson);

        expect(await appData.repositories.settings.get(c.key), isNull);
        expect(c.read(tester.element(find.byType(AppShell))), c.defaultValue);
      });
    }
  });

  // The non-boolean half of the descriptor-list ratchet: each of these live
  // preferences must also return to its default when a restored backup lacks
  // its key, and show a stored non-default value at startup.
  group('restoring a backup without a non-boolean preference resets it', () {
    final matrixStored = const MatrixColumnConfig(
      hidden: {'some-column'},
    ).toJson();
    final cases =
        <
          ({
            String key,
            Object? stored,
            Object? Function(BuildContext) read,
            Object? storedResult,
            Object? defaultValue,
          })
        >[
          (
            key: kAppThemeKey,
            stored: 'dark',
            read: AppThemeScope.of,
            storedResult: AppThemeSelection.dark,
            defaultValue: AppThemeSelection.system,
          ),
          (
            key: kVenueCallCountKey,
            stored: 7,
            read: VenueCallCountScope.of,
            storedResult: 7,
            defaultValue: kVenueCallCountDefault,
          ),
          (
            key: kDateFormatKey,
            stored: DateFormatPref.ymd.token,
            read: (c) => DateFormatScope.of(c).pref,
            storedResult: DateFormatPref.ymd,
            defaultValue: DateFormatPref.system,
          ),
          (
            key: kFirstDayOfWeekKey,
            stored: FirstDayOfWeekPref.monday.token,
            read: FirstDayOfWeekScope.of,
            storedResult: FirstDayOfWeekPref.monday,
            defaultValue: FirstDayOfWeekPref.system,
          ),
          (
            key: kLocaleKey,
            stored: 'de',
            read: LocaleScope.of,
            storedResult: const Locale('de'),
            defaultValue: null,
          ),
          (
            key: kCollectionTileVisibleFieldsKey,
            stored: [CollectionTileField.authors.toJson()],
            read: CollectionTileFieldsScope.of,
            storedResult: {CollectionTileField.authors},
            defaultValue: CollectionTileField.all,
          ),
          (
            key: kProgramDanceShareFieldsKey,
            stored: [DanceShareField.values.first.toJson()],
            read: DanceShareFieldsScope.of,
            storedResult: {DanceShareField.values.first},
            defaultValue: DanceShareField.allExceptTunes,
          ),
          (
            key: kCollectionHiddenFacetsKey,
            stored: ['form'],
            read: CollectionFacetsScope.of,
            storedResult: {'form'},
            defaultValue: <String>{},
          ),
          (
            key: kProgramMatrixColumnsKey,
            stored: matrixStored,
            read: (c) => ProgramMatrixColumnConfigScope.of(c).toJson(),
            storedResult: matrixStored,
            defaultValue: MatrixColumnConfig.empty.toJson(),
          ),
        ];

    for (final c in cases) {
      testWidgets('without ${c.key}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = openTestRepositories();
        final backupJson = await BackupService(source).exportToJson();

        final appData = openTestAppData();
        await appData.repositories.settings.set(c.key, c.stored);

        await tester.pumpWidget(
          CompendiumApp(
            appData: appData,
            windowService: NoopWindowService(appData.repositories.settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          c.read(tester.element(find.byType(AppShell))),
          c.storedResult,
          reason: 'the stored non-default value is applied at startup',
        );

        await _restoreFromPaste(tester, backupJson);

        expect(await appData.repositories.settings.get(c.key), isNull);
        expect(c.read(tester.element(find.byType(AppShell))), c.defaultValue);
      });
    }
  });

  testWidgets(
    'a settings read that throws for one key starts the app with that key at '
    'its default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openFlakySettingsAppData({kSortIgnoreArticlesKey});
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      final context = tester.element(find.byType(AppShell));
      expect(SortIgnoreArticlesScope.of(context), isTrue);
    },
  );

  testWidgets(
    'a custom-dialect library read that throws starts the app on Larks/Robins',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sink = _RecordingCrashLogSink();
      installCaughtErrorLog(sink);
      addTearDown(resetCaughtErrorLogForTesting);

      final appData = _openFlakySettingsAppData({kCustomDialectsKey});
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      final context = tester.element(find.byType(AppShell));
      expect(ActiveDialectScope.of(context), Dialect.larksRobins);
      // Not silent: the dialect load can also write, so the failure is logged.
      expect(sink.sources, contains('startup.dialect_library_load'));
    },
  );

  for (final heldKey in [kAppThemeKey, kLocaleKey]) {
    testWidgets(
      'a same-value restore never shows the default theme or language while '
      'the $heldKey read is in flight',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = openTestRepositories();
        await source.settings.set(kAppThemeKey, 'dark');
        await source.settings.set(kLocaleKey, 'de');
        final backupJson = await BackupService(source).exportToJson();

        final appData = _openFlakySettingsAppData({});
        await appData.repositories.settings.set(kAppThemeKey, 'dark');
        await appData.repositories.settings.set(kLocaleKey, 'de');
        await tester.pumpWidget(
          CompendiumApp(
            appData: appData,
            windowService: NoopWindowService(appData.repositories.settings),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(AppShell));
        final themeNotifier = AppThemeScope.notifierOf(context);
        final localeNotifier = LocaleScope.notifierOf(context);
        expect(themeNotifier.value, AppThemeSelection.dark);
        expect(localeNotifier.value, const Locale('de'));

        // Hold one read open (the theme read is the first to reassign a value,
        // the language read among the last) so frames can run mid-reload.
        final gate = Completer<void>();
        appData.flakySettings
          ..gateKey = heldKey
          ..gate = gate;
        var sampled = false;
        await _restoreFromPaste(
          tester,
          backupJson,
          whileReloading: () async {
            sampled = true;
            expect(
              themeNotifier.value,
              AppThemeSelection.dark,
              reason: 'theme flashed to the default mid-reload',
            );
            expect(
              localeNotifier.value,
              const Locale('de'),
              reason: 'language flashed to the default mid-reload',
            );
            gate.complete();
          },
        );

        expect(sampled, isTrue);
        expect(themeNotifier.value, AppThemeSelection.dark);
        expect(localeNotifier.value, const Locale('de'));
      },
    );
  }

  testWidgets('restoring a backup without the key returns danceShareFields to '
      'its default', (tester) async {
    // Pins the behaviour, not the reset-list line: the loader's decode of an
    // absent key also yields the default, so deleting the reset entry alone
    // would not turn this red.
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final source = openTestRepositories();
    final backupJson = await BackupService(source).exportToJson();

    final appData = openTestAppData();
    await appData.repositories.settings.set(kProgramDanceShareFieldsKey, [
      DanceShareField.authors.name,
    ]);
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
      ),
    );
    await tester.pumpAndSettle();

    var context = tester.element(find.byType(AppShell));
    expect(DanceShareFieldsScope.of(context), {DanceShareField.authors});

    await _restoreFromPaste(tester, backupJson);

    expect(
      await appData.repositories.settings.get(kProgramDanceShareFieldsKey),
      isNull,
    );
    context = tester.element(find.byType(AppShell));
    expect(DanceShareFieldsScope.of(context), DanceShareField.allExceptTunes);
  });

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
        windowService: NoopWindowService(initialAppData.repositories.settings),
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
        windowServiceFactory: (settings) => NoopWindowService(settings),
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

      final appData = openTestAppData();
      final failure = SnapshotFailure(
        fromVersion: 1,
        toVersion: 2,
        cause: SnapshotFailureCause.diskFull,
        error: const FileSystemException('no space left on device'),
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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

      final appData = openTestAppData();
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
          windowService: NoopWindowService(appData.repositories.settings),
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

  for (final reason in DatabaseRelocationFailure.values) {
    testWidgets('a blocked database relocation (${reason.name}) routes to a '
        'non-retryable terminal screen with its own message', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          migrationPreflight: (_) async =>
              throw DatabaseRelocationBlocked(reason),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      // The message for *this* reason, not the generic bootstrap error
      // screen's text; terminal, so no Retry (a retry would only open an
      // empty database beside the real library).
      expect(
        find.text(databaseRelocationMessage(l10n, reason)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.text(l10n.commonRetry), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });
  }

  testWidgets('the both-copies screen lists each copy with its size and last '
      'change, in the semantics (dbloc-6)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    final appData = openTestAppData();
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        migrationPreflight: (_) async => throw DatabaseRelocationBlocked(
          DatabaseRelocationFailure.bothExist,
          copies: [
            DatabaseCopy(
              location: DatabaseCopyLocation.newLocation,
              bytes: 98304,
              modified: DateTime(2026, 10, 6, 9, 5),
            ),
            DatabaseCopy(
              location: DatabaseCopyLocation.documents,
              bytes: 4415488,
              modified: DateTime(2026, 9, 30, 21, 40),
            ),
          ],
        ),
        integrityCheck: () async => true,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.migrationRelocationCopiesHeading), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^New location: 96 KB, last changed Oct 6, 2026 9:05\sAM$'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Documents folder: 4,312 KB, last changed Sep 30, 2026 9:40\sPM$',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'a wrong-typed theme_mode preference does not brick startup (issue #609)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
      // Simulate a restored/corrupt backup that persisted a non-string under
      // the theme key. The old startup read cast this with `as String?`, which
      // threw here and — because the value stays on disk — re-threw on every
      // subsequent launch, bricking the app. Startup must now tolerate it and
      // fall back to the default theme.
      await appData.repositories.settings.set(kAppThemeKey, 123);

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
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

  group('hidden Collection filters preference (#1419)', () {
    // The value the running app's scope holds after startup, read from inside
    // the tree the way a FacetPanel would.
    Future<Set<String>> bootAndReadHidden(
      WidgetTester tester,
      Object? stored,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appData = openTestAppData();
      if (stored != null) {
        await appData.repositories.settings.set(
          kCollectionHiddenFacetsKey,
          stored,
        );
      }
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      return CollectionFacetsScope.of(tester.element(find.byType(AppShell)));
    }

    testWidgets('a stored list is applied at startup', (tester) async {
      expect(await bootAndReadHidden(tester, ['tags', 'cf:abc']), {
        'tags',
        'cf:abc',
      });
    });

    testWidgets('an absent value hides nothing', (tester) async {
      expect(await bootAndReadHidden(tester, null), isEmpty);
    });

    testWidgets('a corrupt stored value hides nothing and does not crash', (
      tester,
    ) async {
      expect(await bootAndReadHidden(tester, 'tags'), isEmpty);
    });
  });

  group('on-launch ECD-convert prompt', () {
    const dialogKey = ValueKey('ecd-convert-prompt-dialog');

    Future<AppData> bootWithEcdTaggedDance(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appData = openTestAppData();
      // Lowercase "ecd", proving the match is case-insensitive.
      // ignore: unused_result
      await appData.repositories.tags.upsert(Tag(id: 'tag-ecd', name: 'ecd'));
      // ignore: unused_result
      await appData.repositories.tags.upsert(
        Tag(id: 'tag-keep', name: 'Waltz'),
      );
      await appData.repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Nonesuch',
          tagIds: const ['tag-ecd', 'tag-keep'],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      return appData;
    }

    testWidgets(
      'does not appear when nothing in the collection is tagged "ECD"',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final appData = openTestAppData();

        await tester.pumpWidget(
          CompendiumApp(
            appData: appData,
            windowService: NoopWindowService(appData.repositories.settings),
            integrityCheck: () async => true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(dialogKey), findsNothing);
      },
    );

    testWidgets('does not appear once the user has opted out', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appData = openTestAppData();
      // ignore: unused_result
      await appData.repositories.tags.upsert(Tag(id: 'tag-ecd', name: 'ECD'));
      await appData.repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Nonesuch',
          tagIds: const ['tag-ecd'],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await appData.repositories.settings.set(
        kEcdConvertPromptDismissedKey,
        true,
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(dialogKey), findsNothing);
    });

    testWidgets(
      'confirming converts the matching dance, strips only the "ECD" tag, '
      'and reports how many were converted',
      (tester) async {
        final appData = await bootWithEcdTaggedDance(tester);

        expect(find.byKey(dialogKey), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('ecd-convert-prompt-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(dialogKey), findsNothing);
        final dance = await appData.repositories.dances.getById('d1');
        expect(dance!.form, DanceForm.ecd);
        expect(dance.tagIds, ['tag-keep']);
        expect(
          find.text('Converted 1 dance to English (ECD).'),
          findsOneWidget,
        );
        expect(
          await appData.repositories.settings.get(
            kEcdConvertPromptDismissedKey,
          ),
          isNull,
          reason: 'declining the checkbox must not opt out future launches',
        );
      },
    );

    testWidgets('declining leaves the dance untouched', (tester) async {
      final appData = await bootWithEcdTaggedDance(tester);

      await tester.tap(
        find.byKey(const ValueKey('ecd-convert-prompt-decline')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(dialogKey), findsNothing);
      final dance = await appData.repositories.dances.getById('d1');
      expect(dance!.form, DanceForm.contra);
      expect(dance.tagIds, ['tag-ecd', 'tag-keep']);
    });

    testWidgets('checking "don\'t show this again" and declining persists the '
        'opt-out without converting', (tester) async {
      final appData = await bootWithEcdTaggedDance(tester);

      await tester.tap(
        find.byKey(const ValueKey('ecd-convert-prompt-dont-show-again')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ecd-convert-prompt-decline')),
      );
      await tester.pumpAndSettle();

      expect(
        await appData.repositories.settings.get(kEcdConvertPromptDismissedKey),
        isTrue,
      );
      final dance = await appData.repositories.dances.getById('d1');
      expect(dance!.form, DanceForm.contra);
    });

    testWidgets('checking "don\'t show this again" and confirming persists the '
        'opt-out and still converts', (tester) async {
      final appData = await bootWithEcdTaggedDance(tester);

      await tester.tap(
        find.byKey(const ValueKey('ecd-convert-prompt-dont-show-again')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ecd-convert-prompt-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        await appData.repositories.settings.get(kEcdConvertPromptDismissedKey),
        isTrue,
      );
      final dance = await appData.repositories.dances.getById('d1');
      expect(dance!.form, DanceForm.ecd);
    });
  });
}
