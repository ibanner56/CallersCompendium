import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_app/src/widgets/bar_timing.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// A square's sequence in [FigureListEditor] may state its own span in beats
/// (ADR-007 Q10, opened to squares by the maintainer on 23 November 2026),
/// as an English dance's does in bars: "forward again and swing the
/// opposite (8)" gives one count for two calls.
class _Host extends StatefulWidget {
  const _Host({required this.drafts, required this.spans});

  final List<FigureDraft> drafts;

  /// Whether the dance's sequences may state a span ([SequenceSpanScope]).
  final bool spans;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    final editor = FigureListEditor(
      drafts: widget.drafts,
      taxonomy: shippedTaxonomies.forForm(DanceForm.square),
      phraseStructure: PhraseStructure.standard,
      onChanged: () => setState(() {}),
      onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
      onDelete: (d) => setState(() => widget.drafts.remove(d)),
    );
    return MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: widget.spans ? SequenceSpanScope(child: editor) : editor,
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  List<FigureDraft> drafts, {
  bool spans = true,
}) async {
  const size = Size(1200, 2400);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(_Host(drafts: drafts, spans: spans));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
  await tester.pumpAndSettle();
}

FigureDraft _step(String move, int beats) =>
    FigureDraft(move: move, params: {'beats': beats}, beatsTouched: true);

/// "Forward again and swing the opposite": a forward and back and a swing.
FigureDraft _forwardAgainAndSwing() => FigureDraft(
  sequenceFigures: [_step('sq_forward_and_back', 8), _step('sq_swing', 8)],
);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  testWidgets("a square's sequence states its span in beats, and a step can "
      'leave its beats empty', (tester) async {
    final drafts = [_forwardAgainAndSwing()];
    await _pump(tester, drafts);

    // With no span, the sequence adds up its steps, as contra's does.
    expect(find.text('Beats for all'), findsOneWidget);
    expect(_fieldText(tester, 'figure-0-sequence-span'), '');
    expect(drafts.single.beats, 16);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-sequence-span')),
      '8',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceSpanStated, isTrue);
    expect(drafts.single.beats, 8);
    expect(
      find.text(
        'The steps share these beats, and each may leave its own beats '
        'empty.',
      ),
      findsOneWidget,
    );
    // Both steps still state 8, so they overrun the span.
    expect(
      find.text('The steps take 16 beats, but the sequence takes 8 beats.'),
      findsOneWidget,
    );

    // Each step's beats emptied: no timing of its own.
    for (final side in [0, 1]) {
      await tester.enterText(
        find.byKey(ValueKey('figure-0-side-$side-beats')),
        '',
      );
      await tester.pumpAndSettle();
    }
    expect(drafts.single.sequenceFigures!.every((s) => s.untimed), isTrue);
    expect(
      find.byKey(const ValueKey('figure-0-sequence-span-mismatch')),
      findsNothing,
    );
    final built = drafts.single.toFigure()!;
    expect(built.beats, 8);
    expect(built.subFigures.any(stepStatesTiming), isFalse);
    expect(sequenceSpanIssue(built, DanceForm.square), isNull);
  });

  testWidgets('a timed step that fills the span leaves none for the rest', (
    tester,
  ) async {
    final drafts = [_forwardAgainAndSwing()..setSequenceSpan(8)];
    drafts.single.sequenceFigures![1].params.remove('beats');
    await _pump(tester, drafts);

    expect(_fieldText(tester, 'figure-0-sequence-span'), '8');
    expect(_fieldText(tester, 'figure-0-side-1-beats'), '');
    expect(
      find.text(
        "The steps with beats of their own take 8 beats of the sequence's "
        '8 beats, leaving none for the rest.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a count out of range is refused and kept as it was', (
    tester,
  ) async {
    final drafts = [_forwardAgainAndSwing()..setSequenceSpan(8)];
    await _pump(tester, drafts);

    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-beats')),
      '99',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceFigures![0].params['beats'], 8);
    expect(find.text('Enter a whole number from 0 to 64'), findsOneWidget);

    // Clearing the span counts the steps again.
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-sequence-span')),
      '',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceSpanStated, isFalse);
    expect(drafts.single.beats, 16);
  });

  testWidgets('without spans, a sequence shows the total of its steps', (
    tester,
  ) async {
    final drafts = [_forwardAgainAndSwing()];
    await _pump(tester, drafts, spans: false);

    expect(find.byKey(const ValueKey('figure-0-sequence-span')), findsNothing);
    expect(
      find.byKey(const ValueKey('figure-0-sequence-beats')),
      findsOneWidget,
    );
  });
}
