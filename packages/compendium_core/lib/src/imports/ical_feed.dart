import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../export/program_calendar.dart' show programCalendarUidSuffix;
import '../util/text_sanitizer.dart';

/// The most `VEVENT`s [parseICalFeed] reads from one feed, not counting a
/// one-off event that is already over (pre-release audit finding E1-07):
/// that can never be offered, so a long-lived calendar written oldest first
/// does not spend the cap on its past and lose its upcoming gigs. Events after
/// it are not read, and [ICalFeed.truncated] says so. A past event is still
/// read, whatever the count, so it is known to be in the calendar; the
/// fetch's size cap bounds how many there can be.
const int iCalMaxEvents = 5000;

/// The most days [planCalendarImport] tries, across all of one feed's
/// series, counting the occurrences a `COUNT` series had before the dates it
/// reads (pre-release audit findings SEC-03 and E1-02): a series dated
/// centuries back would otherwise cost a walk across those centuries, on
/// every import. Only the days a rule can fall on are tried (each day of a
/// daily series, each listed weekday of a weekly one, and so on), so this is
/// about 2,700 years of a daily series between them; a calendar's own series
/// come nowhere near it. Once it is spent, the series that would need more,
/// and every later one with dates to count, is listed in
/// [CalendarImportPlan.unreadableSeries], like a rule the app can't read.
const int iCalCountWorkLimit = 1000000;

/// How far ahead a repeating series is expanded, counted in days from today
/// (maintainer decision on #2352: "Only import repeating series 30 days out,
/// to avoid unbounded import"). An occurrence on day 30 is included.
const int iCalRepeatHorizonDays = 30;

/// Thrown by [parseICalFeed] for a body with no `BEGIN:VCALENDAR` — most often
/// an HTML page, such as a private Google Calendar's ordinary link.
class NotACalendarException implements Exception {
  const NotACalendarException();

  @override
  String toString() => 'NotACalendarException';
}

/// A `DATE` or `DATE-TIME` value as written in the feed (RFC 5545 §3.3.4,
/// §3.3.5). No time-zone database is consulted: a `TZID` value keeps its
/// written local date and time, and a `Z` value is converted by the caller.
class ICalDateValue {
  const ICalDateValue({
    required this.year,
    required this.month,
    required this.day,
    this.hour,
    this.minute,
    this.second,
    this.isUtc = false,
  });

  final int year;
  final int month;
  final int day;

  /// Null for a `DATE` value.
  final int? hour;
  final int? minute;
  final int? second;

  /// Whether the value ends in `Z`.
  final bool isUtc;

  bool get isDate => hour == null;

  /// The value in its written form, without parameters: `20261205`,
  /// `20261205T190000` or `20261205T190000Z`. Used as an occurrence's
  /// recurrence id, so an occurrence the expander generates and a
  /// `RECURRENCE-ID` override written for it compare equal.
  String get text {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${year.toString().padLeft(4, '0')}${two(month)}${two(day)}';
    if (isDate) return date;
    return '${date}T${two(hour!)}${two(minute!)}${two(second!)}'
        '${isUtc ? 'Z' : ''}';
  }

  /// This value with its date moved to [date], time of day kept.
  ICalDateValue onDate(DateTime date) => ICalDateValue(
    year: date.year,
    month: date.month,
    day: date.day,
    hour: hour,
    minute: minute,
    second: second,
    isUtc: isUtc,
  );

  /// The written calendar date, as a UTC midnight.
  DateTime get writtenDate => DateTime.utc(year, month, day);

  /// The date this value falls on for the reader: a `Z` value through
  /// [toLocal]; a `DATE`, floating or `TZID` value as written.
  DateTime localDate(DateTime Function(DateTime utc) toLocal) {
    if (!isUtc || isDate) return writtenDate;
    final local = toLocal(
      DateTime.utc(year, month, day, hour!, minute!, second!),
    );
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// The wall-clock date and time this value falls at for the reader, as a
  /// UTC-flagged container (no instant is implied), or `null` for a `DATE`:
  /// a `Z` value through [toLocal]; a floating or `TZID` value as written
  /// (#2423). The same rule as [localDate], with the time of day kept.
  DateTime? localDateTime(DateTime Function(DateTime utc) toLocal) {
    if (isDate) return null;
    if (!isUtc) return _instant;
    return _wallClock(toLocal(_instant));
  }

  /// The written date and time in a UTC container: the instant itself for a
  /// `Z` value, the wall clock for a floating or `TZID` one. Not for a `DATE`.
  DateTime get _instant =>
      DateTime.utc(year, month, day, hour!, minute!, second!);

  /// [local]'s wall-clock fields in a UTC container.
  static DateTime _wallClock(DateTime local) => DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );

  /// Comparable key: date, then time (a `DATE` sorts as midnight).
  int get _sortKey =>
      ((year * 100 + month) * 100 + day) * 1000000 +
      (hour ?? 0) * 10000 +
      (minute ?? 0) * 100 +
      (second ?? 0);

  static ICalDateValue? tryParse(String raw) {
    final v = raw.trim();
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$',
    ).firstMatch(v);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    // Year 0000 is not read (pre-release audit finding SEC-03): no calendar
    // writes it, and a series starting there is the costliest to count.
    if (year < 1) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (DateTime.utc(year, month, day).day != day) return null;
    if (m.group(4) == null) {
      return ICalDateValue(year: year, month: month, day: day);
    }
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.parse(m.group(6)!);
    if (hour > 23 || minute > 59 || second > 60) return null;
    return ICalDateValue(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second == 60 ? 59 : second,
      isUtc: m.group(7) == 'Z',
    );
  }
}

/// One `VEVENT`, with only the properties the calendar import reads. Text
/// values are unescaped but **not** sanitized: [planCalendarImport] sanitizes
/// what it keeps. `DESCRIPTION`, `ORGANIZER`, `ATTENDEE` and `URL` are never
/// read, so organisers' names, emails and phone numbers have no path in.
class ICalEvent {
  const ICalEvent({
    required this.uid,
    required this.start,
    this.end,
    this.duration,
    this.summary,
    this.location,
    this.status,
    this.rrule,
    this.exdates = const [],
    this.recurrenceId,
  });

  final String uid;
  final ICalDateValue start;

  /// `DTEND`, when the event has one (#2423).
  final ICalDateValue? end;

  /// `DURATION`, when the event has one (RFC 5545 §3.3.6), as a nominal
  /// length: weeks, days, hours, minutes and seconds added together. An
  /// [end] takes precedence where a feed gives both.
  final Duration? duration;
  final String? summary;
  final String? location;

