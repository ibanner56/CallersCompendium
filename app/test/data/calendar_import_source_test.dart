// Pre-release audit finding E1-01: a program remembers which calendar it came
// from (`Program.calendarFeedDigest`), and an import compares it only with
// that calendar. Before, a program was judged against whatever feed was
// fetched, so importing from a second address, or a second device with its
// own address, labelled every upcoming program from the first calendar "No
// longer in your calendar".
//
// Mutations these catch: compare every program with the fetched feed again
// (drop the digest check); treat a program with no digest as from this
// calendar; reuse one salt for every program; digest the address as typed
// rather than as fetched (`webcal://` read as `https://`).
import 'dart:math' as math;

import 'package:compendium_app/src/data/calendar_import.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/calendar_startup.dart';
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

/// The caller's own gigs calendar, and a dance series' public one.
const _urlA = 'https://calendar.example/private-s3cr3tt0ken/gigs.ics';
const _urlB = 'https://series.example/public.ics';

final _feedA = _cal([
  ['UID:a1', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:My gig at Glen Echo'],
]);
final _feedAMoved = _cal([
  ['UID:a1', 'DTSTART;VALUE=DATE:20300627', 'SUMMARY:My gig at Glen Echo'],
]);
final _feedB = _cal([
  ['UID:b1', 'DTSTART;VALUE=DATE:20300622', 'SUMMARY:Series dance'],
]);

/// A valid calendar with no events: sharing switched off upstream, say.
final _empty = _cal([]);

Future<CalendarImportPreview> _preview(
  CompendiumRepositories repos,
  String body,
  String url,
) => buildCalendarImportPreview(
  repos,
  body: body,
  feedUrl: url,
  settings: const CalendarImportSettings(),
  today: _today,
  toLocal: (u) => u,
);

Future<List<String>> _importNew(
  CompendiumRepositories repos,
  String body,
  String url,
) async {
  final preview = await _preview(repos, body, url);
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

/// Presses Import with nothing ticked: what a review writes on its own.
Future<void> _pressImport(
  CompendiumRepositories repos,
  String body,
  String url,
) async {
  final preview = await _preview(repos, body, url);
  await commitCalendarImport(
    repos,
    chosen: [
      for (final e in preview.entries)
        if (e.tickedByDefault) e,
    ],
    untitledTitle: 'Untitled event',
    now: _t1,
  );
  await applyCalendarUpdates(repos, preview: preview, accepted: {}, now: _t1);
}

List<(String, String?)> _flags(CalendarImportPreview preview) => [
  for (final f in preview.flagChanges) (f.program.title, f.flag),
];

Future<Program> _byTitle(CompendiumRepositories repos, String title) async =>
    (await repos.programs.listAll()).singleWhere((p) => p.title == title);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a program from another calendar is not compared with this one', () {
    test('importing from a second address flags nothing from the first, '
        'and going back flags nothing from the second', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);

      final fromB = await _preview(repos, _feedB, _urlB);
      expect(fromB.entries.single.state, CalendarEntryState.fresh);
      expect(_flags(fromB), isEmpty);
      expect(fromB.flagged, isEmpty);
      await _pressImport(repos, _feedB, _urlB);
      expect(
        (await _byTitle(repos, 'My gig at Glen Echo')).calendarFlag,
        isNull,
      );

      final backToA = await _preview(repos, _feedA, _urlA);
      expect(_flags(backToA), isEmpty);
      await _pressImport(repos, _feedA, _urlA);
      expect((await _byTitle(repos, 'Series dance')).calendarFlag, isNull);
    });

    test('an empty calendar at another address flags nothing', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);
      expect(_flags(await _preview(repos, _empty, _urlB)), isEmpty);
    });

    test('a cancellation in another calendar does not flag it', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);
      // The same event, cancelled, in a calendar the caller also reads.
      final cancelledElsewhere = _cal([
        [
          'UID:a1',
          'DTSTART;VALUE=DATE:20300620',
          'SUMMARY:My gig at Glen Echo',
          'STATUS:CANCELLED',
        ],
      ]);
      expect(_flags(await _preview(repos, cancelledElsewhere, _urlB)), isEmpty);
    });

    test('a change in another calendar is not offered', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);
      final preview = await _preview(repos, _feedAMoved, _urlB);
      expect(preview.changes, isEmpty);
      // Still recognised, so it is not offered as new.
      expect(preview.entries.single.state, CalendarEntryState.alreadyImported);
    });

    test(
      'a flag its own calendar set is not listed in another\'s review',
      () async {
        final repos = openTestRepositories();
        await _importNew(repos, _feedA, _urlA);
        await _pressImport(repos, _empty, _urlA);
        expect(
          (await _byTitle(repos, 'My gig at Glen Echo')).calendarFlag,
          calendarFlagMissing,
        );
        final fromB = await _preview(repos, _feedB, _urlB);
        expect(fromB.flagged, isEmpty);
        expect(fromB.flagChanges, isEmpty);
      },
    );
  });

  group('its own calendar still judges it', () {
    // Positive controls: the check above must not switch the judgement off.
    test('gone from its own calendar', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);
      expect(_flags(await _preview(repos, _empty, _urlA)), [
        ('My gig at Glen Echo', calendarFlagMissing),
      ]);
    });

    test(
      'the webcal:// spelling of the address is the same calendar',
      () async {
        final repos = openTestRepositories();
        await _importNew(
          repos,
          _feedA,
          'webcal://calendar.example/private-s3cr3tt0ken/gigs.ics',
        );
        expect(_flags(await _preview(repos, _empty, _urlA)), [
          ('My gig at Glen Echo', calendarFlagMissing),
        ]);
        expect(
          (await _preview(repos, _feedAMoved, '  $_urlA ')).changes,
          hasLength(1),
        );
      },
    );
  });

  group('a program with no recorded calendar is never judged', () {
    Future<CompendiumRepositories> withUnrecorded() async {
      final repos = openTestRepositories();
      await repos.programs.create(
        Program(
          id: 'p',
          title: 'Unrecorded',
          eventDate: DateTime.utc(2030, 6, 20),
          calendarEventKey: calendarEventKey('a1', ''),
          createdAt: _t0,
          updatedAt: _t0,
        ),
      );
      return repos;
    }

    test('not missing', () async {
      final repos = await withUnrecorded();
      expect(_flags(await _preview(repos, _empty, _urlA)), isEmpty);
    });

    test('not cancelled', () async {
      final repos = await withUnrecorded();
      final cancelled = _cal([
        ['UID:a1', 'DTSTART;VALUE=DATE:20300620', 'STATUS:CANCELLED'],
      ]);
      expect(_flags(await _preview(repos, cancelled, _urlA)), isEmpty);
    });

    test('a digest an older build dropped turns the judgement off, and '
        'marks nothing', () async {
      final repos = openTestRepositories();
      await _importNew(repos, _feedA, _urlA);
      final program = (await repos.programs.listAll()).single;
      expect(program.calendarFeedDigest, isNotNull);

      // An edit from a build that does not know the key and does not keep it
      // aside: its body leaves the key out, and since #2562 a program key a
      // body leaves out reads as empty on receipt.
      final address = (kind: SyncRecordKind.program, recordId: program.id);
      final held = (await CompendiumSyncStorage(
        repos,
      ).snapshot()).local[address]!;
      final body = {...held.blob.body}..remove('calendarFeedDigest');
      final edited = DateTime.utc(2030, 6, 15, 13);
      body['notes'] = 'edited on an older build';
      body['updatedAt'] = edited.toIso8601String();
      // The test's own clock, so the 2030 stamps are not quarantined.
      final result = await SyncApplyEngine(now: () => _t1).apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.program,
              id: program.id,
              updatedAt: edited,
              deletedAt: null,
              existenceAt: held.blob.existenceAt,
              body: body,
            ),
          ),
        ],
        storage: CompendiumSyncStorage(repos),
      );
      expect([for (final r in result.reports) r.code], isEmpty);
      expect(result.applied, [address]);
      final received = (await repos.programs.listAll()).single;
      expect(received.notes, 'edited on an older build');
      expect(received.calendarFeedDigest, isNull);
      expect(received.calendarEventKey, program.calendarEventKey);
      expect(received.calendarFlag, isNull);

      expect(_flags(await _preview(repos, _empty, _urlA)), isEmpty);
    });
  });

  group(
    'the startup run counts only changes from a program\'s own calendar',
    () {
      Future<CalendarStartupOutcome> run(
        CompendiumRepositories repos,
        String url,
        String body,
      ) async {
        await repos.settings.set(kCalendarImportOnStartupKey, true);
        await repos.settings.set(kCalendarFeedUrlKey, url);
        return runCalendarStartup(
          repos,
          fetcher: (_) async => body,
          now: _t1,
          today: _today,
          untitledTitle: 'Untitled event',
          toLocal: (u) => u,
        );
      }

      test('nothing to report from another calendar', () async {
        final repos = openTestRepositories();
        await _importNew(repos, _feedA, _urlA);
        await _importNew(repos, _feedB, _urlB);
        expect(await run(repos, _urlB, _feedB), isA<CalendarStartupQuiet>());
      });

      test('a change in its own calendar is counted', () async {
        final repos = openTestRepositories();
        await _importNew(repos, _feedA, _urlA);
        await _importNew(repos, _feedB, _urlB);
        final outcome = await run(repos, _urlA, _feedAMoved);
        expect(outcome, isA<CalendarStartupFound>());
        expect((outcome as CalendarStartupFound).changes, 1);
        expect(outcome.newEvents, 0);
      });
    },
  );

  group('the digest', () {
    test('differs for every program, even from one address', () {
      final source = CalendarFeedSource(_urlA);
      final first = source.newDigest();
      final second = source.newDigest();
      expect(first, isNot(second));
      expect(source.matches(first), isTrue);
      expect(source.matches(second), isTrue);
    });

    test('holds no part of the address', () {
      final digest = CalendarFeedSource(_urlA).newDigest();
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
      for (final part in ['s3cr3tt0ken', 'calendar', 'example', 'gigs']) {
        expect(digest, isNot(contains(part)));
      }
    });

    test('does not match another address, or anything malformed', () {
      final digest = CalendarFeedSource(_urlA).newDigest();
      expect(CalendarFeedSource(_urlB).matches(digest), isFalse);
      final source = CalendarFeedSource(_urlA);
      expect(source.matches(null), isFalse);
      expect(source.matches(''), isFalse);
      expect(source.matches(digest.toUpperCase()), isFalse);
      expect(source.matches(digest.substring(1)), isFalse);
      // The same salt with another digest half.
      final tampered =
          digest.substring(0, 63) + (digest.endsWith('0') ? '1' : '0');
      expect(source.matches(tampered), isFalse);
    });

    test('takes its salt from the random source it is given', () {
      final a = CalendarFeedSource(_urlA, random: math.Random(1)).newDigest();
      final b = CalendarFeedSource(_urlA, random: math.Random(1)).newDigest();
      expect(a, b);
    });
  });
}
