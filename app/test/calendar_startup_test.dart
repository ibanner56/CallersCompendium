import 'package:clock/clock.dart';
import 'package:compendium_app/src/data/calendar_import.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/calendar_startup.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/calendar_import_screen.dart';
import 'package:compendium_app/src/screens/calendar_startup_message.dart';
import 'package:compendium_app/src/screens/settings/calendar_settings_tiles.dart';
import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

String _cal(List<List<String>> events) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  for (final e in events) ...['BEGIN:VEVENT', ...e, 'END:VEVENT'],
  'END:VCALENDAR',
  '',
].join('\r\n');

final _feed = _cal([
  ['UID:a', 'DTSTART;VALUE=DATE:20300620', 'SUMMARY:Contra A'],
  ['UID:b', 'DTSTART;VALUE=DATE:20300627', 'SUMMARY:Contra B'],
]);
const _url = 'https://calendar.example/basic.ics';

// Injected, not the real date.
final _today = DateTime(2030, 6, 15);
final _now = DateTime.utc(2030, 6, 15, 9);

Future<String> _mustNotFetch(String url) =>
    throw StateError('no network request may be made');

Future<CalendarStartupOutcome> _run(
  CompendiumRepositories repos, {
  Future<String> Function(String url)? fetcher,
  DateTime? now,
}) => runCalendarStartup(
  repos,
  fetcher: fetcher ?? (_) async => _feed,
  now: now ?? _now,
  today: _today,
  untitledTitle: 'Untitled event',
  toLocal: (u) => u,
);

