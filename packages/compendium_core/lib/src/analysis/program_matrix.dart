/// The programming matrix (figures × dances) — CC's Elements matrix, but
/// **derived for free** from the structured [Dance.figures] we already store
/// rather than a manually ticked checklist (CC's failure mode).
///
/// Pure, Flutter-free, and unit-tested: the UI (`ProgramMatrixTable` in the
/// app) is a thin renderer over this model. Columns are the moves actually
/// present across the given dances; each cell records whether a dance uses a
/// move.
///
/// Three independent highlights are derived:
///  * **Dance's first figure** (per row): the move each dance *opens* with
///    ([MatrixRow.firstMoveId] / [MatrixRow.isFirst] / [ProgramMatrix.isFirst]).
///    This mirrors Caller's Companion's per-dance "First figure" field.
///  * **Program debut** (per column): the first dance in program (row) order
///    whose figures contain that move *anywhere* — "this move is introduced
///    here" ([ProgramMatrix.isProgramDebut]). A move used by several dances is
///    a debut only on the earliest row; the collapsed custom column debuts on
///    its first appearance too.
///  * **Same-figure-same-phrase collision** (per cell): the move repeats, in
///    the same phrase (A1/A2/B1/B2…), in a *strictly-adjacent* dance (the row
///    immediately above or below in program order) — the repeat a caller wants
///    to reconsider ([ProgramMatrix.isPhraseCollision]). Phrase positions are
///    derived from cumulative **effective** beats ([Taxonomy.effectiveParams],
///    so figures with no explicitly-stored count still land in the right
///    phrase) and threaded through [MatrixRow.phraseLabelsByMove]; the
///    un-comparable custom column never collides.
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
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
const MapEquality<String, Set<String>> _phraseMapEq =
    MapEquality<String, Set<String>>(values: _setEq);

/// One row of the matrix: a dance and the moves it contains.
@immutable
class MatrixRow {
  MatrixRow({
    required this.danceId,
    required this.title,
    required this.firstMoveId,
    required Set<String> presentMoveIds,
    Map<String, Set<String>> phraseLabelsByMove = const {},
    this.half,
    this.formation = const Formation(FormationShape.dupleImproper),
  }) : presentMoveIds = Set.unmodifiable(presentMoveIds),
       phraseLabelsByMove = Map.unmodifiable({
         for (final entry in phraseLabelsByMove.entries)
           entry.key: Set.unmodifiable(entry.value),
       });

  final String danceId;
  final String title;

  /// The program half this dance's slot falls in (see [Program.halfAtIndex]),
  /// or `null` when the program has no break to derive halves from. Drives the
  /// "1st"/"2nd" half badge on the matrix row header.
  final ProgramHalf? half;

  /// Column key of the dance's FIRST figure (the first-figure highlight), or
  /// `null` when the dance has no figures. Custom first figures use
  /// [customMove]. When non-null it is always contained in [presentMoveIds].
  final String? firstMoveId;

  /// Column keys (see [columnKeyForFigure]) of every move present in the dance.
  final Set<String> presentMoveIds;

  /// For each comparable move (column key) present in the dance, the set of
  /// phrase labels (A1/A2/B1/B2…) in which that move *starts*. Positions are
  /// derived from cumulative **effective** beats (taxonomy defaults folded in
  /// via [Taxonomy.effectiveParams]), so a figure whose beat count isn't
  /// explicitly stored still lands in the right phrase. A move used in more
  /// than one phrase carries every label. Drives the same-figure-same-phrase
  /// collision check ([ProgramMatrix.isPhraseCollision]).
  ///
  /// The collapsed [customMove] column is intentionally **absent** here: custom
  /// (free-text) figures aren't reliably comparable, so distinct customs that
  /// happen to share a phrase must not read as the *same* figure repeating.
  final Map<String, Set<String>> phraseLabelsByMove;

