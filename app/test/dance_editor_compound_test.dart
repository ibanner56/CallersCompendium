import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart' show testFigure;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/screens/dance_editor/dance_editor_controller.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';

import 'figures_support.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Picking one of the user's own compound figures in the dance editor, and
/// what a saved dance holds for it (#709).
void main() {
  final created = DateTime.utc(2026, 10, 14, 9);

  /// Four pull-bys alternating hands, from the hand given.
  CompoundDefinition grandRightAndLeft({int beats = 2}) {
    Figure pullBy() => testFigure(
      move: 'pull_by',
      params: {'who': 'neighbors', 'hand': 'right', 'beats': beats},
    );
    return CompoundDefinition(
      params: const [
        CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        CompoundParam(key: 'hand', kind: ParamKind.handedness),
      ],
      figures: [pullBy(), pullBy(), pullBy(), pullBy()],
      bindings: [
        for (var i = 0; i < 4; i++) ...[
          CompoundSlotBinding(figureIndex: i, slotKey: 'who', paramKey: 'who'),
          CompoundSlotBinding(
            figureIndex: i,
            slotKey: 'hand',
            paramKey: 'hand',
            source: i.isEven
                ? CompoundBindingSource.declared
                : CompoundBindingSource.opposite,
          ),
        ],
      ],
    );
  }

  UserGlossaryEntry entry({int beats = 2, String name = 'grand pull'}) =>
      UserGlossaryEntry(
        id: 'grl',
        kindName: UserGlossaryEntryKind.compound.name,
        name: name,
        definition: 'Pull by alternating hands.',
        description: 'Four pull-bys.',
        payload: grandRightAndLeft(beats: beats).toJson(),
        createdAt: created,
      );

  FigureDraft placeholder({String hand = 'right'}) => FigureDraft(
    compound: CompoundPlaceholder(
      id: 'grl',
      name: 'grand pull',
      args: {'who': 'partners', 'hand': hand},
    ),
  );

  group('the controller', () {
    Future<DanceEditorController> loaded(CompendiumRepositories repos) async {
      final controller = DanceEditorController(
        repositories: repos,
        danceId: null,
        dialect: Dialect.larksRobins,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.load(dance: null, fieldDefs: const []);
      controller.titleController.text = 'A dance';
      controller.figureDrafts.clear();
      return controller;
    }

    test('builds a dance holding the expansion, with no trace of the '
        'compound', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(entry());
      final controller = await loaded(repos);
      controller.figureDrafts.add(placeholder(hand: 'left'));

      final figures = figuresOf(controller.buildDance());
      expect([for (final f in figures) f.move], List.filled(4, 'pull_by'));
      expect(
        [for (final f in figures) f.params['hand']],
        ['left', 'right', 'left', 'right'],
      );
      final stored = encodeFigures(figures);
      expect(stored, isNot(contains('grl')));
      expect(stored, isNot(contains('grand pull')));
    });

    test('expands with the compound as it is stored when the dance is built, '
        'and falls back to its name once it is deleted', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(entry());
      final controller = await loaded(repos);
      controller.figureDrafts.add(placeholder());

      await repos.userGlossary.upsert(entry(beats: 4));
      await controller.refreshCompounds();
      expect([
        for (final f in figuresOf(controller.buildDance())) f.params['beats'],
      ], List.filled(4, 4));

      await repos.userGlossary.delete('grl');
      await controller.refreshCompounds();
      final fallback = figuresOf(controller.buildDance()).single;
      expect(fallback.move, customMove);
      expect(fallback.params['text'], 'grand pull');
      expect(fallback.params['beats'], 16, reason: 'its last expansion\'s');
    });

    test('offers only compounds this build can expand', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(entry());
      await repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'broken',
          kindName: UserGlossaryEntryKind.compound.name,
          name: 'broken',
          definition: 'd',
          description: 'd',
          payload: const {'x': 1},
          createdAt: created,
        ),
      );
      final controller = await loaded(repos);
      expect([for (final e in controller.compoundEntries) e.id], ['grl']);
      expect(controller.resolveCompound('broken'), isNull);
    });

    test(
      'will not group a placeholder, as the first row or the second',
      () async {
        final repos = openTestRepositories();
        await repos.userGlossary.upsert(entry());
        final controller = await loaded(repos);
        final swing = FigureDraft(
          move: 'swing',
          params: {'who': 'partners', 'beats': 8},
        );
        controller.figureDrafts.addAll([placeholder(), swing, placeholder()]);
        controller
          ..groupFigureWithNext(controller.figureDrafts[0])
          ..groupFigureWithNext(controller.figureDrafts[1])
          ..groupFigureWithNextAsModifier(controller.figureDrafts[0])
          ..groupFigureWithNextAsModifier(controller.figureDrafts[1]);
        expect(controller.figureDrafts, hasLength(3));
        expect(controller.figureDrafts.any((d) => d.isContainerDraft), isFalse);
      },
    );

    test('a restored draft\'s placeholder takes the beats its compound has '
        'now', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(entry());
      final controller = await loaded(repos);
      final stale = placeholder()..compound!.beats = 3;
      controller.figureDrafts.add(stale);
      final snapshot = controller.captureSnapshot();
      controller.figureDrafts.clear();

      controller.applyRestoredDraft(snapshot);
      expect(controller.figureDrafts.single.compound!.beats, 8);
      expect(controller.figureDrafts.single.beats, 8);
    });

    test('a duplicated placeholder keeps its values', () async {
      final repos = openTestRepositories();
      await repos.userGlossary.upsert(entry());
      final controller = await loaded(repos);
      controller.figureDrafts.add(placeholder(hand: 'left'));
      controller.duplicateFigure(controller.figureDrafts.single);
      expect(controller.figureDrafts, hasLength(2));
      expect(controller.figureDrafts.last.compound!.args['hand'], 'left');
      expect(figuresOf(controller.buildDance()), hasLength(8));
    });
  });

  group('the dance editor', () {
    Future<CompendiumRepositories> pump(
      WidgetTester tester, {
      bool customFigures = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      await tester.runAsync(() => repos.userGlossary.upsert(entry()));
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      final glossary = ValueNotifier<bool>(true);
      final custom = ValueNotifier<bool>(customFigures);
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
                child: ShowCustomFiguresScope(notifier: custom, child: child!),
              ),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-editor'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<String>(
                    builder: (_) => const DanceEditorScreen(danceId: null),
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

    Future<void> typeMove(WidgetTester tester, String text) async {
      if (find
          .byKey(const ValueKey('figure-0-move-input'))
          .evaluate()
          .isEmpty) {
        await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(const ValueKey('figure-0-move-input')),
        text,
      );
      await tester.pumpAndSettle();
    }

    const option = ValueKey('figure-0-move-option-compound:grl');

    testWidgets('a picked compound is saved as the figures it expands to', (
      tester,
    ) async {
      final repos = await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('title-field')), 'T');
      await typeMove(tester, 'grand');
      await tester.tap(find.byKey(option));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final dance = (await tester.runAsync(repos.dances.listAll))!.single;
      final figures = figuresOf(dance);
      expect(
        [for (final f in figures.take(4)) (f.move, f.params['hand'])],
        [
          ('pull_by', 'right'),
          ('pull_by', 'left'),
          ('pull_by', 'right'),
          ('pull_by', 'left'),
        ],
      );
      expect(figures.skip(4).any((f) => f.move == customMove), isFalse);
    });

    testWidgets('a save expands with the compound as stored then, even when '
        'the change has not reached the editor', (tester) async {
      final repos = await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('title-field')), 'T');
      await typeMove(tester, 'grand');
      await tester.tap(find.byKey(option));
      await tester.pumpAndSettle();
      // Written past the repository, so the editor's watch is not told.
      await tester.runAsync(
        () => repos.db.customStatement(
          'UPDATE user_glossary_entries SET payload_json = ? WHERE id = ?',
          [jsonEncode(grandRightAndLeft(beats: 4).toJson()), 'grl'],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final dance = (await tester.runAsync(repos.dances.listAll))!.single;
      expect([
        for (final f in figuresOf(dance).take(4)) f.params['beats'],
      ], List.filled(4, 4));
    });

    testWidgets('no compound is offered while Custom Figures is off', (
      tester,
    ) async {
      await pump(tester, customFigures: false);
      await typeMove(tester, 'grand');
      expect(find.byKey(option), findsNothing);
    });
  });
}
