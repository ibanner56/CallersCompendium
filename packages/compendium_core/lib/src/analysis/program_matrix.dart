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
import '../dialect/renderer.dart';
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

  /// A sub-column of a move that is split by one of its params so callers can
  /// see variety at a glance: `swing` is split by role (`who`) and `hey` by
  /// length. The column's [MatrixColumn.moveId] is a compound key
  /// (`<baseMoveId>:<variant>`, e.g. `swing:partner`, `hey:full`); the parent
  /// move and the variant are carried in [MatrixColumn.baseMoveId] /
  /// [MatrixColumn.variant] so the label function can render the header.
  split,
}

/// The parent move id for [swingColumnKey]-style split columns.
const String swingMoveId = 'swing';

/// The parent move id for [heyColumnKey]-style split columns.
const String heyMoveId = 'hey';

/// Swing role variants in header order: [swingBaselineVariants] first (always
/// shown), then the present-only variants. Anything not mapped lands in
/// `other` so nothing is silently dropped.
const List<String> swingBaselineVariants = ['partner', 'neighbor'];
const List<String> _swingPresentOnlyVariants = [
  'larks',
  'robins',
  'shadow',
  'ones',
  'twos',
  'corners',
  'same',
  'other',
];
const List<String> _swingVariantOrder = [
  ...swingBaselineVariants,
  ..._swingPresentOnlyVariants,
];

/// Hey length variants in header order (both present-only — no baseline).
const List<String> _heyVariantOrder = ['half', 'full'];

/// Maps a swing's `who` value (defaulting to the taxonomy default `partners`
/// when unset) to its role-group variant.
String _swingRoleVariant(Object? who) {
  switch (who ?? 'partners') {
    case 'partners':
      return 'partner';
    case 'neighbors':
      return 'neighbor';
    case 'shadows':
    case 'secondShadows':
      return 'shadow';
    case 'role1s':
      return 'larks';
    case 'role2s':
      return 'robins';
    case 'ones':
      return 'ones';
    case 'twos':
      return 'twos';
    case 'firstCorners':
    case 'secondCorners':
      return 'corners';
    case 'sameRoles':
      return 'same';
    default:
      return 'other';
  }
}

/// Maps a hey's `length` value (defaulting to the taxonomy default `half` when
/// unset) to its length-group variant. Mirrors the taxonomy's own `paramBeats`
/// grouping: {lessThanHalf, half} → half (8 beats); {betweenHalfAndFull, full}
/// → full (16 beats).
String _heyLengthVariant(Object? length) {
  switch (length) {
    case 'betweenHalfAndFull':
    case 'full':
      return 'full';
    default:
      return 'half';
  }
}

/// Compound column key for a swing of the given [who] role.
String swingColumnKey(Object? who) => '$swingMoveId:${_swingRoleVariant(who)}';

/// Compound column key for a hey of the given [length].
String heyColumnKey(Object? length) =>
    '$heyMoveId:${_heyLengthVariant(length)}';

/// One column of the matrix: a move (or the collapsed custom bucket).
@immutable
class MatrixColumn {
  const MatrixColumn({
    required this.moveId,
    required this.kind,
    this.baseMoveId,
    this.variant,
  }) : assert(
         (kind == MatrixColumnKind.split) == (baseMoveId != null),
         'split columns require baseMoveId; non-split columns must omit it',
       ),
       assert(
         (baseMoveId != null) == (variant != null),
         'baseMoveId and variant are set together or not at all',
       );

  /// Canonical move id, an unknown raw id, [customMove] for the custom bucket,
  /// or a compound `<baseMoveId>:<variant>` key for a [MatrixColumnKind.split]
  /// column.
  final String moveId;
  final MatrixColumnKind kind;

  /// For [MatrixColumnKind.split] columns, the parent move id (`swing`/`hey`);
  /// `null` for every other kind.
  final String? baseMoveId;

  /// For [MatrixColumnKind.split] columns, the variant token (e.g. `partner`,
  /// `full`); `null` for every other kind.
  final String? variant;

  bool get isCustom => kind == MatrixColumnKind.custom;
  bool get isSplit => kind == MatrixColumnKind.split;

  @override
  bool operator ==(Object other) =>
      other is MatrixColumn &&
      other.moveId == moveId &&
      other.kind == kind &&
      other.baseMoveId == baseMoveId &&
      other.variant == variant;

  @override
  int get hashCode => Object.hash(moveId, kind, baseMoveId, variant);

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

  /// True when the matrix has no columns. Because the partner/neighbor swing
  /// baseline is emitted whenever the program has at least one dance, this is
  /// true only for a program with **no dances** at all — not merely one whose
  /// dances carry no figures. Gates the empty-state (on-screen table and PDF)
  /// and the matrix-export control.
  bool get isEmpty => columns.isEmpty;

  /// Whether [rows]`[rowIndex]` uses [columns]`[colIndex]`.
  bool isPresent(int rowIndex, int colIndex) =>
      rows[rowIndex].contains(columns[colIndex]);

  /// Whether [columns]`[colIndex]` is the FIRST figure of [rows]`[rowIndex]`.
  bool isFirst(int rowIndex, int colIndex) =>
      rows[rowIndex].isFirst(columns[colIndex]);
}

