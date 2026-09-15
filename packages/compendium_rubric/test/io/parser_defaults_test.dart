import 'dart:convert';

import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// The parser's default table, pinned figure by figure.
///
/// A dance record names a move and supplies only the parameters the caller
/// cared about; everything else comes from the builder's defaults. Those
/// defaults are transcribed from the upstream compendium, and a wrong one is
/// invisible — the dance still parses, still compiles, and still produces a
/// confident answer, just for a different dance than the one on the card.
///
/// So every registered move is parsed here from a bare record and compared
/// against a typed expectation. The comparison leans on `Operation ==`, which
/// `value_semantics_test.dart` proves is field-complete; between the two files
/// a mis-wired default has nowhere to hide.

/// Parses a one-figure dance and returns the operation it built.
Operation parseFigure(String move, [Map<String, Object?> params = const {}]) {
  final record = {
    'title': 'default probe',
    'formation': {'shape': 'dupleImproper'},
    'progression': 'single',
    'figures': [
      {'move': move, 'params': params},
    ],
  };
  final result = parseDanceJson(jsonEncode(record));
  return switch (result) {
    Ok(:final value) => value.figures.single.operation,
    Err(:final error) => fail('$move did not parse: ${error.message}'),
  };
}

/// Every registered move, and the figure a bare record must build.
const Map<String, Operation> defaults = {
  'allemande': Allemande(),
  'balance': Balance(),
  'balance_the_ring': BalanceTheRing(),
  'box_circulate': BoxCirculate(who: WhoSet.role2s),
  'box_the_gnat': BoxTheGnat(),
  'california_twirl': CaliforniaTwirl(),
  'chain': Chain(who: WhoSet.role2s),
  'circle': Circle(turn: CircleDirection.left, places: 4),
  'courtesy_turn': CourtesyTurn(),
  'cross_trails': CrossTrails(),
  'do_si_do': DoSiDo(who: WhoSet.neighbors),
  'down_the_hall': DownTheHall(),
  'facing_star': FacingStar(),
  'figure_8': FigureEight(lead: 'onesRole2'),
  'form_a_long_wave': FormALongWave(),
  'form_long_waves': FormLongWaves(who: WhoSet.role1s),
  'form_short_waves': FormShortWaves(centerHand: Hand.left),
  'gate': Gate(),
  'give_and_take': GiveAndTake(),
  'hey': HeyForFour(pass1: WhoSet.role2s, length: HeyLength.half),
  'long_lines': LongLines(),
  'mad_robin': MadRobin(who: WhoSet.role2s),
  'orbit': Orbit(),
  'pass_by': PassBy(),
  'pass_the_ocean': PassTheOcean(centerHand: Hand.left),
  'pass_through': PassThrough(),
  'petronella': Petronella(),
  'poussette': Poussette(),
  'right_left_through': RightLeftThrough(),
  'roll_away': RollAway(),
  'rory_o_more': RoryOMore(),
  'shoulder_round': ShoulderRound(),
  'slide_along_set': SlideAlongSet(slide: SlideDirection.left),
  'square_through': SquareThrough(),
  'stand_still': StandStill(),
  'star': Star(hand: Hand.right, places: 4),
  'star_promenade': StarPromenade(),
  'star_through': StarThrough(),
  'swing': Swing(who: WhoSet.partners),
  'turn_alone': TurnAlone(),
  'turn_as_couples': TurnAsCouples(),
  'two_hand_turn': TwoHandTurn(),
  'up_the_hall': UpTheHall(),
  'zig_zag': ZigZag(),

  // `compendium_core`'s aliases: a target move with some params pinned. They
  // are parseable, so they are pinned here on the same footing as the rest --
  // each expectation is the target's own defaults with the pin applied.
  'meltdown_swing': Swing(who: WhoSet.partners, prefix: 'meltdown'),
  'pull_by_dancers': PullByDancers(),
  'pull_by_direction': PullByDirection(),
  'see_saw': DoSiDo(who: WhoSet.neighbors, shoulder: Hand.left),
  'swat_the_flea': BoxTheGnat(hand: Hand.left),
};

