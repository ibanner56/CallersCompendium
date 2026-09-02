part of '../operation.dart';

/// The direction a `chain` travels.
///
/// Canonical spelling is **camelCase**, matching the upstream direction
/// vocabulary that real dance records are written against. The snake_case
/// spelling used in `docs/taxonomy.md` prose is accepted as an alias at the
/// JSON parse boundary only, so the pure core sees one vocabulary — the same
/// arrangement [WhoSet] uses.
enum ChainDirection {
  across('across'),
  along('along'),
  rightDiagonal('rightDiagonal', aliases: {'right_diagonal'}),
  leftDiagonal('leftDiagonal', aliases: {'left_diagonal'});

  const ChainDirection(this.key, {this.aliases = const {}});

  /// The value as it appears in the external JSON.
  final String key;

  /// Alternate spellings accepted on input and normalized to [key].
  final Set<String> aliases;

  /// Whether this direction reaches into an adjacent grouping.
  bool get isDiagonal =>
      this == ChainDirection.rightDiagonal ||
      this == ChainDirection.leftDiagonal;

  static ChainDirection? fromKey(String key) {
    for (final value in ChainDirection.values) {
      if (value.key == key || value.aliases.contains(key)) return value;
    }
    return null;
  }
}

/// `chain` — a pull-by to a courtesy turn, trading places with another dancer
/// of the same role (`docs/taxonomy.md`).
///
/// The chain is defined over **groupings**, not hands four: a waiting-out
/// couple at an end of the set participates as its own single-couple grouping.
/// That is the whole reason the pairing rule is stated in terms of **couple
/// number** rather than column — a waiting couple's chaining dancer can sit in
/// either column, so the older "scan c0" shortcut would miss it.
///
/// Each **#2** chaining dancer swaps cells with the **#1** chaining dancer of
/// the grouping named by [dir]: the same grouping for `across`, the one above
/// for `left_diagonal`, the one below for `right_diagonal`. Iterating the #2s
/// alone is what guarantees the taxonomy's *vital* invariant that **no dancer
/// is swapped twice**. Where the needed grouping or partner does not exist —
/// the top grouping reaching further up, the bottom reaching further down —
/// the dancer simply stays put.
///
/// [hand] does not affect end positions, and no normalization is applied: the
/// closing courtesy turn is a rigid wheel that preserves the couple's
/// handedness rather than imposing lark-left/robin-right.
///
/// `along` is deferred — the taxonomy believes it occurs only in
/// four-facing-four dances, which are out of scope.
final class Chain extends Operation {
  const Chain({
    required this.who,
    this.hand = Hand.right,
    this.dir = ChainDirection.across,
  });

  /// The role that chains across. Only the role sets are meaningful here.
  final WhoSet who;

  /// The pull-by hand. Recorded for fidelity; no end-state effect.
  final Hand hand;

  /// The direction of the chain.
  final ChainDirection dir;

  @override
  String get name => 'chain';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// A diagonal needs one extra hands four so the ends have somewhere to reach
  /// (§3.1, D7).
  @override
  int get hands4Contribution => dir.isDiagonal ? 1 : 0;

  @override
  bool get progressionEligible => true;

  @override
  OpError? checkPreconditions(Formation formation) {
    if (dir == ChainDirection.along) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'chain dir:along is deferred (four-facing-four only)',
      );
    }
    if (who != WhoSet.role1s && who != WhoSet.role2s) {
      return OpError(
        ErrorKind.unsupportedParam,
        'chain requires a role set (role1s / role2s); got ${who.key}',
      );
    }
    return null;
  }

  /// The chaining dancer of [grouping] whose couple number is [number].
  DancerId? _chainer(
    Formation formation,
    Grouping grouping,
    CoupleNumber number,
  ) {
    for (final id in dancersInGrouping(formation, grouping)) {
      final state = formation.stateOf(id);
      if (state.number != number) continue;
      if (id.role != _chainingRole) continue;
      return id;
    }
    return null;
  }

  Role get _chainingRole => who == WhoSet.role1s ? Role.lark : Role.robin;

  /// The grouping index a #2 in grouping [index] trades with.
  int _targetIndex(int index) => switch (dir) {
    ChainDirection.across => index,
    ChainDirection.leftDiagonal => index - 1,
    ChainDirection.rightDiagonal => index + 1,
    ChainDirection.along => index,
  };

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final groupings = groupingsDownTheSet(formation);
    final changes = <DancerId, DancerState>{};
    final swapped = <DancerId>{};

    // Iterate the #2s only. This is the taxonomy's stated invariant, and it is
    // load-bearing: scanning both numbers would swap every pair twice and
    // return the set to where it started.
    for (var i = 0; i < groupings.length; i++) {
      final initiator = _chainer(formation, groupings[i], CoupleNumber.two);
      if (initiator == null || swapped.contains(initiator)) continue;

      final target = _targetIndex(i);
      if (target < 0 || target >= groupings.length) continue;

      final receiver = _chainer(formation, groupings[target], CoupleNumber.one);
      if (receiver == null || swapped.contains(receiver)) continue;

      final from = formation.stateOf(initiator);
      final to = formation.stateOf(receiver);
      changes[initiator] = from.copyWith(
        position: to.position,
        facing: _facingIn(to.position.col),
      );
      changes[receiver] = to.copyWith(
        position: from.position,
        facing: _facingIn(from.position.col),
      );
      swapped
        ..add(initiator)
        ..add(receiver);
    }
    return Ok(formation.withUpdates(changes));
  }

  /// Dancers finish facing **across, into the set**.
  Facing _facingIn(int col) => col == 0 ? Facing.acrossEast : Facing.acrossWest;

  @override
  bool operator ==(Object other) =>
      other is Chain &&
      other.who == who &&
      other.hand == hand &&
      other.dir == dir;

  @override
  int get hashCode => Object.hash(name, who, hand, dir);

  @override
  String toString() => 'chain(${who.key}, ${hand.key}, ${dir.key})';
}
