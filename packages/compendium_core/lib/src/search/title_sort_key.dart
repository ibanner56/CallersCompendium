import 'package:unorm_dart/unorm_dart.dart';

/// Leading articles ignored when alphabetizing dance titles.
///
/// Standard library-catalog practice for English: a title like
/// "The Nice Combination" files under **N**, not **T**. Kept lowercase; the
/// comparison in [titleSortKey] is case-insensitive.
const List<String> kIgnoredLeadingArticles = ['the', 'a', 'an'];

final RegExp _ascii = RegExp(r'^[\x00-\x7F]*$');

/// Lowercases [text] and strips combining marks, so "École" and "ecole" compare
/// equal, as they do in the Collection's FTS index (`remove_diacritics`).
String foldForTitleMatch(String text) {
  // ASCII has no combining marks; skipping NFD keeps the title sort (run over
  // every result of the default sort) cheap on large libraries.
  if (_ascii.hasMatch(text)) return text.toLowerCase();
  final decomposed = nfd(text.toLowerCase());
  final buf = StringBuffer();
  for (final unit in decomposed.runes) {
    // U+0300–U+036F: the Combining Diacritical Marks block.
    if (unit >= 0x300 && unit <= 0x36F) continue;
    buf.writeCharCode(unit);
  }
  return buf.toString();
}

/// Returns a case- and accent-insensitive comparison key for alphabetizing [title] with a
/// leading article ("the"/"a"/"an") ignored.
///
/// The article is only stripped when it is a standalone leading word (followed
/// by whitespace) and non-article content remains — so a title that is just
/// "The" or "A" keeps its full text and never collapses to an empty key.
/// Leading/trailing whitespace is trimmed and the result is folded with
/// [foldForTitleMatch] (lowercased, combining marks stripped) so callers get a
/// stable, order-ready key in which "École" files with E.
///
/// This is accent folding, not locale-aware collation: NFD leaves Æ and Ø
/// (which have no decomposition) after Z, and folds Danish Å to A.
///
/// Examples:
/// - `"The Nice Combination"` → `"nice combination"`
/// - `"A Fine Romance"` → `"fine romance"`
/// - `"An Dro"` → `"dro"`
/// - `"Anaconda"` → `"anaconda"` (no whitespace after "an": not an article)
/// - `"École"` → `"ecole"`
/// - `"The"` → `"the"` (nothing left to sort by; keep as-is)
String titleSortKey(String title) {
  final trimmed = title.trim();
  final lower = foldForTitleMatch(trimmed);
  for (final article in kIgnoredLeadingArticles) {
    final prefix = '$article ';
    if (lower.startsWith(prefix)) {
      final rest = lower.substring(prefix.length).trimLeft();
      if (rest.isNotEmpty) return rest;
    }
  }
  return lower;
}
