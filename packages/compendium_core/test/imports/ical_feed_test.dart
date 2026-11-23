import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// A calendar document from [events] (each a list of content lines), joined
/// with CRLF unless [lf].
String _cal(
  List<List<String>> events, {
  bool lf = false,
  List<String> extra = const [],
}) {
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Test//EN',
    ...extra,
    for (final e in events) ...['BEGIN:VEVENT', ...e, 'END:VEVENT'],
    'END:VCALENDAR',
  ];
  return lines.join(lf ? '\n' : '\r\n') + (lf ? '\n' : '\r\n');
}

void main() {
  // The injected "today": not the real date, so a version reading the wall
  // clock fails these tests.
  final today = DateTime(2030, 6, 15);
  DateTime utcDay(int y, int m, int d) => DateTime.utc(y, m, d);

  CalendarImportPlan plan(
    String body, {
    int windowMonths = 6,
    String? titleFilter,
    DateTime Function(DateTime utc)? toLocal,
    DateTime? on,
  }) => planCalendarImport(
    parseICalFeed(body),
    today: on ?? today,
    windowMonths: windowMonths,
    titleFilter: titleFilter,
    toLocal: toLocal ?? (u) => u,
  );

  List<DateTime> dates(CalendarImportPlan p) => [
    for (final c in p.candidates) c.date,
  ];

  group('parsing', () {
    test('unfolds folded lines, with CRLF or bare LF', () {
      for (final lf in [false, true]) {
        final feed = parseICalFeed(
          _cal([
            [
              'UID:a',
              'DTSTART;VALUE=DATE:20300620',
              'SUMMARY:Friday ',
              ' Contra',
              '\tDance',
            ],
          ], lf: lf),
        );
        expect(feed.events.single.summary, 'Friday ContraDance');
      }
    });

    test('unescapes TEXT values', () {
      final feed = parseICalFeed(
        _cal([
          [r'UID:a', 'DTSTART:20300620', r'SUMMARY:A\, B\; C\\D\nE'],
        ]),
      );
      expect(feed.events.single.summary, 'A, B; C\\D\nE');
    });

    test('reads DATE, floating, Z and TZID DATE-TIMEs', () {
      final feed = parseICalFeed(
        _cal([
          ['UID:d', 'DTSTART;VALUE=DATE:20300620'],
          ['UID:f', 'DTSTART:20300620T190000'],
          ['UID:z', 'DTSTART:20300620T020000Z'],
          ['UID:t', 'DTSTART;TZID="America/New_York":20300620T190000'],
        ]),
      );
      final byUid = {for (final e in feed.events) e.uid: e.start};
      expect(byUid['d']!.isDate, isTrue);
      expect(byUid['f']!.text, '20300620T190000');
      expect(byUid['z']!.isUtc, isTrue);
      expect(byUid['t']!.text, '20300620T190000');
      expect(byUid['t']!.isUtc, isFalse);
    });

    test('a body that is not a calendar throws NotACalendarException', () {
      expect(
        () => parseICalFeed('<!doctype html><html><body>Sign in</body></html>'),
        throwsA(isA<NotACalendarException>()),
      );
      expect(() => parseICalFeed(''), throwsA(isA<NotACalendarException>()));
    });

    test('skips and counts events with no UID', () {
      final feed = parseICalFeed(
        _cal([
          ['DTSTART:20300620', 'SUMMARY:No uid'],
          ['UID:a', 'DTSTART:20300620'],
        ]),
      );
      expect(feed.events.map((e) => e.uid), ['a']);
      expect(feed.skippedNoUid, 1);
      expect(
        plan(
          _cal([
            ['DTSTART:20300620'],
          ]),
        ).skippedNoUid,
        1,
      );
    });

    test('reads only top-level VEVENTs: not VTODO, VTIMEZONE or a VALARM '
        "property", () {
      final feed = parseICalFeed(
        _cal(
          [
            [
              'UID:a',
              'DTSTART:20300620',
              'SUMMARY:Gig',
              'BEGIN:VALARM',
              'SUMMARY:Alarm text',
              'END:VALARM',
            ],
          ],
          extra: [
            'BEGIN:VTIMEZONE',
            'TZID:X',
            'BEGIN:STANDARD',
            'DTSTART:19701101T020000',
            'END:STANDARD',
            'END:VTIMEZONE',
            'BEGIN:VTODO',
            'UID:todo',
            'DTSTART:20300620',
            'END:VTODO',
          ],
        ),
      );
      expect(feed.events.map((e) => e.uid), ['a']);
      expect(feed.events.single.summary, 'Gig');
    });

    test('stops at the event cap and says so', () {
      final feed = parseICalFeed(
        _cal([
          for (var i = 0; i < 5; i++) ['UID:e$i', 'DTSTART:20300620'],
        ]),
        maxEvents: 3,
      );
      expect(feed.events, hasLength(3));
      expect(feed.truncated, isTrue);
      expect(
        parseICalFeed(
          _cal([
            ['UID:a', 'DTSTART:20300620'],
          ]),
        ).truncated,
        isFalse,
      );
    });
  });

  group('which single events are offered', () {
    test('today is offered, yesterday is not, the last day of the window is, '
        'the day after is not', () {
      final p = plan(
        _cal([
          ['UID:today', 'DTSTART;VALUE=DATE:20300615'],
          ['UID:yesterday', 'DTSTART;VALUE=DATE:20300614'],
          ['UID:last', 'DTSTART;VALUE=DATE:20301215'],
          ['UID:after', 'DTSTART;VALUE=DATE:20301216'],
        ]),
      );
      expect(dates(p), [utcDay(2030, 6, 15), utcDay(2030, 12, 15)]);
    });

    test('the window can be 3 or 12 months', () {
      final body = _cal([
        ['UID:a', 'DTSTART:20300915'],
        ['UID:b', 'DTSTART:20300916'],
        ['UID:c', 'DTSTART:20310615'],
      ]);
      expect(dates(plan(body, windowMonths: 3)), [utcDay(2030, 9, 15)]);
      expect(dates(plan(body, windowMonths: 12)), hasLength(3));
    });

    test('STATUS:CANCELLED is not offered', () {
      final p = plan(
        _cal([
          ['UID:a', 'DTSTART:20300620', 'STATUS:CANCELLED'],
          ['UID:b', 'DTSTART:20300620', 'STATUS:CONFIRMED'],
        ]),
      );
      expect(p.candidates, hasLength(1));
    });

    test('the title filter ignores case', () {
      final p = plan(
        _cal([
          ['UID:a', 'DTSTART:20300620', 'SUMMARY:Contra at Glen Echo'],
          ['UID:b', 'DTSTART:20300620', 'SUMMARY:Dentist'],
        ]),
        titleFilter: 'CONTRA',
      );
      expect(p.candidates.single.title, 'Contra at Glen Echo');
    });
  });

  group('dates and time zones', () {
    final body = _cal([
      ['UID:z', 'DTSTART:20300620T020000Z'],
      ['UID:t', 'DTSTART;TZID=Asia/Tokyo:20300620T020000'],
    ]);
    DateTime Function(DateTime) offset(int hours) =>
        (u) => u.add(Duration(hours: hours));

    test('02:00Z is the previous local date at UTC-8, the same at UTC+9', () {
      final west = plan(body, toLocal: offset(-8));
      final east = plan(body, toLocal: offset(9));
      String keyOf(String uid) => calendarEventKey(uid, '');
      DateTime dateOf(CalendarImportPlan p, String uid) =>
          p.candidates.singleWhere((c) => c.eventKey == keyOf(uid)).date;
      expect(dateOf(west, 'z'), utcDay(2030, 6, 19));
      expect(dateOf(east, 'z'), utcDay(2030, 6, 20));
      // A TZID value keeps its written date under both.
      expect(dateOf(west, 't'), utcDay(2030, 6, 20));
      expect(dateOf(east, 't'), utcDay(2030, 6, 20));
    });
  });

  group('times of day (#2423)', () {
    CalendarImportCandidate one(
      List<String> event, {
      DateTime Function(DateTime utc)? toLocal,
    }) => plan(_cal([event]), toLocal: toLocal).candidates.single;
    (int?, int?) minutes(CalendarImportCandidate c) =>
        (c.startMinute, c.endMinute);
    DateTime Function(DateTime) offset(int hours) =>
        (u) => u.add(Duration(hours: hours));

    test('a floating start and end are taken as written', () {
      final c = one([
        'UID:a',
        'DTSTART:20300620T193000',
        'DTEND:20300620T223000',
      ]);
      expect(minutes(c), (1170, 1350));
    });

    test('a TZID time is taken as written, under any reader zone', () {
      for (final hours in [-8, 0, 9]) {
        final c = one([
          'UID:t',
          'DTSTART;TZID=America/New_York:20300620T193000',
          'DTEND;TZID=America/New_York:20300620T223000',
        ], toLocal: offset(hours));
        expect(minutes(c), (1170, 1350), reason: 'UTC$hours');
        expect(c.date, utcDay(2030, 6, 20));
      }
    });

    test(
      'a Z time is converted to the reader\'s local time, with its date',
      () {
        // 02:30Z-05:30Z: 18:30-21:30 the previous day at UTC-8.
        final west = one([
          'UID:z',
          'DTSTART:20300621T023000Z',
          'DTEND:20300621T053000Z',
        ], toLocal: offset(-8));
        expect(west.date, utcDay(2030, 6, 20));
        expect(minutes(west), (1110, 1290));
        // The same event at UTC+9: 11:30-14:30 on the 21st.
        final east = one([
          'UID:z',
          'DTSTART:20300621T023000Z',
          'DTEND:20300621T053000Z',
        ], toLocal: offset(9));
        expect(east.date, utcDay(2030, 6, 21));
        expect(minutes(east), (690, 870));
      },
    );

    test('an end after midnight is earlier than the start', () {
      final c = one([
        'UID:n',
        'DTSTART:20300620T210000',
        'DTEND:20300621T010000',
      ]);
      expect(minutes(c), (1260, 60));
    });

    test('an event of no length, or a day or more, keeps only its start', () {
      for (final end in [
        '20300620T193000', // no time at all
        '20300621T193000', // exactly a day
        '20300622T200000', // two days
      ]) {
        final c = one(['UID:l', 'DTSTART:20300620T193000', 'DTEND:$end']);
        expect(minutes(c), (1170, null), reason: end);
      }
    });

    test('DURATION gives the same end as DTEND; a day or more gives none', () {
      expect(
        minutes(one(['UID:d', 'DTSTART:20300620T193000', 'DURATION:PT3H'])),
        (1170, 1350),
      );
      expect(
        minutes(one(['UID:d', 'DTSTART:20300620T193000', 'DURATION:PT2H45M'])),
        (1170, 1335),
      );
      expect(
        minutes(one(['UID:d', 'DTSTART:20300620T230000', 'DURATION:PT2H'])),
        (1380, 60),
      );
      for (final d in ['P1D', 'P1W', 'PT24H', 'nonsense', '-PT1H', 'PT']) {
        expect(
          minutes(one(['UID:d', 'DTSTART:20300620T193000', 'DURATION:$d'])),
          (1170, null),
          reason: d,
        );
      }
    });

    // A New York reader: EDT (UTC-4) until 06:00Z on 3 November 2030, then
    // EST (UTC-5).
    DateTime newYork(DateTime u) => u.add(
      Duration(hours: u.isBefore(DateTime.utc(2030, 11, 3, 6)) ? -4 : -5),
    );

    test('a Z event across a daylight-saving change ends at the right local '
        'time, from DTEND or DURATION alike', () {
      // 04:00Z-07:00Z: 00:00 EDT to 02:00 EST, three real hours.
      final viaEnd = plan(
        _cal([
          ['UID:e', 'DTSTART:20301103T040000Z', 'DTEND:20301103T070000Z'],
        ]),
        toLocal: newYork,
        on: DateTime(2030, 11, 1),
      ).candidates.single;
      final viaDuration = plan(
        _cal([
          ['UID:e', 'DTSTART:20301103T040000Z', 'DURATION:PT3H'],
        ]),
        toLocal: newYork,
        on: DateTime(2030, 11, 1),
      ).candidates.single;
      expect(minutes(viaEnd), (0, 120));
      expect(minutes(viaDuration), (0, 120));
    });

    test(
      'a Z series carries its real length, not its first wall-clock span',
      () {
        // First occurrence 04:00Z-07:00Z on 3 Nov spans the change; the next
        // (10 Nov, EST) is 23:00-02:00 local, three hours.
        final p = plan(
          _cal([
            [
              'UID:s',
              'DTSTART:20301103T040000Z',
              'DTEND:20301103T070000Z',
              'RRULE:FREQ=WEEKLY;COUNT=2',
            ],
          ]),
          toLocal: newYork,
          on: DateTime(2030, 11, 1),
        );
        expect(
          [for (final c in p.candidates) (c.date, c.startMinute, c.endMinute)],
          [(utcDay(2030, 11, 3), 0, 120), (utcDay(2030, 11, 9), 1380, 120)],
        );
      },
    );

    test('a Z start with DURATION, away from any change', () {
      expect(
        minutes(
          one([
            'UID:zd',
            'DTSTART:20300621T023000Z',
            'DURATION:PT3H',
          ], toLocal: offset(-8)),
        ),
        (1110, 1290),
      );
    });

    test('an end before the start, or inside the start\'s own minute, keeps '
        'only the start', () {
      for (final end in ['20300620T183000', '20300620T193030']) {
        expect(
          minutes(one(['UID:b', 'DTSTART:20300620T193000', 'DTEND:$end'])),
          (1170, null),
          reason: end,
        );
      }
    });

    test('a DATE end on a timed start keeps only the start', () {
      expect(
        minutes(
          one([
            'UID:m',
            'DTSTART:20300620T193000',
            'DTEND;VALUE=DATE:20300621',
          ]),
        ),
        (1170, null),
      );
    });

    test('an override with no DTEND has no end: it does not take the '
        'series\'', () {
      final p = plan(
        _cal([
          [
            'UID:o',
            'DTSTART:20300615T193000',
            'DTEND:20300615T223000',
            'RRULE:FREQ=WEEKLY;COUNT=2',
          ],
          ['UID:o', 'RECURRENCE-ID:20300622T193000', 'DTSTART:20300622T200000'],
        ]),
      );
      expect(p.candidates.last.date, utcDay(2030, 6, 22));
      expect(minutes(p.candidates.last), (1200, null));
    });

    test('two events on one date are listed in start order, an all-day one '
        'first', () {
      final p = plan(
        _cal([
          ['UID:late', 'DTSTART:20300620T210000', 'SUMMARY:Late'],
          ['UID:all', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:All day'],
          ['UID:early', 'DTSTART:20300620T190000', 'SUMMARY:Early'],
        ]),
      );
      expect(
        [for (final c in p.candidates) c.title],
        ['All day', 'Early', 'Late'],
      );
    });

    test('a start with no end or duration keeps only its start', () {
      expect(minutes(one(['UID:s', 'DTSTART:20300620T193000'])), (1170, null));
    });

    test('an all-day event has no times', () {
      expect(
        minutes(
          one([
            'UID:all',
            'DTSTART;VALUE=DATE:20300620',
            'DTEND;VALUE=DATE:20300621',
          ]),
        ),
        (null, null),
      );
    });

    test("round-trips this app's own timed export", () {
      final ics = programsToICalendar([
        ProgramCalendarEvent(
          programId: 'p-1',
          title: 'Contra',
          date: DateTime.utc(2030, 6, 20),
          updatedAt: DateTime.utc(2030, 1, 1),
          start: const CalendarTimeOfDay(21, 0),
          end: const CalendarTimeOfDay(0, 30),
        ),
      ], now: DateTime.utc(2030));
      final c = plan(ics).candidates.single;
      expect(c.date, utcDay(2030, 6, 20));
      expect(minutes(c), (1260, 30));
    });

    test('every occurrence of a series keeps its times; an override has its '
        'own', () {
      final p = plan(
        _cal([
          [
            'UID:r',
            'DTSTART:20300615T193000',
            'DTEND:20300615T223000',
            'RRULE:FREQ=WEEKLY;COUNT=3',
          ],
          [
            'UID:r',
            'RECURRENCE-ID:20300622T193000',
            'DTSTART:20300622T200000',
            'DTEND:20300622T230000',
          ],
        ]),
      );
      expect(
        [for (final c in p.candidates) (c.date, c.startMinute, c.endMinute)],
        [
          (utcDay(2030, 6, 15), 1170, 1350),
          (utcDay(2030, 6, 22), 1200, 1380),
          (utcDay(2030, 6, 29), 1170, 1350),
        ],
      );
    });
  });

  group('calendarFingerprintChanges (#2354)', () {
    String fp({
      String title = 'T',
      int day = 20,
      String? venue = 'Hall',
      int? start = 1140,
      int? end = 1320,
    }) => calendarEventFingerprint(
      title: title,
      date: DateTime.utc(2030, 6, day),
      venueLabel: venue,
      startMinute: start,
      endMinute: end,
    );

    test('names each field that changed, start and end apart', () {
      expect(calendarFingerprintChanges(fp(), fp(end: 1350)), (
        title: false,
        date: false,
        venue: false,
        start: false,
        end: true,
      ));
      expect(calendarFingerprintChanges(fp(), fp(start: null, end: null)), (
        title: false,
        date: false,
        venue: false,
        start: true,
        end: true,
      ));
      expect(calendarFingerprintChanges(fp(), fp(title: 'U', day: 27)), (
        title: true,
        date: true,
        venue: false,
        start: false,
        end: false,
      ));
    });

    test('calendarFingerprintLocalDateMoved compares the event\'s own '
        'local date, whatever wrote the fingerprint', () {
      DateTime minus4(DateTime u) => u.subtract(const Duration(hours: 4));
      // Now: 20 June locally (UTC-4), written as UTC.
      CalendarImportCandidate utcAt(DateTime utcDate, int minute) =>
          CalendarImportCandidate(
            eventKey: 'k',
            title: 'T',
            date: DateTime.utc(2030, 6, 20),
            asWritten: (date: utcDate, startMinute: minute, endMinute: null),
            startsInUtc: true,
          );
      final now = utcAt(DateTime.utc(2030, 6, 21), 30); // 00:30Z = 20:30
      // Stored from UTC: 23:30Z on 20 June is 19:30 on 20 June: not moved.
      expect(
        calendarFingerprintLocalDateMoved(
          utcAt(DateTime.utc(2030, 6, 20), 23 * 60 + 30).fingerprint,
          now,
          minus4,
        ),
        isFalse,
      );
      // Stored from UTC: 23:30Z on 21 June is 21 June locally: moved.
      expect(
        calendarFingerprintLocalDateMoved(
          utcAt(DateTime.utc(2030, 6, 21), 23 * 60 + 30).fingerprint,
          now,
          minus4,
        ),
        isTrue,
      );
      // Stored from a local time or all-day, on 20 June: not moved; on 21
      // June: moved. Its minute is never read as UTC.
      for (final (day, moved) in [(20, false), (21, true)]) {
        for (final minute in [null, 23 * 60]) {
          expect(
            calendarFingerprintLocalDateMoved(
              calendarEventFingerprint(
                title: 'T',
                date: DateTime.utc(2030, 6, day),
                startMinute: minute,
              ),
              now,
              minus4,
            ),
            moved,
            reason: '$day June, minute $minute',
          );
        }
      }
      // Stored from UTC on the date that is now the local date: 02:00Z on
      // 21 June was 20 June locally, so a reading of 21 June has moved. The
      // UTC mark keeps it from passing as a local 21 June.
      final now21 = CalendarImportCandidate(
        eventKey: 'k',
        title: 'T',
        date: DateTime.utc(2030, 6, 21),
        asWritten: (
          date: DateTime.utc(2030, 6, 21),
          startMinute: 20 * 60,
          endMinute: null,
        ),
        startsInUtc: true,
      );
      expect(
        calendarFingerprintLocalDateMoved(
          utcAt(DateTime.utc(2030, 6, 21), 2 * 60).fingerprint,
          now21,
          minus4,
        ),
        isTrue,
      );
      expect(calendarFingerprintLocalDateMoved(null, now, minus4), isNull);
      expect(
        calendarFingerprintLocalDateMoved('v1:a:b:c', now, minus4),
        isNull,
      );
    });

    test('an unknown or v1 fingerprint, or none, reads as unknown', () {
      expect(calendarFingerprintChanges(null, fp()), isNull);
      expect(calendarFingerprintChanges('v1:a:b:c', fp()), isNull);
      expect(calendarFingerprintChanges('v3:a:b:c:d:e', fp()), isNull);
    });
  });

  group('sanitizing and what is kept', () {
    test('bidi overrides and zero-width characters are stripped from SUMMARY '
        'and LOCATION', () {
      final p = plan(
        _cal([
          [
            'UID:a',
            'DTSTART:20300620',
            'SUMMARY:Con\u202Etra\u200B Night',
            'LOCATION:Glen\u200B Echo\u202D Park\\, 7300 MacArthur Blvd',
          ],
        ]),
      );
      final c = p.candidates.single;
      expect(c.title, 'Contra Night');
      expect(c.venueLabel, 'Glen Echo Park');
    });

    test('only the first LOCATION segment is kept, on one line', () {
      final p = plan(
        _cal([
          [
            'UID:a',
            'DTSTART:20300620',
            r'LOCATION:Glen Echo Park\, 7300 MacArthur Blvd\, Glen Echo\, MD',
          ],
          ['UID:b', 'DTSTART:20300620', r'LOCATION:Town\nHall'],
        ]),
      );
      expect(p.candidates.map((c) => c.venueLabel), [
        'Glen Echo Park',
        isNot(contains('\n')),
      ]);
    });

    test('a title that sanitizes to nothing is empty, for the app to fill', () {
      final p = plan(
        _cal([
          ['UID:a', 'DTSTART:20300620', 'SUMMARY:\u200B\u202E'],
          ['UID:b', 'DTSTART:20300620'],
        ]),
      );
      expect(p.candidates.map((c) => c.title), ['', '']);
    });

    test('the event key is a digest, never the UID', () {
      const uid = 'pat.organiser@example.com';
      final p = plan(
        _cal([
          ['UID:$uid', 'DTSTART:20300620'],
        ]),
      );
      final key = p.candidates.single.eventKey;
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(key.contains('example'), isFalse);
      expect(key, calendarEventKey(uid, ''));
    });

    test('an event this app exported names its program', () {
      final p = plan(
        _cal([
          ['UID:abc-123@callers-compendium', 'DTSTART:20300620'],
          ['UID:other@example.com', 'DTSTART:20300620'],
        ]),
      );
      expect(p.candidates.map((c) => c.exportedProgramId), ['abc-123', null]);
    });

    test("round-trips this app's own calendar export", () {
      final ics = programsToICalendar([
        ProgramCalendarEvent(
          programId: 'p-1',
          title: 'Contra, with; a\nbreak ♪ ${'x' * 80}',
          date: DateTime.utc(2030, 6, 20),
          updatedAt: DateTime.utc(2030, 1, 1),
          location: 'Grange Hall, 123 Main St',
        ),
      ], now: DateTime.utc(2030));
      final c = plan(ics).candidates.single;
      expect(c.exportedProgramId, 'p-1');
      expect(c.date, utcDay(2030, 6, 20));
      // The line break is sanitized away (single-line title).
      expect(c.title, startsWith('Contra, with; a'));
      expect(c.title, contains('♪ xxxx'));
      expect(c.venueLabel, 'Grange Hall');
    });
  });

  group('repeating events', () {
    test('a weekly series yields occurrences through day 30, none after', () {
      // Saturdays from 2030-06-15 (a Saturday). Day 30 is 2030-07-15, a
      // Monday; the last Saturday within it is 2030-07-13.
      final p = plan(
        _cal([
          [
            'UID:w',
            'DTSTART;VALUE=DATE:20300601',
            'RRULE:FREQ=WEEKLY;BYDAY=SA',
          ],
        ]),
      );
      expect(dates(p), [
        utcDay(2030, 6, 15),
        utcDay(2030, 6, 22),
        utcDay(2030, 6, 29),
        utcDay(2030, 7, 6),
        utcDay(2030, 7, 13),
      ]);
    });

    test('an occurrence on day 30 is included', () {
      // Day 30 from 2030-06-15 is 2030-07-15, a Monday.
      final p = plan(
        _cal([
          ['UID:m', 'DTSTART:20300527T190000', 'RRULE:FREQ=WEEKLY'],
        ]),
      );
      expect(dates(p).last, utcDay(2030, 7, 15));
      expect(dates(p).first, utcDay(2030, 6, 17));
    });

    test('each occurrence has its own key, from UID and start', () {
      final p = plan(
        _cal([
          ['UID:w', 'DTSTART:20300615T190000', 'RRULE:FREQ=WEEKLY;COUNT=2'],
        ]),
      );
      expect(p.candidates.map((c) => c.eventKey), [
        calendarEventKey('w', '20300615T190000'),
        calendarEventKey('w', '20300622T190000'),
      ]);
    });

    test('a monthly BYDAY=2SA series yields the second Saturday', () {
      final p = plan(
        _cal([
          [
            'UID:m',
            'DTSTART;VALUE=DATE:20300112',
            'RRULE:FREQ=MONTHLY;BYDAY=2SA',
          ],
        ]),
        on: DateTime(2030, 6, 1),
      );
      // June 2030: the 1st is a Saturday, so the second is the 8th.
      expect(dates(p), [utcDay(2030, 6, 8)]);
    });

    test('a monthly last-Friday (-1FR) and BYMONTHDAY=-1 rule', () {
      final p = plan(
        _cal([
          ['UID:f', 'DTSTART:20300125', 'RRULE:FREQ=MONTHLY;BYDAY=-1FR'],
          ['UID:d', 'DTSTART:20300131', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1'],
        ]),
        on: DateTime(2030, 6, 1),
      );
      expect(dates(p), [utcDay(2030, 6, 28), utcDay(2030, 6, 30)]);
    });

    test('COUNT is counted from the series start', () {
      // Daily from 2030-06-10, five times: the 10th to the 14th, all before
      // today, so nothing is offered.
      expect(
        plan(
          _cal([
            ['UID:c', 'DTSTART:20300610', 'RRULE:FREQ=DAILY;COUNT=5'],
          ]),
        ).candidates,
        isEmpty,
      );
      expect(
        dates(
          plan(
            _cal([
              ['UID:c', 'DTSTART:20300610', 'RRULE:FREQ=DAILY;COUNT=7'],
            ]),
          ),
        ),
        [utcDay(2030, 6, 15), utcDay(2030, 6, 16)],
      );
    });

    test('UNTIL is inclusive', () {
      final p = plan(
        _cal([
          [
            'UID:u',
            'DTSTART:20300615T190000',
            'RRULE:FREQ=DAILY;UNTIL=20300617T190000',
          ],
          [
            'UID:v',
            'DTSTART;VALUE=DATE:20300615',
            'RRULE:FREQ=DAILY;UNTIL=20300616',
          ],
        ]),
      );
      expect(dates(p), [
        utcDay(2030, 6, 15),
        utcDay(2030, 6, 15),
        utcDay(2030, 6, 16),
        utcDay(2030, 6, 16),
        utcDay(2030, 6, 17),
      ]);
    });

    test('a UTC UNTIL ends a TZID series at the right occurrence, for a '
        'device east or west of UTC', () {
      // 19:00 Berlin (UTC+1 in December) is 18:00Z: UNTIL names the last
      // occurrence exactly, as Google and Apple write it.
      final berlin = _cal([
        [
          'UID:b',
          'DTSTART;TZID=Europe/Berlin:20301201T190000',
          'RRULE:FREQ=WEEKLY;UNTIL=20301215T180000Z',
        ],
      ]);
      expect(
        dates(
          plan(
            berlin,
            on: DateTime(2030, 12, 1),
            toLocal: (u) => u.add(const Duration(hours: 1)),
          ),
        ),
        [utcDay(2030, 12, 1), utcDay(2030, 12, 8), utcDay(2030, 12, 15)],
      );
      // 19:00 Los Angeles (UTC-8) is 03:00Z the next day; a daily series
      // must not gain a day after its last.
      final la = _cal([
        [
          'UID:l',
          'DTSTART;TZID=America/Los_Angeles:20301201T190000',
          'RRULE:FREQ=DAILY;UNTIL=20301204T030000Z',
        ],
      ]);
      expect(
        dates(
          plan(
            la,
            on: DateTime(2030, 12, 1),
            toLocal: (u) => u.subtract(const Duration(hours: 8)),
          ),
        ),
        [utcDay(2030, 12, 1), utcDay(2030, 12, 2), utcDay(2030, 12, 3)],
      );
    });

    test('EXDATE removes an occurrence', () {
      final p = plan(
        _cal([
          [
            'UID:x',
            'DTSTART:20300615T190000',
            'RRULE:FREQ=WEEKLY;COUNT=3',
            'EXDATE:20300622T190000',
          ],
        ]),
      );
      expect(dates(p), [utcDay(2030, 6, 15), utcDay(2030, 6, 29)]);
    });

    test('a RECURRENCE-ID override replaces its occurrence; a cancelled one '
        'removes it', () {
      final p = plan(
        _cal([
          [
            'UID:r',
            'DTSTART:20300615T190000',
            'RRULE:FREQ=WEEKLY;COUNT=3',
            'SUMMARY:Weekly',
          ],
          [
            'UID:r',
            'RECURRENCE-ID:20300622T190000',
            'DTSTART:20300623T190000',
            'SUMMARY:Moved to Sunday',
          ],
          [
            'UID:r',
            'RECURRENCE-ID:20300629T190000',
            'DTSTART:20300629T190000',
            'STATUS:CANCELLED',
          ],
        ]),
      );
      expect(
        [for (final c in p.candidates) (c.date, c.title)],
        [
          (utcDay(2030, 6, 15), 'Weekly'),
          (utcDay(2030, 6, 23), 'Moved to Sunday'),
        ],
      );
      expect(
        p.candidates[1].eventKey,
        calendarEventKey('r', '20300622T190000'),
        reason: 'the override keeps the key of the occurrence it replaces',
      );
    });

    test('a rule part outside the supported set yields no programs and a '
        'preview entry', () {
      final p = plan(
        _cal([
          [
            'UID:a',
            'DTSTART:20300615',
            'SUMMARY:Odd one',
            'RRULE:FREQ=WEEKLY;BYSETPOS=1;BYDAY=SA',
          ],
          ['UID:b', 'DTSTART:20300615', 'SUMMARY:Hourly', 'RRULE:FREQ=HOURLY'],
          [
            'UID:c',
            'DTSTART:20300615',
            'SUMMARY:Positional weekly',
            'RRULE:FREQ=WEEKLY;BYDAY=2SA',
          ],
        ]),
      );
      expect(p.candidates, isEmpty);
      expect(p.unreadableSeries, ['Odd one', 'Hourly', 'Positional weekly']);
    });

    test('WKST is read, and moves weeks for an every-other-week rule', () {
      // Every other week on Sunday and Monday, from Sunday 2030-06-16.
      String body(String wkst) => _cal([
        [
          'UID:k',
          'DTSTART;VALUE=DATE:20300616',
          'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=$wkst;COUNT=4',
        ],
      ]);
      // Weeks from Monday: Sun 16 is in the week of Mon 10; Mon 17 opens the
      // next week, which is skipped.
      expect(dates(plan(body('MO'))), [
        utcDay(2030, 6, 16),
        utcDay(2030, 6, 24),
        utcDay(2030, 6, 30),
        utcDay(2030, 7, 8),
      ]);
      // Weeks from Sunday: Sun 16 and Mon 17 are one week.
      expect(dates(plan(body('SU'))), [
        utcDay(2030, 6, 16),
        utcDay(2030, 6, 17),
        utcDay(2030, 6, 30),
        utcDay(2030, 7, 1),
      ]);
    });

    test('guard: a series with no end never yields more than 30 days', () {
      for (final rule in [
        'FREQ=DAILY',
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU',
        'FREQ=MONTHLY;BYMONTHDAY=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,'
            '19,20,21,22,23,24,25,26,27,28,29,30,31',
      ]) {
        final p = plan(
          _cal([
            ['UID:n', 'DTSTART;VALUE=DATE:20000101', 'RRULE:$rule'],
          ]),
          windowMonths: 12,
        );
        expect(p.candidates, hasLength(31), reason: rule);
        expect(dates(p).first, utcDay(2030, 6, 15), reason: rule);
        expect(dates(p).last, utcDay(2030, 7, 15), reason: rule);
      }
    });

    test('moving the clock forward a week offers the newly in-range '
        'occurrences', () {
      final body = _cal([
        ['UID:w', 'DTSTART;VALUE=DATE:20300601', 'RRULE:FREQ=WEEKLY;BYDAY=SA'],
      ]);
      final first = plan(body).candidates.map((c) => c.eventKey).toSet();
      final later = plan(body, on: DateTime(2030, 6, 22)).candidates;
      final fresh = [
        for (final c in later)
          if (!first.contains(c.eventKey)) c.date,
      ];
      expect(fresh, [utcDay(2030, 7, 20)]);
    });
  });
}
