import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/widgets/app_bar_text_action.dart';
import 'package:compendium_app/src/widgets/program_list_tile.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Archiving a program: the Programs list's "Show archived" / "Hide archived",
/// the row, summary and builder actions, and where each one leaves the caller.
final _now = DateTime.utc(2026, 1, 1);

Program _program(String id, String title, {DateTime? archivedAt}) => Program(
  id: id,
  title: title,
  archivedAt: archivedAt,
  createdAt: _now,
  updatedAt: _now,
);

List<String> _titles(WidgetTester tester) => tester
    .widgetList<ProgramListTile>(find.byType(ProgramListTile))
    .map((t) => t.program.title)
    .toList();

Widget _app(
  CompendiumRepositories repos,
  Widget home, {
  bool compact = false,
}) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  builder: (context, child) {
    final scoped = RepositoriesScope(repositories: repos, child: child!);
    return compact
        ? AppShellSearchScope(openSearch: () async {}, child: scoped)
        : scoped;
  },
  home: home,
);

Future<void> _pumpList(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool compact = false,
  bool isActive = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      repos,
      ProgramsListScreen(key: const ValueKey('list'), isActive: isActive),
      compact: compact,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMoreActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<CompendiumRepositories> seeded() async {
    final repos = openTestRepositories();
    await repos.programs.create(_program('p1', 'Alpha'));
    await repos.programs.create(
      _program('p2', 'Bravo', archivedAt: DateTime.utc(2026, 2, 1)),
    );
    return repos;
  }

  group('Programs list', () {
    testWidgets('hides archived programs until Show archived, which then '
        'reads Hide archived and hides them again', (tester) async {
      final repos = await seeded();
      await _pumpList(tester, repos);
      expect(_titles(tester), ['Alpha']);
      expect(find.text('1 program'), findsOneWidget);

      await _openMoreActions(tester);
      expect(find.text('Show archived'), findsOneWidget);
      expect(find.text('Hide archived'), findsNothing);
      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha', 'Bravo']);
      expect(find.text('2 programs'), findsOneWidget);
      // Only the archived row carries the chip.
      expect(
        find.descendant(
          of: find.widgetWithText(ProgramListTile, 'Bravo'),
          matching: find.byKey(const ValueKey('program-archived-chip')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('program-archived-chip')),
        findsOneWidget,
      );

      await _openMoreActions(tester);
      expect(find.text('Hide archived'), findsOneWidget);
      expect(find.text('Show archived'), findsNothing);
      await tester.tap(find.text('Hide archived'));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha']);
    });

    for (final compact in [false, true]) {
      testWidgets('Show archived sits just above Recently deleted '
          '(${compact ? 'phone' : 'wide'} menu)', (tester) async {
        final repos = await seeded();
        await _pumpList(tester, repos, compact: compact);
        await _openMoreActions(tester);
        final toggle = tester.getTopLeft(
          find.byKey(const ValueKey('programs-toggle-archived')),
        );
        final trash = tester.getTopLeft(
          find.byKey(const ValueKey('programs-recently-deleted')),
        );
        expect(toggle.dy, lessThan(trash.dy));
        final items = tester
            .widgetList<PopupMenuEntry<Object?>>(
              find.byWidgetPredicate((w) => w is PopupMenuEntry),
            )
            .toList();
        final toggleIndex = items.indexWhere(
          (i) => i.key == const ValueKey('programs-toggle-archived'),
        );
        expect(
          items[toggleIndex + 1].key,
          const ValueKey('programs-recently-deleted'),
        );
      });
    }

    testWidgets('a row ⋮ Archive archives it and drops the row; Undo brings it '
        'back', (tester) async {
      final repos = await seeded();
      await _pumpList(tester, repos);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      // After Duplicate, before Delete.
      final duplicate = tester.getTopLeft(
        find.byKey(const ValueKey('program-action-duplicate')),
      );
      final archive = tester.getTopLeft(
        find.byKey(const ValueKey('program-action-archive')),
      );
      final delete = tester.getTopLeft(
        find.byKey(const ValueKey('program-action-delete')),
      );
      expect(duplicate.dy, lessThan(archive.dy));
      expect(archive.dy, lessThan(delete.dy));
      await tester.tap(find.byKey(const ValueKey('program-action-archive')));
      await tester.pumpAndSettle();

      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(_titles(tester), isEmpty);
      expect(find.text('"Alpha" archived.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isFalse);
      expect(_titles(tester), ['Alpha']);
    });

    testWidgets('an archived row, shown, offers Unarchive and stays listed', (
      tester,
    ) async {
      final repos = await seeded();
      await _pumpList(tester, repos);
      await _openMoreActions(tester);
      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-actions-p2')));
      await tester.pumpAndSettle();
      expect(find.text('Unarchive'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      await tester.tap(find.text('Unarchive'));
      await tester.pumpAndSettle();

      expect((await repos.programs.getById('p2'))!.isArchived, isFalse);
      expect(_titles(tester), ['Alpha', 'Bravo']);
      expect(find.byKey(const ValueKey('program-archived-chip')), findsNothing);
      expect(find.text('"Bravo" unarchived.'), findsOneWidget);
    });

    testWidgets('with every program archived, the empty state says so and '
        'offers Show archived', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(
        _program('p1', 'Alpha', archivedAt: DateTime.utc(2026, 2, 1)),
      );
      await _pumpList(tester, repos);
      expect(find.text('No programs to show'), findsOneWidget);
      expect(find.text('No programs yet'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('empty-show-archived')));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha']);
    });

    testWidgets('Show archived lasts while the list stays active and resets '
        'when it goes inactive', (tester) async {
      final repos = await seeded();
      await _pumpList(tester, repos);
      await _openMoreActions(tester);
      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();

      // A route on top (opening a program) keeps it.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('on top')),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha', 'Bravo']);

      // Rebuilt still active: kept.
      await tester.pumpWidget(
        _app(
          repos,
          const ProgramsListScreen(key: ValueKey('list'), isActive: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha', 'Bravo']);

      // Another destination chosen, then Programs again: reset.
      await tester.pumpWidget(
        _app(
          repos,
          const ProgramsListScreen(key: ValueKey('list'), isActive: false),
        ),
      );
      await tester.pumpWidget(
        _app(
          repos,
          const ProgramsListScreen(key: ValueKey('list'), isActive: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(_titles(tester), ['Alpha']);
    });
  });

  group('program summary', () {
    Future<List<String>> pumpSummary(
      WidgetTester tester,
      CompendiumRepositories repos, {
      required Size size,
      String id = 'p1',
    }) async {
      final closed = <String>[];
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          repos,
          Scaffold(
            body: ProgramSummaryPane(
              programId: id,
              showAppBar: true,
              onOpenBuilder: () {},
              onDeleted: () => closed.add('closed'),
              onNavigateTo: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return closed;
    }

    testWidgets('wide: Archive follows Duplicate, archives, and leaves the '
        'view', (tester) async {
      final repos = await seeded();
      final closed = await pumpSummary(
        tester,
        repos,
        size: const Size(1000, 900),
      );
      final duplicate = tester.getTopLeft(
        find.byKey(const ValueKey('summary-duplicate')),
      );
      final archive = tester.getTopLeft(
        find.byKey(const ValueKey('summary-archive')),
      );
      final delete = tester.getTopLeft(
        find.byKey(const ValueKey('summary-delete')),
      );
      expect(duplicate.dx, lessThan(archive.dx));
      expect(archive.dx, lessThan(delete.dx));

      await tester.tap(find.byKey(const ValueKey('summary-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(closed, ['closed']);
    });

    testWidgets('narrow: Archive is in the ⋮ menu, right after Duplicate', (
      tester,
    ) async {
      final repos = await seeded();
      final closed = await pumpSummary(
        tester,
        repos,
        size: const Size(400, 900),
      );
      expect(
        find.byKey(const ValueKey('summary-archive')),
        findsNothing,
        reason: 'folded into the menu on a narrow pane',
      );
      await tester.tap(find.byKey(const ValueKey('summary-actions-overflow')));
      await tester.pumpAndSettle();
      final entries = tester
          .widgetList<PopupMenuEntry<Object?>>(
            find.byWidgetPredicate((w) => w is PopupMenuEntry),
          )
          .map((e) => e.key)
          .toList();
      final at = entries.indexOf(const ValueKey('summary-duplicate'));
      expect(entries[at + 1], const ValueKey('summary-archive'));

      await tester.tap(find.byKey(const ValueKey('summary-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(closed, ['closed']);
    });

    testWidgets('an archived program shows the chip and Unarchive, and '
        'unarchiving stays in the view', (tester) async {
      final repos = await seeded();
      final closed = await pumpSummary(
        tester,
        repos,
        size: const Size(1000, 900),
        id: 'p2',
      );
      expect(
        find.byKey(const ValueKey('program-archived-chip')),
        findsOneWidget,
      );
      expect(find.byTooltip('Unarchive'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('summary-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p2'))!.isArchived, isFalse);
      expect(closed, isEmpty);
      expect(find.byKey(const ValueKey('program-archived-chip')), findsNothing);
      expect(find.byTooltip('Archive'), findsOneWidget);
    });
  });

  group('program builder', () {
    Future<List<String?>> pumpBuilder(
      WidgetTester tester,
      CompendiumRepositories repos, {
      required Size size,
      String id = 'p1',
    }) async {
      final popped = <String?>[];
      // The builder folds its actions by window width (MediaQuery), so the
      // view itself is sized, as the phone-layout tests do.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          repos,
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  popped.add(
                    await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(
                        builder: (_) => ProgramEditorScreen(programId: id),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('wide: Archive follows Duplicate, archives and exits like '
        'Delete', (tester) async {
      final repos = await seeded();
      final popped = await pumpBuilder(
        tester,
        repos,
        size: const Size(1200, 900),
      );
      final duplicate = tester.getTopLeft(
        find.byKey(const ValueKey('duplicate-program')),
      );
      final archive = tester.getTopLeft(
        find.byKey(const ValueKey('archive-program')),
      );
      final delete = tester.getTopLeft(
        find.byKey(const ValueKey('delete-program')),
      );
      expect(duplicate.dx, lessThan(archive.dx));
      expect(archive.dx, lessThan(delete.dx));

      await tester.tap(find.byKey(const ValueKey('archive-program')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(popped, ['archived']);
      expect(find.byType(ProgramEditorScreen), findsNothing);
    });

    testWidgets('narrow: Archive is in the ⋮ menu right after Duplicate, and '
        'saves the edit on screen first', (tester) async {
      final repos = await seeded();
      final popped = await pumpBuilder(
        tester,
        repos,
        size: const Size(400, 900),
      );
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Alpha renamed',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('program-actions-overflow')));
      await tester.pumpAndSettle();
      final entries = tester
          .widgetList<PopupMenuEntry<Object?>>(
            find.byWidgetPredicate((w) => w is PopupMenuEntry),
          )
          .map((e) => e.key)
          .toList();
      final at = entries.indexOf(const ValueKey('duplicate-program'));
      expect(entries[at + 1], const ValueKey('archive-program'));

      await tester.tap(find.byKey(const ValueKey('archive-program')));
      await tester.pumpAndSettle();
      final stored = (await repos.programs.getById('p1'))!;
      expect(stored.isArchived, isTrue);
      expect(stored.title, 'Alpha renamed');
      expect(popped, ['archived']);
    });

    testWidgets('while Archive is saving the edits on screen, Delete and Save '
        'are disabled, so the builder cannot leave twice', (tester) async {
      final delayed = openTestRepositoriesWithDelayedPrograms();
      final repos = delayed.repos;
      await repos.programs.create(_program('p1', 'Alpha'));
      final popped = await pumpBuilder(
        tester,
        repos,
        size: const Size(1200, 900),
      );
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Alpha renamed',
      );
      await tester.pump();

      delayed.programs.holdNextWrite();
      await tester.tap(find.byKey(const ValueKey('archive-program')));
      await delayed.programs.writeStarted;
      await tester.pump();
      IconButton button(String key) =>
          tester.widget<IconButton>(find.byKey(ValueKey(key)));
      expect(button('delete-program').onPressed, isNull);
      expect(button('archive-program').onPressed, isNull);
      final save = tester.widget<AppBarTextAction>(
        find.byKey(const ValueKey('save-program')),
      );
      expect(save.onPressed, isNull);

      delayed.programs.releaseWrite();
      await tester.pumpAndSettle();
      final stored = (await repos.programs.getById('p1'))!;
      expect(stored.isArchived, isTrue);
      expect(stored.isDeleted, isFalse);
      expect(popped, ['archived']);
    });

    testWidgets('an archive that lands while a save is in flight survives the '
        'save', (tester) async {
      final delayed = openTestRepositoriesWithDelayedPrograms();
      final repos = delayed.repos;
      await repos.programs.create(_program('p1', 'Alpha'));
      await pumpBuilder(tester, repos, size: const Size(1200, 900));
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Alpha renamed',
      );
      await tester.pump();

      // The save has read the program and is held just before its write; the
      // archive (another device's, or a second window's) lands in that gap.
      delayed.programs.holdNextWrite();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await delayed.programs.writeStarted;
      await repos.programs.archive('p1', at: DateTime.utc(2026, 3, 1));
      delayed.programs.releaseWrite();
      await tester.pumpAndSettle();

      final stored = (await repos.programs.getById('p1'))!;
      expect(stored.title, 'Alpha renamed');
      expect(stored.archivedAt, DateTime.utc(2026, 3, 1));
    });

    testWidgets('a save after Unarchive does not archive the program again, '
        'and a save never unarchives one', (tester) async {
      final repos = await seeded();
      await pumpBuilder(tester, repos, size: const Size(1200, 900), id: 'p2');
      expect(find.byTooltip('Unarchive'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('archive-program')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p2'))!.isArchived, isFalse);
      expect(find.byType(ProgramEditorScreen), findsOneWidget);
      expect(find.byTooltip('Archive'), findsOneWidget);

      // Archived elsewhere while the builder is open (as a sync would): a save
      // from this builder must keep the stored state, not its stale copy.
      await repos.programs.archive('p2', at: DateTime.utc(2026, 3, 1));
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Bravo edited',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();
      final stored = (await repos.programs.getById('p2'))!;
      expect(stored.title, 'Bravo edited');
      expect(stored.archivedAt, DateTime.utc(2026, 3, 1));
    });
  });
}
