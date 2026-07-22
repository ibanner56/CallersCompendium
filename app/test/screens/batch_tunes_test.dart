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

Dance _dance({
  required String id,
  required String title,
  List<String> tunes = const [],
}) => Dance(
  id: id,
  title: title,
  tunes: tunes,
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

Future<void> _openMore(WidgetTester tester, String itemKey) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(itemKey)));
  await tester.pumpAndSettle();
}

Future<void> _addTunes(WidgetTester tester, List<String> tunes) async {
  await _openMore(tester, 'batch-add-tunes');
  for (final tune in tunes) {
    await tester.enterText(
      find.byKey(const ValueKey('batch-tunes-field')),
      tune,
    );
    await tester.tap(find.byKey(const ValueKey('batch-tunes-add')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('batch-tunes-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('add-tunes unions tunes into every selected dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _addTunes(tester, ['Jig B']);

    // Existing tune preserved; addition merged in.
    expect((await repos.dances.getById('d1'))!.tunes, ['Reel A', 'Jig B']);
    expect((await repos.dances.getById('d2'))!.tunes, ['Jig B']);
    // The un-selected dance is untouched.
    expect((await repos.dances.getById('d3'))!.tunes, isEmpty);
    expect(find.text('Added tunes to 2 dances'), findsOneWidget);
  });

  testWidgets('add-tunes is idempotent when the tune is already present', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _addTunes(tester, ['Reel A']);

    expect(find.text('Added tunes to 1 dance'), findsOneWidget);
    expect((await repos.dances.getById('d1'))!.tunes, ['Reel A']);
    expect((await repos.dances.getById('d2'))!.tunes, ['Reel A']);
  });

  testWidgets('undo restores the prior per-dance tunes after add', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _addTunes(tester, ['Jig B']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.tunes, ['Reel A']);
    expect((await repos.dances.getById('d2'))!.tunes, isEmpty);
  });

  testWidgets('clear-tunes removes all tunes after confirmation', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A', 'Jig B']),
    );
    await repos.dances.create(
      _dance(id: 'd2', title: 'Bravo', tunes: ['Reel C']),
    );
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await _openMore(tester, 'batch-clear-tunes');
    await tester.tap(
      find.byKey(const ValueKey('batch-clear-tunes-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.tunes, isEmpty);
    expect((await repos.dances.getById('d2'))!.tunes, isEmpty);
    expect(find.text('Cleared tunes from 2 dances'), findsOneWidget);
  });

  testWidgets('clear-tunes can be cancelled and changes nothing', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A']),
    );
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openMore(tester, 'batch-clear-tunes');
    await tester.tap(find.byKey(const ValueKey('batch-clear-tunes-cancel')));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.tunes, ['Reel A']);
  });

  testWidgets('undo restores tunes after a clear', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A', 'Jig B']),
    );
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openMore(tester, 'batch-clear-tunes');
    await tester.tap(
      find.byKey(const ValueKey('batch-clear-tunes-confirm-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.tunes, ['Reel A', 'Jig B']);
  });
}
