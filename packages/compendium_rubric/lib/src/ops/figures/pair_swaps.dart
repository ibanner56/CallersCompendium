part of '../operation.dart';

/// The plain pair swaps: `roll_away`, `pull_by_dancers`, `pass_by` and
/// `box_the_gnat`.
///
/// Each takes a named pair and exchanges their cells. The first three preserve
/// facing — a dancer walks forward past the other and keeps their direction —
/// and differ only in which parameter names the swapping pair and which
/// styling tokens they carry. `box_the_gnat` joins them for the permutation but
/// adds a facing precondition and a relational ending facing.

/// `roll_away` — the two dancers of the `whom` pair trade places, one rolling
/// across in front of the other.
///
/// Note that it is `whom`, not `who`, that names the swapping pair: `who` is
/// actor context and has no positional effect. Getting that the wrong way round
/// would silently swap a different pair.
final class RollAway extends Operation {
  const RollAway({
    this.who = WhoSet.neighbors,
    this.whom = WhoSet.partners,
    this.halfSashay = false,
  });

  /// Actor context. Descriptive; no end-position effect.
  final WhoSet who;

  /// **The relationship that trades** — this names the swapping pair.
  final WhoSet whom;

  /// Styling: a sashay rather than a roll. No end-state effect.
  final bool halfSashay;

  @override
  String get name => 'roll_away';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom];

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(swapPairs(formation, whoPairsInSet(formation, whom)));

  @override
  bool operator ==(Object other) =>
      other is RollAway &&
      other.who == who &&
      other.whom == whom &&
      other.halfSashay == halfSashay;

  @override
  int get hashCode => Object.hash(name, who, whom, halfSashay);

  @override
  String toString() => 'roll_away(${who.key}, ${whom.key})';
}

/// `pull_by_dancers` — the `who` pair take hands and pull past each other.
///
/// Progression is **not** baked in: a pull-by is a swap within the hands four
/// and only reaches new neighbours when the invocation carries the explicit
/// `progression` flag. This is the same stance `pass_through` takes.
final class PullByDancers extends Operation {
  const PullByDancers({
    this.who = WhoSet.neighbors,
    this.balance = false,
    this.hand = Hand.right,
  });

  /// The pair that pulls by, and therefore swaps.
  final WhoSet who;

  /// A balance lead-in; no end-state effect.
  final bool balance;

  /// Which hand passes. Styling; no positional effect.
  final Hand hand;

  @override
  String get name => 'pull_by_dancers';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(swapPairs(formation, whoPairsInSet(formation, who)));

  @override
  bool operator ==(Object other) =>
      other is PullByDancers &&
      other.who == who &&
      other.balance == balance &&
      other.hand == hand;

  @override
  int get hashCode => Object.hash(name, who, balance, hand);

  @override
  String toString() => 'pull_by_dancers(${who.key}, ${hand.key})';
}

/// `pass_by` — the `who` pair walk forward and pass by the given shoulder.
///
/// The shoulder-named twin of [PullByDancers].
final class PassBy extends Operation {
  const PassBy({this.who = WhoSet.neighbors, this.shoulder = Hand.right});

  /// The pair that passes by, and therefore swaps.
  final WhoSet who;

  /// Which shoulder passes. Styling; no positional effect.
  final Hand shoulder;

  @override
  String get name => 'pass_by';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok(swapPairs(formation, whoPairsInSet(formation, who)));

  @override
  bool operator ==(Object other) =>
      other is PassBy && other.who == who && other.shoulder == shoulder;

  @override
  int get hashCode => Object.hash(name, who, shoulder);

  @override
  String toString() => 'pass_by(${who.key}, ${shoulder.key})';
}

/// `box_the_gnat` — two facing dancers join hands and trade places, one turning
/// under.
///
/// Unlike the rest of this family it **requires** its pairs to be adjacent:
/// partners across the set share a row, neighbours up and down share a column.
/// A diagonal pair has no hand to give, so it raises
/// [ErrorKind.notAdjacent]. This is the one refusal in the family that is not
/// about facing — no turn on the spot brings a diagonal within reach.
///
/// Deliberately **not** normalized. Box the gnat leaves dancers on the swapped
/// — often "wrong" — side, which is usually the point: it commonly sets up a
/// following pull-by or twirl that expects exactly that arrangement.
final class BoxTheGnat extends Operation {
  const BoxTheGnat({
    this.who = WhoSet.partners,
    this.hand = Hand.right,
    this.balance = false,
  });

  /// Which pair trades. Both pairs in the hands four participate.
  final WhoSet who;

  /// The turning hand. `left` is the `swat_the_flea` alias; no position effect.
  final Hand hand;

  /// A balance lead-in; no end-state effect.
  final bool balance;

  @override
  String get name => 'box_the_gnat';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) {
    final diagonal = firstNonAdjacentPair(
      formation,
      whoPairsInSet(formation, who),
    );
    if (diagonal == null) return null;
    return OpError(
      ErrorKind.notAdjacent,
      'box_the_gnat needs each ${who.key} pair adjacent, but ${diagonal.a} and '
      '${diagonal.b} are diagonal',
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(
    swapPairs(
      formation,
      whoPairsInSet(formation, who),
      // The pair ends facing each other across whichever axis they swapped on.
      facing: (before, after, other) =>
          facingToward(after, other) ?? before.facing,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is BoxTheGnat &&
      other.who == who &&
      other.hand == hand &&
      other.balance == balance;

  @override
  int get hashCode => Object.hash(name, who, hand, balance);

  @override
  String toString() => 'box_the_gnat(${who.key}, ${hand.key})';
}
