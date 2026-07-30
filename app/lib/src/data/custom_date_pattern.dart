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

/// A single recognized token in a validated custom pattern.
///
/// [width] is the number of source characters (`2` or `4` for year, `2` for
/// month/day) and drives zero-padded formatting and the parsing character
/// class.
class _FieldToken {
  const _FieldToken(this.kind, this.width);

  final DateFieldKind kind;
  final int width;
}

/// A literal separator run (e.g. `-`, `.`, `/`, or a space) between fields.
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
}

/// Allowed separator characters between fields. A fixed set, so matching them
/// introduces no backtracking risk.
const Set<String> _allowedSeparatorChars = {'-', '/', '.', ' '};

/// Parses [raw] into a [CustomDatePattern], or returns `null` for any invalid
/// input (never throws).
///
/// Rules (OWASP allowlist): length ≤ [kMaxCustomDatePatternLength]; the string
/// is a sequence of maximal same-character runs that are each either
///  * a recognized field token — `yyyy`/`yy` (year, case-insensitive), `mm`
///    (month), `dd` (day) — with exactly one of each kind present, or
///  * a run of allowed separator characters (`-`, `/`, `.`, space).
///
/// Any unknown character, an unrecognized token length (e.g. `yyy`, `m`,
/// `ddd`), a duplicate field, or a missing field rejects the whole pattern.
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
      if (runLength != 2) return null; // only MM
      sawMonth = true;
      segments.add(const _FieldToken(DateFieldKind.month, 2));
    } else if (lower == 'd') {
      if (sawDay) return null;
      if (runLength != 2) return null; // only dd
      sawDay = true;
      segments.add(const _FieldToken(DateFieldKind.day, 2));
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
String formatWithCustomPattern(DateTime date, CustomDatePattern pattern) {
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
          buffer.write(date.month.toString().padLeft(2, '0'));
        case DateFieldKind.day:
          buffer.write(date.day.toString().padLeft(2, '0'));
      }
    }
  }
  return buffer.toString();
}

/// Regex fragment matching one occurrence of a separator run in a title. Kept
/// permissive-but-bounded: one or more of the allowed separator characters, so
/// `MM.DD.YY` still matches `MM . DD . YY`-style spacing without introducing
/// backtracking (single bounded quantifier, no nesting/backreferences).
const String _separatorClass = r'[-/. ]';

/// Builds a [RegExp] from a validated [pattern] and, on the first match within
/// [title], returns the corresponding UTC-midnight [DateTime] — or `null` when
/// nothing matches or the fields don't form a real in-range date.
///
/// Safety: the expression is assembled only from fixed literals and bounded
/// character-class quantifiers (`\d{2}`, `\d{4}`, `\d{1,2}`, `[-/. ]+`) with no
/// nesting or backreferences, so an adversarial title cannot trigger
/// catastrophic backtracking (ReDoS). Two-digit years expand to `2000 + yy`.
DateTime? matchTitleWithCustomPattern(String title, CustomDatePattern pattern) {
  final buffer = StringBuffer(r'\b');
  final fieldKinds = <DateFieldKind>[];
  for (final segment in pattern._segments) {
    if (segment is _LiteralToken) {
      // Any declared separator run is matched by one-or-more allowed
      // separators, so the user's chosen separator (and minor spacing) works
      // without embedding user text into the pattern.
      buffer.write('$_separatorClass+');
    } else if (segment is _FieldToken) {
      fieldKinds.add(segment.kind);
      switch (segment.kind) {
        case DateFieldKind.year:
          buffer.write(segment.width == 2 ? r'(\d{2})' : r'(\d{4})');
        case DateFieldKind.month:
        case DateFieldKind.day:
          // Accept optionally non-zero-padded month/day in titles.
          buffer.write(r'(\d{1,2})');
      }
    }
  }
  buffer.write(r'\b');

  final RegExp regExp;
  try {
    regExp = RegExp(buffer.toString());
  } catch (_) {
    // Defensive: a validated pattern always yields a legal expression, but
    // never let an unexpected construction error surface — treat as no match.
    return null;
  }

  final match = regExp.firstMatch(title);
  if (match == null) return null;

  int? year;
  int? month;
  int? day;
  for (var g = 0; g < fieldKinds.length; g++) {
    final value = int.tryParse(match.group(g + 1)!);
    if (value == null) return null;
    switch (fieldKinds[g]) {
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
