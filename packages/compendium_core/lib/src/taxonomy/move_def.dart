import 'package:meta/meta.dart';

import 'param_types.dart';

/// Definition of one canonical move. All metadata for a move lives here —
/// no parallel tables (ContraDB pitfall #5).
@immutable
class MoveDef {
  const MoveDef({
    required this.id,
    required this.displayName,
    this.params = const {},
    required this.renderTemplate,
    this.searchKeywords = const [],
    this.goodBeats,
    this.paramBeats,
  });

  /// Permanent snake_case identifier (e.g. `shoulder_round`). Never renamed;
  /// renames are data migrations.
  final String id;

  /// Default English display name; dialect may override.
  final String displayName;

  /// Named parameter specs, in canonical display order.
  final Map<String, ParamSpec> params;

  /// Canonical text template with `{param}` placeholders (plus the implicit
  /// `{move}` for the display name), e.g. `"{who} allemande {hand} {turn}"`.
  final String renderTemplate;

  /// Extra search terms, including legacy names ("gypsy" → shoulder round)
  /// so searches by older users still match.
  final List<String> searchKeywords;

  /// Beat counts considered musically typical. Deviations are warnings,
  /// never errors. Null/empty = any beat count is fine.
  final List<int>? goodBeats;

  /// For the few moves whose canonical beat count depends on the *value* of
  /// one of their parameters (e.g. a half vs. full hey), the driver parameter
  /// and its per-value beat counts. Null for the vast majority of moves, which
  /// take the flat `beats` spec default. See [ParamBeats].
  final ParamBeats? paramBeats;
}

/// The driver parameter and per-value beat counts for a move whose canonical
/// duration depends on a parameter *value* rather than a single per-move
/// default (e.g. a half hey is 8 beats, a full hey 16). Attached to a
/// [MoveDef] via [MoveDef.paramBeats]; [Taxonomy.effectiveParams] uses it to
/// derive `beats` when a figure does not carry an explicit value.
@immutable
class ParamBeats {
  const ParamBeats({required this.param, required this.byValue});

  /// Name of the parameter whose value selects the beat count.
  final String param;

  /// Canonical beats for each value of [param]. A value absent here falls back
  /// to the move's flat `beats` spec default.
  final Map<Object?, int> byValue;
}

/// An alias entry: resolves to a canonical move with pinned params
/// (e.g. `see saw` → `do_si_do{shoulder: left}`).
///
/// When [inversePairId] is set, this alias is one half of a two-valued
/// inverse pair: toggling the pinned param to its opposite value should
/// re-route the figure to [inversePairId] (and vice versa). The taxonomy's
/// [Taxonomy.resolvedMoveId] uses this to enforce the invariant at write
/// time.
@immutable
class MoveAlias {
  const MoveAlias({
    required this.id,
    required this.displayName,
    required this.targetMove,
    this.pinnedParams = const {},
    this.searchKeywords = const [],
    this.inversePairId,
  });

  final String id;
  final String displayName;
  final String targetMove;
  final Map<String, Object?> pinnedParams;
  final List<String> searchKeywords;

  /// The id of the counterpart alias (or move) that this alias forms an
  /// inverse pair with. For `swat_the_flea` (pins `hand: left`), this is
  /// `'box_the_gnat'`; for `see_saw` (pins `shoulder: left`), this is
  /// `'do_si_do'`. `null` when the alias is not part of an inverse pair
  /// (e.g. `meltdown_swing`).
  final String? inversePairId;
}
