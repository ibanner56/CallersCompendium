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

/// The Collection on a 390×844 phone (or [size]), with two dances so every
/// search tool is offered, and [extraDances] more to give the list length.
Future<void> _pump(
  WidgetTester tester, {
  double textScale = 1,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  int extraDances = 0,
}) async {
  await setScreenSize(tester, size);
  final repos = openTestRepositories();
  final stamp = DateTime.utc(2026, 1, 1);
  for (final (id, title) in [
    ('d1', 'Petronella'),
    ('d2', 'Chorus Jig'),
    for (var i = 0; i < extraDances; i++)
      ('x$i', 'Zesty Reel ${i.toString().padLeft(2, '0')}'),
  ]) {
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

/// The Saved menu (#2325) and the Online search icon sit side by side, Saved
/// first, inside the screen, and come after the three tools: in their row
/// when it has room ([inToolsRow]), else together on the line under it.
///
/// On a 390dp phone the row has no room: the three tools take 282dp of the
/// 358dp inside the margins (304dp with "Filters · 3"), and the two compact
/// icons need 80dp. So there they always take the second line, whether or not
/// a filter is set, and the row never jumps as the first filter is chosen.
void _expectTrailingIcons(WidgetTester tester, {required bool inToolsRow}) {
  final saved = tester.getRect(find.byKey(const ValueKey('saved-search-menu')));
  final online = tester.getRect(
    find.byKey(const ValueKey('online-search-enable')),
  );
  final advanced = tester.getRect(find.byKey(const ValueKey('advanced-panel')));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  expect(saved.center.dy, closeTo(online.center.dy, 1));
  expect(online.left, greaterThanOrEqualTo(saved.right));
  expect(online.right, lessThanOrEqualTo(width));
  if (inToolsRow) {
    expect(saved.center.dy, closeTo(advanced.center.dy, 1));
    expect(saved.left, greaterThanOrEqualTo(advanced.right));
  } else {
    expect(saved.top, greaterThanOrEqualTo(advanced.bottom));
    expect(saved.top, lessThan(advanced.bottom + 8));
  }
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('on a phone, Search in sits beside the search box, the '
      'three search tools share one row, and the Saved and Online search '
      'icons sit together under it', (tester) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(
      _top(tester, 'collection-search-scope'),
      _top(tester, 'collection-search-field'),
    );
    final toolsTop = _top(tester, 'filters-panel');
    expect(_top(tester, 'by-phrase-panel'), toolsTop);
    expect(_top(tester, 'advanced-panel'), toolsTop);
    _expectTrailingIcons(tester, inToolsRow: false);
  });

  testWidgets('on a wider screen the Saved and Online search icons end the '
      'row of tools', (tester) async {
    await _pump(tester, size: const Size(600, 844));

    expect(tester.takeException(), isNull);
    _expectTrailingIcons(tester, inToolsRow: true);
  });

  testWidgets('with filters active, the three search tools still share one '
      'row on a phone, and nothing moves', (tester) async {
    await _pump(tester);
    final savedBefore = tester.getRect(
      find.byKey(const ValueKey('saved-search-menu')),
    );
    await tester.tap(find.byKey(const ValueKey('filters-panel')));
    await tester.pumpAndSettle();
    for (final facet in ['Contra', 'Improper', 'Single']) {
      await tester.tap(find.text(facet).first);
      await tester.pumpAndSettle();
    }

    // A long "Filters (3 active)" pushed Advanced onto a second line, so the
    // whole page jumped down as the first filter was chosen.
    expect(find.text('Filters · 3'), findsOneWidget);
    final toolsTop = _top(tester, 'filters-panel');
    expect(_top(tester, 'by-phrase-panel'), toolsTop);
    expect(_top(tester, 'advanced-panel'), toolsTop);
    _expectTrailingIcons(tester, inToolsRow: false);
    expect(
      tester.getRect(find.byKey(const ValueKey('saved-search-menu'))),
      savedBefore,
    );
  });

  testWidgets('the results start high on a phone screen', (tester) async {
    await _pump(tester);

    // Above the first dance there were Search in, the search box and three
    // stacked panel headers: the "2 dances" count sat at 358dp on this 844dp
    // screen. One search row and one row of tools put it at 188dp; the line
    // that holds the Saved and Online search icons on a phone (#2325) puts it
    // at 240dp.
    expect(tester.getRect(find.text('2 dances')).top, lessThanOrEqualTo(240));
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
    // The Saved menu is still there to reach, inside the screen.
    final saved = find.byKey(const ValueKey('saved-search-menu'));
    expect(saved.hitTestable(), findsOneWidget);
    expect(tester.getRect(saved).right, lessThanOrEqualTo(390));
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

  group('as the list scrolls', () {
    Future<void> scrollFar(WidgetTester tester) async {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }

    testWidgets('the search tools and the dance count stay in view', (
      tester,
    ) async {
      await _pump(tester, extraDances: 60);
      final toolsTop = _top(tester, 'filters-panel');
      final countTop = tester.getRect(find.text('62 dances')).top;

      await scrollFar(tester);

      // The list did scroll: its first dance is gone.
      expect(find.text('Chorus Jig'), findsNothing);
      expect(_top(tester, 'filters-panel'), toolsTop);
      expect(tester.getRect(find.text('62 dances')).top, countTop);
      // On top of the rows that scrolled under them, so a tap reaches them.
      expect(
        find.byKey(const ValueKey('filters-panel')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('online-search-enable')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved-search-menu')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('62 dances').hitTestable(), findsOneWidget);
    });

    testWidgets('an open tool scrolls away between the pinned tools and the '
        'count', (tester) async {
      await _pump(tester, extraDances: 60);
      await tester.tap(find.byKey(const ValueKey('filters-panel')));
      await tester.pumpAndSettle();
      final toolsRect = tester.getRect(
        find.byKey(const ValueKey('filters-panel')),
      );
      expect(
        tester.getRect(find.text('62 dances')).top,
        greaterThan(toolsRect.bottom + 100),
      );

      await scrollFar(tester);

      expect(
        tester.getRect(find.byKey(const ValueKey('filters-panel'))),
        toolsRect,
      );
      // The count has come up to sit just under the row of tools (and, on a
      // phone, the line of Saved and Online search icons under it)…
      final iconsBottom = tester
          .getRect(find.byKey(const ValueKey('saved-search-menu')))
          .bottom;
      final countTop = tester.getRect(find.text('62 dances')).top;
      expect(countTop, greaterThanOrEqualTo(iconsBottom));
      expect(countTop, lessThan(iconsBottom + 40));
      // …and the Filters panel's choices are behind them.
      expect(find.text('Contra').hitTestable(), findsNothing);

      // The pinned toggle still closes the panel it opened.
      await tester.tap(find.byKey(const ValueKey('filters-panel')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('filters-panel')),
          matching: find.byIcon(Icons.expand_more),
        ),
        findsOneWidget,
      );
    });

    testWidgets('on a short screen at large text, the tools scroll away so '
        'the list keeps its room', (tester) async {
      // A phone on its side at 300% text: the search box stacks and leaves
      // the list about 120dp, less than twice the row of tools.
      await _pump(
        tester,
        extraDances: 60,
        size: const Size(844, 390),
        textScale: 3,
      );
      expect(tester.takeException(), isNull);

      await scrollFar(tester);

      expect(
        find.byKey(const ValueKey('filters-panel')).hitTestable(),
        findsNothing,
      );
    });
  });

  testWidgets('German labels fit without overflow', (tester) async {
    await _pump(tester, locale: const Locale('de'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('advanced-panel')), findsOneWidget);
  });
}
