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

/// Scrolls the Defaults content list until [key] is visible. The
/// Dance-authoring subsection sits below the fold on the test surface.
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    120,
    scrollable: find.byType(Scrollable).last,
  );
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

  testWidgets('Program-defaults subsection renders both fields', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    expect(find.text('Program defaults'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('defaults-program-caller')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('defaults-program-band')), findsOneWidget);
  });

  testWidgets('editing the default caller and band persists them', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('defaults-program-caller')),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.byKey(const ValueKey('defaults-program-band')),
      'The Syncopators',
    );
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kDefaultProgramCallerKey), 'Ada Lovelace');
    expect(await repos.settings.get(kDefaultProgramBandKey), 'The Syncopators');
  });

  testWidgets('saved caller and band defaults reflect on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultProgramCallerKey, 'Grace Hopper');
    await repos.settings.set(kDefaultProgramBandKey, 'The Debuggers');

    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-program-caller')),
          )
          .controller
          ?.text,
      'Grace Hopper',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-program-band')),
          )
          .controller
          ?.text,
      'The Debuggers',
    );
  });

  testWidgets('Dance-authoring subsection renders all four controls', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(find.text('Dance-authoring defaults'), findsOneWidget);
    expect(find.byKey(const ValueKey('defaults-dance-form')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('defaults-dance-formation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-progression')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('defaults-dance-phrase')), findsOneWidget);
  });

  testWidgets('Dance-authoring controls show historical defaults when unset', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(
      tester
          .widget<DropdownButton<DanceForm>>(
            find.byKey(const ValueKey('defaults-dance-form')),
          )
          .value,
      DanceForm.contra,
    );
    expect(
      tester
          .widget<DropdownButton<FormationShape>>(
            find.byKey(const ValueKey('defaults-dance-formation')),
          )
          .value,
      FormationShape.dupleImproper,
    );
    expect(
      tester
          .widget<DropdownButton<Progression>>(
            find.byKey(const ValueKey('defaults-dance-progression')),
          )
          .value,
      Progression.single,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-dance-phrase')),
          )
          .controller
          ?.text,
      '',
    );
  });

  testWidgets('changing each Dance-authoring control persists it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await _scrollTo(tester, const ValueKey('defaults-dance-form'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-form')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-formation'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-formation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Becket (CW)').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-progression'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-progression')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Double').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));
    await tester.enterText(
      find.byKey(const ValueKey('defaults-dance-phrase')),
      '6*8*2',
    );
    await tester.pumpAndSettle();

    expect(
      await repos.settings.get(kDefaultDanceFormKey),
      DanceForm.square.name,
    );
    expect(
      await repos.settings.get(kDefaultDanceFormationShapeKey),
      FormationShape.becketCw.name,
    );
    expect(
      await repos.settings.get(kDefaultDanceProgressionKey),
      Progression.double.name,
    );
    expect(await repos.settings.get(kDefaultDancePhraseStructureKey), '6*8*2');
  });

  testWidgets('saved Dance-authoring defaults reflect on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultDanceFormKey, DanceForm.ecd.name);
    await repos.settings.set(
      kDefaultDanceFormationShapeKey,
      FormationShape.longways.name,
    );
    await repos.settings.set(
      kDefaultDanceProgressionKey,
      Progression.none.name,
    );
    await repos.settings.set(kDefaultDancePhraseStructureKey, '8*8*1');

    await _pumpDefaults(tester, repos);
    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(
      tester
          .widget<DropdownButton<DanceForm>>(
            find.byKey(const ValueKey('defaults-dance-form')),
          )
          .value,
      DanceForm.ecd,
    );
    expect(
      tester
          .widget<DropdownButton<FormationShape>>(
            find.byKey(const ValueKey('defaults-dance-formation')),
          )
          .value,
      FormationShape.longways,
    );
    expect(
      tester
          .widget<DropdownButton<Progression>>(
            find.byKey(const ValueKey('defaults-dance-progression')),
          )
          .value,
      Progression.none,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-dance-phrase')),
          )
          .controller
          ?.text,
      '8*8*1',
    );
  });
}
