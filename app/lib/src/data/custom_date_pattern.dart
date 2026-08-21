/// User-defined date pattern support for the "Custom" date-format preference
/// (issue #584).
///
/// The pattern is **free-form, untrusted user input**, so every function here is
/// defensive by design (OWASP): the raw string is length-capped and validated
/// against a fixed token/separator allowlist before use, all matching is built
/// from bounded, backreference-free constructs (no catastrophic backtracking),
/// no raw exception text is ever surfaced, and produced dates are validated as
/// real calendar dates within [_minYear]–[_maxYear]. A `null`, empty,
/// over-long, or otherwise unrecognized pattern resolves to `null` here so the
/// caller can fall back to the system default everywhere it is consumed
/// (display *and* title date parsing).
///
/// This library is intentionally Flutter-free and pure so it can be unit-tested
/// directly.
library;

/// Upper bound on the raw custom-pattern length. Real patterns are short
/// (`yyyy-MM-dd`, `MM.DD.YY`); anything longer is rejected before any work so an
/// adversarial value can never drive unbounded matching or storage.
const int kMaxCustomDatePatternLength = 32;

const int _minYear = 1900;
const int _maxYear = 2100;

/// Which calendar field a token represents.
enum DateFieldKind { year, month, day }

/// How a month field is rendered/matched (issue #632).
///
/// * [numeric] — `MM`, a zero-padded number (`06`).
/// * [abbreviated] — `MMM`, a localized 3-letter-style name (`Jun`).
/// * [full] — `MMMM`, a localized full name (`June`).
///
/// The style is derived from the run length of the month token (`2`/`3`/`4`)
/// and is only meaningful for [DateFieldKind.month] tokens.
enum MonthStyle { numeric, abbreviated, full }

/// Localized month names supplied by the caller for rendering written-out month
/// tokens (`MMM`/`MMMM`, issue #632).
///
/// Kept as a plain, Flutter-free value object so this library stays pure and
/// directly unit-testable: the display layer builds it from `AppLocalizations`
/// and passes it in. Both lists are month-indexed with January at index `0`
/// (i.e. `abbreviated[month - 1]`); each is expected to hold 12 entries.
class MonthNames {
  const MonthNames({required this.abbreviated, required this.full});

  /// Abbreviated names, January first (e.g. `Jan`, `Feb`, …).
  final List<String> abbreviated;

  /// Full names, January first (e.g. `January`, `February`, …).
  final List<String> full;
}

/// A single recognized token in a validated custom pattern.
///
/// [width] is the number of source characters (`2` or `4` for year, `2`/`3`/`4`
/// for month, `1` or `2` for day) and drives zero-padded **formatting** only. A
/// day/year width of `2` (`dd`/`yy`) zero-pads on render; a day width of `1`
/// (`d`) renders with no leading zero. Title **matching**
/// ([matchTitleWithCustomPattern]) stays permissive for numeric month/day
/// fields — it always accepts 1–2 digits regardless of the declared width, so
/// a `d`-declared pattern still matches a zero-padded "03" in text. [monthStyle]
/// is non-null only for [DateFieldKind.month] tokens and records whether the
/// month is numeric/abbreviated/full.
class _FieldToken {
  const _FieldToken(this.kind, this.width, {this.monthStyle});

  final DateFieldKind kind;
  final int width;
  final MonthStyle? monthStyle;
}

/// A literal separator run (e.g. `-`, `.`, `/`, `,`, or a space) between
/// fields.
class _LiteralToken {
  const _LiteralToken(this.text);

  final String text;
}

/// A parsed, validated custom date pattern.
///
/// Produced only by [parseCustomDatePattern]; its very existence means the
/// source pattern passed the length cap, the token/separator allowlist, and the
/// structural rules (exactly one year, one month, and one day token). Callers
/// can therefore format and build a matcher without re-validating.
class CustomDatePattern {
  CustomDatePattern._(this._segments, this.yearWidth);

  /// Ordered mix of [_FieldToken] and [_LiteralToken] describing the layout.
  final List<Object> _segments;

  /// The declared year width: `2` (`yy`) or `4` (`yyyy`).
  final int yearWidth;

  /// Field order (year/month/day) in the sequence they appear, ignoring
  /// separators. Always contains exactly the three kinds, each once.
  List<DateFieldKind> get fieldOrder => [
    for (final s in _segments)
      if (s is _FieldToken) s.kind,
  ];

