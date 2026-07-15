import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';

/// Pumps the [SettingsScreen] on a wide (side-by-side) surface with the scopes
/// it depends on, backed by [repos], and opens the General section.
Future<void> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
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
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: const SettingsScreen(),
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

CompendiumRepositories _openRepos() => openTestRepositories();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auto-size Perform toggle defaults on and is AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repos = _openRepos();

    await _pumpGeneral(tester, repos);

    final toggle = find.byKey(const ValueKey('settings-auto-size-perform'));
    expect(toggle, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(toggle).value,
      isTrue,
      reason: 'auto-size defaults on (ROADMAP G.1)',
    );
    // The switch is reachable and toggleable by assistive tech.
    expect(
      tester.getSemantics(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      ),
      isSemantics(
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('toggling auto-size off persists the setting', (tester) async {
    final repos = _openRepos();

    await _pumpGeneral(tester, repos);

    await tester.tap(find.byKey(const ValueKey('settings-auto-size-perform')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-size-perform')),
          )
          .value,
      isFalse,
    );
    expect(await repos.settings.get(kAutoSizePerformKey), isFalse);
  });
}
