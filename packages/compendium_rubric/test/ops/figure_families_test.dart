import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

Formation di(List<String> rows) =>
    parseRolesNotation(rows, type: FormationType.dupleImproper);

/// The base ring every worked example in `docs/taxonomy.md` is stated against.
///
/// `(r0,c0)=R1-A (r0,c4)=L1-A / (r1,c0)=L2-B (r1,c4)=R2-B`, so partners are
/// row-mates and neighbours are column-mates.
Formation base() => di(const ['R1-A . . . L1-A', 'L2-B . . . R2-B']);

/// The four permutations the taxonomy's effect rules are written in terms of.
const List<String> identity = ['R1-A . . . L1-A', 'L2-B . . . R2-B'];
const List<String> columnSwap = ['L1-A . . . R1-A', 'R2-B . . . L2-B'];
const List<String> rowSwap = ['L2-B . . . R2-B', 'R1-A . . . L1-A'];
const List<String> diagonalSwap = ['R2-B . . . L2-B', 'L1-A . . . R1-A'];

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

void expectLands(Operation op, List<String> expected) =>
    expect(applyOk(op, base()).toRolesNotation(), expected, reason: '$op');

/// Asserts every dancer ends facing the opposite of where they started.
void expectFacingReversed(Operation op) {
  final before = base();
  final after = applyOk(op, before);
  for (final entry in after.dancers.entries) {
    expect(
      entry.value.facing,
      before.stateOf(entry.key).facing.reversed,
      reason: '$op left ${entry.key} facing the same way',
    );
  }
}

/// Asserts nobody's facing changed.
void expectFacingPreserved(Operation op) {
  final before = base();
  final after = applyOk(op, before);
  for (final entry in after.dancers.entries) {
    expect(
      entry.value.facing,
      before.stateOf(entry.key).facing,
      reason: '$op changed ${entry.key}\'s facing',
    );
  }
}

