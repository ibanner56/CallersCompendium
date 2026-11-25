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
      expect(facingAt(after, 0, 4), Facing.down);
      expect(facingAt(after, 1, 0), Facing.up);
      expect(facingAt(after, 1, 3), Facing.up);
    });

    test('the ends join the wave holding the other hand', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
        larksInTheCentre(),
      );
      // Each side pair of the new short wave reads back as holding right.
      for (final (end, centre) in [((1, 0), (0, 1)), ((0, 4), (1, 3))]) {
        final pair = (
          a: at(after, end.$1, end.$2),
          b: at(after, centre.$1, centre.$2),
        );
        expect(waveHoldOf(after, pair), (
          shape: WaveHoldShape.short,
          hand: Hand.right,
        ));
      }
    });

    test('Robins in the centre turn by the right into the mirror wave', () {
      final wave = applyOk(
        const FormALongWave(who: WhoSet.role2s),
        di(['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );
      expect(wave.toRolesNotation(), ['. . R1-A . L1-A', 'L2-B . R2-B . .']);
      final after = applyOk(
        const Allemande(who: WhoSet.role2s, turn: 0.75),
        wave,
      );
      // Top row Down, bottom row Up in the left-handed layout: the Larks
      // hold left on the ends and the Robins right in the centre.
      expect(after.toRolesNotation(), ['L2-B . . R2-B .', '. R1-A . . L1-A']);
      final west = (a: at(after, 0, 0), b: at(after, 1, 1));
      expect(waveHoldOf(after, west), (
        shape: WaveHoldShape.short,
        hand: Hand.left,
      ));
      expect(facingAt(after, 0, 3), Facing.down);
      expect(facingAt(after, 1, 4), Facing.up);
    });

    test('bands that start a row down, with couples out at the ends', () {
      // A Becket slide sends the end rows out and shifts the bands to (1,2)
      // and (3,4); the Larks of those bands then hold right in the centre.
      final slid = applyOk(
        const SlideAlongSet(),
        parseRolesNotation([
          'L1-A . . . R1-A',
          'R2-B . . . L2-B',
          'L1-C . . . R1-C',
          'R2-D . . . L2-D',
          'L1-E . . . R1-E',
          'R2-F . . . L2-F',
        ], type: FormationType.becketCw),
      );
      final wave = applyOk(const FormALongWave(who: WhoSet.role1s), slid);
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, turn: 0.75),
        wave,
      );
      expect(after.toRolesNotation(), [
        'R2-B . . . L1-A',
        'R2-D . . L2-B .',
        '. L1-C . . R1-A',
        'R2-F . . L2-D .',
        '. L1-E . . R1-C',
        'L2-F . . . R1-E',
      ]);
      // The couples standing out are left exactly as they were.
      for (final row in [0, after.lastRow]) {
        for (final id in after.dancersInRow(row)) {
          expect(after.stateOf(id), wave.stateOf(id));
        }
      }
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

  group('the centre pair of a short wave turns into a centre long wave', () {
    /// The canonical short wave, Larks joined left in the centre.
    Formation canonicalWave() => applyOk(
      const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
      larksInTheCentre(),
    );

    test('the Larks in the middle of the line hold left hands', () {
      final wave = canonicalWave();
      expect(wave.toRolesNotation(), ['. L2-B . . R2-B', 'R1-A . . L1-A .']);
      final pair = (a: at(wave, 0, 1), b: at(wave, 1, 3));
      expect(waveHoldOf(wave, pair), (
        shape: WaveHoldShape.shortCentre,
        hand: Hand.left,
      ));
    });

    test('Larks allemande left 3/4: rigidly into c2, facing across', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.75),
        canonicalWave(),
      );
      // Counter-clockwise three quarters carries the western Lark (L2-B)
      // north, into the band's top row; the Robins stay where they stand.
      expect(after.toRolesNotation(), ['. . L2-B . R2-B', 'R1-A . L1-A . .']);
      expect(facingAt(after, 0, 2), Facing.acrossWest);
      expect(facingAt(after, 1, 2), Facing.acrossEast);
    });

    test('a quarter carries the other Lark north', () {
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, hand: Hand.left, turn: 0.25),
        canonicalWave(),
      );
      expect(after.toRolesNotation(), ['. . L1-A . R2-B', 'R1-A . L2-B . .']);
    });
  });

  group('what the centre turn does not cover', () {
    test('the wrong hand leaves the wave and turns from across the set', () {
      // Not holding right hands, the Larks settle back to their lines and
      // turn the across-the-set quarter (§8.5.6), which lands them in the
      // centre column again, now holding right hands.
      final after = applyOk(
        const Allemande(who: WhoSet.role1s, turn: 0.75),
        larksInTheCentre(),
      );
      expect(after.toRolesNotation(), ['R1-A . L1-A . .', '. . L2-B . R2-B']);
      expect(facingAt(after, 0, 2), Facing.acrossEast);
      expect(facingAt(after, 1, 2), Facing.acrossWest);
      final pair = (a: at(after, 0, 2), b: at(after, 1, 2));
      expect(waveHoldOf(after, pair)?.hand, Hand.right);
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