  /// The dance's formation (Becket, 4x4, triplet, …) — surfaced as its own
  /// pinned column in the matrix (#663), never folded into [presentMoveIds]
  /// since it's a per-dance attribute, not a move a dance either does or
  /// doesn't contain.
  final Formation formation;

  bool contains(MatrixColumn column) => presentMoveIds.contains(column.moveId);

  bool isFirst(MatrixColumn column) => firstMoveId == column.moveId;

  @override
  bool operator ==(Object other) =>
      other is MatrixRow &&
      other.danceId == danceId &&
      other.title == title &&
      other.firstMoveId == firstMoveId &&
      other.half == half &&
      other.formation == formation &&
      _setEq.equals(other.presentMoveIds, presentMoveIds) &&
      _phraseMapEq.equals(other.phraseLabelsByMove, phraseLabelsByMove);

  @override
  int get hashCode => Object.hash(
    danceId,
    title,
    firstMoveId,
    half,
    formation,
    _setEq.hash(presentMoveIds),
    _phraseMapEq.hash(phraseLabelsByMove),
  );
}

/// The derived matrix: [columns] × [rows] with per-cell presence, per-row
/// dance-opening flags, and per-column program-debut flags. Immutable and cheap
/// to rebuild whenever the program's dances change.
@immutable
class ProgramMatrix {
  const ProgramMatrix({
    required this.columns,
    required this.rows,
    this.programDebutRowByMove = const {},
  });

  final List<MatrixColumn> columns;
  final List<MatrixRow> rows;

  /// For each move (column key, including [customMove]) present in any dance,
  /// the index of the first [rows] entry — in program order — whose dance
  /// contains that move anywhere. Drives [isProgramDebut]. Moves that no dance
  /// uses are absent from the map.
  final Map<String, int> programDebutRowByMove;

  /// True when the matrix has no columns. Because the partner/neighbor swing
  /// baseline is emitted whenever the program has at least one dance, this is
  /// true only for a program with **no dances** at all — not merely one whose
  /// dances carry no figures. Gates the empty-state (on-screen table and PDF)
  /// and the matrix-export control.
  bool get isEmpty => columns.isEmpty;

  /// Whether [rows]`[rowIndex]` uses [columns]`[colIndex]`.
  bool isPresent(int rowIndex, int colIndex) =>
      rows[rowIndex].contains(columns[colIndex]);

  /// Whether [columns]`[colIndex]` is the dance's opening figure for
  /// [rows]`[rowIndex]` (Caller's Companion "First figure" parity).
  bool isFirst(int rowIndex, int colIndex) =>
      rows[rowIndex].isFirst(columns[colIndex]);

  /// Whether [rows]`[rowIndex]` is where [columns]`[colIndex]`'s move first
  /// appears in program order — its program debut ("introduced here").
  bool isProgramDebut(int rowIndex, int colIndex) =>
      programDebutRowByMove[columns[colIndex].moveId] == rowIndex;

