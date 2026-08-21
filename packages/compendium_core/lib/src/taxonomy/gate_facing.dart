/// Set-relative facing + rotation vocabulary for the `gate` figure.
///
/// ## History: this module used to host a DERIVATION, which was WITHDRAWN (v22)
///
/// From taxonomy v15 (issue #294) to v21 this file exported `gateEndFacing` —
/// a pure function deriving a rotation-gate's ending facing from
/// `(startFacing, direction, turn)` — and was cited by
/// `docs/design/figure-taxonomy.md` as the first and only instance of the
/// "derived (computed-at-render) taxonomy value" convention.
///
/// It was wrong, and not repairably so:
///
///   * The renderer called it WITHOUT a `startFacing`, so every gate derived
///     from the module's nominal `gateStartFacing = 'in'`. A 1/2 gate always
///     rendered "to face out of the set" — including after a down-the-hall,
///     where dancers are facing down and a half turn ends facing **up**.
///   * Passing the real start facing would not have fixed it. The derivation's
///     only sound rules are RELATIVE (a full turn leaves the facing unchanged;
///     a half turn reverses it). Turning a relative rule into an absolute
///     cardinal requires knowing the orientation the dancers arrive in, which
///     depends on every preceding figure — i.e. choreography simulation, not a
///     context-free function. The module's own "CAVEAT" conceded a narrow
///     version of this for gate *sequences*; the real scope is any preceding
///     orientation-changing figure.
///
/// The ending facing is therefore **stored data** as of v22: the `gate.face`
/// param, filled by the ContraDB importer (whose `gate_face` states it
/// literally — `figure.js:841` renders `… "to face" <gate_face>`), left
/// `unspecified` by The Caller's Box (which never states one), and correctable
/// by the user. Nothing is derived, and nothing is fabricated.
///
/// What remains here is the plain vocabulary the merged move and the renderer
/// share.
library;

/// The four cardinal facings a gate can end in, relative to a longways contra
/// set: `up`/`down` the hall, and `in`/`out` across the set (toward / away from
/// the other line). These reuse the tokens already in the taxonomy's
/// `direction` vocabulary (see `ParamVocab.directions`) and are the same four
/// `swing.endFacing` uses.
///
/// Sourced from ContraDB `libfigure` `param.js` `_stringParamGateFace`:
/// `{up: "up the set", down: "down the set", in: "into the set",
/// out: "out of the set"}`.
const List<String> gateFacings = ['up', 'down', 'in', 'out', 'along'];

/// Valid `direction` tokens for a gate — The Caller's Box's rotation sense.
/// `mirror` (the two-couple gate, where the two roles rotate in opposite
/// senses) has no ContraDB equivalent and is why this cannot be
/// `ParamKind.spinDirection`.
const List<String> gateDirections = ['clockwise', 'counterclockwise', 'mirror'];
