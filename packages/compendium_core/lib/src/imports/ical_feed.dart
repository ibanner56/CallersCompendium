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
    if (!isUtc) {
      return DateTime.utc(year, month, day, hour!, minute!, second!);
    }
    final local = toLocal(
      DateTime.utc(year, month, day, hour!, minute!, second!),
    );
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  }

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

  /// `DURATION`, when the event has one and no [end] (RFC 5545 §3.3.6), as a
  /// nominal length: weeks, days, hours, minutes and seconds added together.
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

/// An RFC 5545 §3.3.6 `DURATION` value (`PT3H`, `PT2H30M`, `P1D`, `P1W`), or
/// `null` when it is missing, negative or unreadable.
Duration? _duration(String? raw) {
  if (raw == null) return null;
  final m = RegExp(
    r'^\+?P(?:(\d+)W|(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$',
  ).firstMatch(raw.trim().toUpperCase());
  if (m == null || raw.trim().toUpperCase().endsWith('T')) return null;
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
}

/// What a feed offers for import, before it is compared with the collection.
class CalendarImportPlan {
  const CalendarImportPlan({
    required this.candidates,
    this.unreadableSeries = const [],
    this.skippedNoUid = 0,
    this.truncated = false,
  });

  /// In date order.
  final List<CalendarImportCandidate> candidates;

  /// Titles of repeating events whose rule the import cannot read. They are
  /// not imported, and never guessed.
  final List<String> unreadableSeries;

  final int skippedNoUid;
  final bool truncated;
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
    if (e.isCancelled) continue;
    final rule = ICalRecurrence.tryParse(rrule);
    if (rule == null) {
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
    final exdates = {for (final x in e.exdates) x.writtenDate};
    final exTexts = {for (final x in e.exdates) x.text};
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
      if (exTexts.contains(rid) ||
          (e.exdates.any((x) => x.isDate) && exdates.contains(d))) {
        continue;
      }
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
  candidates.sort((a, b) => a.date.compareTo(b.date));
  return CalendarImportPlan(
    candidates: candidates,
    unreadableSeries: unreadable,
    skippedNoUid: feed.skippedNoUid,
    truncated: feed.truncated,
  );
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
/// The length comes from the event's own `DTSTART` and `DTEND`, both at the
/// reader's wall clock, or from its `DURATION`, and is added to [start], so
/// every occurrence of a series keeps the series' length. An end is kept only
/// when the event lasts more than no time and less than a day: a program's
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
  Duration? length = e.duration;
  final end = e.end;
  if (end != null) {
    final endAt = end.localDateTime(localOf);
    final eventStartAt = e.start.localDateTime(localOf);
    length = endAt == null || eventStartAt == null
        ? null
        : endAt.difference(eventStartAt);
  }
  if (length == null ||
      length <= Duration.zero ||
      length >= const Duration(days: 1)) {
    return (startMinute, null);
  }
  final endAt = startAt.add(length);
  return (startMinute, endAt.hour * 60 + endAt.minute);
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
