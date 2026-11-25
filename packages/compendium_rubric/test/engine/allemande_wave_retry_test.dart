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

List<int?> _retriedAt(CompileResult result) => [
  for (final warning in result.warnings)
    if (warning.kind == WarningKind.allemandeWaveRetry) warning.opIndex,
];

Map<String, Object?> _allemande(String who, String hand, num travel) => {
  'move': 'allemande',
  'params': {'who': who, 'hand': hand, 'travel': travel, 'beats': 8},
};

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

    test('partners who finish in one row are read the same way', () {
      // Partners stand in one row in Duple Improper. Hudson ruled
      // (2026-11-25) that their allemande 1 1/2 gets the short-wave reading
      // too: it is only a retry, kept when the dance compiles from it.
      const allemande = Allemande(
        who: WhoSet.partners,
        hand: Hand.right,
        turn: 1.5,
      );
      final handed = _di();
      final after = _ok(allemande, handed);
      final waves = allemandeWaveReading(handed, after, allemande)!;
      expect(waves.toRolesNotation(), ['. L1-A . R1-A .', '. R2-B . L2-B .']);
      for (final id in waves.dancersInRow(0)) {
        expect(waves.stateOf(id).facing, Facing.down);
      }
      for (final id in waves.dancersInRow(1)) {
        expect(waves.stateOf(id).facing, Facing.up);
      }
    });

    test('a pair whose step in would land on another dancer has none', () {
      // In a line of four the ones stand at the ends, c0 and c4, with the
      // twos between them: stepping the ones in would put two dancers in
      // one cell, so there is no reading (from review).
      final handed = parseRolesNotation([
        'R1-A L2-B . R2-B L1-A',
        'R1-C L2-D . R2-D L1-C',
      ], type: FormationType.dupleImproper);
      const allemande = Allemande(who: WhoSet.ones, hand: Hand.right);
      final after = _ok(allemande, handed);
      expect(allemandeWaveReading(handed, after, allemande), isNull);
    });

    test('a flagged side allemande is still read on the side', () {
      // Its change-over crosses the end couples, so read from where they end
      // the neighbours would look across the set; they started along it.
      final handed = parseRolesNotation([
        'R1-A . . . L1-A',
        'L2-B . . . R2-B',
        'R1-C . . . L1-C',
        'L2-D . . . R2-D',
      ], type: FormationType.dupleImproper);
      const allemande = Allemande(
        who: WhoSet.neighbors,
        hand: Hand.right,
        turn: 1.5,
      );
      const invocation = OperationInvocation(allemande, progression: true);
      final after = (invocation.apply(handed) as Ok<Formation, OpError>).value;
      final waves = allemandeWaveReading(handed, after, allemande)!;
      final expected = _ok(
        const FormShortWaves(centerHand: Hand.left, center: null, sides: null),
        after,
      );
      expect(waves.toRolesNotation(), expected.toRolesNotation());
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
      // Figure 3 (index 2), the Larks' 3/4 after the neighbours' half.
      expect(_retriedAt(result), [2]);
    });

    test('the mismatch retry is warned at the figure after the allemande', () {
      // Jerry's Larks' 1 1/2 is figure 6 (index 5).
      expect(_retriedAt(compile(_parse(_jerryGoesToCamp))), [6]);
    });

    test('a dance that compiles as written is not retried', () {
      final record = {
        ..._jerryGoesToCamp,
        'figures': [
          // Has a side reading, which the dance never needs.
          {
            'move': 'allemande',
            'params': {
              'who': 'neighbors',
              'hand': 'right',
              'travel': 1.0,
              'beats': 8,
            },
          },
          {
            'move': 'allemande',
            'params': {
              'who': 'neighbors',
              'hand': 'right',
              'travel': 1.5,
              'beats': 8,
            },
            'progression': true,
          },
        ],
      };
      final result = compile(_parse(record));
      expect(result, isA<Compiled>(), reason: '$result');
      expect(_retried(result), isFalse);
    });

    test('a reading the next figure refuses from too is not kept', () {
      // Partners' allemande 1 1/2 is read in one row (user-ruled
      // 2026-11-25), but the Larks' 3/4 across the set refuses from that
      // reading too, so the refusal stands exactly as it did before.
      final record = {
        ..._jerryGoesToCamp,
        'figures': [
          {
            'move': 'allemande',
            'params': {
              'who': 'partners',
              'hand': 'right',
              'travel': 1.5,
              'beats': 8,
            },
          },
          {
            'move': 'allemande',
            'params': {
              'who': 'role1s',
              'hand': 'left',
              'travel': 0.75,
              'beats': 8,
            },
            'progression': true,
          },
        ],
      };
      final result = compile(_parse(record));
      expect(result, isA<CompileError>(), reason: '$result');
      expect((result as CompileError).opIndex, 1);
      expect(result.error.kind, ErrorKind.unsupportedParam);
      expect(_retried(result), isFalse);
    });

    test('a retry that refuses too reports the original refusal', () {
      // The neighbours' right 1 1/2 has a side reading, so the swing is
      // retried from the short waves; the partners are no swing pair there
      // either, and the side-line refusal comes back unchanged.
      final result = compile(
        _parse({
          ..._jerryGoesToCamp,
          'figures': [
            _allemande('neighbors', 'right', 1.5),
            {
              'move': 'swing',
              'params': {'who': 'partners', 'beats': 16},
              'progression': true,
            },
          ],
        }),
      );
      expect(result, isA<CompileError>(), reason: '$result');
      expect((result as CompileError).opIndex, 1);
      expect(result.error.kind, ErrorKind.whoMismatch);
      expect(result.error.detail, contains('in swing position in column 0'));
      expect(_retried(result), isFalse);
    });

    test('a retry that lands elsewhere too reports the original mismatch', () {
      // The first allemande has a side reading; nothing moves anyone on, so
      // the dance mismatches from the side lines and from the waves alike.
      final record = {
        ..._jerryGoesToCamp,
        'figures': [
          _allemande('neighbors', 'right', 1.0),
          {..._allemande('neighbors', 'right', 1.0), 'progression': true},
        ],
      };
      final dance = _parse(record);
      final result = compile(dance);
      expect(result, isA<Mismatch>(), reason: '$result');
      // The side-line fold's own end: everyone back where they started.
      expect(
        (result as Mismatch).actual.toRolesNotation(),
        dance.instantiate().toRolesNotation(),
      );
      expect(_retried(result), isFalse);
    });
  });
}
