import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Undoes RFC 5545 §3.1 folding and splits into content lines, asserting the
/// physical-line rules on the way: every line ends in CRLF, no bare LF, and
/// none is longer than 75 octets.
List<String> _contentLines(String ics) {
  expect(ics.endsWith('\r\n'), isTrue, reason: 'last line ends in CRLF');
  final physical = ics.substring(0, ics.length - 2).split('\r\n');
  for (final line in physical) {
    expect(line.contains('\n'), isFalse, reason: 'bare LF in "$line"');
    expect(line.contains('\r'), isFalse, reason: 'bare CR in "$line"');
    expect(
      utf8.encode(line).length,
      lessThanOrEqualTo(75),
      reason: 'over 75 octets: "$line"',
    );
  }
  final out = <String>[];
  for (final line in physical) {
    if (line.startsWith(' ')) {
      out[out.length - 1] += line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

/// The first content line of [lines] whose name (before `:` or `;`) is
/// [name], within the first VEVENT.
String? _prop(List<String> lines, String name) {
  for (final line in lines) {
    if (line.startsWith('$name:') || line.startsWith('$name;')) return line;
  }
  return null;
}

String _unescape(String value) {
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

void main() {
  final now = DateTime.utc(2026, 11, 23, 15, 4, 5);
  final updated = DateTime.utc(2026, 11, 20, 12);

  ProgramCalendarEvent event({
    String id = 'p-1',
    String title = 'Friday Contra',
    DateTime? date,
    DateTime? updatedAt,
    CalendarTimeOfDay? start,
    CalendarTimeOfDay? end,
    String? location,
    String? statusLabel,
    String? scheduleLine,
    String? venueTime,
  }) => ProgramCalendarEvent(
    programId: id,
    title: title,
    date: date ?? DateTime.utc(2026, 12, 5),
    updatedAt: updatedAt ?? updated,
    start: start,
    end: end,
    location: location,
    statusLabel: statusLabel,
    scheduleLine: scheduleLine,
    venueTime: venueTime,
  );

  test('writes a calendar wrapper with one VEVENT per program', () {
    final lines = _contentLines(
      programsToICalendar([event(id: 'a'), event(id: 'b')], now: now),
    );
    expect(lines.first, 'BEGIN:VCALENDAR');
    expect(lines.last, 'END:VCALENDAR');
    expect(lines, contains('VERSION:2.0'));
    expect(lines.where((l) => l.startsWith('PRODID:')), hasLength(1));
    expect(lines.where((l) => l == 'BEGIN:VEVENT'), hasLength(2));
    expect(lines.where((l) => l == 'END:VEVENT'), hasLength(2));
    expect(
      lines,
      containsAll(['UID:a@callers-compendium', 'UID:b@callers-compendium']),
    );
    expect(lines.where((l) => l == 'DTSTAMP:20261123T150405Z'), hasLength(2));
  });

  test('an event with no start time is all-day: DATE values, next-day end', () {
    final lines = _contentLines(
      programsToICalendar([event(date: DateTime.utc(2026, 12, 31))], now: now),
    );
    expect(_prop(lines, 'DTSTART'), 'DTSTART;VALUE=DATE:20261231');
    expect(_prop(lines, 'DTEND'), 'DTEND;VALUE=DATE:20270101');
  });

  test('start and end times are floating local DATE-TIMEs', () {
    final lines = _contentLines(
      programsToICalendar([
        event(
          start: const CalendarTimeOfDay(19, 30),
          end: const CalendarTimeOfDay(22, 45),
        ),
      ], now: now),
    );
    expect(_prop(lines, 'DTSTART'), 'DTSTART:20261205T193000');
    expect(_prop(lines, 'DTEND'), 'DTEND:20261205T224500');
    expect(lines.any((l) => l.contains('TZID')), isFalse);
    expect(lines.any((l) => l.startsWith('BEGIN:VTIMEZONE')), isFalse);
  });

  test('an end before the start ends on the next day', () {
    final lines = _contentLines(
      programsToICalendar([
        event(
          start: const CalendarTimeOfDay(20, 0),
          end: const CalendarTimeOfDay(0, 30),
        ),
      ], now: now),
    );
    expect(_prop(lines, 'DTEND'), 'DTEND:20261206T003000');
  });

  test('a start with no end writes no DTEND', () {
    final lines = _contentLines(
      programsToICalendar([
        event(start: const CalendarTimeOfDay(19, 0)),
      ], now: now),
    );
    expect(_prop(lines, 'DTSTART'), 'DTSTART:20261205T190000');
    expect(_prop(lines, 'DTEND'), isNull);
  });

  test('an end with no start is ignored: the event stays all-day', () {
    final lines = _contentLines(
      programsToICalendar([
        event(end: const CalendarTimeOfDay(22, 0)),
      ], now: now),
    );
    expect(_prop(lines, 'DTSTART'), 'DTSTART;VALUE=DATE:20261205');
    expect(_prop(lines, 'DTEND'), 'DTEND;VALUE=DATE:20261206');
  });

  group('text handling', () {
    test('escapes comma, semicolon, backslash and line breaks', () {
      expect(
        escapeICalendarText('a,b;c\\d\ne\r\nf\rg'),
        r'a\,b\;c\\d\ne\nf\ng',
      );
    });

    test('drops control characters a TEXT value may not hold', () {
      expect(escapeICalendarText('a\u0000b\u0007c\u007Fd\te'), 'abcd\te');
    });

    test('a long title with a comma, a semicolon, a newline and a multi-byte '
        'character at the fold boundary round-trips', () {
      // 'SUMMARY:' is 8 octets, 56 x's and the escaped ', a;b\nc' (10 octets)
      // bring the line to 74, so the 3-octet '♪' would end at octet 77 and
      // must move whole to the next physical line.
      final title = '${'x' * 56}, a;b\nc♪ and more text after the fold ♪♪';
      final ics = programsToICalendar([event(title: title)], now: now);
      final physical = ics.split('\r\n');
      final summaryStart = physical.indexWhere((l) => l.startsWith('SUMMARY:'));
      expect(
        physical[summaryStart],
        hasLength(74),
        reason: 'the fold comes before the multi-byte character',
      );
      expect(physical[summaryStart + 1], startsWith(' ♪'));
      final lines = _contentLines(ics);
      final summary = _prop(lines, 'SUMMARY')!;
      expect(_unescape(summary.substring('SUMMARY:'.length)), title);
    });

    test('folds never split a character, whatever its width', () {
      for (final char in ['é', '♪', '𝄞']) {
        for (var pad = 0; pad < 6; pad++) {
          final content = 'SUMMARY:${'y' * pad}${char * 40}';
          final folded = foldICalendarLine(content);
          for (final line in folded.split('\r\n')) {
            expect(utf8.encode(line).length, lessThanOrEqualTo(75));
            // Decoding each physical line on its own would throw (or yield
            // U+FFFD) had a sequence been split.
            expect(utf8.decode(utf8.encode(line), allowMalformed: false), line);
            expect(line.contains('�'), isFalse);
          }
          expect(folded.replaceAll('\r\n ', ''), content);
        }
      }
    });
  });

  group('LOCATION and DESCRIPTION', () {
    test('LOCATION is written escaped, and omitted when absent or blank', () {
      final withLocation = _contentLines(
        programsToICalendar([
          event(location: 'Glen Echo Park, Spanish Ballroom'),
        ], now: now),
      );
      expect(
        _prop(withLocation, 'LOCATION'),
        r'LOCATION:Glen Echo Park\, Spanish Ballroom',
      );
      for (final blank in [null, '', '   ']) {
        final lines = _contentLines(
          programsToICalendar([event(location: blank)], now: now),
        );
        expect(_prop(lines, 'LOCATION'), isNull, reason: 'location "$blank"');
      }
    });

    test(
      'DESCRIPTION holds status, schedule, and venue time without a start',
      () {
        final lines = _contentLines(
          programsToICalendar([
            event(
              statusLabel: 'Finalized',
              scheduleLine: 'Beginner lesson 7:00 pm · Arrive by 6:30 pm',
              venueTime: '8–11 pm',
            ),
          ], now: now),
        );
        expect(
          _unescape(_prop(lines, 'DESCRIPTION')!.substring(12)),
          'Finalized\nBeginner lesson 7:00 pm · Arrive by 6:30 pm\n8–11 pm',
        );
      },
    );

    test(
      "the venue's free-text time is left out when there is a start time",
      () {
        final lines = _contentLines(
          programsToICalendar([
            event(
              statusLabel: 'Draft',
              venueTime: '8–11 pm',
              start: const CalendarTimeOfDay(20, 0),
            ),
          ], now: now),
        );
        expect(_prop(lines, 'DESCRIPTION'), 'DESCRIPTION:Draft');
      },
    );

    test('no DESCRIPTION when there is nothing to say', () {
      final lines = _contentLines(programsToICalendar([event()], now: now));
      expect(_prop(lines, 'DESCRIPTION'), isNull);
    });
  });

  group('re-export', () {
    test('UID depends only on the program id', () {
      String uidOf(ProgramCalendarEvent e) =>
          _prop(_contentLines(programsToICalendar([e], now: now)), 'UID')!;
      final first = uidOf(event(id: 'abc'));
      final edited = uidOf(
        event(
          id: 'abc',
          title: 'Renamed',
          date: DateTime.utc(2027, 1, 2),
          updatedAt: DateTime.utc(2026, 12, 1),
          location: 'Elsewhere',
        ),
      );
      final laterExport = _prop(
        _contentLines(
          programsToICalendar([event(id: 'abc')], now: DateTime.utc(2030)),
        ),
        'UID',
      );
      expect(first, 'UID:abc@callers-compendium');
      expect(edited, first);
      expect(laterExport, first);
      expect(programCalendarUid('abc'), 'abc@callers-compendium');
    });

    test('SEQUENCE and LAST-MODIFIED advance after an edit', () {
      int sequenceOf(DateTime updatedAt) => int.parse(
        _prop(
          _contentLines(
            programsToICalendar([event(updatedAt: updatedAt)], now: now),
          ),
          'SEQUENCE',
        )!.substring('SEQUENCE:'.length),
      );
      final before = DateTime.utc(2026, 11, 20, 12);
      final after = before.add(const Duration(minutes: 1));
      expect(sequenceOf(after), greaterThan(sequenceOf(before)));
      final lines = _contentLines(
        programsToICalendar([event(updatedAt: after)], now: now),
      );
      expect(_prop(lines, 'LAST-MODIFIED'), 'LAST-MODIFIED:20261120T120100Z');
    });

    test('SEQUENCE is never negative', () {
      expect(programCalendarSequence(DateTime.utc(1999)), 0);
      expect(programCalendarSequence(DateTime.utc(2020)), 0);
      expect(programCalendarSequence(DateTime.utc(2020, 1, 1, 1)), 60);
    });
  });
}