void main() {
  group('every registered move builds from a bare record', () {
    test('the table covers the registry exactly', () {
      // The guard that keeps this file honest: registering a new figure
      // without pinning its defaults fails here rather than shipping unproven.
      expect([...defaults.keys, 'pull_by']..sort(), supportedMoves);
    });

    defaults.forEach((move, expected) {
      test(move, () {
        expect(parseFigure(move), expected);
      });
    });
  });

  group('same-typed parameters are not crossed', () {
    // These figures carry two or more parameters of the same type. A builder
    // that read `who2` from the `who` key would still pass the defaults table
    // whenever the two defaults happen to coincide, so each one is given a
    // record where every such parameter differs from every other.
    test('cross_trails keeps who and who2 apart', () {
      expect(
        parseFigure('cross_trails', {
          'who': 'neighbors',
          'who2': 'partners',
          'dir': 'along',
          'shoulder': 'left',
        }),
        const CrossTrails(
          who: WhoSet.neighbors,
          who2: WhoSet.partners,
          dir: Direction.along,
          shoulder: Hand.left,
        ),
      );
    });

    test('square_through keeps who and who2 apart', () {
      expect(
        parseFigure('square_through', {
          'who': 'neighbors',
          'who2': 'partners',
          'places': 3,
          'balance': false,
        }),
        const SquareThrough(
          who: WhoSet.neighbors,
          who2: WhoSet.partners,
          places: 3,
          balance: false,
        ),
      );
    });

    test('poussette keeps who and whom apart', () {
      expect(
        parseFigure('poussette', {
          'who': 'twos',
          'whom': 'partners',
          'half': 'full',
          'turn': 'counterclockwise',
        }),
        const Poussette(
          who: WhoSet.twos,
          whom: WhoSet.partners,
          half: TurnFraction.full,
          turn: SpinDirection.counterclockwise,
        ),
      );
    });

    test('roll_away keeps who and whom apart', () {
      expect(
        parseFigure('roll_away', {'who': 'partners', 'whom': 'neighbors'}),
        const RollAway(who: WhoSet.partners, whom: WhoSet.neighbors),
      );
    });

    test('give_and_take keeps who and whom apart', () {
      expect(
        parseFigure('give_and_take', {
          'who': 'role2s',
          'whom': 'neighbors',
          'give': false,
        }),
        const GiveAndTake(
          who: WhoSet.role2s,
          whom: WhoSet.neighbors,
          give: false,
        ),
      );
    });

    test('gate keeps who, whom and pair apart', () {
      expect(
        parseFigure('gate', {
          'who': 'ones',
          'whom': 'twos',
          'pair': 'partners',
          'turn': 1,
          'direction': 'clockwise',
          'face': 'down',
        }),
        const Gate(
          who: WhoSet.ones,
          whom: WhoSet.twos,
          pair: WhoSet.partners,
          turn: 1,
          direction: GateDirection.clockwise,
          face: GateFace.down,
        ),
      );
    });

    test('the hall figures keep moving, facing and ender apart', () {
      expect(
        parseFigure('down_the_hall', {
          'who': 'ones',
          'moving': 'center',
          'facing': 'backward',
          'ender': 'slidingDoors',
        }),
        const DownTheHall(
          who: WhoSet.ones,
          moving: HallMoving.center,
          facing: HallFacing.backward,
          ender: HallEnder.slidingDoors,
        ),
      );
    });
  });

  group('hand and shoulder are read, not assumed', () {
    // Every figure whose parameter set includes a left/right choice. The
    // default is right almost everywhere, so a builder that ignored the key
    // would look correct until a left-handed record arrived.
    const lefties = <String, Operation>{
      'allemande': Allemande(hand: Hand.left),
      'box_circulate': BoxCirculate(who: WhoSet.role2s, hand: Hand.left),
      'box_the_gnat': BoxTheGnat(hand: Hand.left),
      'pull_by_dancers': PullByDancers(hand: Hand.left),
      'pull_by_direction': PullByDirection(hand: Hand.left),
    };
    lefties.forEach((move, expected) {
      test('$move reads hand:left', () {
        expect(parseFigure(move, const {'hand': 'left'}), expected);
      });
    });

    test('canonical pull_by reads hand:left with a stated selector', () {
      expect(
        parseFigure('pull_by', const {'where': 'along', 'hand': 'left'}),
        const PullByDirection(hand: Hand.left),
      );
    });

    const shoulders = <String, Operation>{
      'do_si_do': DoSiDo(who: WhoSet.neighbors, shoulder: Hand.left),
      'pass_by': PassBy(shoulder: Hand.left),
      'pass_through': PassThrough(shoulder: Hand.left),
      'shoulder_round': ShoulderRound(shoulder: Hand.left),
    };
    shoulders.forEach((move, expected) {
      test('$move reads shoulder:left', () {
        expect(parseFigure(move, const {'shoulder': 'left'}), expected);
      });
    });
  });

  group('turn is read as the polymorphic parameter it is', () {
    // `turn` means a different thing per figure — a fraction of a rotation, a
    // handedness, a spin direction, a ring direction. Each reading is pinned.
    test('a fraction on allemande', () {
      expect(
        parseFigure('allemande', const {'turn': 0.5}),
        const Allemande(turn: 0.5),
      );
    });

    test('a ring direction on circle', () {
      expect(
        parseFigure('circle', const {'turn': 'right', 'places': 3}),
        const Circle(turn: CircleDirection.right, places: 3),
      );
    });

    test('a spin direction on orbit', () {
      expect(
        parseFigure('orbit', const {'turn': 'counterclockwise'}),
        const Orbit(turn: SpinDirection.counterclockwise),
      );
    });

    test('a handedness on zig_zag', () {
      expect(
        parseFigure('zig_zag', const {'turn': 'right'}),
        const ZigZag(turn: Hand.right),
      );
    });

    test('a fraction on do_si_do, under its own key', () {
      expect(
        parseFigure('do_si_do', const {'who': 'neighbors', 'turn': 0.5}),
        const DoSiDo(who: WhoSet.neighbors, circling: 0.5),
      );
    });

    test('a styling enum on figure_8', () {
      expect(
        parseFigure('figure_8', const {'dir': 'above', 'lead': 'twosRole1'}),
        const FigureEight(dir: FigureEightDir.above, lead: 'twosRole1'),
      );
    });
  });

  group('unknown parameter values are refused, not silently defaulted', () {
    // The dangerous failure here is a typo that falls back to the default: the
    // dance compiles, reports success, and answers for a figure nobody wrote.
    test('an unrecognized enum value is an error', () {
      final record = {
        'title': 'typo',
        'formation': {'shape': 'dupleImproper'},
        'progression': 'single',
        'figures': [
          {
            'move': 'allemande',
            'params': {'hand': 'sinister'},
          },
        ],
      };
      final result = parseDanceJson(jsonEncode(record));
      expect(result, isA<Err<Dance, DanceParseError>>());
    });

    test('an unrecognized who is an error', () {
      final record = {
        'title': 'typo',
        'formation': {'shape': 'dupleImproper'},
        'progression': 'single',
        'figures': [
          {
            'move': 'allemande',
            'params': {'who': 'nieghbors'},
          },
        ],
      };
      final result = parseDanceJson(jsonEncode(record));
      expect(result, isA<Err<Dance, DanceParseError>>());
    });
  });
}
