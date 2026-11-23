import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../export/program_calendar.dart' show programCalendarUidSuffix;
import '../util/text_sanitizer.dart';

/// The most `VEVENT`s [parseICalFeed] reads from one feed. Events after it
/// are not read, and [ICalFeed.truncated] says so.
const int iCalMaxEvents = 5000;

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
  });

  final List<ICalEvent> events;

  /// `VEVENT`s with no `UID`: they could never be matched again, so they are
  /// not offered.
  final int skippedNoUid;

  /// `VEVENT`s with no readable `DTSTART`.
  final int skippedNoStart;

  /// Whether the feed had more than [iCalMaxEvents] events.
  final bool truncated;
}

/// Parses an iCalendar (RFC 5545) document.
///
/// Handles line unfolding (§3.1) with CRLF or bare LF line ends, parameters,
/// and TEXT unescaping (§3.3.11). Reads only `VEVENT`s at the calendar's top
/// level: other components (`VTIMEZONE`, `VTODO`, `VALARM` inside an event)
/// are skipped. Throws [NotACalendarException] when there is no
/// `BEGIN:VCALENDAR`.
ICalFeed parseICalFeed(String body, {int maxEvents = iCalMaxEvents}) {
  final lines = _unfold(body);
  if (!lines.any((l) => l.trim().toUpperCase() == 'BEGIN:VCALENDAR')) {
    throw const NotACalendarException();
  }
  final events = <ICalEvent>[];
  var skippedNoUid = 0;
  var skippedNoStart = 0;
  var truncated = false;
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
        if (events.length >= maxEvents) {
          truncated = true;
        } else {
          final props = current;
          final uid = _text(props, 'UID');
          final start = _date(props, 'DTSTART');
          if (uid == null || uid.trim().isEmpty) {
            skippedNoUid++;
          } else if (start == null) {
            skippedNoStart++;
          } else {
            events.add(
              ICalEvent(
                uid: uid.trim(),
                start: start,
                end: _date(props, 'DTEND'),
                duration: _duration(props['DURATION']?.first.value),
                summary: _text(props, 'SUMMARY'),
                location: _text(props, 'LOCATION'),
                status: _text(props, 'STATUS')?.trim().toUpperCase(),
                rrule: props['RRULE']?.first.value.trim(),
                exdates: [
                  for (final p in props['EXDATE'] ?? const <_Prop>[])
                    for (final part in p.value.split(','))
                      ?ICalDateValue.tryParse(part),
                ],
                recurrenceId: _date(props, 'RECURRENCE-ID'),
              ),
            );
          }
        }
        current = null;
      }
      if (stack.isNotEmpty) stack.removeLast();
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
  );
}

List<String> _unfold(String body) {
  final physical = body
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final out = <String>[];
  for (final line in physical) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += line.substring(1);
    } else {
      out.add(line);
    }
  }
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

  /// The occurrence dates of a series starting on [start] (its written date),
  /// up to and including [last]. Each is also bounded by [count] and [until]
  /// ([beforeOrAtUntil] compares an occurrence's date and time against it). Walks day
  /// by day, so a series is never expanded past [last] whatever its rule
  /// says; [count] is counted from [start], including occurrences before
  /// today.
  ///
  /// Without [count], nothing before [from] can matter, so the walk starts
  /// there; the rule's alignment (interval, week, month) is still taken from
  /// [start].
  List<DateTime> datesThrough(
    DateTime start,
    DateTime last, {
    required DateTime from,
    required bool Function(DateTime date) beforeOrAtUntil,
  }) {
    final out = <DateTime>[];
    var seen = 0;
    final first = count == null && from.isAfter(start) ? from : start;
    for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      if (!(d == start || _matches(start, d))) continue;
      if (!beforeOrAtUntil(d)) break;
      seen++;
      if (count != null && seen > count!) break;
      out.add(d);
    }
    return out;
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

  /// The first comma-separated segment of `LOCATION`, sanitized and
  /// single-line; the rest (usually a street address) is dropped.
  final String? venueLabel;

  /// For an event whose `UID` is `<id>@callers-compendium` (this app's
  /// calendar export, #2351): that program id.
  final String? exportedProgramId;

  /// [calendarEventFingerprint] of this event as it is now.
  String get fingerprint => calendarEventFingerprint(
    title: title,
    date: date,
    venueLabel: venueLabel,
    startMinute: startMinute,
    endMinute: endMinute,
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

  /// Whether the feed was read whole: not truncated, no repeating rule the
  /// app cannot read, no event whose start it could not read. Only then can
  /// an event's absence mean it is gone.
  final bool canJudgeMissing;

  /// Titles of repeating events whose rule the import cannot read. They are
  /// not imported, and never guessed.
  final List<String> unreadableSeries;

  final int skippedNoUid;
  final bool truncated;
}

