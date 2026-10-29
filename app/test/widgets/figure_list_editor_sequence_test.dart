import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The sequence container in [FigureListEditor]: its picker entry, Add menu
/// entry, row-menu grouping, the steps' own beats and total, and the
/// four-step and one-phrase limits.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, required this.phrase});

  final List<FigureDraft> drafts;
  final PhraseStructure phrase;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _aggressive = ValueNotifier(false);

  @override
  void dispose() {
    _aggressive.dispose();
    super.dispose();
  }

  void _groupWithNext(FigureDraft draft, String kind) => setState(() {
    final i = widget.drafts.indexOf(draft);
    final group = FigureDraft.group(kind, draft, widget.drafts[i + 1]);
    widget.drafts
      ..removeRange(i, i + 2)
      ..insert(i, group);
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: AggressiveBeatsUpdateScope(
      notifier: _aggressive,
      child: Scaffold(
        body: SingleChildScrollView(
          child: FigureListEditor(
            drafts: widget.drafts,
            taxonomy: contraTaxonomy,
            phraseStructure: widget.phrase,
            onChanged: () => setState(() {}),
            onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
            onAddSequence: () {
              final draft = FigureDraft(
                sequenceFigures: [FigureDraft(), FigureDraft()],
              );
              setState(() => widget.drafts.add(draft));
              return Future.value(draft.id);
            },
            onDelete: (d) => setState(() => widget.drafts.remove(d)),
            onGroupWithNext: (d) => _groupWithNext(d, meanwhileMove),
            onGroupWithNextAsSequence: (d) => _groupWithNext(d, sequenceMove),
            onConvertToSequence: (d) =>
                setState(() => d.convertContainerTo(sequenceMove)),
            onCollapseMeanwhileGroup: (group, remaining) => setState(() {
              widget.drafts[widget.drafts.indexOf(group)] = remaining;
            }),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  PhraseStructure phrase = PhraseStructure.standard,
}) async {
  const size = Size(1200, 2400);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(_Host(drafts: drafts, phrase: phrase));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
}

FigureDraft _step(String move, int beats) =>
    FigureDraft(move: move, params: {'beats': beats}, beatsTouched: true);

void main() {
  testWidgets('the move picker turns a row into a sequence', (tester) async {
    final drafts = [FigureDraft()];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-move-option-sequence')),
    );
    await tester.pumpAndSettle();

    expect(drafts.single.isSequenceGroup, isTrue);
    expect(drafts.single.sequenceFigures, hasLength(2));
    expect(find.text('Sequence (2 figures)'), findsOneWidget);
  });

  testWidgets('the Add menu inserts and opens a sequence', (tester) async {
    final drafts = <FigureDraft>[];
    await _pump(tester, drafts);
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-add-sequence')));
    await tester.pumpAndSettle();

    expect(drafts.single.isSequenceGroup, isTrue);
    expect(find.byKey(const ValueKey('figure-0-sequence-beats')), findsOne);
  });

  testWidgets('each step edits its own beats, which add up to the total', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.text('12 beats in total'), findsOneWidget);
    // No shared Beats field: the steps own the count.
    expect(find.byKey(const ValueKey('figure-0-sequence-beats')), findsOne);
    expect(
      find.byKey(const ValueKey('figure-0-sequence-beats-beats')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-1-beats')),
      '12',
    );
    await tester.pumpAndSettle();

    expect(drafts.single.beats, 16);
    expect(find.text('16 beats in total'), findsOneWidget);
    expect(drafts.single.toFigure()!.beats, 16);
  });

  testWidgets('a sequence stops at four steps', (tester) async {
    final drafts = [
      FigureDraft(
        sequenceFigures: [for (var i = 0; i < 3; i++) _step('balance', 2)],
      ),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.tap(find.byKey(const ValueKey('figure-0-add-side')));
    await tester.pumpAndSettle();

    expect(drafts.single.sequenceFigures, hasLength(kMaxSequenceFigures));
    expect(find.byKey(const ValueKey('figure-0-add-side')), findsNothing);
    expect(find.text('Maximum of 4 figures in a sequence.'), findsOneWidget);
  });

  testWidgets('no step is added once the steps fill a phrase', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-add-side')), findsNothing);
    expect(
      find.text('These figures fill one phrase (16 beats).'),
      findsOneWidget,
    );
  });

  testWidgets('a sequence longer than a phrase is flagged', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 12)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(
      find.byKey(const ValueKey('figure-0-sequence-over-phrase')),
      findsOneWidget,
    );
  });

  testWidgets('the phrase is the dance\'s own', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 8), _step('swing', 8)]),
    ];
    await _pump(tester, drafts, phrase: PhraseStructure.parse('4*12*2'));
    await _open(tester, 0);

    expect(find.byKey(const ValueKey('figure-0-add-side')), findsOneWidget);
  });

  testWidgets('"Group with next as sequence" is offered only when it fits', (
    tester,
  ) async {
    final drafts = [
      _step('balance', 4),
      _step('swing', 12),
      _step('swing', 16),
    ];
    await _pump(tester, drafts);

    await tester.tap(find.byKey(const ValueKey('figure-1-menu')));
    await tester.pumpAndSettle();
    // 12 + 16 beats is longer than a phrase; a meanwhile is still offered.
    expect(
      find.byKey(const ValueKey('figure-1-group-with-next-sequence')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('figure-1-group-with-next')), findsOne);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-group-with-next-sequence')),
    );
    await tester.pumpAndSettle();

    expect(drafts, hasLength(2));
    expect(drafts.first.isSequenceGroup, isTrue);
    expect(drafts.first.beats, 16);
  });

  testWidgets('a meanwhile side can become a sequence', (tester) async {
    final drafts = [
      FigureDraft(meanwhileSides: [_step('balance', 4), _step('orbit', 8)])
        ..params['beats'] = 8,
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('figure-0-side-0-move-option-sequence')),
    );
    await tester.pumpAndSettle();

    final side = drafts.single.meanwhileSides!.first;
    expect(side.isSequenceGroup, isTrue);
    expect(side.sequenceFigures!.first.move, 'balance');
  });

  testWidgets('a sequence step cannot become another sequence', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('balance', 4), _step('swing', 8)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-move-input')),
      'seq',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('figure-0-side-0-move-option-sequence')),
      findsNothing,
    );
  });
}
