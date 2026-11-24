import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:compendium_rubric/src/engine/allemande_waves.dart';
import 'package:test/test.dart';

/// Jerry Goes to Camp (Caller's Box 10518) as the Caller's Box bridge reads
/// it. The Larks' left 1 1/2 in the centre and the neighbours' right 1 3/4
/// that follows only reach the progressed places when the Larks finish as
/// the centre of a short wave rather than settled back into the side lines.
const Map<String, Object?> _jerryGoesToCamp = {
  "title": "Jerry Goes to Camp",
  "form": "contra",
  "formation": {"shape": "dupleImproper"},
  "progression": "single",
  "figures": [
    {
      "move": "allemande",
      "params": {
        "who": "neighbors",
        "hand": "left",
        "travel": 1.75,
        "beats": 8,
      },
    },
    {
      "move": "allemande",
      "params": {"who": "role2s", "hand": "right", "travel": 1.5, "beats": 8},
    },
    {
      "move": "see_saw",
      "params": {"who": "partners", "beats": 8},
    },
    {
      "move": "hey",
      "params": {
        "length": "half",
        "pass1": "partners",
        "shoulder": "left",
        "pass2": "role1s",
        "beats": 8,
      },
    },
    {
      "move": "swing",
      "params": {"who": "partners", "beats": 16, "prefix": "balance"},
    },
    {
      "move": "allemande",
      "params": {"who": "role1s", "hand": "left", "travel": 1.5, "beats": 8},
    },
    {
      "move": "allemande",
      "params": {
        "who": "neighbors",
        "hand": "right",
        "travel": 1.75,
        "beats": 8,
      },
      "progression": true,
    },
  ],
};

/// Top Spin (Caller's Box 11211) as the Caller's Box bridge reads it. The
/// Larks' left 3/4 (figure 3) straight after the neighbours' half allemande
/// refuses from the side lines; danced from the short wave that half leaves,
/// it turns the Larks into a centre long wave.
const Map<String, Object?> _topSpin = {
  "title": "Top Spin",
  "form": "contra",
  "formation": {"shape": "dupleImproper"},
  "progression": "single",
  "figures": [
    {
      "move": "form_short_waves",
      "params": {
        "sides": "neighbors",
        "center": "role2s",
        "centerHand": "left",
        "balance": true,
        "beats": 4,
      },
    },
    {
      "move": "allemande",
      "params": {
        "who": "neighbors",
        "hand": "right",
        "travel": 0.5,
        "beats": 4,
      },
    },
    {
      "move": "allemande",
      "params": {"who": "role1s", "hand": "left", "travel": 0.75, "beats": 4},
    },
    {
      "move": "balance",
      "params": {"who": "role1s", "beats": 4},
    },
    {
      "move": "allemande",
      "params": {"who": "role1s", "hand": "left", "travel": 0.75, "beats": 4},
    },
    {
      "move": "swing",
      "params": {"who": "partners", "beats": 12},
    },
    {
      "move": "allemande",
      "params": {"who": "role2s", "hand": "left", "travel": 1.5, "beats": 8},
    },
    {
      "move": "swing",
      "params": {"who": "neighbors", "beats": 8},
    },
    {
      "move": "square_through",
      "params": {
        "places": 2,
        "who": "partners",
        "who2": "neighbors",
        "hand": "right",
        "balance": true,
        "beats": 8,
      },
    },
    {
      "move": "do_si_do",
      "params": {"who": "nextNeighbors", "travel": 1.25, "beats": 8},
    },
    {
      "move": "form_short_waves",
      "params": <String, Object?>{},
      "progression": true,
    },
  ],
};

Formation _di() => parseRolesNotation([
  'R1-A . . . L1-A',
  'L2-B . . . R2-B',
], type: FormationType.dupleImproper);

Formation _ok(Operation op, Formation input) {
  final result = op.apply(input);
  expect(result, isA<Ok<Formation, OpError>>(), reason: '$op: $result');
  return (result as Ok<Formation, OpError>).value;
}

Dance _parse(Map<String, Object?> record) =>
    (parseDance(record) as Ok<Dance, DanceParseError>).value;

bool _retried(CompileResult result) => result.warnings.any(
  (warning) => warning.kind == WarningKind.allemandeWaveRetry,
);

void main() {
  group('the short waves an allemande can leave', () {
    test('a centre allemande steps its turning pairs one column in', () {
      const allemande = Allemande(
        who: WhoSet.role1s,
        hand: Hand.left,
        turn: 1.5,
      );
      final handed = _di();
      final after = _ok(allemande, handed);
      expect(after.toRolesNotation(), ['R1-A . . . L2-B', 'L1-A . . . R2-B']);
      final waves = allemandeWaveReading(handed, after, allemande)!;
      expect(waves.toRolesNotation(), ['R1-A . . L2-B .', '. L1-A . . R2-B']);
      // A short wave faces its top row down and its bottom row up (§8.5.1).
      for (final id in waves.dancersInRow(0)) {
        expect(waves.stateOf(id).facing, Facing.down);
      }
      for (final id in waves.dancersInRow(1)) {
        expect(waves.stateOf(id).facing, Facing.up);
      }
    });

    test('a side allemande right forms the wave whose centre joins left', () {
      const allemande = Allemande(
        who: WhoSet.neighbors,
        hand: Hand.right,
        turn: 1.5,
      );
      final handed = _di();
      final after = _ok(allemande, handed);
      final waves = allemandeWaveReading(handed, after, allemande)!;
      final expected = _ok(
        const FormShortWaves(centerHand: Hand.left, center: null, sides: null),
        after,
      );
      expect(waves.toRolesNotation(), expected.toRolesNotation());
      expect(waves.toRolesNotation(), ['. L2-B . . R2-B', 'R1-A . . L1-A .']);
    });

    test('a quarter allemande already lands in a wave and has no reading', () {
      const allemande = Allemande(who: WhoSet.neighbors, turn: 0.75);
      final handed = _di();
      final after = _ok(allemande, handed);
      expect(allemandeWaveReading(handed, after, allemande), isNull);
    });
  });

  group('the compiler retries from those waves', () {
    test('when the dance lands elsewhere: Jerry Goes to Camp', () {
      // Hudson, 2026-11-24: Jerry Goes to Camp "should be able to take the
      // short wave after the 1.5 allemande and with a 1.75 allemande leave
      // dancers in progressed places correctly". Settled into the side lines
      // instead, it mismatches.
      final result = compile(_parse(_jerryGoesToCamp));
      expect(result, isA<Compiled>(), reason: '$result');
      expect(_retried(result), isTrue);
    });

    test('when the next figure refuses: Top Spin', () {
      final result = compile(_parse(_topSpin));
      expect(result, isA<Compiled>(), reason: '$result');
      expect(_retried(result), isTrue);
    });
  });
}