  /// `STATUS`, upper-cased.
  final String? status;

  /// The raw `RRULE` value, if any.
  final String? rrule;
  final List<ICalDateValue> exdates;

  /// Set on an override of one occurrence of a series.
  final ICalDateValue? recurrenceId;

  bool get isCancelled => status == 'CANCELLED';
}

/// What [parseICalFeed] read.
class ICalFeed {
  const ICalFeed({
    required this.events,
    this.skippedNoUid = 0,
    this.skippedNoStart = 0,
    this.truncated = false,
    required this.complete,
  });

  final List<ICalEvent> events;

  /// `VEVENT`s with no `UID`: they could never be matched again, so they are
  /// not offered.
  final int skippedNoUid;

  /// `VEVENT`s with no readable `DTSTART`.
  final int skippedNoStart;

  /// Whether the feed had more than [iCalMaxEvents] events that count
  /// toward it.
  final bool truncated;

  /// Whether the document ended properly: an `END:VCALENDAR` closed it and
  /// no component was left open (pre-release audit finding E1-10). A
  /// response cut off part-way, as a dropped connection can leave it, is
  /// not, and then nothing can be judged missing from it.
  final bool complete;
}

/// Parses an iCalendar (RFC 5545) document.
///
/// Handles line unfolding (§3.1) with CRLF, bare LF or bare CR line ends,
/// parameters, and TEXT unescaping (§3.3.11). Reads only `VEVENT`s at the
/// calendar's top level: other components (`VTIMEZONE`, `VTODO`, `VALARM`
/// inside an event) are skipped. Throws [NotACalendarException] when there is
/// no `BEGIN:VCALENDAR`.
///
/// [maxEvents] counts every event except, when [today] (the reader's local
/// date) is given, a one-off event (no `RRULE`, no `RECURRENCE-ID`) written
/// as starting before yesterday: that is over wherever the reader is, and is
/// read without counting ([iCalMaxEvents]).
ICalFeed parseICalFeed(
  String body, {
  int maxEvents = iCalMaxEvents,
  DateTime? today,
}) {
  final lines = _unfold(body);
  if (!lines.any((l) => l.trim().toUpperCase() == 'BEGIN:VCALENDAR')) {
    throw const NotACalendarException();
  }
  // A `Z` start's local date is at most a day from its written one.
  final pastBefore = today == null
      ? null
      : DateTime.utc(
          today.year,
          today.month,
          today.day,
        ).subtract(const Duration(days: 1));
  final events = <ICalEvent>[];
  var counted = 0;
  var skippedNoUid = 0;
  var skippedNoStart = 0;
  var truncated = false;
  var closed = false;
  // Component nesting below VCALENDAR; an event's own properties are read
  // only at depth 1 inside it.
  final stack = <String>[];
  Map<String, List<_Prop>>? current;
  for (final line in lines) {
    final prop = _Prop.parse(line);
    if (prop == null) continue;
    if (prop.name == 'BEGIN') {
      final kind = prop.value.trim().toUpperCase();
      stack.add(kind);
      if (kind == 'VEVENT' && stack.length == 2 && stack.first == 'VCALENDAR') {
        current = {};
      }
      continue;
    }
    if (prop.name == 'END') {
      final kind = prop.value.trim().toUpperCase();
      if (kind == 'VEVENT' && stack.length == 2 && current != null) {
        final props = current;
        final uid = _text(props, 'UID');
        final start = _date(props, 'DTSTART');
        if (uid == null || uid.trim().isEmpty) {
          skippedNoUid++;
        } else if (start == null) {
          skippedNoStart++;
        } else {
          final rrule = props['RRULE']?.first.value.trim();
          final recurrenceId = _date(props, 'RECURRENCE-ID');
          final past =
              pastBefore != null &&
              rrule == null &&
              recurrenceId == null &&
              start.writtenDate.isBefore(pastBefore);
          if (!past && counted >= maxEvents) {
            truncated = true;
          } else {
            if (!past) counted++;
            events.add(
              ICalEvent(
                uid: uid.trim(),
                start: start,
                end: _date(props, 'DTEND'),
                duration: _duration(props['DURATION']?.first.value),
                summary: _text(props, 'SUMMARY'),
                location: _text(props, 'LOCATION'),
                status: _text(props, 'STATUS')?.trim().toUpperCase(),
                rrule: rrule,
                exdates: [
                  for (final p in props['EXDATE'] ?? const <_Prop>[])
                    for (final part in p.value.split(','))
                      ?ICalDateValue.tryParse(part),
                ],
                recurrenceId: recurrenceId,
              ),
            );
          }
        }
        current = null;
      }
      if (stack.isNotEmpty) {
        stack.removeLast();
        if (kind == 'VCALENDAR' && stack.isEmpty) closed = true;
      }
      continue;
    }
    if (current != null && stack.length == 2) {
      (current[prop.name] ??= []).add(prop);
    }
  }
  return ICalFeed(
    events: events,
    skippedNoUid: skippedNoUid,
    skippedNoStart: skippedNoStart,
    truncated: truncated,
    complete: closed && stack.isEmpty,
  );
}

/// The content lines of [body], unfolded. Each is built in one buffer, so a
/// line folded many times costs time in proportion to its length (pre-release
/// audit finding SEC-03): joining the parts one at a time copied the line so
/// far for every fold.
List<String> _unfold(String body) {
  final physical = body
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final out = <String>[];
  StringBuffer? line;
  for (final part in physical) {
    if ((part.startsWith(' ') || part.startsWith('\t')) && line != null) {
      line.write(part.substring(1));
    } else {
      if (line != null) out.add(line.toString());
      line = StringBuffer(part);
    }
  }
  if (line != null) out.add(line.toString());
  return out;
}

class _Prop {
  const _Prop(this.name, this.value);

  final String name;
  final String value;

  /// Splits `NAME;PARAM=x;PARAM="a:b":value`. Parameters are skipped (a
  /// quoted parameter value may hold `:` or `;`); none is needed: `TZID` keeps
  /// its written local value, and `VALUE=DATE` is visible in the value itself.
  static _Prop? parse(String line) {
    var inQuotes = false;
    int? nameEnd;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (inQuotes) continue;
      if (c == ';') {
        nameEnd ??= i;
      } else if (c == ':') {
        final name = line.substring(0, nameEnd ?? i).trim().toUpperCase();
        if (name.isEmpty) return null;
        return _Prop(name, line.substring(i + 1));
      }
    }
    return null;
  }
}

String? _text(Map<String, List<_Prop>> props, String name) {
  final p = props[name];
  if (p == null || p.isEmpty) return null;
  return unescapeICalendarText(p.first.value);
}

