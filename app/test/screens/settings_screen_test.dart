import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
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
    CustomThemesController customThemes,
  })
>
_pumpSettings(
  WidgetTester tester, {
  Dialect? initialDialect,
  AppThemeSelection? initialTheme,
  Size surfaceSize = const Size(1000, 2600),
}) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();

  final notifier = ValueNotifier<Dialect>(
    initialDialect ?? Dialect.larksRobins,
  );
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    initialTheme ?? AppThemeSelection.system,
  );
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(notifier.dispose);
  addTearDown(themeNotifier.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
        ),
      ),
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return (
    repos: repos,
    notifier: notifier,
    themeNotifier: themeNotifier,
    customThemes: customThemes,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen — dialect selection', () {
    // In the side-by-side layout only the selected section's content is shown,
    // so dialect tests must first select the Dialect section.
    Future<void> openDialect(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();
    }

    testWidgets('renders all preset names', (tester) async {
      await _pumpSettings(tester);
      await openDialect(tester);

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
      await openDialect(tester);

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
      await openDialect(tester);

      // Tap the Gents/Ladies radio tile.
      final tile = find.byKey(ValueKey('dialect-${Dialect.gentsLadies.name}'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
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
      await openDialect(tester);

      final tile = find.byKey(ValueKey('dialect-${Dialect.leadsFollows.name}'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
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
    testWidgets('renders a preview card for every theme option', (
      tester,
    ) async {
      await _pumpSettings(tester);

      for (final option in AppThemeSelection.values) {
        final card = find.byKey(ValueKey('theme-${option.name}'));
        expect(
          card,
          findsOneWidget,
          reason: 'Expected preview card for ${option.name}',
        );
        // The option's label is shown inside its own card.
        expect(
          find.descendant(of: card, matching: find.text(option.label)),
          findsOneWidget,
          reason: 'Expected label inside card for ${option.name}',
        );
      }
    });

    testWidgets('the active option shows a non-color-only selected state', (
      tester,
    ) async {
      await _pumpSettings(tester, initialTheme: AppThemeSelection.dark);

      // Selection must not rely on color alone: the active card also renders a
      // check icon and a "Selected" label.
      final selectedCard = find.byKey(
        ValueKey('theme-${AppThemeSelection.dark.name}'),
      );
      expect(
        find.descendant(
          of: selectedCard,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: selectedCard, matching: find.text('Selected')),
        findsOneWidget,
      );

      // And an unselected card shows neither.
      final otherCard = find.byKey(
        ValueKey('theme-${AppThemeSelection.light.name}'),
      );
      expect(
        find.descendant(
          of: otherCard,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );
    });

    testWidgets('selecting a theme updates the notifier live', (tester) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      final card = find.byKey(
        ValueKey('theme-${AppThemeSelection.highContrast.name}'),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
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

      final card = find.byKey(ValueKey('theme-${AppThemeSelection.dark.name}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
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
      // Gallery palettes follow their pinned scheme's brightness.
      expect(AppThemeSelection.solarizedLight.themeMode, ThemeMode.light);
      expect(AppThemeSelection.monokai.themeMode, ThemeMode.dark);
    });

    test('inGroup lists each group alphabetically by label', () {
      for (final group in AppThemeGroup.values) {
        final labels = AppThemeSelection.inGroup(
          group,
        ).map((s) => s.label).toList();
        final sorted = [...labels]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(
          labels,
          equals(sorted),
          reason: '${group.label} group should be alphabetical',
        );
      }
      // Sanity: the Default group orders as Dark, High contrast, Light.
      expect(
        AppThemeSelection.inGroup(
          AppThemeGroup.defaultHearth,
        ).map((s) => s.label),
        equals(['Dark', 'High contrast', 'Light']),
      );
    });

    test('gallery grouping and brightness resolvers are correct', () {
      expect(AppThemeSelection.system.group, AppThemeGroup.system);
      expect(AppThemeSelection.light.group, AppThemeGroup.defaultHearth);
      expect(AppThemeSelection.highContrast.group, AppThemeGroup.defaultHearth);
      expect(AppThemeSelection.solarizedLight.group, AppThemeGroup.light);
      expect(AppThemeSelection.solarizedDark.group, AppThemeGroup.dark);
      expect(AppThemeSelection.monokai.brightness, Brightness.dark);
      expect(AppThemeSelection.noctisLux.brightness, Brightness.light);
    });

    testWidgets('selecting a gallery palette persists and updates live', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.system,
      );

      final card = find.byKey(
        ValueKey('theme-${AppThemeSelection.monokai.name}'),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(ctx.themeNotifier.value, equals(AppThemeSelection.monokai));
      final stored = await ctx.repos.settings.get(kAppThemeKey) as String?;
      expect(stored, equals(AppThemeSelection.monokai.name));
    });

    testWidgets('gallery renders labeled group headings', (tester) async {
      await _pumpSettings(tester);
      for (final group in AppThemeGroup.values) {
        expect(
          find.text(group.label),
          findsWidgets,
          reason: 'Expected a "${group.label}" section heading',
        );
      }
    });
  });

  group('SettingsScreen — custom themes', () {
    // The Appearance list scrolls (the theme gallery grew), so the custom
    // themes section can sit below the fold. Scroll the content list — located
    // via the always-built gallery — until [target] is on screen.
    Future<void> revealInAppearance(WidgetTester tester, Finder target) async {
      final scrollable = find
          .ancestor(
            of: find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    testWidgets('shows an empty-state hint and a New custom theme button', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await revealInAppearance(
        tester,
        find.byKey(const ValueKey('new-custom-theme')),
      );
      expect(find.byKey(const ValueKey('new-custom-theme')), findsOneWidget);
      expect(find.textContaining('saved on this device'), findsOneWidget);
    });

    testWidgets('renders a card for each saved custom theme', (tester) async {
      final ctx = await _pumpSettings(tester);
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.dark,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.dark()),
      );
      await tester.pumpAndSettle();
      await revealInAppearance(
        tester,
        find.byKey(ValueKey('custom-${created.id}')),
      );

      expect(find.byKey(ValueKey('custom-${created.id}')), findsOneWidget);
      expect(find.text('Test Theme'), findsOneWidget);
    });

    testWidgets('selecting a custom card activates it and clears built-in', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialTheme: AppThemeSelection.monokai,
      );
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.light,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.light()),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(ValueKey('custom-${created.id}'));
      await revealInAppearance(tester, card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(ctx.customThemes.hasActive, isTrue);
      expect(ctx.customThemes.activeId, created.id);
      final storedActive =
          await ctx.repos.settings.get('active_custom_theme') as String?;
      expect(storedActive, created.id);
    });

    testWidgets('selecting a built-in theme clears the active custom theme', (
      tester,
    ) async {
      final ctx = await _pumpSettings(tester);
      final created = await ctx.customThemes.duplicate(
        name: 'Test Theme',
        brightness: Brightness.dark,
        roles: CustomTheme.rolesFromScheme(const ColorScheme.dark()),
      );
      await ctx.customThemes.setActive(created.id);
      await tester.pumpAndSettle();
      expect(ctx.customThemes.hasActive, isTrue);

      final builtIn = find.byKey(
        ValueKey('theme-${AppThemeSelection.monokai.name}'),
      );
      await tester.ensureVisible(builtIn);
      await tester.tap(builtIn);
      await tester.pumpAndSettle();

      expect(ctx.customThemes.hasActive, isFalse);
      expect(ctx.themeNotifier.value, AppThemeSelection.monokai);
    });
  });

  group('SettingsScreen — section navigation', () {
    testWidgets('sidebar renders a nav item for every section', (tester) async {
      await _pumpSettings(tester);
      expect(
        find.byKey(const ValueKey('settings-nav-appearance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-dialect')),
        findsOneWidget,
      );
    });

    testWidgets('appearance is shown by default and dialect is hidden', (
      tester,
    ) async {
      await _pumpSettings(tester);
      // Appearance content: the theme gallery is present.
      expect(
        find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
        findsOneWidget,
      );
      // Dialect content is not mounted until its section is selected.
      expect(
        find.byKey(ValueKey('dialect-${Dialect.larksRobins.name}')),
        findsNothing,
      );
    });

    testWidgets('selecting Dialect swaps the content pane', (tester) async {
      await _pumpSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();

      // Now dialect tiles are shown and the theme gallery is gone.
      expect(
        find.byKey(ValueKey('dialect-${Dialect.larksRobins.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('theme-${AppThemeSelection.system.name}')),
        findsNothing,
      );
    });

    testWidgets('narrow layout pushes a detail page that updates live', (
      tester,
    ) async {
      final ctx = await _pumpSettings(
        tester,
        initialDialect: Dialect.larksRobins,
        surfaceSize: const Size(500, 900),
      );

      // Narrow layout: tapping a nav row pushes the section as its own page.
      await tester.tap(find.byKey(const ValueKey('settings-nav-dialect')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('dialect-${Dialect.gentsLadies.name}')),
        findsOneWidget,
      );

      // Selecting a dialect on the pushed page must update it live (the route
      // depends on ActiveDialectScope, so the notifier change rebuilds it).
      await tester.tap(
        find.byKey(ValueKey('dialect-${Dialect.gentsLadies.name}')),
      );
      await tester.pumpAndSettle();
      expect(ctx.notifier.value, Dialect.gentsLadies);

      final group = tester.widget<RadioGroup<Dialect>>(
        find.byType(RadioGroup<Dialect>),
      );
      expect(group.groupValue, Dialect.gentsLadies);
    });
  });
}
