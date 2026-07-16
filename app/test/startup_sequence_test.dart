import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/screens/app_shell.dart';

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

AppData _openAppData() {
  final appData = AppData(CompendiumDatabase(NativeDatabase.memory()));
  // The database is also closed by CompendiumApp.dispose(); sqlite3's close is
  // idempotent, so this teardown just guarantees cleanup even for the last test
  // in the file (whose widget tree is never unmounted).
  addTearDown(appData.close);
  return appData;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'startup sweep purges programs soft-deleted past the retention window '
    '(Stage 1.2)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = _openAppData();
      final now = DateTime.now().toUtc();
      // Soft-deleted 31 days ago: past the default 30-day retention → purged.
      await appData.repositories.programs.create(
        Program(
          id: 'old',
          title: 'Ancient Program',
          createdAt: now.subtract(const Duration(days: 60)),
          updatedAt: now.subtract(const Duration(days: 31)),
          deletedAt: now.subtract(const Duration(days: 31)),
        ),
      );
      // Soft-deleted yesterday: still inside the window → kept.
      await appData.repositories.programs.create(
        Program(
          id: 'recent',
          title: 'Recent Program',
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 1)),
          deletedAt: now.subtract(const Duration(days: 1)),
        ),
      );

      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
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
}
