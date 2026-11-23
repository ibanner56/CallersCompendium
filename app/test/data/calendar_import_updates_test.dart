import 'dart:convert';

import 'package:compendium_app/src/data/calendar_import.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

String _cal(List<List<String>> events) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  for (final e in events) ...['BEGIN:VEVENT', ...e, 'END:VEVENT'],
  'END:VCALENDAR',
  '',
].join('\r\n');

/// An injected "today", not the real date.
final _today = DateTime(2030, 6, 15);
final _t0 = DateTime.utc(2030, 6, 15, 12);
final _t1 = DateTime.utc(2030, 6, 16, 12);
final _t2 = DateTime.utc(2030, 6, 17, 12);

Future<CalendarImportPreview> _preview(
  CompendiumRepositories repos,
  String body, {
  DateTime? today,
  CalendarImportSettings settings = const CalendarImportSettings(),
}) => buildCalendarImportPreview(
  repos,
  body: body,
  settings: settings,
  today: today ?? _today,
  toLocal: (u) => u,
);

Future<List<String>> _importNew(
  CompendiumRepositories repos,
  String body,
) async {
  final preview = await _preview(repos, body);
  return commitCalendarImport(
    repos,
    chosen: [
      for (final e in preview.entries)
        if (e.tickedByDefault) e,
    ],
    untitledTitle: 'Untitled event',
    now: _t0,
  );
}

/// Presses Import in a review of [body], with [accepted] program ids ticked
/// (by default, whatever starts ticked).
Future<List<CalendarUpdateRecord>> _apply(
  CompendiumRepositories repos,
  String body, {
  Set<String>? accepted,
  DateTime? today,
  DateTime? now,
}) async {
  final preview = await _preview(repos, body, today: today);
  return applyCalendarUpdates(
    repos,
    preview: preview,
    accepted:
        accepted ??
        {
          for (final c in preview.changes)
            if (c.untouched && calendarOfferVisible(c)) c.program.id,
        },
    now: now ?? _t1,
  );
}

final _original = _cal([
  [
    'UID:a',
    'DTSTART;VALUE=DATE:20300620',
    'SUMMARY:Contra A',
    r'LOCATION:Glen Echo Park\, 7300 MacArthur Blvd',
  ],
]);
final _moved = _cal([
  [
    'UID:a',
    'DTSTART;VALUE=DATE:20300627',
    'SUMMARY:Contra A',
    r'LOCATION:Glen Echo Park\, 7300 MacArthur Blvd',
  ],
]);
final _cancelled = _cal([
  [
    'UID:a',
    'DTSTART;VALUE=DATE:20300620',
    'SUMMARY:Contra A',
    'STATUS:CANCELLED',
  ],
]);
final _empty = _cal([]);

