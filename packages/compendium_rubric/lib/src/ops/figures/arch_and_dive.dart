part of '../operation.dart';

/// `arch_and_dive` — one couple raises an arch, the couple facing them ducks
/// under it, and the two couples trade places along the set.
///
/// **User-ruled:** the effect is the unconditional row swap of every hands
/// four, `(r0,c) ↔ (r1,c)` — the one place the prior verifier's reading
/// governs over ours. **Also user-ruled (2026-11-22):** nothing more is baked
/// in. Which couple arches (`who`) changes nobody's landing, and the figure
/// carries the dance's progression only when the record flags it (or the
/// Caller's Box bridge assumes it, by its ordinary last-figure rule), like any
/// other progression-eligible figure. Assuming the progression on the arch
/// itself was measured on the corpus before the ruling and did worse.
///
/// Facing is preserved: both couples walk forward through.
final class ArchAndDive extends Operation {
  const ArchAndDive({this.who = WhoSet.twos});

  /// The couple that makes the arch. Descriptive; no positional effect.
  final WhoSet who;

  @override
  String get name => 'arch_and_dive';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  bool get progressionEligible => true;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok<Formation, OpError>(reflectBands(formation, rows: true));

  @override
  bool operator ==(Object other) => other is ArchAndDive && other.who == who;

  @override
  int get hashCode => Object.hash(name, who);

  @override
  String toString() => 'arch_and_dive(${who.key})';
}