  /// True when the month field precedes the day field in the declared layout.
  /// Used to disambiguate numeric title dates (month-first vs day-first).
  bool get monthBeforeDay {
    final order = fieldOrder;
    return order.indexOf(DateFieldKind.month) <
        order.indexOf(DateFieldKind.day);
  }

  /// The style of the (single) month token in this pattern — numeric (`MM`),
  /// abbreviated (`MMM`), or full (`MMMM`) (issue #632). A validated pattern
  /// always has exactly one month token, so this is never `null`.
  MonthStyle get monthStyle {
    for (final s in _segments) {
      if (s is _FieldToken && s.kind == DateFieldKind.month) {
        return s.monthStyle ?? MonthStyle.numeric;
      }
    }
    return MonthStyle.numeric; // unreachable: a valid pattern has one month.
  }
}

/// Allowed separator characters between fields. A fixed set, so matching them
/// introduces no backtracking risk.
const Set<String> _allowedSeparatorChars = {'-', '/', '.', ' ', ','};

/// Parses [raw] into a [CustomDatePattern], or returns `null` for any invalid
/// input (never throws).
///
/// Rules (OWASP allowlist): length ≤ [kMaxCustomDatePatternLength]; the string
/// is a sequence of maximal same-character runs that are each either
///  * a recognized field token — `yyyy`/`yy` (year, case-insensitive), `mm`
///    (month numeric), `mmm` (month abbreviated name), `mmmm` (month full
///    name), `d`/`dd` (day, non-zero-padded/zero-padded, issue #668) — with
///    exactly one of each kind present, or
///  * a run of allowed separator characters (`-`, `/`, `.`, space, `,`, issue
///    #668).
///
/// Any unknown character, an unrecognized token length (e.g. `yyy`, `m`,
/// `mmmmm`, `ddd`), a duplicate field, or a missing field rejects the whole
/// pattern.
CustomDatePattern? parseCustomDatePattern(String? raw) {
  if (raw == null) return null;
  if (raw.isEmpty || raw.length > kMaxCustomDatePatternLength) return null;

  final segments = <Object>[];
  var yearWidth = 0;
  var sawYear = false;
  var sawMonth = false;
  var sawDay = false;

  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    // Consume a maximal run of the same character (bounded by raw.length).
    var j = i + 1;
    while (j < raw.length && raw[j] == ch) {
      j++;
    }
    final runLength = j - i;
    final lower = ch.toLowerCase();

    if (lower == 'y') {
      if (sawYear) return null; // duplicate year field
      if (runLength != 2 && runLength != 4) return null; // only yy / yyyy
      sawYear = true;
      yearWidth = runLength;
      segments.add(_FieldToken(DateFieldKind.year, runLength));
    } else if (lower == 'm') {
      if (sawMonth) return null;
      // MM = numeric, MMM = abbreviated name, MMMM = full name (issue #632).
      final MonthStyle style;
      switch (runLength) {
        case 2:
          style = MonthStyle.numeric;
        case 3:
          style = MonthStyle.abbreviated;
        case 4:
          style = MonthStyle.full;
        default:
          return null; // only MM / MMM / MMMM
      }
      sawMonth = true;
      segments.add(
        _FieldToken(DateFieldKind.month, runLength, monthStyle: style),
      );
    } else if (lower == 'd') {
      if (sawDay) return null;
      // d = non-zero-padded day, dd = zero-padded (issue #668).
      if (runLength != 1 && runLength != 2) return null;
      sawDay = true;
      segments.add(_FieldToken(DateFieldKind.day, runLength));
    } else if (_allowedSeparatorChars.contains(ch)) {
      segments.add(_LiteralToken(raw.substring(i, j)));
    } else {
      return null; // unknown character → reject rather than interpret
    }
    i = j;
  }

  if (!sawYear || !sawMonth || !sawDay) return null; // all three required
  return CustomDatePattern._(segments, yearWidth);
}

