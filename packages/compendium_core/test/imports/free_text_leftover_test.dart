import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// What is typed is what is shown (October behaviour audit, AUTH-4 and
/// AUTH-16). Free-text entry keeps a structured reading with the rest of the
/// line as its note only when the note holds nothing that contradicts the
/// figure: no turn amount the figure ignores and no second move. Otherwise
/// the line is kept whole as a custom, marked unparsed (#1612).
void main() {
  final dialect = Dialect.larksRobins;
  List<Figure> parse(String line) =>
      parseFreeTextFigureEntry(line, dialect: dialect);

  group('a note that hides a turn or a second move keeps the line custom', () {
    // The audit's probe rows, then the two lines this PR adds for the
    // verifier's unrecorded inputs: a second move named by an alias, and the
    // `&` spelling of "over and back" without the exclamation mark.
    for (final line in [
      'circle left 3/4 and pass through',
      'partners balance and swing, end facing down',
      'petronella twice',
      'petronella turn x2',
      'Ladies chain over & back!',
      'down the hall four in line, turn alone',
      'neighbors box the gnat and swat the flea',
      'Ladies chain over & back',
      // A note that is exactly a move's name, as #1612 already ruled.
      'balance and swing petronella',
      '(4) Balance long wave',
    ]) {
      test(line, () {
        final f = parse(line).single;
        expect(f.isCustom, isTrue, reason: '${f.move} note=${f.note}');
        expect(f.customOrigin, CustomOrigin.importGap);
        expect(f.note, isNull);
      });
    }

    test('one leftover note among several is enough', () {
      // The swing's note is plain words; the balance's hides a turn.
      final f = parse(
        'neighbors swing slowly while partners balance twice',
      ).single;
      expect(f.isCustom, isTrue);
    });

    test('the audit\'s meanwhile line keeps its 1 1/2', () {
      // Before, the side read "allemande right" (once) with "1 1/2" in the
      // side's note, which no surface showed (AUTH-3).
      final f = parse('robins allemande right 1 1/2 while larks orbit').single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], contains('1 1/2'));
    });
  });

  group('a note of plain words keeps the structured reading', () {
    for (final (line, move, note) in [
      ('neighbors swing slowly', 'swing', 'slowly'),
      ('pass through to new neighbors', 'pass_through', 'to new neighbors'),
      ('down the hall in lines of 4', 'down_the_hall', 'in lines of 4'),
      // `back` alone is the return chain, not "over and back".
      ('ladies chain back', 'chain', 'back'),
      // A move named mid-clause is usually where the figure happens.
      ('neighbors swing in the circle', 'swing', 'in the circle'),
      // `once` is what a figure does by default, not a turn it ignores.
      ('Circle left once around', 'circle', 'once around'),
      // A clause that opens with a move's name but is a hold or a place, not
      // a figure of its own.
      ('partners swing, promenade hold', 'swing', 'promenade hold'),
      ('neighbors allemande left, swing hold', 'allemande', 'swing hold'),
      (
        '(4) Women balance long wave in center',
        'balance',
        'long wave in center',
      ),
    ]) {
      test(line, () {
        final f = parse(line).single;
        expect(f.move, move);
        expect(f.note, note);
      });
    }

    test('a move named mid-clause, in brackets too, is not a leftover', () {
      final f = parse(
        'Ladies chain to partner (optional courtesy turn)',
      ).single;
      expect(f.move, 'chain');
      expect(f.note, contains('courtesy turn'));
    });

    test('1x is once, the default, not a turn the figure ignores', () {
      final f = parse("larks allemande left 1x - don't let go").single;
      expect(f.move, 'allemande');
    });
  });

  group('a count in bars is kept as a note on the figure (AUTH-16)', () {
    for (final (line, move) in [
      ('circle left 4 bars', 'circle'),
      ('neighbor swing 2 bars', 'swing'),
      ('star right 6 bars', 'star'),
      ('circle left (4 bars)', 'circle'),
      ('4 bars circle left', 'circle'),
      ('(4 bars) circle left', 'circle'),
    ]) {
      test(line, () {
        final f = parse(line).single;
        expect(f.move, move);
        expect(f.note, matches(RegExp(r'^\d bars$')));
        // Never beats: how many beats a bar holds depends on the music.
        expect(f.params.containsKey('beats'), isFalse);
      });
    }

    test('the rest of the line is still read: 3/4 is three places', () {
      final f = parse('circle left 3/4 4 bars').single;
      expect(f.move, 'circle');
      expect(f.params['places'], 3);
      expect(f.note, '4 bars');
    });

    test('a beat count still wins, and the bars stay in the text', () {
      final f = parse('circle left 4 bars (8)').single;
      expect(f.params['beats'], 8);
    });

    test('a line not read in full stays custom as typed, bars included', () {
      final f = parse('gibberish xyz 4 bars').single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], 'gibberish xyz 4 bars');
      expect(f.params.containsKey('beats'), isFalse);
    });
  });

  group('Re-check custom figures applies the same rule', () {
    test('an honest custom is not "upgraded" into a wrong reading', () {
      final customs = [
        for (final text in [
          'petronella twice',
          'circle left 3/4 and pass through',
          'partners balance and swing, end facing down',
          'neighbors box the gnat and swat the flea',
        ])
          customFigure(text, origin: CustomOrigin.importGap),
      ];
      final out = reparseImportGapFigures(customs);
      expect(out.upgradedCount, 0);
      expect(out.figures, customs);
    });

    test('a custom the parser now reads in full still upgrades', () {
      final out = reparseImportGapFigures([
        customFigure('neighbors swing slowly', origin: CustomOrigin.importGap),
      ]);
      expect(out.upgradedCount, 1);
      expect(out.figures.single.move, 'swing');
    });
  });
}
