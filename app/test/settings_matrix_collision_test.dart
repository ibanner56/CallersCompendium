import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/matrix_collision_mode_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

/// Pumps the [SettingsScreen] (General is opened explicitly) with the scopes
/// it depends on, including a [MatrixCollisionModeScope] seeded from
/// [initialExactBeatCollision] (issue #962).
Future<ValueNotifier<bool>> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool initialExactBeatCollision = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final exactBeatCollision = ValueNotifier<bool>(initialExactBeatCollision);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(exactBeatCollision.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: MatrixCollisionModeScope(
                notifier: exactBeatCollision,
                child: child!,
              ),
            ),
          ),
        ),
      ),
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  return exactBeatCollision;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('matrix exact-beat-collision toggle defaults on', (tester) async {
    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos);

    final toggle = find.byKey(
      const ValueKey('general-matrix-exact-beat-collision'),
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('reflects an initial off value from the scope', (tester) async {
    final repos = openTestRepositories();
    await _pumpGeneral(tester, repos, initialExactBeatCollision: false);

    final toggle = find.byKey(
      const ValueKey('general-matrix-exact-beat-collision'),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('toggling it off persists and flips the notifier (#962)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifier = await _pumpGeneral(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('general-matrix-exact-beat-collision')),
          )
          .value,
      isFalse,
    );
    expect(notifier.value, isFalse);
    expect(await repos.settings.get(kMatrixExactBeatCollisionKey), isFalse);
  });
}
