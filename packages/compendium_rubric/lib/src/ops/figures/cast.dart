part of '../operation.dart';

/// `cast` — dancers turn out, away from the middle of the set, and travel
/// around the outside to a new place (`docs/taxonomy.md`).
///
/// **User-ruled (2026-11-23):** the casting dancers move [places] places up or
/// down the set, and each dancer they pass steps one place the other way.
/// Only a cast of **one** place is built: on the grid the caster and the
/// dancer beside it in its column, inside its own hands four, trade rows.
/// "Cast off" is a cast down one place, the importer's reading
/// (`compendium_core`). A cast of two or more places crosses into the next
/// hands four, and in an ordinary duple set every ones couple casting at once
/// would pass the same dancers, so it is deferred.
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
/// - The cast is danced in the active hands fours only, like every other
///   figure; a couple standing out at an end does not cast and is not passed.
/// - A caster with nobody beside it in its hands four in the cast's direction,
///   or whose neighbour there is casting too (every `ones` cast in Becket,
///   where the ones share a column), is refused
///   ([ErrorKind.unresolvableDancerSet]) rather than left to wait.
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

  /// The caster and the dancer it passes, for every caster in every active
  /// hands four.
  Result<List<DancerPair>, OpError> _plan(Formation formation) {
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
    if (count == null) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast ${dir.key} with an unstated number of places is deferred',
        ),
      );
    }
    if (count != 1) {
      return Err(
        OpError(
          ErrorKind.unsupportedParam,
          'cast ${dir.key} $count places is deferred: only a cast of one '
          'place, which stays inside its hands four, is built',
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
    if (!_passerMemberships.contains(casters)) {
      return Err(
        OpError(
          ErrorKind.unresolvableDancerSet,
          'cast needs dancers named by membership (ones, twos, role1s, '
          'role2s); ${casters.key} names pairs, not casters',
        ),
      );
    }

    return _onePlacePasses(
      formation,
      casters,
      step: dir == CastDirection.down ? 1 : -1,
      figure: 'cast',
      label: 'cast ${dir.key} 1',
      passer: 'cast around',
    );
  }

  @override
  OpError? checkPreconditions(Formation formation) =>
      switch (_plan(formation)) {
        Ok() => null,
        Err(:final error) => error,
      };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _plan(formation).map(
        (pairs) => swapPairs(
          formation,
          pairs,
          facing: (before, after, other) => Facing.flexible,
        ),
      );

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

/// The membership sets that name the dancers who move past others one place
/// along the set: [Cast] and a [HallFigure] led by part of the set.
const _passerMemberships = {
  WhoSet.ones,
  WhoSet.twos,
  WhoSet.role1s,
  WhoSet.role2s,
};

/// Each dancer of [members] in every active hands four, paired with the dancer
/// one row [step] away in its column inside that hands four: the dancer it
/// passes, who steps one place the other way.
///
/// Shared by [Cast] and by a [HallFigure] led by part of the set, which move
/// the set the same way *(user-ruled 2026-11-23)*. Only the active hands fours
/// are read: a couple standing out at an end is outside every one of them, and
/// no figure moves it (`end_normalization.dart`). A mover with nobody beside it
/// in that direction, or whose neighbour there is moving too, is refused
/// ([ErrorKind.unresolvableDancerSet]); so is a plan that moves nobody.
///
/// [figure] names the figure in the empty-plan message, [label] the move in the
/// others, and [passer] what the movers do to the dancer they pass.
Result<List<DancerPair>, OpError> _onePlacePasses(
  Formation formation,
  WhoSet members, {
  required int step,
  required String figure,
  required String label,
  required String passer,
}) {
  final plan = <DancerPair>[];
  for (final band in handsFourBands(formation)) {
    final inBand = [
      ...formation.dancersInRow(band.topRow),
      ...formation.dancersInRow(band.bottomRow),
    ];
    final movers = {
      for (final id in inBand)
        if (whoIncludes(formation, id, members)) id,
    };
    for (final id in movers) {
      final at = formation.stateOf(id).position;
      final row = at.row + step;
      final other = row == band.topRow || row == band.bottomRow
          ? formation.dancerAt(Position(row, at.col))
          : null;
      if (other == null) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$label: $id has nobody to $passer in its hands four (rows '
            '${band.topRow}-${band.bottomRow})',
          ),
        );
      }
      if (movers.contains(other)) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            '$label: $id would pass $other, who is a ${members.key} '
            'moving too',
          ),
        );
      }
      plan.add((a: id, b: other));
    }
  }
  if (plan.isEmpty) {
    return Err(
      OpError(
        ErrorKind.unresolvableDancerSet,
        '$figure: no ${members.key} stands in an active hands four',
      ),
    );
  }
  return Ok(plan);
}
