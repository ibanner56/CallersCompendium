import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// A [SettingsRepository] whose `get` throws for [failingKey] while it is set,
/// as if that one row were unreadable during a backup restore's reload.
class _FlakySettings extends SettingsRepository {
  _FlakySettings(super.db);

  String? failingKey;

  @override
  Future<Object?> get(String key) async {
    if (key == failingKey) throw StateError('injected read failure: $key');
    return super.get(key);
  }
}

Future<(CompendiumRepositories, _FlakySettings)> _open() async {
  final db = openWidgetTestDatabase();
  final settings = _FlakySettings(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  await repos.ensureMigrated();
  return (repos, settings);
}

/// Every `load()` must be transactional: a read that fails part-way through
/// leaves the controller exactly as it was, never a mix of old and new state.
void main() {
  test('CustomThemesController keeps its themes when its read fails', () async {
    final (_, settings) = await _open();
    final c = CustomThemesController(settings);
    await c.upsert(
      CustomTheme(
        id: 'a',
        name: 'Mine',
        brightness: Brightness.light,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.light()),
      ),
    );
    await c.load();
    expect(c.themes.map((t) => t.id), ['a']);

    settings.failingKey = kCustomThemesKey;
    await expectLater(c.load(), throwsStateError);

    expect(c.themes.map((t) => t.id), ['a']);
  });

  test(
    'FormationColorsController keeps its overrides when the read fails',
    () async {
      final (_, settings) = await _open();
      final c = FormationColorsController(settings);
      await c.setColor(FormationShape.becketCw, const Color(0xFFFFEB3B));
      expect(c.overrides, isNotEmpty);

      settings.failingKey = kFormationColorOverridesKey;
      await expectLater(c.load(), throwsStateError);

      expect(c.overrideFor(FormationShape.becketCw), isNotNull);
    },
  );

  test(
    'DialectLibraryController keeps its library when its read fails',
    () async {
      final (_, settings) = await _open();
      final c = DialectLibraryController(settings);
      await c.load();
      final created = await c.duplicate(name: 'Mine');
      expect(c.customDialects.map((d) => d.name), [created.name]);

      settings.failingKey = kCustomDialectsKey;
      await expectLater(c.load(), throwsStateError);

      expect(c.customDialects.map((d) => d.name), [created.name]);
    },
  );

  test('SyncController keeps its state when a later read fails', () async {
    final (repos, settings) = await _open();
    final controller = SyncController(
      settings: settings,
      syncLocal: repos.syncLocal,
      coordinator: () => null,
      reconfigure: ({bool startPass = true}) async {},
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.enabled, isFalse);
    expect(controller.wifiOnly, isTrue);

    // The stored values changed (as after a restore), then a later read fails.
    await settings.set(kSyncEnabledKey, true);
    await settings.set(kSyncWifiOnlyKey, false);
    settings.failingKey = kSyncLastSuccessAtKey;
    await expectLater(controller.load(), throwsStateError);

    expect(controller.enabled, isFalse, reason: 'must not be a hybrid');
    expect(controller.wifiOnly, isTrue, reason: 'must not be a hybrid');
  });
}
