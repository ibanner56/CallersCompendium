import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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

Dance _dance({required String id, required String title, DanceLevel? level}) =>
    Dance(
      id: id,
      title: title,
      level: level,
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

Future<void> _setLevel(WidgetTester tester, String optionKey) async {
  await tester.tap(find.byKey(const ValueKey('batch-set-level')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('batch-level-option-$optionKey')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-level-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('set-level applies the chosen level to every selected dance', (
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
    await _setLevel(tester, 'intermediate');

    expect((await repos.dances.getById('d1'))!.level, DanceLevel.intermediate);
    expect((await repos.dances.getById('d2'))!.level, DanceLevel.intermediate);
    // The un-selected dance is untouched.
    expect((await repos.dances.getById('d3'))!.level, isNull);
    // Selection mode ends after applying.
    expect(find.byKey(const ValueKey('batch-select')), findsOneWidget);
  });

  testWidgets('set-level is idempotent on dances already at that level', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', level: DanceLevel.beginner),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setLevel(tester, 'beginner');

    expect((await repos.dances.getById('d1'))!.level, DanceLevel.beginner);
    expect((await repos.dances.getById('d2'))!.level, DanceLevel.beginner);
    // Only one dance actually changed.
    expect(find.text('Set level on 1 dance'), findsOneWidget);
  });

  testWidgets('set-level with "Unspecified (clear)" clears the level', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', level: DanceLevel.advanced),
    );
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _setLevel(tester, 'unspecified');

    expect((await repos.dances.getById('d1'))!.level, isNull);
    expect(find.text('Cleared level on 1 dance'), findsOneWidget);
  });

  testWidgets('undo restores the prior per-dance levels', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', level: DanceLevel.beginner),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _setLevel(tester, 'advanced');

    expect((await repos.dances.getById('d1'))!.level, DanceLevel.advanced);
    expect((await repos.dances.getById('d2'))!.level, DanceLevel.advanced);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Each dance is restored to its own prior level.
    expect((await repos.dances.getById('d1'))!.level, DanceLevel.beginner);
    expect((await repos.dances.getById('d2'))!.level, isNull);
  });

  testWidgets('set-level is a no-op when nothing actually changes', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', level: DanceLevel.intermediate),
    );
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _setLevel(tester, 'intermediate');

    expect(find.text('No changes'), findsOneWidget);
    expect((await repos.dances.getById('d1'))!.level, DanceLevel.intermediate);
  });

  testWidgets('set-level button is disabled with an empty selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('batch-set-level')),
    );
    expect(button.onPressed, isNull);
  });
}
