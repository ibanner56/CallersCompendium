// The across-the-set quarter of `allemande` (docs/fundamentals.md §8.5.6):
// a pair facing each other across the set turns a quarter or three quarters
// into the centre column. Agent's call, 2026-11-25.
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:compendium_rubric/src/ops/transforms.dart'
    show WaveHoldShape, waveHoldOf;
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

OpError applyErr(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Err<Formation, OpError>>(), reason: '$op passed: $result');
  return (result as Err<Formation, OpError>).error;
}

DancerId at(Formation f, int row, int col) => f.dancerAt(Position(row, col))!;

Facing facingAt(Formation f, int row, int col) =>
    f.stateOf(at(f, row, col)).facing;

/// The Robins of one hands four on a diagonal across the set, as after long
/// lines in Mary Cay's Reel (Caller's Box 10579): R1-A on the east side of
/// the top row, R2-B on the west side of the bottom row.
Formation robinsOnTheDiagonal() => di(['L1-A . . . R1-A', 'R2-B . . . L2-B']);

void main() {
  group('an across-the-set quarter lands in the centre column', () {
    test('Robins allemande right 3/4: the eastern Robin goes north', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role2s, turn: 0.75),
        robinsOnTheDiagonal(),
      );
      expect(after.toRolesNotation(), ['L1-A . R1-A . .', '. . R2-B . L2-B']);
      // Holding right hands down the centre line: the northern dancer faces
      // east, so their right hand is to the south.
      expect(facingAt(after, 0, 2), Facing.acrossEast);
      expect(facingAt(after, 1, 2), Facing.acrossWest);
      final hold = waveHoldOf(after, (a: at(after, 0, 2), b: at(after, 1, 2)));
      expect(hold?.shape, WaveHoldShape.centre);
      expect(hold?.hand, Hand.right);
    });

    test(
      'a right quarter turns the other way: the eastern Robin goes south',
      () {
        final after = applyOk(
          const Allemande(who: WhoSet.role2s, turn: 0.25),
          robinsOnTheDiagonal(),
        );
        expect(after.toRolesNotation(), ['L1-A . R2-B . .', '. . R1-A . L2-B']);
        expect(facingAt(after, 0, 2), Facing.acrossEast);
      },
    );

    test('a left 3/4 is the mirror, holding left hands', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role2s, hand: Hand.left, turn: 0.75),
        robinsOnTheDiagonal(),
      );
      expect(after.toRolesNotation(), ['L1-A . R2-B . .', '. . R1-A . L2-B']);
      expect(facingAt(after, 0, 2), Facing.acrossWest);
      expect(facingAt(after, 1, 2), Facing.acrossEast);
      final hold = waveHoldOf(after, (a: at(after, 0, 2), b: at(after, 1, 2)));
      expect(hold?.hand, Hand.left);
    });

    test('a pair straight across uses its band\'s other row', () {
      final after = applyOk(
        const Allemande(who: WhoSet.partners, turn: 0.75),
        // Only the 1s are partners straight across; the 2s stand along.
        di(['L1-A . . . R1-A', '. . . . .']),
      );
      expect(after.toRolesNotation(), ['. . R1-A . .', '. . L1-A . .']);
    });
  });

  group('what the across-the-set quarter does not cover', () {
    test('two pairs of one band claiming its centre cells still refuse', () {
      // Partners straight across in both couples would both need the band's
      // two centre cells; which way that resolves is not known.
      final error = applyErr(
        const Allemande(who: WhoSet.partners, turn: 0.75),
        di(['L1-A . . . R1-A', 'R2-B . . . L2-B']),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('across-the-set quarter'));
    });

    test('a pair whose centre cells are taken still refuses', () {
      final error = applyErr(
        const Allemande(who: WhoSet.role2s, turn: 0.75),
        di(['L1-A . L2-B . R1-A', 'R2-B . . . .']),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('across-the-set quarter'));
    });
  });
}
