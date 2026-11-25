import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/calendar_import.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_app/src/diagnostics/sensitive_terms.dart';
import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
final _now = DateTime.utc(2030, 6, 15, 12);

/// A feed whose LOCATION holds a street address and whose ORGANIZER,
/// ATTENDEE, DESCRIPTION and URL hold third-party contact data.
final _leakyFeed = _cal([
  [
    'UID:gig-1@pat.organiser.example',
    'DTSTART;VALUE=DATE:20300620',
    'SUMMARY:Glen Echo Contra',
    r'LOCATION:Glen Echo Park\, 7300 MacArthur Blvd\, Glen Echo\, MD 20812',
    'ORGANIZER;CN=Pat Organiser:mailto:pat@organiser.example',
    'ATTENDEE;CN=Sam Dancer:mailto:sam@dancer.example',
    'DESCRIPTION:Call Pat on 555-0142',
    'URL:https://private.example/booking/abc',
  ],
]);

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

Future<List<String>> _importAll(
  CompendiumRepositories repos,
  CalendarImportPreview preview,
) => commitCalendarImport(
  repos,
  chosen: [
    for (final e in preview.entries)
      if (e.tickedByDefault) e,
  ],
  untitledTitle: 'Untitled event',
  now: _now,
);

/// Every text value of every column of every row in `programs` and
/// `program_slots`, read raw from SQLite.
Future<List<String>> _storedText(CompendiumRepositories repos) async {
  final out = <String>[];
  for (final table in ['programs', 'program_slots', 'program_provenance']) {
    final rows = await repos.db.customSelect('SELECT * FROM $table').get();
    for (final row in rows) {
      for (final value in row.data.values) {
        if (value is String) out.add(value);
      }
    }
  }
  return out;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preview and import', () {
    test('new events are offered ticked; Import creates drafts; Undo (hard '
        'delete of the ids) removes them', () async {
      final repos = openTestRepositories();
      final preview = await _preview(
        repos,
        _cal([
          ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:Contra A'],
          ['UID:b', 'DTSTART;VALUE=DATE:20300627', 'SUMMARY:Contra B'],
        ]),
      );
      expect(preview.entries.map((e) => e.state), [
        CalendarEntryState.fresh,
        CalendarEntryState.fresh,
      ]);
      expect(await repos.programs.listAll(), isEmpty, reason: 'preview only');
      final ids = await _importAll(repos, preview);
      final programs = await repos.programs.listAll();
      expect(programs.map((p) => p.title), ['Contra A', 'Contra B']);
      expect(programs.every((p) => p.status == ProgramStatus.draft), isTrue);
      expect(programs.first.eventDate, DateTime.utc(2030, 6, 20));

      await repos.programs.hardDelete(ids);
      expect(await repos.programs.listAll(includeDeleted: true), isEmpty);
    });

    test('a second import of the same feed offers nothing new', () async {
      final repos = openTestRepositories();
      final feed = _cal([
        ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:A'],
      ]);
      await _importAll(repos, await _preview(repos, feed));
      final again = await _preview(repos, feed);
      expect(again.entries.single.state, CalendarEntryState.alreadyImported);
      expect(again.entries.single.offered, isFalse);
      expect(again.offeredCount, 0);
    });

    test(
      'a week later, only the newly in-range occurrences are offered',
      () async {
        final repos = openTestRepositories();
        final feed = _cal([
          [
            'UID:w',
            'DTSTART;VALUE=DATE:20300601',
            'RRULE:FREQ=WEEKLY;BYDAY=SA',
            'SUMMARY:Weekly',
          ],
        ]);
        await _importAll(repos, await _preview(repos, feed));
        final later = await _preview(repos, feed, today: DateTime(2030, 6, 22));
        final fresh = [
          for (final e in later.entries)
            if (e.state == CalendarEntryState.fresh) e.candidate.date,
        ];
        expect(fresh, [DateTime.utc(2030, 7, 20)]);
      },
    );

    test(
      'a program in Recently deleted is not re-offered by default',
      () async {
        final repos = openTestRepositories();
        final feed = _cal([
          ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:A'],
        ]);
        final ids = await _importAll(repos, await _preview(repos, feed));
        await repos.programs.softDelete(ids.single, at: _now);
        final again = await _preview(repos, feed);
        final entry = again.entries.single;
        expect(entry.state, CalendarEntryState.deleted);
        expect(entry.offered, isTrue);
        expect(entry.tickedByDefault, isFalse);
      },
    );

    test('an event this app exported matches its live program: From this '
        'app, not offered', () async {
      final repos = openTestRepositories();
      await repos.programs.create(
        Program(
          id: 'p-1',
          title: 'Mine',
          eventDate: DateTime.utc(2030, 6, 20),
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      final feed = _cal([
        ['UID:p-1@callers-compendium', 'DTSTART;VALUE=DATE:20300620'],
        ['UID:other@callers-compendium', 'DTSTART;VALUE=DATE:20300620'],
      ]);
      final preview = await _preview(repos, feed);
      expect(preview.entries.map((e) => e.state), [
        CalendarEntryState.fromThisApp,
        CalendarEntryState.fresh,
      ], reason: 'with no program of that id it is an ordinary event');
    });

    test('a synced program carrying the key prevents a duplicate', () async {
      final repos = openTestRepositories();
      await repos.programs.writeFromSync(
        Program(
          id: 'from-other-device',
          title: 'A',
          eventDate: DateTime.utc(2030, 6, 20),
          calendarEventKey: calendarEventKey('a', ''),
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      final preview = await _preview(
        repos,
        _cal([
          ['UID:a', 'DTSTART;VALUE=DATE:20300620'],
        ]),
      );
      expect(preview.entries.single.state, CalendarEntryState.alreadyImported);
    });

    test('drafts take the Default template, the default caller and band, and '
        'link a saved venue by name', () async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(id: 'd1', title: 'Chorus Jig', createdAt: _now, updatedAt: _now),
      );
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(
          id: 'family',
          name: 'Family dance',
          entries: [
            ProgramTemplateEntry(danceId: 'd1'),
            ProgramTemplateEntry(text: 'Waltz'),
            ProgramTemplateEntry(danceId: 'gone'),
          ],
        ),
      );
      await saveProgramTemplateOrder(repos.settings, const ['family']);
      await saveProgramTemplateDefault(repos.settings, 'family');
      await repos.settings.set(kDefaultProgramCallerKey, 'Robin');
      await repos.settings.set(kDefaultProgramBandKey, 'The Ripplers');
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Glen  Echo PARK', address1: '7300 MacArthur'),
      );
      await _importAll(repos, await _preview(repos, _leakyFeed));
      final p = (await repos.programs.listAll()).single;
      expect(p.slots.map((s) => (s.danceId, s.text)), [
        ('d1', null),
        (null, 'Waltz'),
      ]);
      expect(p.caller, 'Robin');
      expect(p.band, 'The Ripplers');
      expect(p.venue, 'Glen Echo Park');
      expect(p.venueId, 'v1');
    });

    test('a slot rule in the Default template becomes a placeholder in each '
        'draft, its label as text and its saved search kept (#2338)', () async {
      final repos = openTestRepositories();
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(
          id: 'family',
          name: 'Family dance',
          entries: [
            const ProgramTemplateEntry(text: 'Waltz'),
            ProgramTemplateEntry.rule(
              savedSearchId: 'search-1',
              label: 'Easy family opener',
            ),
          ],
        ),
      );
      await saveProgramTemplateOrder(repos.settings, const ['family']);
      await saveProgramTemplateDefault(repos.settings, 'family');
      await _importAll(
        repos,
        await _preview(
          repos,
          _cal([
            ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:Family dance'],
          ]),
        ),
      );
      final p = (await repos.programs.listAll()).single;
      expect(p.slots.map((s) => (s.danceId, s.text, s.placeholderSearchId)), [
        (null, 'Waltz', null),
        (null, 'Easy family opener', 'search-1'),
      ]);
      expect(p.slots[1].isPlaceholder, isTrue);
    });

    test('a timed event gives its draft a start and end; an all-day one gives '
        'none (#2423)', () async {
      final repos = openTestRepositories();
      await _importAll(
        repos,
        await _preview(
          repos,
          _cal([
            [
              'UID:timed',
              'DTSTART:20300620T193000',
              'DTEND:20300620T223000',
              'SUMMARY:Timed',
            ],
            ['UID:allday', 'DTSTART;VALUE=DATE:20300627', 'SUMMARY:All day'],
          ]),
        ),
      );
      final byTitle = {
        for (final p in await repos.programs.listAll()) p.title: p,
      };
      expect(byTitle['Timed']!.startMinute, 1170);
      expect(byTitle['Timed']!.endMinute, 1350);
      expect(byTitle['Timed']!.eventDate, DateTime.utc(2030, 6, 20));
      expect(byTitle['All day']!.hasTimes, isFalse);
      // Lesson and Arrive by are never read from an event.
      expect(byTitle['Timed']!.lessonMinute, isNull);
      expect(byTitle['Timed']!.arrivalMinute, isNull);
    });

    test('an empty title gets the placeholder', () async {
      final repos = openTestRepositories();
      await _importAll(
        repos,
        await _preview(
          repos,
          _cal([
            ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:\u200B'],
          ]),
        ),
      );
      expect((await repos.programs.listAll()).single.title, 'Untitled event');
    });
  });

  test('guard: no street address, organiser, attendee, description, URL or '
      'raw UID reaches any stored column', () async {
    final repos = openTestRepositories();
    await _importAll(repos, await _preview(repos, _leakyFeed));
    final stored = (await _storedText(repos)).join('\n');
    for (final leaked in [
      '7300 MacArthur',
      'MD 20812',
      'pat@organiser.example',
      'Pat Organiser',
      'sam@dancer.example',
      'Sam Dancer',
      '555-0142',
      'private.example',
      'gig-1@pat.organiser.example',
      'organiser.example',
    ]) {
      expect(stored.contains(leaked), isFalse, reason: '"$leaked" stored');
    }
    expect(stored, contains('Glen Echo Park'));
  });

  group('privacy boundaries', () {
    test('sanitizeProgramForShare strips the key, and a share bundle and '
        'its JSON do not carry it', () async {
      final program = Program(
        id: 'p1',
        title: 'A',
        calendarEventKey: calendarEventKey('a', ''),
        createdAt: _now,
        updatedAt: _now,
      );
      expect(sanitizeProgramForShare(program).calendarEventKey, isNull);
      final json = buildProgramShareBundle(
        program,
        danceFor: (_) => null,
        blankedDanceSlotText: '',
        choreographerFor: (_) => null,
        venueFor: (_) => null,
        tagFor: (_) => null,
        publishedSourceFor: (_) => null,
        customFieldFor: (_) => null,
        difficultyLevelFor: (_) => null,
      );
      expect(json, isNot(contains('calendarEventKey')));
      expect(json, isNot(contains(calendarEventKey('a', ''))));
    });

    test(
      'the feed address is not in a backup, and is unset after a restore',
      () async {
        const secret = 'https://calendar.example/private-s3cr3tt0ken/basic.ics';
        final source = openTestRepositories();
        await source.settings.set(kCalendarFeedUrlKey, secret);
        await source.settings.set(kCalendarImportWindowMonthsKey, 12);
        await source.programs.create(
          Program(
            id: 'p1',
            title: 'A',
            calendarEventKey: calendarEventKey('a', ''),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        final json = await BackupService(source).exportToJson();
        expect(json, isNot(contains('s3cr3tt0ken')));
        final payload =
            jsonDecode((jsonDecode(json) as Map)['payload'] as String) as Map;
        expect(
          payload['backupVersion'],
          backupSchemaVersionCalendarEventKeys,
          reason: 'a backup with calendar keys is stamped v3',
        );

        final target = openTestRepositories();
        final outcome = await BackupService(target).restoreFromJson(json);
        expect(outcome.applied, isTrue);
        final restored = await CalendarImportSettings.read(target.settings);
        expect(restored.hasFeed, isFalse, reason: 'asked for again');
        expect(restored.windowMonths, 12, reason: 'preferences do travel');
        expect(
          (await target.programs.getById('p1'))!.calendarEventKey,
          calendarEventKey('a', ''),
        );
      },
    );

    test('a backup with no calendar key keeps its envelope version', () {
      final doc = BackupDocument(
        createdAt: _now,
        core: CompendiumArchive(
          exportedAt: _now,
          programs: [
            Program(id: 'p', title: 'T', createdAt: _now, updatedAt: _now),
          ],
        ),
      );
      expect(requiredBackupVersion(doc), backupSchemaVersionBase);
    });

    test('the feed address is a diagnostics redaction term', () async {
      const secret = 'webcal://calendar.example/private-s3cr3tt0ken/basic.ics';
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarFeedUrlKey, secret);
      final terms = await collectSensitiveTerms(repos);
      expect(terms, contains(secret));
      expect(
        terms,
        contains('calendar.example/private-s3cr3tt0ken/basic.ics'),
        reason: 'the https:// form a webcal address is fetched as',
      );
    });
  });

  group('fetchCalendarFeed', () {
    late List<Uri> requested;
    http.Client client(http.Response Function(http.Request) respond) =>
        MockClient((request) async {
          requested.add(request.url);
          return respond(request);
        });
    setUp(() => requested = []);

    final okBody = _cal([
      ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:Café ♪'],
    ]);

    test(
      'webcal:// is fetched as https://, and the body is read as UTF-8',
      () async {
        final body = await fetchCalendarFeed(
          'webcal://calendar.example/basic.ics',
          client: client(
            (_) => http.Response.bytes(
              utf8.encode(okBody),
              200,
              headers: {
                // No charset: package:http would read this as Latin-1.
                'content-type': 'text/calendar',
              },
            ),
          ),
        );
        expect(
          requested.single.toString(),
          'https://calendar.example/basic.ics',
        );
        expect(body, contains('Café ♪'));
      },
    );

    for (final (label, url, reason) in [
      (
        'http://',
        'http://calendar.example/a.ics',
        UrlFetchFailureReason.insecureScheme,
      ),
      (
        'a private host',
        'https://192.168.1.10/a.ics',
        UrlFetchFailureReason.blockedHost,
      ),
      (
        'localhost',
        'https://localhost/a.ics',
        UrlFetchFailureReason.blockedHost,
      ),
    ]) {
      test('$label is refused without a request', () async {
        await expectLater(
          fetchCalendarFeed(url, client: client((_) => http.Response('', 200))),
          throwsA(
            isA<UrlFetchException>().having((e) => e.reason, 'reason', reason),
          ),
        );
        expect(requested, isEmpty);
      });
    }

    test('a redirect to http:// is refused', () async {
      await expectLater(
        fetchCalendarFeed(
          'https://calendar.example/a.ics',
          client: client(
            (_) => http.Response(
              '',
              302,
              headers: {'location': 'http://calendar.example/a.ics'},
            ),
          ),
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.insecureScheme,
          ),
        ),
      );
    });

    test('a fold in the middle of a multi-byte character is undone before '
        'decoding', () async {
      final bytes = utf8.encode(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\n'
        'DTSTART:20300620\r\nSUMMARY:Ca',
      );
      // 'é' is C3 A9; fold between its two bytes.
      final folded = [
        ...bytes,
        0xC3,
        0x0D,
        0x0A,
        0x20,
        0xA9,
        ...utf8.encode('\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'),
      ];
      final body = await fetchCalendarFeed(
        'https://calendar.example/a.ics',
        client: client((_) => http.Response.bytes(folded, 200)),
      );
      expect(body, contains('SUMMARY:Caé'));
      expect(body.contains('\uFFFD'), isFalse);
    });

    test('an over-cap body is refused', () async {
      await expectLater(
        fetchCalendarFeed(
          'https://calendar.example/a.ics',
          client: client(
            (_) => http.Response.bytes(
              List.filled(importMaxResponseBytes + 1, 0x41),
              200,
            ),
          ),
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.responseTooLarge,
          ),
        ),
      );
    });

    test('a web page is not a calendar, and the error does not echo the '
        'address', () async {
      const url = 'https://calendar.example/private-s3cr3tt0ken/basic';
      Object? caught;
      try {
        await fetchCalendarFeed(
          url,
          client: client((_) => http.Response('<html>Sign in</html>', 200)),
        );
      } catch (e) {
        caught = e;
      }
      expect(
        caught,
        isA<UrlFetchException>().having(
          (e) => e.reason,
          'reason',
          UrlFetchFailureReason.notACalendar,
        ),
      );
      expect(caught.toString(), isNot(contains('s3cr3tt0ken')));
    });
  });
}
