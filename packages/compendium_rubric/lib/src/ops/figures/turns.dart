part of '../operation.dart';

/// The rotation turns: `allemande`, `two_hand_turn`, `shoulder_round`,
/// `mad_robin`, `orbit` and `star_promenade`.
///
/// Each takes a numeric amount and sorts it into the same four buckets — a
/// whole turn returns the dancers to place, a half exchanges them, and a
/// quarter or three-quarter lands the pair in a short wave (§8.5.6).
/// `allemande` and `shoulder_round` each carry a direction token that fixes
/// that wave's handedness and so implement it; the rest of the family carries
/// no usable direction token, or has no worked example, and refuses both
/// quarter cases.
///
/// What distinguishes them is entirely the facing they leave behind:
/// `do_si_do` preserves it, `allemande` inverts it on a half, `two_hand_turn`
/// ends relational, `shoulder_round` uses the focus rule, and `mad_robin` ends
/// across the set.

/// Refuses a quarter-turn amount on behalf of the figures with no wave landing.
///
/// `do_si_do`, `allemande` and `shoulder_round` have one and do not use this;
/// everything else in the family still refuses, and refuses **both** quarter
/// cases together.
OpError? _requireWholeOrHalf(num amount, String moveName, String param) {
  if (!rotationAmountOf(amount).landsInWave) return null;
  return OpError(
    ErrorKind.unsupportedParam,
    '$moveName supports whole and half turns; $param: $amount lands in a '
    'wave, which is deferred',
  );
}

/// Refuses a quarter-turn amount whose pair is standing **across** the set.
///
/// The wave landing of §8.5.1 is defined over an along-the-set pair; an
/// across-the-set quarter is a separate figure with its own geometry and is
/// deferred. Shared by `do_si_do`, `allemande` and `shoulder_round` so they all
/// refuse alike.
OpError? _requireAlongTheSet(
  Formation formation,
  WhoSet who,
  String moveName,
  String param,
  num amount,
) {
  final across = firstPairAcrossTheSet(
    formation,
    whoPairsInSet(formation, who),
  );
  if (across == null) return null;
  return OpError(
    ErrorKind.unsupportedParam,
    '$moveName $param: $amount lands in a wave, which is defined for a pair '
    'along the set; ${across.a} and ${across.b} are across it, and the '
    'across-the-set quarter is deferred',
  );
}

/// `allemande` — the pair take hands or forearms and turn around each other.
///
/// The positional twin of `do_si_do`, and its **facing** opposite: a do-si-do
/// slides, so dancers keep their direction, while an allemande turns the
/// connected pair, so facing follows the rotation. That is the rotation-facing
/// principle — unchanged on a full turn, opposite on a half.
///
/// The two coincide again on a **quarter**, where both land in a wave and
/// §8.5.1's resting facing owns the result: an allemande right 1¼ from a duple
/// improper start builds the canonical wave, and 1¾ builds the same wave with
/// the other role in the centre, because the half turn trades the couples
/// between rows before the offset is taken.
final class Allemande extends Operation {
  const Allemande({
    this.who = WhoSet.neighbors,
    this.hand = Hand.right,
    this.turn = 1.0,
  });

  /// The turning pair. A precondition in the relaxed `do_si_do` sense: the
  /// named dancer may be in a different column.
  final WhoSet who;

  /// The hand given: `right` turns clockwise, `left` counter-clockwise. It
  /// does not change whole or half end positions, and on a quarter it is the
  /// token that fixes the resulting wave's handedness: `right` builds the
  /// canonical wave — neighbours joining right on the sides, the centre pair
  /// joining left.
  final Hand hand;

  /// How far around, in full turns.
  final double turn;

