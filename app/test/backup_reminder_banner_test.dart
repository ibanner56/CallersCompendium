import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/backup_document.dart'
    show
        defaultBackupCodecRunner,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/data/backup_io.dart' show BackupSaver;
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/screens/app_shell.dart';

import 'support/full_app_harness.dart';
import 'support/test_repositories.dart';

/// A settings repository whose reads of [failingKeys] throw.
class _FlakySettings extends SettingsRepository {
  _FlakySettings(super.db, this.failingKeys);

  final Set<String> failingKeys;

  @override
  Future<Object?> get(String key) async {
    if (failingKeys.contains(key)) {
      throw StateError('injected read failure: $key');
    }
    return super.get(key);
  }
}

class _FlakySettingsAppData extends AppData {
  _FlakySettingsAppData(super.db, Set<String> failingKeys)
    : _repositories = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: _FlakySettings(db, failingKeys),
      );

  final CompendiumRepositories _repositories;

  @override
  CompendiumRepositories get repositories => _repositories;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Same boot hygiene as startup_sequence_test.dart: a fresh root bundle so the
  // offstage User Guide settles, and an inline backup codec because the fake
  // async never delivers a worker isolate's reply.
  setUp(rootBundle.clear);
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  final now = DateTime.utc(2026, 10, 5, 12);
  const bannerKey = ValueKey('backup-reminder-banner');

  Future<void> seed(
    AppData appData, {
    String? cadence,
    Duration? lastBackupAgo,
  }) async {
    final settings = appData.repositories.settings;
    if (cadence != null) {
      await settings.set(kBackupReminderCadenceKey, cadence);
    }
    if (lastBackupAgo != null) {
      await settings.set(
        kLastBackupAtKey,
        now.subtract(lastBackupAgo).toIso8601String(),
      );
    }
  }

  CompendiumApp appFor(AppData appData, {BackupSaver? backupSaver}) =>
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () async => true,
        nowOverride: () => now,
        backupSaver: backupSaver,
      );

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AppShell)));

  Future<void> bigSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('an overdue weekly backup reminder shows a banner on the '
      'Collection screen once per launch', (tester) async {
    await bigSurface(tester);
    final appData = openTestAppData();
    await seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 8),
    );

    await tester.pumpWidget(appFor(appData));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(bannerKey), findsOneWidget);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.backupReminderBannerText), findsOneWidget);
    expect(find.text(l10n.backupReminderBannerExport), findsOneWidget);

    await tester.tap(find.text(l10n.backupReminderBannerNotNow));
    await tester.pumpAndSettle();
    expect(find.byKey(bannerKey), findsNothing);

    // A rebuild of the ready widget within the same launch must not re-show it.
    await tester.pumpWidget(appFor(appData));
    await tester.pumpAndSettle();
    expect(find.byKey(bannerKey), findsNothing);
  });

  testWidgets('Export backup from the reminder banner records a backup', (
    tester,
  ) async {
    await bigSurface(tester);
    final appData = openTestAppData();
    await seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 8),
    );
    final saved = <String>[];

    await tester.pumpWidget(
      appFor(
        appData,
        backupSaver: (json, name) async {
          saved.add(name);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(bannerKey), findsOneWidget);

    await tester.tap(find.text(l10nOf(tester).backupReminderBannerExport));
    await tester.pumpAndSettle();

    expect(saved, ['callers-compendium-backup-2026-10-05.json']);
    expect(
      lastBackupAtFromStored(
        await appData.repositories.settings.get(kLastBackupAtKey),
      ),
      now,
    );
    expect(find.byKey(bannerKey), findsNothing);
    expect(find.text(l10nOf(tester).backupExported), findsOneWidget);
  });

  testWidgets('a cancelled export keeps the banner and stamps nothing', (
    tester,
  ) async {
    await bigSurface(tester);
    final appData = openTestAppData();
    await seed(appData, cadence: 'weekly');

    await tester.pumpWidget(
      appFor(appData, backupSaver: (json, name) async => false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nOf(tester).backupReminderBannerExport));
    await tester.pumpAndSettle();

    expect(find.byKey(bannerKey), findsOneWidget);
    expect(await appData.repositories.settings.get(kLastBackupAtKey), isNull);
  });

  testWidgets('cadence off never shows the banner even with no backup', (
    tester,
  ) async {
    await bigSurface(tester);
    final appData = openTestAppData();

    await tester.pumpWidget(appFor(appData));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(bannerKey), findsNothing);
  });

  testWidgets('a recent backup is not overdue, so no banner', (tester) async {
    await bigSurface(tester);
    final appData = openTestAppData();
    await seed(
      appData,
      cadence: 'weekly',
      lastBackupAgo: const Duration(days: 2),
    );

    await tester.pumpWidget(appFor(appData));
    await tester.pumpAndSettle();

    expect(find.byKey(bannerKey), findsNothing);
  });

  testWidgets('a settings read failure shows nothing and still opens the app', (
    tester,
  ) async {
    await bigSurface(tester);
    final appData = _FlakySettingsAppData(
      openWidgetTestDatabase(closeOnTearDown: false),
      {kBackupReminderCadenceKey},
    );
    addTearDown(appData.close);

    await tester.pumpWidget(appFor(appData));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(bannerKey), findsNothing);
  });
}