ICalDateValue? _date(Map<String, List<_Prop>> props, String name) {
  final p = props[name];
  if (p == null || p.isEmpty) return null;
  return ICalDateValue.tryParse(p.first.value);
}

/// An RFC 5545 §3.3.6 `DURATION` value, such as "PT3H", "PT2H30M", "P1D" or
/// "P1W", or `null` when it is missing, negative or unreadable.
Duration? _duration(String? raw) {
  if (raw == null) return null;
  final m = RegExp(
    r'^\+?P(?:(\d+)W|(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$',
  ).firstMatch(raw.trim().toUpperCase());
  if (m == null) return null;
  int part(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  if ([1, 2, 3, 4, 5].every((i) => m.group(i) == null)) return null;
  return Duration(
    days: part(1) * 7 + part(2),
    hours: part(3),
    minutes: part(4),
    seconds: part(5),
  );
}

/// Undoes RFC 5545 TEXT escaping: `\\`, `\;`, `\,` and `\n` / `\N`. An
/// unknown escape keeps the character after the backslash.
String unescapeICalendarText(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == r'\' && i + 1 < value.length) {
      final n = value[++i];
      out.write(n == 'n' || n == 'N' ? '\n' : n);
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

// --------------------------------------------------------------- recurrence --

/// A parsed `RRULE` in the subset the import supports, or why it is not.
class ICalRecurrence {
  const ICalRecurrence._({
    required this.freq,
    required this.interval,
    this.count,
    this.until,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.weekStart = DateTime.monday,
  });

  final String freq;
  final int interval;
  final int? count;
  final ICalDateValue? until;

  /// `(ordinal, weekday)`: ordinal 0 means every such weekday; weekday is
  /// [DateTime.monday] … [DateTime.sunday].
  final List<(int, int)> byDay;
  final List<int> byMonthDay;
  final int weekStart;

  static const _days = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };

  /// Parses [rule]. Returns null for a rule outside the supported subset:
  /// `FREQ` = `DAILY`/`WEEKLY`/`MONTHLY`/`YEARLY`, `INTERVAL`, `COUNT`,
  /// `UNTIL`, `BYDAY` (positional, such as `2SA`, only with `MONTHLY`), and
  /// `BYMONTHDAY` (not with `YEARLY`). `WKST` is accepted too: it only moves
  /// where a week starts for a `WEEKLY` rule with an `INTERVAL` above 1, and
  /// common calendar apps write it on ordinary weekly rules.
  static ICalRecurrence? tryParse(String rule) {
    String? freq;
    var interval = 1;
    int? count;
    ICalDateValue? until;
    final byDay = <(int, int)>[];
    final byMonthDay = <int>[];
    var weekStart = DateTime.monday;
    for (final part in rule.split(';')) {
      if (part.trim().isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) return null;
      final key = part.substring(0, eq).trim().toUpperCase();
      final value = part.substring(eq + 1).trim().toUpperCase();
      switch (key) {
        case 'FREQ':
          if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(value)) {
            return null;
          }
          freq = value;
        case 'INTERVAL':
          final n = int.tryParse(value);
          if (n == null || n < 1) return null;
          interval = n;
        case 'COUNT':
          final n = int.tryParse(value);
          if (n == null || n < 1) return null;
          count = n;
        case 'UNTIL':
          until = ICalDateValue.tryParse(value);
          if (until == null) return null;
        case 'BYDAY':
          for (final d in value.split(',')) {
            final m = RegExp(
              r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$',
            ).firstMatch(d.trim());
            if (m == null) return null;
            final ord = m.group(1) == null ? 0 : int.parse(m.group(1)!);
            if (ord.abs() > 5) return null;
            byDay.add((ord, _days[m.group(2)]!));
          }
        case 'BYMONTHDAY':
          for (final d in value.split(',')) {
            final n = int.tryParse(d.trim());
            if (n == null || n == 0 || n.abs() > 31) return null;
            byMonthDay.add(n);
          }
        case 'WKST':
          final d = _days[value];
          if (d == null) return null;
          weekStart = d;
        default:
          return null;
      }
    }
    if (freq == null) return null;
    if (count != null && until != null) return null;
    final positional = byDay.any((d) => d.$1 != 0);
    if (positional && freq != 'MONTHLY') return null;
    if (freq == 'YEARLY' && (byDay.isNotEmpty || byMonthDay.isNotEmpty)) {
      return null;
    }
    return ICalRecurrence._(
      freq: freq,
      interval: interval,
      count: count,
      until: until,
      byDay: byDay,
      byMonthDay: byMonthDay,
      weekStart: weekStart,
    );
  }

  /// The occurrence dates of a series starting on [start] (its written
  /// date), from [from] up to and including [last], or `null` when counting
  /// them would try more than [maxTries] days. Each is also bounded by [count]
  /// and [until] ([beforeOrAtUntil] compares an occurrence's date and time
  /// against it). [tries] is how many days were tried before [from].
  ///
  /// Only the days the rule can fall on are tried ([_candidates]): every
  /// [interval]th day, the days of every [interval]th week or month, or the
  /// date in every [interval]th year, starting from [from]'s own period, so
  /// a series is never expanded past [last] whatever its rule says. [count]
  /// is counted from [start], so for a series with one the occurrences
  /// before [from] are counted first, the same way: the one part whose length
  /// is set by how old the series is rather than by [last], and the part
  /// [maxTries] bounds (pre-release audit findings SEC-03 and E1-02).
  ({List<DateTime> dates, int tries})? datesThrough(
    DateTime start,
    DateTime last, {
    required DateTime from,
    required bool Function(DateTime date) beforeOrAtUntil,
    int? maxTries,
  }) {
    final first = from.isAfter(start) ? from : start;
    final end = last.add(const Duration(days: 1));
    var seen = 0;
    var tries = 0;
    if (count != null && first != start) {
      for (final d in _candidates(start, start, first)) {
        if (maxTries != null && tries >= maxTries) return null;
        tries++;
        if (!(d == start || _matches(start, d))) continue;
        // Ended, or used up, before [from]: nothing from there on.
        if (!beforeOrAtUntil(d) || ++seen >= count!) {
          return (dates: const <DateTime>[], tries: tries);
        }
      }
    }
    final out = <DateTime>[];
    for (final d in _candidates(start, first, end)) {
      if (!(d == start || _matches(start, d))) continue;
      if (!beforeOrAtUntil(d)) break;
      seen++;
      if (count != null && seen > count!) break;
      out.add(d);
    }
    return (dates: out, tries: tries);
  }

  /// The days from [from] (not before [start]) up to, not including, [end],
  /// in order, on which this rule can fall for a series starting on [start]:
  /// [_matches] still decides each. [start] itself is always one, as
  /// `DTSTART` is always the first occurrence.
  Iterable<DateTime> _candidates(
    DateTime start,
    DateTime from,
    DateTime end,
  ) sync* {
    if (!from.isAfter(start) && start.isBefore(end)) yield start;
    for (final d in _ruleDays(start, from, end)) {
      if (d != start) yield d;
    }
  }

  /// The days of [_candidates] the rule itself names. The first is found by
  /// arithmetic, not by walking from [start], and no step is taken past
  /// [end], however large [interval] is.
  Iterable<DateTime> _ruleDays(
    DateTime start,
    DateTime from,
    DateTime end,
  ) sync* {
    DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
    switch (freq) {
      case 'DAILY':
        final total = end.difference(start).inDays;
        var k = from.difference(start).inDays;
        final r = k % interval;
        if (r != 0) {
          if (interval - r >= total - k) return;
          k += interval - r;
        }
        while (k < total) {
          yield start.add(Duration(days: k));
          if (interval >= total - k) return;
          k += interval;
        }
      case 'WEEKLY':
        // Only the weekdays it can fall on, unless BYMONTHDAY picks the days.
        final weekdays = byMonthDay.isNotEmpty
            ? const {1, 2, 3, 4, 5, 6, 7}
            : byDay.isEmpty
            ? {start.weekday}
            : {for (final b in byDay) b.$2};
        final week0 = _weekStartOf(start);
        final weeks = end.difference(week0).inDays ~/ 7;
        var k = _weekStartOf(from).difference(week0).inDays ~/ 7;
        k -= k % interval;
        while (k <= weeks) {
          final weekFirst = week0.add(Duration(days: 7 * k));
          for (var i = 0; i < 7; i++) {
            final d = weekFirst.add(Duration(days: i));
            if (!d.isBefore(end)) return;
            if (!d.isBefore(from) && weekdays.contains(d.weekday)) yield d;
          }
          if (interval > weeks - k) return;
          k += interval;
        }
      case 'MONTHLY':
        final month0 = start.year * 12 + start.month - 1;
        final months = end.year * 12 + end.month - 1 - month0;
        var k = from.year * 12 + from.month - 1 - month0;
        k -= k % interval;
        final weekdays = {for (final b in byDay) b.$2};
        while (k <= months) {
          final y = (month0 + k) ~/ 12;
          final m = (month0 + k) % 12 + 1;
          final len = day(y, m + 1, 0).day;
          final List<int> days;
          if (byMonthDay.isNotEmpty) {
            days = {
              for (final n in byMonthDay)
                if (n.abs() <= len) n > 0 ? n : len + n + 1,
            }.toList()..sort();
          } else if (byDay.isNotEmpty) {
            days = [
              for (var dd = 1; dd <= len; dd++)
                if (weekdays.contains(day(y, m, dd).weekday)) dd,
            ];
          } else {
            days = [if (start.day <= len) start.day];
          }
          for (final dd in days) {
            final d = day(y, m, dd);
            if (!d.isBefore(end)) return;
            if (!d.isBefore(from)) yield d;
          }
          if (interval > months - k) return;
          k += interval;
        }
      case 'YEARLY':
        final years = end.year - start.year;
        var k = from.year - start.year;
        k -= k % interval;
        while (k <= years) {
          final d = day(start.year + k, start.month, start.day);
          // 29 February in a common year is no date.
          if (d.month == start.month) {
            if (!d.isBefore(end)) return;
            if (!d.isBefore(from)) yield d;
          }
          if (interval > years - k) return;
          k += interval;
        }
    }
  }

  bool _matches(DateTime start, DateTime d) {
    switch (freq) {
      case 'DAILY':
        if (d.difference(start).inDays % interval != 0) return false;
        return _byDayPlain(d) && _byMonthDay(d);
      case 'WEEKLY':
        final weeks =
            _weekStartOf(d).difference(_weekStartOf(start)).inDays ~/ 7;
        if (weeks % interval != 0) return false;
        if (byDay.isEmpty && byMonthDay.isEmpty) {
          return d.weekday == start.weekday;
        }
        return _byDayPlain(d) && _byMonthDay(d);
      case 'MONTHLY':
        final months = (d.year - start.year) * 12 + d.month - start.month;
        if (months % interval != 0) return false;
        if (byDay.isEmpty && byMonthDay.isEmpty) return d.day == start.day;
        return _byDayInMonth(d) && _byMonthDay(d);
      case 'YEARLY':
        if ((d.year - start.year) % interval != 0) return false;
        return d.month == start.month && d.day == start.day;
    }
    return false;
  }

  DateTime _weekStartOf(DateTime d) =>
      d.subtract(Duration(days: (d.weekday - weekStart + 7) % 7));

  bool _byDayPlain(DateTime d) =>
      byDay.isEmpty || byDay.any((b) => b.$2 == d.weekday);

  bool _byMonthDay(DateTime d) {
    if (byMonthDay.isEmpty) return true;
    final len = DateTime.utc(d.year, d.month + 1, 0).day;
    return byMonthDay.any((n) => n > 0 ? d.day == n : d.day == len + n + 1);
  }

  bool _byDayInMonth(DateTime d) {
    if (byDay.isEmpty) return true;
    final len = DateTime.utc(d.year, d.month + 1, 0).day;
    final nth = (d.day - 1) ~/ 7 + 1;
    final nthFromEnd = -((len - d.day) ~/ 7 + 1);
    return byDay.any(
      (b) =>
          b.$2 == d.weekday && (b.$1 == 0 || b.$1 == nth || b.$1 == nthFromEnd),
    );
  }
}

