import 'dart:async';
import 'dart:convert';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/sync_writer_lifecycle_scope.dart';
import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/data/backup_document.dart'
    show
        BackupDocument,
        defaultBackupCodecRunner,
        encodeBackup,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart'
    show kSoftDeleteRetentionDefaultDays, kSoftDeleteRetentionKey;
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';
import 'support/noop_sync_transport.dart';

/// Parks the write after the first [passes] inserts until released, so a
/// restore can be frozen mid-`_load` (an in-memory DB otherwise finishes in one
/// microtask and the progress frame would never render).
class _InsertGate extends drift.QueryInterceptor {
  Completer<void>? _gate;
  int _passes = 0;

  void arm(Completer<void> gate, {required int passes}) {
    _gate = gate;
    _passes = passes;
  }

  Future<void> _maybeBlock() async {
    final gate = _gate;
    if (gate == null || gate.isCompleted) return;
    if (_passes > 0) {
      _passes--;
      return;
    }
    _gate = null;
    await gate.future;
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _maybeBlock();
    return executor.runInsert(statement, args);
  }
}

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Pumps the General settings section backed by [repos], with the backup
/// save/pick seams and (optionally) an onRestored spy wired in.
Future<void> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos, {
  BackupSaver? saver,
  BackupPicker? picker,
  Future<void> Function()? onRestored,
  Future<void> Function()? beforeRestore,
  Future<void> Function()? afterRestore,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);

  Widget tree = RepositoriesScope(
    repositories: repos,
    child: AppThemeScope(
      notifier: theme,
      child: CustomThemesScope(
        controller: customThemes,
        child: ActiveDialectScope(
          notifier: dialect,
          child: SettingsScreen(backupSaver: saver, backupPicker: picker),
        ),
      ),
    ),
  );
  if (onRestored != null || beforeRestore != null || afterRestore != null) {
    tree = SyncWriterLifecycleScope(
      onRestored: onRestored ?? () async {},
      runWrite: <T>(operation) async {
        try {
          await beforeRestore?.call();
          return await operation();
        } finally {
          await afterRestore?.call();
        }
      },
      child: tree,
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: tree,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();
  // testWidgets' fake async never delivers a worker isolate's reply, so the
  // service's codec runs inline here (production runs it on an isolate).
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  testWidgets(
    'export uses the save seam, wraps a checksum container, and stamps the '
    'last-backup time',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'A Dance'));

      String? capturedJson;
      String? capturedName;
      await _pumpGeneral(
        tester,
        repos,
        saver: (json, name) async {
          capturedJson = json;
          capturedName = name;
          return true;
        },
      );

      final button = find.byKey(const ValueKey('backup-export-button'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // The delivered bytes are the integrity container (issue #536): a
      // SHA-256 checksum wrapping the document payload, saved as `.json`.
      expect(capturedJson, isNotNull);
      final envelope = jsonDecode(capturedJson!) as Map<String, Object?>;
      expect(envelope['backupContainer'], 1);
      final checksum = envelope['checksum'] as Map<String, Object?>;
      expect(checksum['algorithm'], 'sha256');
      expect(checksum['value'] as String, isNotEmpty);
      expect(envelope['payload'], isA<String>());
      expect(capturedName, endsWith('.json'));
      // A last-backup timestamp is now persisted.
      expect(
        lastBackupAtFromStored(await repos.settings.get(kLastBackupAtKey)),
        isNotNull,
      );
      expect(find.text('Backup exported.'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling the save/share dialog is a no-op (no snackbar, no stamp)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'A Dance'));

      var saverCalled = false;
      await _pumpGeneral(
        tester,
        repos,
        saver: (json, name) async {
          saverCalled = true;
          return false;
        },
      );

      final button = find.byKey(const ValueKey('backup-export-button'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(saverCalled, isTrue);
      expect(find.text('Backup exported.'), findsNothing);
      expect(find.text("Couldn't export a backup."), findsNothing);
      expect(await repos.settings.get(kLastBackupAtKey), isNull);
    },
  );

  testWidgets('restore via pasted container replaces content and refreshes', (
    tester,
  ) async {
    // Build a backup representing a "d1" dataset from a separate source.
    final source = openTestRepositories();
    await source.dances.create(_dance('d1', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();

    // The live repos starts with different, stale data.
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));
    await repos.settings.set(kSoftDeleteRetentionKey, 90);

    var refreshed = false;
    await _pumpGeneral(tester, repos, onRestored: () async => refreshed = true);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('general-soft-delete-retention')),
          )
          .value,
      90,
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-backup-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('restore-paste-field')),
      backupJson,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();

    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['d1']);
    expect(refreshed, isTrue, reason: 'onRestored should refresh the live app');
    expect(await repos.settings.get(kSoftDeleteRetentionKey), isNull);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('general-soft-delete-retention')),
          )
          .value,
      kSoftDeleteRetentionDefaultDays,
    );
    expect(find.text('Backup restored.'), findsOneWidget);
  });

  testWidgets(
    'restore waits for the active sync pass before replacing content',
    (tester) async {
      final source = openTestRepositories();
      await source.dances.create(_dance('restored', 'Restored Dance'));
      final backupJson = await BackupService(source).exportToJson();

      final repos = openTestRepositories();
      await repos.dances.create(_dance('live', 'Live Dance'));

      final passGate = Completer<void>();
      final passStarted = Completer<void>();
      final lifecycle = <String>[];
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({SyncStoreResult? initialStore}) async {
          if (!passStarted.isCompleted) passStarted.complete();
          await passGate.future;
          final oldPass = _dance('old-pass', 'Old Pass Dance');
          await repos.dances.create(oldPass);
          await repos.syncLocal.replaceBaseline(
            epoch: 'old-pass-epoch',
            entries: [
              SyncBaselineEntry(
                kind: SyncRecordKind.dance,
                recordId: oldPass.id,
                wireHash: 'old-pass-wire-hash',
              ),
            ],
          );
          return const SyncPassResult(SyncPassStatus.completed);
        },
      );
      addTearDown(coordinator.dispose);

      final inFlight = coordinator.syncNow();
      await passStarted.future;

      var refreshed = false;
      await _pumpGeneral(
        tester,
        repos,
        onRestored: () async {
          lifecycle.add('refresh');
          refreshed = true;
        },
        beforeRestore: () async {
          lifecycle.add('before');
          await coordinator.dispose();
          lifecycle.add('pass-complete');
        },
        afterRestore: () async {
          expect(
            await repos.dances.getById('restored'),
            isNotNull,
            reason: 'the restore must commit before the post-hook runs',
          );
          lifecycle.add('after');
        },
      );

      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        backupJson,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pump();

      // The pre-hook is waiting in coordinator.dispose(), so the restore
      // transaction must not have started while the active pass is gated.
      expect(lifecycle, ['before']);
      expect(await repos.dances.getById('live'), isNotNull);
      expect(await repos.dances.getById('restored'), isNull);
      expect(await repos.dances.getById('old-pass'), isNull);

      passGate.complete();
      expect((await inFlight).status, SyncPassStatus.completed);
      await tester.pumpAndSettle();

      expect(lifecycle, ['before', 'pass-complete', 'after', 'refresh']);
      expect(refreshed, isTrue);
      expect(await repos.dances.getById('live'), isNull);
      expect(await repos.dances.getById('old-pass'), isNull);
      expect(await repos.dances.getById('restored'), isNotNull);
      expect(await repos.syncLocal.snapshotBaseline(), isEmpty);
    },
  );

  testWidgets(
    'a second restore activation cannot overlap a restore waiting for sync',
    (tester) async {
      final source = openTestRepositories();
      await source.dances.create(_dance('restored', 'Restored Dance'));
      final backupJson = await BackupService(source).exportToJson();
      final repos = openTestRepositories();
      final preHookGate = Completer<void>();
      var beforeCalls = 0;

      await _pumpGeneral(
        tester,
        repos,
        picker: () async => backupJson,
        beforeRestore: () async {
          beforeCalls++;
          await preHookGate.future;
        },
      );

      final button = find.byKey(const ValueKey('backup-restore-button'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      // pump, not pumpAndSettle: the restore progress dialog is already up
      // while the pre-hook waits, and its indeterminate bar never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(beforeCalls, 1);

      // The first restore is blocked in its pre-hook. A second tap must not
      // open another dialog or invoke the lifecycle a second time.
      await tester.tap(button);
      await tester.pump();
      expect(find.byKey(const ValueKey('restore-backup-dialog')), findsNothing);
      expect(beforeCalls, 1);

      preHookGate.complete();
      await tester.pumpAndSettle();
      expect(beforeCalls, 1);
      expect((await repos.dances.listAll()).map((dance) => dance.id), [
        'restored',
      ]);
    },
  );

  testWidgets(
    'a tampered container fails the integrity check and leaves data untouched '
    '(#536)',
    (tester) async {
      final source = openTestRepositories();
      await source.dances.create(_dance('d1', 'Restored Dance'));
      final backupJson = await BackupService(source).exportToJson();

      // Alter the payload without recomputing the checksum: exactly the
      // corruption/tamper the SHA-256 guard exists to catch.
      final envelope = jsonDecode(backupJson) as Map<String, Object?>;
      envelope['payload'] = (envelope['payload'] as String).replaceFirst(
        'Restored Dance',
        'Tampered Dance',
      );
      final tampered = jsonEncode(envelope);

      final repos = openTestRepositories();
      await repos.dances.create(_dance('stale', 'Old Dance'));

      var refreshed = false;
      final lifecycle = <String>[];
      await _pumpGeneral(
        tester,
        repos,
        onRestored: () async => refreshed = true,
        beforeRestore: () async => lifecycle.add('before'),
        afterRestore: () async => lifecycle.add('after'),
      );

      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        tampered,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pumpAndSettle();

      // Refused with the integrity message; live data intact; no refresh.
      expect(find.textContaining('integrity check'), findsOneWidget);
      expect(find.text('Backup restored.'), findsNothing);
      expect(refreshed, isFalse);
      expect(lifecycle, ['before', 'after']);
      final dances = await repos.dances.listAll();
      expect(dances.map((d) => d.id), ['stale']);
    },
  );

  testWidgets(
    'a legacy bare-document backup (no container) still restores (#536 '
    'back-compat)',
    (tester) async {
      // The container's payload is exactly the pre-#536 bare document JSON;
      // restoring that directly proves old plain `.json` backups still work.
      final source = openTestRepositories();
      await source.dances.create(_dance('d1', 'Restored Dance'));
      final container = await BackupService(source).exportToJson();
      final bareJson =
          (jsonDecode(container) as Map<String, Object?>)['payload'] as String;

      final repos = openTestRepositories();
      await repos.dances.create(_dance('stale', 'Old Dance'));

      await _pumpGeneral(tester, repos, onRestored: () async {});

      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        bareJson,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pumpAndSettle();

      final dances = await repos.dances.listAll();
      expect(dances.map((d) => d.id), ['d1']);
      expect(find.text('Backup restored.'), findsOneWidget);
    },
  );

  testWidgets('restoring an incomplete backup is refused with a clear message '
      'and leaves live data untouched (#430)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    var refreshed = false;
    final lifecycle = <String>[];
    await _pumpGeneral(
      tester,
      repos,
      onRestored: () async => refreshed = true,
      beforeRestore: () async => lifecycle.add('before'),
      afterRestore: () async => lifecycle.add('after'),
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();

    // A structurally-valid bare backup whose only dance carries an enum value
    // this build can't read: it decodes to an empty (incomplete) core. A
    // replace must be refused rather than reported as a clean "Backup restored."
    // and must not wipe live data. (Bare document exercises the back-compat
    // path; no container/checksum is required for legacy files.)
    const incompleteJson =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"dances":[{"id":"newer","title":"Newer",'
        '"status":"from_the_future",'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}]},"app":{}}';
    await tester.enterText(
      find.byKey(const ValueKey('restore-paste-field')),
      incompleteJson,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();

    // Refused, not a clean success; live data intact; no refresh triggered.
    expect(find.text('Backup restored.'), findsNothing);
    expect(find.textContaining("can't read"), findsOneWidget);
    expect(refreshed, isFalse);
    expect(lifecycle, ['before', 'after']);
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
  });

  for (final (label, json, expected) in [
    (
      'a newer-schema backup',
      '{"backupVersion":999,"createdAt":"2026-07-15T00:00:00.000Z",'
          '"core":{},"app":{}}',
      "can't read",
    ),
    (
      'a backup with no app section',
      '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z","core":{}}',
      "doesn't include your app settings",
    ),
  ]) {
    testWidgets('restoring $label is refused with its own message and leaves '
        'live data untouched', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('stale', 'Old Dance'));
      var refreshed = false;
      await _pumpGeneral(
        tester,
        repos,
        onRestored: () async => refreshed = true,
      );

      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        json,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Backup restored.'), findsNothing);
      expect(find.textContaining(expected), findsOneWidget);
      expect(refreshed, isFalse);
      expect((await repos.dances.listAll()).map((d) => d.id), ['stale']);
    });
  }

  testWidgets('restore dialog can be cancelled without touching data', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));
    final lifecycle = <String>[];

    await _pumpGeneral(
      tester,
      repos,
      onRestored: () async {},
      beforeRestore: () async => lifecycle.add('before'),
      afterRestore: () async => lifecycle.add('after'),
    );
    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-cancel')));
    await tester.pumpAndSettle();

    expect(lifecycle, isEmpty);
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
  });

  testWidgets('choosing an oversized backup file surfaces a friendly error', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    await _pumpGeneral(
      tester,
      repos,
      picker: () async => throw const BackupFileTooLargeException(
        sizeBytes: 60 * 1024 * 1024,
        maxBytes: 50 * 1024 * 1024,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    // The size-cap refusal is shown as a friendly, translated message (not
    // the exception's text, not a crash), and live data is untouched (the file
    // was never read).
    expect(
      find.text(AppLocalizationsEn().backupFileTooLarge('60.0', '50.0')),
      findsOneWidget,
    );
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
  });

  testWidgets('restore shows determinate progress while the service runs', (
    tester,
  ) async {
    final source = openTestRepositories();
    await source.dances.create(_dance('restored', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();

    final gate = _InsertGate();
    final repos = CompendiumRepositories(
      openWidgetTestDatabase(
        executor: NativeDatabase.memory().interceptWith(gate),
      ),
      contraTaxonomy,
    );
    await _pumpGeneral(tester, repos, picker: () async => backupJson);

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    // Park the restore after its first record is written.
    final release = Completer<void>();
    gate.arm(release, passes: 1);
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final bar = find.descendant(
      of: find.byKey(const ValueKey('restore-progress')),
      matching: find.byType(LinearProgressIndicator),
    );
    expect(bar, findsOneWidget);
    final value = tester.widget<LinearProgressIndicator>(bar).value;
    expect(value, isNotNull, reason: 'determinate once the total is known');
    expect(value, greaterThan(0));
    expect(value, lessThan(1));
    expect(
      find.textContaining(RegExp(r'^Restoring \d+ of \d+')),
      findsOneWidget,
    );

    // The progress dialog cannot be dismissed (back button / barrier).
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(find.byKey(const ValueKey('restore-progress')), findsOneWidget);

    release.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-progress')), findsNothing);
    expect(find.text(AppLocalizationsEn().backupRestored), findsOneWidget);
    expect((await repos.dances.listAll()).map((d) => d.id), ['restored']);
  });

  testWidgets('export shows a progress state until the saver returns', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'A Dance'));
    final saverGate = Completer<bool>();
    await _pumpGeneral(tester, repos, saver: (json, name) => saverGate.future);

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final progress = find.byKey(const ValueKey('export-progress'));
    expect(progress, findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.descendant(
              of: progress,
              matching: find.byType(LinearProgressIndicator),
            ),
          )
          .value,
      isNull,
      reason: 'export has no done/total, so the bar is indeterminate',
    );
    expect(
      find.text(AppLocalizationsEn().backupExportInProgress),
      findsOneWidget,
    );

    saverGate.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-progress')), findsNothing);
    expect(find.text(AppLocalizationsEn().backupExported), findsOneWidget);
  });

  testWidgets('a cancelled export closes the progress state with no snackbar', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos, saver: (json, name) async => false);

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('export-progress')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an export over the size cap shows the translated refusal', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(
      tester,
      repos,
      saver: (json, name) async => throw const BackupExportTooLargeException(
        sizeBytes: 60 * 1024 * 1024,
        maxBytes: 50 * 1024 * 1024,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('export-progress')), findsNothing);
    expect(
      find.text(AppLocalizationsEn().backupExportTooLarge('60.0', '50.0')),
      findsOneWidget,
    );
  });

  testWidgets('choosing a large file shows a summary, not the pasted file', (
    tester,
  ) async {
    // ~5 MB of valid backup: 50 dances with 100 kB of calling notes each.
    final big = encodeBackup(
      BackupDocument(
        createdAt: DateTime.utc(2026, 7, 15),
        core: CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [
            for (var i = 0; i < 50; i++)
              Dance(
                id: 'd$i',
                title: 'Dance $i',
                callingNotes: 'x' * 100000,
                createdAt: DateTime.utc(2026, 1, 1),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
          ],
        ),
      ),
    );
    expect(big.length, greaterThan(5 * 1000 * 1000));

    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos, picker: () async => big);

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('restore-paste-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.enabled, isFalse, reason: 'a held file disables pasting');
    expect(find.byKey(const ValueKey('restore-file-summary')), findsOneWidget);
    expect(find.textContaining('50 dances'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('restore-confirm')))
          .onPressed,
      isNotNull,
    );

    // Clear forgets the file and re-enables pasting.
    await tester.tap(find.byKey(const ValueKey('restore-file-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-file-summary')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('restore-paste-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('restore-confirm')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an unreadable file is summarised as such and Replace stays on', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('keep', 'Keep Me'));
    await _pumpGeneral(tester, repos, picker: () async => 'not a backup');

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restore-file-summary')), findsOneWidget);
    expect(find.textContaining("doesn't look like a readable"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();

    // The service owns the refusal; live data is untouched.
    expect(
      find.text(AppLocalizationsEn().backupRestoreInvalidFile),
      findsOneWidget,
    );
    expect((await repos.dances.listAll()).map((d) => d.id), ['keep']);
  });

  testWidgets('a picker that throws FormatException shows a message', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(
      tester,
      repos,
      picker: () async => throw const FormatException('bad utf-8'),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupRestoreInvalidFile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picker that throws another Object shows a generic message', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(
      tester,
      repos,
      picker: () async => throw StateError('picker'),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-choose-file')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupChooseFileFailed), findsOneWidget);
  });

  testWidgets('a saver that throws an Error shows backupExportFailed', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(
      tester,
      repos,
      saver: (_, _) async => throw StateError('disk'),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupExportFailed), findsOneWidget);
  });

  testWidgets('a double tap on Export calls the saver once', (tester) async {
    final repos = openTestRepositories();
    final gate = Completer<bool>();
    var calls = 0;
    await _pumpGeneral(
      tester,
      repos,
      saver: (_, _) {
        calls++;
        return gate.future;
      },
    );

    final button = find.byKey(const ValueKey('backup-export-button'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    gate.complete(true);
    await tester.pumpAndSettle();

    expect(calls, 1);

    // The flag is cleared afterwards: a later export runs again.
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
    'a settings-apply failure after the core commit shows a retryable message '
    '(not a false success), and Retry applies settings once the store recovers '
    '(#608)',
    (tester) async {
      // A valid backup from a separate source.
      final source = openTestRepositories();
      await source.dances.create(_dance('d1', 'Restored Dance'));
      final backupJson = await BackupService(source).exportToJson();

      // Live repos whose settings store fails its writes: the core restore
      // commits, but the SEPARATE settings apply throws.
      final target = openTestRepositoriesWithFailingSettings();
      await target.repos.dances.create(_dance('stale', 'Old Dance'));
      target.settings.failWrites = false;
      await target.repos.settings.set(kSoftDeleteRetentionKey, 90);
      target.settings.failWrites = true;

      var refreshCount = 0;
      final lifecycle = <String>[];
      await _pumpGeneral(
        tester,
        target.repos,
        onRestored: () async => refreshCount++,
        beforeRestore: () async => lifecycle.add('before'),
        afterRestore: () async => lifecycle.add('after'),
      );
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('general-soft-delete-retention')),
            )
            .value,
        90,
      );

      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('restore-paste-field')),
        backupJson,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-confirm')));
      await tester.pumpAndSettle();

      // Core committed and refreshed; the retryable settings message + action
      // show; crucially NO false success is reported.
      expect((await target.repos.dances.listAll()).map((d) => d.id), ['d1']);
      expect(refreshCount, 1);
      expect(lifecycle, ['before', 'after']);
      expect(
        find.textContaining('applying your saved settings failed'),
        findsOneWidget,
      );
      expect(find.text('Retry settings'), findsOneWidget);
      expect(find.text('Backup restored.'), findsNothing);
      expect(find.text('Settings applied.'), findsNothing);
      expect(await target.repos.settings.get(kSoftDeleteRetentionKey), isNull);
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('general-soft-delete-retention')),
            )
            .value,
        kSoftDeleteRetentionDefaultDays,
      );

      // The store recovers; tapping Retry re-applies ONLY settings and now
      // reports the success (and refreshes again).
      target.settings.failWrites = false;
      await tester.tap(find.text('Retry settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings applied.'), findsOneWidget);
      expect(refreshCount, 2);
      expect(lifecycle, [
        'before',
        'after',
      ], reason: 'settings-only retry must not re-enter sync lifecycle');
      expect(await target.repos.settings.get(kSoftDeleteRetentionKey), isNull);
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('general-soft-delete-retention')),
            )
            .value,
        kSoftDeleteRetentionDefaultDays,
      );
    },
  );

  testWidgets('a failed restore pre-hook still runs the post-hook recovery', (
    tester,
  ) async {
    final source = openTestRepositories();
    await source.dances.create(_dance('d1', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();

    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));
    final lifecycle = <String>[];
    var refreshed = false;

    await _pumpGeneral(
      tester,
      repos,
      onRestored: () async => refreshed = true,
      beforeRestore: () async {
        lifecycle.add('before');
        throw const FormatException('injected restore pre-hook failure');
      },
      afterRestore: () async => lifecycle.add('after'),
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore-paste-field')),
      backupJson,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();

    expect(lifecycle, ['before', 'after']);
    expect(refreshed, isFalse);
    expect(find.text("Couldn't restore the backup."), findsOneWidget);
    expect((await repos.dances.listAll()).map((dance) => dance.id), ['stale']);
  });

  testWidgets('changing the reminder cadence persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos, onRestored: () async {});

    await tester.tap(find.byKey(const ValueKey('backup-reminder-cadence')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();

    expect(
      backupReminderCadenceFromStored(
        await repos.settings.get(kBackupReminderCadenceKey),
      ),
      BackupReminderCadence.weekly,
    );
  });
}
