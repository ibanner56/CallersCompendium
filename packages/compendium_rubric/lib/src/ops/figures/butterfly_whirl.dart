part of '../operation.dart';

/// `butterfly_whirl` — two dancers side by side, arms around each other's
/// backs, turn together about a point between them.
///
/// **User-ruled (2026-11-22): nobody changes place.** The figure almost always
/// follows a `star_promenade`, and the half promenade has already carried each
/// couple to its new side, so the whirl only turns the pair to face in. On the
/// Caller's Box corpus the alternative — the whirl swapping the pair — compiled
/// fewer dances (105 against 122), which is the evidence the ruling was asked
/// with. Facing is left as it was, like the other figures whose output facing
/// is flexible; facing is only ever a warning here.
///
/// **Also user-ruled:** a named pair must be standing side by side, and the
/// figure refuses otherwise. A pair that has just star-promenaded nearly
/// always is, so this rarely bites; it exists so the figure cannot "whirl" two
/// dancers who are not holding each other. An unstated `who` (the taxonomy's
/// `unspecified` default, which every ContraDB import carries) names nobody, so
/// there is nothing to check.
///
/// `direction` is the whirl's sense. It has no positional effect and is carried
/// for fidelity.
final class ButterflyWhirl extends Operation {
  const ButterflyWhirl({this.who, this.direction});

  /// The whirling pair, or `null` when the source does not say.
  final WhoSet? who;

  /// Clockwise or counterclockwise, or `null` when the source does not say.
  final SpinDirection? direction;

  @override
  String get name => 'butterfly_whirl';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  OpError? checkPreconditions(Formation formation) {
    final pairSet = who;
    if (pairSet == null) return null;
    final pairs = whoPairsInSet(formation, pairSet);
    final apart = firstNonAdjacentPair(formation, pairs);
    if (apart == null) return null;
    return OpError(
      ErrorKind.unresolvableDancerSet,
      'butterfly_whirl needs each ${pairSet.key} pair standing side by side, '
      'but ${apart.a} and ${apart.b} are diagonal',
    );
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok<Formation, OpError>(formation);

  @override
  bool operator ==(Object other) =>
      other is ButterflyWhirl &&
      other.who == who &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(name, who, direction);

  @override
  String toString() =>
      'butterfly_whirl(${who?.key ?? '-'}, ${direction?.key ?? '-'})';
}
