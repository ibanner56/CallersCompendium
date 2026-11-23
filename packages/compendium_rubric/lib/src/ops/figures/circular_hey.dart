part of '../operation.dart';

/// `circular_hey` — a square through without hands: the four dancers of a
/// ring weave around it, passing alternate shoulders (`docs/taxonomy.md`).
///
/// Each **change** is one pass, and a pass swaps the two dancers passing, as a
/// pull-by does. The `who` pairs pass first, along the set or across it
/// depending on where they stand; the other pairs of the ring pass next, on
/// the other axis, and the changes alternate from there. So four changes
/// bring everyone home, two put each dancer in the opposite corner, and one or
/// three are a swap on one axis. *(The agent's reading of the core taxonomy
/// definition, 2026-11-23; not yet ruled.)*
///
/// The first axis is read from the formation rather than from `where`: the
/// Caller's Box records almost never state `where`, so the import fills its
/// default (`across`) even where neighbours stand along the set. `shoulder`
/// and `where` are carried for fidelity and move nobody.
///
/// A stated `who2` is **checked**, not just carried: after the first pass it
/// must name the two pairs then standing on the other axis, or the figure
/// refuses with [ErrorKind.whoMismatch]. A `who2` reaching another hands four
/// is deferred ([ErrorKind.unsupportedParam]), because only `who` chooses the
/// band phase (`shadows` there is deferred at parse time for the same reason).
///
/// `who` must name two pairs in every hands four, so `ones`, `twos` and the
/// role sets, which name one, are refused rather than read as implying the
/// other pair. *(Agent's call.)*
///
/// Facing: one change keeps it, since everyone walked straight through. After
/// more, each pass turned the dancers to face the next, so facing is left
/// flexible for the next figure to resolve, as `square_through`'s contract
/// says.
final class CircularHey extends Operation {
  const CircularHey({
    this.who = WhoSet.neighbors,
    this.changes = 4,
    this.shoulder = Hand.right,
    this.who2,
    this.where = Direction.across,
  });

  /// The pairs that pass first.
  final WhoSet who;

  /// How many passes. Four is the full circuit.
  final int changes;

  /// The shoulder of the first pass. Styling; no positional effect.
  final Hand shoulder;

  /// The pairs that pass second, when the record names them. Checked against
  /// the ring after the first pass (see above); moves nobody.
  final WhoSet? who2;

  /// The record's direction for the first pass. Descriptive (see above).
  final Direction where;

  @override
  String get name => 'circular_hey';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  /// Whether the first pass is along the set (a row swap) rather than across
  /// it, read from where the `who` pairs stand in every hands four.
  Result<bool, OpError> _firstAlong(Formation formation) {
    if (who == WhoSet.everyone) {
      return const Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'circular_hey needs a pairing to pass first; everyone names none',
        ),
      );
    }
    bool? along;
    for (final band in handsFourBands(formation)) {
      final pairs = resolveWhoPairs(
        formation,
        who,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      if (pairs.length != 2) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'circular_hey needs two ${who.key} pairs to pass first in each '
            'hands four, one on each side of the ring, but rows '
            '${band.topRow}-${band.bottomRow} have ${pairs.length}',
          ),
        );
      }
      for (final pair in pairs) {
        final pairAlong = _isAlong(formation, pair);
        if (pairAlong == null) {
          return Err(
            OpError(
              ErrorKind.unresolvableDancerSet,
              'circular_hey passes ${who.key} first, but ${pair.a} and '
              '${pair.b} stand diagonally, not facing along or across the set',
            ),
          );
        }
        if (along != null && along != pairAlong) {
          return Err(
            OpError(
              ErrorKind.unresolvableDancerSet,
              'circular_hey passes ${who.key} first, but some of those pairs '
              'stand along the set and others across it',
            ),
          );
        }
        along = pairAlong;
      }
    }
    return Ok(along ?? true);
  }

  /// `true` along the set, `false` across it, `null` diagonal.
  static bool? _isAlong(Formation formation, DancerPair pair) {
    final a = formation.stateOf(pair.a).position;
    final b = formation.stateOf(pair.b).position;
    if (a.col == b.col) return true;
    if (a.row == b.row) return false;
    return null;
  }

  /// The swap on one axis, for every hands four.
  static Formation _pass(Formation formation, {required bool along}) =>
      reflectBands(formation, rows: along, columns: !along);

  /// Checks a stated [who2] against the ring after the first pass.
  OpError? _checkWho2(Formation formation, bool firstAlong) {
    final second = who2;
    if (second == null || changes < 2) return null;
    if (second.isCrossHandsFour || second == WhoSet.everyone) {
      return OpError(
        ErrorKind.unsupportedParam,
        'circular_hey who2:${second.key} is deferred: only who chooses which '
        'hands four the ring is danced in',
      );
    }
    final afterFirst = _pass(formation, along: firstAlong);
    for (final band in handsFourBands(afterFirst)) {
      final pairs = resolveWhoPairs(
        afterFirst,
        second,
        topRow: band.topRow,
        bottomRow: band.bottomRow,
      );
      final onSecondAxis =
          pairs.length == 2 &&
          pairs.every((pair) => _isAlong(afterFirst, pair) == !firstAlong);
      if (!onSecondAxis) {
        return OpError(
          ErrorKind.whoMismatch,
          'circular_hey names ${second.key} to pass second, but after the '
          'first pass the dancers facing each other '
          '${firstAlong ? 'across' : 'along'} the set in rows '
          '${band.topRow}-${band.bottomRow} are not ${second.key}',
        );
      }
    }
    return null;
  }

  Result<bool, OpError> _validate(Formation formation) {
    if (changes < 1) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'circular_hey needs at least one change, not $changes',
        ),
      );
    }
    return _firstAlong(formation).flatMap((firstAlong) {
      final error = _checkWho2(formation, firstAlong);
      return error == null ? Ok(firstAlong) : Err(error);
    });
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_validate(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _validate(formation).map((firstAlong) {
        // Passes alternate first axis, other axis, first, other: by `net`
        // changes the first axis has been crossed ceil(net/2) times and the
        // other floor(net/2) times, and only the parity of each matters.
        final net = changes % 4;
        final first = net == 1 || net == 2;
        final second = net == 2 || net == 3;
        final moved = reflectBands(
          formation,
          rows: firstAlong ? first : second,
          columns: firstAlong ? second : first,
        );
        return changes == 1 ? moved : loosenBandFacing(moved);
      });

  @override
  bool operator ==(Object other) =>
      other is CircularHey &&
      other.who == who &&
      other.changes == changes &&
      other.shoulder == shoulder &&
      other.who2 == who2 &&
      other.where == where;

  @override
  int get hashCode => Object.hash(name, who, changes, shoulder, who2, where);

  @override
  String toString() => 'circular_hey(${who.key}, $changes)';
}
