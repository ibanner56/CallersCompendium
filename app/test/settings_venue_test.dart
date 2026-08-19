import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/screens/venue_manager_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

Future<ValueNotifier<bool>> _pumpProgram(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool initialMode = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final venueMode = ValueNotifier<bool>(initialMode);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(venueMode.dispose);
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
              child: VenueEntityModeScope(notifier: venueMode, child: child!),
            ),
          ),
        ),
      ),
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-program')));
  await tester.pumpAndSettle();
  return venueMode;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('venue entity mode defaults off and renders the manage row', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpProgram(tester, repos);

    final toggle = find.byKey(const ValueKey('general-venue-entity-mode'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const ValueKey('general-manage-venues')), findsOneWidget);
  });

  testWidgets('toggling venue entity mode persists and flips the notifier', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifier = await _pumpProgram(tester, repos);

    await tester.tap(find.byKey(const ValueKey('general-venue-entity-mode')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('general-venue-entity-mode')),
          )
          .value,
      isTrue,
    );
    expect(notifier.value, isTrue);
    expect(await repos.settings.get(kVenueEntityModeKey), isTrue);
  });

  testWidgets('manage venues row opens the venue manager', (tester) async {
    final repos = openTestRepositories();
    await _pumpProgram(tester, repos);

    await tester.tap(find.byKey(const ValueKey('general-manage-venues')));
    await tester.pumpAndSettle();

    expect(find.byType(VenueManagerScreen), findsOneWidget);
  });
}
