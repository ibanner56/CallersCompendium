import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// ADR-006 W6, part 3: an English line's leading bar range is its count, in
/// bars of the dance's meter (Hudson, 19 November 2026: "the meter is the
/// rule"), and a Caller's Companion file can be read as English dances.
void main() {
  group('ecdBeatsPerBar', () {
    test('a simple meter counts its top number', () {
      for (final (meter, beats) in [
        ('2/2', 2),
        ('2/4', 2),
        ('3/2', 3),
        ('3/4', 3),
        ('4/4', 4),
      ]) {
        expect(ecdBeatsPerBar(meter), (beatsPerBar: beats, stated: true));
      }
    });

    test('a compound meter counts its dotted beats', () {
      for (final (meter, beats) in [
        ('6/8', 2),
        ('9/8', 3),
        ('12/8', 4),
        ('6/4', 2),
        ('9/4', 3),
        ('12/4', 4),
      ]) {
        expect(ecdBeatsPerBar(meter), (beatsPerBar: beats, stated: true));
      }
    });

    test('a meter in other words is found', () {
      expect(ecdBeatsPerBar('Meter: 9/8'), (beatsPerBar: 3, stated: true));
      // Named twice, or with a non-meter beside it, it still counts.
      expect(ecdBeatsPerBar('3/2 (3/2)'), (beatsPerBar: 3, stated: true));
      expect(ecdBeatsPerBar('3/2, track 3/12'), (beatsPerBar: 3, stated: true));
    });

    test('no meter, or one it cannot read, counts 2 and says so', () {
      for (final meter in [
        null,
        '',
        'jig',
        '3/5',
        '0/4',
        '13/8',
        '3/12',
        '1/2/2003',
        '2/4 and 3/4',
      ]) {
        expect(ecdBeatsPerBar(meter), (
          beatsPerBar: 2,
          stated: false,
        ), reason: '$meter');
      }
    });
  });

  group('ecdMeterForBars', () {
    test('a stated meter is the rule', () {
      expect(ecdMeterForBars('3/2', PhraseStructure.parse('4*8*2')), '3/2');
    });

    test('with none, the phrase structure\'s beats per bar count', () {
      expect(ecdMeterForBars('', PhraseStructure.parse('4*8*3')), '3/4');
      expect(ecdMeterForBars(null, PhraseStructure.standard), '2/4');
      expect(
        ecdBeatsPerBar(ecdMeterForBars('jig', PhraseStructure.parse('4*8*3'))),
        (beatsPerBar: 3, stated: true),
      );
    });

    test('a structure of 6, 9 or 12 beats a bar counts them all', () {
      for (final beats in [6, 9, 12]) {
        final meter = ecdMeterForBars('', PhraseStructure.parse('4*8*$beats'));
        expect(ecdBeatsPerBar(meter).beatsPerBar, beats, reason: meter);
      }
    });

    test('a bar of more than 12 beats has no meter', () {
      expect(ecdMeterForBars('', PhraseStructure.parse('4*8*16')), '');
    });

    test('a tune whose parts differ keeps the meter text as it is', () {
      expect(
        ecdMeterForBars('jig', PhraseStructure.parse('2*8*3+2*8*2')),
        'jig',
      );
    });
  });

  group('a bar range in a dance whose phrases differ in beats per bar', () {
    // A1 and A2 are 4 bars of 3 beats (0-24), B is 8 bars of 2 (24-40).
    final structure = PhraseStructure.parse('A:2*4*3 + B:1*8*2');
    final timing = BarTiming.byPhrase(structure);
    final ecd = shippedTaxonomies.forForm(DanceForm.ecd);

    test('counts each range by the phrase it is danced in', () {
      expect(ecdBarCount('1-4 circle left', timing: timing)!.beats, 12);
      expect(
        ecdBarCount('5-8 circle left', timing: timing, startBeat: 12)!.beats,
        12,
      );
      expect(
        ecdBarCount('9-12 circle left', timing: timing, startBeat: 24)!.beats,
        8,
      );
    });

    test('counts the bars from where the line sits, not by their numbers', () {
      expect(ecdBarCount('9-12 circle left', timing: timing)!.beats, 12);
    });

    test('counts a line of several ranges across all of them', () {
      // Bars 5-8 in A2 (12 beats), then bars 9-12 in B (8).
      expect(
        ecdBarCount(
          '(5-8) circle left (9-12) circle right',
          timing: timing,
          startBeat: 12,
        )!.beats,
        20,
      );
    });

    test('parseEcdFigureLine takes the count of the phrase it falls in', () {
      final inA = parseEcdFigureLine('1-4 circle left', timing: timing)!;
      expect(inA.params['beats'], 12);
      final inB = parseEcdFigureLine(
        '9-12 circle left',
        timing: timing,
        startBeat: 24,
      )!;
      expect(inB.params['beats'], 8);
      // Bars at 18 (3), 21 (3), 24 (2), 26 (2).
      final across = parseEcdFigureLine(
        '1-4 circle left',
        timing: timing,
        startBeat: 18,
      )!;
      expect(across.params['beats'], 10);
    });

    test('a typed range takes the count of the phrase it falls in', () {
      final figures = parseFreeTextFigureEntry(
        '5-8 circle left',
        taxonomy: ecd,
        timing: timing,
        startBeat: 12,
      );
      expect(figures.single.move, 'ecd_circle');
      expect(figures.single.params['beats'], 12);
      final inB = parseFreeTextFigureEntry(
        '9-12 circle left',
        taxonomy: ecd,
        timing: timing,
        startBeat: 24,
      );
      expect(inB.single.params['beats'], 8);
    });

    test('a dance in one meter counts exactly as it did', () {
      expect(ecdBarCount('1-4 circle left', meter: '3/2')!.beats, 12);
      expect(ecdBarCount('1-4 circle left')!.beats, 8);
    });

    test('re-check counts each custom line by where it falls', () {
      final out = reparseImportGapFigures(
        [
          customFigure('1-4 circle left', origin: CustomOrigin.importGap),
          customFigure('5-8 circle left', origin: CustomOrigin.importGap),
          customFigure('9-12 circle left', origin: CustomOrigin.importGap),
        ],
        taxonomy: ecd,
        meter: '',
        phraseStructure: structure,
      );
      // The third line starts where the first two end, in B.
      expect([for (final f in out.figures) f.params['beats']], [12, 12, 8]);
    });

    test('re-check starts every side of a meanwhile with the meanwhile', () {
      // Both sides are danced together from the end of A2's bar at 18, so each
      // counts its two bars from there (3 + 3), not the second after the first.
      final meanwhile = Figure.meanwhile(
        figures: [
          customFigure('1-2 circle left', origin: CustomOrigin.importGap),
          customFigure('1-2 circle right', origin: CustomOrigin.importGap),
        ],
        beats: 6,
      );
      final out = reparseImportGapFigures(
        [customFigure('stand', beats: 18), meanwhile],
        taxonomy: ecd,
        meter: '',
        phraseStructure: structure,
      );
      expect(
        [for (final f in out.figures[1].subFigures) f.params['beats']],
        [6, 6],
      );
    });

    test('a stated Meter does not override phrases that differ', () {
      final out = reparseImportGapFigures(
        [customFigure('1-4 circle left', origin: CustomOrigin.importGap)],
        taxonomy: ecd,
        meter: '3/4',
        phraseStructure: PhraseStructure.parse('A:1*4*2 + B:1*8*3'),
      );
      expect(out.figures.single.params['beats'], 8);
    });

    test('re-check starts each step after the steps before it, as re-read', () {
      // 18 beats of other figures put the sequence at the end of A2: its first
      // step runs 18-24 (two bars of 3), the next starts in B (two of 2).
      final sequence = Figure.sequence(
        figures: [
          customFigure('1-2 circle left', origin: CustomOrigin.importGap),
          customFigure('3-4 circle right', origin: CustomOrigin.importGap),
        ],
        beats: 10,
      );
      final out = reparseImportGapFigures(
        [customFigure('stand', beats: 18), sequence],
        taxonomy: ecd,
        meter: '',
        phraseStructure: structure,
      );
      expect(
        [for (final f in out.figures[1].subFigures) f.params['beats']],
        [6, 4],
      );
    });
  });

  group('splitEcdBarRange', () {
    test('reads a leading range in its usual forms', () {
      for (final (line, bars, rest) in [
        ('1-4 Partners set and turn single', 4, 'Partners set and turn single'),
        ('(5-8) Circle left', 4, 'Circle left'),
        ('9 – 12 All promenade', 4, 'All promenade'),
        ('A1 1-8 Partners lead up', 8, 'Partners lead up'),
        ('A1&2 1-4 Partners siding', 4, 'Partners siding'),
        ('1-2: All set', 2, 'All set'),
        ('A1: 1-4 Partners set', 4, 'Partners set'),
        ('a1 1-4 Partners set', 4, 'Partners set'),
        ('A1&A2 1-8 Partners lead up', 8, 'Partners lead up'),
      ]) {
        expect(splitEcdBarRange(line), (
          bars: bars,
          rest: rest,
          several: false,
          firstBars: bars,
        ), reason: line);
      }
    });

    test('a line of ranges that follow on spans them all', () {
      for (final (line, bars) in [
        ('(5-8) Partners set (9-12) Turn single', 8),
        ('1-4 Lead up 5-8 Fall back', 8),
        ('1-2 Set 3-4 Turn single (5-8) Circle left', 8),
        ('1-4 Lead up – 5–8 fall back', 8),
        ('1-4 Lead up a double. 5-8. Fall back', 8),
      ]) {
        final range = splitEcdBarRange(line)!;
        expect(range.bars, bars, reason: line);
        expect(range.several, isTrue, reason: line);
      }
    });

    test('a later range that does not follow on is part of the words', () {
      for (final (line, bars) in [
        ('(5-8) Partners set (13-16) Turn single', 4),
        ('1-4 Lead up 4-8 fall back', 4),
        ('1-4 Circle in 3/4-time', 4),
        ('1-4 Hey 2-3 times', 4),
        ('1-4 Circle 5-8x', 4),
        ('1-16 Lead up (17-40) fall back', 16),
      ]) {
        final range = splitEcdBarRange(line)!;
        expect(range.bars, bars, reason: line);
        expect(range.several, isFalse, reason: line);
      }
    });

    test('a lone number, a hyphenated word or a bad range is not one', () {
      for (final line in [
        '2 changes of rights and lefts',
        '2-hand turn once',
        '4-1 circle left',
        '1-40 circle left',
        '(1-4)',
        'circle left 1-4',
        '(1-4 circle left',
        '1-4) circle left',
      ]) {
        expect(splitEcdBarRange(line), isNull, reason: line);
      }
    });
  });

  group('parseEcdFigureLine counts a bar range by the meter', () {
    test('in a 3/2 tune, four bars are 12 beats', () {
      final figure = parseEcdFigureLine('1-4 circle left', meter: '3/2')!;
      expect(figure.move, 'ecd_circle');
      expect(figure.params['beats'], 12);
    });

    test('with no meter, two beats a bar', () {
      final figure = parseEcdFigureLine('(5-8) circle left')!;
      expect(figure.move, 'ecd_circle');
      expect(figure.params['beats'], 8);
    });

    test('the bars are the count over one the line was given', () {
      final figure = parseEcdFigureLine(
        '1-4 circle left',
        beats: 6,
        meter: '2/2',
      )!;
      expect(figure.move, 'ecd_circle');
      expect(figure.params['beats'], 8);
    });

    test('over the count a figure would take by default', () {
      final figure = parseEcdFigureLine(
        '1-4 partners set and turn single',
        meter: '3/2',
      )!;
      expect(figure.isCustom, isFalse);
      expect(figure.params['beats'], 12);
    });

    test('a line that also states beats is kept whole, with the bars', () {
      for (final line in [
        '1-4 (6) circle left',
        '1-4 circle left 6 beats',
        '1-4 circle left [6]',
        '1-4 partners set and turn single (4,4)',
        '1-4 partners set and turn single (4+4)',
      ]) {
        final figure = parseEcdFigureLine(line, meter: '2/2')!;
        expect(figure.isCustom, isTrue, reason: line);
        expect(figure.params['text'], line, reason: line);
        expect(figure.params['beats'], 8, reason: line);
      }
    });

    test('a line kept as text keeps the range and the count', () {
      final figure = parseEcdFigureLine(
        '1-4 something only this caller says',
        meter: '6/8',
      )!;
      expect(figure.isCustom, isTrue);
      expect(figure.params['text'], '1-4 something only this caller says');
      expect(figure.params['beats'], 8);
    });

    test('ranges past the beats range keep the first one\'s count', () {
      const line = '(1-12) lead up and back (13-24) set and turn';
      final figure = parseEcdFigureLine(line, meter: '3/2')!;
      expect(figure.isCustom, isTrue);
      expect(figure.params['text'], line);
      expect(figure.params['beats'], 36);
    });

    test('a line of two ranges is kept whole, counted across both', () {
      // The second reads as a sequence if the line is not kept whole, and
      // its range would be lost.
      for (final (line, beats) in [
        ('(5-8) circle left (9-12) circle right', 24),
        ('1-4 partners set (5-8) and turn single', 24),
      ]) {
        final figure = parseEcdFigureLine(line, meter: '3/2')!;
        expect(figure.isCustom, isTrue, reason: line);
        expect(figure.params['text'], line, reason: line);
        expect(figure.params['beats'], beats, reason: line);
      }
    });

    test('a count over the beats range is not taken', () {
      final figure = parseEcdFigureLine('1-32 circle left', meter: '4/4')!;
      expect(figure.isCustom, isTrue);
      expect(figure.params['beats'] ?? 0, 0);
    });
  });

  group('free-text entry in an English dance', () {
    final ecd = shippedTaxonomies.forForm(DanceForm.ecd);

    test('counts a typed bar range by the meter', () {
      final figures = parseFreeTextFigureEntry(
        '1-4 circle left',
        taxonomy: ecd,
        meter: '3/4',
      );
      expect(figures.single.move, 'ecd_circle');
      expect(figures.single.params['beats'], 12);
    });

    test('counts the bars over the count a figure would take', () {
      final figures = parseFreeTextFigureEntry(
        '1-4 partners set and turn single',
        taxonomy: ecd,
        meter: '3/2',
      );
      expect(figures.single.isCustom, isFalse);
      expect(figures.single.params['beats'], 12);
    });

    test('keeps a line that also states beats whole, with the bars', () {
      final figures = parseFreeTextFigureEntry(
        '1-4 (6) circle left',
        taxonomy: ecd,
        meter: '2/2',
      );
      expect(figures.single.isCustom, isTrue);
      expect(figures.single.params['text'], '1-4 (6) circle left');
      expect(figures.single.params['beats'], 8);
    });

    test('keeps a line of two ranges whole, counted across both', () {
      for (final line in [
        '(5-8) circle left (9-12) circle right',
        '1-4 partners set (5-8) and turn single',
      ]) {
        final figures = parseFreeTextFigureEntry(
          line,
          taxonomy: ecd,
          meter: '2/2',
        );
        expect(figures, hasLength(1), reason: line);
        expect(figures.single.isCustom, isTrue, reason: line);
        expect(figures.single.params['text'], line, reason: line);
        expect(figures.single.params['beats'], 16, reason: line);
      }
    });

    test('keeps a line it cannot read whole, with the count', () {
      final figures = parseFreeTextFigureEntry(
        '1-4 something only this caller says',
        taxonomy: ecd,
        meter: '2/2',
      );
      expect(figures.single.isCustom, isTrue);
      expect(
        figures.single.params['text'],
        '1-4 something only this caller says',
      );
      expect(figures.single.params['beats'], 8);
    });

    test('a contra line is not read for bars', () {
      final figures = parseFreeTextFigureEntry(
        '1-4 circle left',
        taxonomy: contraTaxonomy,
        meter: '2/2',
      );
      expect(figures.any((f) => f.params['beats'] == 8), isFalse);
      // The meter changes nothing in a contra line: not its words, not its
      // count.
      expect(
        parseFreeTextFigureEntry(
          '1-4 circle left',
          taxonomy: contraTaxonomy,
          meter: '3/2',
        ),
        figures,
      );
      // Today the contra grammar keeps it as typed, with no count.
      expect(figures.single.params['text'], '1-4 circle left');
      expect(figures.single.params['beats'], isNull);
    });
  });

  test('re-check keeps a line of several ranges as text, with its stored '
      'count', () {
    const line = '(5-8) partners set (9-12) and turn single';
    final out = reparseImportGapFigures(
      [customFigure(line, beats: 8, origin: CustomOrigin.importGap)],
      taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
      meter: '2/2',
      phraseStructure: PhraseStructure.standard,
    );
    expect(out.figures.single.isCustom, isTrue);
    expect(out.figures.single.params['text'], line);
    // A line still kept as text is not recounted (it is not upgraded).
    expect(out.figures.single.params['beats'], 8);
  });

  test('re-check counts by the phrase structure when no meter is stated', () {
    final out = reparseImportGapFigures(
      [
        customFigure(
          '1-4 circle left',
          beats: 0,
          origin: CustomOrigin.importGap,
        ),
      ],
      taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
      meter: '',
      phraseStructure: PhraseStructure.parse('4*8*3'),
    );
    expect(out.figures.single.params['beats'], 12);
  });

  test('re-check counts an English line by the meter it is given', () {
    final out = reparseImportGapFigures(
      [
        customFigure(
          '1-4 circle left',
          beats: 0,
          origin: CustomOrigin.importGap,
        ),
      ],
      taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
      meter: '9/8',
    );
    expect(out.upgradedCount, 1);
    expect(out.figures.single.move, 'ecd_circle');
    expect(out.figures.single.params['beats'], 12);
  });

  group('Caller\'s Companion', () {
    CcDanceRecord record({
      String? type = 'Contra',
      String? music,
      List<String> lines = const ['1-4 circle left'],
    }) => CcDanceRecord(
      name: 'Bar Dance',
      type: type,
      music: music,
      fromUsrColumns: true,
      body: [CcBodySection(lines: lines)],
    );

    group('phrase structure', () {
      List<String> labels(Dance dance) => [
        for (final f in dance.sectionedFigures) f.label,
      ];

      Dance sectioned(String? music, Map<String, List<String>> sections) =>
          mapCallersCompanionDance(
            CcDanceRecord(
              name: 'Phrased',
              type: 'Contra',
              music: music,
              fromUsrColumns: true,
              body: [
                for (final MapEntry(:key, :value) in sections.entries)
                  CcBodySection(label: key, lines: value),
              ],
            ),
            englishDances: true,
          ).dance;

      test('sections A1 A2 B1 counted in full name the phrases', () {
        final dance = sectioned('Key: G, Meter: 3/4', {
          'A1': ['(1-4) circle left'],
          'A2': ['(1-4) circle right'],
          'B1': ['(1-4) circle left', '(5-8) circle right'],
        });
        expect(dance.phraseStructure.raw, 'A:2*4*3 + B:1*8*3');
        expect(dance.phraseStructure.labels, ['A1', 'A2', 'B']);
        expect(labels(dance), ['A1', 'A2', 'B', 'B']);
        expect(dance.validate(), isEmpty);
      });

      test('A, B and C played once each', () {
        final dance = sectioned('2/2', {
          'A1': ['(8) circle left'],
          'B1': ['(8) circle right'],
          'C1': ['(8) circle left', '(8) circle right'],
        });
        expect(dance.phraseStructure.raw, 'A:1*4*2 + B:1*4*2 + C:1*8*2');
        expect(dance.phraseStructure.labels, ['A', 'B', 'C']);
        expect(labels(dance), ['A', 'B', 'C', 'C']);
        expect(dance.validate(), isEmpty);
      });

      test('A1 A2 B1 B2 of 8 bars each stays the unnamed structure', () {
        final sections = {
          for (final label in ['A1', 'A2', 'B1', 'B2'])
            label: ['(1-4) circle left', '(5-8) circle right'],
        };
        expect(sectioned('2/2', sections).phraseStructure.raw, '');
        expect(sectioned('3/2', sections).phraseStructure.raw, '4*8*3');
        // Of 4 bars each, they are named.
        expect(
          sectioned('2/2', {
            for (final label in ['A1', 'A2', 'B1', 'B2'])
              label: ['(1-4) circle left'],
          }).phraseStructure.raw,
          'A:2*4*2 + B:2*4*2',
        );
      });

      test('a section that counts no bars names no phrases', () {
        // Named A:2*8*2 + B:1*8*2, the B figures would be labeled A2.
        final dance = sectioned('2/2', {
          'A1': ['(1-8) circle left'],
          'A2': ['Repeat to places.'],
          'B1': ['(1-8) circle right'],
        });
        expect(dance.phraseStructure.raw, '');
      });

      test('a count lost in a line kept as text names no phrases; the meter '
          'still sets the beats in a bar', () {
        final dance = sectioned('Key G Meter 3/4', {
          'A1': ['(12) circle left', '(12) circle right'],
          'A2': ['(12) circle left', '(12) circle right'],
          // A prefix the line's bars disagree with is kept as text with the
          // bars' count, so the prefix's count is lost.
          'B1': ['(3) 1-2 something only this caller says'],
        });
        expect(dance.phraseStructure.raw, '4*8*3');
      });

      test('unlabeled or unusual sections name no phrases', () {
        for (final sections in [
          {
            'A1': ['(8) circle left'],
            'D1': ['(8) circle right'],
          },
          {
            'A1': ['(8) circle left'],
            'B2': ['(8) circle right'],
          },
          {
            'A1': ['(8) circle left'],
            'A2': ['(8) circle left'],
            'A3': ['(8) circle left'],
          },
          {
            'A1': ['(8) circle left'],
            'A2': ['(16) circle right'],
          },
        ]) {
          expect(
            sectioned('2/2', sections).phraseStructure.raw,
            '',
            reason: '$sections',
          );
        }
        final unlabeled = mapCallersCompanionDance(
          record(music: '6/8', lines: const ['(8) circle left']),
          englishDances: true,
        ).dance;
        expect(unlabeled.phraseStructure.raw, '');
      });

      test('with no named phrases, a meter of other than two beats a bar '
          'sets the structure\'s beats', () {
        for (final (music, raw) in [
          ('3/2', '4*8*3'),
          ('9/8', '4*8*3'),
          ('4/4', '4*8*4'),
          ('2/2', ''),
          ('6/8', ''),
          (null, ''),
        ]) {
          final dance = mapCallersCompanionDance(
            record(music: music, lines: const ['circle left']),
            englishDances: true,
          ).dance;
          expect(dance.phraseStructure.raw, raw, reason: music);
        }
      });

      test('a contra dance keeps the standard structure', () {
        final dance = mapCallersCompanionDance(record(music: '3/2')).dance;
        expect(dance.form, DanceForm.contra);
        expect(dance.phraseStructure.raw, '');
      });
    });

    test('ecdStatedBeats adds up every count a line states', () {
      for (final (line, beats) in [
        ('(8) circle left', 8),
        ('(4,4) set and turn single', 8),
        ('(1-4) circle left (5-8) circle right', 16),
        ('1-2 set 3-4 turn single', 8),
        ('(3) change (3) change', 6),
        ('circle left', 0),
        ('circle left in 3/4-time', 0),
        ('hey for 3', 0),
      ]) {
        expect(ecdStatedBeats(line, 2), beats, reason: line);
      }
    });

    test('a file of English dances reads a Contra-typed dance as English, '
        'and a square as English in a square set', () {
      final english = mapCallersCompanionDance(
        record(),
        englishDances: true,
      ).dance;
      expect(english.form, DanceForm.ecd);
      final square = mapCallersCompanionDance(
        record(type: 'Square'),
        englishDances: true,
      ).dance;
      expect(square.form, DanceForm.ecd);
      expect(square.formation, const Formation(FormationShape.square));
      // Without the answer, the Type rules.
      expect(mapCallersCompanionDance(record()).dance.form, DanceForm.contra);
      expect(
        mapCallersCompanionDance(record(type: 'Square')).dance.form,
        DanceForm.square,
      );
    });

    group('an English square set', () {
      Dance mapped(CcDanceRecord r) =>
          mapCallersCompanionDance(r, englishDances: true).dance;

      test('takes the square shape from its Type, whatever its formation, '
          'keeping what its formation said', () {
        final newcastle = mapped(
          CcDanceRecord(
            name: 'Newcastle',
            type: 'Square',
            formationFamily: 'Quadruplet',
            formationOther: 'Four couples, first couple facing down',
            fromUsrColumns: true,
          ),
        );
        expect(newcastle.form, DanceForm.ecd);
        expect(
          newcastle.formation,
          const Formation(
            FormationShape.square,
            detail: 'Quadruplet; Four couples, first couple facing down',
          ),
        );
      });

      test('takes it from a Square formation under another Type', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Square Set',
            type: 'Contra',
            formationFamily: 'Square',
            fromUsrColumns: true,
          ),
        );
        expect(dance.formation, const Formation(FormationShape.square));
      });

      test('reads the text export\'s Square formation the same way', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Square Set',
            type: 'Square',
            formation: 'Square',
          ),
        );
        expect(dance.form, DanceForm.ecd);
        expect(dance.formation, const Formation(FormationShape.square));
      });

      test('keeps a formation family it does not know as the detail, '
          'as its warning says', () {
        final mapping = mapCallersCompanionDance(
          CcDanceRecord(
            name: 'Hex',
            type: 'Square',
            formationFamily: 'Hexagon',
            fromUsrColumns: true,
          ),
          englishDances: true,
        );
        expect(
          mapping.dance.formation,
          const Formation(FormationShape.square, detail: 'Hexagon'),
        );
        // The family is not a square's, so its warning stays.
        expect(
          mapping.issues.map((i) => i.code),
          contains('cc_unmapped_formation'),
        );
      });

      test('reads a .USR square set named only in its own description', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Set',
            type: 'Contra',
            formationOther: 'Squares',
            fromUsrColumns: true,
          ),
        );
        expect(
          dance.formation,
          const Formation(FormationShape.square, detail: 'Squares'),
        );
      });

      test('keeps a square\'s start and direction in the detail', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Set',
            type: 'Square',
            contraForm: 'Becket',
            direction: 'CCW',
            fromUsrColumns: true,
          ),
        );
        expect(
          dance.formation,
          const Formation(FormationShape.square, detail: 'Becket; CCW'),
        );
      });

      test('a square in a big circle keeps the circle', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Big Set',
            type: 'Square',
            formationFamily: 'Circle',
            fromUsrColumns: true,
          ),
        );
        expect(dance.form, DanceForm.ecd);
        expect(dance.formation.shape, FormationShape.circle);
      });

      test('keeps the repeat order its SubType names', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Keeper',
            type: 'Square',
            subType: 'Keeper, H S H S',
            formationFamily: 'Square',
            fromUsrColumns: true,
          ),
        );
        expect(dance.repeatOrder, SquareRepeatOrder.headsSidesHeadsSides);
      });

      test('reads a text formation naming a square set, with no warning', () {
        final mapping = mapCallersCompanionDance(
          CcDanceRecord(name: 'Set', type: 'Contra', formation: 'Square set'),
          englishDances: true,
        );
        expect(
          mapping.dance.formation,
          const Formation(FormationShape.square, detail: 'Square set'),
        );
        expect(
          mapping.issues.map((i) => i.code),
          isNot(contains('cc_unmapped_formation')),
        );
      });

      test('a square\'s mixer SubType still marks a mixer', () {
        final dance = mapped(
          CcDanceRecord(
            name: 'Mixer Square',
            type: 'Square',
            subType: 'Mixer, H H S S',
            formationFamily: 'Square',
            fromUsrColumns: true,
          ),
        );
        expect(dance.mixer, isTrue);
        expect(dance.formation.shape, FormationShape.square);
      });
    });

    test('an English scatter mixer is another formation that mixes', () {
      final dance = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Scatter',
          type: 'Scatter Mixer',
          formationOther: 'Couples anywhere',
          fromUsrColumns: true,
        ),
        englishDances: true,
      ).dance;
      expect(dance.form, DanceForm.ecd);
      expect(
        dance.formation,
        const Formation(
          FormationShape.other,
          detail: 'Scatter mixer; Couples anywhere',
        ),
      );
      expect(dance.mixer, isTrue);
      expect(ecdFormationShapes, contains(dance.formation.shape));
    });

    test('an English circle mixer is a circle that mixes', () {
      final usr = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Wood Duck',
          type: 'Circle Mixer',
          formationFamily: 'Duple Minor',
          fromUsrColumns: true,
        ),
        englishDances: true,
      ).dance;
      expect(usr.form, DanceForm.ecd);
      expect(usr.formation.shape, FormationShape.circle);
      expect(usr.mixer, isTrue);

      // A circle by its formation alone is a circle, not a mixer: the text
      // export reads any "circle" as a circle mixer, and Sellenger's Round
      // does not mix.
      for (final (r, english) in [
        (
          CcDanceRecord(
            name: 'Sellenger’s Round',
            type: 'Contra',
            formation: 'Circle',
          ),
          true,
        ),
        (
          CcDanceRecord(
            name: 'Sellenger’s Round',
            type: 'English',
            formationFamily: 'Circle',
            fromUsrColumns: true,
          ),
          false,
        ),
      ]) {
        final dance = mapCallersCompanionDance(r, englishDances: english).dance;
        expect(dance.form, DanceForm.ecd);
        expect(dance.formation.shape, FormationShape.circle);
        expect(dance.mixer, isFalse);
      }

      // A text formation that says "mixer" is one: the text export has no
      // Type to say it.
      final named = mapCallersCompanionDance(
        CcDanceRecord(
          name: 'Mixer',
          type: 'English',
          formation: 'Circle mixer',
        ),
      ).dance;
      expect(named.formation.shape, FormationShape.circle);
      expect(named.mixer, isTrue);
    });

    test('an unknown Type read as English raises no "imported as a contra" '
        'note', () {
      final mapping = mapCallersCompanionDance(
        record(type: 'Other'),
        englishDances: true,
      );
      expect(mapping.dance.form, DanceForm.ecd);
      expect(
        mapping.issues.map((i) => i.code),
        isNot(contains('cc_unmapped_type')),
      );
    });

    test('an English dance takes its meter and key from Music, and counts '
        'bars by the meter', () {
      for (final (music, meter, key, beats) in [
        ('Key: G, Meter: 3/2', '3/2', 'G', 12),
        ('Key Dm Meter 6/8', '6/8', 'Dm', 8),
        ('Em 3/4', '3/4', 'Em', 12),
        ('Key: Bb, Meter: 2/2', '2/2', 'Bb', 8),
        ('Key: G minor, Meter: 3/2', '3/2', 'G minor', 12),
        ('G major, 6/8', '6/8', 'G major', 8),
        ('F# 6/4', '6/4', 'F#', 8),
        ('A 6/8', '6/8', 'A', 8),
        ('A 6/8 Trad.', '6/8', 'A', 8),
        ('A 6/8 Jig in G', '6/8', 'G', 8),
        ('A 2/2 reel in A', '2/2', 'A', 8),
        ('A 3/2 Hornpipe in G Minor', '3/2', 'G Minor', 12),
        ('G Minor, 6/8', '6/8', 'G Minor', 8),
        ('Meter 3/2 of Playford', '3/2', '', 12),
        ('Am 3/2 hornpipe', '3/2', 'Am', 12),
        ('Key: A, a 3/2 hornpipe', '3/2', 'A', 12),
        ('Meter 3/4, track 2', '3/4', '', 12),
      ]) {
        final dance = mapCallersCompanionDance(
          record(music: music),
          englishDances: true,
        ).dance;
        expect(dance.meter, meter, reason: music);
        expect(dance.musicalKey, key, reason: music);
        final figure = (dance.figuresSource as DecodedFigures).figures.single;
        expect(figure.params['beats'], beats, reason: music);
      }
    });

    test('an opening "A" before a meter and a word is no key', () {
      for (final (music, meter) in [
        ('A 3/2 hornpipe', '3/2'),
        ('A 6/8 jig in the old style', '6/8'),
        ('A 3/2 Hornpipe', '3/2'),
      ]) {
        final dance = mapCallersCompanionDance(
          record(music: music),
          englishDances: true,
        ).dance;
        expect(dance.meter, meter, reason: music);
        expect(dance.musicalKey, '', reason: music);
      }
    });

    test('a number that is not a meter is not stored as one', () {
      for (final music in [
        'Track 3/12',
        'Learned 1/2/2003',
        'Track 3/4 of CD',
        'Tracks 3/4',
        'CD #2/3',
        'Disc 2/2',
        'p. 3/4',
        'Tune 3/4 of the set',
      ]) {
        final mapping = mapCallersCompanionDance(
          record(music: music),
          englishDances: true,
        );
        expect(mapping.dance.meter, '', reason: music);
        expect(
          mapping.issues.map((i) => i.code),
          contains('cc_bars_meter_unstated'),
          reason: music,
        );
      }
    });

    // #2365: a Music text naming meters of different bars states none, so
    // its bars count 2 beats, as with no meter, and the review says why.
    test('meters of different bars are kept as written and counted as 2 '
        'beats, with a note', () {
      for (final (music, meter) in [
        ('Key: G, Meter: 3/4 and 6/8', '3/4 and 6/8'),
        ('Key G Meter 2/4 and 3/4', '2/4 and 3/4'),
        ('G 3/4, 6/8', '3/4, 6/8'),
        ('Key: G, Meter: 3/2; later 6/8', '3/2; later 6/8'),
      ]) {
        final mapping = mapCallersCompanionDance(
          CcDanceRecord(
            name: 'Mixed',
            type: 'Contra',
            music: music,
            fromUsrColumns: true,
            body: [
              CcBodySection(
                label: 'A',
                lines: const [
                  '1-4 lead up a double and back',
                  '5-8 partners set and turn single',
                ],
              ),
              CcBodySection(
                label: 'B',
                lines: const [
                  '9-12 circle left',
                  '13-16 partners back to back',
                ],
              ),
            ],
          ),
          englishDances: true,
        );
        final dance = mapping.dance;
        expect(dance.meter, meter, reason: music);
        expect(dance.musicalKey, 'G', reason: music);
        expect(dance.phraseStructure.raw, 'A:1*8*2 + B:1*8*2', reason: music);
        expect(
          [
            for (final f in (dance.figuresSource as DecodedFigures).figures)
              f.params['beats'],
          ],
          [8, 8, 8, 8],
          reason: music,
        );
        final codes = mapping.issues.map((i) => i.code);
        expect(codes, contains('cc_bars_meter_mixed'), reason: music);
        expect(codes, isNot(contains('cc_bars_meter_unstated')), reason: music);
      }
    });

    test('meters of different bars too far apart to keep whole are none', () {
      // Clipped, the text would keep only `3/4` and read as stating it.
      final music = 'Meter: 3/4 ${'x' * kMaxMusicLabelLength} 6/8';
      final mapping = mapCallersCompanionDance(
        record(music: music),
        englishDances: true,
      );
      expect(mapping.dance.meter, '');
      final figure =
          (mapping.dance.figuresSource as DecodedFigures).figures.single;
      expect(figure.params['beats'], 8);
      expect(
        mapping.issues.map((i) => i.code),
        contains('cc_bars_meter_unstated'),
      );
    });

    test('meters of the same bar count as the first, with no note', () {
      final mapping = mapCallersCompanionDance(
        record(music: 'Meter: 2/2 or 6/8'),
        englishDances: true,
      );
      expect(mapping.dance.meter, '2/2');
      final figure =
          (mapping.dance.figuresSource as DecodedFigures).figures.single;
      expect(figure.params['beats'], 8);
      expect(
        mapping.issues.map((i) => i.code),
        isNot(
          anyOf(
            contains('cc_bars_meter_mixed'),
            contains('cc_bars_meter_unstated'),
          ),
        ),
      );
    });

    test('bars after a beat prefix with no meter still raise the note', () {
      final mapping = mapCallersCompanionDance(
        record(music: 'a good tune', lines: const ['(8) 1-4 circle left']),
        englishDances: true,
      );
      expect(
        mapping.issues.map((i) => i.code),
        contains('cc_bars_meter_unstated'),
      );
    });

    test('a beat prefix that disagrees with the bars keeps the line as '
        'text, with the bars\' count', () {
      for (final line in [
        '(6) 1-4 circle left',
        '(4,4) 1-4 partners set and turn single',
      ]) {
        final dance = mapCallersCompanionDance(
          record(music: 'Meter: 3/2', lines: [line]),
          englishDances: true,
        ).dance;
        final figure = (dance.figuresSource as DecodedFigures).figures.single;
        expect(figure.isCustom, isTrue, reason: line);
        expect(figure.params['text'], line, reason: line);
        expect(figure.params['beats'], 12, reason: line);
      }
    });

    test('a line of several bracketed counts or ranges is read piece by '
        'piece', () {
      List<Figure> read(String line, {String meter = '2/2'}) =>
          (mapCallersCompanionDance(
                    record(music: 'Meter: $meter', lines: [line]),
                    englishDances: true,
                  ).dance.figuresSource
                  as DecodedFigures)
              .figures;

      final corners = read(
        '(4) First corners trade by right  (4) Second corners trade by right',
      );
      expect(corners.map((f) => f.move), [
        'ecd_change_places',
        'ecd_change_places',
      ]);
      expect(corners.map((f) => f.params['beats']), [4, 4]);
      expect(corners.map((f) => f.params['who']), [
        ['firstCorners'],
        ['secondCorners'],
      ]);

      final ranges = read(
        '(1-2) First Corner Set (3-4) First corners right-hand turn half way',
        meter: '3/2',
      );
      expect(ranges.map((f) => f.move), ['ecd_set', 'ecd_hand_turn']);
      expect(ranges.map((f) => f.params['beats']), [6, 6]);

      // A prefix that totals the ranges after it counts the line, not its
      // first piece.
      final total = read('(16) 1-4 partners set (5-8) turn single');
      expect(total.map((f) => f.move), ['ecd_set', 'ecd_turn_single']);
      expect(total.map((f) => f.params['beats']), [8, 8]);

      // An unbracketed count, or a bracketed one not followed by words,
      // does not split.
      expect(read('(8) circle left (2 bars, starting L foot)'), hasLength(1));
      expect(read('Lead up a double [4] and back'), hasLength(1));
    });

    group('a line is not split where its counts are its words', () {
      List<Figure> read(String line, {String? music = 'Meter: 2/2'}) =>
          (mapCallersCompanionDance(
                    record(music: music, lines: [line]),
                    englishDances: true,
                  ).dance.figuresSource
                  as DecodedFigures)
              .figures;
      int beats(List<Figure> figures) =>
          figures.fold(0, (sum, f) => sum + f.beats);

      test('a count right after a leading bar range', () {
        for (final line in const [
          '1-4 (6) circle left',
          'A1 1-4 (8) circle left',
        ]) {
          final figures = read(line);
          expect(figures, hasLength(1), reason: line);
          expect(beats(figures), 8, reason: line);
        }
      });

      test('a section label before a bracketed range', () {
        final one = read('A1 (1-4) circle left');
        expect(one, hasLength(1));
        expect(beats(one), 8);
        final two = read('A1 (1-4) circle left (5-8) turn single');
        expect(two, hasLength(2));
        expect(two.first.isCustom, isFalse);
        expect(beats(two), 16);
      });

      test('a bracket with no space before its word', () {
        final figures = read(
          '(5-6) Partner Set (while holding hands with N) (7-8)and link',
        );
        expect(beats(figures), 8);
        expect(figures, hasLength(1));
      });

      test('counts in beats inside a line counted in bars', () {
        final figures = read(
          '(5-8) 1st corners join R hands (5) then L hands (6) and with '
          'crossed hands turn 1/2',
        );
        expect(figures, hasLength(1));
        expect(beats(figures), 8);
      });

      test('a total prefix over a line that does not split stays in its '
          'text', () {
        final figures = read('(16) 1-4 circle left (8) circle right');
        expect(figures, hasLength(1));
        expect(figures.single.isCustom, isTrue);
        expect(figures.single.params['text'], startsWith('(16)'));
      });

      test('a count of hands or places', () {
        expect(read('(8) Circle left (3) hands round'), hasLength(1));
        expect(read('(8) Ones cast (2) places down'), hasLength(1));
      });

      test('a later piece\'s bar range with no meter still warns', () {
        final mapping = mapCallersCompanionDance(
          record(
            music: 'Key G',
            lines: const ['(4) Lead up a double (5-8) Turn single right'],
          ),
          englishDances: true,
        );
        expect(
          mapping.issues.map((i) => i.code),
          contains('cc_bars_meter_unstated'),
        );
      });
    });

    test('a piece that does not read stays as text with its own count', () {
      final figures =
          (mapCallersCompanionDance(
                    record(
                      music: 'Meter: 2/2',
                      lines: const [
                        '(4) Neighbor Set advancing to a wave of 4 (4) N Set',
                      ],
                    ),
                    englishDances: true,
                  ).dance.figuresSource
                  as DecodedFigures)
              .figures;
      expect(figures, hasLength(2));
      expect(figures.map((f) => f.params['beats']), [4, 4]);
      expect(figures.fold(0, (sum, f) => sum + f.beats), 8);
    });

    test('a beat prefix the bars agree with reads the line', () {
      final dance = mapCallersCompanionDance(
        record(music: 'Meter: 2/2', lines: const ['(8) 1-4 circle left']),
        englishDances: true,
      ).dance;
      final figure = (dance.figuresSource as DecodedFigures).figures.single;
      expect(figure.move, 'ecd_circle');
      expect(figure.params['beats'], 8);
    });

    test('a compound prefix with no bar range stays on its steps', () {
      final plain = mapCallersCompanionDance(
        record(
          music: 'Meter: 3/2',
          lines: const ['(4,4) partners set and turn single'],
        ),
        englishDances: true,
      ).dance;
      expect(
        [
          for (final s
              in (plain.figuresSource as DecodedFigures)
                  .figures
                  .single
                  .subFigures)
            s.params['beats'],
        ],
        [4, 4],
      );
    });

    test('a contra dance keeps its Music as a note only', () {
      final dance = mapCallersCompanionDance(
        record(music: 'Key: G, Meter: 2/2'),
      ).dance;
      expect(dance.meter, '');
      expect(dance.musicalKey, '');
    });

    test('bars with no meter are counted as 2 beats, with a note', () {
      final mapping = mapCallersCompanionDance(
        record(music: 'a good tune'),
        englishDances: true,
      );
      expect(
        mapping.issues.map((i) => i.code),
        contains('cc_bars_meter_unstated'),
      );
      final figure =
          (mapping.dance.figuresSource as DecodedFigures).figures.single;
      expect(figure.params['beats'], 8);
      // A stated meter raises no note.
      expect(
        mapCallersCompanionDance(
          record(music: 'Meter: 2/2'),
          englishDances: true,
        ).issues.map((i) => i.code),
        isNot(contains('cc_bars_meter_unstated')),
      );
    });

    test('the line cache keeps a line apart per meter', () {
      final cache = CcFigureLineCache();
      int beatsIn(String music) =>
          (mapCallersCompanionDance(
                        record(music: music),
                        englishDances: true,
                        lineCache: cache,
                      ).dance.figuresSource
                      as DecodedFigures)
                  .figures
                  .single
                  .params['beats']!
              as int;
      expect(beatsIn('Meter: 2/2'), 8);
      expect(beatsIn('Meter: 3/2'), 12);
    });

    test(
      'the .USR adapter carries the answer from discover to parse',
      () async {
        final entry = CcDanceEntry(
          recordId: '1',
          record: record(music: 'Key: G, Meter: 3/2'),
          rawColumns: const {
            'zk_Dance_ID': '1',
            'Name': 'Bar Dance',
            'Type': 'Contra',
            'Music': 'Key: G, Meter: 3/2',
          },
        );
        Future<Dance> read({required bool english}) async {
          final adapter = CallersCompanionUsrAdapter(
            reader: (bytes, limits) async => CcUsrArchive(
              dances: [entry],
              sets: const [],
              warnings: const [],
            ),
          );
          final found = await adapter.discover(
            ImportRequest(
              options: {
                'bytes': Uint8List(1),
                if (english)
                  CallersCompanionUsrAdapter.englishDancesOption: true,
              },
            ),
          );
          return adapter.parse(await adapter.fetch(found.single)).dance;
        }

        final english = await read(english: true);
        expect(english.form, DanceForm.ecd);
        expect(english.meter, '3/2');
        expect(
          (english.figuresSource as DecodedFigures)
              .figures
              .single
              .params['beats'],
          12,
        );
        expect((await read(english: false)).form, DanceForm.contra);
      },
    );
  });
}