// ----------------------------------------------------------------- planning --

/// One calendar event the import could turn into a draft program.
class CalendarImportCandidate {
  const CalendarImportCandidate({
    required this.eventKey,
    required this.title,
    required this.date,
    this.startMinute,
    this.endMinute,
    this.venueLabel,
    this.exportedProgramId,
    this.asWritten,
    this.startsInUtc = false,
  });

  /// [calendarEventKey] of the event's `UID` and recurrence id.
  final String eventKey;

  /// Sanitized, single-line; empty when the summary sanitized to nothing (the
  /// app shows a placeholder).
  final String title;

  /// The event date, `DateTime.utc(y, m, d)`, as the program editor stores it.
  final DateTime date;

  /// When the event starts, as minutes after midnight on [date] at the
  /// reader's wall clock (`Program.startMinute`, #2423), or `null` for an
  /// all-day event. A `Z` time is converted to the reader's local time; a
  /// floating or `TZID` time is taken as written.
  final int? startMinute;

  /// When it ends, on the same rule (`Program.endMinute`): earlier than
  /// [startMinute] when it ends after midnight. `null` when the event has no
  /// start time, no end, or lasts no time or a day or more, none of which a
  /// program's start and end can say.
  final int? endMinute;

  /// The place name `LOCATION` starts with: its first non-blank line up to
  /// the first comma, sanitized, with any whitespace read as a space. The rest
  /// (usually a street address) is dropped, and so is that part when it
  /// holds a number, as a street line does, or the part after its first
  /// comma is a word or two holding one: then `null`.
  final String? venueLabel;

