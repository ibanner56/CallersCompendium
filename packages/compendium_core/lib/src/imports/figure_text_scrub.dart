import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../util/text_sanitizer.dart';

/// Scrubs a piece of imported figure free-text through the same chokepoint the
/// other import adapters use, so a `custom` figure reads consistently no matter
/// which source it came from.
///
/// Steps, in order:
/// 0. Disallowed control, bidi-override and invisible/format characters are
///    stripped up front via [sanitizeImportedText] (OWASP input hygiene against
///    display-spoofing, issue #444). Doing this *first* also stops an attacker
///    from smuggling a zero-width character mid-word to defeat the move
///    normalisation below (e.g. `gy<ZWSP>psy`).
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
  final sanitized = sanitizeImportedText(text);
  final normalizedMoves = sanitized
      .replaceAllMapped(_gypsiesTerm, (_) => 'shoulder rounds')
      .replaceAllMapped(_gypsyTerm, (_) => 'shoulder round')
      .replaceAllMapped(_doSiDoTerm, (_) => 'do si do')
      // Protect the move name "mad robin(s)" from role canonicalization: the
      // canonical dialect maps `robin(s)` → `role2(s)` (larks/robins), which
      // would otherwise mangle "mad robin" into "mad role2". Collapsing it to a
      // single non-role token first (no interior word boundary before `robin`)
      // hides it from the substitution; it is restored after canonicalization.
      .replaceAllMapped(_madRobinsTerm, (_) => _madRobinsSentinel)
      .replaceAllMapped(_madRobinTerm, (_) => _madRobinSentinel);
  final canonical = canonicalizeText(normalizedMoves, Dialect.canonical);
  final restored = canonical
      .replaceAll(_madRobinsSentinel, 'mad robins')
      .replaceAll(_madRobinSentinel, 'mad robin');
  return restored.replaceAll(_whitespace, ' ').trim();
}

const String _madRobinSentinel = 'madrobin';
const String _madRobinsSentinel = 'madrobins';

final RegExp _gypsyTerm = RegExp(r'\bgypsy\b', caseSensitive: false);
final RegExp _gypsiesTerm = RegExp(r'\bgypsies\b', caseSensitive: false);
final RegExp _doSiDoTerm = RegExp(r'\bdo-si-do\b', caseSensitive: false);
final RegExp _madRobinsTerm = RegExp(r'\bmad robins\b', caseSensitive: false);
final RegExp _madRobinTerm = RegExp(r'\bmad robin\b', caseSensitive: false);
final RegExp _whitespace = RegExp(r'\s+');
