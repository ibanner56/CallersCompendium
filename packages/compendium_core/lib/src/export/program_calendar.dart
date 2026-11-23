import 'dart:convert';

/// A time of day, local to the event: no zone, no seconds.
///
/// The calendar writer emits it as a *floating* time (RFC 5545 §3.3.5,
/// form #1): no `Z` and no `TZID`, so a calendar app shows it at that clock
/// time wherever the reader is.
class CalendarTimeOfDay {
  const CalendarTimeOfDay(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  int get _minutesOfDay => hour * 60 + minute;
}

/// One program, already reduced to what may leave the device in a calendar
/// file (issue #2351).
///
/// Every text value here is taken as given: the caller has already applied
/// the share boundary. In particular [location] must be built from a venue
/// passed through the app's `sanitizeVenueForShare`, never from
/// `Venue.displayName`, which concatenates the postal address
/// unconditionally. The writer has no way to tell an address from a name, so
/// it cannot enforce that itself.
class ProgramCalendarEvent {
  const ProgramCalendarEvent({
    required this.programId,
    required this.title,
    required this.date,
    required this.updatedAt,
    this.start,
    this.end,
    this.location,
    this.statusLabel,
    this.scheduleLine,
    this.venueTime,
  });

  /// `programs.id`. The only input to the event's `UID`.
  final String programId;

  final String title;

  /// The event date. Only its year, month and day are read, as written, with
  /// no time-zone conversion: the editor stores it as `DateTime.utc(y, m, d)`.
  final DateTime date;

  /// The program's last change, for `LAST-MODIFIED` and `SEQUENCE`.
  final DateTime updatedAt;

  /// Start and end times. With no [start] the event is all-day and [end] is
  /// ignored. An [end] earlier than [start] is taken as after midnight, on the
  /// next day.
  final CalendarTimeOfDay? start;
  final CalendarTimeOfDay? end;

  /// The `LOCATION` text, already sanitized; omitted when null or blank.
  final String? location;

  /// The program status as a localized word ("Draft"), first line of
  /// `DESCRIPTION`.
  final String? statusLabel;

  /// An already-formatted line for the beginner-lesson and arrival times
  /// ("Beginner lesson 7:00 pm · Arrive by 6:30 pm"), when either is set. The
  /// app also puts an end time here when there is no [start], since an
  /// all-day event has nowhere else to carry it.
  final String? scheduleLine;

  /// The linked venue's free-text time. Written only when there is no
  /// [start]: it is free text in any format, so it is never parsed into one.
  final String? venueTime;
}

/// The domain-free suffix of every exported `UID`. Fixed, with no host name,
/// so the same program exported from any of the user's devices carries the
/// same `UID`. The calendar import (#2352) recognises it.
const programCalendarUidSuffix = '@callers-compendium';

/// The `UID` for the program with [programId]: `<id>@callers-compendium`.
String programCalendarUid(String programId) =>
    '$programId$programCalendarUidSuffix';

/// The fixed epoch [programCalendarSequence] counts minutes from.
final DateTime _sequenceEpoch = DateTime.utc(2020);

/// The `SEQUENCE` for a program last changed at [updatedAt]: whole minutes
/// since 2020-01-01 UTC, never negative. It only goes up as the program is
/// edited, so a re-export of an edited program carries a higher sequence and a
/// calendar app that honours it replaces the event it already holds.
int programCalendarSequence(DateTime updatedAt) {
  final minutes = updatedAt.toUtc().difference(_sequenceEpoch).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

/// Writes [events] as one iCalendar (RFC 5545) document, one `VEVENT` each.
///
/// Lines end with CRLF and are folded at 75 octets without splitting a UTF-8
/// character (§3.1). Text values are escaped (§3.3.11). [now] is the export
/// time, written as each event's `DTSTAMP`.
///
/// Pure Dart, so it can be unit-tested and parsed back by the calendar import.
String programsToICalendar(
  Iterable<ProgramCalendarEvent> events, {
  required DateTime now,
}) {
  final out = StringBuffer();
  void line(String content) {
    out.write(foldICalendarLine(content));
    out.write('\r\n');
  }

  line('BEGIN:VCALENDAR');
  line('VERSION:2.0');
  line('PRODID:-//Callers Compendium//Program calendar export//EN');
  line('CALSCALE:GREGORIAN');
  line('METHOD:PUBLISH');
  final stamp = _utcDateTime(now);
  for (final event in events) {
    line('BEGIN:VEVENT');
    line('UID:${escapeICalendarText(programCalendarUid(event.programId))}');
    line('DTSTAMP:$stamp');
    final start = event.start;
    final day = DateTime.utc(event.date.year, event.date.month, event.date.day);
    if (start == null) {
      line('DTSTART;VALUE=DATE:${_date(day)}');
      line('DTEND;VALUE=DATE:${_date(day.add(const Duration(days: 1)))}');
    } else {
      line('DTSTART:${_floating(day, start)}');
      final end = event.end;
      if (end != null) {
        final endDay = end._minutesOfDay < start._minutesOfDay
            ? day.add(const Duration(days: 1))
            : day;
        line('DTEND:${_floating(endDay, end)}');
      }
    }
    line('SUMMARY:${escapeICalendarText(event.title)}');
    if (_nonBlank(event.location) case final location?) {
      line('LOCATION:${escapeICalendarText(location)}');
    }
    final description = [
      ?_nonBlank(event.statusLabel),
      ?_nonBlank(event.scheduleLine),
      if (start == null) ?_nonBlank(event.venueTime),
    ];
    if (description.isNotEmpty) {
      line('DESCRIPTION:${escapeICalendarText(description.join('\n'))}');
    }
    line('LAST-MODIFIED:${_utcDateTime(event.updatedAt)}');
    line('SEQUENCE:${programCalendarSequence(event.updatedAt)}');
    line('END:VEVENT');
  }
  line('END:VCALENDAR');
  return out.toString();
}

/// Escapes [value] as an RFC 5545 TEXT value (§3.3.11): backslash, semicolon
/// and comma are backslash-escaped, and every line break (CRLF, CR or LF)
/// becomes `\n`. Other control characters, which a TEXT value may not hold,
/// are dropped.
String escapeICalendarText(String value) {
  final out = StringBuffer();
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final rune in normalized.runes) {
    switch (rune) {
      case 0x5C: // backslash
        out.write(r'\\');
      case 0x3B: // ;
        out.write(r'\;');
      case 0x2C: // ,
        out.write(r'\,');
      case 0x0A:
        out.write(r'\n');
      case 0x09:
        out.writeCharCode(rune);
      case < 0x20 || 0x7F:
        break;
      default:
        out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Folds one content line (without its CRLF) so no physical line is longer
/// than 75 octets of UTF-8 (RFC 5545 §3.1). Each continuation starts with a
/// single space, which counts toward its 75. A character is never split
/// across a fold.
String foldICalendarLine(String content) {
  const limit = 75;
  final out = StringBuffer();
  var used = 0;
  for (final rune in content.runes) {
    final char = String.fromCharCode(rune);
    final octets = utf8.encode(char).length;
    if (used + octets > limit) {
      out.write('\r\n ');
      used = 1;
    }
    out.write(char);
    used += octets;
  }
  return out.toString();
}

String? _nonBlank(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${_two(d.month)}${_two(d.day)}';

String _floating(DateTime day, CalendarTimeOfDay time) =>
    '${_date(day)}T${_two(time.hour)}${_two(time.minute)}00';

String _utcDateTime(DateTime t) {
  final u = t.toUtc();
  return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}