  /// For an event whose `UID` is `<id>@callers-compendium` (this app's
  /// calendar export, #2351): that program id.
  final String? exportedProgramId;

  /// The date, start and end as the calendar writes them, before a `Z`
  /// (UTC) time is moved to the reader's local time: for a `Z` event, the
  /// UTC date and minutes; otherwise the same as [date], [startMinute] and
  /// [endMinute]. Null means the same as those. Only the fingerprint uses
  /// it, so the same event read in another time zone, or on a device in
  /// another zone that syncs the program, is not taken for a changed one.
  final ({DateTime date, int? startMinute, int? endMinute})? asWritten;

  /// Whether the event starts at a `Z` (UTC) time. Then [asWritten]'s date
  /// is the UTC date, and a change of start time alone can move the local
  /// [date]: a change offer must judge the date from both (#2354).
  final bool startsInUtc;

  /// [calendarEventFingerprint] of this event as it is now, from
  /// [asWritten]: it changes only when the event does, whatever the
  /// reader's time zone.
  String get fingerprint => calendarEventFingerprint(
    title: title,
    date: asWritten?.date ?? date,
    venueLabel: venueLabel,
    startMinute: asWritten == null ? startMinute : asWritten!.startMinute,
    endMinute: asWritten == null ? endMinute : asWritten!.endMinute,
    utc: startsInUtc,
  );
}

/// What a feed offers for import, before it is compared with the collection.
class CalendarImportPlan {
  const CalendarImportPlan({
    required this.candidates,
    this.knownKeys = const {},
    this.cancelledAnywhereKeys = const {},
    this.canJudgeMissing = false,
    this.unreadableSeries = const [],
    this.skippedNoUid = 0,
    this.truncated = false,
  });

  /// In date order, and on one date by start time (an all-day event first).
  final List<CalendarImportCandidate> candidates;

  /// Every event the feed holds and does not cancel, whatever its date or
  /// the title filter (#2354): single events and overrides at any date, and
  /// a readable series' occurrences from 31 days back to a day past the
  /// window, less those its `EXDATE` removes. A program whose key is here is
  /// not gone, wherever its event or its one occurrence moved. A series'
  /// occurrence is known by its `UID` and its written date and time, so a
  /// series moved to another day or time, or split "this and following" (a
  /// new `UID`), gives its occurrences new keys, and their programs are not
  /// known; a changed rule keeps the keys of the dates it still has.
  final Set<String> knownKeys;

  /// Like [knownKeys], for cancelled events: a single event, an occurrence of
  /// a cancelled series, or a cancelled override of one occurrence. An
  /// occurrence its series' `EXDATE` removes is in neither set, so it reads
  /// as gone rather than canceled.
  final Set<String> cancelledAnywhereKeys;

  /// Whether the feed was read whole: the document closed properly
  /// ([ICalFeed.complete]), not truncated, no repeating rule the app cannot
  /// read and no `COUNT` series too long to count ([iCalCountWorkLimit]), no
  /// event whose start it could not read. Only then can an event's absence
  /// mean it is gone.
  final bool canJudgeMissing;

  /// Titles of repeating events whose rule the import cannot read, or that
  /// would take too long to count ([iCalCountWorkLimit]). They are not
  /// imported, and never guessed.
  final List<String> unreadableSeries;

  final int skippedNoUid;
  final bool truncated;
}

/// What a calendar import last wrote from an event (#2354): its title, date,
/// venue label (the venue the program stores), start time and end time (#2423), each as a
/// 16-hex-digit SHA-256 prefix, joined as
/// `v2:<title>:<date>:<location>:<start>:<end>`. For a UTC event ([utc]) the
/// date and minutes are UTC, and the date is hashed marked as UTC. Kept per field so a later import
/// can say which of them changed upstream. A hash rather than the values: all
/// of them are already stored on the program, which the caller may edit.
String calendarEventFingerprint({
  required String title,
  required DateTime date,
  String? venueLabel,
  int? startMinute,
  int? endMinute,
  bool utc = false,
}) {
  final h = _fingerprintHash;
  return 'v2:${h(title)}:${h(_fingerprintDate(date, utc: utc))}'
      ':${h(venueLabel ?? '')}'
      ':${h('${startMinute ?? ''}')}:${h('${endMinute ?? ''}')}';
}

/// The date as the fingerprint writes it: a UTC date is marked `Z:`, so a
/// later reading can tell it from a local one (#2354).
String _fingerprintDate(DateTime d, {required bool utc}) =>
    '${utc ? 'Z:' : ''}${d.year}-${d.month}-${d.day}';

String _fingerprintHash(String s) =>
    sha256.convert(utf8.encode(s)).toString().substring(0, 16);

/// Whether the local date [now]'s event started on has moved since [stored]
/// was written (#2354), or null when that cannot be told. Not the same as
/// the date part changing: a UTC event's date part is its UTC date, which
/// can move while the local date stays and the other way round, and a
/// calendar can re-save an event from a local time to UTC or back.
///
/// A date part written from a local time is that local date, so it either
/// is [now]'s local date or the date moved. One written from UTC (marked
/// `Z:`) whose old local date is [now]'s has a UTC date within a day of it:
/// those three are tried, then the start minute (one of 1,440) is found
/// from its hash and read through [toLocal].
bool? calendarFingerprintLocalDateMoved(
  String? stored,
  CalendarImportCandidate now,
  DateTime Function(DateTime utc) toLocal,
) {
  final parts = _fingerprintParts(stored);
  if (parts == null) return null;
  if (parts[1] == _fingerprintHash(_fingerprintDate(now.date, utc: false))) {
    return false;
  }
  for (final offset in const [-1, 0, 1]) {
    final day = now.date.add(Duration(days: offset));
    if (_fingerprintHash(_fingerprintDate(day, utc: true)) != parts[1]) {
      continue;
    }
    for (var m = 0; m < 24 * 60; m++) {
      if (_fingerprintHash('$m') != parts[3]) continue;
      final local = toLocal(
        DateTime.utc(day.year, day.month, day.day, m ~/ 60, m % 60),
      );
      return DateTime.utc(local.year, local.month, local.day) != now.date;
    }
    return null;
  }
  return true;
}

