part of '../operation.dart';

/// `cast` — dancers turn out, away from the middle of the set, and travel
/// around the outside to a new place (`docs/taxonomy.md`).
///
/// **User-ruled (2026-11-23):** the casting dancers move [places] places up or
/// down the set, and each dancer they pass steps one place the other way. On
/// the grid that is a rotation within the caster's own column: a dancer in row
/// `r` casting down `N` lands in row `r + N`, and the dancers in rows
/// `r + 1 … r + N` of that column each move up one row. "Cast off" is a cast
/// down one place, the importer's reading (`compendium_core`).
///
/// Everything the ruling leaves open is refused rather than guessed
/// ([ErrorKind.unsupportedParam]): a cast `left` or `right` (casting back),
/// one with no direction, no number of places, no casters named, or a stated
/// destination.
///
/// `who` names the casters by membership (`ones`, `twos`, `role1s`,
/// `role2s`). A pair relation such as `partners` names no casters and is
/// refused. `whom`, the dancers cast around, is descriptive: the dancers in
/// the caster's path are the ones passed.
///
/// Two more calls are the agent's, not ruled:
///
/// - A caster whose path leaves the set, or meets an empty place, waits out,
///   as dancers at an end of the set do. If no caster can move at all, the
///   figure is refused ([ErrorKind.unresolvableDancerSet]).
/// - Two casters that would pass the same dancer, or a caster that would pass
///   another caster, are refused rather than ordered.
///
/// Everyone who moved ends with flexible facing: casting turns the casters
/// out and around, and the dancers stepping along turn to follow.
final class Cast extends Operation {
  const Cast({
    this.who,
    this.direction,
    this.places,
    this.whom,
    this.destination,
  });

  /// The casting dancers. `null` when the record does not say.
  final WhoSet? who;

  /// The way they cast. `null` when the record does not say.
  final CastDirection? direction;

  /// How many places they move. `null` when the record does not say.
  final int? places;

  /// The dancers cast around. Descriptive.
  final WhoSet? whom;

  /// A stated endpoint (`compendium_core` `castDestinations`). Deferred.
  final String? destination;

  @override
  String get name => 'cast';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  static const _memberships = {
    WhoSet.ones,
    WhoSet.twos,
    WhoSet.role1s,
    WhoSet.role2s,
  };

  /// The moves this cast makes: for each caster that can cast, the column it
  /// casts in, the row it starts from, and the rows it passes.
  Result<
    List<({DancerId caster, int col, int from, List<int> passed})>,
    OpError
  >
  _plan(Formation formation) {
    final casters = who;
    final dir = direction;
    final count = places;
    if (casters == null) {
      return const Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast with no casters named is deferred',
        ),
      );
    }
    if (dir == null ||
        dir == CastDirection.left ||
        dir == CastDirection.right) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast ${dir?.key ?? 'with no direction'} is deferred; only up and '
          'down are built',
        ),
      );
    }
    if (count == null || count < 1) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast ${dir.key} with ${count ?? 'an unstated number of'} places is '
          'deferred',
        ),
      );
    }
    if (destination != null) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast to a stated destination ($destination) is deferred',
        ),
      );
    }
    if (!_memberships.contains(casters)) {
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'cast needs dancers named by membership (ones, twos, role1s, '
          'role2s); ${casters.key} names pairs, not casters',
        ),
      );
    }

    final step = dir == CastDirection.down ? 1 : -1;
    final casterIds = {
      for (final id in formation.dancers.keys)
        if (whoIncludes(formation, id, casters)) id,
    };
    final plan = <({DancerId caster, int col, int from, List<int> passed})>[];
    final passedIds = <DancerId>{};
    for (final id in casterIds) {
      final at = formation.stateOf(id).position;
      final rows = [for (var k = 1; k <= count; k++) at.row + step * k];
      final passed = <DancerId>[];
      for (final row in rows) {
        if (row < 0 || row > formation.lastRow) break;
        final other = formation.dancerAt(Position(row, at.col));
        if (other == null) break;
        passed.add(other);
      }
      // Off the end of the set, or into an empty place: this caster waits.
      if (passed.length < count) continue;
      for (final other in passed) {
        if (casterIds.contains(other) || !passedIds.add(other)) {
          return Err(
            OpError(
              ErrorKind.unresolvableDancerSet,
              'cast ${dir.key} $count would have $id pass $other, who is '
              '${casterIds.contains(other) ? 'casting too' : 'already being passed by another caster'}; '
              'overlapping casts are not ordered',
            ),
          );
        }
      }
      plan.add((caster: id, col: at.col, from: at.row, passed: rows));
    }
    if (plan.isEmpty) {
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'cast ${dir.key} $count: no ${casters.key} has $count dancers to '
          'cast around',
        ),
      );
    }
    return Ok(plan);
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_plan(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _plan(formation).map((plan) {
        final changes = <DancerId, DancerState>{};
        for (final move in plan) {
          final step = move.passed.last > move.from ? -1 : 1;
          for (final row in move.passed) {
            final id = formation.dancerAt(Position(row, move.col))!;
            changes[id] = formation
                .stateOf(id)
                .copyWith(
                  position: Position(row + step, move.col),
                  facing: Facing.flexible,
                );
          }
          changes[move.caster] = formation
              .stateOf(move.caster)
              .copyWith(
                position: Position(move.passed.last, move.col),
                facing: Facing.flexible,
              );
        }
        return formation.withUpdates(changes);
      });

  @override
  bool operator ==(Object other) =>
      other is Cast &&
      other.who == who &&
      other.direction == direction &&
      other.places == places &&
      other.whom == whom &&
      other.destination == destination;

  @override
  int get hashCode =>
      Object.hash(name, who, direction, places, whom, destination);

  @override
  String toString() =>
      'cast(${who?.key ?? '?'}, ${direction?.key ?? '?'}, ${places ?? '?'})';
}
