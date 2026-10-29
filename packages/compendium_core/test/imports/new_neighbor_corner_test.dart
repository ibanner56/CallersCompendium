import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion's "New Neighbor" is the next neighbors and its
/// "Corner" the first corners. Both the import fan-out and the editor's
/// free-text entry read them.
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      void expectWho(String line, String move, String who) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        expect(figures.single.move, move, reason: line);
        expect(figures.single.params['who'], who, reason: line);
      }

      test('a new neighbor is the next neighbor', () {
        expectWho('New Neighbor swing', 'swing', 'nextNeighbors');
        expectWho('New Neighbor Do-si-do', 'do_si_do', 'nextNeighbors');
        expectWho('swing your new neighbor', 'swing', 'nextNeighbors');
        expectWho(
          'New Neighbor allemande Right 1.5',
          'allemande',
          'nextNeighbors',
        );
      });

      test('a corner is the first corner, and the ordinals name either', () {
        expectWho('Corner swing', 'swing', 'firstCorners');
        expectWho('Corner allemande Left 1.0', 'allemande', 'firstCorners');
        expectWho(
          '1st corner allemande Right 3/4',
          'allemande',
          'firstCorners',
        );
        expectWho('second corner allemande left', 'allemande', 'secondCorners');
      });

      test('"the corners" may be both, so it is not read as first corners', () {
        expect(
          read('allemande left the corners').single.params['who'],
          isNot('firstCorners'),
        );
      });

      test('a corner number is never an amount', () {
        // "Corner 2" names a dancer (third_corner_opposite_test.dart), so its
        // number must not be read as how far the move goes; after an ordinal
        // it is not part of the name either.
        for (final line in [
          'Corner 2 Do-si-do',
          'Corner 2 allemande Left',
          'Corner 3 Right Shoulder Round',
          '1st corner 2 allemande left',
        ]) {
          final f = read(line).single;
          expect(f.params.containsKey('travel'), isFalse, reason: line);
        }
        expect(
          read('1st corner 2 allemande left').single.params['who'],
          isNot('opposites'),
        );
      });

      test('a new neighbor after a leading dancer is whom', () {
        final f = read('Larks give and take new neighbor').single;
        expect(f.move, 'give_and_take');
        expect(f.params['whom'], 'nextNeighbors');
      });
    });
  }
}