/// Which of title, date, location, start and end differ between two
/// fingerprints
/// ([calendarEventFingerprint]). Null when either is missing or not one this
/// build reads (a `v1` fingerprint, written before times were imported, is
/// not): the caller then knows nothing about what changed.
({bool title, bool date, bool venue, bool start, bool end})?
calendarFingerprintChanges(String? before, String after) {
  final a = _fingerprintParts(before);
  final b = _fingerprintParts(after);
  if (a == null || b == null) return null;
  return (
    title: a[0] != b[0],
    date: a[1] != b[1],
    venue: a[2] != b[2],
    start: a[3] != b[3],
    end: a[4] != b[4],
  );
}

List<String>? _fingerprintParts(String? f) {
  if (f == null) return null;
  final parts = f.split(':');
  if (parts.length != 6 || parts.first != 'v2') return null;
  return parts.sublist(1);
}

/// The stored key for an event: SHA-256 of its `UID`, a newline, and its
/// recurrence id ([ICalDateValue.text]; empty for a single event), as
/// lower-case hex. A digest, not the `UID`, so a `UID` built from an email
/// address is never stored.
String calendarEventKey(String uid, String recurrenceId) =>
    sha256.convert(utf8.encode('$uid\n$recurrenceId')).toString();

/// Turns [feed] into the events a calendar import offers (issue #2352).
///
/// * A single event is offered when its date falls from [today] up to
///   [windowMonths] months ahead, inclusive.
/// * A repeating series is expanded only for occurrences from [today] up to
///   and including day [iCalRepeatHorizonDays], whatever the window. Each
///   occurrence is its own candidate, keyed by `UID` and its start.
///   `EXDATE` removes an occurrence; a `RECURRENCE-ID` override replaces it.
///   Either matches an occurrence written the same way or, written in another
///   form (UTC against a `TZID` start), one that falls at the same local date
///   and time for the reader (pre-release audit finding E1-11). A rule
///   outside [ICalRecurrence.tryParse]'s subset, or a `COUNT` series too long
///   to count ([iCalCountWorkLimit]), lists the series in
///   [CalendarImportPlan.unreadableSeries]. A `UID`'s overrides are offered
///   once, however many series share it (pre-release audit finding SEC-03).
/// * `STATUS:CANCELLED` events, series and overrides are not offered.
/// * [titleFilter], when not blank, keeps events whose sanitized title
///   contains it, ignoring case.
///
/// [today] is the reader's local date. [toLocal] converts a UTC instant to
/// the reader's local time, so a `Z` time lands on the right local date; it
/// is a parameter so tests can inject a time zone.
CalendarImportPlan planCalendarImport(
  ICalFeed feed, {
  required DateTime today,
  required int windowMonths,
  String? titleFilter,
  DateTime Function(DateTime utc)? toLocal,
}) {
  final localOf = toLocal ?? (DateTime utc) => utc.toLocal();
  final day0 = DateTime.utc(today.year, today.month, today.day);
  final windowEnd = _addMonths(day0, windowMonths);
  final horizonEnd = day0.add(const Duration(days: iCalRepeatHorizonDays));
  final filter = titleFilter?.trim().toLowerCase();

  // Overrides, by series UID and the recurrence id they replace.
  final overrides = <String, _Overrides>{};
  for (final e in feed.events) {
    if (e.recurrenceId != null) {
      (overrides[e.uid] ??= _Overrides(localOf)).add(e);
    }
  }
  final seriesUids = {
    for (final e in feed.events)
      if (e.rrule != null && e.recurrenceId == null) e.uid,
  };

  final candidates = <CalendarImportCandidate>[];
  final unreadable = <String>[];
  // #2354: every event the feed holds; see the loop after the sort.
  final knownKeys = <String>{};
  final cancelledAnywhere = <String>{};
  void know(ICalEvent e, String recurrenceId) {
    final key = calendarEventKey(e.uid, recurrenceId);
    (e.isCancelled ? cancelledAnywhere : knownKeys).add(key);
  }

  void listUnreadable(ICalEvent e) {
    if (e.isCancelled) return;
    final title = _clean(e.summary) ?? '';
    if (filter == null ||
        filter.isEmpty ||
        title.toLowerCase().contains(filter)) {
      unreadable.add(title);
    }
  }

  // Days the `COUNT` series may still try ([iCalCountWorkLimit]), and
  // whether one could not be counted: then nothing can be judged missing,
  // whatever its title or status.
  var triesLeft = iCalCountWorkLimit;
  var uncounted = false;
  final overridesOffered = <String>{};

  /// [start] is when this occurrence starts: the event's own `DTSTART`, or
  /// for a series occurrence, the series' moved to that day.
  void offer(
    ICalEvent e,
    String recurrenceId,
    DateTime date,
    ICalDateValue start,
  ) {
    if (e.isCancelled) return;
    final (startMinute, endMinute) = _eventMinutes(e, start, localOf);
    // The same reading with no time-zone move, for the fingerprint (#2354).
    DateTime asIs(DateTime utc) => utc;
    final (writtenStart, writtenEnd) = _eventMinutes(e, start, asIs);
    final title = _clean(e.summary) ?? '';
    if (filter != null &&
        filter.isNotEmpty &&
        !title.toLowerCase().contains(filter)) {
      return;
    }
    candidates.add(
      CalendarImportCandidate(
        eventKey: calendarEventKey(e.uid, recurrenceId),
        title: title,
        date: date,
        startMinute: startMinute,
        endMinute: endMinute,
        venueLabel: _venueLabelOf(e.location),
        exportedProgramId: e.uid.endsWith(programCalendarUidSuffix)
            ? e.uid.substring(0, e.uid.length - programCalendarUidSuffix.length)
            : null,
        asWritten: (
          date: start.localDate(asIs),
          startMinute: writtenStart,
          endMinute: writtenEnd,
        ),
        startsInUtc: start.isUtc && !start.isDate,
      ),
    );
  }

  bool inRange(DateTime d, DateTime end) =>
      !d.isBefore(day0) && !d.isAfter(end);

  for (final e in feed.events) {
    if (e.recurrenceId != null) {
      // An override of a series this feed holds is placed with its series,
      // below. One whose series is missing is offered as a single event.
      if (seriesUids.contains(e.uid)) continue;
      final date = e.start.localDate(localOf);
      if (inRange(date, horizonEnd)) {
        offer(e, e.recurrenceId!.text, date, e.start);
      }
      continue;
    }
    final rrule = e.rrule;
    if (rrule == null) {
      final date = e.start.localDate(localOf);
      if (inRange(date, windowEnd)) offer(e, '', date, e.start);
      continue;
    }
    final rule = ICalRecurrence.tryParse(rrule);
    if (rule == null) {
      listUnreadable(e);
      continue;
    }
    // One walk per series, over everything either use below needs: from 31
    // days back (the known keys) to a day past the window.
    final until = rule.until;
    final untilKey = until == null ? null : _untilKey(until, e.start, localOf);
    final walk = rule.datesThrough(
      e.start.writtenDate,
      windowEnd.add(const Duration(days: 1)),
      from: day0.subtract(const Duration(days: 31)),
      beforeOrAtUntil: (d) =>
          untilKey == null || e.start.onDate(d)._sortKey <= untilKey,
      maxTries: triesLeft,
    );
    if (walk == null) {
      uncounted = true;
      triesLeft = 0;
      listUnreadable(e);
      continue;
    }
    triesLeft -= walk.tries;
    final removed = _removedByExdate(e, localOf);
    final occurrences = [
      for (final d in walk.dates)
        if (e.start.onDate(d) case final o when !removed(o)) o,
    ];
    for (final o in occurrences) {
      know(e, o.text);
    }
    final seriesOverrides = overrides[e.uid];
    // The offers are on written dates; a `Z` series can land a day either
    // side locally, so take one day either side of the horizon and filter on
    // local dates. An occurrence an override replaces is not offered.
    final offerFrom = day0.subtract(const Duration(days: 1));
    final offerTo = horizonEnd.add(const Duration(days: 1));
    for (final occurrence in occurrences) {
      final d = occurrence.writtenDate;
      if (d.isBefore(offerFrom) || d.isAfter(offerTo)) continue;
      if (seriesOverrides?.replacing(occurrence) != null) continue;
      final date = occurrence.localDate(localOf);
      if (inRange(date, horizonEnd)) {
        offer(e, occurrence.text, date, occurrence);
      }
    }
    // Each override is offered on its own date, wherever the occurrence it
    // replaces was, and once per `UID`: with the first readable series of
    // it. A second series with that `UID`, which RFC 5545 does not allow,
    // offers its own occurrences but not the overrides again (pre-release
    // audit finding SEC-03: n such series offered m overrides n times).
    if (!overridesOffered.add(e.uid)) continue;
    for (final override in seriesOverrides?.all ?? const <ICalEvent>[]) {
      final date = override.start.localDate(localOf);
      if (inRange(date, horizonEnd)) {
        offer(override, override.recurrenceId!.text, date, override.start);
      }
    }
  }
  // By date, then start time (an all-day event first), so two gigs on one
  // day are listed in the order they happen.
  candidates.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return (a.startMinute ?? -1).compareTo(b.startMinute ?? -1);
  });

  // #2354: every event the feed holds, whatever its date or the title
  // filter, so a program whose event, or one occurrence of it, only moved is
  // never taken for gone. (A whole series moved, re-ruled or split gets new
  // keys; see [CalendarImportPlan.knownKeys].)
  // Single events and overrides at any date, here; a readable series'
  // occurrences from 31 days back to a day past the window (a program's own
  // date can have been edited away from its occurrence's), less the dates
  // its `EXDATE` removes, in the series loop above, from the same walk as
  // its offers: a deleted occurrence is gone. A moved one is an override,
  // known by its own recurrence id.
  for (final e in feed.events) {
    final rid = e.recurrenceId;
    if (rid != null) {
      know(e, rid.text);
    } else if (e.rrule == null) {
      know(e, '');
    }
  }
  return CalendarImportPlan(
    candidates: candidates,
    knownKeys: knownKeys,
    cancelledAnywhereKeys: cancelledAnywhere,
    canJudgeMissing:
        feed.complete &&
        !feed.truncated &&
        unreadable.isEmpty &&
        !uncounted &&
        feed.skippedNoStart == 0,
    unreadableSeries: unreadable,
    skippedNoUid: feed.skippedNoUid,
    truncated: feed.truncated,
  );
}

