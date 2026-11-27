import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';

import 'figures_support.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// An English Becket is a longways set whose formation detail says Becket, and
/// its ring is four dancers: "circle left half way" typed in the editor is two
/// places. The detail reaches the parser on every path a typed line takes —
/// the figure box, an existing row's Move box, a `;` line with a shorthand
/// clause, and the Add figures from text sheet — so each is checked here, and
/// against a plain longways set, whose ring is unknown and is not two places.
void main() {
  final created = DateTime.utc(2026, 11, 27, 9);

  // A compound of the user's own, so a `;` line holding its token takes the
  // editor's shorthand-clause path (#1866).
  final entry = UserGlossaryEntry(
    id: 'twirl',
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'twirl',
    definition: 'Turn single twice.',
    description: 'Two turn singles.',
    payload: CompoundDefinition(
      params: const [],
      figures: [
        Figure(move: 'ecd_turn_single', params: const {'beats': 4}),
        Figure(move: 'ecd_turn_single', params: const {'beats': 4}),
      ],
      bindings: const [],
    ).toJson(),
    createdAt: created,
  );

  Future<CompendiumRepositories> pump(
    WidgetTester tester, {
    required String detail,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await repos.settings.set(kFreeTextEntryKey, true);
      await repos.userGlossary.upsert(entry);
      await controller.upsertCompound(
        CompoundShorthand(
          token: 'TW',
          compoundId: 'twirl',
          compoundName: 'twirl',
          args: {},
        ),
      );
      await repos.dances.create(
        Dance(
          id: 'becket',
          title: 'Becket',
          form: DanceForm.ecd,
          formation: Formation(FormationShape.longways, detail: detail),
          figures: [
            Figure(move: 'ecd_siding', params: const {'beats': 8}),
          ],
          createdAt: created,
          updatedAt: created,
        ),
      );
    });
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final glossary = ValueNotifier<bool>(true);
    final custom = ValueNotifier<bool>(true);
    for (final n in [glossary, custom]) {
      addTearDown(n.dispose);
    }
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(
                notifier: custom,
                child: ShorthandMappingsScope(
                  controller: controller,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-editor'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<String>(
                  builder: (_) => const DanceEditorScreen(danceId: 'becket'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
  }

  Future<void> typeInFigureBox(WidgetTester tester, String line) async {
    await openAddMenu(tester);
    final figureItem = find.byKey(const ValueKey('figure-add-figure'));
    if (figureItem.evaluate().isNotEmpty) {
      await tester.tap(figureItem);
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('figure-free-text-field')),
      line,
    );
    await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
    await tester.pumpAndSettle();
  }

  Future<void> typeInMoveBox(WidgetTester tester, String line) async {
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      line,
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> addFromTextSheet(WidgetTester tester, String line) async {
    await openAddMenu(tester);
    await tester.tap(find.byKey(const ValueKey('figure-add-from-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-text-sheet-field')),
      line,
    );
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('figure-text-sheet-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  /// The places of the one ring the saved dance holds.
  Future<Object?> savedRingPlaces(
    WidgetTester tester,
    CompendiumRepositories repos,
  ) async {
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();
    final dance = (await tester.runAsync(
      () => repos.dances.getById('becket'),
    ))!;
    final rings = [
      for (final f in figuresOf(dance))
        if (f.move == 'ecd_circle') f,
    ];
    expect(rings, hasLength(1));
    return rings.single.params['places'];
  }

  final paths = <String, Future<void> Function(WidgetTester)>{
    'the figure box': (t) => typeInFigureBox(t, 'circle left half way'),
    'an existing row\'s Move box': (t) =>
        typeInMoveBox(t, 'circle left half way'),
    'a ; line with a shorthand clause': (t) =>
        typeInFigureBox(t, 'TW; circle left half way'),
    'the Add figures from text sheet': (t) =>
        addFromTextSheet(t, 'circle left half way'),
  };

  for (final MapEntry(key: path, value: type) in paths.entries) {
    testWidgets('a Becket rings four dancers when typed in $path', (
      tester,
    ) async {
      final repos = await pump(tester, detail: 'Becket');
      await type(tester);
      expect(await savedRingPlaces(tester, repos), 2);
    });

    testWidgets('a plain longways set does not ring four when typed in '
        '$path', (tester) async {
      final repos = await pump(tester, detail: '');
      await type(tester);
      // The editor stores a ring it cannot size as unstated.
      expect(await savedRingPlaces(tester, repos), isNot(2));
    });
  }
}
