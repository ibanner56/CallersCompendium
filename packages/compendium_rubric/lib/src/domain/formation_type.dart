/// The named starting formations a dance can declare.
///
/// See `docs/fundamentals.md` §9. Becket CW and Becket CCW share a starting
/// matrix and differ only in progression sense (§10.6), but are modelled as
/// two formations because the direction is carried by the formation rather
/// than by the success criterion (`docs/architecture.md` §3.4).
library;

import 'couple_number.dart';

enum FormationType {
  dupleImproper(key: 'duple_improper', label: 'Duple Improper'),
  becketCw(key: 'becket_cw', label: 'Becket CW'),
  becketCcw(key: 'becket_ccw', label: 'Becket CCW');

  const FormationType({required this.key, required this.label});

  /// The snake_case key used in dance JSON.
  final String key;

  /// Human-readable name.
  final String label;

  /// Whether couples in this formation share a **column** within their hands
  /// four (Becket) rather than a **row** (Duple Improper).
  ///
  /// This no longer selects the hands-four grouping rule — that is derived from
  /// waiting-out state and is formation-independent (`docs/fundamentals.md`
  /// §10.3). What still differs by formation is how a couple is oriented
  /// *within* a band (§10.3.1) and which axis a progression travels along
  /// (§10.6), and this is the discriminator for both.
  bool get couplesShareColumn => this == becketCw || this == becketCcw;

  /// The number a couple takes when it normalizes at the **top** row of the
  /// set; the bottom row takes the complement.
  ///
  /// **Why this is assigned rather than flipped.** A number identifies which
  /// side of the progression a couple is on — in Duple Improper, which row of
  /// its hands four; in Becket, which **line** (`docs/fundamentals.md` §10.6:
  /// *"c4 = the 1s line, c0 = the 2s line"*). A couple sitting in an end row is
  /// **in transit between lines**, and its number must match the line it is
  /// about to re-enter. Deriving that number from the end it reached — rather
  /// than inverting whatever the dancers happened to arrive holding — makes the
  /// step a true normalization: idempotent, and self-repairing if the incoming
  /// numbers were inconsistent.
  ///
  /// The sense is formation-dispatched because **CCW is the mirror**:
  ///
  /// | Formation | Runs off the top | Re-enters | Top-end number |
  /// |---|---|---|---|
  /// | Duple Improper | the 2s (they travel up) | as 1s | **#1** |
  /// | Becket CW | c0, the 2s line | c4, the 1s line | **#1** |
  /// | Becket CCW | c4, the 1s line | c0, the 2s line | **#2** |
  ///
  /// Verified against §10.5 and all four of §10.6's CW/CCW × single/double
  /// reference states.
  CoupleNumber get topEndNumber =>
      this == becketCcw ? CoupleNumber.two : CoupleNumber.one;

  /// The number a couple takes when it normalizes at the **bottom** row.
  CoupleNumber get bottomEndNumber => topEndNumber.flipped;

  /// Resolves a JSON formation key, accepting the label spellings that appear
  /// in real dance records ("Becket CW", "dupleImproper", ...).
  static FormationType? fromKey(String raw) {
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    for (final value in FormationType.values) {
      if (normalized == value.key) return value;
    }
    return switch (normalized) {
      'dupleimproper' || 'duple_minor_improper' => FormationType.dupleImproper,
      'becket' || 'becketcw' || 'becket_clockwise' => FormationType.becketCw,
      'becketccw' ||
      'becket_counterclockwise' ||
      'becket_ccw' => FormationType.becketCcw,
      _ => null,
    };
  }
}