/// Whether a series' `EXDATE` removes an occurrence. Shared by the offers
/// and the known keys of [planCalendarImport], which must agree (#2354): an
/// occurrence one offers and the other forgets would be wrongly flagged gone,
/// and one it skips and the other knows would never be. An occurrence is
/// removed when an `EXDATE` matches its text exactly, or, once any `EXDATE`
/// is a `DATE`, when one falls on its written date, or when a `DATE-TIME`
/// `EXDATE` written in another form (UTC against a `TZID` start) falls at
/// its local date and time for the reader ([ICalDateValue.localDateTime];
/// pre-release audit finding E1-11). That is exact when the calendar's zone
/// is the reader's; in another zone the two fall at different times of day,
/// so nothing is removed: never a false "gone".
bool Function(ICalDateValue occurrence) _removedByExdate(
  ICalEvent e,
  DateTime Function(DateTime utc) localOf,
) {
  if (e.exdates.isEmpty) return (_) => false;
  final anyDate = e.exdates.any((x) => x.isDate);
  final days = {for (final x in e.exdates) x.writtenDate};
  final texts = {for (final x in e.exdates) x.text};
  final wallClocks = {for (final x in e.exdates) ?x.localDateTime(localOf)};
  return (o) =>
      texts.contains(o.text) ||
      (anyDate && days.contains(o.writtenDate)) ||
      (!o.isDate && wallClocks.contains(o.localDateTime(localOf)));
}

/// A series' `RECURRENCE-ID` overrides: by the recurrence id as written, and
/// by its local date and time for the reader, for an override written in
/// another form than the series' `DTSTART` (pre-release audit finding
/// E1-11), on the same rule as [_removedByExdate].
class _Overrides {
  _Overrides(this._localOf);

  final DateTime Function(DateTime utc) _localOf;
  final _byText = <String, ICalEvent>{};
  final _byWallClock = <DateTime, ICalEvent>{};

  void add(ICalEvent override) {
    final rid = override.recurrenceId!;
    _byText[rid.text] = override;
    if (rid.localDateTime(_localOf) case final at?) _byWallClock[at] = override;
  }

  /// The override that replaces [occurrence], if any.
  ICalEvent? replacing(ICalDateValue occurrence) =>
      _byText[occurrence.text] ??
      (occurrence.isDate
          ? null
          : _byWallClock[occurrence.localDateTime(_localOf)]);

  /// Every override, one per recurrence id as written.
  Iterable<ICalEvent> get all => _byText.values;
}

