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

void main() {
  final start = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

  // The user-ruled landings. A quarter builds the canonical wave -- neighbours
  // joining right on the sides, the centre pair joining left -- and a
  // three-quarter builds the *same* wave with the other role in the centre,
  // because the half turn trades the couples between rows first.
  const canonicalWave = ['. R1-A . . L1-A', 'L2-B . . R2-B .'];
  const rolesSwapped = ['. L2-B . . R2-B', 'R1-A . . L1-A .'];
  const mirrorWave = ['R1-A . . L1-A .', '. L2-B . . R2-B'];

  group('a quarter lands in a wave', () {
    test('do_si_do 1 1/4 right builds the canonical wave', () {
      final after = applyOk(
        const DoSiDo(who: WhoSet.neighbors, circling: 1.25),
        start,
      );
      expect(after.toRolesNotation(), canonicalWave);
    });

    test('allemande right 1 1/4 builds the same wave', () {
      final after = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      expect(after.toRolesNotation(), canonicalWave);
    });

    test('the shoulder mirrors the wave', () {
      final after = applyOk(
        const DoSiDo(
          who: WhoSet.neighbors,
          circling: 1.25,
          shoulder: Hand.left,
        ),
        start,
      );
      expect(after.toRolesNotation(), mirrorWave);
    });

    test('the allemande hand mirrors it the same way', () {
      final after = applyOk(
        const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 1.25),
        start,
      );
      expect(after.toRolesNotation(), mirrorWave);
    });

    test('shoulder_round right 1 1/4 builds the same wave', () {
      final after = applyOk(
        const ShoulderRound(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      expect(after.toRolesNotation(), canonicalWave);
    });

    test('and its shoulder mirrors it, as the other two do', () {
      final after = applyOk(
        const ShoulderRound(
          who: WhoSet.neighbors,
          shoulder: Hand.left,
          turn: 1.25,
        ),
        start,
      );
      expect(after.toRolesNotation(), mirrorWave);
    });

    test('only the fraction matters, so 0.25 and 2.25 agree with 1.25', () {
      for (final amount in [0.25, 1.25, 2.25]) {
        expect(
          applyOk(
            Allemande(who: WhoSet.neighbors, turn: amount),
            start,
          ).toRolesNotation(),
          canonicalWave,
          reason: 'turn: $amount',
        );
      }
    });
  });

  group('a three-quarter is a half and then a quarter', () {
    test('allemande right 1 3/4 keeps the handedness and swaps the '
        'centre', () {
      final after = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.75),
        start,
      );
      expect(after.toRolesNotation(), rolesSwapped);
    });

    test('do_si_do 1 3/4 right lands identically', () {
      final after = applyOk(
        const DoSiDo(who: WhoSet.neighbors, circling: 1.75),
        start,
      );
      expect(after.toRolesNotation(), rolesSwapped);
    });

    test('shoulder_round 1 3/4 right lands identically too', () {
      final after = applyOk(
        const ShoulderRound(who: WhoSet.neighbors, turn: 1.75),
        start,
      );
      expect(after.toRolesNotation(), rolesSwapped);
    });

    test('it is literally the half turn followed by the quarter', () {
      final halved = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.5),
        start,
      );
      final thenQuartered = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.25),
        halved,
      );

      expect(
        thenQuartered.toRolesNotation(),
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 0.75),
          start,
        ).toRolesNotation(),
      );
    });

    test('the centre cells hold the other role than a quarter leaves '
        'there', () {
      final quarter = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      final threeQuarter = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.75),
        start,
      );

      Set<Role> centres(Formation f) => {
        for (final id in f.dancers.keys)
          if (f.stateOf(id).col == 1 || f.stateOf(id).col == 3) id.role,
      };

      expect(centres(quarter), {Role.robin});
      expect(centres(threeQuarter), {Role.lark});
    });
  });

  group('the wave owns the facing (§8.5.1)', () {
    test('a quarter leaves concrete alternating facing', () {
      final after = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.25),
        start,
      );

      for (final id in after.dancers.keys) {
        final state = after.stateOf(id);
        expect(
          state.facing,
          state.row == 0 ? Facing.down : Facing.up,
          reason: '$id faces the wrong way for the wave',
        );
      }
    });

    test('a three-quarter reverses facing, as its half turn should', () {
      // Row-derived, so the claim is about the quarter and the three-quarter
      // relative to each other: the half turn trades the rows, and the wave's
      // facing follows the row.
      final quarter = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      final threeQuarter = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.75),
        start,
      );

      for (final id in threeQuarter.dancers.keys) {
        expect(
          threeQuarter.stateOf(id).facing,
          quarter.stateOf(id).facing.reversed,
          reason: '$id',
        );
      }
    });

    test('the wave imposes its facing rather than carrying the input '
        'through', () {
      // The ruling that decides this: a figure landing in a wave takes the
      // wave's resting facing. Everyone starts facing Down here, so a figure
      // that carried facing through -- which is exactly what `do_si_do`
      // otherwise does -- would leave the bottom row facing Down too.
      final allDown = parseRolesNotation(
        const ['R1-A . . . L1-A', 'L2-B . . . R2-B'],
        type: FormationType.dupleImproper,
        defaultFacing: Facing.down,
      );
      final after = applyOk(
        const DoSiDo(who: WhoSet.neighbors, circling: 1.25),
        allDown,
      );

      for (final id in after.dancers.keys) {
        final state = after.stateOf(id);
        expect(state.facing, state.row == 0 ? Facing.down : Facing.up);
      }
    });

    test('the wave overrides shoulder_round\'s focus facing', () {
      // shoulder_round is the one figure of the three that normally *sets* a
      // determinate facing of its own, across the set, from the passing
      // shoulder. In a wave that rule loses: everyone takes the wave's resting
      // facing instead, which runs along the set, not across it.
      final quarter = applyOk(
        const ShoulderRound(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      final whole = applyOk(const ShoulderRound(who: WhoSet.neighbors), start);

      for (final id in whole.dancers.keys) {
        expect(
          whole.stateOf(id).facing,
          anyOf(Facing.acrossEast, Facing.acrossWest),
          reason: '$id should face across on a whole turn',
        );
      }
      for (final id in quarter.dancers.keys) {
        final state = quarter.stateOf(id);
        expect(state.facing, state.row == 0 ? Facing.down : Facing.up);
      }
    });
  });

  group('a quarter is defined along the set only', () {
    test('an across-the-set pair is refused', () {
      final error = applyErr(
        const Allemande(who: WhoSet.partners, turn: 1.25),
        start,
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('across'));
    });

    test('do_si_do refuses it the same way', () {
      final error = applyErr(
        const DoSiDo(who: WhoSet.partners, circling: 0.75),
        start,
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('so does shoulder_round', () {
      final error = applyErr(
        const ShoulderRound(who: WhoSet.partners, turn: 1.25),
        start,
      );
      expect(error.kind, ErrorKind.unsupportedParam);
      expect(error.message, contains('across'));
    });

    test('whole and half amounts across the set are still fine', () {
      expect(
        applyOk(
          const DoSiDo(who: WhoSet.partners, circling: 1.5),
          start,
        ).toRolesNotation(),
        ['L1-A . . . R1-A', 'R2-B . . . L2-B'],
      );
    });
  });

  group('the rest of the family still refuses both quarter cases', () {
    test('two_hand_turn has no direction token to fix the wave with', () {
      for (final amount in [0.25, 0.75]) {
        final error = applyErr(
          TwoHandTurn(who: WhoSet.neighbors, turn: amount),
          start,
        );
        expect(error.kind, ErrorKind.unsupportedParam, reason: 'turn: $amount');
      }
    });

    test('a three-quarter is refused where a quarter is', () {
      final error = applyErr(
        const StarPromenade(turn: 0.75),
        di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });
  });

  group('the landing agrees with form_short_waves', () {
    test('an allemande right 1 1/4 is the wave that figure builds by '
        'default', () {
      expect(
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 1.25),
          start,
        ).toRolesNotation(),
        applyOk(const FormShortWaves(), start).toRolesNotation(),
      );
    });

    test('and it settles back out like any other wave', () {
      final wave = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 1.25),
        start,
      );
      expect(
        applyOk(const StandStill(), wave).toRolesNotation(),
        wave.toRolesNotation(),
      );
      expect(
        applyOk(const LongLines(), wave).toRolesNotation(),
        start.toRolesNotation(),
      );
    });
  });

  _fromAWave();
}