Future<Program> _only(CompendiumRepositories repos) async =>
    (await repos.programs.listAll(includeDeleted: true)).single;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an imported draft is untouched until the caller edits it', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final p = await _only(repos);
    expect(p.isUntouchedCalendarDraft, isTrue);
    expect(p.calendarEventFingerprint, isNotNull);
    await repos.programs.update(p.copyWith(notes: 'n', updatedAt: _t1));
    expect((await _only(repos)).isUntouchedCalendarDraft, isFalse);
  });

  test('an upstream date change to an untouched draft is offered ticked, '
      'changes nothing until Import, and Undo restores it', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final before = await _only(repos);

    final preview = await _preview(repos, _moved);
    final offer = preview.changes.single;
    expect(offer.untouched, isTrue);
    expect((offer.date, offer.title, offer.venue), (true, false, false));
    expect(await _only(repos), before, reason: 'the review writes nothing');

    final prior = await applyCalendarUpdates(
      repos,
      preview: preview,
      accepted: {offer.program.id},
      now: _t1,
    );
    final after = await _only(repos);
    expect(after.eventDate, DateTime.utc(2030, 6, 27));
    expect(
      after.isUntouchedCalendarDraft,
      isTrue,
      reason: "the import's own write keeps it untouched",
    );

    await undoCalendarUpdates(repos, prior, now: _t2);
    final undone = await _only(repos);
    expect(undone.eventDate, DateTime.utc(2030, 6, 20));
    expect(undone.isUntouchedCalendarDraft, isTrue);
  });

  test(
    'closing the review without Import leaves every program unchanged',
    () async {
      final repos = openTestRepositories();
      await _importNew(repos, _original);
      final before = await repos.programs.listAll(includeDeleted: true);
      await _preview(repos, _moved);
      await _preview(repos, _cancelled);
      await _preview(repos, _empty);
      expect(await repos.programs.listAll(includeDeleted: true), before);
    },
  );

  test('guard: a program whose slot the caller edited is offered unticked; '
      'title, date and venue stay until the caller ticks it', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final p = await _only(repos);
    await repos.programs.update(
      p.copyWith(
        slots: [ProgramSlot(id: 's1', position: 0, text: 'Waltz')],
        updatedAt: _t1,
      ),
    );
    final edited = await _only(repos);

    final preview = await _preview(repos, _moved);
    expect(preview.changes.single.untouched, isFalse);
    // Import with the default ticks: nothing is ticked for this one.
    await _apply(repos, _moved, now: _t2);
    final after = await _only(repos);
    expect(after.title, edited.title);
    expect(after.eventDate, edited.eventDate);
    expect(after.venue, edited.venue);
    expect(after.slots.single.text, 'Waltz');

    // Ticking it updates only the date, which is what changed upstream.
    final again = await _preview(
      repos,
      _cal([
        [
          'UID:a',
          'DTSTART;VALUE=DATE:20300704',
          'SUMMARY:Contra A',
          r'LOCATION:Glen Echo Park\, 7300 MacArthur Blvd',
        ],
      ]),
    );
    final offer = again.changes.single;
    await applyCalendarUpdates(
      repos,
      preview: again,
      accepted: {offer.program.id},
      now: _t2.add(const Duration(hours: 1)),
    );
    final ticked = await _only(repos);
    expect(ticked.eventDate, DateTime.utc(2030, 7, 4));
    expect(ticked.slots.single.text, 'Waltz');
  });

  test(
    'an unticked offer is not offered again until the event changes again',
    () async {
      final repos = openTestRepositories();
      await _importNew(repos, _original);
      final p = await _only(repos);
      await repos.programs.update(p.copyWith(notes: 'mine', updatedAt: _t1));
      await _apply(repos, _moved, now: _t2);
      final again = await _preview(repos, _moved);
      expect(again.changes.where(calendarOfferVisible), isEmpty);
    },
  );

  group('guard: cancelled and missing events never edit or delete', () {
    for (final (label, body, flag) in [
      ('cancelled', _cancelled, calendarFlagCancelled),
      ('missing from the feed', _empty, calendarFlagMissing),
    ]) {
      test(label, () async {
        final repos = openTestRepositories();
        await _importNew(repos, _original);
        final before = await _only(repos);
        final preview = await _preview(repos, body);
        expect(preview.flagged.single.flag, flag);
        await _apply(repos, body);
        final after = await _only(repos);
        expect(after.isDeleted, isFalse);
        expect(after.isArchived, isFalse);
        expect(after.title, before.title);
        expect(after.eventDate, before.eventDate);
        expect(after.venue, before.venue);
        expect(after.slots, before.slots);
        expect(after.calendarFlag, flag);
      });
    }
  });

  test(
    'the flag clears when the event reappears, and when dismissed',
    () async {
      final repos = openTestRepositories();
      await _importNew(repos, _original);
      await _apply(repos, _empty);
      expect((await _only(repos)).calendarFlag, calendarFlagMissing);
      await _apply(repos, _original, now: _t2);
      expect((await _only(repos)).calendarFlag, isNull);

      await _apply(repos, _cancelled, now: _t2.add(const Duration(hours: 1)));
      final flagged = await _only(repos);
      expect(flagged.calendarFlag, calendarFlagCancelled);
      await clearCalendarFlag(
        repos,
        flagged,
        now: _t2.add(const Duration(hours: 2)),
      );
      final cleared = await _only(repos);
      expect(cleared.calendarFlag, isNull);
      expect(
        cleared.isUntouchedCalendarDraft,
        isTrue,
        reason: 'dismissing a flag is not working on the program',
      );
    },
  );

  group('an event that moved is not reported gone', () {
    // "Today" comes from an injected clock, as in the app.
    final fixed = Clock.fixed(DateTime(2030, 6, 15, 9));
    DateTime clockToday() {
      final n = clock.now();
      return DateTime(n.year, n.month, n.day);
    }

    test('a single event moved beyond the date window', () async {
      await withClock(fixed, () async {
        final repos = openTestRepositories();
        await _importNew(repos, _original);
        final moved = _cal([
          ['UID:a', 'DTSTART;VALUE=DATE:20310601', 'SUMMARY:Contra A'],
        ]);
        final preview = await _preview(repos, moved, today: clockToday());
        expect(preview.flagChanges, isEmpty);
      });
    });

    test('a repeating occurrence moved past day 30 by an override', () async {
      await withClock(fixed, () async {
        final repos = openTestRepositories();
        final series = [
          'UID:w',
          'DTSTART;VALUE=DATE:20300601',
          'RRULE:FREQ=WEEKLY;BYDAY=SA',
          'SUMMARY:Weekly',
        ];
        await _importNew(repos, _cal([series]));
        // The 13 July occurrence (day 28) moves to 20 July (day 35).
        final movedOut = _cal([
          series,
          [
            'UID:w',
            'RECURRENCE-ID;VALUE=DATE:20300713',
            'DTSTART;VALUE=DATE:20300720',
            'SUMMARY:Weekly',
          ],
        ]);
        final preview = await _preview(repos, movedOut, today: clockToday());
        expect(preview.flagChanges, isEmpty);
      });
    });

    test(
      'a program dated in the past, or beyond the 30 days read in full',
      () async {
        await withClock(fixed, () async {
          final repos = openTestRepositories();
          await _importNew(repos, _original);
          final later = await _preview(
            repos,
            _empty,
            today: DateTime(2030, 6, 25),
          );
          expect(later.flagChanges, isEmpty);
          final far = openTestRepositories();
          await far.programs.create(
            Program(
              id: 'far',
              title: 'Far',
              eventDate: DateTime.utc(2030, 9, 1),
              calendarEventKey: calendarEventKey('far', ''),
              createdAt: _t0,
              updatedAt: _t0,
            ),
          );
          expect(
            (await _preview(far, _empty, today: clockToday())).flagChanges,
            isEmpty,
          );
        });
      },
    );
  });

  group('an occurrence deleted with EXDATE is flagged gone', () {
    for (final (label, start, exdate) in [
      (
        'all-day series',
        'DTSTART;VALUE=DATE:20300601',
        'EXDATE;VALUE=DATE:20300622',
      ),
      ('timed series', 'DTSTART:20300601T190000', 'EXDATE:20300622T190000'),
      (
        'timed series, whole-day EXDATE',
        'DTSTART:20300601T190000',
        'EXDATE;VALUE=DATE:20300622',
      ),
      ('UTC series', 'DTSTART:20300601T170000Z', 'EXDATE:20300622T170000Z'),
    ]) {
      test(label, () async {
        final repos = openTestRepositories();
        final series = [
          'UID:w',
          start,
          'RRULE:FREQ=WEEKLY;BYDAY=SA',
          'SUMMARY:Weekly',
        ];
        await _importNew(repos, _cal([series]));
        // The 22 June occurrence (day 7) is deleted in the calendar.
        final preview = await _preview(
          repos,
          _cal([
            [...series, exdate],
          ]),
        );
        final gone = [
          for (final f in preview.flagChanges)
            if (f.flag != null) f,
        ];
        expect(gone, hasLength(1));
        expect(gone.single.flag, calendarFlagMissing);
        final date = gone.single.program.eventDate!;
        expect((date.year, date.month, date.day), (2030, 6, 22));
      });
    }
  });

  group('a whole series changed: the dates it no longer has read as gone, '
      'and its new dates are offered', () {
    // The injected today is Saturday 15 June 2030; the first import takes
    // the five Saturdays through day 30: 15, 22, 29 June, 6 and 13 July.
    List<String> weekly(String uid, List<String> when) => [
      'UID:$uid',
      ...when,
      'SUMMARY:Weekly',
    ];
    final original = weekly('w', [
      'DTSTART:20300601T190000',
      'RRULE:FREQ=WEEKLY;BYDAY=SA',
    ]);
    for (final (label, feed, goneCount, freshCount) in [
      (
        'moved to another time',
        [
          weekly('w', [
            'DTSTART:20300601T193000',
            'RRULE:FREQ=WEEKLY;BYDAY=SA',
          ]),
        ],
        5,
        5,
      ),
      (
        // Fridays 21 June to 12 July.
        'moved to another day',
        [
          weekly('w', [
            'DTSTART:20300607T190000',
            'RRULE:FREQ=WEEKLY;BYDAY=FR',
          ]),
        ],
        5,
        4,
      ),
      (
        // Every other Saturday from 1 June keeps 15 and 29 June and 13 July.
        'repeating less often',
        [
          weekly('w', [
            'DTSTART:20300601T190000',
            'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SA',
          ]),
        ],
        2,
        0,
      ),
      (
        // "This and following" from 29 June: the old series ends on 22 June,
        // and a new UID carries the same times on.
        'split "this and following"',
        [
          weekly('w', [
            'DTSTART:20300601T190000',
            'RRULE:FREQ=WEEKLY;BYDAY=SA;UNTIL=20300622T235959',
          ]),
          weekly('w2', [
            'DTSTART:20300629T190000',
            'RRULE:FREQ=WEEKLY;BYDAY=SA',
          ]),
        ],
        3,
        3,
      ),
    ]) {
      test(label, () async {
        final repos = openTestRepositories();
        final imported = await _importNew(repos, _cal([original]));
        expect(imported, hasLength(5));
        final preview = await _preview(repos, _cal(feed));
        expect(
          preview.flagChanges.where((f) => f.flag == calendarFlagMissing),
          hasLength(goneCount),
        );
        expect(
          preview.entries.where((e) => e.state == CalendarEntryState.fresh),
          hasLength(freshCount),
        );
      });
    }
  });

  group(
    'event times (#2423) are offered and applied like the other fields',
    () {
      String timed(String day, String start, String end) => _cal([
        [
          'UID:t',
          'DTSTART:${day}T$start',
          'DTEND:${day}T$end',
          'SUMMARY:Contra T',
        ],
      ]);
      final original = timed('20300620', '190000', '220000');

      test('a date and time move on an untouched draft updates both', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        final before = await _only(repos);
        expect((before.startMinute, before.endMinute), (19 * 60, 22 * 60));
        final moved = timed('20300626', '200000', '230000');
        final offer = (await _preview(repos, moved)).changes.single;
        expect((offer.date, offer.time, offer.untouched), (true, true, true));
        await _apply(repos, moved);
        final after = await _only(repos);
        expect(after.eventDate, DateTime.utc(2030, 6, 26));
        expect((after.startMinute, after.endMinute), (20 * 60, 23 * 60));
        expect(after.isUntouchedCalendarDraft, isTrue);
      });

      test('a time-only change is offered, and Import applies it', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        final later = timed('20300620', '193000', '223000');
        final offer = (await _preview(repos, later)).changes.single;
        expect(
          (offer.title, offer.date, offer.venue, offer.time),
          (false, false, false, true),
        );
        expect(calendarOfferVisible(offer), isTrue);
        await _apply(repos, later);
        final after = await _only(repos);
        expect(
          (after.startMinute, after.endMinute),
          (19 * 60 + 30, 22 * 60 + 30),
        );
      });

      test('an event made all-day clears the times', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        final allDay = _cal([
          ['UID:t', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:Contra T'],
        ]);
        await _apply(repos, allDay);
        final after = await _only(repos);
        expect((after.startMinute, after.endMinute), (null, null));
      });

      group('a UTC (Z) event read in another time zone', () {
        // Imported at UTC-4, read again at UTC+1: the same instant reads
        // 19:00-22:00 on 20 June there and 00:00-03:00 on 21 June here.
        DateTime west(DateTime u) => u.subtract(const Duration(hours: 4));
        DateTime east(DateTime u) => u.add(const Duration(hours: 1));
        String utc(String start, String end) => _cal([
          ['UID:z', 'DTSTART:$start', 'DTEND:$end', 'SUMMARY:Contra Z'],
        ]);
        Future<CalendarImportPreview> read(
          CompendiumRepositories repos,
          String body,
          DateTime Function(DateTime) toLocal,
        ) => buildCalendarImportPreview(
          repos,
          body: body,
          settings: const CalendarImportSettings(),
          today: _today,
          toLocal: toLocal,
        );
        Future<void> importAt(
          CompendiumRepositories repos,
          String body,
          DateTime Function(DateTime) toLocal,
        ) async {
          final preview = await read(repos, body, toLocal);
          await commitCalendarImport(
            repos,
            chosen: [
              for (final e in preview.entries)
                if (e.tickedByDefault) e,
            ],
            untitledTitle: 'Untitled event',
            now: _t0,
          );
        }

        test('an unchanged event is not offered as a change', () async {
          final repos = openTestRepositories();
          final body = utc('20300620T230000Z', '20300621T020000Z');
          await importAt(repos, body, west);
          final p = await _only(repos);
          expect((p.startMinute, p.endMinute), (19 * 60, 22 * 60));
          final preview = await read(repos, body, east);
          expect(preview.changes.where(calendarOfferVisible), isEmpty);
        });

        test('a real change is offered, read in this time zone', () async {
          final repos = openTestRepositories();
          await importAt(
            repos,
            utc('20300620T230000Z', '20300621T020000Z'),
            west,
          );
          // An hour later in the calendar: 01:00-04:00 on 21 June here.
          final preview = await read(
            repos,
            utc('20300621T000000Z', '20300621T030000Z'),
            east,
          );
          final offer = preview.changes.single;
          expect(
            (offer.start, offer.end, offer.candidate.startMinute),
            (true, true, 60),
          );
        });
      });

      Future<void> workOn(CompendiumRepositories repos, {int? start}) async {
        final p = await _only(repos);
        await repos.programs.update(
          p.copyWith(
            notes: 'mine',
            startMinute: start,
            lessonMinute: 18 * 60,
            arrivalMinute: 18 * 60 + 30,
            updatedAt: _t0.add(const Duration(hours: 1)),
          ),
        );
      }

      test('on a worked-on program only the time that changed upstream is '
          'offered, so the caller\'s own start survives a new end', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        await workOn(repos, start: 19 * 60 + 30);
        final later = timed('20300620', '190000', '223000');
        final offer = (await _preview(repos, later)).changes.single;
        expect((offer.start, offer.end, offer.untouched), (false, true, false));
        await _apply(repos, later, accepted: {offer.program.id});
        final after = await _only(repos);
        expect(
          (after.startMinute, after.endMinute),
          (19 * 60 + 30, 22 * 60 + 30),
        );
        expect(
          (after.lessonMinute, after.arrivalMinute),
          (18 * 60, 18 * 60 + 30),
          reason: 'lesson and arrival times are never touched',
        );
      });

      test('a caller\'s edited time is not offered back when only the title '
          'changes upstream', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        await workOn(repos, start: 19 * 60 + 30);
        final renamed = _cal([
          [
            'UID:t',
            'DTSTART:20300620T190000',
            'DTEND:20300620T220000',
            'SUMMARY:Contra T, renamed',
          ],
        ]);
        final offer = (await _preview(repos, renamed)).changes.single;
        expect((offer.title, offer.time), (true, false));
      });

      test(
        'a ticked time offer leaves lesson and arrival times alone',
        () async {
          final repos = openTestRepositories();
          await _importNew(repos, original);
          final p = await _only(repos);
          // Set lesson and arrival through the import's own stamp, so the draft
          // stays untouched and its offer starts ticked.
          await repos.programs.update(
            p.copyWith(lessonMinute: 18 * 60, arrivalMinute: 18 * 60 + 30),
          );
          final later = timed('20300620', '193000', '223000');
          await _apply(repos, later);
          final after = await _only(repos);
          expect(
            (after.startMinute, after.endMinute),
            (19 * 60 + 30, 22 * 60 + 30),
          );
          expect(
            (after.lessonMinute, after.arrivalMinute),
            (18 * 60, 18 * 60 + 30),
          );
        },
      );

      test('on a worked-on program the time change starts unticked, and '
          'leaving it unticked keeps the caller\'s times', () async {
        final repos = openTestRepositories();
        await _importNew(repos, original);
        final p = await _only(repos);
        await repos.programs.update(
          p.copyWith(
            notes: 'mine',
            updatedAt: _t0.add(const Duration(hours: 1)),
          ),
        );
        final later = timed('20300620', '193000', '223000');
        final offer = (await _preview(repos, later)).changes.single;
        expect((offer.time, offer.untouched), (true, false));
        await _apply(repos, later, accepted: const {});
        final after = await _only(repos);
        expect((after.startMinute, after.endMinute), (19 * 60, 22 * 60));
      });
    },
  );

  test('a feed not read whole flags nothing as gone', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final unreadable = _cal([
      ['UID:x', 'DTSTART:20300601', 'RRULE:FREQ=HOURLY', 'SUMMARY:Odd'],
    ]);
    expect((await _preview(repos, unreadable)).flagChanges, isEmpty);
    final noStart = _cal([
      ['UID:y', 'DTSTART:garbage'],
    ]);
    expect((await _preview(repos, noStart)).flagChanges, isEmpty);
    // A feed cut at the event cap is checked at the plan level.
    final plan = planCalendarImport(
      parseICalFeed(
        _cal([
          for (var i = 0; i < 3; i++) ['UID:e$i', 'DTSTART:20300620'],
        ]),
        maxEvents: 2,
      ),
      today: _today,
      windowMonths: 6,
    );
    expect(plan.canJudgeMissing, isFalse);
  });

  test(
    'a program changed after the review was built is not overwritten',
    () async {
      final repos = openTestRepositories();
      await _importNew(repos, _original);
      final preview = await _preview(repos, _moved);
      final p = await _only(repos);
      await repos.programs.update(
        p.copyWith(notes: 'synced edit', updatedAt: _t1),
      );
      final written = await applyCalendarUpdates(
        repos,
        preview: preview,
        accepted: {p.id},
        now: _t2,
      );
      expect(written, isEmpty);
      final after = await _only(repos);
      expect(after.notes, 'synced edit');
      expect(after.eventDate, DateTime.utc(2030, 6, 20));
    },
  );

  test('Undo leaves a program changed again since the import', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final written = await _apply(repos, _moved);
    final p = await _only(repos);
    await repos.programs.update(p.copyWith(notes: 'later', updatedAt: _t2));
    await undoCalendarUpdates(
      repos,
      written,
      now: _t2.add(const Duration(hours: 1)),
    );
    final after = await _only(repos);
    expect(after.notes, 'later');
    expect(after.eventDate, DateTime.utc(2030, 6, 27));
  });

  test('ticking a venue change replaces the venue the caller sees, even a '
      'linked one', () async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v-old', name: 'Old Hall'));
    await _importNew(repos, _original);
    final p = await _only(repos);
    await repos.programs.update(p.copyWith(venueId: 'v-old', updatedAt: _t1));
    final newPlace = _cal([
      [
        'UID:a',
        'DTSTART;VALUE=DATE:20300620',
        'SUMMARY:Contra A',
        'LOCATION:Town Hall',
      ],
    ]);
    final preview = await _preview(repos, newPlace);
    final offer = preview.changes.single;
    expect(offer.venue, isTrue);
    expect(offer.shownVenue, 'Old Hall');
    await applyCalendarUpdates(
      repos,
      preview: preview,
      accepted: {offer.program.id},
      now: _t2,
    );
    final after = await _only(repos);
    expect(after.venue, 'Town Hall');
    expect(after.venueId, isNull);
  });

  test('a program that stays flagged is still listed in the review', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    await _apply(repos, _cancelled);
    final again = await _preview(repos, _cancelled);
    expect(again.flagChanges, isEmpty);
    expect(again.flagged.single.flag, calendarFlagCancelled);
  });

  test('a review with nothing to show rewrites nothing on Import', () async {
    final repos = openTestRepositories();
    // Imported before #2354: no fingerprint, values as in the calendar.
    await repos.programs.create(
      Program(
        id: 'old',
        title: 'Contra A',
        eventDate: DateTime.utc(2030, 6, 20),
        venue: 'Glen Echo Park',
        calendarEventKey: calendarEventKey('a', ''),
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );
    final preview = await _preview(repos, _original);
    expect(preview.hasPendingWrites, isFalse);
    await applyCalendarUpdates(repos, preview: preview, accepted: {}, now: _t1);
    expect((await _only(repos)).updatedAt, _t0);
  });

  test('a program imported before the fingerprint existed is treated as '
      'worked on', () async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'old',
        title: 'Contra A',
        eventDate: DateTime.utc(2030, 6, 20),
        venue: 'Glen Echo Park',
        calendarEventKey: calendarEventKey('a', ''),
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );
    final preview = await _preview(repos, _moved);
    final offer = preview.changes.single;
    expect(offer.untouched, isFalse);
    expect(offer.date, isTrue);
  });

  test('a program edited on another device counts as worked on', () async {
    final repos = openTestRepositories();
    await _importNew(repos, _original);
    final p = await _only(repos);
    await repos.programs.writeFromSync(p.copyWith(notes: 'n', updatedAt: _t1));
    final preview = await _preview(repos, _moved);
    expect(preview.changes.single.untouched, isFalse);
  });

  test('all three fields are stripped from share files', () {
    final p = Program(
      id: 'p',
      title: 'T',
      calendarEventKey: calendarEventKey('a', ''),
      calendarEventFingerprint: 'v1:0:0:0',
      calendarWrittenAt: _t0,
      calendarFlag: calendarFlagMissing,
      createdAt: _t0,
      updatedAt: _t0,
    );
    final shared = sanitizeProgramForShare(p);
    expect(shared.calendarEventFingerprint, isNull);
    expect(shared.calendarWrittenAt, isNull);
    expect(shared.calendarFlag, isNull);
  });

  test('an unknown calendar_flag value decodes without failing the record', () {
    final decoded = decodeArchive(
      jsonEncode({
        'schemaVersion': archiveSchemaVersion,
        'exportedAt': '2030-01-01T00:00:00.000Z',
        'programs': [
          {
            'id': 'p',
            'title': 'T',
            'notes': '',
            'status': 'draft',
            'hideAlternates': false,
            'slots': <Object?>[],
            'createdAt': '2030-01-01T00:00:00.000Z',
            'updatedAt': '2030-01-01T00:00:00.000Z',
            'calendarFlag': 'postponed',
          },
        ],
      }),
    );
    expect(decoded.hasErrors, isFalse);
    expect(decoded.archive.programs.single.calendarFlag, 'postponed');
  });
}
