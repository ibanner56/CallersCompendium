import '../model/figure.dart' show customMoveId;
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
import 'discouraged_terms.dart';
import 'renderer.dart';
import 'role_canonicalizer.dart';
import 'substitution.dart';

/// The result of canonicalizing free text: the rewritten [text] plus the
/// spans of any discouraged terms found (for the editor "lingo line"; they
/// are flagged, never blocked or rewritten).
class CanonicalizationResult {
  const CanonicalizationResult(this.text, this.discouraged);

  final String text;
  final List<({String text, int start})> discouraged;
}

/// The role rewriter [canonicalize] uses for [Dialect.canonical] with no extra
/// synonyms — the only configuration the import path uses.
///
/// Building a [RoleCanonicalizer] sorts every key and compiles
/// Unicode-lookbehind patterns, which is a measurable share of a large import
/// when repeated for every figure line. Both inputs are fixed for the process
/// ([Dialect.canonical] is an immutable singleton), so the result is a pure
/// function of the text. (Per isolate: a static.) Other dialects without extra
/// synonyms are memoised by value in [_dialectRoles]; any [extraRoleSynonyms]
/// (search only) is built per call. (Display rendering is separate:
/// `FigureRenderer.renderFreeText*` caches its substitutors per [Dialect]
/// value, in `renderer.dart`.)
final RoleCanonicalizer _canonicalRoles = RoleCanonicalizer(Dialect.canonical);

/// The discouraged-term matcher for [Dialect.canonical], built once.
final Substitutor? _canonicalDiscouraged = _discouragedFor(Dialect.canonical);

/// Per-[Dialect] memo of role rewriters, cleared when it passes
/// [_maxDialectRoles] so editing a custom dialect cannot grow it without bound.
final Map<Dialect, RoleCanonicalizer> _dialectRoles = {};
const int _maxDialectRoles = 16;

RoleCanonicalizer _rolesFor(
  Dialect dialect,
  Map<String, String> extraRoleSynonyms,
) {
  if (extraRoleSynonyms.isNotEmpty) {
    return RoleCanonicalizer(dialect, extraRoleSynonyms: extraRoleSynonyms);
  }
  if (identical(dialect, Dialect.canonical)) return _canonicalRoles;
  final cached = _dialectRoles[dialect];
  if (cached != null) return cached;
  if (_dialectRoles.length >= _maxDialectRoles) _dialectRoles.clear();
  return _dialectRoles[dialect] = RoleCanonicalizer(dialect);
}

Substitutor? _discouragedFor(Dialect dialect) =>
    dialect.discouragedTerms.isEmpty
    ? null
    : Substitutor({
        for (final t in dialect.discouragedTerms) t: t,
      }, caseInsensitive: true);

/// The canonicalization chokepoint (dialect design §"Canonicalization on
/// input"); user-glossary text has its own variant,
/// [canonicalizeGlossaryText]. Inverse-maps the user's active dialect role
/// terms — plus known legacy synonyms — back to canonical role tokens before
/// persistence, so storage and search stay dialect-agnostic. Conservative:
/// only exact, word-boundary term matches are rewritten; unknown prose is
/// left as typed.
///
/// A role term that is also a move word is not rewritten to a role: "robin" in
/// the move name "mad robin" (which is written in lowercase, "mad robin", as
/// imports store it), and — when the active dialect's terms are "lead" and
/// "follow" — those words used as verbs ("Ones lead down the hall"), which are
/// kept as typed. The rules are on [RoleCanonicalizer].
///
/// [extraRoleSynonyms] is an optional, always-on reverse map (display term →
/// canonical role token) used only by the *search* path to resolve role terms
/// from the union of every saved dialect (see `SearchEnrichment`). It is
/// layered *underneath* the legacy synonyms and the active dialect, so it never
/// overrides them and an empty map (the default — used by the storage/entry
/// path) leaves output byte-for-byte unchanged.
CanonicalizationResult canonicalize(
  String text,
  Dialect dialect, {
  Map<String, String> extraRoleSynonyms = const {},
}) {
  final discouraged = identical(dialect, Dialect.canonical)
      ? _canonicalDiscouraged
      : _discouragedFor(dialect);
  return CanonicalizationResult(
    _rolesFor(dialect, extraRoleSynonyms).canonicalize(text),
    discouraged?.matches(text) ?? const <({String text, int start})>[],
  );
}

