import 'package:meta/meta.dart';

/// The precision to which a [PartialDate] is known.
///
/// Historical composition dates are often known only imprecisely — "1989",
/// "March 2004", or a full calendar date — so a [PartialDate] carries the
/// precision it was specified to.
enum DatePrecision {
  /// Year only (`YYYY`).
  year,

  /// Year and month (`YYYY-MM`).
  month,

  /// Full year, month, and day (`YYYY-MM-DD`).
  day,
}

/// An immutable, partial-precision calendar date: a required [year] with an
/// optional [month] and [day].
///
/// Used for bibliographic metadata such as a dance's composed/revised dates,
/// which are frequently known only to the year (or year+month). This is
/// deliberately **not** a [DateTime]: `DateTime` forces a full year/month/day
/// *plus* a wall-clock time and a time zone, so it cannot represent "1989" or
/// "March 2004"; its midnight is a fiction, and a time-zone shift can roll the
/// value across a day boundary. A partial date is date-only and
/// precision-bearing, so it needs a dedicated type.
///
/// Pure Dart (Flutter-free). Instances are validated at construction and are
/// therefore always well-formed.
///
/// ## Canonical serialization
/// [serialize] renders an ISO-like string sized to the precision — `YYYY`,
/// `YYYY-MM`, or `YYYY-MM-DD` (all zero-padded) — and [PartialDate.parse]
/// round-trips it. Because every field is zero-padded, **lexicographic order
/// equals chronological order**: `"1989" < "1989-03" < "1989-03-01" < "1990"`.
/// A year-only value sorts *before* any month-qualified value in the same year
/// (it is the less-precise anchor at the start of that year). This is what lets
/// a sort be a plain `ORDER BY` on the stored string.
@immutable
class PartialDate implements Comparable<PartialDate> {
  /// Creates a partial date, validating the components.
  ///
  /// Throws [ArgumentError] when:
  /// - [year] is outside 1–9999 (keeps the canonical form 4 digits),
  /// - [month] is present and outside 1–12,
  /// - [day] is present without a [month] (no "day without month"),
  /// - [day] is present and outside the valid range for the given
  ///   [month]/[year] (rejects e.g. Feb 30, Apr 31; leap-year aware).
  PartialDate(this.year, [this.month, this.day]) {
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'must be in 1..9999');
    }
    if (day != null && month == null) {
      throw ArgumentError.value(
        day,
        'day',
        'a day requires a month to be specified',
      );
    }
    if (month != null && (month! < 1 || month! > 12)) {
      throw ArgumentError.value(month, 'month', 'must be in 1..12');
    }
    if (day != null) {
      final maxDay = _daysInMonth(year, month!);
      if (day! < 1 || day! > maxDay) {
        throw ArgumentError.value(
          day,
          'day',
          'must be in 1..$maxDay for $year-${_pad2(month!)}',
        );
      }
    }
  }

  /// Parses a canonical [serialize] string (`YYYY`, `YYYY-MM`, or
  /// `YYYY-MM-DD`). Throws [FormatException] for any other shape and
  /// [ArgumentError] (via the constructor) for a well-shaped but invalid date.
  factory PartialDate.parse(String value) {
    final parts = value.split('-');
    if (parts.isEmpty || parts.length > 3) {
      throw FormatException('invalid PartialDate: "$value"');
    }
    int component(String s, String name, int width) {
      if (s.length != width || int.tryParse(s) == null) {
        throw FormatException('invalid $name in PartialDate: "$value"');
      }
      return int.parse(s);
    }

    final year = component(parts[0], 'year', 4);
    final month = parts.length >= 2 ? component(parts[1], 'month', 2) : null;
    final day = parts.length == 3 ? component(parts[2], 'day', 2) : null;
    return PartialDate(year, month, day);
  }

  /// The year (1–9999). Always present.
  final int year;

  /// The month (1–12), or `null` when the date is known only to the year.
  final int? month;

  /// The day (1–31, valid for the month), or `null` when unspecified.
  final int? day;

  /// The precision to which this date is specified.
  DatePrecision get precision {
    if (day != null) return DatePrecision.day;
    if (month != null) return DatePrecision.month;
    return DatePrecision.year;
  }

  /// The canonical ISO-like string sized to [precision] (see class docs).
  String serialize() {
    final buffer = StringBuffer(_pad4(year));
    if (month != null) {
      buffer.write('-${_pad2(month!)}');
      if (day != null) buffer.write('-${_pad2(day!)}');
    }
    return buffer.toString();
  }

  /// Chronological comparison (== lexicographic order of [serialize]). A less
  /// precise value sorts before a more precise one that shares its prefix, so
  /// `1989 < 1989-03 < 1989-03-01`.
  @override
  int compareTo(PartialDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) return byYear;
    final byMonth = _compareOptional(month, other.month);
    if (byMonth != 0) return byMonth;
    return _compareOptional(day, other.day);
  }

  /// Compares two optional components: absent (`null`, less precise) sorts
  /// before present.
  static int _compareOptional(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) =>
      other is PartialDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'PartialDate(${serialize()})';

  static int _daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && _isLeapYear(year)) return 29;
    return lengths[month - 1];
  }

  static bool _isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static String _pad4(int v) => v.toString().padLeft(4, '0');
}
