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
  'lady': 'role2',
  'ladies': 'role2s',
  'ladle': 'role2',
  'ladles': 'role2s',
  'robin': 'role2',
  'robins': 'role2s',
};

/// The single canonicalization chokepoint (dialect design §"Canonicalization
/// on input"). Inverse-maps the user's active dialect role terms — plus known
/// legacy synonyms — back to canonical role tokens before persistence, so
/// storage and search stay dialect-agnostic. Conservative: only exact,
/// word-boundary term matches are rewritten; unknown prose is left as typed.
CanonicalizationResult canonicalize(String text, Dialect dialect) {
  final reverse = <String, String>{};
  // Legacy synonyms first; the active dialect overrides where they overlap.
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
String canonicalizeText(String text, Dialect dialect) =>
    canonicalize(text, dialect).text;

/// Whether [token] is one of the canonical role tokens.
bool isRoleToken(String token) => roleTokens.contains(token);
