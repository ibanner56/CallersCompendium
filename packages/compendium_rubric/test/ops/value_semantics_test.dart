import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// Value semantics for every figure.
///
/// Each `Operation` is a value: two invocations with the same parameters must
/// be equal, and two that differ in *any* parameter must not be. This matters
/// beyond tidiness — `OperationInvocation` compares by operation, the compiler
/// reports figures by `toString()`, and a dance record round-trips through the
/// parser into these objects. An `==` that quietly forgets a field would make
/// two genuinely different dances compare equal, which is the one thing a
/// verifier must never do.
///
/// The per-field variants below are derived from each class's declared fields
/// rather than from its `==` body, so a field added later without being added
/// to `==` fails here instead of passing by construction.

/// Asserts the full value contract for [base].
///
/// [same] must be a separately constructed instance with identical parameters.
/// [variants] maps a field name to an instance differing in that field alone.
void checkValueSemantics(
  Operation base,
  Operation same,
  Map<String, Operation> variants,
) {
  group(base.name, () {
    test('equals a separately constructed identical instance', () {
      expect(base, same);
      expect(base.hashCode, same.hashCode);
    });

    test('is not equal to a different figure carrying the same shape', () {
      final foil = base is BalanceTheRing
          ? const StandStill()
          : const BalanceTheRing();
      expect(base, isNot(foil));
      expect(foil, isNot(base));
    });

    test('overrides toString rather than inheriting the default', () {
      expect(base.toString(), isNotEmpty);
      expect(base.toString(), isNot(startsWith('Instance of')));
    });

    test('reports a snake_case move name', () {
      expect(base.name, isNotEmpty);
      expect(base.name, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
    });

    variants.forEach((field, variant) {
      test('$field participates in equality', () {
        expect(
          base,
          isNot(variant),
          reason:
              '${base.runtimeType}.$field is not compared by ==, so two '
              'figures that differ in it look identical to the engine',
        );
      });
    });
  });
}

void main() {
  // ---- axis swaps -------------------------------------------------------
  checkValueSemantics(const PassThrough(), const PassThrough(), {
    'dir': const PassThrough(dir: Direction.across),
    'shoulder': const PassThrough(shoulder: Hand.left),
  });

  checkValueSemantics(const PullByDirection(), const PullByDirection(), {
    'balance': const PullByDirection(balance: true),
    'dir': const PullByDirection(dir: Direction.across),
    'hand': const PullByDirection(hand: Hand.left),
  });

  checkValueSemantics(const ZigZag(), const ZigZag(), {
    'who': const ZigZag(who: WhoSet.neighbors),
    'turn': const ZigZag(turn: Hand.right),
    'ender': const ZigZag(ender: ZigZagEnder.ring),
  });

  checkValueSemantics(const CrossTrails(), const CrossTrails(), {
    'who': const CrossTrails(who: WhoSet.neighbors),
    'dir': const CrossTrails(dir: Direction.along),
    'shoulder': const CrossTrails(shoulder: Hand.left),
    'who2': const CrossTrails(who2: WhoSet.partners),
  });

  checkValueSemantics(const SquareThrough(), const SquareThrough(), {
    'who': const SquareThrough(who: WhoSet.neighbors),
    'who2': const SquareThrough(who2: WhoSet.partners),
    'balance': const SquareThrough(balance: false),
    'hand': const SquareThrough(hand: Hand.left),
    'places': const SquareThrough(places: 2),
  });

  // ---- pair swaps -------------------------------------------------------
  checkValueSemantics(const RollAway(), const RollAway(), {
    'who': const RollAway(who: WhoSet.partners),
    'whom': const RollAway(whom: WhoSet.neighbors),
    'halfSashay': const RollAway(halfSashay: true),
  });

  checkValueSemantics(const PullByDancers(), const PullByDancers(), {
    'who': const PullByDancers(who: WhoSet.partners),
    'balance': const PullByDancers(balance: true),
    'hand': const PullByDancers(hand: Hand.left),
  });

  checkValueSemantics(const PassBy(), const PassBy(), {
    'who': const PassBy(who: WhoSet.partners),
    'shoulder': const PassBy(shoulder: Hand.left),
  });

  checkValueSemantics(const BoxTheGnat(), const BoxTheGnat(), {
    'who': const BoxTheGnat(who: WhoSet.neighbors),
    'hand': const BoxTheGnat(hand: Hand.left),
    'balance': const BoxTheGnat(balance: true),
  });

  // ---- rings ------------------------------------------------------------
  checkValueSemantics(
    const Circle(turn: CircleDirection.left, places: 3),
    const Circle(turn: CircleDirection.left, places: 3),
    {
      'turn': const Circle(turn: CircleDirection.right, places: 3),
      'places': const Circle(turn: CircleDirection.left, places: 4),
      'singleFile': const Circle(
        turn: CircleDirection.left,
        places: 3,
        singleFile: true,
      ),
    },
  );

  checkValueSemantics(
    const Star(hand: Hand.left, places: 4),
    const Star(hand: Hand.left, places: 4),
    {
      'hand': const Star(hand: Hand.right, places: 4),
      'places': const Star(hand: Hand.left, places: 3),
      'grip': const Star(hand: Hand.left, places: 4, grip: 'wristGrip'),
    },
  );

  checkValueSemantics(const BoxCirculate(), const BoxCirculate(), {
    'who': const BoxCirculate(who: WhoSet.neighbors),
    'hand': const BoxCirculate(hand: Hand.left),
    'balance': const BoxCirculate(balance: true),
  });

  checkValueSemantics(const FacingStar(), const FacingStar(), {
    'who': const FacingStar(who: WhoSet.twos),
    'turn': const FacingStar(turn: SpinDirection.counterclockwise),
    'places': const FacingStar(places: 4),
  });

  checkValueSemantics(const Petronella(), const Petronella(), {
    'balance': const Petronella(balance: false),
  });

  checkValueSemantics(const RightLeftThrough(), const RightLeftThrough(), {
    'dir': const RightLeftThrough(dir: 'leftDiagonal'),
  });

  // ---- stationary -------------------------------------------------------
  checkValueSemantics(const Balance(), const Balance(), {
    'who': const Balance(who: WhoSet.partners),
    'hand': const Balance(hand: Hand.right),
  });

  checkValueSemantics(const BalanceTheRing(), const BalanceTheRing(), const {});

  checkValueSemantics(const LongLines(), const LongLines(), {
    'goBack': const LongLines(goBack: false),
  });

  checkValueSemantics(const TurnAlone(), const TurnAlone(), {
    'who': const TurnAlone(who: WhoSet.ones),
    'custom': const TurnAlone(custom: 'over the left shoulder'),
  });

  checkValueSemantics(const StandStill(), const StandStill(), {
    'beats': const StandStill(beats: 16),
  });

  checkValueSemantics(const SlideAlongSet(), const SlideAlongSet(), {
    'slide': const SlideAlongSet(slide: SlideDirection.right),
  });

  // ---- couple wheels ----------------------------------------------------
  checkValueSemantics(const CaliforniaTwirl(), const CaliforniaTwirl(), {
    'who': const CaliforniaTwirl(who: WhoSet.neighbors),
  });

  checkValueSemantics(const StarThrough(), const StarThrough(), {
    'who': const StarThrough(who: WhoSet.neighbors),
  });

  checkValueSemantics(const TurnAsCouples(), const TurnAsCouples(), {
    'who': const TurnAsCouples(who: WhoSet.neighbors),
  });

  checkValueSemantics(const CourtesyTurn(), const CourtesyTurn(), {
    'who': const CourtesyTurn(who: WhoSet.neighbors),
    'whom': const CourtesyTurn(whom: WhoSet.partners),
    'direction': const CourtesyTurn(direction: SpinDirection.counterclockwise),
    'endFacing': const CourtesyTurn(endFacing: WhoSet.neighbors),
  });

  test('the three couple wheels are never equal to one another', () {
    // They share one implementation and one field, so an == that tested only
    // the field would collapse all three into the same figure.
    expect(const CaliforniaTwirl(), isNot(const TurnAsCouples()));
    expect(const TurnAsCouples(), isNot(const CaliforniaTwirl()));
    expect(const CaliforniaTwirl(), isNot(const CourtesyTurn()));
  });

  // ---- turns ------------------------------------------------------------
  checkValueSemantics(const Allemande(), const Allemande(), {
    'who': const Allemande(who: WhoSet.partners),
    'hand': const Allemande(hand: Hand.left),
    'turn': const Allemande(turn: 0.5),
  });

  checkValueSemantics(const TwoHandTurn(), const TwoHandTurn(), {
    'who': const TwoHandTurn(who: WhoSet.neighbors),
    'turn': const TwoHandTurn(turn: 0.5),
  });

  checkValueSemantics(const ShoulderRound(), const ShoulderRound(), {
    'who': const ShoulderRound(who: WhoSet.partners),
    'shoulder': const ShoulderRound(shoulder: Hand.left),
    'turn': const ShoulderRound(turn: 0.5),
  });

  checkValueSemantics(const MadRobin(), const MadRobin(), {
    'who': const MadRobin(who: WhoSet.twos),
    'turn': const MadRobin(turn: 0.5),
    'direction': const MadRobin(direction: SpinDirection.clockwise),
    'whom': const MadRobin(whom: WhoSet.neighbors),
  });

  checkValueSemantics(const Orbit(), const Orbit(), {
    'who': const Orbit(who: WhoSet.twos),
    'turn': const Orbit(turn: SpinDirection.counterclockwise),
    'amount': const Orbit(amount: 1),
  });

  checkValueSemantics(const StarPromenade(), const StarPromenade(), {
    'who': const StarPromenade(who: WhoSet.role2s),
    'turn': const StarPromenade(turn: 1),
  });

  test('the turn family does not collapse across move names', () {
    // allemande, two_hand_turn and shoulder_round agree on position for a
    // given turn, but they are different calls and must stay distinguishable.
    expect(const Allemande(turn: 0.5), isNot(const TwoHandTurn(turn: 0.5)));
    expect(const ShoulderRound(turn: 0.5), isNot(const Allemande(turn: 0.5)));
  });

  // ---- do si do, swing, chain -------------------------------------------
  // These three take no default `who`: the taxonomy and the upstream
  // compendium disagree on what it should be, so the engine declines to guess
  // and the caller must say. Every instance here therefore names it.
  checkValueSemantics(
    const DoSiDo(who: WhoSet.neighbors),
    const DoSiDo(who: WhoSet.neighbors),
    {
      'who': const DoSiDo(who: WhoSet.partners),
      'circling': const DoSiDo(who: WhoSet.neighbors, circling: 0.5),
      'shoulder': const DoSiDo(who: WhoSet.neighbors, shoulder: Hand.left),
    },
  );

  checkValueSemantics(
    const Swing(who: WhoSet.neighbors),
    const Swing(who: WhoSet.neighbors),
    {
      'who': const Swing(who: WhoSet.partners),
      'where': const Swing(who: WhoSet.neighbors, where: SwingWhere.center),
      'face': const Swing(who: WhoSet.neighbors, face: FaceDirection.down),
      'prefix': const Swing(who: WhoSet.neighbors, prefix: 'balance'),
    },
  );

  checkValueSemantics(
    const Chain(who: WhoSet.role2s),
    const Chain(who: WhoSet.role2s),
    {
      'who': const Chain(who: WhoSet.role1s),
      'hand': const Chain(who: WhoSet.role2s, hand: Hand.left),
      'dir': const Chain(who: WhoSet.role2s, dir: ChainDirection.leftDiagonal),
    },
  );

  // ---- the bespoke figures ----------------------------------------------
  checkValueSemantics(const HeyForFour(), const HeyForFour(), {
    'pass1': const HeyForFour(pass1: WhoSet.role1s),
    'length': const HeyForFour(length: HeyLength.full),
    'pass2': const HeyForFour(pass2: WhoSet.role1s),
    'meetTarget': const HeyForFour(meetTarget: WhoSet.partners),
    'shoulder': const HeyForFour(shoulder: Hand.left),
    'dir': const HeyForFour(dir: Direction.along),
    'rico1': const HeyForFour(rico1: true),
    'rico2': const HeyForFour(rico2: true),
    'rico3': const HeyForFour(rico3: true),
    'rico4': const HeyForFour(rico4: true),
  });

  checkValueSemantics(const GiveAndTake(), const GiveAndTake(), {
    'who': const GiveAndTake(who: WhoSet.role2s),
    'whom': const GiveAndTake(whom: WhoSet.neighbors),
    'give': const GiveAndTake(give: false),
  });

  checkValueSemantics(const FigureEight(), const FigureEight(), {
    'who': const FigureEight(who: WhoSet.twos),
    'dir': const FigureEight(dir: FigureEightDir.above),
    'lead': const FigureEight(lead: 'onesRole1'),
    'half': const FigureEight(half: TurnFraction.full),
  });

  checkValueSemantics(const Poussette(), const Poussette(), {
    'who': const Poussette(who: WhoSet.twos),
    'whom': const Poussette(whom: WhoSet.partners),
    'half': const Poussette(half: TurnFraction.full),
    'turn': const Poussette(turn: SpinDirection.counterclockwise),
  });

  checkValueSemantics(const Gate(), const Gate(), {
    'who': const Gate(who: WhoSet.ones),
    'whom': const Gate(whom: WhoSet.twos),
    'pair': const Gate(pair: WhoSet.partners),
    'direction': const Gate(direction: GateDirection.clockwise),
    'turn': const Gate(turn: 1),
    'face': const Gate(face: GateFace.down),
  });

  // ---- waves ------------------------------------------------------------
  checkValueSemantics(const FormShortWaves(), const FormShortWaves(), {
    'dir': const FormShortWaves(dir: Direction.rightDiagonal),
    'balance': const FormShortWaves(balance: true),
    'center': const FormShortWaves(center: WhoSet.role1s),
    'centerHand': const FormShortWaves(centerHand: Hand.right),
    'sides': const FormShortWaves(sides: WhoSet.partners),
  });

  checkValueSemantics(const FormLongWaves(), const FormLongWaves(), {
    'who': const FormLongWaves(who: WhoSet.role2s),
    'whom': const FormLongWaves(whom: WhoSet.neighbors),
    'hand': const FormLongWaves(hand: Hand.left),
    'balance': const FormLongWaves(balance: true),
  });

  checkValueSemantics(const PassTheOcean(), const PassTheOcean(), {
    'dir': const PassTheOcean(dir: Direction.rightDiagonal),
    'balance': const PassTheOcean(balance: true),
    'center': const PassTheOcean(center: WhoSet.role1s),
    'centerHand': const PassTheOcean(centerHand: Hand.right),
    'sides': const PassTheOcean(sides: WhoSet.partners),
  });

  checkValueSemantics(const RoryOMore(), const RoryOMore(), {
    'who': const RoryOMore(who: WhoSet.role1s),
    'balance': const RoryOMore(balance: false),
    'slide': const RoryOMore(slide: Hand.left),
  });

  checkValueSemantics(const FormALongWave(), const FormALongWave(), {
    'who': const FormALongWave(who: WhoSet.role1s),
    'stepsIn': const FormALongWave(stepsIn: false),
    'stepsOut': const FormALongWave(stepsOut: true),
    'balance': const FormALongWave(balance: false),
  });

  // ---- the hall ---------------------------------------------------------
  checkValueSemantics(const DownTheHall(), const DownTheHall(), {
    'who': const DownTheHall(who: WhoSet.ones),
    'moving': const DownTheHall(moving: HallMoving.center),
    'facing': const DownTheHall(facing: HallFacing.backward),
    'ender': const DownTheHall(ender: HallEnder.none),
  });

  checkValueSemantics(const UpTheHall(), const UpTheHall(), {
    'who': const UpTheHall(who: WhoSet.ones),
    'moving': const UpTheHall(moving: HallMoving.center),
    'facing': const UpTheHall(facing: HallFacing.backward),
    'ender': const UpTheHall(ender: HallEnder.none),
  });

  test('the two hall figures travel opposite ways and are never equal', () {
    expect(
      const DownTheHall(ender: HallEnder.none),
      isNot(const UpTheHall(ender: HallEnder.none)),
    );
    expect(
      const UpTheHall(ender: HallEnder.none),
      isNot(const DownTheHall(ender: HallEnder.none)),
    );
  });
}
