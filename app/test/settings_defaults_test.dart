import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/search/collection_query.dart';

import 'support/test_repositories.dart';

/// Pumps the settings screen on a wide surface backed by [repos] and opens the
/// Defaults section.
Future<void> _pumpDefaults(
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

  await tester.tap(find.byKey(const ValueKey('settings-nav-defaults')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Defaults appears as a settings section', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    // Both Display-defaults controls render.
    expect(
      find.byKey(const ValueKey('defaults-collection-sort')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-detail-canonical')),
      findsOneWidget,
    );
  });

  testWidgets('Display defaults show the historical defaults when unset', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<CollectionSort>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      CollectionSort.title,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('defaults-dance-detail-canonical')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('changing the default sort persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await tester.tap(find.byKey(const ValueKey('defaults-collection-sort')));
    await tester.pumpAndSettle();
    // Pick "Author" from the opened dropdown menu (last matches the menu item).
    await tester.tap(find.text('Author').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<CollectionSort>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      CollectionSort.author,
    );
    expect(
      await repos.settings.get(kDefaultCollectionSortKey),
      CollectionSort.author.name,
    );
  });

  testWidgets('toggling canonical default persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('defaults-dance-detail-canonical')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('defaults-dance-detail-canonical')),
          )
          .value,
      isTrue,
    );
    expect(
      await repos.settings.get(kDefaultDanceDetailRenderingKey),
      DanceDetailRendering.canonical.name,
    );
  });

  testWidgets('a saved default sort is reflected on reload', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultCollectionSortKey,
      CollectionSort.lastCalled.name,
    );

    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<CollectionSort>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      CollectionSort.lastCalled,
    );
  });

  testWidgets('both saved Display defaults reflect independently on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultCollectionSortKey,
      CollectionSort.author.name,
    );
    await repos.settings.set(
      kDefaultDanceDetailRenderingKey,
      DanceDetailRendering.canonical.name,
    );

    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<CollectionSort>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      CollectionSort.author,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('defaults-dance-detail-canonical')),
          )
          .value,
      isTrue,
    );
  });
}
