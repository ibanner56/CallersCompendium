part of '../operation.dart';

/// The parameterized corner-ring rotations.
///
/// `circle`, `star` and `petronella` are the fixed-direction members of this
/// family and already live in their own files; the two here take their
/// direction from a parameter. All five turn the same ring `O` and differ only
/// in how far, which way, and what facing they leave behind.

/// `box_circulate` — all four dancers circulate one place around the box.
///
/// The `hand` sets the direction: `right` turns the ring **clockwise** (which
/// is the `circle left` rotation) and `left` turns it **counter-clockwise**
/// (the `petronella` rotation). Note the inversion — as with [CircleDirection],
/// the hand named is not the direction travelled.
///
/// Unlike the other ring figures this one **carries a determinate facing**,
/// keyed off the same focus rule `shoulder_round` uses: see [focusFacing].
final class BoxCirculate extends Operation {
  const BoxCirculate({
    this.who = WhoSet.partners,
    this.hand = Hand.right,
    this.balance = false,
  });

  /// The box members. Descriptive — all four dancers circulate regardless.
  final WhoSet who;

  /// The focus hand, which sets both the rotation direction and the facing.
  final Hand hand;

  /// An optional balance lead-in; no end-state effect.
  final bool balance;

  @override
  String get name => 'box_circulate';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// Clockwise for the right hand, counter-clockwise for the left.
  ///
  /// [rotateHandsFourRings] reads a positive offset as counter-clockwise.
  int get _steps => hand == Hand.right ? -1 : 1;

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final rotated = rotateHandsFourRings(formation, steps: _steps);
    return Ok(
      mapBandFacing(rotated, (id, state, band) {
        // The rotation itself skips an incomplete band, so the facing rule must
        // skip it too - otherwise a transient shape the rotation deliberately
        // left alone would still have a facing imposed on it.
        if (!bandIsComplete(rotated, band)) return null;
        return focusFacing(focus: hand, at: state.position, band: band);
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BoxCirculate &&
      other.who == who &&
      other.hand == hand &&
      other.balance == balance;

  @override
  int get hashCode => Object.hash(name, who, hand, balance);

  @override
  String toString() => 'box_circulate(${who.key}, ${hand.key})';
}

/// `facing_star` — two facing couples put a hand in and rotate as a star.
///
/// Mechanically identical to `star` and `circle`, but parameterized by an
/// explicit spin direction rather than by a hand or a left/right token. All
/// `places` are representable because the ring uses only the side columns.
final class FacingStar extends Operation {
  const FacingStar({
    this.who = WhoSet.ones,
    this.turn = SpinDirection.clockwise,
    this.places = 3,
  });

  /// Descriptive — a star is always four hands, and all four dancers rotate.
  final WhoSet who;

  /// The rotation direction. Here `turn` is a **spin direction**, not an
  /// amount: see the `turn` polymorphism note in `docs/taxonomy.md`.
  final SpinDirection turn;

  /// Position-steps around the ring; only `places mod 4` has any effect.
  final int places;

  @override
  String get name => 'facing_star';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final steps = turn.ringSign * (places % 4);
    final rotated = rotateHandsFourRings(formation, steps: steps);
    return Ok(steps % 4 == 0 ? rotated : loosenBandFacing(rotated));
  }

  @override
  bool operator ==(Object other) =>
      other is FacingStar &&
      other.who == who &&
      other.turn == turn &&
      other.places == places;

  @override
  int get hashCode => Object.hash(name, who, turn, places);

  @override
  String toString() => 'facing_star(${who.key}, ${turn.key}, $places)';
}
