import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// Partners are row-mates, neighbours column-mates; the role2s (R1-A, R2-B)
/// stand on one diagonal and the role1s on the other.
const List<String> base = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];

Formation applyOk(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op failed: $result');
  return (result as Ok<Formation, OpError>).value;
}

void main() {
  group('revolving_door (user-ruled 2026-11-22)', () {
    test('the leaders end where they began; the others trade places', () {
      expect(applyOk(const RevolvingDoor(), di(base)).toRolesNotation(), [
        'R1-A . . . L2-B',
        'L1-A . . . R2-B',
      ]);
    });

    test('role1s leading carry the role2s across instead', () {
      expect(
        applyOk(
          const RevolvingDoor(who: WhoSet.role1s, hand: Hand.left),
          di(base),
        ).toRolesNotation(),
        ['R2-B . . . L1-A', 'L2-B . . . R1-A'],
      );
    });

    test('agrees with the way The Caller\'s Box writes it out', () {
      // "Revolving door: star promenade 1/2; women allemande right 1/2". The
      // ruling is that figure's net, so the two must land identically.
      final promenaded = applyOk(const StarPromenade(), di(base));
      final written = applyOk(
        const Allemande(who: WhoSet.role2s, turn: 0.5),
        promenaded,
      );
      expect(applyOk(const RevolvingDoor(), di(base)), written);
    });

    test('hand and whom move nobody differently', () {
      expect(
        applyOk(
          const RevolvingDoor(hand: Hand.left, whom: WhoSet.neighbors),
          di(base),
        ),
        applyOk(const RevolvingDoor(), di(base)),
      );
    });

    test('a who naming two pairs has no single pair to carry', () {
      final result = const RevolvingDoor(who: WhoSet.partners).apply(di(base));
      expect(result, isA<Err<Formation, OpError>>());
      expect(
        (result as Err<Formation, OpError>).error.kind,
        ErrorKind.unresolvableDancerSet,
      );
    });
  });
}
