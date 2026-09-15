import '../domain/couple_number.dart';
import '../domain/dancer.dart';
import '../domain/facing.dart';
import '../domain/formation.dart';
import '../domain/formation_type.dart';
import '../domain/position.dart';
import '../domain/role.dart';

/// Thrown when a role-notation string cannot be parsed.
class RolesNotationFormatException implements Exception {
  RolesNotationFormatException(this.message);

  final String message;

  @override
  String toString() => 'RolesNotationFormatException: $message';
}

final RegExp _tokenPattern = RegExp(r'^([LR])([12])-([A-Z])$');

/// Parses the role notation used by `docs/` and the golden fixtures back into
/// a [Formation] — the inverse of [Formation.toRolesNotation].
///
/// Each row is one string of whitespace-separated cells: `.` for an empty cell
/// and `L1-A` / `R2-D` for a dancer. Rows may use `.` runs of any spacing, so
/// both `"R1-A . . . L1-A"` and `"R1-B .  .  . L1-B"` parse.
///
/// [type] is required rather than defaulted because hands-four grouping is
/// formation-dispatched (see `handsFourOffset`): silently guessing a formation
/// here would silently pick a grouping rule.
///
/// Role notation carries no facing (facing is deliberately outside the encoded
/// cell value, `docs/fundamentals.md` §5), so every dancer is given
/// [defaultFacing]. That default is [Facing.flexible] because "unknown" is the
/// honest value — it must not be mistaken for an asserted direction.
Formation parseRolesNotation(
  List<String> rows, {
  required FormationType type,
  Facing defaultFacing = Facing.flexible,
}) {
  if (rows.isEmpty) {
    throw RolesNotationFormatException('Notation has no rows');
  }
  final dancers = <DancerId, DancerState>{};
  for (var row = 0; row < rows.length; row++) {
    final cells = rows[row].trim().split(RegExp(r'\s+'));
    if (cells.length != kColumnCount) {
      throw RolesNotationFormatException(
        'Row $row has ${cells.length} cells, expected $kColumnCount: '
        '"${rows[row]}"',
      );
    }
    for (var col = 0; col < cells.length; col++) {
      final cell = cells[col];
      if (cell == '.') continue;
      final match = _tokenPattern.firstMatch(cell);
      if (match == null) {
        throw RolesNotationFormatException(
          'Unrecognized cell "$cell" at row $row, column $col',
        );
      }
      final id = DancerId(
        match.group(3)!.codeUnitAt(0) - 0x41,
        match.group(1)! == 'L' ? Role.lark : Role.robin,
      );
      if (dancers.containsKey(id)) {
        throw RolesNotationFormatException('Duplicate dancer $id');
      }
      dancers[id] = DancerState(
        position: Position(row, col),
        number: match.group(2)! == '1' ? CoupleNumber.one : CoupleNumber.two,
        facing: defaultFacing,
      );
    }
  }
  return Formation(type: type, rowCount: rows.length, dancers: dancers);
}
