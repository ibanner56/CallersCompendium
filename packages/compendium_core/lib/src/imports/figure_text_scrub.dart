import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';

/// Scrubs a piece of imported figure free-text through the same chokepoint the
/// other import adapters use, so a `custom` figure reads consistently no matter
/// which source it came from.
///
/// Two steps, in order:
/// 1. The legacy move term `gypsy`/`gypsies` is rewritten to
///    `shoulder round`/`shoulder rounds` (The Caller's Box applied this
///    globally in Oct 2025; we normalise on import so historical decks match).
/// 2. The text is routed through the core canonicalization chokepoint
///    [canonicalizeText] with [Dialect.canonical], whose always-on
///    substitutions map gendered role terms to canonical `role1`/`role2`
///    tokens; the renderer later re-expresses those in the reader's active
///    dialect.
///
/// This is the single shared implementation the Caller's Companion `.USR`
/// adapter uses. The `CallersBoxAdapter` and `ContraDbHtmlAdapter` still carry
/// their own private `_scrub` copies today; consolidating all callers onto this
/// helper is left to the queued shared-parser/scrub-extraction phase (this
/// deliberately does not pre-empt that refactor — it just avoids adding a
/// fourth duplicated copy).
String scrubFigureText(String text) {
  final degypsied = text
      .replaceAllMapped(_gypsiesTerm, (_) => 'shoulder rounds')
      .replaceAllMapped(_gypsyTerm, (_) => 'shoulder round');
  return canonicalizeText(degypsied, Dialect.canonical);
}

final RegExp _gypsyTerm = RegExp(r'\bgypsy\b', caseSensitive: false);
final RegExp _gypsiesTerm = RegExp(r'\bgypsies\b', caseSensitive: false);
