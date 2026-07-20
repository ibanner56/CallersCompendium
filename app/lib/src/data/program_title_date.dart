import 'regional_formats.dart';

/// Best-effort, **high-confidence-only** detection of a program's event date
/// from its (free-form) title, for the ContraDB import preview (issue #351).
///
/// This is deliberately conservative: it returns a [DateTime] (UTC, midnight)
/// **only** when a date can be read unambiguously, and returns `null` otherwise
/// so the import is never blocked and the user simply sets the date by hand. It
/// never throws.
///
/// ## What is treated as high-confidence (auto-filled)
/// 1. **ISO-like** `YYYY-MM-DD` (also `/` or `.` separators) — 4-digit year
///    first is unambiguous.
/// 2. **Month name** forms — `March 15 2024`, `March 15, 2024`,
///    `15 March 2024`, `Mar 15 2024` (full or 3-letter abbreviation, optional
///    `st`/`nd`/`rd`/`th` ordinal).
/// 3. **Numeric with a 4-digit year LAST** — `MM/DD/YYYY` or `DD/MM/YYYY`
///    (`/`, `.`, or `-` separators). When exactly one of the two leading fields
///    is `> 12` the order is forced. When both are `<= 12` (genuinely
///    ambiguous) the order is resolved **only** if [pref] expresses a numeric
///    convention (`mdy` → month-first, `dmy` → day-first); for `system`/`ymd`
///    the value is skipped rather than guessed.
///
/// ## What is deliberately NOT matched (left null)
/// Two-digit years (`3/15/24`, `01.12.18`) and loose/season text
/// (`Spring Fling '24`): the century and/or field order are ambiguous, so
/// auto-filling would be an over-match.
///
/// ## Safety
/// The title is length-capped before matching and every pattern uses bounded
/// quantifiers with no nesting or backreferences, so adversarial titles cannot
/// trigger catastrophic backtracking (ReDoS). All candidates are validated as
/// real calendar dates within [_minYear]–[_maxYear].
///
/// ## Precedence
/// Formats are tried in **confidence-tier order** — ISO → month-name → numeric
/// (see [_matchers]) — and the first tier that produces a valid date wins,
/// regardless of where each format appears in the title. The tiers are
/// mutually near-exclusive in practice (a given substring reads as at most one
/// of them), and the more specific/unambiguous formats are deliberately
/// preferred over the ambiguous numeric one. Within a single tier, that
/// pattern's first textual match in the title is used.
DateTime? detectEventDateFromTitle(String title, DateFormatPref pref) {
  // Cap work regardless of input size (ReDoS belt-and-suspenders).
  final text = title.length > _kMaxTitleScan
      ? title.substring(0, _kMaxTitleScan)
      : title;

  // Try each confidence tier in order; the first tier to yield a valid date
  // wins (ISO/month-name are preferred over the ambiguous numeric form).
  for (final matcher in _matchers) {
    final match = matcher.pattern.firstMatch(text);
    if (match == null) continue;
    final date = matcher.build(match, pref);
    if (date != null) return date;
  }
  return null;
}

/// Upper bound on the number of title characters scanned. Program titles are
/// short; anything beyond this is truncated before regex matching.
const int _kMaxTitleScan = 200;

const int _minYear = 1900;
const int _maxYear = 2100;

/// Ordered list of high-confidence matchers; the first that yields a valid date
/// wins. ISO first (most specific), then month-name, then ambiguous numeric.
final List<_DateMatcher> _matchers = [
  // ISO-like: 4-digit year first, e.g. 2024-03-15 (or / or . separators).
  _DateMatcher(
    RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b'),
    (m, _) => _build(
      year: int.parse(m.group(1)!),
      month: int.parse(m.group(2)!),
      day: int.parse(m.group(3)!),
    ),
  ),
  // Month name first: March 15 2024 / Mar 15, 2024 (optional ordinal).
  _DateMatcher(
    RegExp(
      r'\b(' +
          _monthAlternation +
          r')\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b',
      caseSensitive: false,
    ),
    (m, _) => _build(
      year: int.parse(m.group(3)!),
      month: _monthNumber(m.group(1)!),
      day: int.parse(m.group(2)!),
    ),
  ),
  // Day then month name: 15 March 2024 (optional ordinal on the day).
  _DateMatcher(
    RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(' +
          _monthAlternation +
          r')\.?,?\s+(\d{4})\b',
      caseSensitive: false,
    ),
    (m, _) => _build(
      year: int.parse(m.group(3)!),
      month: _monthNumber(m.group(2)!),
      day: int.parse(m.group(1)!),
    ),
  ),
  // Numeric, 4-digit year LAST: NN[sep]NN[sep]YYYY. Order resolved by field
  // range (one field > 12) or, when ambiguous, by the user's mdy/dmy pref.
  _DateMatcher(
    RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b'),
    _buildAmbiguousNumeric,
  ),
];

DateTime? _buildAmbiguousNumeric(RegExpMatch m, DateFormatPref pref) {
  final a = int.parse(m.group(1)!); // first field
  final b = int.parse(m.group(2)!); // second field
  final year = int.parse(m.group(3)!);

  final aCanBeMonth = a >= 1 && a <= 12;
  final bCanBeMonth = b >= 1 && b <= 12;

  int month;
  int day;
  if (aCanBeMonth && !bCanBeMonth) {
    // Second field can't be a month → first is the month (MDY).
    month = a;
    day = b;
  } else if (!aCanBeMonth && bCanBeMonth) {
    // First field can't be a month → second is the month (DMY).
    day = a;
    month = b;
  } else if (aCanBeMonth && bCanBeMonth) {
    // Both plausible as month → ambiguous. Only resolve on an explicit numeric
    // convention; otherwise skip rather than guess.
    switch (pref) {
      case DateFormatPref.mdy:
        month = a;
        day = b;
      case DateFormatPref.dmy:
        day = a;
        month = b;
      case DateFormatPref.system:
      case DateFormatPref.ymd:
        return null;
    }
  } else {
    // Neither field is a valid month (e.g. 13/15/2024) → not a real date.
    return null;
  }
  return _build(year: year, month: month, day: day);
}

/// Validates the calendar date and year bounds, returning a UTC midnight
/// [DateTime] or null when the fields don't form a real in-range date.
DateTime? _build({required int year, required int month, required int day}) {
  if (year < _minYear || year > _maxYear) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  // Reject rollovers (e.g. Feb 30 → Mar 2) by round-tripping the fields.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

const List<String> _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// Alternation of full and 3-letter month names (e.g. `january|jan|...`). Fixed
/// set, so it introduces no backtracking risk.
final String _monthAlternation = [
  for (final name in _months) ...[name, name.substring(0, 3)],
].join('|');

int _monthNumber(String raw) {
  final lower = raw.toLowerCase();
  for (var i = 0; i < _months.length; i++) {
    final full = _months[i];
    if (lower == full || lower == full.substring(0, 3)) return i + 1;
  }
  return 0; // never reached given the alternation, but keeps _build safe.
}

typedef _DateBuilder =
    DateTime? Function(RegExpMatch match, DateFormatPref pref);

class _DateMatcher {
  _DateMatcher(this.pattern, this.build);

  final RegExp pattern;
  final _DateBuilder build;
}
