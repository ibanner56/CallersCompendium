import 'dart:async';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/screen_size.dart';
import 'support/test_repositories.dart';

/// Settings ▸ Defaults and the user's own new figures (#1023, maintainer
/// decision 13): the default figure lists offer them, and Move defaults links
/// to each one's own defaults.
void main() {
  UserGlossaryEntry figure(String id, String name, {String form = 'contra'}) =>
      UserGlossaryEntry(
        id: id,
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: name,
        definition: 'A figure.',
        description: 'Of your own.',
        payload: {
          'form': form,
          'template': '{who} {move}',
          'defaultBeats': 6,
          'params': const [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'role1s'},
          ],
        },
        createdAt: DateTime.utc(2026, 10, 16),
      );

  Future<CompendiumRepositories> pump(
    WidgetTester tester, {
    bool customFigures = true,
    List<Figure>? startingFigures,
    DanceForm? form,
  }) async {
    await setScreenSize(tester, const Size(1200, 6000));
    final repos = openTestRepositories();
    await tester.runAsync(() async {
      await repos.userGlossary.upsert(figure('zoom-id', 'zoom'));
      await repos.userGlossary.upsert(figure('jig-id', 'jiggle', form: 'ecd'));
      if (form != null) {
        await repos.settings.set(kDefaultDanceFormKey, form.name);
      }
      if (startingFigures != null) {
        await repos.settings.set(
          kDefaultDanceFiguresTemplateKey,
          encodeFigures(startingFigures),
        );
      }
    });
    final userFigures = UserFiguresController(repos.userGlossary);
    addTearDown(userFigures.dispose);
    unawaited(userFigures.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
    final customThemes = CustomThemesController(repos.settings);
    final aggressive = ValueNotifier<bool>(false);
    final shorthands = ShorthandMappingsController(repos.settings);
    final snippets = WalkthroughSnippetLibraryController(repos.settings);
    final facets = ValueNotifier<Set<String>>(const {});
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(customFigures);
    for (final n in <ChangeNotifier>[
      dialect,
      theme,
      customThemes,
      aggressive,
      shorthands,
      snippets,
      facets,
      glossary,
      custom,
    ]) {
      addTearDown(n.dispose);
    }
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
                child: AggressiveBeatsUpdateScope(
                  notifier: aggressive,
                  child: ShorthandMappingsScope(
                    controller: shorthands,
                    child: WalkthroughSnippetLibraryScope(
                      controller: snippets,
                      child: CollectionFacetsScope(
                        notifier: facets,
                        child: ShowGlossaryScope(
                          notifier: glossary,
                          child: ShowCustomFiguresScope(
                            notifier: custom,
                            child: UserFiguresScope(
                              controller: userFigures,
                              child: child!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-defaults')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('defaults-authoring-group')),
    );
    await tester.tap(find.byKey(const ValueKey('defaults-authoring-group')));
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> typeFirstMove(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.byKey(const ValueKey('figure-0-summary')));
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      text,
    );
    await tester.pumpAndSettle();
  }

  const zoomOption = ValueKey('figure-0-move-option-userFigure:zoom-id');

  testWidgets('a starting figure can be one of your figures for the default '
      'form, and is stored as a use of it', (tester) async {
    final repos = await pump(tester);
    await typeFirstMove(tester, 'zoo');
    expect(find.byKey(zoomOption), findsOneWidget);
    await tester.tap(find.byKey(zoomOption));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final stored = await tester.runAsync(
      () => repos.settings.get(kDefaultDanceFiguresTemplateKey),
    );
    final first = danceFiguresTemplateFromStored(stored).first;
    final use = userFigureUseOf(first);
    expect(use?.id, 'zoom-id');
    expect(use?.attached, isTrue);
    expect(first.params['text'], 'role1s zoom');
  });

  testWidgets('the meanwhile and modifier lists offer your figures too', (
    tester,
  ) async {
    await pump(tester);
    for (final list in ['figure', 'meanwhile-side', 'modifier-default']) {
      final editor = tester.widget<FigureListEditor>(
        find.byWidgetPredicate(
          (w) => w is FigureListEditor && w.keyPrefix == list,
        ),
      );
      expect(editor.userFigureOptions?.map((e) => e.id), [
        'zoom-id',
      ], reason: list);
    }
  });

  testWidgets('a figure for another form is not offered', (tester) async {
    await pump(tester);
    await typeFirstMove(tester, 'jig');
    expect(
      find.byKey(const ValueKey('figure-0-move-option-userFigure:jig-id')),
      findsNothing,
    );
  });

  testWidgets('with English dance the default form, its figures are offered '
      'instead', (tester) async {
    await pump(tester, form: DanceForm.ecd);
    await typeFirstMove(tester, 'jig');
    expect(
      find.byKey(const ValueKey('figure-0-move-option-userFigure:jig-id')),
      findsOneWidget,
    );
  });

  testWidgets('your figures are not offered while Custom Figures is off', (
    tester,
  ) async {
    await pump(tester, customFigures: false);
    await typeFirstMove(tester, 'zoo');
    expect(find.byKey(zoomOption), findsNothing);
    expect(
      find.byKey(const ValueKey('defaults-user-figure-zoom-id')),
      findsNothing,
    );
  });

  testWidgets('Move defaults links to each of your figures\' own defaults', (
    tester,
  ) async {
    await pump(tester);
    final link = find.byKey(const ValueKey('defaults-user-figure-zoom-id'));
    await tester.ensureVisible(link);
    expect(
      find.byKey(const ValueKey('defaults-user-figure-jig-id')),
      findsOneWidget,
      reason: 'every form\'s figures are linked: their defaults are theirs',
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
  });

  testWidgets('a figure deleted while Defaults is open is plain text in its '
      'lists, so the next edit there does not store a use of it', (
    tester,
  ) async {
    final repos = await pump(
      tester,
      startingFigures: [
        userFigureUseFigure(
          id: 'zoom-id',
          args: const {'who': 'role2s'},
          text: 'a stale line',
        ),
      ],
    );
    Figure first() => tester
        .widget<FigureListEditor>(
          find.byWidgetPredicate(
            (w) => w is FigureListEditor && w.keyPrefix == 'figure',
          ),
        )
        .drafts
        .first
        .toFigure()!;
    expect(userFigureUseOf(first())?.attached, isTrue);
    expect(
      first().params['text'],
      'role2s zoom',
      reason: 'a use reads as the figure renders it now',
    );
    await tester.runAsync(() => repos.deleteUserFigure('zoom-id'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(userFigureUseOf(first())?.attached ?? false, isFalse);
    expect(first().params['text'], 'role2s zoom');
  });
}
