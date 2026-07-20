/// Deterministic ending-facing derivation for the TCB rotation-gate figure
/// (`rotation_gate`, issue #294).
///
/// The raw TCB line — e.g. `Partner gate counterclockwise 3/4` — does NOT state
/// the ending facing literally. Per the product decision, the resulting facing
/// is a **computed, verifiable value derived from the rotation geometry**, never
/// free-typed or fabricated. [gateEndFacing] is that derivation: a pure function
/// of `(startFacing, direction, turn)`. It is deliberately CONSERVATIVE — it
/// returns a facing ONLY for the cases that are unambiguous regardless of the
/// (still-unratified) clockwise-vs-counterclockwise cardinal-cycle convention,
/// and returns `null` otherwise so the renderer emits no facing clause rather
/// than inventing one.
library;

/// The four cardinal facings, relative to a longways contra set:
/// `up`/`down` the hall, and `in`/`out` across the set (toward / away from the
/// other line). These reuse the tokens already in the taxonomy's `direction`
/// vocabulary (see [ParamVocab.directions]).
const List<String> gateFacings = ['up', 'down', 'in', 'out'];

/// Start-orientation assumption for a gate: dancers begin facing **into the
/// set** (across, toward the other role). This is the ratifiable assumption
/// called out in issue #294; it is confirmed by the corpus contexts (improper
/// openers and post-`long lines` gates both start from an across-the-set
/// facing). Isolated here so a corrected assumption is a one-line change.
const String gateStartFacing = 'in';

const Map<String, String> _opposite = {
  'up': 'down',
  'down': 'up',
  'in': 'out',
  'out': 'in',
};

/// Valid `direction` tokens for a rotation-gate (matches the `rotation_gate`
/// MoveDef's `direction` choice domain).
const List<String> gateDirections = ['clockwise', 'counterclockwise', 'mirror'];

/// Derives the facing a dancer ends in after a rotation-gate, or `null` when it
/// cannot be determined WITHOUT fabricating a value.
///
/// Deterministic and defensive (never throws): unknown [direction], an
/// out-of-domain [startFacing], a non-positive or non-quarter [turn], or any
/// convention-dependent partial turn all yield `null`.
///
/// Resolved (convention-independent) cases:
///   * a whole number of full turns (360° · n) — facing is UNCHANGED;
///   * a half turn (180°, i.e. an odd number of half-turns) — facing is the
///     OPPOSITE of the start.
///
/// Unresolved (returns `null`, so no facing is fabricated):
///   * quarter / three-quarter turns (90° / 270°) for `clockwise` /
///     `counterclockwise` — the resulting cardinal depends on the set-geometry
///     cycle convention, which is not yet ratified (issue #294 open question);
///   * any `mirror` gate other than a full turn — the per-role rotation sense
///     differs, so a partial mirror gate has no single ending facing (and only
///     the full-turn mirror gate is attested in the corpus);
///   * non-quarter turn fractions (e.g. 1/8), which land on no cardinal facing.
String? gateEndFacing({
  required String direction,
  required num turn,
  String startFacing = gateStartFacing,
}) {
  if (!gateDirections.contains(direction)) return null;
  if (!_opposite.containsKey(startFacing)) return null;
  if (turn <= 0) return null;

  // Quarter-turn count. Reject anything that is not an exact quarter multiple
  // rather than rounding (a fabricated facing is worse than none).
  final quartersExact = turn * 4;
  if (quartersExact % 1 != 0) return null;
  final quarters = quartersExact.toInt();

  final mod = quarters % 4; // 0 = full, 2 = half, 1|3 = quarter/three-quarter.

  // A mirror gate is only resolvable at a full turn (the sole attested form).
  if (direction == 'mirror') {
    return mod == 0 ? startFacing : null;
  }

  switch (mod) {
    case 0:
      return startFacing; // full turn(s): back to the start orientation.
    case 2:
      return _opposite[startFacing]; // half turn: face the opposite way.
    default:
      // 90° / 270°: convention-dependent — do not fabricate.
      return null;
  }
}
