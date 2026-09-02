part of '../operation.dart';

/// The **rigid couple-wheel** family: `california_twirl`, `star_through`,
/// `turn_as_couples` and `courtesy_turn`.
///
/// `docs/taxonomy.md` names these as one family and specifies an
/// identical mechanism for each — swap the two dancers of every participating
/// couple, and reverse every participant's facing. They differ only in styling
/// and in which descriptive parameters they carry, so they share an
/// implementation here rather than copies that could drift apart.
///
/// [StarThrough] is the one exception, and only in its finish: it takes the
/// same swap but ends the couple facing into the centre of the hands four
/// rather than reversed. It sits here anyway, because sharing the swap and the
/// couples-must-be-together refusal is what keeps that single difference
/// legible.
///
/// The wheel is **rigid**, which is why no normalization follows it: the
/// couple's mutual left/right relationship is carried through the turn, so a
/// couple that arrives inverted ends inverted. Lark-left/robin-right is the
/// common result, not an imposed rule.

/// The shared mechanism: swap each couple, reverse each facing.
Formation _wheelCouples(Formation formation, List<DancerPair> couples) =>
    swapPairs(
      formation,
      couples,
      facing: (before, after, other) => before.facing.reversed,
    );

/// The refusal shared by the family when a named couple is not standing
/// together, and so has no two-handed hold to wheel on.
OpError? _requireCouplesTogether(
  Formation formation,
  List<DancerPair> couples,
  String moveName,
) {
  final apart = firstNonAdjacentPair(formation, couples);
  if (apart == null) return null;
  return OpError(
    ErrorKind.unresolvableDancerSet,
    '$moveName needs each couple standing together, but ${apart.a} and '
    '${apart.b} are diagonal',
  );
}

/// `california_twirl` — each `who` pair turns as a couple to face the other
/// way, swapping sides as they go.
final class CaliforniaTwirl extends Operation {
  const CaliforniaTwirl({this.who = WhoSet.partners});

  /// The pair that twirls — row-mates in Duple Improper, column-mates in
  /// Becket. Defined as "swap the pair" so it generalizes across formations.
  final WhoSet who;

  @override
  String get name => 'california_twirl';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireCouplesTogether(formation, whoPairsInSet(formation, who), name);

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(_wheelCouples(formation, whoPairsInSet(formation, who)));

  @override
  bool operator ==(Object other) =>
      other is CaliforniaTwirl && other.who == who;

  @override
  int get hashCode => Object.hash(name, who);

  @override
  String toString() => 'california_twirl(${who.key})';
}

/// `star_through` — the couple wheel of [CaliforniaTwirl], finishing faced
/// **into the centre of the hands four** instead of simply reversed.
///
/// Positions are the family's: the two dancers of each `who` couple trade
/// cells, one turning under the other's raised hand. Only the finish differs,
/// and it is the whole point of the figure — a california twirl turns the
/// couple to face back the way they came, while a star through delivers them
/// facing in, ready for whatever the middle of the hands four calls next.
///
/// "Into the centre" resolves against the couple's **own** axis, because the
/// centre they face is the one they are not already standing on:
///
/// * A couple standing **across the set** (row-mates, the Duple Improper case)
///   finish facing the band's other rank — down from the top row, up from the
///   bottom. That is precisely the facing dancers take when they take hands
///   four, which is how the figure is described.
/// * A couple standing **along the set** (column-mates, the Becket case)
///   finish facing across, toward the centre column.
///
/// Both members of a couple therefore finish facing the **same** way, as a
/// couple should. The rule is silent about a couple standing in the centre
/// column itself, which has no centre to face; no formation this compiler
/// builds puts a couple there.
final class StarThrough extends Operation {
  const StarThrough({this.who = WhoSet.partners});

  /// The pair that stars through — row-mates in Duple Improper, column-mates
  /// in Becket, exactly as [CaliforniaTwirl.who].
  final WhoSet who;