Future<void> _turnOn(
  CompendiumRepositories repos, {
  CalendarStartupMode mode = CalendarStartupMode.report,
  bool address = true,
}) async {
  await repos.settings.set(kCalendarImportOnStartupKey, true);
  await repos.settings.set(kCalendarStartupModeKey, mode.name);
  if (address) await repos.settings.set(kCalendarFeedUrlKey, _url);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('runCalendarStartup', () {
    test('off by default: no request, even with an address set', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarFeedUrlKey, _url);
      expect(
        await _run(repos, fetcher: _mustNotFetch),
        isA<CalendarStartupQuiet>(),
      );
      expect(await repos.settings.get(kCalendarLastResultKey), isNull);
    });

    test('on, with no address: no request', () async {
      final repos = openTestRepositories();
      await _turnOn(repos, address: false);
      expect(
        await _run(repos, fetcher: _mustNotFetch),
        isA<CalendarStartupQuiet>(),
      );
    });

    test('on, with an address: exactly one fetch', () async {
      final repos = openTestRepositories();
      await _turnOn(repos);
      final fetched = <String>[];
      await _run(
        repos,
        fetcher: (url) async {
          fetched.add(url);
          return _feed;
        },
      );
      expect(fetched, [_url]);
    });

    test('Report new events is the default, and creates no program', () async {
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarImportOnStartupKey, true);
      await repos.settings.set(kCalendarFeedUrlKey, _url);
      final outcome = await _run(repos);
      expect(outcome, isA<CalendarStartupFound>());
      expect((outcome as CalendarStartupFound).newEvents, 2);
      expect(outcome.addedIds, isEmpty);
      expect(await repos.programs.listAll(), isEmpty);
    });

    test('Add them as drafts creates drafts for new events only', () async {
      final repos = openTestRepositories();
      await _turnOn(repos, mode: CalendarStartupMode.addDrafts);
      final first = await _run(repos) as CalendarStartupFound;
      expect(first.addedIds, hasLength(2));
      expect(await repos.programs.listAll(), hasLength(2));
      // A second launch adds nothing.
      expect(await _run(repos), isA<CalendarStartupQuiet>());
      expect(await repos.programs.listAll(), hasLength(2));
    });

    for (final mode in CalendarStartupMode.values) {
      test('guard: an imported program whose event changed upstream is '
          'unchanged after a startup run (${mode.name})', () async {
        final repos = openTestRepositories();
        final preview = await buildCalendarImportPreview(
          repos,
          body: _feed,
          settings: const CalendarImportSettings(),
          today: _today,
          toLocal: (u) => u,
        );
        await commitCalendarImport(
          repos,
          chosen: preview.entries,
          untitledTitle: 'Untitled event',
          now: _now,
        );
        final before = await repos.programs.listAll();
        await _turnOn(repos, mode: mode);
        final moved = _cal([
          ['UID:a', 'DTSTART;VALUE=DATE:20300704', 'SUMMARY:Contra A, moved'],
        ]);
        final outcome = await _run(
          repos,
          fetcher: (_) async => moved,
          now: _now.add(const Duration(hours: 1)),
        );
        // A's change offer, and B (gone from the feed) flagged missing.
        expect((outcome as CalendarStartupFound).changes, 2);
        expect(await repos.programs.listAll(), before);
      });
    }

    test('repeated failures: counted, cleared by a success and by an address '
        'edit', () async {
      final repos = openTestRepositories();
      await _turnOn(repos);
      Future<String> fail(String _) async =>
          throw const UrlFetchException(UrlFetchFailureReason.unreachable);
      for (var i = 1; i <= 3; i++) {
        expect(await _run(repos, fetcher: fail), isA<CalendarStartupFailed>());
        expect(await repos.settings.get(kCalendarStartupFailuresKey), i);
      }
      final last = CalendarStartupResult.fromStored(
        await repos.settings.get(kCalendarLastResultKey),
      );
      expect(last!.ok, isFalse);
      await _run(repos);
      expect(await repos.settings.get(kCalendarStartupFailuresKey), 0);

      for (var i = 0; i < 3; i++) {
        await _run(repos, fetcher: fail);
      }
      await resetCalendarStartupFailures(repos.settings);
      expect(await repos.settings.get(kCalendarStartupFailuresKey), 0);
    });
  });

  group('what the caller sees', () {
    Future<void> pump(
      WidgetTester tester,
      CompendiumRepositories repos,
      Widget home,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<DateFormatSetting>(
        DateFormatSetting.system,
      );
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => DateFormatScope(
            notifier: notifier,
            child: RepositoriesScope(repositories: repos, child: child!),
          ),
          home: home,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Report: the message offers Review, which opens the preview '
        'without fetching again; Import there creates the drafts', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _turnOn(repos);
      final outcome = await tester.runAsync(() => _run(repos));
      await pump(
        tester,
        repos,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalendarStartupMessage(
                messenger: ScaffoldMessenger.of(context),
                l10n: AppLocalizations.of(context),
                outcome: outcome! as CalendarStartupFound,
                accessibleNavigation: false,
                repositories: repos,
                openReview: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CalendarImportScreen(
                      prefetchedBody: (outcome as CalendarStartupFound).body,
                      prefetchedUrl: outcome.url,
                      fetcher: _mustNotFetch,
                      toLocal: (u) => u,
                    ),
                  ),
                ),
                openProgram: (_) {},
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(find.text('2 new events in your calendar.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // The preview's "today" comes from the clock, injected as the run's.
      await withClock(Clock.fixed(DateTime(2030, 6, 15, 9)), () async {
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
      });
      expect(find.text('Contra A'), findsOneWidget);
      expect(await repos.programs.listAll(), isEmpty);
      await tester.tap(find.byKey(const ValueKey('calendar-import-commit')));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(), hasLength(2));
    });

    testWidgets('Add drafts: Undo on the message removes them', (tester) async {
      final repos = openTestRepositories();
      await _turnOn(repos, mode: CalendarStartupMode.addDrafts);
      final outcome = await tester.runAsync(() => _run(repos));
      await pump(
        tester,
        repos,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalendarStartupMessage(
                messenger: ScaffoldMessenger.of(context),
                l10n: AppLocalizations.of(context),
                outcome: outcome! as CalendarStartupFound,
                accessibleNavigation: false,
                repositories: repos,
                openReview: () {},
                openProgram: (_) {},
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 draft programs added from your calendar.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('calendar-startup-show')), findsOne);
      // Drawn like the snack bar's own action, so it reads on its
      // inverse surface.
      final show = tester.element(find.text('Show'));
      expect(
        DefaultTextStyle.of(show).style.color,
        Theme.of(show).colorScheme.inversePrimary,
      );
      // The caller starts filling in one draft before pressing Undo.
      final ids = (outcome! as CalendarStartupFound).addedIds;
      await tester.runAsync(() async {
        final p = (await repos.programs.getById(ids.first))!;
        await repos.programs.update(
          p.copyWith(
            notes: 'mine',
            updatedAt: _now.add(const Duration(hours: 1)),
          ),
        );
      });
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final left = await tester.runAsync(
        () => repos.programs.listAll(includeDeleted: true),
      );
      expect(left!.map((p) => p.id), [
        ids.first,
      ], reason: 'Undo keeps a draft the caller has worked on');
    });

    testWidgets('launches 1 and 2 show nothing anywhere; after launch 3 only '
        'Settings shows a quiet notice', (tester) async {
      final repos = openTestRepositories();
      await _turnOn(repos);
      Future<String> fail(String _) async =>
          throw const UrlFetchException(UrlFetchFailureReason.unreachable);
      Future<void> settingsAfter(int launches) async {
        await tester.runAsync(() async {
          for (var i = 0; i < launches; i++) {
            await _run(repos, fetcher: fail);
          }
        });
        await pump(
          tester,
          repos,
          Scaffold(
            body: SingleChildScrollView(
              // A new key each time: Settings reads its state when opened.
              child: CalendarSettingsTiles(key: ValueKey(launches)),
            ),
          ),
        );
      }

      await settingsAfter(2);
      expect(
        find.byKey(const ValueKey('calendar-settings-failure-notice')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-settings-last-result')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      await settingsAfter(1);
      expect(
        find.text(
          'The calendar couldn\'t be reached the last 3 times the app started.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  test('a flag cleared, or an offer with nothing to show, is not counted as '
      'a change', () async {
    final repos = openTestRepositories();
    final at = DateTime.utc(2030, 6, 1);
    // Imported from "Contra A", flagged missing; the event is back.
    await repos.programs.create(
      Program(
        id: 'flagged',
        title: 'Contra A',
        eventDate: DateTime.utc(2030, 6, 20),
        calendarEventKey: calendarEventKey('a', ''),
        calendarFlag: calendarFlagMissing,
        createdAt: at,
        updatedAt: at,
      ),
    );
    // Imported from "Contra B", with a fingerprint that differs everywhere
    // although the program already says what the event says: an offer with
    // nothing to show.
    await repos.programs.create(
      Program(
        id: 'same',
        title: 'Contra B',
        eventDate: DateTime.utc(2030, 6, 27),
        calendarEventKey: calendarEventKey('b', ''),
        calendarEventFingerprint: 'v2:0:0:0:0:0',
        createdAt: at,
        updatedAt: at,
      ),
    );
    await _turnOn(repos);
    final preview = await buildCalendarImportPreview(
      repos,
      body: _feed,
      settings: const CalendarImportSettings(),
      today: _today,
      toLocal: (u) => u,
    );
    // The fixture does what it says: one flag clear, one hidden offer.
    expect(preview.flagChanges.map((f) => (f.program.id, f.flag)), [
      ('flagged', null),
    ]);
    expect(preview.changes.map((c) => c.program.id), contains('same'));
    expect(preview.changes.where(calendarOfferVisible), isEmpty);
    expect(await _run(repos), isA<CalendarStartupQuiet>());
  });

  test('a run that reached the calendar but failed later is not counted as '
      'unreachable', () async {
    final repos = openTestRepositories();
    await _turnOn(repos);
    final outcome = await _run(repos, fetcher: (_) async => 'BEGIN:VCALENDAR');
    expect(
      outcome,
      isA<CalendarStartupQuiet>(),
      reason: 'an empty calendar is not a failure',
    );
    await repos.settings.set(kCalendarStartupFailuresKey, 2);
    // Reached, but not a calendar (a captive-portal page): recorded as a
    // failure that reached it, and the unreachable count is left alone,
    // neither counted nor cleared.
    final portal = await _run(
      repos,
      fetcher: (_) async => '<html>Sign in to the hotel wifi</html>',
    );
    expect(portal, isA<CalendarStartupFailed>());
    expect(await repos.settings.get(kCalendarStartupFailuresKey), 2);
    final last = CalendarStartupResult.fromStored(
      await repos.settings.get(kCalendarLastResultKey),
    )!;
    expect((last.ok, last.reached), (false, true));
    // The fetcher threw: that is unreachable, so it counts.
    await _run(repos, fetcher: (_) async => throw StateError('offline'));
    expect(await repos.settings.get(kCalendarStartupFailuresKey), 3);
  });

  test('the gate runs the startup import once per launch', () async {
    final gate = CalendarStartupGate();
    var runs = 0;
    await gate.runOnce(() async => runs++);
    await gate.runOnce(() async => runs++);
    expect(runs, 1);
  });

  testWidgets('a failed or quiet outcome shows nothing at all', (tester) async {
    final repos = openTestRepositories();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                for (final outcome in const [
                  CalendarStartupFailed(),
                  CalendarStartupQuiet(),
                ]) {
                  presentCalendarStartupOutcome(
                    outcome: outcome,
                    messenger: ScaffoldMessenger.of(context),
                    l10n: AppLocalizations.of(context),
                    accessibleNavigation: false,
                    repositories: repos,
                    openReview: () {},
                    openProgram: (_) {},
                  );
                }
              },
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('changing the address in Settings clears the failure count; '
      'saving it unchanged does not', (tester) async {
    final repos = openTestRepositories();
    await tester.runAsync(() async {
      await _turnOn(repos);
      await repos.settings.set(kCalendarStartupFailuresKey, 3);
    });
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = ValueNotifier<DateFormatSetting>(DateFormatSetting.system);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => DateFormatScope(
          notifier: notifier,
          child: RepositoriesScope(repositories: repos, child: child!),
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: CalendarSettingsTiles()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> saveAddress(String value) async {
      await tester.tap(find.byKey(const ValueKey('calendar-settings-address')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('calendar-settings-address-field')),
        value,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-settings-save')));
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const ValueKey('calendar-settings-failure-notice')),
      findsOneWidget,
      reason: 'shown before any edit',
    );
    await saveAddress(_url);
    expect(
      find.byKey(const ValueKey('calendar-settings-failure-notice')),
      findsOneWidget,
    );
    await saveAddress('https://calendar.example/other.ics');
    expect(
      find.byKey(const ValueKey('calendar-settings-failure-notice')),
      findsNothing,
    );
    expect(
      await tester.runAsync(
        () => repos.settings.get(kCalendarStartupFailuresKey),
      ),
      0,
    );
  });

  testWidgets('Review ignores a feed fetched from an address changed since', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await tester.runAsync(
      () =>
          repos.settings.set(kCalendarFeedUrlKey, 'https://new.example/a.ics'),
    );
    final notifier = ValueNotifier<DateFormatSetting>(DateFormatSetting.system);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => DateFormatScope(
          notifier: notifier,
          child: RepositoriesScope(repositories: repos, child: child!),
        ),
        home: CalendarImportScreen(
          prefetchedBody: _feed,
          prefetchedUrl: _url,
          fetcher: _mustNotFetch,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contra A'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-import-summary')), findsNothing);
  });
}