/// Convenience: canonical text only (drops the discouraged-term spans), and
/// skips the discouraged-term scan.
String canonicalizeText(
  String text,
  Dialect dialect, {
  Map<String, String> extraRoleSynonyms = const {},
}) => _rolesFor(dialect, extraRoleSynonyms).canonicalize(text);

/// Per-[Dialect] memo of the user-glossary role rewriters, bounded like
/// [_dialectRoles].
final Map<Dialect, RoleCanonicalizer> _glossaryRoles = {};

/// Per-[Dialect] memo of the built-in discouraged terms as stored text,
/// bounded like [_dialectRoles].
final Map<Dialect, Substitutor> _glossaryDiscouraged = {};

/// The built-in discouraged terms as stored text, with [dialect]'s own role
/// words that hold one ([claimedRoleWords]) mapped to themselves, possessives
/// included. Longest match wins, so "lady birds" in a dialect whose role1 is
/// "Lady Bird" is kept whole for the role canonicalizer, while "lady" alone
/// still reads by the table; and where the role word is the term itself,
/// such as "ravens" for a role1 "Raven", the dialect's meaning replaces the
/// table's.
Substitutor _glossaryDiscouragedFor(Dialect dialect) {
  final cached = _glossaryDiscouraged[dialect];
  if (cached != null) return cached;
  if (_glossaryDiscouraged.length >= _maxDialectRoles) {
    _glossaryDiscouraged.clear();
  }
  return _glossaryDiscouraged[dialect] = Substitutor({
    ...storedDiscouragedTerms,
    for (final word in claimedRoleWords(dialect))
      // The forms the table's own keys take: plain, `'` and `'s`/`’s`.
      for (final form in [word, "$word'", "$word's", '$word’s']) form: form,
  }, caseInsensitive: true);
}

/// Canonicalizes text a user typed into their own glossary — a compound
/// figure's name, definition, description and notes, and their notes on
/// shipped figures (#709). Notes on a dance's figures keep [canonicalize].
///
/// Stricter than [canonicalizeText] in one way and wider in another, for this
/// text only. The maintainer decided the stored discouraged terms and the
/// singular-role-term subject exception (2026-10-14); what else counts as a
/// subject is the implementer's choice (see `docs/design/dialect.md`):
/// - the built-in discouraged terms are stored canonically ("ladies" →
///   `role2s`, "gypsy" → "shoulder round"), not kept as typed. The table is
///   the built-in one the renderer displays them from, not [dialect]'s own
///   editable list; a role word of [dialect] that is or holds one of its
///   terms keeps the dialect's meaning (the implementer's choices, see
///   `docs/design/dialect.md`);
/// - under a dialect whose roles are "lead"/"follow", "leads"/"follows"
///   directly after a singular subject is the verb ("The robin follows the
///   lark across" → "The role2 follows the role1 across", "The caller
///   follows the music" is kept), where [canonicalizeText] would read it as
///   the plural role. What counts as a singular subject is
///   `RoleCanonicalizer`'s `_followsSingularSubject`.
///
/// Everything else is [canonicalizeText]'s behaviour, so "leads cross +
/// follows loop" still becomes "role1s cross + role2s loop".
String canonicalizeGlossaryText(String text, Dialect dialect) {
  if (text.isEmpty) return text;
  var roles = _glossaryRoles[dialect];
  if (roles == null) {
    if (_glossaryRoles.length >= _maxDialectRoles) _glossaryRoles.clear();
    roles = _glossaryRoles[dialect] = RoleCanonicalizer(
      dialect,
      subjectVerbException: true,
    );
  }
  return roles.canonicalize(_glossaryDiscouragedFor(dialect).apply(text));
}

