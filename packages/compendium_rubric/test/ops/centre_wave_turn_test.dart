import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:compendium_rubric/src/ops/transforms.dart' show waveHoldOf;
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

/// "Men walk forward; form long wave in center || women fall back": the
/// Larks of each hands four stand one above the other in c2, facing across.
Formation larksInTheCentre({int bands = 1}) => applyOk(
  const FormALongWave(who: WhoSet.role1s),
  di([
    for (var i = 0; i < bands; i++) ...[
      'R1-${String.fromCharCode(0x41 + 2 * i)} . . . '
          'L1-${String.fromCharCode(0x41 + 2 * i)}',
      'L2-${String.fromCharCode(0x42 + 2 * i)} . . . '
          'R2-${String.fromCharCode(0x42 + 2 * i)}',
    ],
  ]),
);

void main() {
  group('the centre pair of a centre long wave holds hands', () {
    test('the Larks of one hands four hold left hands', () {
      final wave = larksInTheCentre();
      expect(wave.toRolesNotation(), ['R1-A . L1-A . .', '. . L2-B . R2-B']);
      final pair = (a: at(wave, 0, 2), b: at(wave, 1, 2));
      expect(waveHoldOf(wave, pair)?.hand, Hand.left);
    });

    test('Larks of neighbouring hands fours are not one pair', () {
      final wave = larksInTheCentre(bands: 2);
      // L2-B (r1) and L1-C (r2) hold right hands down the centre line, but
      // they belong to two hands fours, so they are not a pair a turn uses.
      final pair = (a: at(wave, 1, 2), b: at(wave, 2, 2));
      expect(waveHoldOf(wave, pair), isNull);
    });
  });

  group('turning out of a centre long wave lands in a short wave', () {
    test(
      'Larks allemande left 3/4: the canonical wave, Larks in the centre',
      () {
        final after = applyOk(
          const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
          larksInTheCentre(),
        );
        expect(after.toRolesNotation(), ['. L2-B . . R2-B', 'R1-A . . L1-A .']);
        // Top row faces down, bottom row up (§8.5.1): neighbours join right
        // hands on the sides and the Larks join left in the centre.
        expect(facingAt(after, 0, 1), Facing.down);
        expect(facingAt(after, 0, 4), Facing.down);
        expect(facingAt(after, 1, 0), Facing.up);
        expect(facingAt(after, 1, 3), Facing.up);
      },
    );

    test('a quarter turns the pair the other way round', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 1.25),
        larksInTheCentre(),
      );
      expect(after.toRolesNotation(), ['. L1-A . . R2-B', 'R1-A . . L2-B .']);
      expect(facingAt(after, 0, 1), Facing.down);
      expect(facingAt(after, 1, 3), Facing.up);
    });

    test('every hands four turns', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
        larksInTheCentre(bands: 2),
      );
      expect(after.toRolesNotation(), [
        '. L2-B . . R2-B',
        'R1-A . . L1-A .',
        '. L2-D . . R2-D',
        'R1-C . . L1-C .',
      ]);
    });

    test('the wave then settles back to the ring for a neighbour swing', () {
      final turned = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
        larksInTheCentre(),
      );
      final swung = applyOk(const Swing(who: WhoSet.neighbors), turned);
      expect(swung.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
    });
  });

  group('what the centre turn does not cover', () {
    test('the wrong hand is still an across-the-set quarter', () {
      final error = applyErr(
        const Allemande(who: WhoSet.role1s, turn: 0.75),
        larksInTheCentre(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.detail, contains('across-the-set quarter'));
    });

    test('a shoulder round holds no hands, so it is still refused', () {
      final error = applyErr(
        const ShoulderRound(who: WhoSet.role1s, turn: 0.75),
        larksInTheCentre(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('without one dancer on each side there is no wave to join', () {
      final wave = larksInTheCentre();
      final robin = at(wave, 1, 4);
      final lopsided = wave.withUpdates({
        robin: wave.stateOf(robin).copyWith(position: const Position(1, 0)),
      });
      final error = applyErr(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
        lopsided,
      );
      expect(error.kind, ErrorKind.unresolvableDancerSet);
      expect(error.detail, contains('one on each side'));
    });
  });
}
