import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/app_metadata.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/licenses.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';

/// Pumps the [SettingsScreen] with the scopes it needs and opens the About
/// section. [surfaceSize] chooses the wide (side-by-side) or narrow (detail
/// route) layout so the same section can be exercised on both.
Future<CompendiumRepositories> _pumpAbout(
  WidgetTester tester, {
  // Tall by default so the whole (lazily-built) About list renders without
  // scrolling — matching the convention in settings_screen_test.dart.
  Size surfaceSize = const Size(1000, 2600),
}) async {
  final repos = openTestRepositories();

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
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

  await tester.tap(find.byKey(const ValueKey('settings-nav-about')));
  await tester.pumpAndSettle();
  return repos;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Each test drives the global LicenseRegistry, so start from a clean slate
    // and let the once-guarded registration run fresh.
    LicenseRegistry.reset();
    resetBundledFontLicensesForTest();
  });

  testWidgets('About section shows license, source, and attributions (wide)', (
    tester,
  ) async {
    await _pumpAbout(tester);

    // App identity.
    expect(find.byKey(const ValueKey('about-app-version')), findsOneWidget);
    expect(find.text(kAppName), findsWidgets);
    expect(find.text('Version $kAppVersion'), findsOneWidget);

    // AGPL-3.0 license notice + source offer and link.
    expect(find.textContaining('AGPL-3.0'), findsWidgets);
    expect(
      find.textContaining('Affero General Public License'),
      findsOneWidget,
    );
    final sourceLink = find.byKey(const ValueKey('about-source-link'));
    expect(sourceLink, findsOneWidget);
    expect(find.text(kSourceRepoUrl), findsOneWidget);

    // Font attributions (all three bundled fonts, OFL).
    expect(find.text('Fraunces'), findsOneWidget);
    expect(find.text('Atkinson Hyperlegible'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);
    expect(find.textContaining('SIL Open Font License 1.1'), findsWidgets);

    // Theme "inspired by" note and dance-data provenance (TCB, CC BY-NC).
    expect(find.textContaining('code-editor palettes'), findsOneWidget);
    expect(find.textContaining('The Caller’s Box'), findsOneWidget);
    expect(find.textContaining('CC BY-NC'), findsOneWidget);

    // The View-licenses entry is present.
    expect(find.byKey(const ValueKey('about-view-licenses')), findsOneWidget);
  });

  testWidgets('About section is reachable and renders on a narrow layout', (
    tester,
  ) async {
    await _pumpAbout(tester, surfaceSize: const Size(420, 2600));

    // The detail route shows the same compliance content.
    expect(find.text(kAppName), findsWidgets);
    expect(
      find.textContaining('Affero General Public License'),
      findsOneWidget,
    );
    expect(find.text('Fraunces'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-view-licenses')), findsOneWidget);
  });

  testWidgets(
    'View licenses opens showLicensePage including a bundled font license',
    (tester) async {
      // Register the bundled font licenses so the license page lists them.
      registerBundledFontLicenses();

      await _pumpAbout(tester, surfaceSize: const Size(500, 2600));

      await tester.tap(find.byKey(const ValueKey('about-view-licenses')));
      await tester.pumpAndSettle();

      // Flutter's license page is shown...
      expect(find.byType(LicensePage), findsOneWidget);
      // ...and it enumerates the bundled Roboto (OFL) license we registered,
      // proving LicenseRegistry wiring reached showLicensePage.
      expect(find.text('Roboto (OFL 1.1)'), findsOneWidget);
    },
  );
}
