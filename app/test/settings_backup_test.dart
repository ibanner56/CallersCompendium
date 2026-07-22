import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/backup_controller_scope.dart';
import 'package:compendium_app/src/data/backup_crypto.dart';
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

/// Encrypts [json] with cheap KDF params so widget tests stay fast while still
/// producing a real, valid encrypted container (issue #461).
Future<String> _encryptFast(String json, String passphrase) =>
    encryptBackup(json, passphrase, argon2MemoryKiB: 256, argon2Iterations: 1);

/// Pumps the General settings section backed by [repos], with the backup
/// save/pick seams and (optionally) an onRestored spy wired in.
Future<void> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos, {
  BackupSaver? saver,
  BackupPicker? picker,
  BackupEncryptor? encryptor,
  BackupDecryptor? decryptor,
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
          child: SettingsScreen(
            backupSaver: saver,
            backupPicker: picker,
            backupEncryptor: encryptor,
            backupDecryptor: decryptor,
          ),
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

    // The options dialog defaults to a plain (unencrypted) export.
    expect(find.byKey(const ValueKey('export-backup-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-confirm')));
    await tester.pumpAndSettle();

    expect(capturedJson, isNotNull);
    expect(capturedJson, contains('backupVersion'));
    expect(isEncryptedBackup(capturedJson!), isFalse);
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
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pumpAndSettle();

      expect(saverCalled, isTrue);
      expect(find.text('Backup exported.'), findsNothing);
      expect(find.text("Couldn't export a backup."), findsNothing);
      expect(await repos.settings.get(kLastBackupAtKey), isNull);
    },
  );

  testWidgets('cancelling the export options dialog is a clean no-op', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'A Dance'));

    var saverCalled = false;
    await _pumpGeneral(
      tester,
      repos,
      saver: (json, name) async {
        saverCalled = true;
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-cancel')));
    await tester.pumpAndSettle();

    expect(saverCalled, isFalse);
    expect(find.text('Backup exported.'), findsNothing);
    expect(await repos.settings.get(kLastBackupAtKey), isNull);
  });

  testWidgets('encrypted export produces an armored container via the seam', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'A Dance'));

    String? capturedPayload;
    String? capturedName;
    await _pumpGeneral(
      tester,
      repos,
      saver: (payload, name) async {
        capturedPayload = payload;
        capturedName = name;
        return true;
      },
      encryptor: _encryptFast,
    );

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();

    // Opt into encryption and enter a matching passphrase.
    await tester.tap(find.byKey(const ValueKey('export-encrypt-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('export-passphrase-field')),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.byKey(const ValueKey('export-confirm-field')),
      'correct horse battery staple',
    );
    await tester.pumpAndSettle();
    // The explicit no-recovery warning is shown.
    expect(
      find.byKey(const ValueKey('export-no-recovery-warning')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('export-confirm')));
    await tester.pumpAndSettle();

    expect(capturedPayload, isNotNull);
    // The delivered bytes are an encrypted container, not plain backup JSON,
    // and carry no plaintext entity data.
    expect(isEncryptedBackup(capturedPayload!), isTrue);
    expect(capturedPayload, isNot(contains('backupVersion')));
    expect(capturedPayload, isNot(contains('A Dance')));
    expect(capturedName, endsWith('.ccbackup'));
    expect(find.text('Encrypted backup exported.'), findsOneWidget);
  });

  testWidgets('encrypted export blocks confirm until passphrases match', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'A Dance'));

    await _pumpGeneral(tester, repos, encryptor: _encryptFast);

    await tester.tap(find.byKey(const ValueKey('backup-export-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-encrypt-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('export-passphrase-field')),
      'passphrase-one',
    );
    await tester.enterText(
      find.byKey(const ValueKey('export-confirm-field')),
      'passphrase-two',
    );
    await tester.pumpAndSettle();

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('export-confirm')),
    );
    expect(confirm.onPressed, isNull, reason: 'mismatched confirm disables it');
  });

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

  testWidgets('restoring an incomplete backup is refused with a clear message '
      'and leaves live data untouched (#430)', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    var refreshed = false;
    await _pumpGeneral(tester, repos, onRestored: () async => refreshed = true);

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();

    // A structurally-valid backup whose only dance carries an enum value this
    // build can't read: it decodes to an empty (incomplete) core. A replace
    // must be refused rather than reported as a clean "Backup restored." and
    // must not wipe live data.
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
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
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

    // The size-cap refusal is shown as a friendly message, not a crash, and
    // live data is untouched (the file was never read).
    expect(find.textContaining('too large'), findsOneWidget);
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
  });

  testWidgets('encrypted restore with the correct passphrase restores data', (
    tester,
  ) async {
    // Build a plain backup, then encrypt it into an armored container.
    final source = openTestRepositories();
    await source.dances.create(_dance('d1', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();
    final armored = await _encryptFast(backupJson, 'open sesame');

    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    var refreshed = false;
    await _pumpGeneral(
      tester,
      repos,
      decryptor: decryptBackup,
      onRestored: () async => refreshed = true,
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore-paste-field')),
      armored,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();

    // An encrypted container is detected and prompts for the passphrase.
    expect(
      find.byKey(const ValueKey('decrypt-passphrase-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('decrypt-passphrase-field')),
      'open sesame',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('decrypt-confirm')));
    await tester.pumpAndSettle();

    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['d1']);
    expect(refreshed, isTrue);
    expect(find.text('Backup restored.'), findsOneWidget);
  });

  testWidgets('encrypted restore with a wrong passphrase fails closed', (
    tester,
  ) async {
    final source = openTestRepositories();
    await source.dances.create(_dance('d1', 'Restored Dance'));
    final backupJson = await BackupService(source).exportToJson();
    final armored = await _encryptFast(backupJson, 'open sesame');

    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Old Dance'));

    var refreshed = false;
    await _pumpGeneral(
      tester,
      repos,
      decryptor: decryptBackup,
      onRestored: () async => refreshed = true,
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore-paste-field')),
      armored,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('decrypt-passphrase-field')),
      'wrong passphrase',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('decrypt-confirm')));
    await tester.pumpAndSettle();

    // Fail closed: a clean error, zero entities written, no refresh.
    expect(find.textContaining('Your data is unchanged.'), findsOneWidget);
    expect(find.text('Backup restored.'), findsNothing);
    expect(refreshed, isFalse);
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
