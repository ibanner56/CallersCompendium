import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_filter_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';
import '../support/test_repositories.dart';

/// The real fonts, so widths measured here are the app's, not the test font's
/// (whose every glyph is a full em wide and would wrap the chips regardless).
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Fraunces', ['assets/fonts/Fraunces-VariableFont.ttf']);
  await load('AtkinsonHyperlegible', [
    'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
    'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
  ]);
  await load('Roboto', ['assets/fonts/Roboto-VariableFont.ttf']);
}

/// The Collection on a 390×844 phone, with two dances so every search tool is
/// offered.
Future<void> _pump(
  WidgetTester tester, {
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  await setScreenSize(tester, const Size(390, 844));
  final repos = openTestRepositories();
  final stamp = DateTime.utc(2026, 1, 1);
  for (final (id, title) in [('d1', 'Petronella'), ('d2', 'Chorus Jig')]) {
    await repos.dances.create(
      Dance(id: id, title: title, createdAt: stamp, updatedAt: stamp),
    );
  }
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.light);
  addTearDown(theme.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  final sortIgnore = ValueNotifier<bool>(true);
  addTearDown(sortIgnore.dispose);
  final filters = CollectionFilterController();
  addTearDown(filters.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepositoriesScope(
          repositories: repos,
          child: AppThemeScope(
            notifier: theme,
            child: CustomThemesScope(
              controller: customThemes,
              child: ActiveDialectScope(
                notifier: dialect,
                child: SortIgnoreArticlesScope(
                  notifier: sortIgnore,
                  child: CollectionFilterScope(
                    controller: filters,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      home: const DanceListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key))).top;

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('on a phone, Search in sits beside the search box and the '
      'three search tools share one row', (tester) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(
      _top(tester, 'collection-search-scope'),
      _top(tester, 'collection-search-field'),
    );
    final toolsTop = _top(tester, 'filters-panel');
    expect(_top(tester, 'by-phrase-panel'), toolsTop);
    expect(_top(tester, 'advanced-panel'), toolsTop);
  });

  testWidgets('the results start high on a phone screen', (tester) async {
    await _pump(tester);

    // Above the first dance there were Search in, the search box and three
    // stacked panel headers: the "2 dances" count sat at 358dp on this 844dp
    // screen. One search row and one row of tools put it at 188dp.
    expect(tester.getRect(find.text('2 dances')).top, lessThan(240));
  });

  testWidgets('at large text Search in stacks above the search box again', (
    tester,
  ) async {
    await _pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(
      _top(tester, 'collection-search-scope'),
      lessThan(_top(tester, 'collection-search-field')),
    );
  });

  testWidgets('the search field keeps focus when the header switches between '
      'one row and two', (tester) async {
    await _pump(tester);
    final field = find.byKey(const ValueKey('collection-search-field'));
    await tester.tap(field);
    await tester.enterText(field, 'pet');
    await tester.pumpAndSettle();
    expect(
      _top(tester, 'collection-search-scope'),
      _top(tester, 'collection-search-field'),
    );

    // Narrow enough that the header stacks, as a rotation or resize can.
    await setScreenSize(tester, const Size(290, 844));
    await tester.pumpAndSettle();

    expect(
      _top(tester, 'collection-search-scope'),
      lessThan(_top(tester, 'collection-search-field')),
    );
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'pet');
  });

  testWidgets('German labels fit without overflow', (tester) async {
    await _pump(tester, locale: const Locale('de'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('advanced-panel')), findsOneWidget);
  });
}
