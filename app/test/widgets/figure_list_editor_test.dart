import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host that owns a mutable draft list so the editor's in-place edits and
/// add/delete callbacks drive real rebuilds, mirroring the dance editor screen.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, this.phrase = PhraseStructure.standard});

  final List<FigureDraft> drafts;
  final PhraseStructure phrase;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: widget.phrase,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  PhraseStructure phrase = PhraseStructure.standard,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_Host(drafts: drafts, phrase: phrase));
  await tester.pumpAndSettle();
}

Future<void> _selectMove(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
  await tester.enterText(
    find.byKey(ValueKey('figure-$index-move-input')),
    typed,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-move-option-$optionId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty list shows a placeholder and an add button', (
    tester,
  ) async {
    await _pump(tester, []);
    expect(find.text('No figures yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-add')), findsOneWidget);
  });

  testWidgets('add creates an empty figure row', (tester) async {
    final drafts = <FigureDraft>[];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-move-input')), findsOneWidget);
    expect(drafts, hasLength(1));
  });

  testWidgets('selecting a move seeds the taxonomy default params', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    // Default params surface as concrete editors.
    expect(find.byKey(const ValueKey('figure-0-who')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
    expect(drafts.single.move, 'swing');
    expect(drafts.single.params['who'], 'partners');
    expect(drafts.single.params['beats'], 8);
  });

  testWidgets('selecting an alias keeps the alias identity and pins', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'see', 'see_saw');

    expect(drafts.single.move, 'see_saw');
    // Alias pins the do-si-do shoulder to left.
    expect(drafts.single.params['shoulder'], 'left');
  });

  testWidgets('unmatched text creates a custom figure', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'scoop them up',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, customMove);
    expect(drafts.single.params['text'], 'scoop them up');
    expect(find.byKey(const ValueKey('figure-0-text')), findsOneWidget);
  });

  testWidgets('whitespace-only submission does not create a custom figure', (
    tester,
  ) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      '   ',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, isNull);
  });

  testWidgets('custom figure text is trimmed', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      '  scoop them up  ',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(drafts.single.move, customMove);
    expect(drafts.single.params['text'], 'scoop them up');
  });

  testWidgets('running beat total warns on underflow', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    // One swing = 8 beats against the standard 64.
    expect(find.byKey(const ValueKey('figure-beats-total')), findsOneWidget);
    expect(find.text('Total: 8 / 64 beats'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-beats-warning')), findsOneWidget);
    expect(find.text('Under by 56 beats'), findsOneWidget);
  });

  testWidgets('editing beats updates the running total', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();
    expect(find.text('Total: 16 / 64 beats'), findsOneWidget);
    expect(drafts.single.beats, 16);
  });

  testWidgets('derived section labels advance with beats', (tester) async {
    // Two 16-beat figures land in A1 then A2 under the standard structure.
    final drafts = <FigureDraft>[FigureDraft(), FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();
    await _selectMove(tester, 1, 'sw', 'swing');
    await tester.enterText(find.byKey(const ValueKey('figure-1-beats')), '16');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-0-label'))).data,
      'A1',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('figure-1-label'))).data,
      'A2',
    );
  });

  testWidgets('progression toggle flips the draft flag', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    expect(drafts.single.progression, isFalse);
    await tester.tap(find.byKey(const ValueKey('figure-0-progression')));
    await tester.pumpAndSettle();
    expect(drafts.single.progression, isTrue);
  });

  testWidgets('note field records a note on the draft', (tester) async {
    final drafts = <FigureDraft>[FigureDraft()];
    await _pump(tester, drafts);
    await _selectMove(tester, 0, 'sw', 'swing');

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'big and smooth',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.note, 'big and smooth');
  });

  testWidgets('delete removes a figure row', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(move: 'swing', params: {'beats': 8}),
      FigureDraft(move: 'balance', params: {'beats': 4}),
    ];
    await _pump(tester, drafts);
    expect(find.byKey(const ValueKey('figure-1-move-input')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
    await tester.pumpAndSettle();

    expect(drafts, hasLength(1));
    expect(drafts.single.move, 'balance');
  });

  testWidgets('a seeded draft renders its editors and values', (tester) async {
    final drafts = <FigureDraft>[
      FigureDraft(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.0, 'beats': 8},
      ),
    ];
    await _pump(tester, drafts);

    expect(find.byKey(const ValueKey('figure-0-hand')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-0-turn-value')), findsOneWidget);
    // toFigure preserves the seeded values.
    final figure = drafts.single.toFigure()!;
    expect(figure.move, 'allemande');
    expect(figure.params['hand'], 'right');
  });
}
