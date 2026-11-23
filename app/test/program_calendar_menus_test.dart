import 'package:clock/clock.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/export/program_calendar_export.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _stamp = DateTime.utc(2026, 1, 1);

Program _program(String id, {DateTime? eventDate, DateTime? archivedAt}) =>
    Program(
      id: id,
      title: 'Program $id',
      eventDate: eventDate,
      archivedAt: archivedAt,
      createdAt: _stamp,
      updatedAt: _stamp,
    );

/// The ids in an exported file's UIDs, in file order.
List<String> _uidIds(String ics) => [
  for (final m in RegExp(r'UID:(.*)@callers-compendium').allMatches(ics))
    m.group(1)!,
];

CalendarExportDelivery _capture(
  void Function(String ics, String name) onSave,
) => CalendarExportDelivery(
  choicePicker: (_) async => CalendarExportChoice.save,
  saveInvoker: (ics, name) async {
    onSave(ics, name);
    return null;
  },
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Programs list ▸ Export calendar (.ics)', () {
    // The injected "today": 15 Jun 2030, local time — not the real date, so
    // a version reading the wall clock fails these tests.
    final fixed = Clock.fixed(DateTime(2030, 6, 15, 9));

    Future<CompendiumRepositories> seed() async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program('today', eventDate: DateTime.utc(2030, 6, 15)),
      );
      await repos.programs.create(
        _program('later', eventDate: DateTime.utc(2030, 7, 1)),
      );
      await repos.programs.create(
        _program('yesterday', eventDate: DateTime.utc(2030, 6, 14)),
      );
      await repos.programs.create(
        _program(
          'archived-soon',
          eventDate: DateTime.utc(2030, 6, 20),
          archivedAt: _stamp,
        ),
      );
      await repos.programs.create(_program('undated'));
      return repos;
    }

    Future<void> pump(
      WidgetTester tester,
      CompendiumRepositories repos,
      CalendarExportDelivery delivery, {
      required bool compact,
    }) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<DateFormatSetting>(
        DateFormatSetting.system,
      );
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) {
            final scoped = DateFormatScope(
              notifier: notifier,
              child: RepositoriesScope(repositories: repos, child: child!),
            );
            return compact
                ? AppShellSearchScope(
                    searchPrograms: () async {},
                    child: scoped,
                  )
                : scoped;
          },
          home: ProgramsListScreen(calendarExportDelivery: delivery),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool ticked(WidgetTester tester, String id) => tester
        .widget<CheckboxListTile>(find.byKey(ValueKey('calendar-pick-$id')))
        .value!;

    for (final compact in [false, true]) {
      testWidgets('upcoming are listed ticked; past only behind the switch, '
          'unticked; the file holds the ticked ones '
          '(${compact ? 'compact' : 'wide'})', (tester) async {
        await withClock(fixed, () async {
          final repos = await seed();
          String? exported;
          String? fileName;
          await pump(
            tester,
            repos,
            _capture((ics, name) {
              exported = ics;
              fileName = name;
            }),
            compact: compact,
          );

          await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('programs-export-calendar')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('calendar-program-picker')),
            findsOne,
          );
          // The injected today is upcoming; yesterday is past.
          expect(ticked(tester, 'today'), isTrue);
          expect(ticked(tester, 'later'), isTrue);
          expect(
            find.byKey(const ValueKey('calendar-pick-yesterday')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('calendar-pick-archived-soon')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('calendar-pick-undated')),
            findsNothing,
          );

          await tester.tap(find.byKey(const ValueKey('calendar-show-past')));
          await tester.pumpAndSettle();
          expect(ticked(tester, 'yesterday'), isFalse);

          await tester.tap(
            find.byKey(const ValueKey('calendar-pick-yesterday')),
          );
          await tester.tap(find.byKey(const ValueKey('calendar-pick-later')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('calendar-picker-export')),
          );
          await tester.pumpAndSettle();

          expect(_uidIds(exported!), ['today', 'yesterday']);
          expect(fileName, 'programs.ics');
        });
      });
    }

    testWidgets('cancelling the checklist writes nothing', (tester) async {
      await withClock(fixed, () async {
        final repos = await seed();
        var saves = 0;
        await pump(tester, repos, _capture((_, _) => saves++), compact: false);
        await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('programs-export-calendar')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(saves, 0);
      });
    });

    testWidgets('Export is disabled with nothing ticked', (tester) async {
      await withClock(fixed, () async {
        final repos = await seed();
        await pump(tester, repos, _capture((_, _) {}), compact: false);
        await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('programs-export-calendar')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('calendar-pick-today')));
        await tester.tap(find.byKey(const ValueKey('calendar-pick-later')));
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('calendar-picker-export')),
        );
        expect(button.onPressed, isNull);
      });
    });
  });

  group('Program ▸ Export ▸ Add to calendar (.ics)', () {
    late bool Function() savedUnsupported;
    setUp(() {
      savedUnsupported = isBundleShareUnsupported;
      isBundleShareUnsupported = () => false;
    });
    tearDown(() => isBundleShareUnsupported = savedUnsupported);

    Future<void> pumpMenu(
      WidgetTester tester,
      Program program,
      CalendarExportDelivery delivery,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ProgramExportMenu(
                  program: program,
                  titleFor: (_) => null,
                  calendarExportDelivery: delivery,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
    }

    for (final (label, date) in [
      ('upcoming', DateTime.utc(2099, 1, 1)),
      ('past', DateTime.utc(2001, 1, 1)),
    ]) {
      testWidgets('offered for a $label program, and exports it alone', (
        tester,
      ) async {
        String? exported;
        String? fileName;
        await pumpMenu(
          tester,
          _program('p1', eventDate: date),
          _capture((ics, name) {
            exported = ics;
            fileName = name;
          }),
        );
        expect(find.text('Add to calendar (.ics)'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('program-export-calendar')));
        await tester.pumpAndSettle();
        expect(_uidIds(exported!), ['p1']);
        expect(fileName, endsWith('.ics'));
      });
    }

    testWidgets('not offered for a program with no date', (tester) async {
      await pumpMenu(tester, _program('p1'), _capture((_, _) {}));
      expect(find.text('Export / print PDF'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('program-export-calendar')),
        findsNothing,
      );
      expect(find.text('Add to calendar (.ics)'), findsNothing);
    });
  });

  group('Program builder ▸ Export ▸ Add to calendar (.ics)', () {
    Future<void> pumpEditor(
      WidgetTester tester,
      CompendiumRepositories repos, {
      String? programId,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) =>
              RepositoriesScope(repositories: repos, child: child!),
          home: ProgramEditorScreen(programId: programId, onSaved: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<bool> offered(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('program-export-menu')));
      await tester.pumpAndSettle();
      final found = find
          .byKey(const ValueKey('program-export-calendar'))
          .evaluate()
          .isNotEmpty;
      // Close the menu.
      await tester.tapAt(const Offset(4, 600));
      await tester.pumpAndSettle();
      return found;
    }

    testWidgets('offered for a saved program, not once it has unsaved edits', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program('p1', eventDate: DateTime.utc(2030, 6, 15)),
      );
      await pumpEditor(tester, repos, programId: 'p1');
      expect(await offered(tester), isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Renamed',
      );
      await tester.pumpAndSettle();
      // Its UID and SEQUENCE would describe the stored program, not this one.
      expect(await offered(tester), isFalse);
    });

    testWidgets('not offered for a new program that was never saved, even '
        'with a date', (tester) async {
      final repos = openTestRepositories();
      await pumpEditor(tester, repos);
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'New gig',
      );
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('pick-event-date'))
          .hitTestable()
          .evaluate()
          .isEmpty) {
        await tester.tap(find.text('More details'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('pick-event-date')));
      await tester.tap(find.byKey(const ValueKey('pick-event-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('clear-event-date')),
        findsOneWidget,
        reason: 'the new program now has a date',
      );
      // It would be exported as `draft@callers-compendium`.
      expect(await offered(tester), isFalse);
    });
  });
}
