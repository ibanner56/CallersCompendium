import '../geometry/geometry.dart';
import 'couple_number.dart';
import 'dancer.dart';
import 'facing.dart';
import 'formation.dart';
import 'formation_type.dart';
import 'position.dart';
import 'role.dart';

/// Builds the starting [Formation] for [type] with [handsFour] hands four.
///
/// Every start is built couple-by-couple from the normalization rule
/// (`docs/fundamentals.md` §7–§8) rather than from a transcribed matrix, so
/// the geometry has exactly one definition.
Formation startingFormation(FormationType type, {required int handsFour}) {
  if (handsFour < 1) {
    throw ArgumentError.value(handsFour, 'handsFour', 'must be at least 1');
  }
  return switch (type) {
    FormationType.dupleImproper => _dupleImproper(handsFour),
    FormationType.becketCw ||
    FormationType.becketCcw => _becket(type, handsFour),
  };
}

/// Duple Improper: 1s face down and normalize (Lark c4, Robin c0); 2s face up
/// and normalize (Lark c0, Robin c4).
///
/// Hands four `k` holds couple `2k` as the #1 couple on row `2k` and couple
/// `2k + 1` as the #2 couple on row `2k + 1`.
Formation _dupleImproper(int handsFour) {
  final dancers = <DancerId, DancerState>{};
  for (var block = 0; block < handsFour; block++) {
    _placeAlongHall(
      dancers,
      coupleIndex: block * 2,
      number: CoupleNumber.one,
      row: block * kRowsPerHandsFour,
      facing: Facing.down,
    );
    _placeAlongHall(
      dancers,
      coupleIndex: block * 2 + 1,
      number: CoupleNumber.two,
      row: block * kRowsPerHandsFour + 1,
      facing: Facing.up,
    );
  }
  return Formation(
    type: FormationType.dupleImproper,
    rowCount: handsFour * kRowsPerHandsFour,
    dancers: dancers,
  );
}

/// Becket: DI circled left one place. Partners share a column, both lines
/// face across/in; c4 is the 1s line and c0 is the 2s line.
///
/// Hands four `k` holds couple `2k` (#1) stacked in c4 and couple `2k + 1`
/// (#2) stacked in c0, both spanning rows `2k` and `2k + 1`.
Formation _becket(FormationType type, int handsFour) {
  final dancers = <DancerId, DancerState>{};
  for (var block = 0; block < handsFour; block++) {
    final topRow = block * kRowsPerHandsFour;
    _placeAcross(
      dancers,
      coupleIndex: block * 2 + 1,
      number: CoupleNumber.two,
      col: Position.westColumn,
      topRow: topRow,
      facing: Facing.acrossEast,
    );
    _placeAcross(
      dancers,
      coupleIndex: block * 2,
      number: CoupleNumber.one,
      col: Position.eastColumn,
      topRow: topRow,
      facing: Facing.acrossWest,
    );
  }
  return Formation(
    type: type,
    rowCount: handsFour * kRowsPerHandsFour,
    dancers: dancers,
  );
}

/// Places a couple standing along a row, normalized for an up/down [facing].
void _placeAlongHall(
  Map<DancerId, DancerState> dancers, {
  required int coupleIndex,
  required CoupleNumber number,
  required int row,
  required Facing facing,
}) {
  final placement = normalizeAlongHall(row: row, facing: facing);
  _place(dancers, coupleIndex, number, facing, placement);
}

/// Places a couple stacked in a column, normalized for an across [facing].
void _placeAcross(
  Map<DancerId, DancerState> dancers, {
  required int coupleIndex,
  required CoupleNumber number,
  required int col,
  required int topRow,
  required Facing facing,
}) {
  final placement = normalizeAcross(col: col, topRow: topRow, facing: facing);
  _place(dancers, coupleIndex, number, facing, placement);
}

void _place(
  Map<DancerId, DancerState> dancers,
  int coupleIndex,
  CoupleNumber number,
  Facing facing,
  CouplePlacement placement,
) {
  dancers[DancerId(coupleIndex, Role.lark)] = DancerState(
    position: placement.lark,
    number: number,
    facing: facing,
  );
  dancers[DancerId(coupleIndex, Role.robin)] = DancerState(
    position: placement.robin,
    number: number,
    facing: facing,
  );
}
