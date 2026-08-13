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
///  * **Same-figure collision** (per cell): the move repeats in a
///    *strictly-adjacent* dance (the row immediately above or below in program
///    order) — the repeat a caller wants to reconsider
///    ([ProgramMatrix.isCollision]). Positions are derived from cumulative
///    **effective** beats ([Taxonomy.effectiveParams], so figures with no
///    explicitly-stored count still land correctly) and threaded through
///    [MatrixRow.phraseLabelsByMove] / [MatrixRow.beatSpansByMove]; the
///    un-comparable custom column never collides. [ProgramMatrix.collisionMode]
///    (issue #962) selects which of two comparisons decides a collision:
///     * [MatrixCollisionMode.exactBeats] (the default): the move's beat
///       *span* actually overlaps between the two dances — guards against,
///       say, one dance's 8-count swing and another's 10-count swing landing
///       in the same named phrase without their beats overlapping at all.
///     * [MatrixCollisionMode.phrase]: the move merely *starts* in the same
///       named phrase (A1/A2/B1/B2…) — the original (#582) behaviour, kept as
///       an opt-in via the "exact beat overlap" setting.
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
  /// see variety at a glance: `swing`, `allemande`, and `chain` are split by
  /// role (`who`) — `swing` additionally by its `prefix` (none/balance/
  /// meltdown) — and `hey` by length (issue #933). The column's
  /// [MatrixColumn.moveId] is a compound key (`<baseMoveId>:<variant>`, e.g.
  /// `swing:partner`, `swing:partner:balance`, `allemande:larks`, `hey:full`);
  /// the parent move and the variant are carried in [MatrixColumn.baseMoveId]
  /// / [MatrixColumn.variant] so the label function can render the header.
  split,
}

/// The parent move id for [swingColumnKey]-style split columns.
const String swingMoveId = 'swing';

/// The parent move id for [heyColumnKey]-style split columns.
const String heyMoveId = 'hey';

/// The parent move id for [allemandeColumnKey]-style split columns
/// (issue #933).
const String allemandeMoveId = 'allemande';

/// The parent move id for [chainColumnKey]-style split columns (issue #933).
const String chainMoveId = 'chain';

/// Swing role variants in header order: [swingBaselineVariants] first (always
/// shown for swing — see [buildProgramMatrix]'s baseline behaviour), then the
/// present-only variants shared by swing, allemande, and chain's role split.
/// Anything not mapped lands in `other` so nothing is silently dropped.
const List<String> swingBaselineVariants = ['partner', 'neighbor'];
const List<String> _roleGroupPresentOnlyVariants = [
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
  ..._roleGroupPresentOnlyVariants,
];

/// Role-group variant order for [allemandeMoveId] / [chainMoveId] split
/// columns (issue #933): present-only — unlike swing (which appears in nearly
/// every dance and so gets a fixed partner/neighbor baseline), most programs
/// use zero or one allemande/chain role, so neither is a baseline here.
/// `partner`/`neighbor` still come first when present, for the same
/// left-to-right reading order as swing.
const List<String> _roleVariantOrder = [
  ...swingBaselineVariants,
  ..._roleGroupPresentOnlyVariants,
];

/// Hey length variants in header order (both present-only — no baseline).
const List<String> _heyVariantOrder = ['half', 'full'];

/// Swing's `prefix` variants that get their own sub-column, in header order.
/// `none` is NOT here — it folds into the bare role column (`swing:<role>`),
/// unchanged from before issue #933's split, so every pre-existing
/// `swing:<role>`-keyed assertion keeps testing exactly what it tested.
const List<String> _swingPrefixVariantOrder = ['balance', 'meltdown'];

