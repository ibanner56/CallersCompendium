import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The user's own compound figures in the figure list (#709): offered in a
/// top-level row's move picker, and edited there as one placeholder row until
/// the dance is saved.
void main() {
  /// Four pull-bys alternating hands, from the hand given.
  CompoundDefinition grandRightAndLeft() {
    Figure pullBy() => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
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

  final entry = UserGlossaryEntry(
    id: 'grl',
    kindName: UserGlossaryEntryKind.compound.name,
    name: 'grand pull',
    definition: 'Pull by alternating hands.',
    description: 'Four pull-bys.',
    keywords: const ['grl'],
    payload: grandRightAndLeft().toJson(),
    createdAt: DateTime.utc(2026, 10, 14),
  );

  Future<void> pump(
    WidgetTester tester,
    List<FigureDraft> drafts, {
    List<UserGlossaryEntry>? options = const [],
    CompoundResolver? resolve,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => FigureListEditor(
                drafts: drafts,
                taxonomy: contraTaxonomy,
                phraseStructure: PhraseStructure.standard,
                dialect: Dialect.larksRobins,
                onChanged: () => setState(() {}),
                onAdd: () => setState(() => drafts.add(FigureDraft())),
                onDelete: (d) => setState(() => drafts.remove(d)),
                onReorder: (from, to) => setState(() {
                  drafts.insert(to, drafts.removeAt(from));
                }),
                onGroupWithNext: (_) {},
                onGroupWithNextAsModifier: (_) {},
                compoundOptions: options == null ? null : [...options, entry],
                resolveCompound:
                    resolve ?? (id) => id == 'grl' ? grandRightAndLeft() : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pumpAndSettle();
  }

  const compoundOption = ValueKey('figure-0-move-option-compound:grl');

  FigureDraft placeholder() => FigureDraft(
    compound: CompoundPlaceholder(
      id: 'grl',
      name: 'grand pull',
      args: {'who': 'neighbors', 'hand': 'right'},
      beats: 8,
    ),
  );

  testWidgets('a top-level row offers a compound first, found by name or '
      'keyword, and picking it makes the row a placeholder with its '
      'author\'s values', (tester) async {
    final drafts = [FigureDraft()];
    await pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();

    await type(tester, 'figure-0-move-input', 'grl');
    expect(find.byKey(compoundOption), findsOneWidget, reason: 'a keyword');
    await type(tester, 'figure-0-move-input', 'pull');
    expect(find.byKey(compoundOption), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.first.key, compoundOption, reason: 'before the moves');
    expect(find.byTooltip('Custom'), findsWidgets);

    await tester.tap(find.byKey(compoundOption));
    await tester.pumpAndSettle();
    final draft = drafts.single;
    expect(draft.move, isNull);
    expect(draft.params, isEmpty);
    expect(draft.compound!.id, 'grl');
    expect(draft.compound!.args, {'who': 'neighbors', 'hand': 'right'});
    expect(draft.compound!.beats, 8);
    expect(
      find.text('Becomes 4 figures (8 beats) when the dance is saved.'),
      findsOneWidget,
    );
  });

  testWidgets('a placeholder\'s values are edited within what the compound '
      'accepts, and its row summarises them', (tester) async {
    final drafts = [placeholder()];
    await pump(tester, drafts);
    expect(find.text('grand pull: neighbors, right'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-0-compound-hand')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('left').last);
    await tester.pumpAndSettle();
    expect(drafts.single.compound!.args['hand'], 'left');
  });

  testWidgets('no compound is offered without options', (tester) async {
    await pump(tester, [FigureDraft()], options: null);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-move-input', 'grand');
    expect(find.byKey(compoundOption), findsNothing);
  });

  testWidgets('a meanwhile side does not offer compounds', (tester) async {
    final drafts = [
      FigureDraft(meanwhileSides: [FigureDraft(), FigureDraft()])
        ..params['beats'] = 8,
    ];
    await pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-side-0-move-input', 'grand');
    expect(
      find.byKey(const ValueKey('figure-0-side-0-move-option-compound:grl')),
      findsNothing,
    );
    expect(find.text('grand pull'), findsNothing);
  });

  testWidgets('a placeholder cannot be grouped, as the first row or the '
      'second', (tester) async {
    await pump(tester, [
      placeholder(),
      FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      placeholder(),
    ]);
    for (final index in [0, 1]) {
      await tester.tap(find.byKey(ValueKey('figure-$index-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('figure-$index-group-with-next')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('figure-$index-group-with-next-modifier')),
        findsNothing,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a placeholder that can no longer expand says it will be saved '
      'as its name', (tester) async {
    await pump(tester, [placeholder()], resolve: (_) => null);
    expect(
      find.byKey(const ValueKey('figure-0-compound-unavailable')),
      findsOneWidget,
    );
    expect(find.text('grand pull'), findsOneWidget);
  });

  testWidgets('opening a placeholder whose value the compound no longer '
      'accepts leaves the value as it is', (tester) async {
    final drafts = [
      FigureDraft(
        compound: CompoundPlaceholder(
          id: 'grl',
          name: 'grand pull',
          args: {'who': 'neighbors', 'hand': 'sideways'},
          beats: 8,
        ),
      ),
    ];
    await pump(tester, drafts);
    expect(
      find.byKey(const ValueKey('figure-0-compound-unavailable')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    expect(drafts.single.compound!.args, {
      'who': 'neighbors',
      'hand': 'sideways',
    });
    final status = tester.widget<Text>(
      find.byKey(const ValueKey('figure-0-compound-status')),
    );
    expect(status.data, startsWith('This figure of yours can\'t be expanded'));
  });

  // A hey whose ends pair is the compound's parameter: `hey.pass2` admits
  // "not stated", so the field could claim it.
  CompoundDefinition heyWithEnds() => CompoundDefinition(
    params: const [CompoundParam(key: 'ends', kind: ParamKind.dancerSet)],
    figures: [
      Figure(move: 'hey', params: const {'pass1': 'role2s', 'length': 'half'}),
    ],
    bindings: [
      CompoundSlotBinding(figureIndex: 0, slotKey: 'pass2', paramKey: 'ends'),
    ],
  );

  for (final (label, args) in [
    ('one it no longer accepts', {'ends': 'sideways'}),
    ('a missing one', <String, Object?>{}),
  ]) {
    testWidgets('a placeholder\'s field asks for a choice for $label, rather '
        'than reading "not stated", and can be cleared', (tester) async {
      final drafts = [
        FigureDraft(
          compound: CompoundPlaceholder(
            id: 'grl',
            name: 'grand pull',
            args: Map.of(args),
            beats: 8,
          ),
        ),
      ];
      await pump(tester, drafts, resolve: (_) => heyWithEnds());
      await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('figure-0-compound-ends'));
      expect(
        find.descendant(of: field, matching: find.text('choose a value')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('not stated')),
        findsNothing,
      );
      expect(drafts.single.compound!.args, args, reason: 'left as it is');

      await tester.tap(
        find.byKey(const ValueKey('figure-0-compound-ends-clear')),
      );
      await tester.pumpAndSettle();
      expect(drafts.single.compound!.args['ends'], ParamVocab.unspecified);
      expect(
        find.descendant(of: field, matching: find.text('not stated')),
        findsOneWidget,
      );
    });
  }

  // A gate whose turn amount is the compound's `turns`; `gate.travel` is the
  // one rotation slot that admits "not stated". `again` is a flag bound to no
  // slot, which its row may not hold yet.
  CompoundDefinition gateWithTurns() => CompoundDefinition(
    params: const [
      CompoundParam(key: 'turns', kind: ParamKind.rotation),
      CompoundParam(key: 'again', kind: ParamKind.flag),
    ],
    figures: [Figure(move: 'gate', params: const {})],
    bindings: [
      CompoundSlotBinding(figureIndex: 0, slotKey: 'travel', paramKey: 'turns'),
    ],
  );

  Future<List<FigureDraft>> pumpGate(
    WidgetTester tester,
    Map<String, Object?> args,
  ) async {
    final drafts = [
      FigureDraft(
        compound: CompoundPlaceholder(
          id: 'grl',
          name: 'gate turns',
          args: args,
          beats: 8,
        ),
      ),
    ];
    await pump(tester, drafts, resolve: (_) => gateWithTurns());
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    return drafts;
  }

  String turnsShown(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('figure-0-compound-turns-value')))
      .data!;

  testWidgets('a rotation argument holding "not stated" says so, not 1, and '
      'can be set back to it', (tester) async {
    final drafts = await pumpGate(tester, {
      'turns': ParamVocab.unspecified,
      'again': false,
    });
    expect(turnsShown(tester), 'not stated');
    expect(
      find.byKey(const ValueKey('figure-0-compound-turns-choose')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('figure-0-compound-turns-inc')));
    await tester.pumpAndSettle();
    expect(drafts.single.compound!.args['turns'], isA<num>());
    await tester.tap(
      find.byKey(const ValueKey('figure-0-compound-turns-clear')),
    );
    await tester.pumpAndSettle();
    expect(drafts.single.compound!.args['turns'], ParamVocab.unspecified);
    expect(turnsShown(tester), 'not stated');
  });

  testWidgets('an argument of a kind that is not a list asks for a choice '
      'when it is missing, and is left as it is', (tester) async {
    final drafts = await pumpGate(tester, {'turns': ParamVocab.unspecified});
    expect(
      find.byKey(const ValueKey('figure-0-compound-again-choose')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('figure-0-compound-turns-choose')),
      findsNothing,
    );
    expect(drafts.single.compound!.args, {'turns': ParamVocab.unspecified});
  });

  for (final (label, args) in [
    (
      'one the compound no longer accepts',
      {'turns': 'sideways', 'again': true},
    ),
    ('a missing one', {'again': true}),
    ('an amount outside the domain', {'turns': 3.0, 'again': true}),
  ]) {
    testWidgets('a rotation argument asks for a choice for $label, never '
        'reading "not stated", and can be cleared', (tester) async {
      final drafts = await pumpGate(tester, Map.of(args));
      expect(turnsShown(tester), 'choose a value');
      // Nothing on the page claims "not stated": the only other argument
      // is a flag.
      expect(find.text('not stated'), findsNothing);
      expect(drafts.single.compound!.args, args, reason: 'left as it is');

      await tester.tap(
        find.byKey(const ValueKey('figure-0-compound-turns-clear')),
      );
      await tester.pumpAndSettle();
      expect(drafts.single.compound!.args['turns'], ParamVocab.unspecified);
      expect(turnsShown(tester), 'not stated');
    });
  }

  testWidgets('a placeholder counts its beats in the phrase labels', (
    tester,
  ) async {
    // 8 beats of placeholder and 8 of swing fill A1; the next swing is A2.
    await pump(tester, [
      placeholder(),
      FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      FigureDraft(move: 'swing', params: {'who': 'partners', 'beats': 8}),
    ]);
    String label(int i) =>
        tester.widget<Text>(find.byKey(ValueKey('figure-$i-label'))).data!;
    expect([label(0), label(1), label(2)], ['A1', '', 'A2']);
  });

  testWidgets('a placeholder\'s picker does not offer the modifier, which '
      'would discard it', (tester) async {
    await pump(tester, [placeholder()]);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-move-input', 'modifier');
    expect(
      find.byKey(const ValueKey('figure-0-move-option-$modifierMove')),
      findsNothing,
    );
  });

  testWidgets('choosing a move replaces the placeholder', (tester) async {
    final drafts = [placeholder()];
    await pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await type(tester, 'figure-0-move-input', 'swing');
    await tester.tap(find.byKey(const ValueKey('figure-0-move-option-swing')));
    await tester.pumpAndSettle();
    expect(drafts.single.compound, isNull);
    expect(drafts.single.move, 'swing');
  });
}