  /// Whether the move at [rows]`[rowIndex]` × [columns]`[colIndex]` is a
  /// **same-figure-same-phrase collision** with a strictly-adjacent dance: the
  /// same move appears, in the *same* phrase (A1/A2/B1/B2…), in the dance
  /// immediately above OR below this one in program order.
  ///
  /// Adjacency is strictly the previous/next row (issue #582's locked design —
  /// not a configurable window). The collapsed [customMove] column never
  /// collides (custom figures aren't reliably comparable), because
  /// [MatrixRow.phraseLabelsByMove] omits it. Returns `false` when the move
  /// isn't present in this cell.
  bool isPhraseCollision(int rowIndex, int colIndex) {
    final moveId = columns[colIndex].moveId;
    final here = rows[rowIndex].phraseLabelsByMove[moveId];
    if (here == null || here.isEmpty) return false;
    for (final neighbor in [rowIndex - 1, rowIndex + 1]) {
      if (neighbor < 0 || neighbor >= rows.length) continue;
      final there = rows[neighbor].phraseLabelsByMove[moveId];
      if (there != null && here.any(there.contains)) return true;
    }
    return false;
  }
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

/// Effective beat length of [figure] under [taxonomy], for phrase math: the
/// figure's explicit/alias-pinned `beats`, else the move's `paramBeats`/spec
/// default, else the neutral unknown-move fallback ([Taxonomy.effectiveParams]).
/// A move that legitimately carries no beat cost (absent from `effectiveParams`)
/// contributes 0. Never negative. This is the phrase-safe counterpart to raw
/// [Figure.beats], which reads 0 for any figure whose count wasn't stored.
int _effectiveBeats(Taxonomy taxonomy, Figure figure) {
  final beats = taxonomy.effectiveParams(figure)['beats'];
  return beats is int && beats > 0 ? beats : 0;
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
///
/// [halves], when provided, is a parallel list aligned to [dances] (same order
/// and length) supplying each row's derived [ProgramHalf] (see
/// [Program.halvesForSlots] / [Program.halfAtIndex]); a `null` entry means the
/// dance has no half (the program has no break, or the slot is itself the
/// break). It must be exactly the same length as [dances] — a mismatch throws
/// [ArgumentError] (enforced at runtime, in release builds too). Omit it to
/// leave every row's [MatrixRow.half] `null`.
ProgramMatrix buildProgramMatrix(
  List<Dance> dances, {
  Taxonomy? taxonomy,
  List<ProgramHalf?>? halves,
}) {
  final tax = taxonomy ?? contraTaxonomy;
  if (halves != null && halves.length != dances.length) {
    throw ArgumentError.value(
      halves.length,
      'halves',
      'must be aligned to dances (same length: ${dances.length})',
    );
  }

  final rows = <MatrixRow>[];
  final present = <String>{};
  var hasCustom = false;

  for (var i = 0; i < dances.length; i++) {
    final dance = dances[i];
    final rowMoves = <String>{};
    final phraseLabels = <String, Set<String>>{};
    // Phrase positions are derived from cumulative *effective* beats
    // ([Taxonomy.effectiveParams]) — the taxonomy defaults and unknown-move
    // fallback the rest of the analysis uses — NOT raw [Figure.beats] (which is
    // 0 when a figure carries no explicitly-stored count, mislabelling every
    // such figure as A1 and producing false collisions). A figure is labelled
    // by the phrase it *starts* in; every figure (custom included) advances the
    // beat cursor so later figures land in the right phrase.
    final structure = dance.phraseStructure;
    var beat = 0;
    for (final figure in dance.figures) {
      final key = columnKeyForFigure(figure);
      final effBeats = _effectiveBeats(tax, figure);
      rowMoves.add(key);
      if (key == customMove) {
        hasCustom = true;
      } else {
        present.add(key);
        // Track the phrase in which this move starts so strictly-adjacent
        // dances can be checked for same-figure-same-phrase collisions. Custom
        // figures are excluded (their column is un-comparable) but still
        // advance the beat cursor below.
        (phraseLabels[key] ??= <String>{}).add(
          labelForFigure(beat, effBeats, structure),
        );
      }
      beat += effBeats;
    }
    rows.add(
      MatrixRow(
        danceId: dance.id,
        title: dance.title,
        firstMoveId: dance.figures.isEmpty
            ? null
            : columnKeyForFigure(dance.figures.first),
        presentMoveIds: rowMoves,
        phraseLabelsByMove: phraseLabels,
        half: halves == null ? null : halves[i],
        formation: dance.formation,
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

  // Program debut per move: the first row (program order) whose dance contains
  // that move anywhere, keyed by column moveId (including the collapsed custom
  // column). Built from rows directly so it's independent of column ordering.
  final programDebutRowByMove = <String, int>{};
  for (var r = 0; r < rows.length; r++) {
    for (final moveId in rows[r].presentMoveIds) {
      programDebutRowByMove.putIfAbsent(moveId, () => r);
    }
  }

  return ProgramMatrix(
    columns: columns,
    rows: rows,
    programDebutRowByMove: programDebutRowByMove,
  );
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
