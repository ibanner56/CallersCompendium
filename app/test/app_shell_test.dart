import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/show_repertoire_scope.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/theme/app_breakpoints.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/hardware_keyboard_presence.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';
import 'package:compendium_app/src/update/update_controller.dart';
import 'package:compendium_app/src/update/update_scope.dart';
import 'package:compendium_app/src/update/update_service.dart';
import 'package:compendium_app/src/widgets/brand_mark.dart';
import 'package:compendium_app/src/widgets/command_palette.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Size size,
  ImportPicker? reimportPicker,
  ValueNotifier<bool>? showGlossary,
  ValueNotifier<bool>? showRepertoire,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    AppThemeSelection.system,
  );
  addTearDown(themeNotifier.dispose);
  final requirePerformedNotifier = ValueNotifier<bool>(false);
  addTearDown(requirePerformedNotifier.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  // The shell hosts the app-wide UpdateBanner, which reads an UpdateScope. Wire
  // one with a no-network fetcher so the banner stays hidden (no update found)
  // and no real HTTP is attempted during shell tests.
  final updateController = UpdateController(
    repos.settings,
    service: UpdateService(fetcher: (_, {client}) async => null),
  );
  addTearDown(updateController.dispose);
  final shellKey = GlobalKey<AppShellState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      // Mirrors the root MaterialApp in main.dart, which owns Ctrl/Cmd-K.
      shortcuts: {...WidgetsApp.defaultShortcuts, ...searchShortcuts},
      actions: {
        ...WidgetsApp.defaultActions,
        OpenSearchIntent: CallbackAction<OpenSearchIntent>(
          onInvoke: (_) {
            shellKey.currentState?.openSearch();
            return null;
          },
        ),
      },
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: UpdateScope(
          controller: updateController,
          child: AppThemeScope(
            notifier: themeNotifier,
            child: CustomThemesScope(
              controller: customThemes,
              child: ActiveDialectScope(
                notifier: notifier,
                child: RequirePerformedForHistoryScope(
                  notifier: requirePerformedNotifier,
                  child: _maybeShowRepertoire(
                    showRepertoire,
                    showGlossary == null
                        ? child!
                        : ShowGlossaryScope(
                            notifier: showGlossary,
                            child: child!,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      home: AppShell(key: shellKey, reimportPicker: reimportPicker),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mounts [ShowRepertoireScope] only when a test supplies a notifier.
Widget _maybeShowRepertoire(ValueNotifier<bool>? notifier, Widget child) =>
    notifier == null
    ? child
    : ShowRepertoireScope(notifier: notifier, child: child);

void main() {
  // The guide is now a kept-alive shell destination, so its doc FutureBuilder
  // builds (offstage) in every test. The root bundle caches parsed results as
  // `SynchronousFuture`s after the first load, which stalls that FutureBuilder
  // (leaving its spinner animating so `pumpAndSettle` never settles); clearing
  // the cache before each test makes the guide load fresh and settle.
  setUp(rootBundle.clear);
  // Each test starts as a fresh run that has seen no key press.
  setUp(HardwareKeyboardPresence.debugReset);

  testWidgets('narrow layout uses a bottom NavigationBar', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Collection is the default tab.
    expect(find.text('Collection'), findsWidgets);
  });

  testWidgets('wide layout uses a NavigationRail', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('wide layout seats a brand mark atop the nav rail', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    // A compact brand mark lives in the rail header (above the search button);
    // scoped to the rail so it is distinct from any empty-state marks in the
    // body content.
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(BrandMark),
      ),
      findsOneWidget,
    );
    // Rail wiring is preserved: the search button still sits in the rail.
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byKey(const ValueKey('global-search-button')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('narrow layout has no rail brand mark', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    // The rail mark is desktop-only (§4.3); the bottom-nav layout carries none.
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(BrandMark),
      ),
      findsNothing,
    );
  });

  testWidgets('switching to Programs shows the Programs screen', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Nav Target Program',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(500, 900));

    // Tap the Programs destination in the bottom bar.
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();

    expect(find.text('Nav Target Program'), findsOneWidget);

    // Switching back keeps the Collection alive.
    await tester.tap(find.text('Collection').last);
    await tester.pumpAndSettle();
    expect(find.text('Nav Target Program'), findsNothing);
  });

  group('Show archived on the Programs list', () {
    Future<CompendiumRepositories> seeded() async {
      final repos = openTestRepositories();
      final now = DateTime.utc(2026, 1, 1);
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Live Program',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p2',
          title: 'Archived Program',
          archivedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return repos;
    }

    Future<void> showArchived(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();
      expect(find.text('Archived Program'), findsOneWidget);
    }

    for (final destination in ['Collection', 'Settings']) {
      testWidgets('outlasts opening a program, and resets when $destination '
          'is chosen', (tester) async {
        final repos = await seeded();
        await _pump(tester, repos, size: const Size(500, 900));
        await tester.tap(find.text('Programs').last);
        await tester.pumpAndSettle();
        expect(find.text('Archived Program'), findsNothing);
        await showArchived(tester);

        // Open the archived program's summary and its builder, then come back.
        await tester.tap(find.text('Archived Program'));
        await tester.pumpAndSettle();
        expect(find.byType(ProgramSummaryScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('open-builder')));
        await tester.pumpAndSettle();
        expect(find.byType(ProgramEditorScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Archived Program'), findsOneWidget);

        await tester.tap(
          find.widgetWithText(NavigationDestination, destination),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Programs').last);
        await tester.pumpAndSettle();
        expect(find.text('Live Program'), findsOneWidget);
        expect(find.text('Archived Program'), findsNothing);
      });
    }

    testWidgets('wide: archiving the open program from its row closes it', (
      tester,
    ) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(find.byType(ProgramSummaryPane), findsNothing);
    });

    testWidgets('wide: Hide archived closes an open archived program, and '
        'leaves an open unarchived one', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await showArchived(tester);

      // An unarchived program stays open across Hide archived.
      await tester.tap(find.text('Live Program'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide archived'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);

      // An archived one closes.
      await showArchived(tester);
      await tester.tap(find.text('Archived Program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide archived'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsNothing);
      expect(await repos.programs.getById('p2'), isNotNull);
    });

    testWidgets('wide: leaving Programs with Show archived on closes an open '
        'archived program', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await showArchived(tester);
      await tester.tap(find.text('Archived Program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);

      await tester.tap(find.text('Collection').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      expect(find.text('Archived Program'), findsNothing);
      expect(find.byType(ProgramSummaryPane), findsNothing);
    });

    testWidgets('wide: a program deleted from its row is not closed by the '
        'hidden-program check', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Program'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1')), isNull);
      // Deleting keeps the behaviour it had before archiving existed: the
      // pane stays, saying the program is unavailable.
      expect(find.byType(ProgramSummaryPane), findsOneWidget);
    });

    testWidgets('a program archived while narrow is closed on rotating back to '
        'wide', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(600, 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsNothing);
    });

    testWidgets('wide: archiving from the summary pane closes the program', (
      tester,
    ) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(1400, 900));
      await tester.tap(find.text('Programs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramSummaryPane), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('summary-archive')));
      await tester.pumpAndSettle();
      expect((await repos.programs.getById('p1'))!.isArchived, isTrue);
      expect(find.byType(ProgramSummaryPane), findsNothing);
      expect(find.text('Live Program'), findsNothing);
    });
  });

  testWidgets('a rotation across the rail breakpoint mid-set keeps the '
      "program's Perform place (GIG-14)", (tester) async {
    final repos = openTestRepositories();
    final now = DateTime.utc(2026, 1, 1);
    for (final (id, title) in [('d1', 'First Dance'), ('d2', 'Second Dance')]) {
      await repos.dances.create(
        Dance(
          id: id,
          title: title,
          authorIds: const [],
          tagIds: const [],
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: const [],
          customFields: const [],
          hook: '',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Rotation Night',
        slots: [
          ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _pump(tester, repos, size: const Size(1400, 900));
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotation Night'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pump();

    // Crossing the rail width swaps rail for bottom bar, which rebuilds
    // everything under it unless it is moved. The shells are laid out again
    // only once Perform has gone.
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();

    // The program it was performing resumes at slot 2.
    await tester.tap(find.text('Rotation Night'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('perform-position'))).data,
      'Slot 2 of 2',
    );
  });

  testWidgets('turning a phone to landscape keeps what each destination '
      'holds: the Collection search, the Settings section', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Petronella',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    // Portrait: bottom bar. Landscape: wider than the rail width, so the rail.
    await _pump(tester, repos, size: const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    final field = find.byKey(const ValueKey('collection-search-field'));
    await tester.enterText(field, 'petro');
    await tester.pumpAndSettle();

    String searchText() => tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .controller
        .text;
    expect(searchText(), 'petro');

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(searchText(), 'petro');

    // The Settings section chosen on a wide window survives a narrowing too.
    await tester.binding.setSurfaceSize(const Size(1000, 844));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-updates')));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1000, 844));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('settings-nav-updates')))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Collection').last);
    await tester.pumpAndSettle();
    expect(searchText(), 'petro');
  });

  testWidgets('exposes four destinations including Settings and Guide', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Guide'), findsWidgets);
  });

  testWidgets('selecting Settings shows the settings content inline', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    // The Settings page renders inline in the IndexedStack: its title shows and
    // the section sidebar is visible, with no Navigator back affordance.
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Appearance'), findsWidgets);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Ctrl-K opens the global search palette', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });

  testWidgets('the rail search button opens the palette (wide)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.tap(find.byKey(const ValueKey('global-search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });

  testWidgets('global search opens a saved dance with re-import available', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Petronella',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(1200, 900));

    await tester.tap(find.byKey(const ValueKey('global-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('command-result-dance-d1')));
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dance-actions-overflow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reimport-dance')), findsOneWidget);
  });

  testWidgets(
    'picking a program in the search palette opens the read-focused summary, '
    'not the edit builder (#830)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Autumn Ball',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      Future<String?> reimportPicker() async => null;
      await _pump(
        tester,
        repos,
        size: const Size(1200, 900),
        reimportPicker: reimportPicker,
      );

      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('command-result-program-p1')));
      await tester.pumpAndSettle();

      // The palette's dance results open [DanceDetailScreen], a read view; its
      // program results must land on the equivalent read view rather than the
      // builder. Same assertions as the dance-details calling-history test, so
      // both entry points fail the same recognisable way if either regresses.
      expect(
        find.byType(ProgramSummaryScreen),
        findsOneWidget,
        reason: 'a program search result must open the program summary',
      );
      expect(
        find.byType(ProgramEditorScreen),
        findsNothing,
        reason: 'it must not drop the caller straight into the edit builder',
      );
      expect(find.byKey(const ValueKey('open-builder')), findsOneWidget);
      expect(find.text('Edit program'), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-perform')), findsOneWidget);
      expect(find.text('Perform this program'), findsOneWidget);
      expect(
        tester
            .widget<ProgramSummaryScreen>(find.byType(ProgramSummaryScreen))
            .reimportPicker,
        same(reimportPicker),
      );

      await tester.tap(find.byKey(const ValueKey('open-builder')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProgramEditorScreen>(find.byType(ProgramEditorScreen))
            .reimportPicker,
        same(reimportPicker),
      );
    },
  );

  testWidgets(
    'the rail hosts a bottom Help affordance that selects the guide inline',
    (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, size: const Size(1200, 900));

      // The Help/User-guide button lives in the rail on wide layouts.
      final helpButton = find.byKey(const ValueKey('user-guide-button'));
      expect(
        find.descendant(of: find.byType(NavigationRail), matching: helpButton),
        findsOneWidget,
      );

      await tester.tap(helpButton);
      await tester.pumpAndSettle();

      // It selects the offline guide as a destination rendered in the content
      // area — the rail chrome (and its search affordance) stays visible.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        find.byKey(const ValueKey('global-search-button')),
        findsOneWidget,
      );
      expect(find.byType(UserGuideScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('user-guide-title')))
            .data,
        'User guide',
      );
      // Selecting the guide is not a pushed route, so there is no back button.
      expect(find.byType(BackButton), findsNothing);
    },
  );

  testWidgets('the rail Guide button shows a selected state when active', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    // Unselected: the guide icon is the outline variant.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-guide-button')),
        matching: find.byIcon(Icons.help_outline),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('user-guide-button')));
    await tester.pumpAndSettle();

    // Selected: the icon switches to the filled variant (active indicator).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-guide-button')),
        matching: find.byIcon(Icons.help),
      ),
      findsOneWidget,
    );
    // The core rail destinations are deselected while the guide is showing.
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      isNull,
    );
  });

  testWidgets('a short wide window scrolls the rail rather than overflowing, '
      'and keeps Guide reachable', (tester) async {
    final repos = openTestRepositories();
    // Wide enough for the rail, about as tall as a landscape phone — the rail's
    // brand, search, destinations and Guide need more height than this.
    await _pump(tester, repos, size: const Size(1000, 400));

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    final guide = find.byKey(const ValueKey('user-guide-button'));
    expect(guide.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(guide).bottom,
      lessThanOrEqualTo(400),
      reason: 'Guide stays pinned on screen, not clipped below the window',
    );
    await tester.tap(guide);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: guide, matching: find.byIcon(Icons.help)),
      findsOneWidget,
    );
  });

  testWidgets('the narrow layout selects the guide from the bottom bar', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(500, 900));

    // The rail Help button is desktop-only; the guide is a bottom-bar
    // destination on narrow layouts instead.
    expect(find.byKey(const ValueKey('user-guide-button')), findsNothing);

    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();

    // The guide renders inline and the bottom bar stays visible.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(UserGuideScreen), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('user-guide-title'))).data,
      'User guide',
    );
  });

  testWidgets('the narrow Collection has no global search action; its own '
      'search field is its search', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Petronella',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(360, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('collection-search')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.search),
      ),
      findsNothing,
      reason: 'no magnifying glass in the Collection app bar',
    );
    expect(
      find.byKey(const ValueKey('collection-search-field')),
      findsOneWidget,
    );
    // Only one FAB in the bottom-right slot: the screen's "New dance" FAB.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byKey(const ValueKey('new-dance')), findsOneWidget);
  });

  testWidgets('the narrow Programs search lists programs only', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Autumn Reel',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Autumn Ball',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(360, 800));
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byKey(const ValueKey('new-program')), findsOneWidget);
    final search = find.byKey(const ValueKey('programs-search'));
    expect(tester.widget<IconButton>(search).tooltip, 'Search programs');
    // A touch target that meets the >=44px minimum.
    expect(tester.getSize(search).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(search).height, greaterThanOrEqualTo(44));

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
    expect(find.text('Search programs…'), findsOneWidget);
    // Both titles match "Autumn"; only the program is listed.
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-field')),
      'Autumn',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('command-result-program-p1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-result-dance-d1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('command-result-program-p1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramSummaryScreen), findsOneWidget);
  });

  testWidgets('Ctrl-K on a phone still searches dances and programs together', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Autumn Reel',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Autumn Ball',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _pump(tester, repos, size: const Size(360, 800));
    await tester.tap(find.text('Programs').last);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-field')),
      'Autumn',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('command-result-program-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('command-result-dance-d1')),
      findsOneWidget,
    );
  });

  testWidgets('wide layout keeps search in the rail, not the app bar', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    // The rail owns search on desktop; the list app bar must not duplicate it.
    expect(find.byKey(const ValueKey('global-search-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('collection-search')), findsNothing);
  });

  testWidgets('desktop rail search is labeled with a keyboard shortcut hint', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      size: const Size(1200, 900),
      theme: ThemeData(platform: TargetPlatform.windows),
    );

    // Discoverability: the rail search entry is not a bare glyph — it shows a
    // visible "Search" label plus the ⌘K / Ctrl K shortcut hint.
    final button = find.byKey(const ValueKey('global-search-button'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('Search')),
      findsOneWidget,
    );
    final hint = find
        .byKey(const ValueKey('global-search-shortcut-hint'))
        .hitTestable();
    expect(hint, findsOneWidget);
    expect(
      find.descendant(of: hint, matching: find.textContaining('K')),
      findsOneWidget,
    );

    // The labeled affordance still opens the palette (binding preserved).
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
  });

  group('Repertoire (issue #2357)', () {
    List<String> destinations(WidgetTester tester) => [
      for (final d in tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      ))
        d.label,
      if (find.byType(NavigationRail).evaluate().isNotEmpty)
        for (final d
            in tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .destinations)
          (d.label as Text).data!,
    ];

    for (final size in [const Size(500, 900), const Size(1400, 900)]) {
      testWidgets('adds no navigation destination at ${size.width} wide; '
          'More actions offers it only while on', (tester) async {
        final repos = openTestRepositories();
        final show = ValueNotifier<bool>(false);
        addTearDown(show.dispose);
        await _pump(tester, repos, size: size, showRepertoire: show);
        final off = destinations(tester);
        expect(off, isNotEmpty);

        await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('collection-repertoire')),
          findsNothing,
        );
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        show.value = true;
        await tester.pumpAndSettle();
        expect(destinations(tester), off);
        expect(find.text('Repertoire'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('collection-repertoire')),
          findsOneWidget,
        );
      });
    }
  });

  group('Glossary destination (issue #695)', () {
    List<String> barLabels(WidgetTester tester) => [
      for (final d in tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      ))
        d.label,
    ];

    List<String> railLabels(WidgetTester tester) => [
      for (final d
          in tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .destinations)
        (d.label as Text).data!,
    ];

    testWidgets('is absent while Show glossary is off', (tester) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(false);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(500, 900),
        showGlossary: show,
      );

      expect(barLabels(tester), [
        'Collection',
        'Programs',
        'Settings',
        'Guide',
      ]);
      expect(find.byType(GlossaryScreen), findsNothing);
    });

    testWidgets('sits between Programs and Settings on both layouts', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(500, 900),
        showGlossary: show,
      );
      expect(barLabels(tester), [
        'Collection',
        'Programs',
        'Glossary',
        'Settings',
        'Guide',
      ]);

      await _pump(
        tester,
        repos,
        size: const Size(1200, 900),
        showGlossary: show,
      );
      expect(railLabels(tester), [
        'Collection',
        'Programs',
        'Glossary',
        'Settings',
      ]);
    });

    testWidgets('selecting it shows the Glossary, and Settings and the Guide '
        'still open their own pages', (tester) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(500, 900),
        showGlossary: show,
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Glossary'));
      await tester.pumpAndSettle();
      expect(find.byType(GlossaryScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsWidgets);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );

      await tester.tap(find.byKey(const ValueKey('user-guide-destination')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
    });

    testWidgets('the rail selects the Glossary and Settings by name', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(1200, 900),
        showGlossary: show,
      );
      int? railIndex() => tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .selectedIndex;

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Glossary'),
        ),
      );
      await tester.pumpAndSettle();
      expect(railIndex(), 2);
      expect(find.byType(GlossaryScreen), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(railIndex(), 3);
      expect(find.text('Appearance'), findsWidgets);
    });

    testWidgets('turning it on keeps Settings selected', (tester) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(false);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(500, 900),
        showGlossary: show,
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();
      show.value = true;
      await tester.pumpAndSettle();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 5);
      expect(bar.selectedIndex, 3, reason: 'Settings moved to index 3');
      expect(find.text('Appearance'), findsWidgets);
    });

    testWidgets('turning it off while open falls back to the Collection', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await _pump(
        tester,
        repos,
        size: const Size(500, 900),
        showGlossary: show,
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Glossary'));
      await tester.pumpAndSettle();
      show.value = false;
      await tester.pumpAndSettle();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 4);
      expect(bar.selectedIndex, 0);
      expect(find.byType(GlossaryScreen), findsNothing);
    });
  });

  group('one set of breakpoints', () {
    Future<CompendiumRepositories> seeded() async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Autumn Ball',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      return repos;
    }

    // The list pane is a fixed-width column only beside a detail pane.
    bool splitsCollection(WidgetTester tester) =>
        tester.getSize(find.byType(DanceListScreen)).width == 400;
    bool splitsPrograms(WidgetTester tester) =>
        tester.getSize(find.byType(ProgramsListScreen)).width == 400;
    // Narrow Settings lists its sections with a chevron; side by side it
    // shows the General section beside the sidebar.
    bool splitsSettings(WidgetTester tester) {
      final sideBySide = find
          .byKey(const ValueKey('general-sort-ignore-articles'))
          .evaluate()
          .isNotEmpty;
      final chevrons = find
          .descendant(
            of: find.byKey(const ValueKey('settings-nav-general')),
            matching: find.byIcon(Icons.chevron_right),
          )
          .evaluate()
          .isNotEmpty;
      expect(sideBySide, !chevrons, reason: 'exactly one Settings layout');
      return sideBySide;
    }

    Future<void> showSettings(WidgetTester tester) async {
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
    }

    for (final (width, rail, split) in [
      (AppBreakpoints.rail - 1, false, false),
      (AppBreakpoints.rail, true, false),
      (AppBreakpoints.split - 1, true, false),
      (AppBreakpoints.split, true, true),
    ]) {
      testWidgets('at ${width.toInt()} px: rail $rail, split $split', (
        tester,
      ) async {
        final repos = await seeded();
        await _pump(tester, repos, size: Size(width, 900));

        expect(
          find.byType(NavigationRail),
          rail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          rail ? findsNothing : findsOneWidget,
        );
        expect(splitsCollection(tester), split, reason: 'Collection');

        await tester.tap(find.text('Programs').last);
        await tester.pumpAndSettle();
        expect(splitsPrograms(tester), split, reason: 'Programs');

        await showSettings(tester);
        expect(splitsSettings(tester), split, reason: 'Settings');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the bands are the ones named in AppBreakpoints', (
      tester,
    ) async {
      // A change of the numbers is a change of docs/design/ux.md too.
      expect(AppBreakpoints.rail, 720);
      expect(AppBreakpoints.split, 900);
      expect(AppBreakpoints.compact, 600);
    });

    testWidgets('a tablet in portrait, 820 px wide, gets the rail and one '
        'pane', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(820, 1180));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(splitsCollection(tester), isFalse);
    });

    testWidgets('widening across the split width splits each destination, '
        'and narrowing joins it again', (tester) async {
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(899, 900));
      await showSettings(tester);
      expect(splitsSettings(tester), isFalse);

      await tester.binding.setSurfaceSize(const Size(900, 900));
      await tester.pumpAndSettle();
      expect(splitsSettings(tester), isTrue);

      await tester.binding.setSurfaceSize(const Size(899, 900));
      await tester.pumpAndSettle();
      expect(splitsSettings(tester), isFalse);
    });

    testWidgets('large text between the bands lays out without overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repos = await seeded();
      await _pump(tester, repos, size: const Size(720, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      await showSettings(tester);
      await tester.tap(find.byKey(const ValueKey('user-guide-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('short windows (a phone in landscape)', () {
    Future<void> pumpWindow(
      WidgetTester tester,
      Size size, {
      double textScale = 1.0,
    }) async {
      // The window's real size, so MediaQuery sees the height too.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await _pump(tester, repos, size: size);
    }

    for (final (size, short) in [
      (const Size(844, 390), true),
      (const Size(932, 430), true),
      (const Size(390, 844), false),
      (const Size(430, 932), false),
    ]) {
      testWidgets('at ${size.width.toInt()} x ${size.height.toInt()} the New '
          'dance button is ${short ? 'its icon' : 'labelled'}', (tester) async {
        await pumpWindow(tester, size);
        // Landscape is wider than the rail width, so no bottom bar takes
        // height there.
        expect(
          find.byType(NavigationBar),
          size.width >= AppBreakpoints.rail ? findsNothing : findsOneWidget,
        );
        final fab = tester.widget<FloatingActionButton>(
          find.byKey(const ValueKey('new-dance')),
        );
        expect(fab.isExtended, !short);
        // Folded, it keeps its name as a tooltip; labelled, nothing repeats it.
        expect(fab.tooltip, short ? 'New dance' : isNull);
        expect(find.text('New dance'), short ? findsNothing : findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('large text on a landscape phone lays out without overflow', (
      tester,
    ) async {
      await pumpWindow(tester, const Size(844, 390), textScale: 2.0);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('new-dance')),
            )
            .isExtended,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('rail Search and Guide', () {
    for (final (platform, keyboard) in [
      (TargetPlatform.macOS, true),
      (TargetPlatform.windows, true),
      (TargetPlatform.linux, true),
      (TargetPlatform.iOS, false),
      (TargetPlatform.android, false),
    ]) {
      testWidgets('on $platform the shortcut hint shows from the start: '
          '$keyboard', (tester) async {
        final repos = openTestRepositories();
        await _pump(
          tester,
          repos,
          size: const Size(1200, 900),
          theme: ThemeData(platform: platform),
        );
        final hint = find
            .byKey(const ValueKey('global-search-shortcut-hint'))
            .hitTestable();
        expect(hint, keyboard ? findsOneWidget : findsNothing);
        final tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: find.byKey(const ValueKey('global-search-button')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(
          tooltip.message,
          keyboard ? startsWith('Search (') : 'Search',
          reason: 'the tooltip names a shortcut only when there is a key',
        );
      });
    }

    testWidgets('on an iPad the hint appears once a key only a hardware '
        'keyboard sends is pressed', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        size: const Size(1200, 900),
        theme: ThemeData(platform: TargetPlatform.iOS),
      );
      final hint = find
          .byKey(const ValueKey('global-search-shortcut-hint'))
          .hitTestable();
      expect(hint, findsNothing);

      // Keys that reach the app without a keyboard: an on-screen keyboard's
      // Backspace, Enter, arrows and digits, Android's volume and Back keys.
      for (final key in [
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.audioVolumeUp,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(hint, findsNothing, reason: '$key');
      }
      // The key simulator has no scan code for Android's Back key, so it goes
      // straight to the keyboard state the presence check listens to.
      const back = PhysicalKeyboardKey(0x000c0224);
      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: back,
          logicalKey: LogicalKeyboardKey.goBack,
          timeStamp: Duration.zero,
        ),
      );
      HardwareKeyboard.instance.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: back,
          logicalKey: LogicalKeyboardKey.goBack,
          timeStamp: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(hint, findsNothing, reason: 'goBack');

      final collection = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Collection'),
      );
      final before = tester.getTopLeft(collection);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(hint, findsOneWidget);
      // Its room was kept, so nothing below it moves.
      expect(tester.getTopLeft(collection), before);
      expect(
        find.descendant(of: hint, matching: find.text('⌘K')),
        findsOneWidget,
      );
    });

    for (final (name, theme) in [
      ('default', AppTheme.dark),
      ('High contrast', AppTheme.highContrast),
      // A rail theme of its own, so the test tells "reads the rail theme"
      // from "happens to match the fallback".
      (
        'custom rail theme',
        AppTheme.dark.copyWith(
          navigationRailTheme: const NavigationRailThemeData(
            indicatorColor: Color(0xFF7A3E9D),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
        ),
      ),
    ]) {
      testWidgets('Search and Guide use the destinations\' pill ($name)', (
        tester,
      ) async {
        final repos = openTestRepositories();
        await _pump(tester, repos, size: const Size(1200, 900), theme: theme);
        final railTheme = theme.navigationRailTheme;

        Material pill(String key) => tester.widget<Material>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byKey(const ValueKey('rail-action-indicator')),
          ),
        );

        // No circle anywhere in the two tiles.
        for (final key in ['global-search-button', 'user-guide-button']) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).shape == BoxShape.circle,
              ),
            ),
            findsNothing,
            reason: key,
          );
          expect(pill(key).shape, railTheme.indicatorShape, reason: key);
        }
        // Unselected: no fill, like an unselected destination.
        expect(pill('global-search-button').color, Colors.transparent);
        expect(pill('user-guide-button').color, Colors.transparent);

        await tester.tap(find.byKey(const ValueKey('user-guide-button')));
        await tester.pumpAndSettle();
        // Selected: the rail's own indicator colour, as a selected destination.
        expect(pill('user-guide-button').color, railTheme.indicatorColor);
        // Search is an action, never selected.
        expect(pill('global-search-button').color, Colors.transparent);
      });
    }

    testWidgets('a tap on the label, not only the pill, opens search', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, size: const Size(1200, 900));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('global-search-button')),
          matching: find.text('Search'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
    });

    testWidgets('keyboard alone reaches Search and Guide and activates them', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, size: const Size(1200, 900));

      // Tabs until keyboard focus is inside the tile with [key], within a
      // bounded number of presses.
      Future<bool> tabTo(String key) async {
        for (var i = 0; i < 40; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focused = FocusManager.instance.primaryFocus?.context;
          final tile = find.byKey(ValueKey(key)).evaluate().single;
          if (focused is Element && _isAncestor(tile, focused)) return true;
        }
        return false;
      }

      expect(await tabTo('global-search-button'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);

      expect(await tabTo('user-guide-button'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(UserGuideScreen).hitTestable(), findsOneWidget);
    });
  });

  // UX4-6b: the rail's Search and Guide tiles were bare InkWells, so a screen
  // reader got a label with no "button" role.
  testWidgets('the rail Search and Guide tiles are announced as buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repos = openTestRepositories();
    await _pump(tester, repos, size: const Size(1200, 900));

    for (final key in ['global-search-button', 'user-guide-button']) {
      expect(
        tester.getSemantics(find.byKey(ValueKey(key))),
        isSemantics(isButton: true),
        reason: key,
      );
    }
    // Guide is a place and says whether it is selected; Search is an action
    // and has no selected state to announce.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('user-guide-button'))),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('global-search-button'))),
      isSemantics(isButton: true, hasSelectedState: false),
    );
    handle.dispose();
  });
}

/// Whether [ancestor] is above [element] in the element tree.
bool _isAncestor(Element ancestor, Element element) {
  var found = false;
  element.visitAncestorElements((e) {
    if (identical(e, ancestor)) found = true;
    return !found;
  });
  return found;
}
