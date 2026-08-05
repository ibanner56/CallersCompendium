/// Normalization for user-chosen ARGB colours that reach the app from
/// untrusted or long-lived storage.
library;

/// Coerces [raw] into a safe, fully opaque 32-bit ARGB int, or `null` when it
/// carries no usable colour.
///
/// Applied wherever a stored or imported colour is read (tag colours, #786),
/// because such a value is attacker-controlled the moment it can arrive in a
/// shared archive and then drive a painted UI element. The rules mirror
/// `formationColorOverridesFromStored` in the app package (issue #367), which
/// hardens the equivalent settings-backed payload:
///
/// - Anything that is not a number — including `null` and a missing value —
///   yields `null`, the "no colour assigned" state.
/// - Non-finite (`NaN`, `±Infinity`) and fractional values yield `null`; a
///   colour is an integer, and `toInt()` on a non-finite double throws.
/// - Values outside the 32-bit range `0x00000000..0xFFFFFFFF` yield `null`
///   rather than being wrapped or truncated, so an out-of-range value cannot
///   silently become an unrelated in-range colour.
/// - An accepted colour is forced fully opaque (`| 0xFF000000`), so a stored
///   zero- or low-alpha value can never render an invisible chip.
///
/// Degrading to `null` is deliberate rather than throwing: the colour is
/// decoration, and the name beside it is the meaningful data. A malformed
/// colour must cost the user its tint, never the tag.
int? normalizeArgb(Object? raw) {
  if (raw is! num) return null;
  if (raw is double && (!raw.isFinite || raw != raw.roundToDouble())) {
    return null;
  }
  final argb = raw.toInt();
  if (argb < 0 || argb > 0xFFFFFFFF) return null;
  return argb | 0xFF000000;
}
