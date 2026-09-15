import 'package:meta/meta.dart';

import 'dancer.dart';
import 'formation_type.dart';
import 'position.dart';

/// Thrown when a [Formation]'s entity map cannot be projected onto a valid
/// matrix.
///
/// The entity-primary representation (`docs/architecture.md` §6, D2/D3) buys
/// automatic facing/number transport at the cost of losing the structural
/// guarantee that two dancers cannot share a cell. Projection therefore
/// re-imposes that guarantee explicitly, which surfaces a buggy figure loudly
/// at the moment it produces an impossible state rather than silently
/// corrupting the comparison downstream.
class FormationProjectionError extends StateError {
  FormationProjectionError(super.message);
}

/// An immutable dance state: every dancer's identity, position, number, and
/// facing, plus the fixed height of the matrix they occupy.
///
/// **Entity-primary.** The authoritative store is `DancerId -> DancerState`;
/// the matrix is a *projection* computed on demand ([toMatrix]). Equality is
/// defined over that projection, which is what makes facing excluded from
/// success comparison "for free" (`docs/architecture.md` §3.5) — facing simply
/// is not part of the encoded cell value (`docs/fundamentals.md` §5).
@immutable
class Formation {
  Formation._(this.type, this.rowCount, this._dancers);

  /// Builds a formation, validating that it projects onto a legal matrix.
  ///
  /// Throws [FormationProjectionError] if two dancers share a cell or any
  /// dancer sits outside the `rowCount x kColumnCount` grid.
  factory Formation({
    required FormationType type,
    required int rowCount,
    required Map<DancerId, DancerState> dancers,
  }) {
    final formation = Formation._(type, rowCount, Map.unmodifiable(dancers));
    formation.toMatrix(); // Validates; result deliberately discarded.
    return formation;
  }

  /// The formation this dance is danced in.
  ///
  /// Constant for the whole dance. It is carried on the state because two
  /// rules are formation-dispatched rather than derivable from the matrix:
  /// hands-four grouping (`handsFourOffset`, since DI couples share a row
  /// while Becket couples share a column) and Becket progression sense
  /// (`docs/fundamentals.md` §10.6).
  ///
  /// Deliberately **not** part of [operator ==]: equality is cell-by-cell
  /// decimal per `docs/architecture.md` §3.5.
  final FormationType type;

  /// Matrix height, always `kRowsPerHandsFour * handsFourCount`.
  ///
  /// Fixed rather than derived from occupied rows: a line of four (§8.1)
  /// leaves one row of its hands four empty, and shrinking the matrix there
  /// would make an otherwise-correct state fail equality *structurally*
  /// against a full-height oracle.
  final int rowCount;

  final Map<DancerId, DancerState> _dancers;

  /// The number of hands four this matrix is sized for.
  int get handsFourCount => rowCount ~/ kRowsPerHandsFour;

  /// Every dancer's state, keyed by invariant identity.
  Map<DancerId, DancerState> get dancers => _dancers;

  /// The index of the bottom row (row `N` in `docs/fundamentals.md` §10.2).
  int get lastRow => rowCount - 1;

  /// The state of [id], or `null` if that dancer is not in this set.
  DancerState? operator [](DancerId id) => _dancers[id];

  /// The state of [id]. Throws if the dancer is not in this set.
  DancerState stateOf(DancerId id) {
    final state = _dancers[id];
    if (state == null) {
      throw FormationProjectionError('No such dancer in this set: $id');
    }
    return state;
  }

  /// The identity of the dancer standing at [position], or `null` if empty.
  DancerId? dancerAt(Position position) {
    for (final entry in _dancers.entries) {
      if (entry.value.position == position) return entry.key;
    }
    return null;
  }

  /// Every dancer standing in [row], in ascending column order.
  List<DancerId> dancersInRow(int row) {
    final found = _dancers.entries.where((e) => e.value.row == row).toList()
      ..sort((a, b) => a.value.col.compareTo(b.value.col));
    return [for (final e in found) e.key];
  }

  /// Every dancer standing in [col], in ascending row order.
  List<DancerId> dancersInColumn(int col) {
    final found = _dancers.entries.where((e) => e.value.col == col).toList()
      ..sort((a, b) => a.value.row.compareTo(b.value.row));
    return [for (final e in found) e.key];
  }

