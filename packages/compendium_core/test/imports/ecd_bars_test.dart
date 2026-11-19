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
      for (final (meter, beats) in [('6/8', 2), ('9/8', 3), ('12/8', 4)]) {
        expect(ecdBeatsPerBar(meter), (beatsPerBar: beats, stated: true));
      }
    });

    test('a meter in other words is found', () {
      expect(ecdBeatsPerBar('Meter: 9/8'), (beatsPerBar: 3, stated: true));
    });

    test('no meter, or one it cannot read, counts 2 and says so', () {
      for (final meter in [null, '', 'jig', '3/5', '0/4', '13/8']) {
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

    test('a tune whose parts differ keeps the meter text as it is', () {
      expect(
        ecdMeterForBars('jig', PhraseStructure.parse('2*8*3+2*8*2')),
        'jig',
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
      ]) {
        expect(splitEcdBarRange(line), (bars: bars, rest: rest), reason: line);
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

    test('a stated count stands', () {
      final figure = parseEcdFigureLine(
        '1-4 circle left',
        beats: 6,
        meter: '2/2',
      )!;
      expect(figure.params['beats'], 6);
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
    });
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

    test('a file of English dances reads a Contra-typed dance as English, '
        'a square as a square', () {
      final english = mapCallersCompanionDance(
        record(),
        englishDances: true,
      ).dance;
      expect(english.form, DanceForm.ecd);
      final square = mapCallersCompanionDance(
        record(type: 'Square'),
        englishDances: true,
      ).dance;
      expect(square.form, DanceForm.square);
      // Without the answer, the Type rules.
      expect(mapCallersCompanionDance(record()).dance.form, DanceForm.contra);
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
