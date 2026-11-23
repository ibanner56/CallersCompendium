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
/// default (`across`) even where neighbours stand along the set. `shoulder`,
/// `who2` and `where` are carried for fidelity and move nobody.
///
/// Facing is kept, as `square_through` keeps it.
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

  /// The pairs that pass second, when the record names them. Descriptive.
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
        final a = formation.stateOf(pair.a).position;
        final b = formation.stateOf(pair.b).position;
        final bool pairAlong;
        if (a.col == b.col) {
          pairAlong = true;
        } else if (a.row == b.row) {
          pairAlong = false;
        } else {
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

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_firstAlong(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _firstAlong(formation).map((firstAlong) {
        // Passes alternate first axis, other axis, first, other: by `net`
        // changes the first axis has been crossed ceil(net/2) times and the
        // other floor(net/2) times, and only the parity of each matters.
        final net = changes % 4;
        final first = net == 1 || net == 2;
        final second = net == 2 || net == 3;
        return reflectBands(
          formation,
          rows: firstAlong ? first : second,
          columns: firstAlong ? second : first,
        );
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
