// A program's start, end, lesson and arrival times (#2350): the editor sets,
// changes and clears them; the summary shows them in the active locale's
// clock; the linked venue's free-text time is only a hint; and a time synced
// while the editor is open survives the editor's next save.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({
  int? start,
  int? end,
  int? lesson,
  int? arrival,
  DateTime? eventDate,
  String? venueId,
}) => Program(
  id: 'p1',
  title: 'Barn Dance',
  eventDate: eventDate,
  venueId: venueId,
  startMinute: start,
  endMinute: end,
  lessonMinute: lesson,
  arrivalMinute: arrival,
  createdAt: _now,
  updatedAt: _now,
);

/// The rendered text normalised for comparison: `intl` puts a narrow
/// no-break space before AM/PM in some versions and a plain space in others.
String _plain(String text) => text.replaceAll(' ', ' ');

Future<void> _pumpSummary(
  WidgetTester tester,
  CompendiumRepositories repos, {
  Locale locale = const Locale('en', 'US'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: const ProgramSummaryScreen(programId: 'p1'),
    ),
  );
  await tester.pumpAndSettle();
}

String? _summaryTimes(WidgetTester tester) {
  final line = find.descendant(
    of: find.byKey(const ValueKey('program-summary-times')),
    matching: find.byType(Text),
  );
  if (line.evaluate().isEmpty) return null;
  return _plain(tester.widget<Text>(line.first).data!);
}

Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool enriched = true,
  Locale locale = const Locale('en', 'US'),
  bool use24Hour = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final mode = ValueNotifier<bool>(enriched);
  addTearDown(mode.dispose);
  final autoCommit = ValueNotifier<bool>(false);
  addTearDown(autoCommit.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24Hour),
        child: RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ProgramAutoCommitScope(
              notifier: autoCommit,
              child: VenueEntityModeScope(notifier: mode, child: child!),
            ),
          ),
        ),
      ),
      home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldValue(WidgetTester tester, String field) => _plain(
  tester.widget<Text>(find.byKey(ValueKey('program-time-$field-value'))).data!,
);

/// Opens [field]'s picker, types [hour]:[minute] in its 24-hour input mode,
/// and confirms.
Future<void> _typeTime(
  WidgetTester tester,
  String field,
  int hour,
  int minute,
) async {
  await tester.tap(find.byKey(ValueKey('pick-program-time-$field')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final inputs = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), '$hour');
  await tester.enterText(inputs.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('save-program')));
  await tester.pumpAndSettle();
}

