import '../model/figure.dart' show customMoveId;
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
import 'renderer.dart';
import 'substitution.dart';

/// The result of canonicalizing free text: the rewritten [text] plus the
/// spans of any discouraged terms found (for the editor "lingo line"; they
/// are flagged, never blocked or rewritten).
class CanonicalizationResult {
  const CanonicalizationResult(this.text, this.discouraged);

  final String text;
  final List<({String text, int start})> discouraged;
}

/// Legacy/synonym terms that always map back to canonical role tokens,
/// independent of the active dialect, so older transcriptions and users
/// still resolve. Keys are lowercased.
const Map<String, String> _legacyRoleSynonyms = {
  'gent': 'role1',
  'gents': 'role1s',
  'gentlespoon': 'role1',
  'gentlespoons': 'role1s',
  'lark': 'role1',
  'larks': 'role1s',
  'man': 'role1',
  'men': 'role1s',
  'lady': 'role2',
  'ladies': 'role2s',
  'ladle': 'role2',
  'ladles': 'role2s',
  'robin': 'role2',
  'robins': 'role2s',
  'woman': 'role2',
  'women': 'role2s',
};

/// The single canonicalization chokepoint (dialect design §"Canonicalization
/// on input"). Inverse-maps the user's active dialect role terms — plus known
/// legacy synonyms — back to canonical role tokens before persistence, so
/// storage and search stay dialect-agnostic. Conservative: only exact,
/// word-boundary term matches are rewritten; unknown prose is left as typed.
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
  final reverse = <String, String>{};
  // Union enrichment first (lowest precedence); then legacy synonyms; then the
  // active dialect — so legacy and the active dialect always win where they
  // overlap, and the union only fills terms they leave unclaimed.
  if (extraRoleSynonyms.isNotEmpty) {
    reverse.addAll(extraRoleSynonyms);
  }
  reverse.addAll(_legacyRoleSynonyms);
  for (final entry in dialect.roles.entries) {
    reverse[entry.value.singular.toLowerCase()] = entry.key;
    reverse[entry.value.plural.toLowerCase()] = '${entry.key}s';
  }
  final rewritten = Substitutor(reverse, caseInsensitive: true).apply(text);

  final discouraged = dialect.discouragedTerms.isEmpty
      ? const <({String text, int start})>[]
      : Substitutor({
          for (final t in dialect.discouragedTerms) t: t,
        }, caseInsensitive: true).matches(text);

  return CanonicalizationResult(rewritten, discouraged);
}

/// Convenience: canonical text only (drops the discouraged-term spans).
String canonicalizeText(
  String text,
  Dialect dialect, {
  Map<String, String> extraRoleSynonyms = const {},
}) => canonicalize(text, dialect, extraRoleSynonyms: extraRoleSynonyms).text;

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

/// Returns spans in [text] that are recognised as role terms, for the editor
/// "lingo line" underline. Covers:
///  - the active [dialect]'s configured role display-terms,
///  - built-in legacy/synonym role terms (gent, lark, robin, lady, etc.),
///  - canonical role tokens typed directly (e.g. `role1`, `role2s`).
///
/// All returned spans hold positions in the original [text].
List<({String text, int start})> roleSpans(String text, Dialect dialect) {
  if (text.isEmpty) return const [];
  // Build the same reverse map as [canonicalize]: legacy synonyms first, then
  // the dialect's own role terms (override legacy where they overlap).
  final map = <String, String>{..._legacyRoleSynonyms};
  for (final entry in dialect.roles.entries) {
    map[entry.value.singular.toLowerCase()] = entry.key;
    map[entry.value.plural.toLowerCase()] = '${entry.key}s';
  }
  // Include canonical tokens typed directly (e.g. data loaded from storage).
  for (final token in roleTokens) {
    map.putIfAbsent(token, () => token);
  }
  return Substitutor(map, caseInsensitive: true).matches(text);
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
