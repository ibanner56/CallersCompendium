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
import 'support/l10n_harness.dart';

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
      'Folk Process',
    );
    await tester.enterText(
      find.byKey(const ValueKey('defaults-program-band')),
      'The Syncopators',
    );
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kDefaultProgramCallerKey), 'Folk Process');
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
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();

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
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();

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
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();
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

  testWidgets('Starting-figures editor renders with the default template', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();

    expect(find.text('Starting figures'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-add')), findsOneWidget);
    // The pre-seeded default is eight stand_still figures.
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('figure-$i-summary')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('figure-8-summary')), findsNothing);
  });

  testWidgets('editing the template figure persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();

    final stored = danceFiguresTemplateFromStored(
      await repos.settings.get(kDefaultDanceFiguresTemplateKey),
    );
    // The editor persists the full edited list: eight figures, the first with
    // the edited beats (16) and the remaining seven at the default (8).
    expect(stored, hasLength(8));
    expect(stored.first.move, 'stand_still');
    expect(stored.first.params['beats'], 16);
    for (final figure in stored.skip(1)) {
      expect(figure.move, 'stand_still');
      expect(figure.params['beats'], 8);
    }
  });

  testWidgets(
    'deleting template figures persists the shortened/empty template',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 3000));
      await tester.pumpAndSettle();

      // Delete one of the eight seeded figures: the shortened list persists.
      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
      await tester.pumpAndSettle();

      final afterOne = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      expect(afterOne, hasLength(7));

      // Delete the remaining seven (indices shift down, so always target 0).
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
        await tester.pumpAndSettle();
      }

      // An emptied template persists as an intentional '[]', not the default.
      expect(await repos.settings.get(kDefaultDanceFiguresTemplateKey), '[]');
      expect(find.byKey(const ValueKey('figure-0-summary')), findsNothing);
    },
  );

  testWidgets('a saved multi-figure template reflects on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures([
        Figure(move: 'balance', params: const {'who': 'neighbors', 'beats': 4}),
        Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 12}),
      ]),
    );
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-2-summary')), findsNothing);
  });

  testWidgets(
    'duplicating a template figure preserves the assumed-subject marker (#460)',
    (tester) async {
      final repos = openTestRepositories();
      // Seed a template whose single figure carries the non-authoritative
      // assumed-subject marker (as an import would produce).
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([
          Figure(
            move: 'allemande',
            params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
            assumedSubject: true,
          ),
        ]),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 3000));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-0-duplicate')));
      await tester.pumpAndSettle();

      final stored = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      // The clone is inserted after the source and the persisted template keeps
      // the marker on BOTH figures (the #460 regression dropped it on the copy).
      expect(stored, hasLength(2));
      expect(stored.every((f) => f.move == 'allemande'), isTrue);
      expect(stored.every((f) => f.assumedSubject), isTrue);
    },
  );

  group('Move defaults (DD.3)', () {
    testWidgets('editor renders with an add affordance', (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      expect(find.text('Move defaults'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-defaults-add')), findsOneWidget);
    });

    testWidgets('adding a move and setting a param persists an override', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('move-defaults-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('move-defaults-add-picker-input')),
        'circle',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('move-defaults-add-picker-option-circle')),
      );
      await tester.pumpAndSettle();

      // The move card renders; change its beats away from the default (8).
      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('move-default-circle-beats')),
        '12',
      );
      await tester.pumpAndSettle();

      final stored = moveParamOverridesFromStored(
        await repos.settings.get(kDefaultMoveParamOverridesKey),
      );
      expect(stored, {
        'circle': {'beats': 12},
      });
    });

    testWidgets('resetting a param to its default drops it from storage', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'circle': {'beats': 12},
        }),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      // The saved override renders its card on reload; reset beats to 8.
      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('move-default-circle-beats')),
        '8',
      );
      await tester.pumpAndSettle();

      expect(
        moveParamOverridesFromStored(
          await repos.settings.get(kDefaultMoveParamOverridesKey),
        ),
        isEmpty,
      );
    });

    testWidgets('removing a move override persists and hides its card', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'circle': {'beats': 12},
        }),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('move-default-remove-circle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsNothing,
      );
      expect(
        moveParamOverridesFromStored(
          await repos.settings.get(kDefaultMoveParamOverridesKey),
        ),
        isEmpty,
      );
    });
  });

  group('Free-text entry toggle (#419)', () {
    const toggleKey = ValueKey('defaults-free-text-entry');

    testWidgets('renders in the Dance-authoring section, off by default', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      expect(find.text('Free-text entry'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isFalse,
      );
    });

    testWidgets('toggling it on persists the preference', (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isTrue,
      );
      expect(await repos.settings.get(kFreeTextEntryKey), isTrue);
    });

    testWidgets('a saved preference reflects on reload', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(kFreeTextEntryKey, true);

      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isTrue,
      );
    });

    testWidgets('when on, the template editor Add opens a free-text field', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kFreeTextEntryKey, true);
      // Start from an empty template so the Add button is unambiguous.
      await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');

      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 3000));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('figure-free-text-field')),
        findsOneWidget,
      );

      // Typing a recognised line inserts a structured figure into the template.
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
    });
  });
}
