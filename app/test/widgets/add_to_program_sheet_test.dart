import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/widgets/add_to_program_list.dart';
import 'package:compendium_app/src/widgets/add_to_program_sheet.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program(
  String id, {
  String? title,
  ProgramStatus status = ProgramStatus.draft,
  DateTime? eventDate,
  DateTime? updatedAt,
  String? venue,
  String? venueId,
  List<ProgramSlot> slots = const [],
}) => Program(
  id: id,
  title: title ?? 'Program $id',
  status: status,
  eventDate: eventDate,
  venue: venue,
  venueId: venueId,
  slots: slots,
  createdAt: _now,
  updatedAt: updatedAt ?? _now,
);

List<String> _ids(Iterable<Program> programs) => [
  for (final p in programs) p.id,
];

/// Opens the sheet from a button, with [repos] in scope.
Future<void> _openSheet(
  WidgetTester tester,
  CompendiumRepositories repos, {
  Size surface = const Size(800, 1200),
  double keyboard = 0,
}) async {
  await repos.dances.create(
    Dance(id: 'd1', title: 'Chorus Jig', createdAt: _now, updatedAt: _now),
  );
  // The view's own size, not `setSurfaceSize`: the latter leaves MediaQuery
  // reporting the default 2400×1800 screen.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () => showAddToProgramSheet(
                  context,
                  repositories: repos,
                  danceId: 'd1',
                  danceTitle: 'Chorus Jig',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('program-pick-$id'));
