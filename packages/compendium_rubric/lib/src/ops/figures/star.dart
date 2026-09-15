part of '../operation.dart';

/// `star` — the four dancers rotate around the hands four with the stated hand
/// in the centre (`docs/taxonomy.md`).
///
/// Mechanically identical to [Circle]; only the direction token differs.
/// **`hand: right` turns clockwise (circle left) and `hand: left` turns
/// counter-clockwise (circle right).** `places: 4` is a full turn, and so the
/// identity — which is exactly what The Baby Rose's closing star is.
final class Star extends Operation {
  const Star({required this.hand, required this.places, this.grip});

  /// Which hand is in the centre. This sets the rotation direction.
  final Hand hand;

  /// Position-steps around the ring. Effective rotation is `places mod 4`.
  final int places;

  /// Handhold style (`wrist_grip` / `hands_across`). No effect on end state.
  final String? grip;

  @override
  String get name => 'star';

  /// A left hand in the centre turns the ring counter-clockwise.
  int get _ringSign => hand == Hand.left ? 1 : -1;

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final steps = _ringSign * places;
    final rotated = rotateHandsFourRings(formation, steps: steps);
    return Ok(steps % 4 == 0 ? rotated : loosenBandFacing(rotated));
  }

  @override
  bool operator ==(Object other) =>
      other is Star &&
      other.hand == hand &&
      other.places == places &&
      other.grip == grip;

  @override
  int get hashCode => Object.hash(name, hand, places, grip);

  @override
  String toString() => 'star(${hand.key}, $places)';
}
