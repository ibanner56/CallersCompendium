import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion's "Neighbor Roll Away" is a roll away with your
/// neighbor, and a box circulate's beats say whether it carries a balance (8
/// beats: a balance; 4: none).
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 4),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
    // ContraDB's dialect claims "Larks roll away" first on both paths above;
    // the Caller's Box front end reaches the shared recognizer.
    'Caller\'s Box': (String line) => [
      parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd)!,
    ],
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      group('roll away', () {
        test('a relationship before it is whom the roll away is with', () {
          for (final (line, whom) in [
            ('Neighbor Roll Away with half sashay', 'neighbors'),
            ('Partner roll away', 'partners'),
          ]) {
            final f = single(line);
            expect(f.move, 'roll_away', reason: line);
            expect(f.params['whom'], whom, reason: line);
            expect(f.params.containsKey('who'), isFalse, reason: line);
            expect(f.assumedSubject, isTrue, reason: line);
          }
        });

        test('"rollaway" and "w/ half sashay" read', () {
          final f = single('Neighbor rollaway w/ half sashay');
          expect(f.move, 'roll_away');
          expect(f.params['whom'], 'neighbors');
          expect(f.params['halfSashay'], isTrue);
        });

        test('a role or couple before it is still who rolls', () {
          final larks = single('Larks roll away');
          expect(larks.params['who'], 'role1s');
          expect(larks.params.containsKey('whom'), isFalse);


          final ones = single('Ones roll away neighbors');
          expect(ones.params['who'], 'ones');
          expect(ones.params['whom'], 'neighbors');
        });

        test('a relationship with a dancer after it keeps both slots', () {
          final f = single('Neighbors roll away partners');
          expect(f.params['who'], 'neighbors');
          expect(f.params['whom'], 'partners');
        });
      });
    });
  }

  // Free-text entry has no beats, so only an import reads the balance from
  // them. The re-parse of a stored custom line is the singular fan-out.
  group('box circulate', () {
    final importers = {
      'import': (String line, int beats) =>
          parseFigureLinesFanOut(line, beats: beats).single,
      're-parse': (String line, int beats) =>
          parseFigureLineFanOut(line, beats: beats)!,
    };
    for (final MapEntry(key: path, value: read) in importers.entries) {
      test('$path: 8 beats is a balance and circulate', () {
        final f = read('Box circulate', 8);
        expect(f.move, 'box_circulate');
        expect(f.params['balance'], isTrue);
      });

      test('$path: 4 beats keeps no balance', () {
        final f = read('Box circulate', 4);
        expect(f.move, 'box_circulate');
        expect(f.params.containsKey('balance'), isFalse);
      });

      test('$path: any other count says nothing', () {
        for (final beats in [0, 6, 16]) {
          expect(
            read('Box circulate', beats).params.containsKey('balance'),
            isFalse,
            reason: '$beats',
          );
        }
      });
    }
  });
}
