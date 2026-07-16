import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';

/// Scrubs a piece of imported figure free-text through the same chokepoint the
/// other import adapters use, so a `custom` figure reads consistently no matter
/// which source it came from.
///
/// Three steps, in order:
/// 1. Legacy move terms are normalised to their canonical taxonomy spelling so
///    the recognizer matches them:
///    - `gypsy`/`gypsies` is rewritten to `shoulder round`/`shoulder rounds`
///      (The Caller's Box applied this globally in Oct 2025; we normalise on
///      import so historical decks match).
///    - the hyphenated `do-si-do` is rewritten to `do si do` (The Caller's Box
///      hyphenates it exclusively, but the figure parser tokenises on spaces
///      and only matches the space-separated `do si do` / `dosido` forms).
/// 2. The text is routed through the core canonicalization chokepoint
///    [canonicalizeText] with [Dialect.canonical], whose always-on
///    substitutions map gendered role terms to canonical `role1`/`role2`
///    tokens; the renderer later re-expresses those in the reader's active
///    dialect.
/// 3. Runs of whitespace are collapsed to a single space and the result is
///    trimmed, so text extracted from wrapped/inline markup (e.g. the ContraDB
///    HTML page) does not leave doubled spaces or stray newlines. Inputs
///    without repeated whitespace (typical CallersBox / Caller's Companion
///    figure strings) are unchanged by this step.
///
/// This is the single shared implementation every free-text import adapter uses
/// (`CallersBoxAdapter`, `ContraDbHtmlAdapter`, and the Caller's Companion
/// `.USR` path via `mapCallersCompanionDance`), so a `custom` figure reads
/// consistently no matter which source it came from.
String scrubFigureText(String text) {
  final degypsied = text
      .replaceAllMapped(_gypsiesTerm, (_) => 'shoulder rounds')
      .replaceAllMapped(_gypsyTerm, (_) => 'shoulder round')
      .replaceAllMapped(_doSiDoTerm, (_) => 'do si do');
  final canonical = canonicalizeText(degypsied, Dialect.canonical);
  return canonical.replaceAll(_whitespace, ' ').trim();
}

final RegExp _gypsyTerm = RegExp(r'\bgypsy\b', caseSensitive: false);
final RegExp _gypsiesTerm = RegExp(r'\bgypsies\b', caseSensitive: false);
final RegExp _doSiDoTerm = RegExp(r'\bdo-si-do\b', caseSensitive: false);
final RegExp _whitespace = RegExp(r'\s+');
