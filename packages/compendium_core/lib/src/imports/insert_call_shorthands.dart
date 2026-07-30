import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'callers_companion_usr_archive.dart';
import 'figure_front_end_fan_out.dart';
import 'shorthand_mappings.dart';

/// One proposed shorthand seeded from a CC `InsertCall` button (issue #562).
///
/// A candidate carries the button's [token] (its `InsertButtonLabel`) and the
/// PRIMARY expansion ([figures]) that the button's call text structured to
/// through [parseFigureLinesFanOut]. When the button's ALT slot is a *different*
/// call that also structures cleanly, [altFigures] holds that alternative
/// expansion for the **same** token — CC toggles the two under one button, and a
/// shorthand token is unique, so the seeding UI offers primary OR alt and
/// persists exactly one [ShorthandMapping] per token (never two).
///
/// Every candidate is guaranteed seedable: [figures] is non-empty, within
/// [maxShorthandTargetFigures], and contains **no** custom figure (a button that
/// only parses to `custom` yields no candidate). The same holds for [altFigures]
/// when present.
@immutable
class ShorthandSeedCandidate {
  ShorthandSeedCandidate({
    required this.token,
    required List<Figure> figures,
    List<Figure>? altFigures,
    this.sourceText,
    this.altSourceText,
  }) : figures = List.unmodifiable(figures),
       altFigures = altFigures == null ? null : List.unmodifiable(altFigures);

  /// The proposed shorthand token (the sanitized `InsertButtonLabel`), original
  /// casing preserved for display.
  final String token;

  /// The primary expansion: ordered, non-empty, non-custom figures.
  final List<Figure> figures;

  /// The alternative expansion (the button's ALT call) when it is present and
  /// structures to non-custom figure(s); otherwise `null`. Offered for the SAME
  /// [token] as a user-selectable alternative to [figures].
  final List<Figure>? altFigures;

  /// The primary button call text, retained for preview/diagnostics.
  final String? sourceText;

  /// The alt button call text, retained for preview/diagnostics; `null` when
  /// there is no distinct, seedable alt.
  final String? altSourceText;

  /// Whether a seedable alternative expansion is available.
  bool get hasAlt => altFigures != null;

  /// The trimmed + lowercased token used for matching, uniqueness, and conflict
  /// detection against existing shorthands.
  String get normalizedToken => normalizeShorthandToken(token);

  /// The [ShorthandMapping] for the primary expansion.
  ShorthandMapping toPrimaryMapping() =>
      ShorthandMapping(token: token, figures: figures);

  /// The [ShorthandMapping] for the alternative expansion. Throws [StateError]
  /// when [hasAlt] is false — callers gate on [hasAlt] first.
  ShorthandMapping toAltMapping() {
    final alt = altFigures;
    if (alt == null) {
      throw StateError(
        'ShorthandSeedCandidate for "$token" has no alt figures',
      );
    }
    return ShorthandMapping(token: token, figures: alt);
  }
}

/// Builds the ordered list of [ShorthandSeedCandidate]s from a file's
/// [insertCalls] (issue #562).
///
/// For each button, the primary call text is structured through
/// [parseFigureLinesFanOut] against [taxonomy]; a button contributes a candidate
/// **only** when its primary expansion is non-empty, within
/// [maxShorthandTargetFigures], and entirely non-custom (a button that only
/// yields `custom` is dropped — no raw-text shorthands are seeded). The ALT call
/// is parsed the same way and attached when it is present, *differs* from the
/// primary text, and also structures non-custom.
///
/// Bounds mirror the shorthand store's persisted-decode guards so the seeded set
/// can never exceed what the store accepts:
/// - a token that is empty (after sanitize/trim) or longer than
///   [maxShorthandTokenLength] is skipped;
/// - candidates are deduped on [normalizeShorthandToken] (the FIRST button that
///   yields a candidate for a token wins — matching [ShorthandMappings.decode]'s
///   dedupe rule and CC's own first-writer-wins button ordering);
/// - at most [maxShorthandMappings] candidates are produced.
List<ShorthandSeedCandidate> buildInsertCallShorthandCandidates(
  Iterable<CcInsertCall> insertCalls, {
  required Taxonomy taxonomy,
}) {
  final result = <ShorthandSeedCandidate>[];
  final seen = <String>{};
  for (final button in insertCalls) {
    if (result.length >= maxShorthandMappings) break;
    final token = button.label.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) continue;

    // Primary must structure cleanly (non-custom) for the button to seed at all.
    final primary = _parseExpansion(button.text, button.beats, taxonomy);
    if (primary == null) continue;

    // Dedupe only among buttons that actually yield a candidate: keep the first,
    // matching the persisted-decode dedupe so seeding and reload agree.
    if (!seen.add(normalizeShorthandToken(token))) continue;

    final altText = button.altText;
    final hasDistinctAlt =
        altText != null &&
        altText.trim().isNotEmpty &&
        altText.trim() != button.text.trim();
    final alt = hasDistinctAlt
        ? _parseExpansion(altText, button.altBeats, taxonomy)
        : null;

    result.add(
      ShorthandSeedCandidate(
        token: token,
        figures: primary,
        altFigures: alt,
        sourceText: button.text,
        altSourceText: alt == null ? null : altText,
      ),
    );
  }
  return result;
}

/// Structures [text] through the free-text fan-out and returns the expansion
/// only when it is a usable seed: non-empty, within [maxShorthandTargetFigures],
/// and entirely non-custom. Returns `null` otherwise.
List<Figure>? _parseExpansion(String text, int beats, Taxonomy taxonomy) {
  final figures = parseFigureLinesFanOut(
    text,
    beats: beats,
    taxonomy: taxonomy,
  );
  if (figures.isEmpty || figures.length > maxShorthandTargetFigures) {
    return null;
  }
  if (figures.any((f) => f.isCustom)) return null;
  return figures;
}

/// The split of seed candidates by whether their token already names an existing
/// shorthand (issue #562): [conflicting] tokens must be **surfaced, not
/// overwritten**, and [seedable] tokens are safe to add. This is also what makes
/// re-import idempotent — after a first seed the tokens exist, so a second
/// import routes them all to [conflicting] and adds nothing.
@immutable
class ShorthandCandidatePartition {
  const ShorthandCandidatePartition({
    required this.seedable,
    required this.conflicting,
  });

  /// Candidates whose token does not collide with an existing shorthand.
  final List<ShorthandSeedCandidate> seedable;

  /// Candidates whose token already names an existing shorthand (surfaced to the
  /// user as "already defined", never overwritten).
  final List<ShorthandSeedCandidate> conflicting;
}

/// Partitions [candidates] against [existingNormalizedTokens] (already-normalized
/// via [normalizeShorthandToken]) into seedable vs. conflicting, preserving input
/// order within each bucket.
ShorthandCandidatePartition partitionInsertCallCandidates(
  Iterable<ShorthandSeedCandidate> candidates,
  Set<String> existingNormalizedTokens,
) {
  final seedable = <ShorthandSeedCandidate>[];
  final conflicting = <ShorthandSeedCandidate>[];
  for (final candidate in candidates) {
    if (existingNormalizedTokens.contains(candidate.normalizedToken)) {
      conflicting.add(candidate);
    } else {
      seedable.add(candidate);
    }
  }
  return ShorthandCandidatePartition(
    seedable: seedable,
    conflicting: conflicting,
  );
}