/// Maps a dancer-set `who` value to its role-group variant, shared by swing,
/// allemande, and chain's role split (issue #933 mirrors swing/hey's existing
/// split mechanism onto allemande/chain). Callers pass the ALREADY-resolved
/// effective value (taxonomy default / alias pin folded in via
/// [Taxonomy.effectiveParams]) — this function does no defaulting of its own.
String _roleVariant(Object? who) {
  switch (who) {
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

/// Normalizes a swing's `prefix` value to a split-column suffix, or `null` for
/// `none` (folds into the bare role column). An unrecognized/missing value is
/// treated as `none`, matching the taxonomy default.
String? _swingPrefixVariant(Object? prefix) {
  switch (prefix) {
    case 'balance':
      return 'balance';
    case 'meltdown':
      return 'meltdown';
    default:
      return null;
  }
}

/// Compound column key for a swing of the given [who] role and [prefix]
/// (`none`/`balance`/`meltdown`, defaulting to `none` when omitted or
/// unrecognized — issue #933). A `none` prefix folds into the bare role
/// column (`swing:<role>`); `balance`/`meltdown` widen it to
/// `swing:<role>:<prefix>`. Defaults [who] to `partners` — the taxonomy's own
/// default for `swing.who` — when omitted.
String swingColumnKey(Object? who, [Object? prefix]) {
  final role = _roleVariant(who ?? 'partners');
  final prefixVariant = _swingPrefixVariant(prefix);
  return prefixVariant == null
      ? '$swingMoveId:$role'
      : '$swingMoveId:$role:$prefixVariant';
}

/// Compound column key for a hey of the given [length].
String heyColumnKey(Object? length) =>
    '$heyMoveId:${_heyLengthVariant(length)}';

/// Compound column key for an allemande of the given [who] role (issue #933).
/// Defaults to `neighbors` — the taxonomy's own default for `allemande.who`
/// — when [who] is omitted.
String allemandeColumnKey(Object? who) =>
    '$allemandeMoveId:${_roleVariant(who ?? 'neighbors')}';

/// Compound column key for a chain of the given [who] role (issue #933).
/// Defaults to `role2s` — the taxonomy's own default for `chain.who` — when
/// [who] is omitted.
String chainColumnKey(Object? who) =>
    '$chainMoveId:${_roleVariant(who ?? 'role2s')}';

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
const ListEquality<BeatSpan> _beatSpanListEq = ListEquality<BeatSpan>();
const MapEquality<String, List<BeatSpan>> _beatSpanMapEq =
    MapEquality<String, List<BeatSpan>>(values: _beatSpanListEq);

/// A figure's cumulative-beat extent within a dance: `[start, start + beats)`.
/// [beats] is the figure's **effective** beat count ([Taxonomy.effectiveParams]),
/// so a figure with no explicitly-stored count still carries a real span.
/// [beats] may be `0` (e.g. `form_long_waves`, a bare formation label) — such a
/// figure is compared as a single **point** at [start] rather than an empty
/// range (see the overlap rule at [ProgramMatrix.isCollision]).
@immutable
class BeatSpan {
  const BeatSpan(this.start, this.beats)
    : assert(start >= 0, 'start must be >= 0'),
      assert(beats >= 0, 'beats must be >= 0');

  /// Cumulative beat offset at which the figure starts (0-based).
  final int start;

  /// The figure's effective beat length. May be 0 (see class doc).
  final int beats;

  /// Whether this span overlaps [other] under the exact-beat-overlap rule
  /// (issue #962): half-open range intersection for two non-zero-length spans;
  /// a zero-length span is treated as a **point** that must fall within (or
  /// equal, for two zero-length spans) the other span. This point treatment is
  /// a deliberate departure from [labelForFigure]'s backward phrase tie-break —
  /// that rule exists to choose between two *named buckets* at a boundary, and
  /// there are no buckets in exact-overlap mode to tie-break between.
  bool overlaps(BeatSpan other) {
    if (beats == 0 && other.beats == 0) return start == other.start;
    if (beats == 0) {
      return other.start <= start && start < other.start + other.beats;
    }
    if (other.beats == 0) {
      return start <= other.start && other.start < start + beats;
    }
    return start < other.start + other.beats && other.start < start + beats;
  }

  @override
  bool operator ==(Object other) =>
      other is BeatSpan && other.start == start && other.beats == beats;

  @override
  int get hashCode => Object.hash(start, beats);

  @override
  String toString() => 'BeatSpan($start, +$beats)';
}

/// Which comparison decides a same-figure collision between two
/// strictly-adjacent dances (issue #962). See [ProgramMatrix.isCollision].
enum MatrixCollisionMode {
  /// The move's beat span actually overlaps between the two dances. The
  /// default: guards against e.g. one dance's 8-count swing and another's
  /// 10-count swing landing in the same named phrase without their beats
  /// overlapping at all.
  exactBeats,

  /// The move merely starts in the same named phrase (A1/A2/B1/B2…) in both
  /// dances — the original (#582) behaviour, now opt-in.
  phrase,
}

/// One row of the matrix: a dance and the moves it contains.
@immutable
class MatrixRow {
  MatrixRow({
    required this.danceId,
    required this.title,
    required this.firstMoveId,
    required Set<String> presentMoveIds,
    Map<String, Set<String>> phraseLabelsByMove = const {},
    Map<String, List<BeatSpan>> beatSpansByMove = const {},
    this.half,
    this.formation = const Formation(FormationShape.dupleImproper),
  }) : presentMoveIds = Set.unmodifiable(presentMoveIds),
       phraseLabelsByMove = Map.unmodifiable({
         for (final entry in phraseLabelsByMove.entries)
           entry.key: Set.unmodifiable(entry.value),
       }),
       beatSpansByMove = Map.unmodifiable({
         for (final entry in beatSpansByMove.entries)
           entry.key: List<BeatSpan>.unmodifiable(entry.value),
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
  /// than one phrase carries every label. Drives the phrase-mode collision
  /// check ([ProgramMatrix.isCollision] with [MatrixCollisionMode.phrase]).
  ///
  /// The collapsed [customMove] column is intentionally **absent** here: custom
  /// (free-text) figures aren't reliably comparable, so distinct customs that
  /// happen to share a phrase must not read as the *same* figure repeating.
  final Map<String, Set<String>> phraseLabelsByMove;

  /// For each comparable move (column key) present in the dance, every
  /// occurrence's [BeatSpan] (cumulative effective-beat start + length). Drives
  /// the default exact-beat-overlap collision check ([ProgramMatrix.isCollision]
  /// with [MatrixCollisionMode.exactBeats], issue #962). Computed alongside
  /// [phraseLabelsByMove] from the same beat cursor; the collapsed [customMove]
  /// column is excluded here for the same reason it is excluded there.
  final Map<String, List<BeatSpan>> beatSpansByMove;

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
      _phraseMapEq.equals(other.phraseLabelsByMove, phraseLabelsByMove) &&
      _beatSpanMapEq.equals(other.beatSpansByMove, beatSpansByMove);

  @override
  int get hashCode => Object.hash(
    danceId,
    title,
    firstMoveId,
    half,
    formation,
    _setEq.hash(presentMoveIds),
    _phraseMapEq.hash(phraseLabelsByMove),
    _beatSpanMapEq.hash(beatSpansByMove),
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
    this.collisionMode = MatrixCollisionMode.exactBeats,
  });

  final List<MatrixColumn> columns;
  final List<MatrixRow> rows;

  /// Which comparison [isCollision] uses (issue #962). Defaults to
  /// [MatrixCollisionMode.exactBeats] — the product default changed by #962;
  /// [MatrixCollisionMode.phrase] restores the original (#582) behaviour via
  /// the "flag exact beat overlap only" setting when the caller turns it off.
  final MatrixCollisionMode collisionMode;

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
  /// **same-figure collision** with a strictly-adjacent dance: the same move
  /// appears in the dance immediately above OR below this one in program
  /// order, under whichever comparison [collisionMode] selects:
  ///
  ///  * [MatrixCollisionMode.exactBeats] (the default, issue #962): the move's
  ///    beat span actually overlaps ([BeatSpan.overlaps]) with an occurrence in
  ///    the neighbouring dance — the beat count itself, not just the named
  ///    phrase it starts in.
  ///  * [MatrixCollisionMode.phrase] (issue #582's original behaviour): the
  ///    move merely *starts* in the same phrase (A1/A2/B1/B2…) as an
  ///    occurrence in the neighbouring dance.
  ///
  /// Adjacency is strictly the previous/next row in both modes (issue #582's
  /// locked design — not a configurable window). The collapsed [customMove]
  /// column never collides in either mode (custom figures aren't reliably
  /// comparable), because neither [MatrixRow.phraseLabelsByMove] nor
  /// [MatrixRow.beatSpansByMove] carries it. Returns `false` when the move
  /// isn't present in this cell.
  bool isCollision(int rowIndex, int colIndex) {
    final moveId = columns[colIndex].moveId;
    return switch (collisionMode) {
      MatrixCollisionMode.exactBeats => _isExactBeatCollision(rowIndex, moveId),
      MatrixCollisionMode.phrase => _isPhraseCollision(rowIndex, moveId),
    };
  }

  bool _isExactBeatCollision(int rowIndex, String moveId) {
    final here = rows[rowIndex].beatSpansByMove[moveId];
    if (here == null || here.isEmpty) return false;
    for (final neighbor in [rowIndex - 1, rowIndex + 1]) {
      if (neighbor < 0 || neighbor >= rows.length) continue;
      final there = rows[neighbor].beatSpansByMove[moveId];
      if (there == null) continue;
      for (final h in here) {
        if (there.any(h.overlaps)) return true;
      }
    }
    return false;
  }

  bool _isPhraseCollision(int rowIndex, String moveId) {
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

/// Column key for a [figure] under [taxonomy]: custom figures all map to
/// [customMove]; `swing` maps to a compound `swing:<role>` key (widened to
/// `swing:<role>:<prefix>` for a `balance`/`meltdown` prefix); `allemande` and
/// `chain` map to `allemande:<role>` / `chain:<role>`; `hey` maps to
/// `hey:<length>` (issue #933 extends the existing swing/hey split mechanism
/// to allemande, chain, and swing's prefix). Every other figure maps to its
/// raw move id — aliases are intentionally NOT resolved for a non-split
/// target, so a "see saw" column stays distinct from "do si do" — EXCEPT an
/// alias whose target move IS itself split, like `meltdown_swing` -> `swing`:
/// reading [Taxonomy.effectiveParams] (which folds the alias's pinned params
/// in) naturally routes it to `swing:<role>:meltdown` instead of a stray
/// column of its own, with no special-case code needed here.
String columnKeyForFigure(Figure figure, Taxonomy taxonomy) {
  if (figure.isCustom) return customMove;
  final canonicalId = taxonomy.resolve(figure.move)?.id;
  switch (canonicalId) {
    case swingMoveId:
      final effective = taxonomy.effectiveParams(figure);
      return swingColumnKey(effective['who'], effective['prefix']);
    case heyMoveId:
      return heyColumnKey(figure.params['length']);
    case allemandeMoveId:
      return allemandeColumnKey(taxonomy.effectiveParams(figure)['who']);
    case chainMoveId:
      return chainColumnKey(taxonomy.effectiveParams(figure)['who']);
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
/// order) for known moves that appear, then any alias-only ids in taxonomy
/// alias-declaration order (e.g. `see_saw`, `swat_the_flea` — an alias whose
/// target move is itself split, like `meltdown_swing`, never reaches this
/// bucket; see [columnKeyForFigure]), then any truly unknown move ids (sorted,
/// for determinism), then a single trailing custom column when any custom
/// figure is present. This is stable — it doesn't reshuffle as the program
/// changes — and groups related moves the way the taxonomy authors intended.
///
/// `swing`, `allemande`, `chain`, and `hey` are split into sub-columns at
/// their taxonomy position (issue #933): swing and allemande/chain split by
/// role (`who`) into per-role columns (`larks`, `robins`, `shadow`, `ones`,
/// `twos`, `corners`, `same`, `other`, in that order); swing additionally
/// splits each role by `prefix` into a bare (`none`-prefix) column plus
/// `balance`/`meltdown` sub-columns. `partner`/`neighbor`'s BARE column is a
/// fixed baseline, shown whenever the program has any dances (even if no
/// dance swings those roles plain); every other swing role's bare column,
/// and every role's `balance`/`meltdown` sub-column regardless of role, is
/// present-only — so a program with only a `larks` swing that is ALWAYS
/// balance-prefixed shows `larks bal & swing` but no empty plain `larks
/// swing` column beside it (matching the present-only convention `hey` and
/// every non-baseline swing role already followed before this split). Only
/// `partner`/`neighbor`'s bare column is ever shown without a corresponding
/// present figure. Allemande/chain have no baseline at all, since most
/// programs use zero or one role for either. Hey splits into `half` then
/// `full`, both present-only.
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
///
/// [collisionMode] sets [ProgramMatrix.collisionMode] (issue #962), defaulting
/// to [MatrixCollisionMode.exactBeats] — the callers deriving the on-screen
/// matrix and its PDF export both read this from the "flag exact beat overlap
/// only" setting.
ProgramMatrix buildProgramMatrix(
  List<Dance> dances, {
  Taxonomy? taxonomy,
  List<ProgramHalf?>? halves,
  MatrixCollisionMode collisionMode = MatrixCollisionMode.exactBeats,
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
    final beatSpans = <String, List<BeatSpan>>{};
    // Phrase/beat positions are derived from cumulative *effective* beats
    // ([Taxonomy.effectiveParams]) — the taxonomy defaults and unknown-move
    // fallback the rest of the analysis uses — NOT raw [Figure.beats] (which is
    // 0 when a figure carries no explicitly-stored count, mislabelling every
    // such figure as A1 and producing false collisions). A figure is labelled
    // by the phrase it *starts* in; every figure (custom included) advances the
    // beat cursor so later figures land in the right phrase/position.
    final structure = dance.phraseStructure;
    var beat = 0;
    for (final figure in dance.figures) {
      final key = columnKeyForFigure(figure, tax);
      final effBeats = _effectiveBeats(tax, figure);
      rowMoves.add(key);
      if (key == customMove) {
        hasCustom = true;
      } else {
        present.add(key);
        // Track the phrase in which this move starts, and its exact beat
        // span, so strictly-adjacent dances can be checked for same-figure
        // collisions under either [MatrixCollisionMode]. Custom figures are
        // excluded (their column is un-comparable) but still advance the beat
        // cursor below.
        (phraseLabels[key] ??= <String>{}).add(
          labelForFigure(beat, effBeats, structure),
        );
        (beatSpans[key] ??= <BeatSpan>[]).add(BeatSpan(beat, effBeats));
      }
      beat += effBeats;
    }
    rows.add(
      MatrixRow(
        danceId: dance.id,
        title: dance.title,
        firstMoveId: dance.figures.isEmpty
            ? null
            : columnKeyForFigure(dance.figures.first, tax),
        presentMoveIds: rowMoves,
        phraseLabelsByMove: phraseLabels,
        beatSpansByMove: beatSpans,
        half: halves == null ? null : halves[i],
        formation: dance.formation,
      ),
    );
  }

  final columns = <MatrixColumn>[];
  final hasDances = dances.isNotEmpty;

  // Known moves in taxonomy definition order. `swing`, `allemande`, `chain`,
  // and `hey` expand into their split sub-columns (grouped, in variant order)
  // in place of a single column (issue #933); every other known move emits
  // one column when present.
  for (final id in tax.moves.keys) {
    if (id == swingMoveId) {
      // For EACH role variant: the bare (none-prefix) column is a fixed
      // baseline ONLY for partner/neighbor (`hasDances`); every other role's
      // bare column is present-only, keyed independently of its
      // balance/meltdown sub-columns — so a role that's ALWAYS prefixed
      // (e.g. only ever a `larks bal & swing`) shows just that sub-column,
      // never an empty plain `larks swing` beside it (issue #933 code
      // review: confirmed intentional, matching `hey`'s present-only
      // convention, and locked in by a test).
      for (final variant in _swingVariantOrder) {
        final baseline = swingBaselineVariants.contains(variant);
        final basePresent = present.remove('$swingMoveId:$variant');
        if (baseline ? hasDances : basePresent) {
          columns.add(_splitColumn(swingMoveId, variant));
        }
        for (final prefixVariant in _swingPrefixVariantOrder) {
          if (present.remove('$swingMoveId:$variant:$prefixVariant')) {
            columns.add(_splitColumn(swingMoveId, '$variant:$prefixVariant'));
          }
        }
      }
    } else if (id == heyMoveId) {
      for (final variant in _heyVariantOrder) {
        if (present.remove('$heyMoveId:$variant')) {
          columns.add(_splitColumn(heyMoveId, variant));
        }
      }
    } else if (id == allemandeMoveId) {
      for (final variant in _roleVariantOrder) {
        if (present.remove('$allemandeMoveId:$variant')) {
          columns.add(_splitColumn(allemandeMoveId, variant));
        }
      }
    } else if (id == chainMoveId) {
      for (final variant in _roleVariantOrder) {
        if (present.remove('$chainMoveId:$variant')) {
          columns.add(_splitColumn(chainMoveId, variant));
        }
      }
    } else if (present.remove(id)) {
      columns.add(MatrixColumn(moveId: id, kind: MatrixColumnKind.known));
    }
  }

  // Aliases whose TARGET move is not itself split (e.g. `see_saw` ->
  // `do_si_do`, `swat_the_flea` -> `box_the_gnat`) keep their own column,
  // distinct from their target's ([columnKeyForFigure] never resolves them) —
  // but they ARE taxonomy entities, not unrecognized ids, so they're
  // classified [MatrixColumnKind.known] (issue #933) rather than falling into
  // the sorted-unknown bucket below, ordered here in taxonomy alias
  // declaration order. An alias whose target IS split (`meltdown_swing` ->
  // `swing`) never reaches this loop: [columnKeyForFigure] folds it into the
  // target's split column via its pinned param, so its raw alias id is never
  // added to `present`.
  for (final alias in tax.aliases.values) {
    if (present.remove(alias.id)) {
      columns.add(MatrixColumn(moveId: alias.id, kind: MatrixColumnKind.known));
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
    collisionMode: collisionMode,
  );
}

/// Human label for a matrix [column] under [dialect], routed through the same
/// display path as figure rendering so column headers honour the active
/// dialect.
///
/// - custom → "Custom";
/// - split → the parent move's dialect-aware name qualified by the variant:
///   swing/allemande/chain role columns read `<role> <move>` ('partner swing',
///   'lark allemande', …) — larks/robins route through
///   [FigureRenderer.displayToken] so role dialects (Larks/Robins,
///   Gents/Ladies, …) are honoured; swing's `balance`/`meltdown` prefix
///   widens the move word to a short HEADER-ONLY form (`bal & swing`,
///   `meltdown swing` — issue #933); hey columns read `<length> <hey>`
///   ('half hey' / 'full hey');
/// - known → an ALIAS column (e.g. `see_saw`) is labelled under its OWN
///   display name, never its target's — resolving through to the target
///   would make two visually distinct figures share one header (issue #933).
///   The dialect-substitution lookup keys off the CANONICAL move id either
///   way (matching [FigureRenderer.displayMoveName]'s rule, since
///   `dialect.moves` is keyed by canonical id, not alias id). Side-dependent
///   substitutions (those using `%S`, which need a specific figure's
///   shoulder/hand) can't be resolved at the column level, so they fall back
///   to the display name;
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
  final alias = taxonomy.aliases[column.moveId];
  final displayName = alias?.displayName ?? def.displayName;
  final substitution = dialect.moves[def.id];
  if (substitution != null && !substitution.contains('%S')) {
    return substitution;
  }
  return displayName;
}

/// Dialect-aware display word for a (taxonomy-known) [moveId] — the same
/// resolution [matrixColumnLabel] uses for known columns, reused for the
/// parent-move word of a split column.
String _splitMoveWord(String moveId, Taxonomy taxonomy, Dialect dialect) {
  final substitution = dialect.moves[moveId];
  if (substitution != null && !substitution.contains('%S')) return substitution;
  return taxonomy.resolve(moveId)?.displayName ?? moveId;
}

/// Dialect-aware role-group column label: `<role term> <moveWord>` (e.g.
/// 'partner swing', 'lark allemande'), shared by swing/allemande/chain's role
/// split (issue #933 mirrors swing's existing role split onto
/// allemande/chain). Role columns honour the active dialect's role term
/// (singular) for larks/robins; `same` reads 'same-role'; an unrecognized
/// role (`other`) reads `<moveWord> (other)` rather than a role prefix, since
/// there's no role term to show.
String _roleColumnLabel(String role, String moveWord, Dialect dialect) {
  switch (role) {
    // Role columns honour the active dialect's role term (singular). `spec`
    // is intentionally `null`: role1/role2 are in [roleTokens], so
    // [FigureRenderer.displayToken] resolves them from the dialect's role
    // term alone and never consults `spec`.
    case 'larks':
      return '${FigureRenderer.displayToken('role1', null, dialect)} '
          '$moveWord';
    case 'robins':
      return '${FigureRenderer.displayToken('role2', null, dialect)} '
          '$moveWord';
    case 'partner':
      return 'partner $moveWord';
    case 'neighbor':
      return 'neighbor $moveWord';
    case 'shadow':
      return 'shadow $moveWord';
    case 'ones':
      return 'ones $moveWord';
    case 'twos':
      return 'twos $moveWord';
    case 'corners':
      return 'corners $moveWord';
    case 'same':
      return 'same-role $moveWord';
    default:
      return '$moveWord (other)';
  }
}

/// Header for a [MatrixColumnKind.split] column.
String _splitColumnLabel(
  MatrixColumn column,
  Taxonomy taxonomy,
  Dialect dialect,
) {
  final variant = column.variant!;
  if (column.baseMoveId == heyMoveId) {
    // variant is 'half' / 'full'.
    return '$variant ${_splitMoveWord(heyMoveId, taxonomy, dialect)}';
  }
  if (column.baseMoveId == allemandeMoveId) {
    return _roleColumnLabel(
      variant,
      _splitMoveWord(allemandeMoveId, taxonomy, dialect),
      dialect,
    );
  }
  if (column.baseMoveId == chainMoveId) {
    return _roleColumnLabel(
      variant,
      _splitMoveWord(chainMoveId, taxonomy, dialect),
      dialect,
    );
  }
  // swing: variant is `<role>` (prefix `none`) or `<role>:<prefix>` (issue
  // #933's balance/meltdown prefix split). The prefix word here is a short
  // HEADER-ONLY abbreviation ('bal &' for balance) distinct from the figure
  // renderer's fuller wording ('balance and'/'balance &' — see
  // `renderer.dart`'s `_renderPrefix`): the 64px column header has no room
  // for the longer form (maintainer decision), so the two intentionally
  // diverge rather than sharing one vocabulary.
  final parts = variant.split(':');
  final role = parts[0];
  final prefix = parts.length > 1 ? parts[1] : null;
  final swing = _splitMoveWord(swingMoveId, taxonomy, dialect);
  final moveWord = switch (prefix) {
    'balance' => 'bal & $swing',
    'meltdown' => 'meltdown $swing',
    _ => swing,
  };
  return _roleColumnLabel(role, moveWord, dialect);
}
