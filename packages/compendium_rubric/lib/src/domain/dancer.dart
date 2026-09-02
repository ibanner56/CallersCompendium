import 'package:meta/meta.dart';

import 'couple_number.dart';
import 'facing.dart';
import 'position.dart';
import 'role.dart';

/// Bit offset of the one-hot couple-id field in the dancer bitmask.
///
/// Bits 1..0 hold the role and bit 2 holds the number, so the couple-id
/// one-hot field starts at bit 3. See `docs/fundamentals.md` §5.
const int kCoupleIdShift = 3;

/// A dancer's **invariant** identity: their couple letter and their role.
///
/// Per `docs/fundamentals.md` §5 these two fields never change, which is
/// exactly what makes them a safe map key: a dancer's *number* flips at a
/// progression and their position changes constantly, but `(couple, role)`
/// follows one human around the hall for the whole dance.
@immutable
class DancerId {
  const DancerId(this.coupleIndex, this.role);

  /// Zero-based couple letter: 0 = A, 1 = B, 2 = C, …
  final int coupleIndex;

  final Role role;

  /// The couple letter (`A`, `B`, `C`, …) used in role notation.
  String get coupleLetter => String.fromCharCode(0x41 + coupleIndex);

  /// The one-hot bit value contributed by this dancer's couple.
  ///
  /// Ascending powers of two from the low end, so a couple's contribution is
  /// stable regardless of set size (A always 8, B 16, C 32, …).
  int get coupleBits => 1 << (coupleIndex + kCoupleIdShift);

  @override
  bool operator ==(Object other) =>
      other is DancerId &&
      other.coupleIndex == coupleIndex &&
      other.role == role;

  @override
  int get hashCode => Object.hash(coupleIndex, role);

  @override
  String toString() => '${role.label}-$coupleLetter';
}

/// Everything about a dancer that can change during a dance.
///
/// Held as the value half of the entity map on [Formation]; the key is the
/// invariant [DancerId]. Facing and number therefore travel with the dancer
/// automatically rather than having to be moved in lockstep with position.
@immutable
class DancerState {
  const DancerState({
    required this.position,
    required this.number,
    required this.facing,
    this.waitingOut = false,
  });

  final Position position;
  final CoupleNumber number;
  final Facing facing;

  /// Whether this dancer is standing out at an end of the set this round
  /// (`docs/fundamentals.md` §10.3).
  ///
  /// Held here — beside [facing], outside the encoded cell value — for two
  /// reasons. First, it is therefore excluded from success comparison for free
  /// (`docs/architecture.md` §3.5), exactly as facing is. Second, it is the
  /// *primary* signal for hands-four grouping: the couple-number and
  /// couple-orientation rules this replaced are only evaluable on a settled
  /// shape, and every state a figure actually sees is mid-dance.
  ///
  /// Per **dancer** rather than per couple so that the pair standing out at an
  /// end need not be partners — a real case (see §10.2.1).
  final bool waitingOut;

  int get row => position.row;
  int get col => position.col;

  DancerState copyWith({
    Position? position,
    CoupleNumber? number,
    Facing? facing,
    bool? waitingOut,
  }) => DancerState(
    position: position ?? this.position,
    number: number ?? this.number,
    facing: facing ?? this.facing,
    waitingOut: waitingOut ?? this.waitingOut,
  );

  /// This dancer moved to [newPosition], keeping number and facing.
  DancerState movedTo(Position newPosition) => copyWith(position: newPosition);

  /// This dancer turned 180° in place.
  DancerState reversed() => copyWith(facing: facing.reversed);

  @override
  bool operator ==(Object other) =>
      other is DancerState &&
      other.position == position &&
      other.number == number &&
      other.facing == facing &&
      other.waitingOut == waitingOut;

  @override
  int get hashCode => Object.hash(position, number, facing, waitingOut);

  @override
  String toString() =>
      '$position #${number.label} ${facing.label}${waitingOut ? ' (out)' : ''}';
}

/// Encodes a dancer into the decimal cell value stored in the matrix.
///
/// Layout (`docs/fundamentals.md` §5), read from the right:
/// `[ couple-id one-hot ][ number ][ role ]`.
///
/// Facing is deliberately absent — that is what makes `actual == expected`
/// cell-by-cell equality naturally exclude it (`docs/architecture.md` §3.5).
int encodeDancer(DancerId id, CoupleNumber number) =>
    id.coupleBits | (number.bit << 2) | id.role.bits;

/// Decodes a non-empty cell value back into its identity and number.
///
/// Returns `null` for the empty cell (`0`) or a value with no valid role field.
({DancerId id, CoupleNumber number})? decodeDancer(int value) {
  if (value == 0) return null;
  final role = Role.fromBits(value);
  if (role == null) return null;
  final coupleField = value >> kCoupleIdShift;
  // The couple-id field is one-hot; anything else is not a valid dancer.
  if (coupleField == 0 || (coupleField & (coupleField - 1)) != 0) return null;
  return (
    id: DancerId(coupleField.bitLength - 1, role),
    number: CoupleNumber.fromBits(value),
  );
}
