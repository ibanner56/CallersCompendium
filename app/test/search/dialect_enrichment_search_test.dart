import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import '../support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: figures,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Pumps [DanceListScreen] with the active dialect fixed to Larks/Robins and,
/// when [library] is provided, a [DialectLibraryScope] exposing the user's
/// saved dialects (the source of union search enrichment).
Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos, {
  DialectLibraryController? library,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialectNotifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialectNotifier.dispose);
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    AppThemeSelection.system,
  );
  addTearDown(themeNotifier.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  final ignoreArticles = ValueNotifier<bool>(true);
  addTearDown(ignoreArticles.dispose);

  Widget wrap(Widget child) {
    Widget tree = ActiveDialectScope(
      notifier: dialectNotifier,
      child: SortIgnoreArticlesScope(notifier: ignoreArticles, child: child),
    );
    if (library != null) {
      tree = DialectLibraryScope(controller: library, child: tree);
    }
    return RepositoriesScope(
      repositories: repos,
      child: AppThemeScope(
        notifier: themeNotifier,
        child: CustomThemesScope(controller: customThemes, child: tree),
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => wrap(child!),
      home: const DanceListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Seeds one dance with a canonical role2s figure param (so FTS stores
  // 'role2s') and one decoy that never should match a role-term query.
  Future<CompendiumRepositories> seed() async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'chain',
        title: 'Chain Dance',
        figures: [
          Figure(move: 'swing', params: const {'who': 'role2s', 'beats': 8}),
        ],
      ),
    );
    await repos.dances.create(_dance(id: 'decoy', title: 'Decoy Dance'));
    return repos;
  }

  testWidgets(
    'a term from a NON-active saved dialect resolves like ladies/role2s',
    (tester) async {
      final repos = await seed();
      // A custom dialect the user saved but is NOT actively using, with a term
      // that exists in no shipped preset — role2 → "sylph".
      final library = DialectLibraryController(repos.settings);
      await library.load();
      await library.upsert(
        Dialect(name: 'Sylphs', roles: const {'role2': RoleTerm('sylph')}),
      );
      addTearDown(library.dispose);

      await _pumpScreen(tester, repos, library: library);

      // Baseline: the built-in legacy synonym resolves today.
      await _search(tester, 'ladies');
      expect(_titles(tester), ['Chain Dance']);

      // The reported bug: a term from the user's own saved (non-active) dialect
      // must now resolve the same way.
      await _search(tester, 'sylphs');
      expect(_titles(tester), ['Chain Dance']);
    },
  );

  testWidgets(
    'without the saved dialect, the custom term does not resolve (old bug)',
    (tester) async {
      final repos = await seed();
      final library = DialectLibraryController(repos.settings);
      await library.load();
      addTearDown(library.dispose);

      await _pumpScreen(tester, repos, library: library);

      // Legacy synonym still works...
      await _search(tester, 'ladies');
      expect(_titles(tester), ['Chain Dance']);
      // ...but the un-saved custom term matches nothing.
      await _search(tester, 'sylphs');
      expect(_titles(tester), isEmpty);
    },
  );
}
