/// A couple's **number** within its hands four — the *mutable* half of a
/// dancer's identity.
///
/// See `docs/fundamentals.md` §5: number occupies bit 2 of the per-dancer
/// bitmask, and §10: a couple's number flips when it reaches an end of the set
/// and turns around at a progression.
enum CoupleNumber {
  one(bit: 0, label: '1'),
  two(bit: 1, label: '2');

  const CoupleNumber({required this.bit, required this.label});

  /// The value stored in bit 2 of the dancer bitmask (0 = #1, 1 = #2).
  final int bit;

  /// Digit used by the role-notation renderer (`L1-A`).
  final String label;

  /// The other number — the flip applied to an end couple at a progression.
  CoupleNumber get flipped =>
      this == CoupleNumber.one ? CoupleNumber.two : CoupleNumber.one;

  /// Decodes the number field of a dancer bitmask.
  static CoupleNumber fromBits(int value) =>
      (value >> 2) & 0x1 == 0 ? CoupleNumber.one : CoupleNumber.two;
}
