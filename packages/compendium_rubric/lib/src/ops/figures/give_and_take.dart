part of '../operation.dart';

/// A resolved `give_and_take` pairing: who stays and who crosses.
typedef _TakePair = ({DancerId taker, DancerId taken});

/// `give_and_take` — the taker draws the taken across to their side, and the
/// two end as a column couple there.
///
/// The one genuinely bespoke permutation in the taxonomy: neither a swap nor a
/// reflection, but a turn of the pair from **across** the set to **along** it.
/// Given a taker `T` at `(r, cT)` and the taken `K` at `(r, cK)`:
///
/// - `K` crosses into the taker's column, staying in the shared row → `(r, cT)`
/// - `T` keeps their column and slides to the now-free row → `(r̄, cT)`
///
/// The taker's column therefore holds the taken in the taker's original row and
/// the taker in the other one, which is exactly a vertical couple on the
/// taker's side.
///
/// The **across** precondition is load-bearing rather than defensive: the rule
/// reads `cT` and `cK` as distinct columns of a shared row, and a pair standing
/// any other way has no free row for the taker to slide into.
final class GiveAndTake extends Operation {
  const GiveAndTake({
    this.who = WhoSet.role1s,
    this.whom = WhoSet.partners,
    this.give = true,
  });

  /// **The taker** — the dancer who stays on their own side. Restricted
  /// upstream to `role1s` / `role2s`.
  final WhoSet who;

  /// **The taken** — the relationship that crosses to the taker's column.
  final WhoSet whom;

  /// `false` is the "take only" variant. Beat-shaping and styling; no
  /// end-position effect.
  final bool give;

  @override
  String get name => 'give_and_take';

  @override
  Iterable<WhoSet?> get dancerSets => [who, whom];

  /// Splits each `whom` pair into a taker and a taken.
  ///
  /// Exactly one member must satisfy `who`. Neither qualifying, or both,
  /// leaves the figure with no way to say which side the couple ends on.
  Result<List<_TakePair>, OpError> _assignRoles(Formation formation) {
    final assigned = <_TakePair>[];
    for (final pair in whoPairsInSet(formation, whom)) {
      final aIsTaker = whoIncludes(formation, pair.a, who);
      final bIsTaker = whoIncludes(formation, pair.b, who);
      if (aIsTaker == bIsTaker) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'give_and_take needs exactly one ${who.key} in each ${whom.key} '
            'pair, but ${pair.a} and ${pair.b} '
            '${aIsTaker ? 'both qualify' : 'neither qualifies'}',
          ),
        );
      }
      assigned.add(
        aIsTaker
            ? (taker: pair.a, taken: pair.b)
            : (taker: pair.b, taken: pair.a),
      );
    }
    return Ok(assigned);
  }

  /// Rejects any pairing that is not standing across the set.
  OpError? _requireAcross(Formation formation, List<_TakePair> pairs) {
    for (final pair in pairs) {
      final taker = formation.stateOf(pair.taker);
      final taken = formation.stateOf(pair.taken);
      if (taker.row == taken.row && taker.col != taken.col) continue;
      return OpError(
        ErrorKind.unresolvableDancerSet,
        'give_and_take needs the taker and taken across the set - a shared '
        'row, different columns - but ${pair.taker} is at ${taker.position} '
        'and ${pair.taken} is at ${taken.position}',
      );
    }
    return null;
  }

  @override
  OpError? checkPreconditions(Formation formation) => _assignRoles(
    formation,
  ).fold((pairs) => _requireAcross(formation, pairs), (error) => error);

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _assignRoles(formation).map((pairs) {
        final changes = <DancerId, DancerState>{};
        for (final pair in pairs) {
          final taker = formation.stateOf(pair.taker);
          final taken = formation.stateOf(pair.taken);
          final band = handsFourBandContaining(formation, taker.row);
          if (band == null) continue;
          final freeRow = taker.row == band.topRow
              ? band.bottomRow
              : band.topRow;

          changes[pair.taken] = taken.movedTo(Position(taker.row, taker.col));
          changes[pair.taker] = taker.movedTo(Position(freeRow, taker.col));
        }
        return formation.withUpdates(changes);
      });

  @override
  bool operator ==(Object other) =>
      other is GiveAndTake &&
      other.who == who &&
      other.whom == whom &&
      other.give == give;

  @override
  int get hashCode => Object.hash(name, who, whom, give);

  @override
  String toString() => 'give_and_take(${who.key}, ${whom.key}, give: $give)';
}
