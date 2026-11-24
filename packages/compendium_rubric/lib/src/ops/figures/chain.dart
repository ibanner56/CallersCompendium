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
///
/// A diagonal pairs dancers by **where they stand** *(user-ruled
/// 2026-11-23)*: the chaining dancer on the west line (`c0`) of each grouping
/// swaps cells with the chaining dancer on the east line (`c4`) of the
/// grouping above for `left_diagonal`, below for `right_diagonal`. `across`
/// pairs the #2 with the #1 of the same grouping, by couple number, as it
/// always has. The diagonal pair are the dancers who stand on that diagonal:
/// facing across from the west line, your left is up the set and your right
/// down it. Pairing by couple number instead read the right pair only while
/// the #2s stood on the west line; after an across chain had traded the
/// chaining dancers' sides it chained them on the other diagonal.
///
/// A couple waiting out at an end takes part from whichever line its
/// chaining dancer stands on *(user-ruled 2026-11-23)*.
///
/// Iterating the starting dancers alone is what guarantees the taxonomy's
/// *vital* invariant that **no dancer is swapped twice**. Where no couple
/// stands on the diagonal — the top grouping reaching further up, the bottom
/// reaching further down — or the couple there has no chaining dancer, the
/// dancer simply stays put.
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
    return _allSides(formation).errorOrNull;
  }

  /// The chaining dancers of [grouping] that start and receive a trade, or
  /// why the grouping cannot be read.
  ///
  /// A diagonal reads them by line: the west-line dancer starts, the east-line
  /// one receives. Two chaining dancers on one line, or one off the side
  /// lines, leave no diagonal to read; that is refused rather than guessed.
  /// A waiting couple's lone chaining dancer on a side line is the exception:
  /// it is read as both, so it takes part from either line.
  /// `across` keeps reading them by couple number (the #2 starts, the #1
  /// receives): the ruling was about diagonals, and number pairing is what
  /// lets a chain across between two dancers on one line, as in a proper
  /// set's ladies chain after the ones cast, keep the trade it always made.
  /// Only when the numbers name no pair does `across` read them by line.
  Result<({DancerId? west, DancerId? east}), OpError> _sides(
    Formation formation,
    Grouping grouping,
  ) {
    if (!dir.isDiagonal) {
      final two = _byNumber(formation, grouping, CoupleNumber.two);
      final one = _byNumber(formation, grouping, CoupleNumber.one);
      if (two != null && one != null) return Ok((west: two, east: one));
      // The numbers name no pair, as when an earlier diagonal chain left both
      // chaining dancers of a hands four with one number. Two of them facing
      // each other across the set are still the pair: read them by line
      // rather than leave the hands four silently unchained. *(Agent's call,
      // following the 2026-11-23 ruling; a pair the numbers do name is never
      // overridden.)*
      final chainers = [
        for (final id in dancersInGrouping(formation, grouping))
          if (id.role == _chainingRole) id,
      ];
      if (chainers.length == 2) {
        final cols = {
          for (final id in chainers) formation.stateOf(id).position.col,
        };
        if (cols.containsAll(const [0, kColumnCount - 1])) {
          return Ok((
            west: chainers.firstWhere(
              (id) => formation.stateOf(id).position.col == 0,
            ),
            east: chainers.firstWhere(
              (id) => formation.stateOf(id).position.col == kColumnCount - 1,
            ),
          ));
        }
      }
      return Ok((west: two, east: one));
    }
    if (grouping.isWaiting) {
      // A couple waiting out at an end still takes part from whichever line
      // its chaining dancer stands on: it is the only couple on that
      // diagonal. *(User-ruled 2026-11-23, on Ragtime Annie.)* It has one
      // neighbouring grouping, so it starts or receives at most one trade.
      // Anything but one chaining dancer on a side line falls through to the
      // line read below, which refuses what it cannot pair. *(Agent's call.)*
      final chainers = [
        for (final id in dancersInGrouping(formation, grouping))
          if (id.role == _chainingRole) id,
      ];
      if (chainers.length == 1) {
        final col = formation.stateOf(chainers.single).position.col;
        if (col == 0 || col == kColumnCount - 1) {
          return Ok((west: chainers.single, east: chainers.single));
        }
      }
    }
    DancerId? west;
    DancerId? east;
    for (final id in dancersInGrouping(formation, grouping)) {
      if (id.role != _chainingRole) continue;
      final col = formation.stateOf(id).position.col;
      if (col == 0 && west == null) {
        west = id;
      } else if (col == kColumnCount - 1 && east == null) {
        east = id;
      } else {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'chain needs one ${who.key} dancer on each side line of a hands '
            'four, but $id at column $col leaves no pair across the set to '
            'chain',
          ),
        );
      }
    }
    return Ok((west: west, east: east));
  }

  /// The chaining dancer of [grouping] whose couple number is [number].
  DancerId? _byNumber(
    Formation formation,
    Grouping grouping,
    CoupleNumber number,
  ) {
    for (final id in dancersInGrouping(formation, grouping)) {
      if (id.role != _chainingRole) continue;
      if (formation.stateOf(id).number == number) return id;
    }
    return null;
  }

  /// Every grouping's starting and receiving chaining dancers, top to bottom.
  Result<List<({DancerId? west, DancerId? east})>, OpError> _allSides(
    Formation formation,
  ) {
    final sides = <({DancerId? west, DancerId? east})>[];
    for (final grouping in groupingsDownTheSet(formation)) {
      switch (_sides(formation, grouping)) {
        case Ok(:final value):
          sides.add(value);
        case Err(:final error):
          return Err(error);
      }
    }
    return Ok(sides);
  }

  Role get _chainingRole => who == WhoSet.role1s ? Role.lark : Role.robin;

  /// The grouping index a starting dancer in grouping [index] trades with.
  int _targetIndex(int index) => switch (dir) {
    ChainDirection.across => index,
    ChainDirection.leftDiagonal => index - 1,
    ChainDirection.rightDiagonal => index + 1,
    ChainDirection.along => index,
  };

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final List<({DancerId? west, DancerId? east})> sides;
    switch (_allSides(formation)) {
      case Ok(:final value):
        sides = value;
      case Err(:final error):
        return Err(error);
    }
    final changes = <DancerId, DancerState>{};
    final swapped = <DancerId>{};

    // Iterate the starting dancers only. This is the taxonomy's stated
    // invariant, and it is load-bearing: scanning both would swap every pair
    // twice and return the set to where it started.
    for (var i = 0; i < sides.length; i++) {
      final initiator = sides[i].west;
      if (initiator == null || swapped.contains(initiator)) continue;

      final target = _targetIndex(i);
      if (target < 0 || target >= sides.length) continue;

      final receiver = sides[target].east;
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
    final chained = formation.withUpdates(changes);
    return Ok(
      dir.isDiagonal ? _rememberShadows(formation, chained, swapped) : chained,
    );
  }

  /// [after] with the shadows a diagonal chain makes remembered.
  ///
  /// A chaining dancer who stood beside a neighbour before the chain is
  /// chaining to a shadow *(user-ruled 2026-11-24)*: whoever she ends beside
  /// is her shadow from then on, so a later figure naming shadows finds them
  /// by who they are ([DancerState.shadow]). One who stood beside her partner
  /// chains to a neighbour and makes no shadow. A dancer who already has a
  /// shadow keeps the one they first danced with.
  ///
  /// "Beside" is read in the hands fours the chain was danced in, before and
  /// after alike: the chain moves no one between groupings' boundaries, but a
  /// trade with a couple waiting out can leave the end rows looking like a
  /// different grouping. A dancer who lands in a waiting couple's row, or
  /// beside someone of her own role or her own partner, remembers nobody
  /// *(agent's calls)*.
  static Formation _rememberShadows(
    Formation before,
    Formation after,
    Set<DancerId> swapped,
  ) {
    final bands = handsFourBands(before);
    final changes = <DancerId, DancerState>{};
    for (final id in swapped) {
      final besideBefore = _beside(before, bands, id);
      if (besideBefore == null ||
          besideBefore.role == id.role ||
          besideBefore.coupleIndex == id.coupleIndex) {
        continue;
      }
      final shadow = _beside(after, bands, id);
      if (shadow == null ||
          shadow.role == id.role ||
          shadow.coupleIndex == id.coupleIndex) {
        continue;
      }
      for (final (who, other) in [(id, shadow), (shadow, id)]) {
        final state = changes[who] ?? after.stateOf(who);
        if (state.shadow == null) changes[who] = state.copyWith(shadow: other);
      }
    }
    return changes.isEmpty ? after : after.withUpdates(changes);
  }

  /// The dancer standing beside [id] in [formation] on their side line: the
  /// same column, the other row of whichever of [bands] holds their row.
  /// `null` when their row is in none of them (a waiting couple's row).
  static DancerId? _beside(
    Formation formation,
    List<({int topRow, int bottomRow})> bands,
    DancerId id,
  ) {
    final at = formation.stateOf(id).position;
    for (final band in bands) {
      if (at.row != band.topRow && at.row != band.bottomRow) continue;
      final other = at.row == band.topRow ? band.bottomRow : band.topRow;
      return formation.dancerAt(Position(other, at.col));
    }
    return null;
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
