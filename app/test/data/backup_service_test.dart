import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/screens/settings_screen.dart'
    show kSortIgnoreArticlesKey;
import 'package:compendium_app/src/data/window_service.dart'
    show kWindowFrameKey;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _seed(CompendiumRepositories repos) async {
  await repos.dances.create(_dance('d1', 'Kept Dance'));
  await repos.settings.set(kCustomDialectsKey, [
    Dialect(name: 'My Dialect').toJson(),
  ]);
  await repos.settings.set(kActiveDialectRefKey, 'My Dialect');
  await repos.settings.set(kCustomThemesKey, [
    const CustomTheme(
      id: 'custom-1',
      name: 'Sunset',
      brightness: Brightness.dark,
      roles: {'primary': 0xFF112233},
    ).toJson(),
  ]);
  await repos.settings.set(kActiveCustomThemeKey, 'custom-1');
  await repos.settings.set(kSortIgnoreArticlesKey, false);
  // Device-local / metadata keys that must NOT travel in a backup.
  await repos.settings.set(kWindowFrameKey, 'some-geometry');
  await repos.settings.set(kLastBackupAtKey, '2020-01-01T00:00:00.000Z');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'buildDocument captures app-local pieces and excludes denylisted keys',
    () async {
      final repos = openTestRepositories();
      await _seed(repos);

      final doc = await BackupService(repos).buildDocument();

      expect(doc.core.dances.single.id, 'd1');
      expect(doc.customDialects.single.name, 'My Dialect');
      expect(doc.activeDialectRef, 'My Dialect');
      expect(doc.customThemes.single.id, 'custom-1');
      expect(doc.activeCustomThemeId, 'custom-1');
      expect(doc.settings[kSortIgnoreArticlesKey], false);
      // Denylisted keys are never carried in the settings map.
      expect(doc.settings.containsKey(kWindowFrameKey), isFalse);
      expect(doc.settings.containsKey(kLastBackupAtKey), isFalse);
      expect(doc.settings.containsKey(kCustomDialectsKey), isFalse);
      expect(doc.settings.containsKey(kCustomThemesKey), isFalse);
    },
  );

  test(
    'restore replaces content and re-applies dialects, themes, settings',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      // A fresh dataset with different, stale data to prove replace clears it.
      final target = openTestRepositories();
      await target.dances.create(_dance('stale', 'Should Be Gone'));
      await target.settings.set(kSortIgnoreArticlesKey, true);

      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.hasErrors, isFalse);

      // Content replaced.
      final dances = await target.dances.listAll();
      expect(dances.map((d) => d.id), ['d1']);

      // App-local pieces re-applied — verify via the real controllers.
      final dialects = DialectLibraryController(target.settings);
      await dialects.load();
      expect(dialects.customDialects.single.name, 'My Dialect');
      expect(dialects.activeName, 'My Dialect');

      final themes = CustomThemesController(target.settings);
      await themes.load();
      expect(themes.themes.single.id, 'custom-1');
      expect(themes.activeId, 'custom-1');

      expect(await target.settings.get(kSortIgnoreArticlesKey), false);
      // Device-local key was neither backed up nor restored.
      expect(await target.settings.get(kWindowFrameKey), isNull);
    },
  );

  test('recordBackup stamps the last-backup timestamp', () async {
    final repos = openTestRepositories();
    final at = DateTime.utc(2026, 7, 15, 9, 30);

    await BackupService(repos).recordBackup(at);

    expect(
      lastBackupAtFromStored(await repos.settings.get(kLastBackupAtKey)),
      at,
    );
  });

  test('restoring malformed JSON reports errors without throwing', () async {
    final repos = openTestRepositories();
    final outcome = await BackupService(repos).restoreFromJson('garbage {');
    expect(outcome.hasErrors, isTrue);
  });
}
