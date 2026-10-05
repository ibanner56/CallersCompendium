import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/backup_document.dart'
    show
        defaultBackupCodecRunner,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

const _bannerKey = ValueKey('backup-reminder-banner');

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _seed(
  AppData appData, {
  String? cadence,
  Duration? lastBackupAgo,
}) async {
  final settings = appData.repositories.settings;
  if (cadence != null) await settings.set(kBackupReminderCadenceKey, cadence);
  if (lastBackupAgo != null) {
    await settings.set(
      kLastBackupAtKey,
      DateTime.now().toUtc().subtract(lastBackupAgo).toIso8601String(),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  AppData appData, {
  BackupSaverFn? saver,
}) async {
  await tester.pumpWidget(
    CompendiumApp(
      appData: appData,
      windowService: NoopWindowService(appData.repositories.settings),
      integrityCheck: () async => true,
      backupSaver: saver,
    ),
  );
  await tester.pumpAndSettle();
}

typedef BackupSaverFn = Future<bool> Function(String json, String name);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Same startup-test setup as startup_sequence_test.dart: a fresh asset cache
  // so the offstage User Guide settles, and the backup codec inline because
  // fake async never delivers a worker isolate's reply.
  setUp(rootBundle.clear);
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  testWidgets('an overdue weekly backup reminder shows a banner on the '
      'Collection screen once per launch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = await _l10n();
    final appData = openTestAppData();
    await _seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 8),
    );

    await _pump(tester, appData);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(_bannerKey), findsOneWidget);
    expect(find.text(l10n.backupReminderBannerText), findsOneWidget);

    await tester.tap(find.text(l10n.backupReminderBannerNotNow));
    await tester.pumpAndSettle();
    expect(find.byKey(_bannerKey), findsNothing);

    // A rebuild of the ready tree must not re-raise it this launch.
    tester.element(find.byType(AppShell)).visitAncestorElements((e) {
      e.markNeedsBuild();
      return true;
    });
    await tester.pumpAndSettle();
    expect(find.byKey(_bannerKey), findsNothing);
  });

  testWidgets('Export backup from the reminder banner records a backup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = await _l10n();
    final appData = openTestAppData();
    await _seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 8),
    );
    final saved = <String>[];

    await _pump(
      tester,
      appData,
      saver: (json, name) async {
        saved.add(name);
        return true;
      },
    );
    await tester.tap(find.text(l10n.backupReminderBannerExport));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(find.byKey(_bannerKey), findsNothing);
    final stamped = lastBackupAtFromStored(
      await appData.repositories.settings.get(kLastBackupAtKey),
    );
    expect(DateTime.now().toUtc().difference(stamped!).inMinutes, lessThan(5));
  });

  testWidgets(
    'cancelling the save dialog keeps the banner and stamps nothing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final l10n = await _l10n();
      final appData = openTestAppData();
      await _seed(appData, cadence: 'weekly');

      await _pump(tester, appData, saver: (_, _) async => false);
      await tester.tap(find.text(l10n.backupReminderBannerExport));
      await tester.pumpAndSettle();

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(await appData.repositories.settings.get(kLastBackupAtKey), isNull);
    },
  );

  testWidgets('cadence off never shows the banner even with no backup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appData = openTestAppData();

    await _pump(tester, appData);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(_bannerKey), findsNothing);
  });

  testWidgets('a recent backup under a weekly cadence shows no banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appData = openTestAppData();
    await _seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 1),
    );

    await _pump(tester, appData);

    expect(find.byKey(_bannerKey), findsNothing);
  });
}