/// A turn that starts from a wave the pair is already holding (§8.5.7).
///
/// The sequence is the one the Caller's Box dances "Seagull", "You Can't Get
/// There From Here" and "Need for Speed" open with: balance a wave, allemande
/// right 3/4 to a long wave, balance it, allemande right 3/4 to a wave with the
/// other role in the centre. Every landing below was worked by hand by turning
/// the pair rigidly about its own midpoint.
void _fromAWave() {
  final start = di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
  DancerId dancer(Formation f, String name) =>
      f.dancers.keys.singleWhere((id) => '$id' == name);
  Facing facingOf(Formation f, String name) =>
      f.stateOf(dancer(f, name)).facing;

  group('a turn from a wave turns the pair from where it stands', () {
    late Formation wave;
    setUp(() {
      // Neighbours hold right hands on the sides; the Robins are in the centre.
      wave = applyOk(
        const FormShortWaves(center: WhoSet.role2s, centerHand: Hand.left),
        start,
      );
    });

    test('the starting wave is the one the dances balance', () {
      expect(wave.toRolesNotation(), ['. R1-A . . L1-A', 'L2-B . . R2-B .']);
    });

    test('a wave and an allemande right 3/4 make a long wave', () {
      final long = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        wave,
      );
      expect(long.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      // "Balance long wave (neighbours right, women face in)".
      expect(facingOf(long, 'R-A'), Facing.acrossEast);
      expect(facingOf(long, 'R-B'), Facing.acrossWest);
      expect(facingOf(long, 'L-B'), Facing.acrossWest);
      expect(facingOf(long, 'L-A'), Facing.acrossEast);
      for (final id in long.dancers.keys) {
        final partner = long.dancers.keys.firstWhere(
          (other) =>
              other != id && long.stateOf(other).col == long.stateOf(id).col,
        );
        expect(
          waveHoldOf(long, (a: id, b: partner))?.hand,
          Hand.right,
          reason: 'the neighbours still hold right hands',
        );
      }
    });

    test('and a second 3/4 puts the other role in the centre', () {
      final long = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        wave,
      );
      final back = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        long,
      );
      expect(back.toRolesNotation(), ['. L2-B . . R2-B', 'R1-A . . L1-A .']);
      // The balance the dances call next names the Larks in the centre, and
      // the shape agrees; it would refuse the Robins.
      expect(
        applyOk(
          const FormShortWaves(center: WhoSet.role1s, centerHand: Hand.left),
          back,
        ).toRolesNotation(),
        back.toRolesNotation(),
      );
      expect(
        applyErr(
          const FormShortWaves(center: WhoSet.role2s, centerHand: Hand.left),
          back,
        ).kind,
        ErrorKind.whoMismatch,
      );
    });

    test('a quarter turns the other way round to the same long wave '
        'column', () {
      final quarter = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.25),
        wave,
      );
      expect(quarter.toRolesNotation(), ['L2-B . . . R2-B', 'R1-A . . . L1-A']);
      expect(facingOf(quarter, 'L-B'), Facing.acrossEast);
      expect(facingOf(quarter, 'R-A'), Facing.acrossWest);
    });

    test('a long wave formed by form_long_waves turns the same way', () {
      final long = applyOk(const FormLongWaves(who: WhoSet.role2s), start);
      expect(
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 0.75),
          long,
        ).toRolesNotation(),
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 0.75),
          applyOk(const Allemande(who: WhoSet.neighbors, turn: 0.75), wave),
        ).toRolesNotation(),
      );
    });

    test('a pair not holding the hand turns from facing, as before', () {
      // The ruling covers a pair already holding hands. An allemande left
      // from a right-hand wave is not that: the pair leave the wave and turn
      // from facing each other, exactly as every figure did before it.
      expect(
        applyOk(
          const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 0.75),
          wave,
        ).toRolesNotation(),
        applyOk(
          const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 0.75),
          start,
        ).toRolesNotation(),
      );
    });

    test('a whole or half turn still leaves the wave first', () {
      expect(
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 1.5),
          wave,
        ).toRolesNotation(),
        applyOk(
          const Allemande(who: WhoSet.neighbors, turn: 1.5),
          start,
        ).toRolesNotation(),
      );
    });

    test('a quarter from the long wave turns the rest of the way home', () {
      // Three quarters and one quarter are a whole turn.
      final long = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        wave,
      );
      final home = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.25),
        long,
      );
      expect(home.toRolesNotation(), wave.toRolesNotation());
      for (final id in home.dancers.keys) {
        expect(home.stateOf(id).facing, wave.stateOf(id).facing, reason: '$id');
      }
    });

    test('a left-hand wave turns counter-clockwise', () {
      // Neighbours holding left hands on the sides: the mirror wave.
      final left = applyOk(
        const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 1.25),
        start,
      );
      expect(left.toRolesNotation(), ['R1-A . . L1-A .', '. L2-B . . R2-B']);
      final pair = (a: dancer(left, 'R-A'), b: dancer(left, 'L-B'));
      expect(waveHoldOf(left, pair)?.hand, Hand.left);

      final long = applyOk(
        const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 0.75),
        left,
      );
      expect(long.toRolesNotation(), ['R1-A . . . L1-A', 'L2-B . . . R2-B']);
      expect(facingOf(long, 'R-A'), Facing.acrossWest);
      expect(facingOf(long, 'L-B'), Facing.acrossEast);
      expect(waveHoldOf(long, pair)?.hand, Hand.left);

      final back = applyOk(
        const Allemande(who: WhoSet.neighbors, hand: Hand.left, turn: 0.75),
        long,
      );
      expect(back.toRolesNotation(), ['L2-B . . R2-B .', '. R1-A . . L1-A']);
      expect(waveHoldOf(back, pair)?.hand, Hand.left);
    });

    test('a held pair and a pair that holds nothing share a band', () {
      // Turn the east pair back to back: the west pair still holds its wave
      // and turns from it, the east pair leaves the wave and turns from
      // facing, and neither lands on the other.
      final eastTurned = wave.withUpdates({
        for (final name in ['R-B', 'L-A'])
          dancer(wave, name): wave
              .stateOf(dancer(wave, name))
              .copyWith(facing: facingOf(wave, name).reversed),
      });
      final after = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        eastTurned,
      );
      expect(
        after.stateOf(dancer(after, 'R-A')).position,
        const Position(0, 0),
      );
      expect(
        after.stateOf(dancer(after, 'L-B')).position,
        const Position(1, 0),
      );
      expect(facingOf(after, 'R-A'), Facing.acrossEast);
      final east = applyOk(
        const Allemande(who: WhoSet.neighbors, turn: 0.75),
        start,
      );
      for (final name in ['R-B', 'L-A']) {
        expect(
          after.stateOf(dancer(after, name)).position,
          east.stateOf(dancer(east, name)).position,
          reason: '$name turns from facing, as before',
        );
      }
    });

    test('a reaching quarter still settles an offset in the end rows', () {
      // The next neighbours are danced one band phase over, where the end
      // rows wait out. An offset standing there is settled exactly as a half
      // turn settles it.
      final passed = di(const [
        '. L2-B . . R2-B',
        'R1-A . . . L1-A',
        'L2-D . . . R2-D',
        'R1-C . . . L1-C',
        'L2-F . . . R2-F',
        'R1-E . . . L1-E',
      ]);
      Position lb(Operation op) {
        final after = applyOk(op, passed);
        return after.stateOf(dancer(after, 'L-B')).position;
      }

      expect(
        lb(const Allemande(who: WhoSet.nextNeighbors, turn: 0.75)),
        lb(const Allemande(who: WhoSet.nextNeighbors, turn: 0.5)),
      );
      expect(lb(const Allemande(who: WhoSet.nextNeighbors, turn: 0.5)).col, 0);
    });

    test('dancers back to back in wave cells hold nothing', () {
      // The same cells as a short-wave side pair, facing the other way: the
      // top row faces up. That is not a hold, whatever the cells say.
      final turned = {
        for (final id in wave.dancers.keys)
          id: wave
              .stateOf(id)
              .copyWith(facing: wave.stateOf(id).facing.reversed),
      };
      final backToBack = wave.withUpdates(turned);
      final pair = (a: dancer(wave, 'L-B'), b: dancer(wave, 'R-A'));
      expect(waveHoldOf(wave, pair)?.hand, Hand.right, reason: 'control');
      expect(waveHoldOf(backToBack, pair), isNull);
    });
  });
}
