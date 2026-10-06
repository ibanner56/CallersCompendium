import '../model/figure.dart' show customMoveId;
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
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

/// The single canonicalization chokepoint (dialect design §"Canonicalization
/// on input"). Inverse-maps the user's active dialect role terms — plus known
/// legacy synonyms — back to canonical role tokens before persistence, so
/// storage and search stay dialect-agnostic. Conservative: only exact,
/// word-boundary term matches are rewritten; unknown prose is left as typed.
///
/// A role term that is also a move word is kept as typed: "robin" in the move
/// name "mad robin", and — when the active dialect's terms are "lead" and
/// "follow" — those words used as verbs ("Ones lead down the hall"). The rules
/// are on [RoleCanonicalizer].
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
