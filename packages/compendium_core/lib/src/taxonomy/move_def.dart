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
    this.progressionCapable = false,
    required this.renderTemplate,
    this.searchKeywords = const [],
    this.goodBeats,
  });

  /// Permanent snake_case identifier (e.g. `shoulder_round`). Never renamed;
  /// renames are data migrations.
  final String id;

  /// Default English display name; dialect may override.
  final String displayName;

  /// Named parameter specs, in canonical display order.
  final Map<String, ParamSpec> params;

  /// Whether this move can carry the progression point.
  final bool progressionCapable;

  /// Canonical text template with `{param}` placeholders (plus the implicit
  /// `{move}` for the display name), e.g. `"{who} allemande {hand} {turn}"`.
  final String renderTemplate;

  /// Extra search terms, including legacy names ("gypsy" → shoulder round)
  /// so searches by older users still match.
  final List<String> searchKeywords;

  /// Beat counts considered musically typical. Deviations are warnings,
  /// never errors. Null/empty = any beat count is fine.
  final List<int>? goodBeats;
}

/// An alias entry: resolves to a canonical move with pinned params
/// (e.g. `see saw` → `do_si_do{shoulder: left}`).
@immutable
class MoveAlias {
  const MoveAlias({
    required this.id,
    required this.displayName,
    required this.targetMove,
    this.pinnedParams = const {},
    this.searchKeywords = const [],
  });

  final String id;
  final String displayName;
  final String targetMove;
  final Map<String, Object?> pinnedParams;
  final List<String> searchKeywords;
}
