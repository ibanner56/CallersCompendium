import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Import entry opens the review flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repos = openTestRepositories();
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
    final customThemes = CustomThemesController(repos.settings);
    await customThemes.load();
    addTearDown(dialect.dispose);
    addTearDown(theme.dispose);
    addTearDown(customThemes.dispose);

    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: MaterialApp(
                home: SettingsScreen(
                  importPicker: () async => '{"schemaVersion":1}',
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

    expect(find.byKey(const ValueKey('import-dances-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-dances-button')));
    await tester.pumpAndSettle();

    // The review screen is now on top.
    expect(find.byKey(const ValueKey('import-review-appbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-choose-file')), findsOneWidget);
  });
}
