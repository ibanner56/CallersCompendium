/// Turns arbitrary user-typed search text into a safe FTS5 `MATCH` expression.
///
/// FTS5's query grammar treats `- " : * ^ ( )` and the bare keywords
/// `AND` / `OR` / `NOT` / `NEAR` as syntax, so binding raw user text straight
/// into `… MATCH ?` throws `fts5: syntax error` on perfectly ordinary contra
/// terms — `do-si-do`, `right-and-left`, `O'Neill`, or an unbalanced `"`.
///
/// The fix is to hand FTS5 a query it can never misparse: split the input on
/// whitespace and wrap each token in a double-quoted phrase (escaping any
/// embedded `"` by doubling it, per the FTS5 spec). Quoting neutralises every
/// special character and operator keyword — each token becomes a literal phrase
/// — while the tokenizer still splits `"do-si-do"` into the `do si do` phrase
/// at match time, so results are unchanged for ordinary queries. Tokens are
/// joined with a space, preserving FTS5's implicit-AND-between-terms semantics.
///
/// An input with no usable tokens (empty or whitespace-only) yields the empty
/// phrase `""`, which FTS5 accepts and matches nothing — as opposed to the
/// empty string `''`, which is itself a syntax error.
String toFtsMatchQuery(String raw) {
  final tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return '""';
  return tokens.map((t) => '"${t.replaceAll('"', '""')}"').join(' ');
}

/// Builds a literal FTS5 token-prefix query. Prefix syntax is appended outside
/// the quoted phrase so punctuation in the user input remains literal.
String toFtsPrefixMatchQuery(String raw) {
  final tokens = raw.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return '""';
  return tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
}

/// Builds a literal substring query for the FTS5 trigram tokenizer. The whole
/// input stays one phrase: splitting it would turn punctuation-spanning and
/// mid-token searches into a different query.
String toFtsSubstringMatchQuery(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '""';
  return '"${text.replaceAll('"', '""')}"';
}

/// Counts Unicode scalar values after the same trimming used by the query
/// builders. FTS5's short-query boundary is character-based, not byte-based.
int ftsQueryScalarLength(String raw) => raw.trim().runes.length;
