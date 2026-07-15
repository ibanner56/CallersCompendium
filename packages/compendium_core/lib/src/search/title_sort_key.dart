/// Leading articles ignored when alphabetizing dance titles.
///
/// Standard library-catalog practice for English: a title like
/// "The Nice Combination" files under **N**, not **T**. Kept lowercase; the
/// comparison in [titleSortKey] is case-insensitive.
const List<String> kIgnoredLeadingArticles = ['the', 'a', 'an'];

/// Returns a case-insensitive comparison key for alphabetizing [title] with a
/// leading article ("the"/"a"/"an") ignored.
///
/// The article is only stripped when it is a standalone leading word (followed
/// by whitespace) and non-article content remains — so a title that is just
/// "The" or "A" keeps its full text and never collapses to an empty key.
/// Leading/trailing whitespace is trimmed and the result is lowercased so
/// callers get a stable, order-ready key.
///
/// Examples:
/// - `"The Nice Combination"` → `"nice combination"`
/// - `"A Fine Romance"` → `"fine romance"`
/// - `"An Dro"` → `"dro"`
/// - `"Anaconda"` → `"anaconda"` (no whitespace after "an": not an article)
/// - `"The"` → `"the"` (nothing left to sort by; keep as-is)
String titleSortKey(String title) {
  final trimmed = title.trim();
  final lower = trimmed.toLowerCase();
  for (final article in kIgnoredLeadingArticles) {
    final prefix = '$article ';
    if (lower.startsWith(prefix)) {
      final rest = lower.substring(prefix.length).trimLeft();
      if (rest.isNotEmpty) return rest;
    }
  }
  return lower;
}
