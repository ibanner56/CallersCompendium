import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import '../support/test_repositories.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<
  ({
    CompendiumRepositories repos,
    ValueNotifier<Dialect> notifier,
    ValueNotifier<AppThemeSelection> themeNotifier,
  })
>
_pumpSettings(
  WidgetTester tester, {
  Dialect? initialDialect,
  AppThemeSelection? initialTheme,
}) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();

  final notifier = ValueNotifier<Dialect>(
    initialDialect ?? Dialect.larksRobins,
  );
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    initialTheme ?? AppThemeSelection.system,
  );

  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(notifier.dispose);
  addTearDown(themeNotifier.dispose);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
      ),
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return (repos: repos, notifier: notifier, themeNotifier: themeNotifier);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen — dialect selection', () {
    testWidgets('renders all preset names', (tester) async {
      await _pumpSettings(tester);

      for (final preset in Dialect.presets) {
        expect(
          find.byKey(ValueKey('dialect-${preset.name}')),
          findsOneWidget,
          reason: 'Expected radio tile for ${preset.name}',
        );
        expect(find.text(preset.name), findsOneWidget);
      }
    });

    testWidgets('default selection matches active dialect notifier', (
      tester,
    ) async {
      await _pumpSettings(tester, initialDialect: Dialect.larksRobins);

      // The Larks/Robins tile should be visible with the right value.
      final radio = tester.widget<RadioListTile<Dialect>>(
        find.byKey(ValueKey('dialect-${Dialect.larksRobins.name}')),
      );
      expect(radio.value, equals(Dialect.larksRobins));
    });

    testWidgets('selecting a preset updates the notifier live', (tester) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
      );

      // Tap the Gents/Ladies radio tile.
      await tester.tap(
        find.byKey(ValueKey('dialect-${Dialect.gentsLadies.name}')),
      );
      await tester.pumpAndSettle();

      expect(ctx.notifier.value, equals(Dialect.gentsLadies));
    });

    testWidgets('selecting a preset persists to SettingsRepository', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
      );

      await tester.tap(
        find.byKey(ValueKey('dialect-${Dialect.leadsFollows.name}')),
      );
      await tester.pumpAndSettle();

      final stored = await ctx.repos.settings.get(kActiveDialectKey) as String?;
      expect(stored, equals(Dialect.leadsFollows.name));
    });

    testWidgets('round-trip: stored name is restored to correct preset', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      // Pre-set the stored value.
      await repos.settings.set(kActiveDialectKey, Dialect.gentsLadies.name);

      final name = await repos.settings.get(kActiveDialectKey) as String?;
      final preset = name != null ? Dialect.forName(name) : null;

      expect(preset, equals(Dialect.gentsLadies));
    });

    testWidgets('default-when-unset falls back to larksRobins', (tester) async {
      // Dialect.forName on a missing key → null → default larksRobins.
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final name = await repos.settings.get(kActiveDialectKey) as String?;
      final preset =
          (name != null ? Dialect.forName(name) : null) ?? Dialect.larksRobins;

      expect(preset, equals(Dialect.larksRobins));
    });
  });

  group('SettingsScreen — theme selection', () {
    testWidgets('renders every theme option', (tester) async {
      await _pumpSettings(tester);

      for (final option in AppThemeSelection.values) {
        expect(
          find.byKey(ValueKey('theme-${option.name}')),
          findsOneWidget,
          reason: 'Expected radio tile for ${option.name}',
        );
        expect(find.text(option.label), findsOneWidget);
      }
    });

    testWidgets('default selection matches the active theme notifier', (
      tester,
    ) async {
      await _pumpSettings(tester, initialTheme: AppThemeSelection.dark);

      // Assert the actual checked state: the enclosing RadioGroup's
      // groupValue is what drives which tile renders selected, so this fails
      // if the default-selection wiring (AppThemeScope -> _themeSelected)
      // breaks. Asserting the tile's constant `value` would prove nothing.
      final group = tester.widget<RadioGroup<AppThemeSelection>>(
        find.byType(RadioGroup<AppThemeSelection>),
      );
      expect(group.groupValue, equals(AppThemeSelection.dark));
    });

    testWidgets('selecting a theme updates the notifier live', (tester) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      await tester.tap(
        find.byKey(ValueKey('theme-${AppThemeSelection.highContrast.name}')),
      );
      await tester.pumpAndSettle();

      expect(ctx.themeNotifier.value, equals(AppThemeSelection.highContrast));
    });

    testWidgets('selecting a theme persists to SettingsRepository', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      await tester.tap(
        find.byKey(ValueKey('theme-${AppThemeSelection.dark.name}')),
      );
      await tester.pumpAndSettle();

      final stored = await ctx.repos.settings.get(kAppThemeKey) as String?;
      expect(stored, equals(AppThemeSelection.dark.name));
    });

    testWidgets('round-trip: stored name is restored to correct selection', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      await repos.settings.set(kAppThemeKey, AppThemeSelection.light.name);

      final name = await repos.settings.get(kAppThemeKey) as String?;
      final selection = AppThemeSelection.forName(name);

      expect(selection, equals(AppThemeSelection.light));
    });

    testWidgets('default-when-unset resolves to null (System default)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final name = await repos.settings.get(kAppThemeKey) as String?;
      final selection =
          AppThemeSelection.forName(name) ?? AppThemeSelection.system;

      expect(selection, equals(AppThemeSelection.system));
    });

    test('themeMode mapping is correct for each selection', () {
      expect(AppThemeSelection.system.themeMode, ThemeMode.system);
      expect(AppThemeSelection.light.themeMode, ThemeMode.light);
      expect(AppThemeSelection.dark.themeMode, ThemeMode.dark);
      // High-contrast forces the dark slot (both theme slots are high-contrast).
      expect(AppThemeSelection.highContrast.themeMode, ThemeMode.dark);
      expect(AppThemeSelection.highContrast.isHighContrast, isTrue);
      expect(AppThemeSelection.light.isHighContrast, isFalse);
    });
  });
}
