part of '../operation.dart';

/// `revolving_door` — the leaders star-promenade the dancers they carry across
/// the set, drop them off, and turn on to meet someone new.
///
/// **User-ruled (2026-11-22):** the named dancers (`who`, the role2s by
/// default) effectively **allemande once around**, ending where they started,
/// while **the other pair trades places**. That is the net of how The Caller's
/// Box writes the figure out — a star promenade halfway, then the leaders
/// turning halfway by the named hand — reduced to its landing.
///
/// In every hands four exactly one `who` pair must be found; anything else
/// (no leaders, or a `who` such as `partners` that names two pairs) has no
/// single "other pair" to carry and is refused rather than guessed. The
/// leaders must also stand on the diagonal of the hands four, since they join
/// hands across its centre. *(Agent's call, 2026-11-22, not yet ruled: the
/// alternative was dancing leaders who share a row or column, where the
/// written-out star promenade and allemande would move them and this net
/// would not.)*
///
/// `hand` is carried for fidelity and has no positional effect. `whom` does not
/// change who trades places either, but like every dancer set a figure names
/// it chooses which hands four the figure is danced in: a `whom` reaching the
/// next neighbours or the shadows re-bands the set first, exactly as it would
/// for any other figure. (The Caller's Box import does not recover `whom` from
/// its written-out lines, so it usually arrives as the default.)
final class RevolvingDoor extends Operation {
  const RevolvingDoor({
    this.who = WhoSet.role2s,
    this.hand = Hand.right,
    this.whom = WhoSet.partners,
  });

  /// The leaders, who join hands in the centre and end where they began.
  final WhoSet who;

  /// The hand the leaders join.
  final Hand hand;

  /// Whom the leaders carry and drop off on the far side.
  final WhoSet whom;

  @override
  String get name => 'revolving_door';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom];

  /// Per hands four, the carried pair: the two dancers who are not the single
  /// `who` pair. Returns the refusal instead when the band has no such split.
  Result<List<DancerPair>, OpError> _carried(Formation formation) {
    final carried = <DancerPair>[];
    for (final band in handsFourBands(formation)) {
      final leaders = resolveWhoPairs(
        formation,
        who,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (leaders.length != 1) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'revolving_door needs exactly one ${who.key} pair to lead in each '
            'hands four, but rows ${band.topRow}-${band.bottomRow} have '
            '${leaders.length}',
          ),
        );
      }
      final leader = leaders.single;
      // The leaders join hands across the middle of the hands four, so they
      // must stand on its diagonal: two dancers sharing a row or a column are
      // on one side of the centre, with no star to make.
      final a = formation.stateOf(leader.a).position;
      final b = formation.stateOf(leader.b).position;
      if (a.row == b.row || a.col == b.col) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'revolving_door needs the ${who.key} leading it to stand on the '
            'diagonal of the hands four, but ${leader.a} and ${leader.b} '
            'share a ${a.row == b.row ? 'row' : 'column'}',
          ),
        );
      }
      final rest = [
        ...formation.dancersInRow(band.topRow),
        ...formation.dancersInRow(band.bottomRow),
      ].where((id) => id != leader.a && id != leader.b).toList();
      if (rest.length != 2) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'revolving_door needs two dancers to carry in each hands four, '
            'but rows ${band.topRow}-${band.bottomRow} have ${rest.length}',
          ),
        );
      }
      carried.add((a: rest[0], b: rest[1]));
    }
    return Ok(carried);
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_carried(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _carried(formation).map((pairs) => swapPairs(formation, pairs));

  @override
  bool operator ==(Object other) =>
      other is RevolvingDoor &&
      other.who == who &&
      other.hand == hand &&
      other.whom == whom;

  @override
  int get hashCode => Object.hash(name, who, hand, whom);

  @override
  String toString() => 'revolving_door(${who.key}, ${hand.key}, ${whom.key})';
}
