/// Splitting a date (and what follows it) off the end of a Caller's Companion
/// dance Name.
library;

import 'title_article.dart';

/// Where a Name's trailing annotation starts: a run of two or more spaces, or
/// a tab, followed by a year, optionally after `Circa`, `ca.` or `c.`.
///
/// A single space is not enough: a title may end in a number of its own
/// ("Trip to the Manors 2000" is left alone), but Caller's Companion lists
/// pad a date out to a column with several.
final RegExp _tailStart = RegExp(
  r'(?:[ ]{2,}|\t)\s*(?=(?:(?:circa|ca\.?|c\.)\s*)?\d{4}(?!\d))',
  caseSensitive: false,
);

/// A tail that is exactly one year and nothing else.
final RegExp _plainYear = RegExp(r'^\d{4}$');

/// The year a tail opens with, after any `Circa`, `ca.` or `c.`.
final RegExp _leadingDate = RegExp(
  r'^(?:(?:circa|ca\.?|c\.)\s*)?\d{4}(?:\s*/\s*\d{2,4})?(?:\?|ish\b)?',
  caseSensitive: false,
);

/// A Caller's Companion dance [name] split into its [title] and the
/// annotation a library padded onto its end, such as `Jack's Maggot   1702`
/// or `Gypsy Round, The      1979    Am 3/4`.
///
/// The [tail] starts at the first run of two or more spaces (or a tab) that is
/// followed by a four-digit year, optionally after `Circa`, `ca.` or `c.`, and
/// runs to the end of the name. It is null when there is none, and then
/// [title] is the whole [name], trimmed. Both are trimmed but otherwise
/// unchanged: the caller sanitizes them.
({String title, String? tail}) splitCcNameTail(String name) {
  final trimmed = name.trim();
  final match = _tailStart.firstMatch(trimmed);
  if (match == null) return (title: trimmed, tail: null);
  final title = trimmed.substring(0, match.start).trim();
  final tail = trimmed.substring(match.end).trim();
  if (title.isEmpty || tail.isEmpty) return (title: trimmed, tail: null);
  return (title: title, tail: tail);
}

/// The year [tail] states when it is exactly one plain year (`1702`), or null
/// when it says anything more or less: `1703/2009`, `2024?`, `Circa 1800`,
/// `1750ish`, or a year followed by a key and meter.
int? ccNameTailPlainYear(String tail) {
  final trimmed = tail.trim();
  return _plainYear.hasMatch(trimmed) ? int.parse(trimmed) : null;
}

/// What [tail] goes on to say after the date it opens with, trimmed: `Am 3/4`
/// for `1979    Am 3/4`, and `''` for a tail that is only a date.
String ccNameTailAfterDate(String tail) {
  final trimmed = tail.trim();
  final date = _leadingDate.firstMatch(trimmed);
  return date == null ? trimmed : trimmed.substring(date.end).trim();
}

/// The title a Caller's Companion dance [name] is imported under, for a
/// discovery label: without the annotation [splitCcNameTail] takes off, and
/// with a trailing article fronted (#1976), so the label agrees with the
/// drafted title.
String ccDanceTitleOf(String name) =>
    frontTrailingArticle(splitCcNameTail(name).title);
