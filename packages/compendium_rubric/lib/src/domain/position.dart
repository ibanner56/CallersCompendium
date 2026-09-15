import 'package:meta/meta.dart';

/// The fixed column count of the matrix.
///
/// See `docs/fundamentals.md` §4: only `c0` and `c4` hold dancers at the
/// standard start, but the middle columns `c1`–`c3` are always retained — the
/// line of four (§8.1) occupies `c0`,`c1`,`c3`,`c4` with `c2` empty.
const int kColumnCount = 5;

/// The number of matrix rows contributed by each hands four.
const int kRowsPerHandsFour = 2;

/// A cell coordinate in the matrix.
@immutable
class Position {
  const Position(this.row, this.col);

  final int row;
  final int col;

  /// The westmost column (`c0`).
  static const int westColumn = 0;

  /// The eastmost column (`c4`).
  static const int eastColumn = kColumnCount - 1;

  /// Whether this position sits in one of the two side columns.
  bool get isSideColumn => col == westColumn || col == eastColumn;

  @override
  bool operator ==(Object other) =>
      other is Position && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '(r$row,c$col)';
}