  @override
  String get name => 'allemande';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (!rotationAmountOf(turn).landsInWave) return null;
    return _requireAlongTheSet(formation, who, name, 'turn', turn);
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final amount = rotationAmountOf(turn);
    if (amount == RotationAmount.whole) return Ok(formation);
    if (amount.landsInWave) {
      return Ok(
        quarterTurnIntoWave(
          formation,
          whoPairsInSet(formation, who),
          hand: hand,
          afterHalfTurn: amount == RotationAmount.threeQuarter,
        ),
      );
    }
    return Ok(
      swapPairs(
        formation,
        whoPairsInSet(formation, who),
        facing: (before, after, other) => before.facing.reversed,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Allemande &&
      other.who == who &&
      other.hand == hand &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(name, who, hand, turn);

  @override
  String toString() => 'allemande(${who.key}, ${hand.key}, $turn)';
}

/// `two_hand_turn` — the pair take **both** hands and turn around each other.
///
/// The two-handed hold is the whole difference from [Allemande]. It keeps the
/// pair face to face throughout, so the ending facing is **relational** —
/// toward the other dancer, derived from where they finish — rather than a
/// rotation of the input facing.
///
/// It also means the move carries no direction token at all, which is why a
/// quarter turn is *doubly* undetermined here: `allemande` at least has a hand
/// to fix the wave's direction.
final class TwoHandTurn extends Operation {
  const TwoHandTurn({this.who = WhoSet.partners, this.turn = 1.0});

  /// The turning pair.
  final WhoSet who;

  /// How far around, in full turns.
  final double turn;

  @override
  String get name => 'two_hand_turn';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    final quarter = _requireWholeOrHalf(turn, name, 'turn');
    if (quarter != null) return quarter;

    final apart = firstNonAdjacentPair(
      formation,
      whoPairsInSet(formation, who),
    );
    if (apart == null) return null;
    return OpError(
      ErrorKind.unresolvableDancerSet,
      'two_hand_turn needs the pair side by side for a two-handed hold, but '
      '${apart.a} and ${apart.b} are diagonal',
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final pairs = whoPairsInSet(formation, who);
    if (rotationAmountOf(turn) == RotationAmount.half) {
      return Ok(
        swapPairs(
          formation,
          pairs,
          facing: (before, after, other) =>
              facingToward(after, other) ?? before.facing,
        ),
      );
    }

    // A whole turn moves nobody, but the pair still finishes facing each
    // other, and a downstream precondition may read that.
    final changes = <DancerId, DancerState>{};
    for (final pair in pairs) {
      final stateA = formation.stateOf(pair.a);
      final stateB = formation.stateOf(pair.b);
      final toward = facingToward(stateA.position, stateB.position);
      if (toward == null) continue;
      changes[pair.a] = stateA.copyWith(facing: toward);
      changes[pair.b] = stateB.copyWith(facing: toward.reversed);
    }
    return Ok(formation.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other is TwoHandTurn && other.who == who && other.turn == turn;

  @override
  int get hashCode => Object.hash(name, who, turn);

  @override
  String toString() => 'two_hand_turn(${who.key}, $turn)';
}

/// `shoulder_round` — two dancers walk around each other facing, without hands.
/// Also called a gypsy or a gyre.
///
/// Positionally the face-to-face twin of `do_si_do`. The difference is that it
/// **carries a determinate facing**, keyed off which shoulder passes: see
/// [focusFacing].
///
/// The exception is a **quarter**, where the pair lands in a short wave and
/// §8.5.6's rule that the wave owns the facing overrides the focus rule — a
/// wave whose dancers did not alternate would not be a wave. `shoulder` then
/// plays the part `allemande`'s `hand` plays, fixing the wave's handedness.
final class ShoulderRound extends Operation {
  const ShoulderRound({
    this.who = WhoSet.neighbors,
    this.shoulder = Hand.right,
    this.turn = 1.0,
  });

  /// The pair that goes around. Relaxed precondition, as `do_si_do`.
  final WhoSet who;

  /// Which shoulder passes. This is the **focus** that fixes the ending facing,
  /// though it is irrelevant to the end position at whole and half turns. On a
  /// quarter it instead fixes the handedness of the wave the pair lands in:
  /// `right` builds the canonical wave (§8.5.6).
  final Hand shoulder;

  /// How far around, in full turns. `1` is once around, back to place.
  final double turn;

  @override
  String get name => 'shoulder_round';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (!rotationAmountOf(turn).landsInWave) return null;
    return _requireAlongTheSet(formation, who, name, 'turn', turn);
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final amount = rotationAmountOf(turn);
    if (amount.landsInWave) {
      return Ok(
        quarterTurnIntoWave(
          formation,
          whoPairsInSet(formation, who),
          hand: shoulder,
          afterHalfTurn: amount == RotationAmount.threeQuarter,
        ),
      );
    }
    final moved = amount == RotationAmount.half
        ? swapPairs(formation, whoPairsInSet(formation, who))
        : formation;
    return Ok(
      mapBandFacing(
        moved,
        (id, state, band) =>
            focusFacing(focus: shoulder, at: state.position, band: band),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoulderRound &&
      other.who == who &&
      other.shoulder == shoulder &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(name, who, shoulder, turn);

  @override
  String toString() => 'shoulder_round(${who.key}, ${shoulder.key}, $turn)';
}

/// `mad_robin` — an orbit **along** the set: each dancer circles their
/// column-mate while facing across.
///
/// The axis is fixed by the figure rather than chosen by `who`, so a half turn
/// is a global row swap regardless of which pair is named as going in front
/// first. Both `direction` and `whom` are descriptive at whole and half turns.
final class MadRobin extends Operation {
  const MadRobin({
    this.who = WhoSet.ones,
    this.turn = 1.0,
    this.direction,
    this.whom,
  });

  /// The pair that steps in front first. Descriptive.
  final WhoSet who;

  /// The orbit amount, in full turns.
  final double turn;

  /// The rotation sense. `null` is the upstream `unspecified` sentinel.
  /// Styling at whole and half turns — 180° lands the same either way.
  final SpinDirection? direction;

  /// The pair you travel around. `null` is the `unspecified` sentinel; the
  /// along-set axis is already fixed by the figure, so this is descriptive.
  final WhoSet? whom;

  @override
  String get name => 'mad_robin';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom];

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireWholeOrHalf(turn, name, 'turn');

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    reflectBands(
      formation,
      rows: rotationAmountOf(turn) == RotationAmount.half,
      facing: (before, after, band) => acrossFacingInto(after.col),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is MadRobin &&
      other.who == who &&
      other.turn == turn &&
      other.direction == direction &&
      other.whom == whom;

  @override
  int get hashCode => Object.hash(name, who, turn, direction, whom);

  @override
  String toString() => 'mad_robin(${who.key}, $turn)';
}

/// `orbit` — the `who` dancers travel around the outside of the hands four.
///
/// The one figure whose amount lives in an `amount` slot: its `turn` is spent
/// on the spin direction instead.
///
/// A half orbit is a 180° rotation about the centre of the hands four, which
/// maps the two Larks — diagonally opposite in Duple Improper — exactly onto
/// each other. For a same-role `who` the swap rule is therefore provably the
/// real orbit.
///
/// ⚠️ **For a couple `who` it is not.** The 1s are row-mates, so rotating them
/// about the centre would carry them onto the 2s' cells, which only resolves
/// once the centre figure's outcome is known — the *meanwhile* dependency,
/// which is not modelled. The swap rule is applied to every `who` on the user's
/// ruling; the caveat is recorded here because the baseline default `who` is
/// `ones`, so the default invocation is the caveated case.
final class Orbit extends Operation {
  const Orbit({
    this.who = WhoSet.ones,
    this.turn = SpinDirection.clockwise,
    this.amount = 0.5,
  });

  /// The orbiting dancers.
  final WhoSet who;

  /// The rotation sense. Not an amount — see [amount].
  final SpinDirection turn;

  /// How far around, in full turns.
  final double amount;

  @override
  String get name => 'orbit';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireWholeOrHalf(amount, name, 'amount');

  @override
  Result<Formation, OpError> perform(Formation formation) {
    if (rotationAmountOf(amount) == RotationAmount.whole) return Ok(formation);
    return Ok(
      swapPairs(
        formation,
        whoPairsInSet(formation, who),
        // The "facing (output): Flexible" contract, scoped to the orbiting
        // dancers rather than the band. Unlike `circle` and `star`, an orbit
        // moves only its `who` - usually two of the four - so loosening the
        // whole hands four would discard the facing of dancers who never
        // moved. A whole orbit is the identity and returns above, so nobody
        // reaches here without having gone somewhere.
        facing: (before, after, other) => Facing.flexible,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Orbit &&
      other.who == who &&
      other.turn == turn &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(name, who, turn, amount);

  @override
  String toString() => 'orbit(${who.key}, ${turn.key}, $amount)';
}

/// `star_promenade` — all four rotate around a central star, couples
/// travelling as units.
///
/// A half is a 180° rotation of the whole ring, which is the diagonal swap.
/// Quarters are deferred for a specific reason: the Compendium removed this
/// move's `hand` parameter, so it carries **no direction token**, and a
/// one-place rotation with no direction is undetermined.
final class StarPromenade extends Operation {
  const StarPromenade({this.who = WhoSet.role1s, this.turn = 0.5});

  /// The dancer you pick up on the side. Descriptive; no positional effect at
  /// whole or half turns.
  final WhoSet who;

  /// The rotation amount, in full turns.
  final double turn;

  @override
  String get name => 'star_promenade';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) =>
      _requireWholeOrHalf(turn, name, 'turn');

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final half = rotationAmountOf(turn) == RotationAmount.half;
    return Ok(reflectBands(formation, rows: half, columns: half));
  }

  @override
  bool operator ==(Object other) =>
      other is StarPromenade && other.who == who && other.turn == turn;

  @override
  int get hashCode => Object.hash(name, who, turn);

  @override
  String toString() => 'star_promenade(${who.key}, $turn)';
}