/// Formats [date] using a validated [pattern] via dependency-free, zero-padded
/// token substitution (no `intl`). `yy` renders the last two digits of the
/// year; `yyyy` the full four.
///
/// Written-out month tokens (`MMM`/`MMMM`, issue #632) render a localized name
/// looked up from [monthNames] (`abbreviated`/`full`, month-indexed from 0).
/// When a name-style token is present but [monthNames] is `null` (or the list
/// is too short), the month degrades safely to its zero-padded number rather
/// than throwing — the display layer always supplies names, so this only guards
/// direct/pure callers.
String formatWithCustomPattern(
  DateTime date,
  CustomDatePattern pattern, {
  MonthNames? monthNames,
}) {
  final buffer = StringBuffer();
  for (final segment in pattern._segments) {
    if (segment is _LiteralToken) {
      buffer.write(segment.text);
    } else if (segment is _FieldToken) {
      switch (segment.kind) {
        case DateFieldKind.year:
          final full = date.year.toString().padLeft(4, '0');
          buffer.write(
            segment.width == 2 ? full.substring(full.length - 2) : full,
          );
        case DateFieldKind.month:
          buffer.write(
            _formatMonth(date.month, segment.monthStyle, monthNames),
          );
        case DateFieldKind.day:
          // Zero-pad only for the declared dd width; d (width 1, issue #668)
          // renders with no leading zero.
          buffer.write(
            segment.width == 2
                ? date.day.toString().padLeft(2, '0')
                : date.day.toString(),
          );
      }
    }
  }
  return buffer.toString();
}

/// Renders a 1-based [month] per [style], looking localized names up in
/// [monthNames]. Falls back to the zero-padded number for the numeric style, a
/// missing name table, or an out-of-range index so this never throws.
String _formatMonth(int month, MonthStyle? style, MonthNames? monthNames) {
  final numeric = month.toString().padLeft(2, '0');
  final index = month - 1;
  switch (style) {
    case MonthStyle.abbreviated:
      final names = monthNames?.abbreviated;
      if (names == null || index < 0 || index >= names.length) return numeric;
      return names[index];
    case MonthStyle.full:
      final names = monthNames?.full;
      if (names == null || index < 0 || index >= names.length) return numeric;
      return names[index];
    case MonthStyle.numeric:
    case null:
      return numeric;
  }
}

/// Regex fragment matching one occurrence of a separator run in a title. Kept
/// permissive-but-bounded: one or more of the allowed separator characters, so
/// `MM.DD.YY` still matches `MM . DD . YY`-style spacing without introducing
/// backtracking (single bounded quantifier, no nesting/backreferences).
const String _separatorClass = r'[-/. ,]'; // comma added, issue #668