  /// A copy of this formation with [changes] applied over the existing map.
  ///
  /// The primitive every figure builds on: figures compute the deltas they
  /// cause and hand them here rather than mutating shared state.
  Formation withUpdates(Map<DancerId, DancerState> changes) {
    if (changes.isEmpty) return this;
    final next = Map<DancerId, DancerState>.of(_dancers);
    for (final entry in changes.entries) {
      if (!next.containsKey(entry.key)) {
        throw FormationProjectionError(
          'Cannot update unknown dancer ${entry.key}',
        );
      }
      next[entry.key] = entry.value;
    }
    return Formation(type: type, rowCount: rowCount, dancers: next);
  }

  /// A copy of this formation with [rowCount] left intact and every dancer
  /// rebuilt by [transform].
  Formation mapDancers(
    DancerState Function(DancerId id, DancerState state) transform,
  ) => Formation(
    type: type,
    rowCount: rowCount,
    dancers: {
      for (final entry in _dancers.entries)
        entry.key: transform(entry.key, entry.value),
    },
  );

  /// Projects the entity map onto the decimal matrix defined in
  /// `docs/fundamentals.md` §5. `0` marks an empty cell.
  List<List<int>> toMatrix() {
    final grid = List.generate(
      rowCount,
      (_) => List<int>.filled(kColumnCount, 0),
      growable: false,
    );
    final occupants = <Position, DancerId>{};
    for (final entry in _dancers.entries) {
      final position = entry.value.position;
      if (position.row < 0 || position.row >= rowCount) {
        throw FormationProjectionError(
          'Dancer ${entry.key} is outside the matrix at $position '
          '(rowCount=$rowCount)',
        );
      }
      if (position.col < 0 || position.col >= kColumnCount) {
        throw FormationProjectionError(
          'Dancer ${entry.key} is outside the matrix at $position',
        );
      }
      final existing = occupants[position];
      if (existing != null) {
        throw FormationProjectionError(
          'Cell collision at $position: ${entry.key} and $existing',
        );
      }
      occupants[position] = entry.key;
      grid[position.row][position.col] = encodeDancer(
        entry.key,
        entry.value.number,
      );
    }
    return grid;
  }

  /// Role notation, one string per row (`R1-A . . . L1-A`).
  ///
  /// Matches the `rolesNotation` form used by the golden fixtures.
  List<String> toRolesNotation() {
    final grid = toMatrix();
    return [
      for (final row in grid)
        [
          for (final cell in row)
            if (cell == 0) '.' else _label(cell),
        ].join(' '),
    ];
  }

  static String _label(int cell) {
    final decoded = decodeDancer(cell);
    if (decoded == null) return '?';
    return '${decoded.id.role.label}${decoded.number.label}'
        '-${decoded.id.coupleLetter}';
  }

  /// A three-view debug rendering: decimal, role notation, and facing.
  String render() {
    final grid = toMatrix();
    final buffer = StringBuffer()..writeln('decimal:');
    for (final row in grid) {
      buffer.writeln('  ${row.map((c) => c.toString().padLeft(4)).join()}');
    }
    buffer.writeln('roles:');
    for (final line in toRolesNotation()) {
      buffer.writeln('  $line');
    }
    buffer.writeln('facing:');
    for (var r = 0; r < rowCount; r++) {
      final cells = <String>[];
      for (var c = 0; c < kColumnCount; c++) {
        final id = dancerAt(Position(r, c));
        cells.add((id == null ? '.' : stateOf(id).facing.label).padLeft(9));
      }
      buffer.writeln('  ${cells.join()}');
    }
    return buffer.toString();
  }

  /// Cell-by-cell matrix equality (`docs/architecture.md` §3.5).
  ///
  /// Facing is intentionally not compared: it is not encoded in a cell value,
  /// so two states that differ only in where dancers are looking are equal.
  @override
  bool operator ==(Object other) {
    if (other is! Formation) return false;
    if (other.rowCount != rowCount) return false;
    final a = toMatrix();
    final b = other.toMatrix();
    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < kColumnCount; c++) {
        if (a[r][c] != b[r][c]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(rowCount, Object.hashAll(toMatrix().expand((r) => r)));

  @override
  String toString() => toRolesNotation().join(' / ');
}
