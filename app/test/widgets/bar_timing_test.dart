import 'package:compendium_app/src/widgets/bar_timing.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('barsText', () {
    test('whole and half bars', () {
      expect(barsText(8, 2), '4');
      expect(barsText(3, 2), '1½');
      expect(barsText(1, 2), '½');
      expect(barsText(6, 3), '2');
    });

    test('a count that is no whole number of half bars has none', () {
      expect(barsText(1, 3), isNull);
      expect(barsText(4, 3), isNull);
    });
  });

  group('parseHalfBars', () {
    test('reads whole bars and the ways a half is written', () {
      expect(parseHalfBars('4'), 8);
      expect(parseHalfBars('1.5'), 3);
      expect(parseHalfBars('1,5'), 3);
      expect(parseHalfBars('1½'), 3);
      expect(parseHalfBars('1 1/2'), 3);
      expect(parseHalfBars('½'), 1);
      expect(parseHalfBars(' 2 '), 4);
    });

    test('reads nothing else', () {
      for (final text in ['', '1.25', 'two', '-1', '1.5.5', '½½']) {
        expect(parseHalfBars(text), isNull, reason: text);
      }
    });
  });

  group('BarTimingScope.beatsPerBarFor', () {
    test('an English dance in one meter is timed in its bars', () {
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.parse('3*8*3'),
        ),
        3,
      );
    });

    test('a stated meter is the rule; with none, the phrase structure', () {
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.standard,
          meter: '3/2',
        ),
        3,
      );
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.parse('4*8*3'),
          meter: '6/8',
        ),
        2,
      );
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.parse('4*8*3'),
          meter: 'a jig',
        ),
        3,
      );
      // A tune whose parts differ stays in beats, whatever the meter says.
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.parse('2*8*3+2*8*2'),
          meter: '3/4',
        ),
        isNull,
      );
    });

    test('contra, and a tune whose parts differ in meter, keep beats', () {
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.contra,
          PhraseStructure.parse('3*8*3'),
        ),
        isNull,
      );
      expect(
        BarTimingScope.beatsPerBarFor(
          DanceForm.ecd,
          PhraseStructure.parse('2*8*3+2*8*2'),
        ),
        isNull,
      );
    });
  });
}