/// Column key for a [figure]: custom figures all map to [customMove]; `swing`
/// and `hey` map to compound `<move>:<variant>` keys ([swingColumnKey] /
/// [heyColumnKey]) so they split into per-role / per-length sub-columns; every
/// other figure maps to its raw move id (aliases are intentionally NOT resolved
/// here — a "see saw" column stays distinct from "do si do", and
/// `meltdown_swing` keeps its own key rather than folding into a swing role
/// column, matching how the renderer shows aliases under their own name).
String columnKeyForFigure(Figure figure) {
  if (figure.isCustom) return customMove;
  switch (figure.move) {
    case swingMoveId:
      return swingColumnKey(figure.params['who']);
    case heyMoveId:
      return heyColumnKey(figure.params['length']);
    default:
      return figure.move;
  }
}

MatrixColumn _splitColumn(String baseMoveId, String variant) => MatrixColumn(
  moveId: '$baseMoveId:$variant',
  kind: MatrixColumnKind.split,
  baseMoveId: baseMoveId,
  variant: variant,
);

/// Builds the [ProgramMatrix] for [dances] (rows, in the given order) using
/// [taxonomy] (defaults to [contraTaxonomy]) to order and classify columns.
///
/// Column order: taxonomy canonical order (the [Taxonomy.moves] definition
/// order) for known moves that appear, then any unknown move ids (sorted, for
/// determinism), then a single trailing custom column when any custom figure is
/// present. This is stable — it doesn't reshuffle as the program changes —
/// and groups related moves the way the taxonomy authors intended.
///
/// The `swing` and `hey` moves are split into sub-columns at their taxonomy
/// position: swing into per-role columns (`partner`, `neighbor` always shown as
/// a fixed baseline whenever the program has any dances, then `larks`, `robins`,
/// `shadow`, `ones`, `twos`, `corners`, `same`, `other` present-only, in that
/// order); hey into `half` then `full`, both present-only.
///
/// Presence is boolean (a repeated move counts once, matching CC's checklist
/// semantics). Figure-less or deleted dances still produce a row (with an empty
/// presence set) so the gap is visible; they contribute no columns of their own
/// (but the swing baseline still appears while any dance exists).
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
  final hasDances = dances.isNotEmpty;

  // Known moves in taxonomy definition order. `swing` and `hey` expand into
  // their split sub-columns (grouped, in variant order) in place of a single
  // column; every other known move emits one column when present.
  for (final id in tax.moves.keys) {
    if (id == swingMoveId) {
      for (final variant in _swingVariantOrder) {
        final present0 = present.remove('$swingMoveId:$variant');
        final baseline = swingBaselineVariants.contains(variant);
        if (baseline ? hasDances : present0) {
          columns.add(_splitColumn(swingMoveId, variant));
        }
      }
    } else if (id == heyMoveId) {
      for (final variant in _heyVariantOrder) {
        if (present.remove('$heyMoveId:$variant')) {
          columns.add(_splitColumn(heyMoveId, variant));
        }
      }
    } else if (present.remove(id)) {
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
/// - split → the parent move's dialect-aware name qualified by the variant:
///   swing role columns read `<role> <swing>` ('partner swing', 'lark swing',
///   …) — larks/robins route through [FigureRenderer.displayToken] so role
///   dialects (Larks/Robins, Gents/Ladies, …) are honoured; hey columns read
///   `<length> <hey>` ('half hey' / 'full hey');
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
  if (column.isSplit) return _splitColumnLabel(column, taxonomy, dialect);
  final def = taxonomy.resolve(column.moveId);
  if (def == null) return column.moveId;
  final substitution = dialect.moves[column.moveId];
  if (substitution != null && !substitution.contains('%S')) {
    return substitution;
  }
  return def.displayName;
}

/// Dialect-aware display word for a (taxonomy-known) [moveId] — the same
/// resolution [matrixColumnLabel] uses for known columns, reused for the
/// parent-move word of a split column.
String _splitMoveWord(String moveId, Taxonomy taxonomy, Dialect dialect) {
  final substitution = dialect.moves[moveId];
  if (substitution != null && !substitution.contains('%S')) return substitution;
  return taxonomy.resolve(moveId)?.displayName ?? moveId;
}

/// Header for a [MatrixColumnKind.split] column.
String _splitColumnLabel(
  MatrixColumn column,
  Taxonomy taxonomy,
  Dialect dialect,
) {
  final variant = column.variant;
  if (column.baseMoveId == swingMoveId) {
    final swing = _splitMoveWord(swingMoveId, taxonomy, dialect);
    final whoSpec = taxonomy.resolve(swingMoveId)?.params['who'];
    switch (variant) {
      // Role columns honour the active dialect's role term (singular).
      case 'larks':
        return '${FigureRenderer.displayToken('role1', whoSpec, dialect)} '
            '$swing';
      case 'robins':
        return '${FigureRenderer.displayToken('role2', whoSpec, dialect)} '
            '$swing';
      case 'partner':
        return 'partner $swing';
      case 'neighbor':
        return 'neighbor $swing';
      case 'shadow':
        return 'shadow $swing';
      case 'ones':
        return 'ones $swing';
      case 'twos':
        return 'twos $swing';
      case 'corners':
        return 'corners $swing';
      case 'same':
        return 'same-role $swing';
      default:
        return '$swing (other)';
    }
  }
  if (column.baseMoveId == heyMoveId) {
    // variant is 'half' / 'full'.
    return '$variant ${_splitMoveWord(heyMoveId, taxonomy, dialect)}';
  }
  return column.moveId;
}
