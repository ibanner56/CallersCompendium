import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

Dance _dance({required String id, required String title, int? rating}) => Dance(
  id: id,
  title: title,
  rating: rating,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    AppThemeSelection.system,
  );
  addTearDown(themeNotifier.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
        ),
      ),
      home: const DanceListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterSelectionMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String danceId) async {
  await tester.tap(find.byKey(ValueKey('batch-checkbox-$danceId')));
  await tester.pumpAndSettle();
}

Future<void> _openRatingDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-set-rating')));
  await tester.pumpAndSettle();
}

Future<void> _setRating(WidgetTester tester, String optionKey) async {
  await _openRatingDialog(tester);
  await tester.tap(find.byKey(ValueKey('batch-rating-option-$optionKey')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-rating-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('set-rating applies the chosen rating to every selected dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setRating(tester, '4');

    expect((await repos.dances.getById('d1'))!.rating, 4);
    expect((await repos.dances.getById('d2'))!.rating, 4);
    // The un-selected dance is untouched.
    expect((await repos.dances.getById('d3'))!.rating, isNull);
    expect(find.byKey(const ValueKey('batch-select')), findsOneWidget);
  });

  testWidgets('set-rating is idempotent on dances already at that rating', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', rating: 3));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setRating(tester, '3');

    expect((await repos.dances.getById('d1'))!.rating, 3);
    expect((await repos.dances.getById('d2'))!.rating, 3);
    expect(find.text('Set rating on 1 dance'), findsOneWidget);
  });

  testWidgets('set-rating with "Unrated (clear)" clears the rating', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', rating: 5));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _setRating(tester, 'unrated');

    expect((await repos.dances.getById('d1'))!.rating, isNull);
    expect(find.text('Cleared rating on 1 dance'), findsOneWidget);
  });

  testWidgets('undo restores the prior per-dance ratings', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', rating: 2));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setRating(tester, '5');

    expect((await repos.dances.getById('d1'))!.rating, 5);
    expect((await repos.dances.getById('d2'))!.rating, 5);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Each dance is restored to its own prior rating.
    expect((await repos.dances.getById('d1'))!.rating, 2);
    expect((await repos.dances.getById('d2'))!.rating, isNull);
  });

  testWidgets('set-rating is a no-op when nothing actually changes', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', rating: 4));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _setRating(tester, '4');

    expect(find.text('No changes'), findsOneWidget);
    expect((await repos.dances.getById('d1'))!.rating, 4);
  });

  testWidgets('the batch-more menu is disabled with an empty selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);

    final button = tester.widget<PopupMenuButton<Object?>>(
      find.byKey(const ValueKey('batch-more')),
    );
    expect(button.enabled, isFalse);
  });
}
