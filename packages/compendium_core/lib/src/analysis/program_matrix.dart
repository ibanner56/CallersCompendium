/// The programming matrix (figures × dances) — CC's Elements matrix, but
/// **derived for free** from the structured [Dance.figures] we already store
/// rather than a manually ticked checklist (CC's failure mode).
///
/// Pure, Flutter-free, and unit-tested: the UI (`ProgramMatrixTable` in the
/// app) is a thin renderer over this model. Columns are the moves actually
/// present across the given dances; each cell records whether a dance uses a
/// move; each row flags the dance's FIRST move (the first-figure highlight).
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../dialect/dialect.dart';
import '../model/dance.dart';
import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';

/// What kind of move a [MatrixColumn] represents, so the UI can label and
/// order it appropriately.
enum MatrixColumnKind {
  /// A move found in the taxonomy — labelled via its `MoveDef`/dialect.
  known,

  /// A move id not present in the taxonomy — labelled with its raw id so
  /// nothing is silently dropped (mirrors the renderer's unknown-move fallback).
  unknown,

  /// The single collapsed column for all custom (free-text) figures. Custom
  /// moves are un-taxonomised and can't be reliably compared, so they share one
  /// column. First-figure highlighting still works when a dance opens custom.
  custom,
}

/// One column of the matrix: a move (or the collapsed custom bucket).
@immutable
class MatrixColumn {
  const MatrixColumn({required this.moveId, required this.kind});

  /// Canonical move id, an unknown raw id, or [customMove] for the custom
  /// bucket.
  final String moveId;
  final MatrixColumnKind kind;

  bool get isCustom => kind == MatrixColumnKind.custom;

  @override
  bool operator ==(Object other) =>
      other is MatrixColumn && other.moveId == moveId && other.kind == kind;

  @override
  int get hashCode => Object.hash(moveId, kind);

  @override
  String toString() => 'MatrixColumn($moveId, ${kind.name})';
}

const SetEquality<String> _setEq = SetEquality<String>();

/// One row of the matrix: a dance and the moves it contains.
@immutable
class MatrixRow {
  MatrixRow({
    required this.danceId,
    required this.title,
    required this.firstMoveId,
    required Set<String> presentMoveIds,
  }) : presentMoveIds = Set.unmodifiable(presentMoveIds);

  final String danceId;
  final String title;

  /// Column key of the dance's FIRST figure (the first-figure highlight), or
  /// `null` when the dance has no figures. Custom first figures use
  /// [customMove]. When non-null it is always contained in [presentMoveIds].
  final String? firstMoveId;

  /// Column keys (see [columnKeyForFigure]) of every move present in the dance.
  final Set<String> presentMoveIds;

  bool contains(MatrixColumn column) => presentMoveIds.contains(column.moveId);

  bool isFirst(MatrixColumn column) => firstMoveId == column.moveId;

  @override
  bool operator ==(Object other) =>
      other is MatrixRow &&
      other.danceId == danceId &&
      other.title == title &&
      other.firstMoveId == firstMoveId &&
      _setEq.equals(other.presentMoveIds, presentMoveIds);

  @override
  int get hashCode =>
      Object.hash(danceId, title, firstMoveId, _setEq.hash(presentMoveIds));
}

/// The derived matrix: [columns] × [rows] with per-cell presence and per-row
/// first-figure flags. Immutable and cheap to rebuild whenever the program's
/// dances change.
@immutable
class ProgramMatrix {
  const ProgramMatrix({required this.columns, required this.rows});

  final List<MatrixColumn> columns;
  final List<MatrixRow> rows;

  /// True when no move columns were discovered (no dance carries a figure).
  bool get isEmpty => columns.isEmpty;

  /// Whether [rows]`[rowIndex]` uses [columns]`[colIndex]`.
  bool isPresent(int rowIndex, int colIndex) =>
      rows[rowIndex].contains(columns[colIndex]);

  /// Whether [columns]`[colIndex]` is the FIRST figure of [rows]`[rowIndex]`.
  bool isFirst(int rowIndex, int colIndex) =>
      rows[rowIndex].isFirst(columns[colIndex]);
}

/// Column key for a [figure]: custom figures all map to [customMove]; every
/// other figure maps to its raw move id (aliases are intentionally NOT resolved
/// here — a "see saw" column stays distinct from "do si do", matching how the
/// renderer shows aliases under their own name).
String columnKeyForFigure(Figure figure) =>
    figure.isCustom ? customMove : figure.move;

/// Builds the [ProgramMatrix] for [dances] (rows, in the given order) using
/// [taxonomy] (defaults to [contraTaxonomy]) to order and classify columns.
///
/// Column order: taxonomy canonical order (the [Taxonomy.moves] definition
/// order) for known moves that appear, then any unknown move ids (sorted, for
/// determinism), then a single trailing custom column when any custom figure is
/// present. This is stable — it doesn't reshuffle as the program changes —
/// and groups related moves the way the taxonomy authors intended.
///
/// Presence is boolean (a repeated move counts once, matching CC's checklist
/// semantics). Figure-less or deleted dances still produce a row (with an empty
/// presence set) so the gap is visible; they contribute no columns.
ProgramMatrix buildProgramMatrix(List<Dance> dances, {Taxonomy? taxonomy}) {
  final tax = taxonomy ?? contraTaxonomy;

  final rows = <MatrixRow>[];
  final present = <String>{};
  var hasCustom = false;

  for (final dance in dances) {
    final rowMoves = <String>{};
    for (final figure in dance.figures) {
      final key = columnKeyForFigure(figure);
      rowMoves.add(key);
      if (key == customMove) {
        hasCustom = true;
      } else {
        present.add(key);
      }
    }
    rows.add(
      MatrixRow(
        danceId: dance.id,
        title: dance.title,
        firstMoveId: dance.figures.isEmpty
            ? null
            : columnKeyForFigure(dance.figures.first),
        presentMoveIds: rowMoves,
      ),
    );
  }

  final columns = <MatrixColumn>[];

  // Known moves in taxonomy definition order.
  for (final id in tax.moves.keys) {
    if (present.remove(id)) {
      columns.add(MatrixColumn(moveId: id, kind: MatrixColumnKind.known));
    }
  }

  // Anything left in `present` is an unknown move id (not in the taxonomy),
  // sorted for deterministic output.
  final unknown = present.toList()..sort();
  for (final id in unknown) {
    columns.add(MatrixColumn(moveId: id, kind: MatrixColumnKind.unknown));
  }

  // Single trailing custom column.
  if (hasCustom) {
    columns.add(
      const MatrixColumn(moveId: customMove, kind: MatrixColumnKind.custom),
    );
  }

  return ProgramMatrix(columns: columns, rows: rows);
}

/// Human label for a matrix [column] under [dialect], routed through the same
/// display path as figure rendering so column headers honour the active
/// dialect.
///
/// - custom → "Custom";
/// - known → dialect move substitution when present and side-independent,
///   otherwise the move's canonical display name. Side-dependent substitutions
///   (those using `%S`, which need a specific figure's shoulder/hand) can't be
///   resolved at the column level, so they fall back to the canonical display
///   name;
/// - unknown → the raw move id (nothing silently dropped).
String matrixColumnLabel(
  MatrixColumn column,
  Taxonomy taxonomy,
  Dialect dialect,
) {
  if (column.isCustom) return 'Custom';
  final def = taxonomy.resolve(column.moveId);
  if (def == null) return column.moveId;
  final substitution = dialect.moves[column.moveId];
  if (substitution != null && !substitution.contains('%S')) {
    return substitution;
  }
  return def.displayName;
}
