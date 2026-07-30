import 'custom_date_pattern.dart';
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
/// 3. **The user's explicit custom pattern** (issue #584/#632) — when [setting]
///    selects a valid custom pattern, a title date matching its declared field
///    order/separators is read per that layout: numeric fields (including
///    two-digit years) and written-out month tokens (`MMM`/`MMMM`), whose month
///    names are matched against the same English allowlist as tier 2.
/// 4. **Numeric with a 4-digit year LAST** — `MM/DD/YYYY` or `DD/MM/YYYY`
///    (`/`, `.`, or `-` separators). When exactly one of the two leading fields
///    is `> 12` the order is forced. When both are `<= 12` (genuinely
///    ambiguous) the order is resolved **only** if [setting] expresses a numeric
///    convention (`mdy`/month-first custom → month-first; `dmy`/day-first custom
///    → day-first); for `system`/`ymd`/invalid-custom the value is skipped
///    rather than guessed.
///
/// ## What is deliberately NOT matched (left null)
/// Two-digit years (`3/15/24`, `01.12.18`) — unless a valid custom pattern
/// declares a two-digit year and thereby resolves the century/order — and
/// loose/season text (`Spring Fling '24`): the century and/or field order are
/// otherwise ambiguous, so auto-filling would be an over-match.
///
/// ## Safety
/// The title is length-capped before matching and every pattern uses bounded
/// quantifiers with no nesting or backreferences, so adversarial titles cannot
/// trigger catastrophic backtracking (ReDoS). The custom-pattern matcher is
/// built by [matchTitleWithCustomPattern] under the same guarantees. All
/// candidates are validated as real calendar dates within [_minYear]–[_maxYear].
///
/// ## Precedence
/// Formats are tried in **confidence-tier order** — ISO → month-name → explicit
/// custom pattern → generic numeric — and the first tier that produces a valid
/// date wins, regardless of where each format appears in the title. Text forms
/// are deliberately preferred over numeric ones, and the user's explicit custom
/// layout is preferred over the generic numeric guesser. Within a single tier,
/// that pattern's first textual match in the title is used.
DateTime? detectEventDateFromTitle(String title, DateFormatSetting setting) {
  // Cap work regardless of input size (ReDoS belt-and-suspenders).
  final text = title.length > _kMaxTitleScan
      ? title.substring(0, _kMaxTitleScan)
      : title;

  final custom = setting.effectivePattern;
  final order = _numericOrderFor(setting, custom);

  // Tiers 1–2: ISO then month-name (unambiguous, highest confidence).
  for (final matcher in _highConfidenceMatchers) {
    final match = matcher.pattern.firstMatch(text);
    if (match == null) continue;
    final date = matcher.build(match);
    if (date != null) return date;
  }

  // Tier 3: the user's explicit custom layout (adds two-digit-year support,
  // written-out month tokens, and uses the declared field ORDER; separator
  // segments match any allowed separator run — see matchTitleWithCustomPattern —
  // rather than the exact declared separators). Month-name tokens are matched
  // against the same English month allowlist used by the tiers above. Only when
  // the custom pattern is valid; an invalid/absent pattern skips this tier and
  // behaves like `system`.
  if (custom != null) {
    final date = matchTitleWithCustomPattern(text, custom, monthNames: _months);
    if (date != null) return date;
  }

  // Tier 4: generic ambiguous numeric (4-digit year last), resolved by field
  // range or, when ambiguous, the effective month/day order.
  final numericMatch = _ambiguousNumericPattern.firstMatch(text);
  if (numericMatch != null) {
    final date = _buildAmbiguousNumeric(numericMatch, order);
    if (date != null) return date;
  }

  return null;
}

/// Upper bound on the number of title characters scanned. Program titles are
/// short; anything beyond this is truncated before regex matching.
const int _kMaxTitleScan = 200;

const int _minYear = 1900;
const int _maxYear = 2100;

/// How to resolve an otherwise-ambiguous numeric date (both leading fields
/// `<= 12`). Derived once per call from the active [DateFormatSetting].
enum _NumericOrder { none, monthFirst, dayFirst }

/// Maps the active [setting] (and its parsed [custom] pattern, when any) to the
/// numeric field order used for the ambiguous-numeric tier. A valid custom
/// pattern contributes its declared month/day order; an invalid custom pattern
/// resolves to [_NumericOrder.none] so it behaves exactly like `system`.
_NumericOrder _numericOrderFor(
  DateFormatSetting setting,
  CustomDatePattern? custom,
) {
  switch (setting.pref) {
    case DateFormatPref.mdy:
      return _NumericOrder.monthFirst;
    case DateFormatPref.dmy:
      return _NumericOrder.dayFirst;
    case DateFormatPref.custom:
      if (custom == null) return _NumericOrder.none;
      return custom.monthBeforeDay
          ? _NumericOrder.monthFirst
          : _NumericOrder.dayFirst;
    case DateFormatPref.system:
    case DateFormatPref.ymd:
      return _NumericOrder.none;
  }
}

/// High-confidence, order-independent matchers tried first: ISO, then the two
/// month-name forms. These never depend on the user's numeric convention.
final List<_DateMatcher> _highConfidenceMatchers = [
  // ISO-like: 4-digit year first, e.g. 2024-03-15 (or / or . separators).
  _DateMatcher(
    RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b'),
    (m) => _build(
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
    (m) => _build(
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
    (m) => _build(
      year: int.parse(m.group(3)!),
      month: _monthNumber(m.group(2)!),
      day: int.parse(m.group(1)!),
    ),
  ),
];

/// Ambiguous numeric form, 4-digit year LAST: NN[sep]NN[sep]YYYY. Order resolved
/// by field range (one field > 12) or, when ambiguous, by the effective
/// [_NumericOrder]. Bounded and backreference-free (ReDoS-safe).
final RegExp _ambiguousNumericPattern = RegExp(
  r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b',
);

DateTime? _buildAmbiguousNumeric(RegExpMatch m, _NumericOrder order) {
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
    switch (order) {
      case _NumericOrder.monthFirst:
        month = a;
        day = b;
      case _NumericOrder.dayFirst:
        day = a;
        month = b;
      case _NumericOrder.none:
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

typedef _DateBuilder = DateTime? Function(RegExpMatch match);

class _DateMatcher {
  _DateMatcher(this.pattern, this.build);

  final RegExp pattern;
  final _DateBuilder build;
}