  @override
  String get name => 'star_through';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireCouplesTogether(formation, whoPairsInSet(formation, who), name);

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final couples = whoPairsInSet(formation, who);
    // Whether each participant's couple stands across the set. Read before the
    // swap because it survives it: trading cells with the dancer beside you
    // keeps you both on the axis you shared.
    final acrossTheSet = <DancerId, bool>{};
    for (final couple in couples) {
      final together =
          formation.stateOf(couple.a).row == formation.stateOf(couple.b).row;
      acrossTheSet[couple.a] = together;
      acrossTheSet[couple.b] = together;
    }
    return Ok(
      mapBandFacing(swapPairs(formation, couples), (id, state, band) {
        final across = acrossTheSet[id];
        // Silent about everyone the figure did not name, per mapBandFacing.
        if (across == null) return null;
        if (across) {
          return state.row == band.topRow ? Facing.down : Facing.up;
        }
        return state.col < kColumnCount ~/ 2
            ? Facing.acrossEast
            : Facing.acrossWest;
      }),
    );
  }

  @override
  bool operator ==(Object other) => other is StarThrough && other.who == who;

  @override
  int get hashCode => Object.hash(name, who);

  @override
  String toString() => 'star_through(${who.key})';
}

/// `turn_as_couples` — each `who` couple turns 180° as a unit.
///
/// The plain couple wheel: mechanically [CaliforniaTwirl] without the twirl
/// under joined hands.
final class TurnAsCouples extends Operation {
  const TurnAsCouples({this.who = WhoSet.partners});

  /// The couple(s) that turn.
  final WhoSet who;

  @override
  String get name => 'turn_as_couples';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireCouplesTogether(formation, whoPairsInSet(formation, who), name);

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(_wheelCouples(formation, whoPairsInSet(formation, who)));

  @override
  bool operator ==(Object other) => other is TurnAsCouples && other.who == who;

  @override
  int get hashCode => Object.hash(name, who);

  @override
  String toString() => 'turn_as_couples(${who.key})';
}

/// `courtesy_turn` — a couple wheels 180° as a rigid unit, one backing up as
/// the pivot while the other walks forward around them.
///
/// The sub-component that `chain` and `right_left_through` each end with, here
/// as the standalone figure. It must **not** be paired with either of those:
/// they carry their courtesy turn internally, and emitting both would apply the
/// wheel twice.
final class CourtesyTurn extends Operation {
  const CourtesyTurn({
    this.who = WhoSet.partners,
    this.whom,
    this.direction = SpinDirection.clockwise,
    this.endFacing,
  });

  /// The pairing the turn is danced with — this selects the wheeling couples.
  final WhoSet who;

  /// The dancer being turned, when a source names both a turner and a turnee.
  /// `null` is the upstream `unspecified` sentinel; no source populates it.
  final WhoSet? whom;

  /// The wheel's sense. A courtesy turn is clockwise by construction, and a
  /// 180° wheel lands the same either way, so this has no positional effect.
  final SpinDirection direction;

  /// ⚠️ A **dancer relationship**, not a cardinal facing — despite the name it
  /// shares with `swing.endFacing` and `gate.face`. It answers *whom* you end
  /// up facing, which needs cross-hands-four dancer resolution, so it is
  /// carried for fidelity and not resolved.
  final WhoSet? endFacing;

  @override
  String get name => 'courtesy_turn';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom, endFacing];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireCouplesTogether(formation, whoPairsInSet(formation, who), name);

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(_wheelCouples(formation, whoPairsInSet(formation, who)));

  @override
  bool operator ==(Object other) =>
      other is CourtesyTurn &&
      other.who == who &&
      other.whom == whom &&
      other.direction == direction &&
      other.endFacing == endFacing;

  @override
  int get hashCode => Object.hash(name, who, whom, direction, endFacing);

  @override
  String toString() => 'courtesy_turn(${who.key}, ${direction.key})';
}
