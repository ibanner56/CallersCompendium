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

  group('barTimingFor', () {
    const ecd = DanceForm.ecd;

    test('an English dance in one meter is timed in its bars', () {
      expect(
        barTimingFor(ecd, PhraseStructure.parse('3*8*3')),
        const BarTiming.fixed(3),
      );
    });

    test('a stated meter is the rule; with none, the phrase structure', () {
      expect(
        barTimingFor(ecd, PhraseStructure.standard, meter: '3/2'),
        const BarTiming.fixed(3),
      );
      expect(
        barTimingFor(ecd, PhraseStructure.parse('4*8*3'), meter: '6/8'),
        const BarTiming.fixed(2),
      );
      expect(
        barTimingFor(ecd, PhraseStructure.parse('4*8*3'), meter: 'a jig'),
        const BarTiming.fixed(3),
      );
    });

    test('a tune whose parts differ is timed by phrase, whatever the meter '
        'states (#2303)', () {
      final mixed = PhraseStructure.parse('2*8*3+2*8*2');
      expect(barTimingFor(ecd, mixed, meter: '3/4'), BarTiming.byPhrase(mixed));
      expect(barTimingFor(ecd, mixed), BarTiming.byPhrase(mixed));
    });

    test('contra keeps beats, with phrases that differ or not', () {
      expect(
        barTimingFor(DanceForm.contra, PhraseStructure.parse('3*8*3')),
        isNull,
      );
      expect(
        barTimingFor(DanceForm.contra, PhraseStructure.parse('2*8*3+2*8*2')),
        isNull,
      );
    });

    test(
      'a tune in one meter is timed as danceBeatsPerBar always timed it',
      () {
        for (final phrase in [
          '',
          '4*8*2',
          '4*8*3',
          '4*8*4',
          '2*8*6',
          '4*8*16',
        ]) {
          for (final meter in [
            '',
            '2/2',
            '3/2',
            '3/4',
            '6/8',
            '9/8',
            'a jig',
          ]) {
            final structure = PhraseStructure.parse(phrase);
            final perBar = danceBeatsPerBar(ecd, structure, meter: meter);
            expect(
              barTimingFor(ecd, structure, meter: meter),
              perBar == null ? isNull : BarTiming.fixed(perBar),
              reason: '"$phrase" in "$meter"',
            );
          }
        }
      },
    );
  });
}