void main() {
  group('stationary figures', () {
    test('balance is the identity, whatever it is danced with', () {
      expectLands(const Balance(), identity);
      expectLands(
        const Balance(who: WhoSet.partners, hand: Hand.left),
        identity,
      );
    });

    test('balance the ring is the identity', () {
      expectLands(const BalanceTheRing(), identity);
    });

    test('long lines going back is the identity', () {
      expectLands(const LongLines(), identity);
    });

    test('long lines forward-only is deferred, not approximated', () {
      final error = applyErr(const LongLines(goBack: false), base());
      expect(error.kind, ErrorKind.unsupportedParam);
    });

    test('turn alone holds position and reverses facing', () {
      expectLands(const TurnAlone(), identity);
      expectFacingReversed(const TurnAlone());
    });

    test('turn alone scoped to one role turns only that role', () {
      final before = base();
      final after = applyOk(const TurnAlone(who: WhoSet.role1s), before);
      for (final entry in after.dancers.entries) {
        final expected = before.stateOf(entry.key).facing;
        expect(
          entry.value.facing,
          entry.key.role == Role.lark ? expected.reversed : expected,
        );
      }
    });
  });

  group('the pass and pull family — one axis, one swap', () {
    test('pass through along the set swaps rows', () {
      expectLands(const PassThrough(), rowSwap);
    });

    test('pass through across the set swaps columns', () {
      expectLands(const PassThrough(dir: Direction.across), columnSwap);
    });

    test('a pass through keeps everyone walking the same way', () {
      expectFacingPreserved(const PassThrough());
    });

    test(
      'passing across a hall that is facing along is warned, not refused',
      () {
        // A real duple improper start faces up and down the hall, so an `across`
        // pass through asks for an axis nobody is standing on. Facing is the
        // softest thing the matrix holds - the figure runs, and says so.
        final start = startingFormation(
          FormationType.dupleImproper,
          handsFour: 2,
        );
        const across = PassThrough(dir: Direction.across);
        expect(across.apply(start), isA<Ok<Formation, OpError>>());
        final warnings = across.lint(start).toList();
        expect(warnings, hasLength(1));
        expect(warnings.single.kind, WarningKind.facingPrecondition);
        expect(warnings.single.message, contains('across'));
      },
    );

    test('passing along that same hall has nothing to report', () {
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      expect(const PassThrough().lint(start), isEmpty);
    });

    test('a flexible facing is resolved by the pass, not reported by it', () {
      // What `circle` and `star` hand over. Loosening the ring must not turn
      // every following pass through into a warning, or the contract would be
      // unusable.
      final loosened = applyOk(
        const Circle(turn: CircleDirection.left, places: 3),
        startingFormation(FormationType.dupleImproper, handsFour: 2),
      );
      expect(
        loosened.dancers.values.map((state) => state.facing),
        everyElement(Facing.flexible),
      );
      expect(const PassThrough().lint(loosened), isEmpty);
      expect(const PassThrough(dir: Direction.across).lint(loosened), isEmpty);
    });

    test('pull by direction matches pass through on each axis', () {
      expectLands(const PullByDirection(), rowSwap);
      expectLands(const PullByDirection(dir: Direction.across), columnSwap);
    });

    test('pull by dancers swaps the named pair', () {
      expectLands(const PullByDancers(), rowSwap);
      expectLands(const PullByDancers(who: WhoSet.partners), columnSwap);
    });

    test('pass by swaps the named pair', () {
      expectLands(const PassBy(), rowSwap);
      expectLands(const PassBy(who: WhoSet.partners), columnSwap);
    });

    test('zig zag is one along-the-set pass', () {
      expectLands(const ZigZag(), rowSwap);
    });

    test('cross trails is across then along - a diagonal', () {
      expectLands(const CrossTrails(), diagonalSwap);
    });

    test('a balance lead-in never changes where anyone lands', () {
      expectLands(const PullByDancers(balance: true), rowSwap);
      expectLands(const BoxTheGnat(balance: true), columnSwap);
    });
  });

  group('square through — alternating pull-bys', () {
    test('one place is the across pass', () {
      expectLands(const SquareThrough(places: 1), columnSwap);
    });

    test('two places is across then along - a diagonal', () {
      expectLands(const SquareThrough(places: 2), diagonalSwap);
    });

    test('three places is a net row swap', () {
      expectLands(const SquareThrough(places: 3), rowSwap);
    });

    test('four places returns everyone home', () {
      expectLands(const SquareThrough(), identity);
    });
  });

  group('the trade family — swap the named pair', () {
    test('box the gnat trades partners across columns', () {
      expectLands(const BoxTheGnat(), columnSwap);
    });

    test('box the gnat trades neighbours across rows', () {
      expectLands(const BoxTheGnat(who: WhoSet.neighbors), rowSwap);
    });

    test('swat the flea is box the gnat with the other hand', () {
      expectLands(const BoxTheGnat(hand: Hand.left), columnSwap);
    });

    test('roll away swaps the whom pair, not the who pair', () {
      // `who` is actor context here; `whom` names the trade.
      expectLands(const RollAway(), columnSwap);
      expectLands(const RollAway(whom: WhoSet.neighbors), rowSwap);
    });

    test('a half sashay lands where a plain roll away does', () {
      expectLands(const RollAway(halfSashay: true), columnSwap);
    });
  });

  group('couple wheels — swap and reverse together', () {
    test('california twirl swaps the couple and reverses facing', () {
      expectLands(const CaliforniaTwirl(), columnSwap);
      expectFacingReversed(const CaliforniaTwirl());
    });

    test('turn as couples is the same pair of effects', () {
      expectLands(const TurnAsCouples(), columnSwap);
      expectFacingReversed(const TurnAsCouples());
    });

    test('courtesy turn wheels the couple unconditionally', () {
      expectLands(const CourtesyTurn(), columnSwap);
    });

    test('a wheel needs its couple standing together', () {
      // A hand-built arrangement with both couples on the diagonal: there is
      // no two-handed hold for a rigid wheel to turn on. Every ring rotation
      // preserves adjacency, so this state has to be stated rather than
      // reached by a figure.
      final diagonal = di(const ['R1-A . . . R2-B', 'L2-B . . . L1-A']);
      for (final op in <Operation>[
        const CaliforniaTwirl(),
        const TurnAsCouples(),
        const CourtesyTurn(),
        const TwoHandTurn(turn: 0.5),
      ]) {
        final error = applyErr(op, diagonal);
        expect(error.kind, ErrorKind.unresolvableDancerSet, reason: '$op');
      }
    });
  });

  group('ring rotations', () {
    test('box circulate right is circle left one place', () {
      final viaBox = applyOk(const BoxCirculate(), base());
      final viaCircle = applyOk(
        const Circle(turn: CircleDirection.left, places: 1),
        base(),
      );
      expect(viaBox.toRolesNotation(), viaCircle.toRolesNotation());
    });

    test('box circulate left is circle right one place', () {
      final viaBox = applyOk(const BoxCirculate(hand: Hand.left), base());
      final viaCircle = applyOk(
        const Circle(turn: CircleDirection.right, places: 1),
        base(),
      );
      expect(viaBox.toRolesNotation(), viaCircle.toRolesNotation());
    });

    test('facing star turns the corner ring by places', () {
      expectLands(const FacingStar(), ['L1-A . . . R2-B', 'R1-A . . . L2-B']);
    });

    test('facing star reverses with the turn direction', () {
      final clockwise = applyOk(const FacingStar(places: 1), base());
      final widdershins = applyOk(
        const FacingStar(places: 1, turn: SpinDirection.counterclockwise),
        base(),
      );
      final andBack = applyOk(
        const FacingStar(places: 1, turn: SpinDirection.counterclockwise),
        clockwise,
      );
      expect(andBack.toRolesNotation(), base().toRolesNotation());
      expect(widdershins.toRolesNotation(), isNot(clockwise.toRolesNotation()));
    });

    test('a full four places is the identity', () {
      expectLands(const FacingStar(places: 4), identity);
    });
  });

  group('the turn family — whole, half, and a quarter that lands in a '
      'wave', () {
    test('a whole allemande is the identity', () {
      expectLands(const Allemande(), identity);
    });

    test('a half allemande swaps the turning pair', () {
      expectLands(const Allemande(turn: 0.5), rowSwap);
      expectLands(const Allemande(who: WhoSet.partners, turn: 0.5), columnSwap);
    });

    test('a one-and-a-quarter allemande lands in the canonical wave', () {
      expectLands(const Allemande(turn: 1.25), const [
        '. R1-A . . L1-A',
        'L2-B . . R2-B .',
      ]);
    });

    test('a one-and-three-quarter allemande is the same wave with the other '
        'role in the centre', () {
      expectLands(const Allemande(turn: 1.75), const [
        '. L2-B . . R2-B',
        'R1-A . . L1-A .',
      ]);
    });

    test('a two-hand turn follows the same rule with no hand to defer to', () {
      expectLands(const TwoHandTurn(), identity);
      expectLands(const TwoHandTurn(turn: 0.5), columnSwap);
      expect(
        applyErr(const TwoHandTurn(turn: 0.25), base()).kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('a shoulder round matches do_si_do on position', () {
      expectLands(const ShoulderRound(), identity);
      final viaShoulder = applyOk(const ShoulderRound(turn: 1.5), base());
      final viaDoSiDo = applyOk(
        const DoSiDo(who: WhoSet.neighbors, circling: 1.5),
        base(),
      );
      expect(viaShoulder.toRolesNotation(), viaDoSiDo.toRolesNotation());
    });

    test('a mad robin orbits along the set', () {
      expectLands(const MadRobin(), identity);
      expectLands(const MadRobin(turn: 0.5), rowSwap);
      expect(
        applyErr(const MadRobin(turn: 0.25), base()).kind,
        ErrorKind.unsupportedParam,
      );
    });

    test('a half star promenade is the 180 degree diagonal', () {
      expectLands(const StarPromenade(), diagonalSwap);
      expectLands(const StarPromenade(turn: 1), identity);
    });

    test('a half orbit of a couple swaps that couple only', () {
      expectLands(const Orbit(), ['L1-A . . . R1-A', 'L2-B . . . R2-B']);
    });

    test('a half orbit of a role is the diagonal that role stands on', () {
      // In DI the two Larks are diagonally opposite, so a true 180 degree
      // rotation about the hands four centre maps them onto each other.
      expectLands(const Orbit(who: WhoSet.role1s), [
        'R1-A . . . L2-B',
        'L1-A . . . R2-B',
      ]);
    });

    test('a whole orbit returns everyone home', () {
      expectLands(const Orbit(amount: 1), identity);
    });

    test('a half orbit loosens only the dancers who moved', () {
      // The "facing (output): Flexible" contract, scoped to the `who`. Unlike
      // circle and star, an orbit moves two of the four - loosening the whole
      // band would discard the facing of dancers who never went anywhere.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = applyOk(const Orbit(who: WhoSet.role1s), start);
      for (final entry in after.dancers.entries) {
        final moved = entry.key.role == Role.lark;
        expect(
          entry.value.facing,
          moved ? Facing.flexible : start.stateOf(entry.key).facing,
          reason: '${entry.key} should ${moved ? '' : 'not '}be loosened',
        );
      }
    });

    test('a whole orbit is the identity and leaves facing alone', () {
      // Same exemption circle and star take: nobody is anywhere new, so there
      // is no new facing to resolve.
      final start = startingFormation(
        FormationType.dupleImproper,
        handsFour: 2,
      );
      final after = applyOk(const Orbit(amount: 1), start);
      for (final entry in after.dancers.entries) {
        expect(entry.value.facing, start.stateOf(entry.key).facing);
      }
    });
  });

  group('poussette', () {
    test('a full poussette returns the couples home', () {
      expectLands(const Poussette(half: TurnFraction.full), identity);
    });

    test('a half poussette swaps the two couples', () {
      expectLands(const Poussette(), rowSwap);
    });

    test('quarter turns are deferred', () {
      final error = applyErr(
        const Poussette(half: TurnFraction.quarter),
        base(),
      );
      expect(error.kind, ErrorKind.unsupportedParam);
    });
  });

  group('the cross-hands-four guard', () {
    test('a figure naming nextNeighbors needs somewhere to reach', () {
      // The base shape is a single hands four, so there is no grouping beyond
      // it. Re-banding one would strand every dancer at an end and leave the
      // figure with no hands four at all -- a silent no-op, which is the one
      // outcome that must not happen, because it would then be compared
      // against the oracle as though the figure had run.
      for (final op in <Operation>[
        const ShoulderRound(who: WhoSet.nextNeighbors),
        const Allemande(who: WhoSet.nextNeighbors),
        const Swing(who: WhoSet.nextNeighbors),
        const GiveAndTake(whom: WhoSet.nextNeighbors),
      ]) {
        final error = applyErr(op, base());
        expect(error.kind, ErrorKind.unresolvableDancerSet, reason: '$op');
        expect(error.detail, contains('nextNeighbors'));
      }
    });
  });
}
