import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';

/// Pumps the [SettingsScreen] with the accessibility scopes wired (seeded from
/// the persisted keys) and opens the General section.
Future<void> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  final reduceMotion = ValueNotifier<bool>(
    await repos.settings.get(kReduceMotionKey) == true,
  );
  final verboseFigures = ValueNotifier<bool>(
    await repos.settings.get(kVerboseFigureRenderingKey) == true,
  );
  final confirmDelete = ValueNotifier<bool>(
    await repos.settings.get(kConfirmBeforeDeleteKey) == true,
  );
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(reduceMotion.dispose);
  addTearDown(verboseFigures.dispose);
  addTearDown(confirmDelete.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: ReduceMotionScope(
                notifier: reduceMotion,
                child: VerboseFigureRenderingScope(
                  notifier: verboseFigures,
                  child: ConfirmBeforeDeleteScope(
                    notifier: confirmDelete,
                    child: const SettingsScreen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keys = {
    'general-reduce-motion': kReduceMotionKey,
    'general-verbose-figures': kVerboseFigureRenderingKey,
    'general-confirm-before-delete': kConfirmBeforeDeleteKey,
  };

  testWidgets('all three accessibility switches render and default off', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos);

    for (final widgetKey in keys.keys) {
      final finder = find.byKey(ValueKey(widgetKey));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(finder, findsOneWidget, reason: '$widgetKey should render');
      expect(
        _switchValue(tester, widgetKey),
        isFalse,
        reason: '$widgetKey defaults off',
      );
    }
  });

  keys.forEach((widgetKey, settingsKey) {
    testWidgets('toggling $widgetKey persists $settingsKey', (tester) async {
      final repos = openTestRepositories();
      await _pumpGeneral(tester, repos);

      final finder = find.byKey(ValueKey(widgetKey));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(_switchValue(tester, widgetKey), isTrue);
      expect(await repos.settings.get(settingsKey), isTrue);
    });

    testWidgets('$widgetKey reflects the persisted value on reload', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(settingsKey, true);

      await _pumpGeneral(tester, repos);

      final finder = find.byKey(ValueKey(widgetKey));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(_switchValue(tester, widgetKey), isTrue);
    });
  });
}
