/// Moving a title's trailing article back to the front, for sources that file
/// titles library-style ("Baby Rose, The").
library;

/// The articles [frontTrailingArticle] moves, lower-cased. The maintainer
/// listed these on #1976 (2026-10-28), and kept them on 2026-10-30 knowing a
/// rare real title misfires ("Thanks, Les"); any other is to be confirmed on
/// the issue or its PR before it is added.
const Set<String> _articles = {'the', 'a', 'an', 'la', 'le', 'les', "l'"};

/// Apostrophes an `L'` may be typed with, folded to ASCII `'` for matching.
final RegExp _apostrophes = RegExp('[\u2019\u2018\u02BC]');

/// How many trailing bracketed annotations stay at the end, as
/// `dedupeCoreTitleKey` strips: "Baby Rose, The (Imp Var) (2)".
const int _maxAnnotations = 3;

/// [title] with a trailing `, <article>` moved to the front, the way Caller's
/// Companion files a title library-style (#1976): "Baby Rose, The" → "The Baby
/// Rose", "Bastringue, La" → "La Bastringue", "Amour, L'" → "L'Amour". Up to
/// [_maxAnnotations] bracketed annotations after the article stay at the end:
/// "Baby Rose, The (var)" → "The Baby Rose (var)".
///
/// Only the article after the **last** comma is considered, so "Rose, Rose,
/// The" becomes "The Rose, Rose". The article keeps its spelling, with its
/// first letter capitalised. Any other title is returned unchanged.
String frontTrailingArticle(String title) {
  var core = title.trim();
  var annotation = '';
  for (var i = 0; i < _maxAnnotations && core.isNotEmpty; i++) {
    final open = switch (core[core.length - 1]) {
      ')' => '(',
      ']' => '[',
      '}' => '{',
      _ => null,
    };
    if (open == null) break;
    final at = core.lastIndexOf(open);
    // Only an annotation set off by whitespace: `Trip(let)` is one word.
    if (at <= 0 || core[at - 1].trim().isNotEmpty) break;
    annotation = ' ${core.substring(at)}$annotation';
    core = core.substring(0, at).trimRight();
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
