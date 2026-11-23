import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #2303: a dance whose phrases differ in beats per bar counts each bar by the
/// phrase it starts in, from where the figure starts.
void main() {
  // A1 and A2 are 4 bars of 3 beats (beats 0-24), B is 8 bars of 2 (24-40).
  final timing = BarTiming.byPhrase(PhraseStructure.parse('A:2*4*3 + B:1*8*2'));

  group('PhraseStructure.hasMixedMeter', () {
    test('is true only where the components differ in beats per bar', () {
      expect(PhraseStructure.parse('A:2*4*3 + B:1*8*2').hasMixedMeter, isTrue);
      expect(PhraseStructure.parse('2*8*3 + 2*8*2').hasMixedMeter, isTrue);
      expect(PhraseStructure.parse('A:2*4*3 + B:1*8*3').hasMixedMeter, isFalse);
      expect(PhraseStructure.standard.hasMixedMeter, isFalse);
    });
  });

  group('barTimingForMixedMeter', () {
    test('counts by phrase only an English dance whose phrases differ', () {
      final mixed = PhraseStructure.parse('A:2*4*3 + B:1*8*2');
      expect(barTimingForMixedMeter(DanceForm.ecd, mixed), timing);
      expect(barTimingForMixedMeter(DanceForm.contra, mixed), isNull);
      expect(
        barTimingForMixedMeter(
          DanceForm.ecd,
          PhraseStructure.parse('A:2*4*3 + B:1*8*3'),
        ),
        isNull,
      );
      expect(
        barTimingForMixedMeter(DanceForm.ecd, PhraseStructure.standard),
        isNull,
      );
    });
  });

  test('only one bar length for the whole tune is fixed', () {
    expect(const BarTiming.fixed(3).isFixed, isTrue);
    expect(timing.isFixed, isFalse);
  });

  group('BarTiming.beatsPerBarAt', () {
    test('is the beats per bar of the phrase the bar starts in', () {
      expect(
        [
          for (final b in [0, 23, 24, 39]) timing.beatsPerBarAt(b),
        ],
        [3, 3, 2, 2],
      );
    });

    test('wraps at the end of the structure, as phrase labels do', () {
      expect(timing.beatsPerBarAt(40), 3);
      expect(timing.beatsPerBarAt(64), 2);
    });
  });

  group('BarTiming.beatsForHalfBars', () {
    test('counts each phrase\'s bars by its own beats per bar', () {
      expect(timing.beatsForHalfBars(0, 8), 12, reason: 'bars 1-4, in A1');
      expect(timing.beatsForHalfBars(12, 8), 12, reason: 'bars 5-8, in A2');
      expect(timing.beatsForHalfBars(24, 8), 8, reason: 'bars 9-12, in B');
    });

    test('a figure that runs across the change counts each bar by its own '
        'phrase', () {
      // Bars at 18 (3), 21 (3), 24 (2), 26 (2).
      expect(timing.beatsForHalfBars(18, 8), 10);
      expect(timing.beatsForHalfBars(18, 6), 8);
    });

    test('half a bar only where it is a whole number of beats', () {
      expect(timing.beatsForHalfBars(0, 1), isNull, reason: 'triple time');
      expect(timing.beatsForHalfBars(24, 1), 1);
      // Two bars of 3 beats, then a half bar of the 2-beat phrase.
      expect(timing.beatsForHalfBars(18, 5), 7);
    });

    test('wraps past the end of the structure', () {
      // Bars at 36 (2), 38 (2), 40 -> 0 (3), 43 (3).
      expect(timing.beatsForHalfBars(36, 8), 10);
    });

    test('refuses a negative start or count', () {
      expect(() => timing.beatsForHalfBars(-1, 2), throwsArgumentError);
      expect(() => timing.beatsForHalfBars(0, -1), throwsArgumentError);
    });
  });

  group('BarTiming.barsTextAt', () {
    test('reads beats back as bars of the phrase they start in', () {
      expect(timing.barsTextAt(0, 12), (text: '4', halfBars: 8));
      expect(timing.barsTextAt(24, 8), (text: '4', halfBars: 8));
      expect(timing.barsTextAt(0, 0), (text: '0', halfBars: 0));
    });

    test('a figure across the change reads as the bars it spans', () {
      expect(timing.barsTextAt(18, 10), (text: '4', halfBars: 8));
      expect(timing.barsTextAt(18, 8), (text: '3', halfBars: 6));
      expect(timing.barsTextAt(18, 9), (text: '3½', halfBars: 7));
    });

    test('beats that are not a whole number of half bars stay beats', () {
      expect(timing.barsTextAt(0, 4), isNull);
      expect(timing.barsTextAt(18, 5), isNull);
    });

    test('is the inverse of beatsForHalfBars from every start', () {
      for (var start = 0; start < 90; start++) {
        for (var halfBars = 0; halfBars <= 24; halfBars++) {
          final beats = timing.beatsForHalfBars(start, halfBars);
          if (beats == null) continue;
          expect(
            timing.barsTextAt(start, beats)?.halfBars,
            halfBars,
            reason: 'from $start, $halfBars half bars are $beats beats',
          );
        }
      }
    });

    test('from a start between bar lines, bars are counted from the start', () {
      // Beat 22 is not on a bar line (A2's bars start at 21 and 24). The bar
      // counted from there is A's 3 beats, so it runs 22-25 across the
      // change, and the next bar is B's.
      expect(timing.beatsForHalfBars(22, 2), 3);
      expect(timing.beatsForHalfBars(22, 4), 5);
      expect(timing.barsTextAt(22, 3), (text: '1', halfBars: 2));
      expect(timing.barsTextAt(22, 5), (text: '2', halfBars: 4));
    });
  });

  group('BarTiming.maxBarsWithin', () {
    test('is as many whole bars as fit in the beats, from the start', () {
      // Bars at 18 (3), 21 (3), 24 (2), 26 (2): 10 beats are 4 bars.
      expect(timing.maxBarsWithin(18, 10), 4);
      expect(timing.maxBarsWithin(18, 9), 3);
      expect(timing.maxBarsWithin(24, 5), 2);
      expect(timing.maxBarsWithin(0, 64), greaterThan(20));
    });

    test('is the beats over the bar for one bar length', () {
      for (var perBar = 1; perBar <= 12; perBar++) {
        for (var start = 0; start < 12; start++) {
          for (var beats = 0; beats <= 64; beats++) {
            expect(
              BarTiming.fixed(perBar).maxBarsWithin(start, beats),
              beats ~/ perBar,
              reason: '$beats beats of $perBar from $start',
            );
          }
        }
      }
    });
  });

  group('BarTiming.doubledBeatsForHalfBars', () {
    test('counts a half bar even where it is not a whole number of beats', () {
      expect(timing.doubledBeatsForHalfBars(0, 1), 3);
      expect(timing.doubledBeatsForHalfBars(0, 8), 24);
      // Two bars of 3, then half a bar of the 2-beat phrase.
      expect(timing.doubledBeatsForHalfBars(18, 5), 14);
    });

    test('is the half bars times the bar for one bar length', () {
      for (var perBar = 1; perBar <= 12; perBar++) {
        for (var halfBars = 0; halfBars <= 30; halfBars++) {
          expect(
            BarTiming.fixed(perBar).doubledBeatsForHalfBars(5, halfBars),
            halfBars * perBar,
            reason: '$halfBars half bars of $perBar',
          );
        }
      }
    });
  });

  group('BarTiming.beatsPerBarOfHalfAt', () {
    test('is the bar the last half bar falls in', () {
      expect(timing.beatsPerBarOfHalfAt(18, 1), 3);
      // Two whole bars from 18 end at 24, where the half bar is B's.
      expect(timing.beatsPerBarOfHalfAt(18, 5), 2);
      expect(timing.beatsPerBarOfHalfAt(0, 1), 3);
      expect(timing.beatsPerBarOfHalfAt(24, 3), 2);
    });
  });

  group('barTimingFor', () {
    final mixed = PhraseStructure.parse('A:2*4*3 + B:1*8*2');

    test('counts a tune whose phrases differ by phrase, whatever the Meter '
        'states', () {
      for (final meter in ['', '3/4', '3/4 and 6/8', 'a jig']) {
        expect(
          barTimingFor(DanceForm.ecd, mixed, meter: meter),
          timing,
          reason: 'Meter "$meter"',
        );
      }
    });

    test('counts a tune in one meter by one bar length, as it always has', () {
      expect(
        barTimingFor(DanceForm.ecd, PhraseStructure.parse('4*8*3')),
        const BarTiming.fixed(3),
      );
      expect(
        barTimingFor(
          DanceForm.ecd,
          PhraseStructure.parse('4*8*3'),
          meter: '6/8',
        ),
        const BarTiming.fixed(2),
      );
      expect(
        barTimingFor(DanceForm.ecd, PhraseStructure.standard),
        const BarTiming.fixed(2),
      );
    });

    test('leaves any other form in beats', () {
      expect(barTimingFor(DanceForm.contra, mixed), isNull);
      expect(barTimingFor(DanceForm.contra, PhraseStructure.standard), isNull);
    });
  });

  group('PhraseStructure.longestPhraseStart', () {
    test('is where the longest phrase starts', () {
      // A is 12 beats, B is 16.
      expect(PhraseStructure.parse('A:2*4*3 + B:1*8*2').longestPhraseStart, 24);
      expect(PhraseStructure.parse('A:1*8*2 + B:1*4*2').longestPhraseStart, 0);
      expect(PhraseStructure.standard.longestPhraseStart, 0);
    });

    test('is the first of phrases tied for longest that agree in bars', () {
      expect(PhraseStructure.parse('A:1*8*2 + B:1*8*2').longestPhraseStart, 0);
    });

    test('is null where phrases tied for longest differ in bars', () {
      // Both are 16 beats: 8 bars of 2, and 4 bars of 4.
      expect(
        PhraseStructure.parse('A:1*8*2 + B:1*4*4').longestPhraseStart,
        isNull,
      );
    });
  });

  group('childStartBeats', () {
    Figure step(int beats) => customFigure('x', beats: beats);

    test('a sequence\'s steps follow one another', () {
      final sequence = Figure.sequence(
        figures: [step(10), step(6), step(4)],
        beats: 20,
      );
      expect(childStartBeats(sequence, 18), [18, 28, 34]);
    });

    test('a meanwhile\'s sides and a modifier\'s parts start with it', () {
      final meanwhile = Figure.meanwhile(figures: [step(6), step(6)], beats: 6);
      expect(childStartBeats(meanwhile, 18), [18, 18]);
      final modifier = Figure.modifier(figures: [step(6), step(0)], beats: 6);
      expect(childStartBeats(modifier, 18), [18, 18]);
    });
  });

  group('the phrase warnings carry where they start', () {
    // A is 12 beats (A1, A2 of 4 bars of 3), B is 8 (4 bars of 2).
    final structure = PhraseStructure.parse('A:2*4*3 + B:1*4*2');

    Figure step(int beats) => customFigure('x', beats: beats);

    test('a sequence longer than a phrase has its start and its limit\'s', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [
          step(6),
          Figure.sequence(figures: [step(7), step(7)], beats: 14),
        ],
        structure,
        issues: issues,
      );
      final issue = issues.singleWhere(
        (i) => i.code == 'sequence_exceeds_phrase',
      );
      expect(issue.data['startBeat'], 6);
      expect(issue.data['limit'], 12);
      expect(issue.data['limitStart'], 0);
    });

    test('a sequence inside a meanwhile starts with the meanwhile', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [
          step(20),
          Figure.meanwhile(
            figures: [
              Figure.sequence(figures: [step(7), step(7)], beats: 14),
              step(14),
            ],
            beats: 14,
          ),
        ],
        structure,
        issues: issues,
      );
      final issue = issues.singleWhere(
        (i) => i.code == 'sequence_exceeds_phrase',
      );
      expect(issue.data['startBeat'], 20);
    });
  });

  group('BarTiming.fixed', () {
    test('reads and counts as one bar length wherever the figure starts', () {
      for (var perBar = 1; perBar <= 12; perBar++) {
        final fixed = BarTiming.fixed(perBar);
        for (var start = 0; start < 30; start++) {
          for (var beats = 0; beats <= 60; beats++) {
            final doubled = beats * 2;
            final expected = doubled % perBar == 0
                ? (text: barsText(beats, perBar)!, halfBars: doubled ~/ perBar)
                : null;
            expect(
              fixed.barsTextAt(start, beats),
              expected,
              reason: '$beats beats in bars of $perBar from $start',
            );
          }
          for (var halfBars = 0; halfBars <= 20; halfBars++) {
            final doubled = halfBars * perBar;
            expect(
              fixed.beatsForHalfBars(start, halfBars),
              doubled.isEven ? doubled ~/ 2 : null,
              reason: '$halfBars half bars of $perBar',
            );
          }
        }
      }
    });
  });
}
