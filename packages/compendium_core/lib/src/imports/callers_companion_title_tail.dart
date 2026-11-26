/// Splitting a date (and what follows it) off the end of a Caller's Companion
/// dance Name.
library;

import '../util/text_sanitizer.dart';
import 'title_article.dart';

/// A run of whitespace: a candidate for the gap before a Name's date.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Two spaces in a row (no-break spaces included): what makes a run of
/// whitespace a gap, rather than the single space between words.
final RegExp _padding = RegExp(r'[ \u00A0]{2}');

/// A year, optionally after `Circa`, `ca.` or `c.`, matched where a gap ends.
final RegExp _dateAhead = RegExp(
  r'(?:(?:circa|ca\.?|c\.)\s*)?\d{4}(?!\d)',
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
/// [title] is the whole name sanitized as a single line, as it always was (a
/// tab in it is dropped). Both parts are sanitized ([sanitizeImportedText])
/// and trimmed. The date is looked for after sanitizing, so an invisible
/// character cannot hide the gap before it, and with each tab read as two
/// spaces, so a tab in either part is kept as spaces rather than dropped
/// (`Foo\tBar  1702` is titled `Foo  Bar`).
({String title, String? tail}) splitCcNameTail(String name) {
  final spaced = _clean(name.replaceAll('\t', '  '));
  final match = _tailGap(spaced);
  final title = match == null ? '' : spaced.substring(0, match.start).trim();
  final tail = match == null ? '' : spaced.substring(match.end).trim();
  if (title.isEmpty || tail.isEmpty) return (title: _clean(name), tail: null);
  return (title: title, tail: tail);
}

/// The first run of whitespace in [text] that holds two spaces in a row (a
/// single space is not enough: a title may end in a number of its own, "Trip
/// to the Manors 2000", but Caller's Companion lists pad a date out to a
/// column with several) and is followed by a year, optionally after `Circa`,
/// `ca.` or `c.`; null when there is none.
///
/// Linear in the length of [text], whatever it holds: each run is found once,
/// searched once for its two spaces, and the year looked for once where it
/// ends. A single pattern that let two whitespace quantifiers share a run
/// tried every split of it from every start, so a Name with a few thousand
/// spaces and no year after them held the import for minutes.
Match? _tailGap(String text) {
  for (final run in _whitespaceRun.allMatches(text)) {
    if (!_padding.hasMatch(run[0]!)) continue;
    if (_dateAhead.matchAsPrefix(text, run.end) != null) return run;
  }
  return null;
}

String _clean(String text) =>
    sanitizeImportedText(text.trim(), allowLineBreaks: false).trim();

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
