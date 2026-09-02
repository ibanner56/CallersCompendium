part of '../operation.dart';

/// `circle` — a clockwise or counter-clockwise rotation of the four dancers in
/// each hands four (`docs/taxonomy.md`).
///
/// The rotation runs over the corner ring `O = [(topRow,c0), (topRow,c4),
/// (botRow,c4), (botRow,c0)]` with `p = places mod 4`, so `places: 4` is a full
/// turn and therefore the identity.
///
/// **`turn: left` is clockwise and `turn: right` is counter-clockwise.** This
/// is the taxonomy's convention and it is the reverse of the naive reading.
final class Circle extends Operation {
  const Circle({
    required this.turn,
    required this.places,
    this.singleFile = false,
  });

  /// Which way the ring turns. See [CircleDirection] — `left` is clockwise.
  final CircleDirection turn;

  /// Position-steps around the ring. Effective rotation is `places mod 4`.
  final int places;

  /// Whether the dancers circulate single-file rather than hand-in-hand.
  ///
  /// Styling only: the ring positions and the rotation rule are unchanged, so
  /// this never affects the end state.
  final bool singleFile;

  @override
  String get name => 'circle';

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final steps = turn.ringSign * places;
    final rotated = rotateHandsFourRings(formation, steps: steps);
    // A full turn is the identity (taxonomy: `places mod 4`), and an identity
    // leaves nobody anywhere new, so it leaves no facing to resolve either.
    return Ok(steps % 4 == 0 ? rotated : loosenBandFacing(rotated));
  }

  @override
  bool operator ==(Object other) =>
      other is Circle &&
      other.turn == turn &&
      other.places == places &&
      other.singleFile == singleFile;

  @override
  int get hashCode => Object.hash(name, turn, places, singleFile);

  @override
  String toString() => 'circle(${turn.key}, $places)';
}