/// `UNTIL` as a key comparable with an occurrence written like [start]. A
/// `DATE` `UNTIL` covers its whole day, and so does any `UNTIL` of an
/// all-day series, for which RFC 5545 wants a `DATE`: a floating one its
/// written date, a `Z` one the later of its UTC date and its date in this
/// device's zone. Calendars write the last day's UTC midnight there, which
/// west of Greenwich falls the day before, or its local midnight, which east
/// of it falls in UTC the day before; either way the last day is kept
/// (pre-release audit finding E1-11).
///
/// RFC 5545 §3.3.10 has `UNTIL` in UTC whenever `DTSTART` has a `TZID`, and
/// calendar apps write it so; the occurrences are in that zone's wall-clock
/// time. With no time-zone database, `UNTIL` is moved to this device's local
/// time with [toLocal]: exact when the calendar's zone is the device's (a
/// caller's own calendar, the common case), and otherwise off by the
/// difference between the two zones, which can move the end by one
/// occurrence only for a series that repeats within a day of its `UNTIL`.
int _untilKey(
  ICalDateValue until,
  ICalDateValue start,
  DateTime Function(DateTime utc) toLocal,
) {
  if (until.isDate || start.isDate) {
    var last = until.writtenDate;
    if (until.isUtc && !until.isDate) {
      final local = until.localDate(toLocal);
      if (local.isAfter(last)) last = local;
    }
    return ICalDateValue(
          year: last.year,
          month: last.month,
          day: last.day,
        )._sortKey +
        235959;
  }
  if (until.isUtc && !start.isUtc) {
    final local = toLocal(
      DateTime.utc(
        until.year,
        until.month,
        until.day,
        until.hour!,
        until.minute!,
        until.second!,
      ),
    );
    return ICalDateValue(
      year: local.year,
      month: local.month,
      day: local.day,
      hour: local.hour,
      minute: local.minute,
      second: local.second,
    )._sortKey;
  }
  return until._sortKey;
}

/// The start and end minutes after midnight of [e]'s occurrence starting at
/// [start], at the reader's wall clock (#2423).
///
/// The length comes from the event's own `DTSTART` and `DTEND`, or from its
/// `DURATION` when it has no `DTEND`, and is added to [start], so every
/// occurrence of a series keeps the series' length. An override is a whole
/// event of its own: without a `DTEND` or `DURATION` it has no end, and does
/// not take the series'.
///
/// For a `Z` start the length is measured and added as an instant and the end
/// converted with [localOf], so an event across a daylight-saving change ends
/// at the right local time; a floating or `TZID` event is wall-clock
/// throughout. An end is kept only when the event lasts more than no time and
/// less than a day, and does not fall in the start's own minute: a program's
/// end time is a time of day, read as the next day when it is earlier than
/// the start, so it cannot say anything longer.
(int?, int?) _eventMinutes(
  ICalEvent e,
  ICalDateValue start,
  DateTime Function(DateTime utc) localOf,
) {
  final startAt = start.localDateTime(localOf);
  if (startAt == null) return (null, null);
  final startMinute = startAt.hour * 60 + startAt.minute;
  final end = e.end;
  final Duration? length;
  if (end != null) {
    length = end.isDate || e.start.isDate
        ? null
        : (end.isUtc && e.start.isUtc)
        ? end._instant.difference(e.start._instant)
        : end
              .localDateTime(localOf)!
              .difference(e.start.localDateTime(localOf)!);
  } else {
    length = e.duration;
  }
  if (length == null ||
      length <= Duration.zero ||
      length >= const Duration(days: 1)) {
    return (startMinute, null);
  }
  final endAt = start.isUtc
      ? ICalDateValue._wallClock(localOf(start._instant.add(length)))
      : startAt.add(length);
  final endMinute = endAt.hour * 60 + endAt.minute;
  return (startMinute, endMinute == startMinute ? null : endMinute);
}

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final last = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, d.day > last ? last : d.day);
}

/// The venue label a calendar event's unescaped `LOCATION` gives (#2352): its
/// first non-blank line, up to the first comma, sanitized and trimmed.
/// Calendars write a place picked from a map as the name, then the address on
/// the following lines or after a comma, so this keeps the name.
///
/// `null` when that part holds a number, as a street line does ("12 Elm
/// St", "Hauptstraße 5", "#12", "神宮前１丁目", "建国路八十八号"), or when the
/// part after its first comma is a word or two holding a number ("Via Roma,
/// 10, Milano"). An English ordinal ("1st Church") is not a number here. So a
/// location that starts with a numbered street address gives no venue: `programs.venue` is a
/// shareable label that sync, share files and every export carry. A name
/// that holds a number ("Studio 54") is dropped with it: the caller can type
/// it back, whereas a kept address would travel.
String? _venueLabelOf(String? location) {
  if (location == null) return null;
  final line = location
      .split(_lineBreak)
      .firstWhere((l) => _clean(l) != null, orElse: () => '');
  // Whitespace the sanitizer would strip (a tab) still separates words.
  final parts = line.replaceAll(_whitespace, ' ').split(_comma);
  final label = _clean(parts.first);
  if (label == null || _holdsNumber(label)) return null;
  if (parts.length > 1) {
    final next = _clean(parts[1]);
    if (next != null && _words(next).length <= 2 && _holdsNumber(next)) {
      return null;
    }
  }
  return label;
}

final _lineBreak = RegExp('\r\n|[\n\r\u0085\u2028\u2029]');
final _whitespace = RegExp(r'\s', unicode: true);

/// A comma, fullwidth comma or ideographic comma.
final _comma = RegExp('[,\uFF0C\u3001]');

/// Any numeral, or a number in CJK numerals before a block, lot or house
/// counter (丁目, 番地, 番, 号).
final _digit = RegExp(r'\p{N}|[〇零一二三四五六七八九十百千万]+(?:丁目|番地|番|号)', unicode: true);

/// An English ordinal, which is part of a name ("1st Church", "4th Street
/// Hall"), not a house number.
final _ordinal = RegExp(
  r'^\p{Nd}+(?:st|nd|rd|th)$',
  caseSensitive: false,
  unicode: true,
);

List<String> _words(String s) =>
    s.split(' ').where((w) => w.isNotEmpty).toList();

/// Whether a word of [s] holds a digit and is not an ordinal.
bool _holdsNumber(String s) =>
    _words(s).any((w) => _digit.hasMatch(w) && !_ordinal.hasMatch(w));

String? _clean(String? value) {
  if (value == null) return null;
  final s = sanitizeImportedText(value, allowLineBreaks: false).trim();
  return s.isEmpty ? null : s;
}