void main() {
  group('editor', () {
    testWidgets('each time can be set, changed and cleared, and is saved', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      await _pumpEditor(tester, repos, use24Hour: true);

      for (final field in ['start', 'end', 'lesson', 'arrival']) {
        expect(_fieldValue(tester, field), 'Not set');
      }
      // Set: an unset time opens at 7:30 pm.
      await tester.tap(find.byKey(const ValueKey('pick-program-time-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_fieldValue(tester, 'start'), '7:30 PM');

      await _typeTime(tester, 'end', 22, 30);
      await _typeTime(tester, 'lesson', 19, 0);
      await _typeTime(tester, 'arrival', 18, 15);
      // Change.
      await _typeTime(tester, 'arrival', 18, 45);
      expect(_fieldValue(tester, 'arrival'), '6:45 PM');
      // Clear.
      await tester.tap(find.byKey(const ValueKey('clear-program-time-lesson')));
      await tester.pumpAndSettle();
      expect(_fieldValue(tester, 'lesson'), 'Not set');

      await _save(tester);
      final saved = (await repos.programs.getById('p1'))!;
      expect(saved.startMinute, 19 * 60 + 30);
      expect(saved.endMinute, 22 * 60 + 30);
      expect(saved.lessonMinute, isNull);
      expect(saved.arrivalMinute, 18 * 60 + 45);
    });

    testWidgets('an end earlier than the start is marked as the next day', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(start: 21 * 60, end: 60));
      await _pumpEditor(tester, repos);

      expect(find.text('Ends the next day'), findsOneWidget);
    });

    testWidgets('the linked venue\'s usual time is a hint, never parsed into '
        'the fields, and the venue is not written', (tester) async {
      final repos = openTestRepositories();
      final venue = Venue(id: 'v1', name: 'Grange Hall', time: '7:30-10:30pm');
      await repos.venues.upsert(venue);
      await repos.programs.create(_program(venueId: 'v1'));
      await _pumpEditor(tester, repos);

      expect(find.text("Venue's usual time: 7:30-10:30pm"), findsOneWidget);
      expect(_fieldValue(tester, 'start'), 'Not set');
      expect(_fieldValue(tester, 'end'), 'Not set');

      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Renamed',
      );
      await _save(tester);
      final saved = (await repos.programs.getById('p1'))!;
      expect(saved.hasTimes, isFalse);
      expect(await repos.venues.getById('v1'), venue);
    });

    testWidgets('no hint without a linked venue time', (tester) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(_program(venueId: 'v1'));
      await _pumpEditor(tester, repos);

      expect(
        find.byKey(const ValueKey('program-venue-time-hint')),
        findsNothing,
      );
    });

    // Guard: the editor writes a time only if the person changed it since it
    // loaded, as it does the venue link, so a sync landing while it is open is
    // not undone by its next save.
    testWidgets('a time synced while the editor is open survives its next '
        'save; the person\'s own change still wins', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program(start: 19 * 60, end: 22 * 60, lesson: 18 * 60 + 30),
      );
      await _pumpEditor(tester, repos, use24Hour: true);

      // Another device changes the start, end and arrival; sync applies it.
      final stored = (await repos.programs.getById('p1'))!;
      await repos.programs.updateAndReadBack(
        stored.copyWith(
          startMinute: 19 * 60 + 30,
          endMinute: 23 * 60,
          arrivalMinute: 18 * 60,
          updatedAt: DateTime.utc(2026, 10, 30),
        ),
      );

      // Here the person changes only the end, and renames the program.
      await _typeTime(tester, 'end', 22, 30);
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Renamed',
      );
      await _save(tester);

      final saved = (await repos.programs.getById('p1'))!;
      expect(saved.title, 'Renamed');
      expect(saved.startMinute, 19 * 60 + 30, reason: 'synced, not edited');
      expect(saved.arrivalMinute, 18 * 60, reason: 'synced, not edited');
      expect(saved.lessonMinute, 18 * 60 + 30, reason: 'untouched');
      expect(saved.endMinute, 22 * 60 + 30, reason: 'the person\'s edit');
    });
  });

  group('summary', () {
    testWidgets('shows every set time in the en_US 12-hour clock', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program(
          eventDate: DateTime.utc(2026, 5, 1),
          start: 19 * 60 + 30,
          end: 22 * 60 + 30,
          lesson: 19 * 60,
          arrival: 18 * 60 + 30,
        ),
      );
      await _pumpSummary(tester, repos);

      expect(
        _summaryTimes(tester),
        'Lesson 7:00 PM · Dance 7:30 PM–10:30 PM · Arrive by 6:30 PM',
      );
    });

    testWidgets('shows the de_DE 24-hour clock', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program(start: 19 * 60 + 30, end: 22 * 60 + 30, arrival: 18 * 60),
      );
      await _pumpSummary(tester, repos, locale: const Locale('de', 'DE'));

      expect(_summaryTimes(tester), 'Tanz 19:30–22:30 · Ankunft bis 18:00');
    });

    testWidgets('leaves out empty times, and shows times with no date', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(lesson: 19 * 60));
      await _pumpSummary(tester, repos);

      expect(_summaryTimes(tester), 'Lesson 7:00 PM');
    });

    testWidgets('an end earlier than the start reads as the next day', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(start: 21 * 60, end: 60));
      await _pumpSummary(tester, repos);

      expect(_summaryTimes(tester), 'Dance 9:00 PM–1:00 AM (next day)');
    });

    testWidgets('no times line without times', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      await _pumpSummary(tester, repos);

      expect(_summaryTimes(tester), isNull);
    });
  });
}
