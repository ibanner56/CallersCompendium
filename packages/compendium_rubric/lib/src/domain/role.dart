/// Dancer role — the invariant half of a dancer's identity.
///
/// See `docs/fundamentals.md` §5: role occupies bits 1..0 of the per-dancer
/// bitmask (`01` = Lark, `10` = Robin; `00` only for an empty cell).
enum Role {
  lark(bits: 0x1, label: 'L'),
  robin(bits: 0x2, label: 'R');

  const Role({required this.bits, required this.label});

  /// The two-bit field stored in bits 1..0 of the dancer bitmask.
  final int bits;

  /// Single-character tag used by the role-notation renderer (`L1-A`).
  final String label;

  /// Decodes the role field of a non-empty dancer bitmask.
  ///
  /// Returns `null` when [value] carries no valid role field, which includes
  /// the empty cell (`0`).
  static Role? fromBits(int value) => switch (value & 0x3) {
    0x1 => Role.lark,
    0x2 => Role.robin,
    _ => null,
  };
}
