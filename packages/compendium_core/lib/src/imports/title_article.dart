/// Moving a title's trailing article back to the front, for sources that file
/// titles library-style ("Baby Rose, The").
library;

/// The articles [frontTrailingArticle] moves, lower-cased. The maintainer
/// listed these on #1976 (2026-10-28); any other is to be confirmed there
/// before it is added.
const Set<String> _articles = {'the', 'a', 'an', 'la', 'le', 'les', "l'"};

/// Apostrophes an `L'` may be typed with, folded to ASCII `'` for matching.
final RegExp _apostrophes = RegExp('[’‘ʼ]');

/// [title] with a trailing `, <article>` moved to the front, the way Caller's
/// Companion files a title library-style (#1976): "Baby Rose, The" → "The Baby
/// Rose", "Bastringue, La" → "La Bastringue", "Amour, L'" → "L'Amour". A
/// bracketed annotation after the article stays at the end: "Baby Rose, The
/// (var)" → "The Baby Rose (var)".
///
/// Only the article after the **last** comma is considered, so "Rose, Rose,
/// The" becomes "The Rose, Rose". The article keeps its spelling, with its
/// first letter capitalised. Any other title is returned unchanged.
String frontTrailingArticle(String title) {
  final trimmed = title.trim();
  var core = trimmed;
  var annotation = '';
  final close = trimmed.isEmpty ? '' : trimmed[trimmed.length - 1];
  final open = switch (close) {
    ')' => '(',
    ']' => '[',
    '}' => '{',
    _ => null,
  };
  if (open != null) {
    final at = trimmed.lastIndexOf(open);
    // Only an annotation set off by a space: `Trip(let)` is part of a word.
    if (at > 0 && trimmed[at - 1] == ' ') {
      core = trimmed.substring(0, at).trimRight();
      annotation = ' ${trimmed.substring(at)}';
    }
  }

  final comma = core.lastIndexOf(',');
  if (comma < 0) return title;
  final base = core.substring(0, comma).trim();
  final article = core.substring(comma + 1).trim();
  if (base.isEmpty) return title;
  if (!_articles.contains(
    article.replaceAll(_apostrophes, "'").toLowerCase(),
  )) {
    return title;
  }

  final front = '${article[0].toUpperCase()}${article.substring(1)}';
  final elided = front.endsWith("'") || _apostrophes.hasMatch(front);
  return '$front${elided ? '' : ' '}$base$annotation';
}
