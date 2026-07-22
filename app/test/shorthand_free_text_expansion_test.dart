import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

Figure _swing() =>
    Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 16});

/// Pumps the Settings screen with the shorthand scope in place (mirrors
/// `settings_defaults_test` but adds [ShorthandMappingsScope]) and opens the
/// Defaults section, so the template figure editor's free-text field routes
/// through the shorthand-aware entry path.
Future<void> _pumpDefaultsWithShorthands(
  WidgetTester tester,
  CompendiumRepositories repos,
  ShorthandMappingsController shorthands,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: ShorthandMappingsScope(
                controller: shorthands,
                child: const SettingsScreen(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-defaults')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a shorthand expands in the template editor free-text field', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kFreeTextEntryKey, true);
    await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');

    final shorthands = ShorthandMappingsController(repos.settings);
    addTearDown(shorthands.dispose);
    await shorthands.upsert(ShorthandMapping(token: 'ns', figures: [_swing()]));

    await _pumpDefaultsWithShorthands(tester, repos, shorthands);

    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();

    // Typing the shorthand token (any casing) expands to the mapped figure,
    // NOT a custom figure from the free-text parser.
    await tester.enterText(
      find.byKey(const ValueKey('figure-free-text-field')),
      'NS',
    );
    await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
    await tester.pumpAndSettle();

    final stored = danceFiguresTemplateFromStored(
      await repos.settings.get(kDefaultDanceFiguresTemplateKey),
    );
    expect(stored, hasLength(1));
    expect(stored.single.move, 'swing');
    expect(stored.single.params['who'], 'neighbors');
  });

  testWidgets(
    'a non-matching line still falls through to the free-text parser',
    (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(kFreeTextEntryKey, true);
      await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');

      final shorthands = ShorthandMappingsController(repos.settings);
      addTearDown(shorthands.dispose);
      await shorthands.upsert(
        ShorthandMapping(token: 'ns', figures: [_swing()]),
      );

      await _pumpDefaultsWithShorthands(tester, repos, shorthands);

      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('figure-free-text-field')),
        'Neighbor swing',
      );
      await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
      await tester.pumpAndSettle();

      final stored = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      expect(stored, hasLength(1));
      expect(stored.single.move, 'swing');
    },
  );
}
