import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/bar_timing.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// An English dance's figures in [FigureListEditor], timed in bars
/// (ADR-006 §5.5): bars in and out, the half-bar rule (Q16), and a
/// sequence's own span with steps that carry no timing.
class _Host extends StatefulWidget {
  const _Host({
    required this.drafts,
    required this.beatsPerBar,
    this.aggressiveBeats = false,
  });

  final List<FigureDraft> drafts;
  final int beatsPerBar;
  final bool aggressiveBeats;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final _aggressive = ValueNotifier(widget.aggressiveBeats);

  @override
  void dispose() {
    _aggressive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: AggressiveBeatsUpdateScope(
      notifier: _aggressive,
      child: Scaffold(
        body: SingleChildScrollView(
          child: BarTimingScope(
            beatsPerBar: widget.beatsPerBar,
            child: FigureListEditor(
              drafts: widget.drafts,
              taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
              phraseStructure: PhraseStructure.parse(
                '4*8*${widget.beatsPerBar}',
              ),
              onChanged: () => setState(() {}),
              onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
              onDelete: (d) => setState(() => widget.drafts.remove(d)),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  int beatsPerBar = 3,
  bool aggressiveBeats = false,
}) async {
  const size = Size(1200, 2400);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    _Host(
      drafts: drafts,
      beatsPerBar: beatsPerBar,
      aggressiveBeats: aggressiveBeats,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
  // An ECD movement lists its count after its other parameters.
  final more = find.byKey(ValueKey('figure-$index-more-options'));
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
}

FigureDraft _step(String move, int beats) =>
    FigureDraft(move: move, params: {'beats': beats}, beatsTouched: true);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  testWidgets('a figure shows and takes its count in bars', (tester) async {
    final drafts = [_step('ecd_lead', 6)];
    await _pump(tester, drafts);

    // Bars out: the summary and the field.
    expect(find.text('2 bars'), findsOneWidget);
    await _open(tester, 0);
    expect(_fieldText(tester, 'figure-0-beats'), '2');

    // Bars in, stored as beats.
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '4');
    await tester.pumpAndSettle();
    expect(drafts.single.params['beats'], 12);
    expect(find.text('4 bars'), findsWidgets);
  });

  testWidgets('half a bar is refused in triple time and taken in duple', (
    tester,
  ) async {
    final drafts = [_step('ecd_lead', 6)];
    await _pump(tester, drafts);
    await _open(tester, 0);

    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '1.5');
    await tester.pumpAndSettle();
    expect(drafts.single.params['beats'], 6, reason: 'nothing reported');
    expect(
      find.text('Whole bars only, with 3 beats to the bar'),
      findsOneWidget,
    );

    final duple = [_step('ecd_lead', 4)];
    await _pump(tester, duple, beatsPerBar: 2);
    await _open(tester, 0);
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '1½');
    await tester.pumpAndSettle();
    expect(duple.single.params['beats'], 3);
    expect(find.text('1½ bars'), findsWidgets);
  });

  testWidgets('a sequence states its own span, and a step can leave its '
      'bars empty', (tester) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('ecd_lead', 6), _step('ecd_set', 6)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    // With no span, the sequence adds up its steps, as contra's does.
    expect(_fieldText(tester, 'figure-0-sequence-span'), '');
    expect(drafts.single.beats, 12);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-sequence-span')),
      '4',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceSpanStated, isTrue);
    expect(drafts.single.beats, 12);

    // A step's bars emptied: no timing of its own.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-1-beats')),
      '',
    );
    await tester.pumpAndSettle();
    final step = drafts.single.sequenceFigures![1];
    expect(step.untimed, isTrue);
    final built = drafts.single.toFigure()!;
    expect(built.beats, 12);
    expect(stepStatesTiming(built.subFigures[1]), isFalse);
    expect(ecdSequenceSpanIssue(built, DanceForm.ecd), isNull);
  });

  testWidgets('steps that do not add up to the span are flagged', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(sequenceFigures: [_step('ecd_lead', 6), _step('ecd_set', 6)])
        ..setSequenceSpan(18),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);

    expect(_fieldText(tester, 'figure-0-sequence-span'), '6');
    expect(
      find.byKey(const ValueKey('figure-0-sequence-span-mismatch')),
      findsOneWidget,
    );
    expect(
      find.text('The steps take 4 bars, but the sequence takes 6 bars.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-sequence-span')),
      '4',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('figure-0-sequence-span-mismatch')),
      findsNothing,
    );
  });

  testWidgets('an emptied bars field says so and keeps its count', (
    tester,
  ) async {
    final drafts = [_step('ecd_lead', 6)];
    await _pump(tester, drafts);
    await _open(tester, 0);

    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '');
    await tester.pumpAndSettle();
    expect(drafts.single.params['beats'], 6);
    expect(find.text('Enter whole or half bars, up to 21'), findsOneWidget);
  });

  testWidgets('a span that fills the phrase still takes an untimed step', (
    tester,
  ) async {
    final drafts = [
      FigureDraft(
        sequenceFigures: [
          _step('ecd_lead', 6),
          FigureDraft(move: 'ecd_set', beatsTouched: true),
        ],
      )..setSequenceSpan(24),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    expect(find.byKey(const ValueKey('figure-0-add-side')), findsOneWidget);
  });

  testWidgets('a group inside a spanned sequence keeps a count of its own', (
    tester,
  ) async {
    final group = FigureDraft(
      meanwhileSides: [_step('ecd_lead', 6), _step('ecd_set', 6)],
      params: {'beats': 6},
    );
    final drafts = [
      FigureDraft(sequenceFigures: [_step('ecd_lead', 6), group])
        ..setSequenceSpan(12),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.tap(find.byKey(const ValueKey('figure-0-nested-1-0-summary')));
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('figure-0-nested-1-0-meanwhile-beats'),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(group.params['beats'], 6, reason: 'an empty count is refused');
    expect(find.text('Enter whole or half bars, up to 21'), findsOneWidget);
  });

  testWidgets('an untimed step stays untimed when another parameter '
      'changes', (tester) async {
    // A contra swing kept in an English dance: its prefix moves its default
    // count, which aggressive beats would write over a count the caller set,
    // but an untimed step has none to write over.
    final untimed = FigureDraft(move: 'swing', beatsTouched: true);
    final drafts = [
      FigureDraft(sequenceFigures: [_step('ecd_lead', 6), untimed])
        ..setSequenceSpan(12),
    ];
    await _pump(tester, drafts, aggressiveBeats: true);
    await _open(tester, 0);

    final prefix = find.byKey(const ValueKey('figure-0-side-1-prefix'));
    await tester.ensureVisible(prefix);
    await tester.tap(prefix);
    await tester.pumpAndSettle();
    await tester.tap(find.text('balance').last);
    await tester.pumpAndSettle();
    expect(untimed.params['prefix'], 'balance');
    expect(untimed.untimed, isTrue);
  });
}