final _search = find.byKey(const ValueKey('add-to-program-search'));
final _performedToggle = find.byKey(
  const ValueKey('add-to-program-performed-toggle'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('groupProgramsForAdd', () {
    final today = DateTime(2026, 6, 15);

    test('open: dated today or later soonest first, then the rest by edit', () {
      final groups = groupProgramsForAdd([
        _program('undated-new', updatedAt: DateTime.utc(2026, 6, 1)),
        _program(
          'later',
          eventDate: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        _program(
          'past-draft',
          eventDate: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 6, 10),
        ),
        _program('today', eventDate: DateTime.utc(2026, 6, 15)),
        _program('undated-old', updatedAt: DateTime.utc(2026, 2, 1)),
      ], today: today);
      expect(_ids(groups.open), [
        'today',
        'later',
        'past-draft',
        'undated-new',
        'undated-old',
      ]);
    });

    test(
      'Performed programs leave the open group whatever their edit time',
      () {
        final groups = groupProgramsForAdd([
          _program('old-open', updatedAt: DateTime.utc(2020, 1, 1)),
          _program(
            'new-done',
            status: ProgramStatus.performed,
            updatedAt: DateTime.utc(2026, 6, 14),
          ),
        ], today: today);
        expect(_ids(groups.open), ['old-open']);
        expect(_ids(groups.performed), ['new-done']);
      },
    );

    test('Performed: newest event first, undated last by edit', () {
      final groups = groupProgramsForAdd([
        _program(
          'undated',
          status: ProgramStatus.performed,
          updatedAt: DateTime.utc(2026, 6, 14),
        ),
        _program(
          'older',
          status: ProgramStatus.performed,
          eventDate: DateTime.utc(2026, 3, 1),
        ),
        _program(
          'newer',
          status: ProgramStatus.performed,
          eventDate: DateTime.utc(2026, 5, 1),
        ),
      ], today: today);
      expect(_ids(groups.performed), ['newer', 'older', 'undated']);
    });
  });

  group('filterProgramsForAdd', () {
    final venues = {'v1': Venue(id: 'v1', name: 'Grange Hall')};

    test('folds case and accents on titles', () {
      final programs = [_program('a', title: 'École Night'), _program('b')];
      expect(
        _ids(filterProgramsForAdd(programs, 'ECOLE', venuesById: venues)),
        ['a'],
      );
    });

    test('matches a linked venue and a free-text venue', () {
      final programs = [
        _program('linked', venueId: 'v1'),
        _program('free', venue: 'The Barn'),
        _program('none'),
      ];
      expect(
        _ids(filterProgramsForAdd(programs, 'grange', venuesById: venues)),
        ['linked'],
      );
      expect(_ids(filterProgramsForAdd(programs, 'barn', venuesById: venues)), [
        'free',
      ]);
    });

    test('a blank query keeps everything', () {
      final programs = [_program('a'), _program('b')];
      expect(
        filterProgramsForAdd(programs, '  ', venuesById: venues),
        programs,
      );
    });
  });

  group('the sheet', () {
    testWidgets('lists an open program above a Performed one, whatever its '
        'edit time', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program(
          'done',
          status: ProgramStatus.performed,
          updatedAt: DateTime.utc(2026, 6, 14),
        ),
      );
      await repos.programs.create(
        _program('open', updatedAt: DateTime.utc(2020, 1, 1)),
      );
      await _openSheet(tester, repos);

      expect(_row('open'), findsOneWidget);
      // Collapsed: the Performed program is a count, not a row.
      expect(_row('done'), findsNothing);
      expect(find.text('Performed (1)'), findsOneWidget);
    });

    testWidgets('Performed expands on tap and collapses again', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('open'));
      await repos.programs.create(
        _program('done', status: ProgramStatus.performed),
      );
      await _openSheet(tester, repos);

      await tester.tap(_performedToggle);
      await tester.pumpAndSettle();
      expect(_row('done'), findsOneWidget);
      expect(
        tester.getTopLeft(_row('open')).dy,
        lessThan(tester.getTopLeft(_row('done')).dy),
      );

      await tester.tap(_performedToggle);
      await tester.pumpAndSettle();
      expect(_row('done'), findsNothing);
    });

    testWidgets('Performed opens by itself when no program is open', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program('done', status: ProgramStatus.performed),
      );
      await _openSheet(tester, repos);

      expect(_row('done'), findsOneWidget);
    });

    testWidgets('a status shows on every row, as text and an icon', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('d', status: ProgramStatus.draft));
      await repos.programs.create(
        _program('f', status: ProgramStatus.finalized),
      );
      await _openSheet(tester, repos);

      expect(
        find.descendant(of: _row('d'), matching: find.textContaining('Draft')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('f'),
          matching: find.textContaining('Finalized'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row('d'), matching: find.byType(Icon)),
        findsOneWidget,
      );
    });

    testWidgets('no search field with 8 programs, one with 9', (tester) async {
      final repos = openTestRepositories();
      for (var i = 0; i < kAddToProgramSearchThreshold; i++) {
        await repos.programs.create(_program('p$i'));
      }
      await _openSheet(tester, repos);
      expect(_search, findsNothing);

      Navigator.of(tester.element(find.byType(AddToProgramList))).pop();
      await tester.pumpAndSettle();
      await repos.programs.create(_program('p-extra'));
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(_search, findsOneWidget);
    });

    testWidgets('search folds accents and matches a venue name', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      for (var i = 0; i < 9; i++) {
        await repos.programs.create(_program('p$i'));
      }
      await repos.programs.create(_program('accent', title: 'École Night'));
      await repos.programs.create(_program('venue', venueId: 'v1'));
      await _openSheet(tester, repos);

      await tester.enterText(_search, 'ecole');
      await tester.pumpAndSettle();
      expect(_row('accent'), findsOneWidget);
      expect(_row('p0'), findsNothing);

      await tester.enterText(_search, 'grange');
      await tester.pumpAndSettle();
      expect(_row('venue'), findsOneWidget);
      expect(_row('accent'), findsNothing);

      await tester.enterText(_search, 'zzz');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('add-to-program-no-matches')),
        findsOneWidget,
      );
    });

    testWidgets('a search matching only Performed programs expands the group, '
        'and clearing it collapses the group again', (tester) async {
      final repos = openTestRepositories();
      for (var i = 0; i < 9; i++) {
        await repos.programs.create(_program('p$i'));
      }
      await repos.programs.create(
        _program('done', title: 'Gala', status: ProgramStatus.performed),
      );
      await _openSheet(tester, repos);
      expect(_row('done'), findsNothing);

      await tester.enterText(_search, 'gala');
      await tester.pumpAndSettle();
      expect(_row('done'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('add-to-program-search-clear')),
      );
      await tester.pumpAndSettle();
      expect(_row('done'), findsNothing);
    });

    testWidgets('adding to a Performed program leaves it Performed with the '
        'new slot unperformed', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program('done', status: ProgramStatus.performed),
      );
      await _openSheet(tester, repos);

      await tester.tap(_row('done'));
      await tester.pumpAndSettle();

      final saved = (await repos.programs.getById('done'))!;
      expect(saved.status, ProgramStatus.performed);
      expect(saved.slots, hasLength(1));
      expect(saved.slots.single.danceId, 'd1');
      expect(saved.slots.single.performedAt, isNull);
    });

    testWidgets('at 360×640 with the keyboard up, the New row, the search '
        'field and a program row are all visible above it', (tester) async {
      final repos = openTestRepositories();
      for (var i = 0; i < 12; i++) {
        await repos.programs.create(_program('p$i'));
      }
      const keyboard = 300.0;
      await _openSheet(
        tester,
        repos,
        surface: const Size(360, 640),
        keyboard: keyboard,
      );

      const visibleBottom = 640 - keyboard;
      for (final finder in [
        find.byKey(const ValueKey('add-to-program-create')),
        _search,
        _row('p0'),
      ]) {
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(visibleBottom));
      }
    });
  });
}
