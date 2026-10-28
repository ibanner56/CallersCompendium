import 'package:unorm_dart/unorm_dart.dart';

import 'title_sort_key.dart';

/// How well a title matches a typed query, best first. Used by surfaces that
/// match titles in memory (the Ctrl/Cmd-K palette) so they rank the way a
/// caller expects rather than in storage order.
enum TitleMatchRank {
  /// The whole title is the query ("Hey" for `hey`).
  exact,

  /// The title starts with the query ("Heyday" for `hey`).
  prefix,

  /// The query appears somewhere else in the title ("Cheyenne" for `hey`).
  substring,
}

/// Lowercases [text] and strips combining marks, so "École" and "ecole" compare
/// equal, as they do in the Collection's FTS index (`remove_diacritics`).
String foldForTitleMatch(String text) {
  final decomposed = nfd(text.toLowerCase());
  final buf = StringBuffer();
  for (final unit in decomposed.runes) {
    // U+0300–U+036F: the Combining Diacritical Marks block.
    if (unit >= 0x300 && unit <= 0x36F) continue;
    buf.writeCharCode(unit);
  }
  return buf.toString();
}

/// Ranks [title] against [query], or returns `null` when it does not match.
///
/// Both sides are folded with [foldForTitleMatch]. Exact and prefix matches are
/// tested against the title as typed *and*, when [ignoreLeadingArticles], with
/// its leading article removed ([titleSortKey]), so `nice` is a prefix match for
/// "The Nice Combination". A substring match always uses the full title, so
/// `the` still finds it. An empty [query] matches every title as a prefix.
TitleMatchRank? rankTitleMatch(
  String title,
  String query, {
  required bool ignoreLeadingArticles,
}) {
  final q = foldForTitleMatch(query).trim();
  final full = foldForTitleMatch(title).trim();
  final key = ignoreLeadingArticles ? titleSortKey(full) : full;
  if (q.isEmpty) return TitleMatchRank.prefix;
  if (full == q || key == q) return TitleMatchRank.exact;
  if (full.startsWith(q) || key.startsWith(q)) return TitleMatchRank.prefix;
  if (full.contains(q)) return TitleMatchRank.substring;
  return null;
}
