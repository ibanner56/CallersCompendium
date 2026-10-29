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

      test('contra corners is still the figure', () {
        expectWho('Ones turn contra corners', 'contra_corners', 'ones');
      });
    });
  }
}
