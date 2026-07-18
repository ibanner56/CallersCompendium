import 'package:collection/collection.dart';

import '../dialect/dialect.dart';
import '../dialect/renderer.dart' show roleTokens;

const MapEquality<Object?, Object?> _mapEq = MapEquality<Object?, Object?>();

/// Always-on, dialect-agnostic reverse-synonym maps used to enrich a *search*
/// query so a user's saved-dialect vocabulary resolves regardless of which
/// single dialect is currently active.
///
/// This is deliberately **search-specific** and reverse-only (display term →
/// canonical token). It is NOT a [Dialect]: it carries no render direction and
/// no name, so it can never be mistaken for the active dialect when rendering.
///
/// Layering (applied by the search canonicalization boundary): the built-in
/// legacy synonyms and the active dialect always win; this enrichment fills in
/// only where they leave a term unclaimed. Consequently, passing an empty
/// enrichment leaves canonicalization byte-for-byte unchanged.
///
/// Core stays Flutter-free: the app assembles the set of the user's saved
/// dialects (from its dialect library) and hands them to [fromDialects]; core
/// only ever sees plain [Dialect]s and maps.
class SearchEnrichment {
  SearchEnrichment({
    Map<String, String> roleSynonyms = const {},
    Map<String, String> moveSynonyms = const {},
  }) : roleSynonyms = Map.unmodifiable(roleSynonyms),
       moveSynonyms = Map.unmodifiable(moveSynonyms);

  /// The identity enrichment: adds nothing. Search behaves exactly as before.
  static final SearchEnrichment empty = SearchEnrichment();

  /// Lowercased role display term (singular or plural) → canonical role token
  /// (`role1`/`role2`/`role1s`/`role2s`). Stored as an unmodifiable view;
  /// callers must not mutate it.
  final Map<String, String> roleSynonyms;

  /// Lowercased move display substitution → canonical move id. Templated
  /// (`%S`) substitutions are excluded (not reversible by a plain word match),
  /// mirroring the active-dialect move reversal in the filter compiler. Stored
  /// as an unmodifiable view; callers must not mutate it.
  final Map<String, String> moveSynonyms;

  bool get isEmpty => roleSynonyms.isEmpty && moveSynonyms.isEmpty;

  /// Builds the union of role and move reverse-mappings across every dialect in
  /// [dialects] (typically the user's whole saved library: presets + custom).
  ///
  /// Collision rule (deterministic, no arbitrary pick): a display term that
  /// maps to two **different** canonical tokens across the supplied dialects is
  /// **dropped** entirely; same-target duplicates are kept. Terms that collide
  /// with a canonical token itself (e.g. a display term literally `role1`) are
  /// dropped so they can't shadow the pass-through of typed canonical tokens.
  /// Templated (`%S`) move substitutions are skipped.
  ///
  /// This union never overrides the built-in legacy synonyms or the active
  /// dialect — that precedence is enforced where the maps are applied — so it
  /// is safe to include the active dialect (and presets) in [dialects].
  factory SearchEnrichment.fromDialects(Iterable<Dialect> dialects) {
    final roles = _UnionBuilder();
    final moves = _UnionBuilder();

    for (final dialect in dialects) {
      for (final entry in dialect.roles.entries) {
        final token = entry.key;
        roles.add(entry.value.singular.toLowerCase(), token);
        roles.add(entry.value.plural.toLowerCase(), '${token}s');
      }
      for (final entry in dialect.moves.entries) {
        final display = entry.value;
        if (display.contains('%S')) continue;
        moves.add(display.toLowerCase(), entry.key);
      }
    }

    return SearchEnrichment(
      roleSynonyms: roles.build(),
      moveSynonyms: moves.build(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchEnrichment &&
      _mapEq.equals(other.roleSynonyms, roleSynonyms) &&
      _mapEq.equals(other.moveSynonyms, moveSynonyms);

  @override
  int get hashCode =>
      Object.hash(_mapEq.hash(roleSynonyms), _mapEq.hash(moveSynonyms));
}

/// Accumulates `display → canonical` mappings across dialects, dropping any
/// display term seen with two different targets (or one that is itself a
/// canonical role token).
class _UnionBuilder {
  final Map<String, String> _map = {};
  final Set<String> _dropped = {};

  void add(String display, String canonical) {
    if (display.isEmpty || _dropped.contains(display)) return;
    // A display term identical to a canonical role token must not shadow the
    // pass-through of typed canonical tokens.
    if (roleTokens.contains(display)) {
      _dropped.add(display);
      _map.remove(display);
      return;
    }
    final existing = _map[display];
    if (existing == null) {
      _map[display] = canonical;
    } else if (existing != canonical) {
      _dropped.add(display);
      _map.remove(display);
    }
  }

  Map<String, String> build() => Map.unmodifiable(_map);
}
