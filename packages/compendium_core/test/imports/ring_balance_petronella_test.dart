import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// #1975: Caller's Companion writes the petronella as "Ring balance, spin to
/// the right", and a bare "Ring balance" is balance the ring. Both the import
/// fan-out and the editor's free-text entry read them.
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

      test('a ring balance and a spin to the right is the petronella', () {
        for (final line in [
          'Ring balance, spin to the right',
          'Ring balance and spin right',
          'Balance the ring, spin to the right',
          'Balance ring, spin right',
        ]) {
          final f = single(line);
          expect(f.move, 'petronella', reason: line);
          expect(f.params['balance'], isTrue, reason: line);
        }
      });

      test('a bracketed note after it is kept', () {
        final f = single('Ring balance, spin to the right (look for Partner)');
        expect(f.move, 'petronella');
        expect(f.note, 'look for Partner');
      });

      test('a bare ring balance is balance the ring', () {
        expect(single('Ring balance').move, 'balance_the_ring');
      });

      test('only a spin to the right after the balance is the petronella', () {
        for (final line in [
          'Ring balance, spin to the left',
          'Spin to the right, ring balance',
        ]) {
          expect(
            read(line).map((f) => f.move),
            isNot(contains('petronella')),
            reason: line,
          );
        }
      });
    });
  }
}