/// What a calendar import last wrote from an event (#2354): its title, date,
/// first location segment, start time and end time (#2423), each as a
/// 16-hex-digit SHA-256 prefix, joined as
/// `v2:<title>:<date>:<location>:<start>:<end>`. Kept per field so a later import
/// can say which of them changed upstream. A hash rather than the values: all
/// of them are already stored on the program, which the caller may edit.
String calendarEventFingerprint({
  required String title,
  required DateTime date,
  String? venueLabel,
  int? startMinute,
  int? endMinute,
}) {
  String h(String s) =>
      sha256.convert(utf8.encode(s)).toString().substring(0, 16);
  final d = '${date.year}-${date.month}-${date.day}';
  return 'v2:${h(title)}:${h(d)}:${h(venueLabel ?? '')}'
      ':${h('${startMinute ?? ''}')}:${h('${endMinute ?? ''}')}';
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
///   A rule outside [ICalRecurrence.tryParse]'s subset lists the series in
///   [CalendarImportPlan.unreadableSeries].
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
  final overrides = <String, Map<String, ICalEvent>>{};
  for (final e in feed.events) {
    final rid = e.recurrenceId;
    if (rid != null) (overrides[e.uid] ??= {})[rid.text] = e;
  }
  final seriesUids = {
    for (final e in feed.events)
      if (e.rrule != null && e.recurrenceId == null) e.uid,
  };

  final candidates = <CalendarImportCandidate>[];
  final unreadable = <String>[];

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
        venueLabel: _clean(e.location?.split(',').first),
        exportedProgramId: e.uid.endsWith(programCalendarUidSuffix)
            ? e.uid.substring(0, e.uid.length - programCalendarUidSuffix.length)
            : null,
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
      if (e.isCancelled) continue;
      final title = _clean(e.summary) ?? '';
      if (filter == null ||
          filter.isEmpty ||
          title.toLowerCase().contains(filter)) {
        unreadable.add(title);
      }
      continue;
    }
    final start = e.start.writtenDate;
    final until = rule.until;
    final removed = _removedByExdate(e);
    final seriesOverrides = overrides[e.uid] ?? const {};
    final placed = <String>{};
    // The walk is on written dates; a `Z` series can land a day either side
    // locally, so walk one day past the horizon and filter on local dates.
    for (final d in rule.datesThrough(
      start,
      horizonEnd.add(const Duration(days: 1)),
      from: day0.subtract(const Duration(days: 1)),
      beforeOrAtUntil: (d) =>
          until == null ||
          e.start.onDate(d)._sortKey <= _untilKey(until, e.start, localOf),
    )) {
      final occurrence = e.start.onDate(d);
      final rid = occurrence.text;
      if (removed(d, rid)) continue;
      final override = seriesOverrides[rid];
      if (override != null) {
        placed.add(rid);
        final date = override.start.localDate(localOf);
        if (inRange(date, horizonEnd)) {
          offer(override, rid, date, override.start);
        }
        continue;
      }
      final date = occurrence.localDate(localOf);
      if (inRange(date, horizonEnd)) offer(e, rid, date, occurrence);
    }
    // An override moved into the horizon from an occurrence outside it.
    for (final entry in seriesOverrides.entries) {
      if (placed.contains(entry.key)) continue;
      final date = entry.value.start.localDate(localOf);
      if (inRange(date, horizonEnd)) {
        offer(entry.value, entry.key, date, entry.value.start);
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
  // Single events and overrides at any date; a readable series' occurrences
  // from 31 days back to a day past the window (a program's own date can have
  // been edited away from its occurrence's), less the dates its `EXDATE`
  // removes, which the offer walk above skips too: a deleted occurrence is
  // gone. A moved one is an override, known by its own recurrence id.
  final knownKeys = <String>{};
  final cancelledAnywhere = <String>{};
  void know(ICalEvent e, String recurrenceId) {
    final key = calendarEventKey(e.uid, recurrenceId);
    (e.isCancelled ? cancelledAnywhere : knownKeys).add(key);
  }

  for (final e in feed.events) {
    final rid = e.recurrenceId;
    if (rid != null) {
      know(e, rid.text);
    } else if (e.rrule == null) {
      know(e, '');
    } else if (ICalRecurrence.tryParse(e.rrule!) case final rule?) {
      final until = rule.until;
      final removed = _removedByExdate(e);
      for (final d in rule.datesThrough(
        e.start.writtenDate,
        windowEnd.add(const Duration(days: 1)),
        from: day0.subtract(const Duration(days: 31)),
        beforeOrAtUntil: (d) =>
            until == null ||
            e.start.onDate(d)._sortKey <= _untilKey(until, e.start, localOf),
      )) {
        final rid = e.start.onDate(d).text;
        if (!removed(d, rid)) know(e, rid);
      }
    }
  }
  return CalendarImportPlan(
    candidates: candidates,
    knownKeys: knownKeys,
    cancelledAnywhereKeys: cancelledAnywhere,
    canJudgeMissing:
        !feed.truncated && unreadable.isEmpty && feed.skippedNoStart == 0,
    unreadableSeries: unreadable,
    skippedNoUid: feed.skippedNoUid,
    truncated: feed.truncated,
  );
}

/// Whether a series' `EXDATE` removes the occurrence on written date `d`,
/// whose recurrence id is `rid`. Shared by the offer walk and the known-keys
/// walk of [planCalendarImport], which must agree (#2354): an occurrence one
/// offers and the other forgets would be wrongly flagged gone, and one it
/// skips and the other knows would never be. An occurrence is removed when
/// an `EXDATE` matches its text exactly or, once any `EXDATE` is a `DATE`,
/// when one falls on its written date. A `DATE-TIME` `EXDATE` written in
/// another form from `DTSTART` (UTC against a `TZID` start) matches nothing,
/// which keeps the occurrence: never a false "gone".
bool Function(DateTime d, String rid) _removedByExdate(ICalEvent e) {
  if (e.exdates.isEmpty) return (_, _) => false;
  final anyDate = e.exdates.any((x) => x.isDate);
  final days = {for (final x in e.exdates) x.writtenDate};
  final texts = {for (final x in e.exdates) x.text};
  return (d, rid) => texts.contains(rid) || (anyDate && days.contains(d));
}

/// `UNTIL` as a key comparable with an occurrence written like [start]. A
/// `DATE` `UNTIL` covers its whole day.
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
  if (until.isDate) return until._sortKey + 235959;
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

String? _clean(String? value) {
  if (value == null) return null;
  final s = sanitizeImportedText(value, allowLineBreaks: false).trim();
  return s.isEmpty ? null : s;
}
