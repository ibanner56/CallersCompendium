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
  List<String> tagIds = const [],
}) => Dance(
  id: id,
  title: title,
  tagIds: tagIds,
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

Set<String> _tagIdsOf(Dance dance) => dance.tagIds.toSet();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('enters selection mode and tracks the selected count', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    expect(find.text('0 selected'), findsOneWidget);

    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    expect(find.text('2 selected'), findsOneWidget);

    await _toggle(tester, 'd1');
    expect(find.text('1 selected'), findsOneWidget);

    // Exit clears the mode.
    await tester.tap(find.byKey(const ValueKey('batch-exit')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.byKey(const ValueKey('batch-select')), findsOneWidget);
  });

  testWidgets('long-press enters selection mode with that row selected', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('add-tags applies the chosen tag to every selected dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Beginner'));
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await repos.dances.create(_dance(id: 'd3', title: 'Charlie'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');

    await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
    await tester.pumpAndSettle();

    expect(_tagIdsOf((await repos.dances.getById('d1'))!), {'t1'});
    expect(_tagIdsOf((await repos.dances.getById('d2'))!), {'t1'});
    expect(_tagIdsOf((await repos.dances.getById('d3'))!), isEmpty);
    // Selection mode ends after applying.
    expect(find.byKey(const ValueKey('batch-select')), findsOneWidget);
  });

  testWidgets('add-tags unions without duplicating an existing tag', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Beginner'));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', tagIds: ['t1']));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
    await tester.tap(find.byKey(const ValueKey('batch-tag-option-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
    await tester.pumpAndSettle();

    final d1 = (await repos.dances.getById('d1'))!;
    expect(d1.tagIds, ['t1', 't2']);
  });

  testWidgets('remove-tags subtracts from every selected dance', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Beginner'));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
    await repos.dances.create(
      _dance(id: 'd1', title: 'Alpha', tagIds: ['t1', 't2']),
    );
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo', tagIds: ['t1']));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await tester.tap(find.byKey(const ValueKey('batch-remove-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
    await tester.pumpAndSettle();

    expect(_tagIdsOf((await repos.dances.getById('d1'))!), {'t2'});
    expect(_tagIdsOf((await repos.dances.getById('d2'))!), isEmpty);
  });

  testWidgets('remove-tags picker only lists tags present on the selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Beginner'));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', tagIds: ['t1']));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await tester.tap(find.byKey(const ValueKey('batch-remove-tags')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('batch-tag-option-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-tag-option-t2')), findsNothing);
  });

  testWidgets('create-inline tag then apply persists and tags the selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('batch-new-tag-field')),
      'Contra Corners',
    );
    await tester.tap(find.byKey(const ValueKey('batch-create-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
    await tester.pumpAndSettle();

    final tags = await repos.tags.listAll();
    expect(tags.map((t) => t.name), contains('Contra Corners'));
    final newTagId = tags.firstWhere((t) => t.name == 'Contra Corners').id;
    expect(_tagIdsOf((await repos.dances.getById('d1'))!), {newTagId});
  });

  testWidgets('undo restores the prior tag sets', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Beginner'));
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha', tagIds: ['t1']));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _toggle(tester, 'd2');
    await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
    await tester.pumpAndSettle();

    // Both dances now carry t1 (d1 unchanged, d2 gained it).
    expect(_tagIdsOf((await repos.dances.getById('d2'))!), {'t1'});

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // d2 (the only changed dance) is restored to no tags; d1 stays as it was.
    expect(_tagIdsOf((await repos.dances.getById('d1'))!), {'t1'});
    expect(_tagIdsOf((await repos.dances.getById('d2'))!), isEmpty);
  });

  testWidgets('selection checkbox and batch actions are AT-reachable', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    final handle = tester.ensureSemantics();
    await _pumpScreen(tester, repos);

    await _enterSelectionMode(tester);

    // The selection toggle exposes checkbox role + checked state (not
    // color-only) and is reachable/toggleable by assistive tech.
    final checkbox = find.byKey(const ValueKey('batch-checkbox-d1'));
    expect(
      tester.getSemantics(checkbox),
      isSemantics(
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
      reason: 'selection checkbox must expose checked-state semantics',
    );

    await _toggle(tester, 'd1');
    expect(
      tester.getSemantics(checkbox),
      isSemantics(hasCheckedState: true, isChecked: true),
      reason: 'checkbox must reflect the checked state after toggling',
    );

    // The batch add-tags action is a labelled, focusable, tappable button.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('batch-add-tags'))),
      isSemantics(
        tooltip: 'Add tags',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
      reason: 'Add tags must be a reachable button',
    );
    handle.dispose();
  });
}