/// Rewrites taxonomy move display names and legacy keywords to their canonical
/// display names for full-text search. Unlike role canonicalization, this is
/// intentionally query-only: persisted figure text is produced by the renderer
/// and remains canonical without storing duplicate legacy spellings.
String canonicalizeMoveSearchText(String text, Taxonomy taxonomy) {
  final replacements = <String, String>{};
  for (final move in taxonomy.moves.values) {
    if (move.id == customMoveId) continue;
    replacements[move.displayName] = move.displayName;
    for (final keyword in move.searchKeywords) {
      replacements[keyword] = move.displayName;
    }
  }
  for (final alias in taxonomy.aliases.values) {
    replacements[alias.displayName] = alias.displayName;
    for (final keyword in alias.searchKeywords) {
      replacements[keyword] = alias.displayName;
    }
  }
  return Substitutor(replacements, caseInsensitive: true).apply(text);
}

/// Whether [token] is one of the canonical role tokens.
bool isRoleToken(String token) => roleTokens.contains(token);

/// Canonical role tokens typed directly (e.g. data loaded from storage).
final Substitutor _roleTokenMatcher = Substitutor({
  for (final t in roleTokens) t: t,
}, caseInsensitive: true);

/// Returns spans in [text] that are recognised as role terms, for the editor
/// "lingo line" underline. Covers:
///  - the active [dialect]'s configured role display-terms,
///  - built-in legacy/synonym role terms (gent, lark, robin, lady, etc.),
///  - canonical role tokens typed directly (e.g. `role1`, `role2s`).
///
/// A role term that [canonicalize] keeps as a move word ("robin" in "mad
/// robin", a verb "lead" under Leads/Follows) is not a role span, so the
/// underline agrees with what a save stores.
///
/// All returned spans hold positions in the original [text].
List<({String text, int start})> roleSpans(String text, Dialect dialect) {
  if (text.isEmpty) return const [];
  final spans = <({String text, int start})>[
    for (final d in _rolesFor(dialect, const {}).analyze(text))
      if (d.kind == RoleSpanKind.role) (text: d.text, start: d.start),
    ..._roleTokenMatcher.matches(text),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

/// Returns spans in [text] that are recognised as taxonomy move keywords, for
/// the editor "lingo line" dotted-underline.  Covers each [MoveDef] and
/// [MoveAlias] `displayName` and `searchKeywords` (e.g. 'swing', 'petronella',
/// 'do si do', 'gypsy' → shoulder_round's legacy keyword).  The generic
/// `custom` move is excluded.
///
/// Matching is case-insensitive and word/phrase-boundary-aware: single-word
/// names ('swing') use the same `(?<![\w])...(?![\w])` boundaries as
/// [roleSpans]; multi-word phrases ('do si do', 'right left through') match the
/// phrase as a unit — boundaries apply only at the phrase start and end, not
/// at internal spaces.
///
/// All returned spans hold positions in the original [text].
List<({String text, int start})> moveKeywordSpans(
  String text,
  Taxonomy taxonomy,
) {
  if (text.isEmpty) return const [];
  // Build a keyword → id map (values aren't used by .matches(); any non-empty
  // string works as the map value).
  final keywords = <String, String>{};
  for (final move in taxonomy.moves.values) {
    if (move.id == customMoveId) continue;
    keywords[move.displayName.toLowerCase()] = move.id;
    for (final kw in move.searchKeywords) {
      if (kw.isNotEmpty) keywords[kw.toLowerCase()] = move.id;
    }
  }
  for (final alias in taxonomy.aliases.values) {
    keywords[alias.displayName.toLowerCase()] = alias.id;
    for (final kw in alias.searchKeywords) {
      if (kw.isNotEmpty) keywords[kw.toLowerCase()] = alias.id;
    }
  }
  return Substitutor(keywords, caseInsensitive: true).matches(text);
}
