import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/backup_controller_scope.dart';
import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

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
  if (onRestored != null) {
    tree = BackupControllerScope(onRestored: onRestored, child: tree);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('export uses the save seam and stamps the last-backup time', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'A Dance'));

    String? capturedJson;
    await _pumpGeneral(
      tester,
      repos,
      saver: (json, name) async {
        capturedJson = json;
        return true;
      },
    );

    final button = find.byKey(const ValueKey('backup-export-button'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(capturedJson, isNotNull);
    expect(capturedJson, contains('backupVersion'));
    // A last-backup timestamp is now persisted.
    expect(
      lastBackupAtFromStored(await repos.settings.get(kLastBackupAtKey)),
      isNotNull,
    );
    expect(find.text('Backup exported.'), findsOneWidget);
  });

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

  testWidgets('restore via pasted JSON replaces content and refreshes', (
    tester,
  ) async {
    // Build a backup representing a "d1" dataset from a separate source.
    final source = openTestRepositories();
    await source.dances.create(_dance('d1', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();

    // The live repos starts with different, stale data.
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    var refreshed = false;
    await _pumpGeneral(tester, repos, onRestored: () async => refreshed = true);

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
    expect(find.text('Backup restored.'), findsOneWidget);
  });

  testWidgets('restore dialog can be cancelled without touching data', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    await _pumpGeneral(tester, repos, onRestored: () async {});

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-cancel')));
    await tester.pumpAndSettle();

    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
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
