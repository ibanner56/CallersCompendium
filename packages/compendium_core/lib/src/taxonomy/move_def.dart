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
  const ParamBeats({
    required this.param,
    required this.byValue,
    this.beatsPerAmount,
  });

  /// Name of the parameter whose value selects the beat count.
  final String param;

  /// Canonical beats for each value of [param]. A value absent here falls back
  /// to [beatsPerAmount] when that applies, else to the move's flat `beats`
  /// spec default.
  final Map<Object?, int> byValue;

  /// For a [ParamKind.fraction] driver: beats per full amount, applied to the
  /// amount an `other` fraction states (`statedFractionAmount`). `figure_8`
  /// sets 16, ContraDB's `half_or_full * 16` carried past `full` (a 1½ figure
  /// 8 is 24 beats). Null, or an `other` that states no amount, falls back to
  /// the flat default.
  final int? beatsPerAmount;

  /// The beats these rules derive from a figure's [effective] params, or null
  /// when they derive none.
  int? derive(Map<String, Object?> effective) {
    final byName = byValue[effective[param]];
    if (byName != null) return byName;
    final perAmount = beatsPerAmount;
    if (perAmount == null) return null;
    final amount = statedFractionAmount(effective, fractionParam: param);
    return amount == null ? null : (amount * perAmount).round();
  }
}

/// An alias entry: resolves to a canonical move with pinned params
/// (e.g. `see saw` → `do_si_do{shoulder: left}`).
///
/// When [inversePairId] is set, this alias is one half of an inverse pair:
/// moving the pinned param off the pinned value should re-route the figure
/// to [inversePairId], and that move taking the pinned value should re-route
/// it back. The axis need not be two-valued: `long_lines` pins
/// `forward_and_back.formation` to one of twelve formations, and any other
/// formation is a `forward_and_back`. The taxonomy's
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
    this.listedAsMove = false,
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

  /// Whether this alias stands as a move of its own outside the taxonomy:
  /// pickers that offer moves and not aliases (the dialect editor, Advanced
  /// search's "Has figure", Settings' per-move defaults) offer it too, without
  /// its pinned params, and a dialect's name and wording for it apply to it
  /// while its target's never do. False for every alias but `long_lines`
  /// (taxonomy v39), which was a move until then: its figures are stored
  /// under its own id, so a search must be able to name it; dialects hold
  /// entries keyed on it; and its name is a formation where its target's,
  /// `forward_and_back`, is a direction, so a name for one would misread the
  /// other. Every other alias takes its target's dialect entries.
  final bool listedAsMove;
}
