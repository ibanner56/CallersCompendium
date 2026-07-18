import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/colour_dance_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/colour_dance_theme.dart';

import 'support/test_repositories.dart';

/// Pumps the [SettingsScreen] with the scopes it needs (including the
/// colour-tint easter-egg scope the Appearance toggle mutates) and opens the
/// Appearance section.
Future<ValueNotifier<bool>> _pumpAppearance(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final colourDance = ValueNotifier<bool>(false);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(colourDance.dispose);
  addTearDown(customThemes.dispose);

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
              child: ColourDanceThemeScope(
                notifier: colourDance,
                child: const SettingsScreen(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
  await tester.pumpAndSettle();
  return colourDance;
}

/// Captures the [ColorScheme] a [ColourDanceTheme] resolves for its child under
/// the given conditions, so tests can assert whether the override fired.
Future<ColorScheme> _capturedScheme(
  WidgetTester tester, {
  required bool enabled,
  required bool highContrast,
  String? title,
}) async {
  late ColorScheme captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: AppThemeScope(
        notifier: ValueNotifier<AppThemeSelection>(
          highContrast
              ? AppThemeSelection.highContrast
              : AppThemeSelection.light,
        ),
        child: ReduceMotionScope(
          // Reduce-motion on → instant Theme swap, so no AnimatedTheme frames.
          notifier: ValueNotifier<bool>(true),
          child: ColourDanceThemeScope(
            notifier: ValueNotifier<bool>(enabled),
            child: ColourDanceTheme(
              title: title,
              child: Builder(
                builder: (context) {
                  captured = Theme.of(context).colorScheme;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Appearance colour-tint toggle', () {
    testWidgets('defaults off and persists when enabled', (tester) async {
      final repos = openTestRepositories();
      final colourDance = await _pumpAppearance(tester, repos);

      final toggle = find.byKey(
        const ValueKey('appearance-colour-dance-theme'),
      );
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(toggle, findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isFalse,
        reason: 'the easter egg is opt-in, off by default',
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        await repos.settings.get(kColourDanceThemeKey),
        isTrue,
        reason: 'enabling the toggle persists the preference',
      );
      expect(
        colourDance.value,
        isTrue,
        reason: 'the live scope updates instantly so open dances re-tint',
      );
    });
  });

  group('ColourDanceTheme override', () {
    testWidgets('tints a colour-named dance when enabled and not '
        'high-contrast', (tester) async {
      final base = AppTheme.light.colorScheme;
      final scheme = await _capturedScheme(
        tester,
        enabled: true,
        highContrast: false,
        title: 'Blue Boy',
      );

      final seed = colourSeedForTitle('Blue Boy')!;
      final expected = ColorScheme.fromSeed(
        seedColor: Color(seed),
        brightness: Brightness.light,
      );
      expect(scheme.primary, expected.primary);
      expect(
        scheme.primary,
        isNot(base.primary),
        reason: 'the tint replaces the ambient scheme',
      );
    });

    testWidgets('is suppressed when a high-contrast theme is active', (
      tester,
    ) async {
      final base = AppTheme.light.colorScheme;
      final scheme = await _capturedScheme(
        tester,
        enabled: true,
        highContrast: true,
        title: 'Blue Boy',
      );
      expect(
        scheme.primary,
        base.primary,
        reason: 'high-contrast wins: no colour override',
      );
    });

    testWidgets('does nothing when disabled', (tester) async {
      final base = AppTheme.light.colorScheme;
      final scheme = await _capturedScheme(
        tester,
        enabled: false,
        highContrast: false,
        title: 'Blue Boy',
      );
      expect(scheme.primary, base.primary);
    });

    testWidgets('does nothing for a title with no colour word', (tester) async {
      final base = AppTheme.light.colorScheme;
      final scheme = await _capturedScheme(
        tester,
        enabled: true,
        highContrast: false,
        title: 'Hull Reel',
      );
      expect(scheme.primary, base.primary);
    });
  });
}
