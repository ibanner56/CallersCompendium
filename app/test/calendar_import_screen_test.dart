import 'package:clock/clock.dart';
import 'package:compendium_app/src/data/calendar_import_settings.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/calendar_import_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/screens/settings/calendar_settings_tiles.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _secret = 'https://calendar.example/private-s3cr3tt0ken/basic.ics';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixed = Clock.fixed(DateTime(2030, 6, 15, 9));

  Future<void> pump(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget home,
  ) async {
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
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening the screen fetches nothing; Fetch fetches once; '
      'Import creates the drafts and Undo removes them', (tester) async {
    await withClock(fixed, () async {
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarFeedUrlKey, _secret);
      final fetched = <String>[];
      await pump(
        tester,
        repos,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CalendarImportScreen(
                    fetcher: (url) async {
                      fetched.add(url);
                      return _feed;
                    },
                    toLocal: (u) => u,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(fetched, isEmpty, reason: 'no fetch until the caller asks');

      await tester.tap(find.byKey(const ValueKey('calendar-import-fetch')));
      await tester.pumpAndSettle();
      expect(fetched, [_secret]);
      expect(find.text('Contra A'), findsOneWidget);
      expect(find.text('Contra B'), findsOneWidget);
      expect(await repos.programs.listAll(), isEmpty);

      await tester.tap(find.byKey(const ValueKey('calendar-import-commit')));
      await tester.pumpAndSettle();
      expect((await repos.programs.listAll()).map((p) => p.title), [
        'Contra A',
        'Contra B',
      ]);
      expect(find.text('2 draft programs added from your calendar.'), findsOne);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(includeDeleted: true), isEmpty);
      expect(fetched, hasLength(1));
    });
  });

  testWidgets(
    'a failed fetch shows a message that never contains the address',
    (tester) async {
      await withClock(fixed, () async {
        final repos = openTestRepositories();
        await repos.settings.set(kCalendarFeedUrlKey, _secret);
        await pump(
          tester,
          repos,
          CalendarImportScreen(
            fetcher: (_) async => throw const UrlFetchException(
              UrlFetchFailureReason.notACalendar,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('calendar-import-fetch')));
        await tester.pumpAndSettle();
        final error = tester.widget<Text>(
          find.byKey(const ValueKey('calendar-import-error')),
        );
        expect(error.data, contains('iCal'));
        expect(error.data, isNot(contains('s3cr3tt0ken')));
        expect(
          find.textContaining('s3cr3tt0ken'),
          findsOneWidget,
          reason: 'only in the address field the caller typed it into',
        );
      });
    },
  );

  testWidgets('the preview shows a timed event\'s times beside its date '
      '(#2423)', (tester) async {
    await withClock(fixed, () async {
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarFeedUrlKey, _secret);
      await pump(
        tester,
        repos,
        CalendarImportScreen(
          fetcher: (_) async => _cal([
            [
              'UID:t',
              'DTSTART:20300620T193000',
              'DTEND:20300620T223000',
              'SUMMARY:Timed contra',
            ],
            ['UID:d', 'DTSTART;VALUE=DATE:20300627', 'SUMMARY:All-day contra'],
          ]),
          toLocal: (u) => u,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('calendar-import-fetch')));
      await tester.pumpAndSettle();

      // intl may put a narrow no-break space before AM/PM.
      Finder textWith(String part) => find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').replaceAll('\u202f', ' ').contains(part),
      );
      expect(textWith('7:30 PM–10:30 PM'), findsOneWidget);
      expect(
        textWith('PM'),
        findsOneWidget,
        reason: 'the all-day event has no time',
      );
    });
  });

  testWidgets('the review offers a changed time as "Time: old → new" '
      '(#2354 with #2423)', (tester) async {
    await withClock(fixed, () async {
      final repos = openTestRepositories();
      await repos.settings.set(kCalendarFeedUrlKey, _secret);
      final at = DateTime.utc(2030, 6, 1);
      await repos.programs.create(
        Program(
          id: 'p',
          title: 'Timed contra',
          eventDate: DateTime.utc(2030, 6, 20),
          startMinute: 19 * 60,
          endMinute: 22 * 60,
          calendarEventKey: calendarEventKey('t', ''),
          calendarEventFingerprint: calendarEventFingerprint(
            title: 'Timed contra',
            date: DateTime.utc(2030, 6, 20),
            startMinute: 19 * 60,
            endMinute: 22 * 60,
          ),
          calendarWrittenAt: at,
          createdAt: at,
          updatedAt: at,
        ),
      );
      await pump(
        tester,
        repos,
        CalendarImportScreen(
          fetcher: (_) async => _cal([
            [
              'UID:t',
              'DTSTART:20300620T193000',
              'DTEND:20300620T223000',
              'SUMMARY:Timed contra',
            ],
          ]),
          toLocal: (u) => u,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('calendar-import-fetch')));
      await tester.pumpAndSettle();
      // intl may put a narrow no-break space before AM/PM.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '').replaceAll(' ', ' ') ==
                  'Time: 7:00 PM–10:00 PM → 7:30 PM–10:30 PM',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('Settings shows the address as set, never its text', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kCalendarFeedUrlKey, _secret);
    var opened = 0;
    await pump(
      tester,
      repos,
      Scaffold(
        body: ListView(
          children: [CalendarSettingsTiles(openImport: (_) async => opened++)],
        ),
      ),
    );
    expect(find.text('Set. Tap to change it.'), findsOneWidget);
    expect(find.textContaining('s3cr3tt0ken'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-settings-pull-now')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('Settings with no address says Not set', (tester) async {
    final repos = openTestRepositories();
    await pump(tester, repos, const Scaffold(body: CalendarSettingsTiles()));
    expect(find.text('Not set'), findsOneWidget);
  });

  for (final compact in [false, true]) {
    testWidgets('the Programs list offers the calendar import '
        '(${compact ? 'compact' : 'wide'})', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Existing',
          createdAt: DateTime.utc(2030),
          updatedAt: DateTime.utc(2030),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) {
            final scoped = RepositoriesScope(
              repositories: repos,
              child: child!,
            );
            return compact
                ? AppShellSearchScope(
                    searchPrograms: () async {},
                    child: scoped,
                  )
                : scoped;
          },
          home: const ProgramsListScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey(compact ? 'programs-more-actions' : 'programs-import'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-import-calendar')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarImportScreen), findsOneWidget);
    });
  }

  testWidgets('guard: saving an imported draft in the editor keeps its '
      'calendar event key, so the next import does not offer it again', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final key = calendarEventKey('a', '');
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Contra A',
        eventDate: DateTime.utc(2030, 6, 20),
        calendarEventKey: key,
        calendarEventFingerprint: 'v1:0000000000000000:1:2',
        calendarWrittenAt: DateTime.utc(2030),
        calendarFlag: calendarFlagMissing,
        createdAt: DateTime.utc(2030),
        updatedAt: DateTime.utc(2030),
      ),
    );
    await pump(
      tester,
      repos,
      ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    );
    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Contra A, planned',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();
    final saved = (await repos.programs.getById('p1'))!;
    expect(saved.title, 'Contra A, planned');
    expect(saved.calendarEventKey, key);
    expect(saved.calendarEventFingerprint, 'v1:0000000000000000:1:2');
    expect(saved.calendarWrittenAt, DateTime.utc(2030));
    expect(saved.calendarFlag, calendarFlagMissing);
    expect(saved.isUntouchedCalendarDraft, isFalse, reason: 'an edit');
  });

  testWidgets('editing the address in Settings saves it, and the dialog closes '
      'cleanly', (tester) async {
    final repos = openTestRepositories();
    await pump(tester, repos, const Scaffold(body: CalendarSettingsTiles()));
    await tester.tap(find.byKey(const ValueKey('calendar-settings-address')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-settings-address-field')),
      _secret,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-settings-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Set. Tap to change it.'), findsOneWidget);
    expect(
      await tester.runAsync(() => repos.settings.get(kCalendarFeedUrlKey)),
      _secret,
    );
  });

  testWidgets('a pasted address survives a tap outside, Escape and Back, and '
      'Cancel still closes the dialog (pre-release audit finding F-02)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await pump(tester, repos, const Scaffold(body: CalendarSettingsTiles()));
    await tester.tap(find.byKey(const ValueKey('calendar-settings-address')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('calendar-settings-address-field'));
    await tester.enterText(field, _secret);
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, _secret);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(
      await tester.runAsync(() => repos.settings.get(kCalendarFeedUrlKey)),
      isNull,
    );
  });

  testWidgets('an untouched address dialog still closes on a tap outside', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await pump(tester, repos, const Scaffold(body: CalendarSettingsTiles()));
    await tester.tap(find.byKey(const ValueKey('calendar-settings-address')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-settings-address-field')),
      findsNothing,
    );
  });

  // The address holds a secret token and never syncs, so clearing it erases
  // the row: a tombstone would keep the address on disk with nobody to tell.
  testWidgets('guard: clearing the address in Settings erases it from the '
      'database, not just from view', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kCalendarFeedUrlKey, _secret);
    await pump(tester, repos, const Scaffold(body: CalendarSettingsTiles()));
    await tester.tap(find.byKey(const ValueKey('calendar-settings-address')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-settings-address-field')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-settings-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Not set'), findsOneWidget);
    final rows = await tester.runAsync(
      () => repos.db
          .customSelect(
            'SELECT value_json FROM settings WHERE key = ?',
            variables: [Variable<String>(kCalendarFeedUrlKey)],
          )
          .get(),
    );
    expect(rows, isEmpty, reason: 'no row, tombstoned or not, holds it');
  });
}
