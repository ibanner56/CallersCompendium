import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: a bare `L`/`R` is a direction only straight after a move that takes
/// one, and `R&L` is right and left through (maintainer decisions). Both the
/// import fan-out and the editor's free-text entry read them.
void main() {
  final readers = {
    'import': (String line) => parseFigureLinesFanOut(line, beats: 8),
    'free-text entry': (String line) => parseFreeTextFigureEntry(line),
  };

  for (final MapEntry(key: path, value: read) in readers.entries) {
    group(path, () {
      Figure single(String line) {
        final figures = read(line);
        expect(figures, hasLength(1), reason: line);
        return figures.single;
      }

      void expectMove(String line, String move, Map<String, Object?> params) {
        final f = single(line);
        expect(f.move, move, reason: line);
        for (final e in params.entries) {
          expect(f.params[e.key], e.value, reason: '$line: ${e.key}');
        }
      }

      test('a bare side after a move is its direction, hand or shoulder', () {
        expectMove('Circle L', 'circle', {'direction': 'left'});
        expectMove('Slice L', 'slice', {'slice': 'left'});
        expectMove('Larks pull by L', 'pull_by', {
          'who': 'role1s',
          'hand': 'left',
        });
        expectMove('N3 pull by L', 'pull_by', {
          'who': 'thirdNeighbors',
          'hand': 'left',
        });
        expectMove('Slide L', 'slide_along_set', {'slide': 'left'});
        expectMove('Zig L, Zag R', 'zig_zag', {'slide': 'left'});
        expectMove('Larks pass L', 'pass_by', {'shoulder': 'left'});
        expectMove('Larks pass R shoulder', 'pass_by', {'shoulder': 'right'});
      });

      test('"alle" is the allemande', () {
        expectMove('Neighbor alle R 1.5', 'allemande', {
          'who': 'neighbors',
          'hand': 'right',
          'travel': 1.5,
        });
      });

      test('a lone side anywhere else stays as written', () {
        // After a dancer or a word that is not one of the moves, the letter is
        // not spelled, so these lines do not read as if it were.
        for (final line in [
          'Allemande neighbor R',
          'Full Hey, Larks start R shoulder',
          'Ring balance and spin R',
        ]) {
          expect(single(line).isCustom, isTrue, reason: line);
        }
      });

      test('R&L is right and left through', () {
        expect(single('R&L').move, 'right_left_through');
        expect(single('R&L thru').move, 'right_left_through');
        expect(single('R & L').move, 'right_left_through');
      });

      // A pin, not a guard: the leftover "grand" keeps the right and left
      // through from matching.
      test('Grand R&L is not a right and left through', () {
        expect(
          read('Grand R&L').map((f) => f.move),
          isNot(contains('right_left_through')),
        );
      });
    });
  }
}