/// Builds a [RegExp] from a validated [pattern] and, on the first match within
/// [title], returns the corresponding UTC-midnight [DateTime] — or `null` when
/// nothing matches or the fields don't form a real in-range date.
///
/// Safety: the expression is assembled only from fixed literals and bounded
/// character-class quantifiers (`\d{2}`, `\d{4}`, `\d{1,2}`, `[-/. ,]+`) with no
/// nesting or backreferences, so an adversarial title cannot trigger
/// catastrophic backtracking (ReDoS). Two-digit years expand to `2000 + yy`.
/// Builds a [RegExp] from a validated [pattern] and, on the first match within
/// [title], returns the corresponding UTC-midnight [DateTime] — or `null` when
/// nothing matches or the fields don't form a real in-range date.
///
/// Written-out month tokens (`MMM`/`MMMM`, issue #632) match a **localized-name
/// allowlist**: [monthNames] supplies the full names (January first) and the
/// matcher accepts each full name *or* its 3-letter prefix, case-insensitively,
/// mapping the captured word back to a month number. When the pattern declares a
/// name-style month but [monthNames] is `null`/empty, that pattern simply does
/// not match (returns `null`) rather than falling back to a numeric field.
///
/// Safety: the expression is assembled only from fixed literals, bounded
/// character-class quantifiers (`\d{2}`, `\d{4}`, `\d{1,2}`, `[-/. ,]+`), and a
/// finite alternation of the **allowlisted, regex-escaped** month names — no
/// nesting, backreferences, or user text — so an adversarial title cannot
/// trigger catastrophic backtracking (ReDoS). Two-digit years expand to
/// `2000 + yy`.
DateTime? matchTitleWithCustomPattern(
  String title,
  CustomDatePattern pattern, {
  List<String>? monthNames,
}) {
  // Build a longest-first, regex-escaped alternation of the allowlisted month
  // names (full name + 3-letter prefix), plus a lookup from the lowercased word
  // to its 1-based month number. A name-style token with no usable name table
  // cannot match and aborts the whole pattern.
  String? monthNameGroup;
  final monthNumberByName = <String, int>{};
  if (monthNames != null && monthNames.isNotEmpty) {
    final alternatives = <String>[];
    for (var i = 0; i < monthNames.length; i++) {
      final name = monthNames[i].trim();
      if (name.isEmpty) continue;
      final lowerFull = name.toLowerCase();
      monthNumberByName[lowerFull] = i + 1;
      alternatives.add(lowerFull);
      if (lowerFull.length >= 3) {
        final abbr = lowerFull.substring(0, 3);
        monthNumberByName.putIfAbsent(abbr, () => i + 1);
        alternatives.add(abbr);
      }
    }
    // Longest-first so `january` wins over its `jan` prefix; escape every name
    // so only the fixed allowlist can ever reach the regex engine.
    alternatives.sort((a, b) => b.length.compareTo(a.length));
    if (alternatives.isNotEmpty) {
      monthNameGroup = '(${alternatives.map(RegExp.escape).join('|')})';
    }
  }

  final buffer = StringBuffer(r'\b');
  // Per captured group, in order: the field kind and whether it is a month
  // captured as a name (so the group is looked up rather than int-parsed).
  final fields = <({DateFieldKind kind, bool isMonthName})>[];
  for (final segment in pattern._segments) {
    if (segment is _LiteralToken) {
      // Any declared separator run is matched by one-or-more allowed
      // separators, so the user's chosen separator (and minor spacing) works
      // without embedding user text into the pattern.
      buffer.write('$_separatorClass+');
    } else if (segment is _FieldToken) {
      switch (segment.kind) {
        case DateFieldKind.year:
          fields.add((kind: DateFieldKind.year, isMonthName: false));
          buffer.write(segment.width == 2 ? r'(\d{2})' : r'(\d{4})');
        case DateFieldKind.month:
          final wantsName =
              segment.monthStyle == MonthStyle.abbreviated ||
              segment.monthStyle == MonthStyle.full;
          if (wantsName) {
            // A name-style month with no allowlist can never match.
            if (monthNameGroup == null) return null;
            fields.add((kind: DateFieldKind.month, isMonthName: true));
            buffer.write(monthNameGroup);
          } else {
            fields.add((kind: DateFieldKind.month, isMonthName: false));
            // Accept optionally non-zero-padded month in titles.
            buffer.write(r'(\d{1,2})');
          }
        case DateFieldKind.day:
          fields.add((kind: DateFieldKind.day, isMonthName: false));
          // Accept optionally non-zero-padded day in titles.
          buffer.write(r'(\d{1,2})');
      }
    }
  }
  buffer.write(r'\b');

  final RegExp regExp;
  try {
    regExp = RegExp(buffer.toString(), caseSensitive: false);
  } catch (_) {
    // diagnostics: silent — a validated pattern always yields a legal
    // expression; treats an unexpected construction error as no match.
    return null;
  }

  final match = regExp.firstMatch(title);
  if (match == null) return null;

  int? year;
  int? month;
  int? day;
  for (var g = 0; g < fields.length; g++) {
    final raw = match.group(g + 1);
    if (raw == null) return null;
    final field = fields[g];
    if (field.isMonthName) {
      final value = monthNumberByName[raw.toLowerCase()];
      if (value == null) return null; // outside the allowlist → no match
      month = value;
      continue;
    }
    final value = int.tryParse(raw);
    if (value == null) return null;
    switch (field.kind) {
      case DateFieldKind.year:
        year = pattern.yearWidth == 2 ? 2000 + value : value;
      case DateFieldKind.month:
        month = value;
      case DateFieldKind.day:
        day = value;
    }
  }
  if (year == null || month == null || day == null) return null;
  return _buildValidDate(year: year, month: month, day: day);
}

/// Validates the calendar date and year bounds, returning a UTC-midnight
/// [DateTime] or `null` when the fields don't form a real in-range date. Mirrors
/// the guard used by the title-date detector so both paths share one bound.
DateTime? _buildValidDate({
  required int year,
  required int month,
  required int day,
}) {
  if (year < _minYear || year > _maxYear) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}
