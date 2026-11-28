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
    this.structure,
  });

  final List<FigureDraft> drafts;
  final int beatsPerBar;
  final bool aggressiveBeats;

  /// A tune whose phrases differ in beats per bar (#2303), timed by phrase;
  /// else one of [beatsPerBar] beats a bar.
  final PhraseStructure? structure;

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
            timing: widget.structure == null
                ? BarTiming.fixed(widget.beatsPerBar)
                : BarTiming.byPhrase(widget.structure!),
            child: SequenceSpanScope(
              child: FigureListEditor(
                drafts: widget.drafts,
                taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
                phraseStructure:
                    widget.structure ??
                    PhraseStructure.parse('4*8*${widget.beatsPerBar}'),
                onChanged: () => setState(() {}),
                onAdd: () => setState(() => widget.drafts.add(FigureDraft())),
                onDelete: (d) => setState(() => widget.drafts.remove(d)),
              ),
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
  PhraseStructure? structure,
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
      structure: structure,
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
    expect(sequenceSpanIssue(built, DanceForm.ecd), isNull);
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

  testWidgets('in one bar length, a step\'s half-typed bars survive an edit '
      'to the step before it', (tester) async {
    // 3 beats to the bar: half a bar is refused, and the text stays to fix.
    final drafts = [
      FigureDraft(sequenceFigures: [_step('ecd_lead', 6), _step('ecd_set', 6)]),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-1-beats')),
      '2.5',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-side-0-beats')),
      '3',
    );
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceFigures!.first.beats, 9);
    expect(_fieldText(tester, 'figure-0-side-1-beats'), '2.5');
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
    // And tapping it adds the step: only the timed steps count toward the
    // phrase, for the button and for what it does alike.
    await tester.tap(find.byKey(const ValueKey('figure-0-add-side')));
    await tester.pumpAndSettle();
    expect(drafts.single.sequenceFigures, hasLength(3));
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

  group('a tune whose phrases differ in beats per bar (#2303)', () {
    // A1 and A2 are 4 bars of 3 beats (0-24), B is 8 bars of 2 (24-40).
    final structure = PhraseStructure.parse('A:2*4*3 + B:1*8*2');

    testWidgets('a figure whose start moves reads its count from the new '
        'start', (tester) async {
      final drafts = [
        _step('ecd_lead', 12),
        _step('ecd_lead', 12),
        _step('ecd_lead', 8),
      ];
      await _pump(tester, drafts, structure: structure);
      await _open(tester, 2);
      expect(_fieldText(tester, 'figure-2-beats'), '4');

      // The first figure shortens by 2 beats: the third now starts at 22, in
      // a bar of 3 that runs on into B, and its 8 beats are 3½ bars. The open
      // field reads that, not the 4 it showed from 24.
      drafts.first.params['beats'] = 10;
      await _pump(tester, drafts, structure: structure);
      expect(_fieldText(tester, 'figure-2-beats'), '3½');
    });

    testWidgets('a step starts where the steps before it end', (tester) async {
      // 18 beats of other figures put the sequence at the end of A2: its
      // first step runs 18-24 and the next starts in B, in bars of 2.
      final drafts = [
        _step('ecd_lead', 18),
        FigureDraft(
          sequenceFigures: [_step('ecd_lead', 6), _step('ecd_set', 4)],
        ),
      ];
      await _pump(tester, drafts, structure: structure);
      await _open(tester, 1);
      expect(_fieldText(tester, 'figure-1-side-0-beats'), '2');
      expect(_fieldText(tester, 'figure-1-side-1-beats'), '2');
    });

    testWidgets('a sequence longer than a phrase reads the phrase in its own '
        'bars', (tester) async {
      // 18 beats of other figures put the sequence late in A2: its 20 beats
      // are 9 bars (3, 3 then 7 of 2). Its limit is A2, the phrase it starts
      // in: 12 beats, or 4 bars of 3 read from A2's start at 12. Read from the
      // sequence's own start, 12 beats would be 5 bars (2 of 3, then 3 of 2).
      final drafts = [
        _step('ecd_lead', 18),
        FigureDraft(
          sequenceFigures: [_step('ecd_lead', 10), _step('ecd_set', 10)],
        )..setSequenceSpan(20),
      ];
      await _pump(tester, drafts, structure: structure);
      await _open(tester, 1);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('figure-1-sequence-over-phrase')),
            )
            .data,
        'This sequence is 9 bars, longer than its phrase (4 bars).',
      );
    });

    testWidgets('a sequence in B reads B\'s length in B\'s bars', (
      tester,
    ) async {
      // A is 8 bars of 2 and B 4 bars of 4, both 16 beats. From 16, in B, the
      // sequence's 20 beats are 4 bars of 4 and then, back in A, 2 bars of 2.
      final ab = PhraseStructure.parse('A:1*8*2 + B:1*4*4');
      final drafts = [
        _step('ecd_lead', 16),
        FigureDraft(
          sequenceFigures: [_step('ecd_lead', 10), _step('ecd_set', 10)],
        )..setSequenceSpan(20),
      ];
      await _pump(tester, drafts, structure: ab);
      await _open(tester, 1);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('figure-1-sequence-over-phrase')),
            )
            .data,
        'This sequence is 6 bars, longer than its phrase (4 bars).',
      );
    });

    testWidgets('a group nested in a sequence starts where the steps before '
        'it end', (tester) async {
      // The sequence starts at 18; its first step ends at 24, where the group
      // starts, and its 4 beats are 2 bars of 2 there.
      final group = FigureDraft(
        meanwhileSides: [_step('ecd_lead', 4), _step('ecd_set', 4)],
        params: {'beats': 4},
      );
      final drafts = [
        _step('ecd_lead', 18),
        FigureDraft(sequenceFigures: [_step('ecd_lead', 6), group]),
      ];
      await _pump(tester, drafts, structure: structure);
      await _open(tester, 1);
      await tester.tap(
        find.byKey(const ValueKey('figure-1-nested-1-0-summary')),
      );
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'figure-1-nested-1-0-meanwhile-beats'), '2');
    });

    testWidgets('the field reads a count anew when the tune it is in changes', (
      tester,
    ) async {
      // 6 beats from the start: 2 bars of 3, then, in 2, 3 bars.
      final drafts = [_step('ecd_lead', 6)];
      await _pump(tester, drafts);
      await _open(tester, 0);
      expect(_fieldText(tester, 'figure-0-beats'), '2');
      await _pump(tester, drafts, beatsPerBar: 2);
      expect(_fieldText(tester, 'figure-0-beats'), '3');
    });

    testWidgets('half a bar is refused by the bar it falls in', (tester) async {
      // 12 + 12 + 8 + 4 beats put the fifth figure at 36, in a bar of 2: two
      // and a half bars from there end in the first bar of the next time
      // through, of 3 beats, so the half is refused there.
      final drafts = [
        _step('ecd_lead', 12),
        _step('ecd_lead', 12),
        _step('ecd_lead', 8),
        _step('ecd_lead', 4),
        _step('ecd_lead', 4),
      ];
      await _pump(tester, drafts, structure: structure);
      await _open(tester, 4);
      await tester.enterText(
        find.byKey(const ValueKey('figure-4-beats')),
        '2.5',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Whole bars only, with 3 beats to the bar'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a sequence longer than a phrase reads the message in beats '
      'where its count is not whole bars, so the two are never mixed', (
    tester,
  ) async {
    // A stated span of 25 beats (entered in beats, or imported) is no whole
    // number of half bars in 3/4, while the phrase of 24 beats is 8 bars.
    final drafts = [
      FigureDraft(
        sequenceFigures: [_step('ecd_lead', 12), _step('ecd_set', 12)],
      )..setSequenceSpan(25),
    ];
    await _pump(tester, drafts);
    await _open(tester, 0);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('figure-0-sequence-over-phrase')),
          )
          .data,
      'This sequence is 25 beats, longer than its phrase (24 beats).',
    );
  });

  group('the Bars field reads and refuses a count as it always did for a tune '
      'in one meter', () {
    // What the field did with one bar length, frozen here: the largest count
    // (64 beats over the bar), a count past it, and the half bar.
    String? oldError(int perBar, String text) {
      const maxBeats = 64;
      final halfBars = parseHalfBars(text);
      if (text.trim().isEmpty ||
          halfBars == null ||
          halfBars * perBar > maxBeats * 2) {
        return 'Enter whole or half bars, up to ${maxBeats ~/ perBar}';
      }
      return (halfBars * perBar).isEven
          ? null
          : 'Whole bars only, with $perBar beats to the bar';
    }

    for (final perBar in [2, 3, 4, 6]) {
      testWidgets('of $perBar beats a bar', (tester) async {
        final drafts = [_step('ecd_lead', perBar * 2)];
        await _pump(tester, drafts, beatsPerBar: perBar);
        await _open(tester, 0);
        for (final text in [
          '',
          'x',
          '0',
          '1',
          '2',
          '1.5',
          '2½',
          '21',
          '22',
          '33',
          '99',
        ]) {
          await tester.enterText(
            find.byKey(const ValueKey('figure-0-beats')),
            text,
          );
          await tester.pumpAndSettle();
          final error = oldError(perBar, text);
          for (final message in [
            'Enter whole or half bars, up to ${64 ~/ perBar}',
            'Whole bars only, with $perBar beats to the bar',
          ]) {
            expect(
              find.text(message),
              message == error ? findsOneWidget : findsNothing,
              reason: '"$text" of $perBar: $message',
            );
          }
        }
      });
    }
  });

  group('pre-release audit findings A2-04, GAPE-02 and GAPE-03', () {
    testWidgets('a figure row is announced in the bars it shows', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_step('ecd_lead', 12)]);
      expect(find.text('4 bars'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'\b4 bars\b.*Figure 1 of 1')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'\b12 beats\b')), findsNothing);
      handle.dispose();
    });

    testWidgets('the running total and the difference are in bars', (
      tester,
    ) async {
      await _pump(tester, [_step('ecd_lead', 12), _step('ecd_set', 12)]);
      expect(find.text('Total: 8 / 32 bars'), findsOneWidget);
      expect(find.text('Under by 24 bars'), findsOneWidget);
      expect(find.textContaining('beats'), findsNothing);
    });

    testWidgets('a total over by half a bar says so in bars', (tester) async {
      await _pump(tester, [
        for (var i = 0; i < 8; i++) _step('ecd_lead', 8),
        _step('ecd_set', 1),
      ], beatsPerBar: 2);
      expect(find.text('Total: 32½ / 32 bars'), findsOneWidget);
      expect(find.text('Over by ½ bar'), findsOneWidget);
    });

    testWidgets('a total that is no whole number of half bars stays in '
        'beats', (tester) async {
      await _pump(tester, [_step('ecd_lead', 13)]);
      expect(find.text('Total: 13 / 96 beats'), findsOneWidget);
      expect(find.text('Under by 83 beats'), findsOneWidget);
    });

    testWidgets('a sequence\'s span refuses 0 bars and keeps its count', (
      tester,
    ) async {
      final drafts = [
        FigureDraft(
          sequenceFigures: [_step('ecd_lead', 6), _step('ecd_set', 6)],
        )..setSequenceSpan(12),
      ];
      await _pump(tester, drafts);
      await _open(tester, 0);

      await tester.enterText(
        find.byKey(const ValueKey('figure-0-sequence-span')),
        '0',
      );
      await tester.pumpAndSettle();
      expect(drafts.single.beats, 12);
      expect(find.text('Enter whole or half bars, up to 21'), findsOneWidget);
    });
  });
}
