import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/weekends_and_series_scope.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/combined_programs_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/screens/settings/experimental_section.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart' show testFigure;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show LayoutCallback;

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Weekends and series (#2349): selecting programs on the Programs list and
/// the combined view they open.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime.utc(2026, 1, 1);

  Dance dance(String id, String title, String moveId) => Dance(
    id: id,
    title: title,
    figures: [
      testFigure(move: moveId, params: {'beats': 16}),
    ],
    createdAt: now,
    updatedAt: now,
  );

  Program program(
    String id,
    String title, {
    DateTime? date,
    List<String> danceIds = const [],
    Set<int> alternates = const {},
    bool archived = false,
  }) => Program(
    id: id,
    title: title,
    eventDate: date,
    createdAt: now,
    updatedAt: now,
    archivedAt: archived ? now : null,
    slots: [
      for (var i = 0; i < danceIds.length; i++)
        ProgramSlot(
          id: '$id-$i',
          position: i,
          danceId: danceIds[i],
          isAlt: alternates.contains(i),
        ),
    ],
  );

  /// Saturday and Sunday share "Chorus Jig"; Sunday holds "Butterfly" only
  /// as an alternate, Saturday as a planned dance. Friday is archived.
  Future<CompendiumRepositories> seed() async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('jig', 'Chorus Jig', 'balance'));
    await repos.dances.create(dance('fly', 'Butterfly', 'do_si_do'));
    await repos.dances.create(dance('rose', 'Baby Rose', 'balance'));
    await repos.programs.create(
      program(
        'sun',
        'Sunday afternoon',
        date: DateTime.utc(2026, 8, 2),
        danceIds: const ['jig', 'rose', 'fly'],
        alternates: const {2},
      ),
    );
    await repos.programs.create(
      program(
        'sat',
        'Saturday evening',
        date: DateTime.utc(2026, 8, 1),
        danceIds: const ['fly', 'jig'],
      ),
    );
    await repos.programs.create(
      program(
        'fri',
        'Friday dance',
        date: DateTime.utc(2026, 7, 31),
        danceIds: const ['rose'],
        archived: true,
      ),
    );
    return repos;
  }

  Future<ValueNotifier<bool>> pumpList(
    WidgetTester tester,
    CompendiumRepositories repos, {
    bool enabled = true,
    ValueNotifier<bool>? active,
    bool phone = false,
  }) async {
    final notifier = ValueNotifier(enabled);
    addTearDown(notifier.dispose);
    final isActive = active ?? ValueNotifier(true);
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) {
          final scoped = RepositoriesScope(
            repositories: repos,
            child: WeekendsAndSeriesScope(notifier: notifier, child: child!),
          );
          // The phone layout's app bar: a search action, and the import
          // items in the ⋮ menu.
          return phone
              ? AppShellSearchScope(searchPrograms: () async {}, child: scoped)
              : scoped;
        },
        home: ValueListenableBuilder<bool>(
          valueListenable: isActive,
          builder: (context, value, _) => ProgramsListScreen(isActive: value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  final more = find.byKey(const ValueKey('programs-more-actions'));
  final selectItem = find.byKey(const ValueKey('programs-select-programs'));
  final combined = find.byKey(const ValueKey('programs-combined-view'));
  Finder checkbox(String id) => find.byKey(ValueKey('program-select-$id'));

  bool combinedEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(combined).onPressed != null;

  Future<void> startSelecting(WidgetTester tester) async {
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(selectItem);
    await tester.pumpAndSettle();
  }

  group('the Programs list', () {
    testWidgets('offers no Select programs while the setting is off (the '
        'default)', (tester) async {
      final repos = await seed();
      await pumpList(tester, repos, enabled: false);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(selectItem, findsNothing);
      // Positive control: the menu is open.
      expect(
        find.byKey(const ValueKey('programs-recently-deleted')),
        findsOneWidget,
      );
      expect(checkbox('sat'), findsNothing);
    });

    testWidgets('Combined view needs two programs', (tester) async {
      final repos = await seed();
      await pumpList(tester, repos);
      await startSelecting(tester);
      expect(combined, findsOneWidget);
      expect(combinedEnabled(tester), isFalse);
      expect(find.byKey(const ValueKey('new-program')), findsNothing);

      await tester.tap(checkbox('sat'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(combinedEnabled(tester), isFalse);

      await tester.tap(find.text('Sunday afternoon'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(combinedEnabled(tester), isTrue);

      await tester.tap(combined);
      await tester.pumpAndSettle();
      final screen = tester.widget<CombinedProgramsScreen>(
        find.byType(CombinedProgramsScreen),
      );
      expect(screen.programIds, {'sat', 'sun'});
    });

    testWidgets('Show archived still works while selecting, and a checked '
        'program it hides stays checked and is counted', (tester) async {
      final repos = await seed();
      await pumpList(tester, repos);
      await startSelecting(tester);
      expect(checkbox('fri'), findsNothing);

      Future<void> toggleArchived() async {
        await tester.tap(find.byKey(const ValueKey('programs-selection-more')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('programs-toggle-archived')),
        );
        await tester.pumpAndSettle();
      }

      await toggleArchived();
      expect(checkbox('fri'), findsOneWidget);
      await tester.tap(checkbox('fri'));
      await tester.tap(checkbox('sat'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('programs-selection-not-shown')),
        findsNothing,
      );

      await toggleArchived();
      expect(checkbox('fri'), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
      expect(
        find.text(' · 2 selected (1 not shown)'),
        findsOneWidget,
        reason: 'the hidden program is still selected, and said to be',
      );
      expect(combinedEnabled(tester), isTrue);

      await tester.tap(
        find.byKey(const ValueKey('programs-deselect-not-shown')),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('the phone layout\'s menu offers Select programs too, only '
        'while the setting is on', (tester) async {
      final repos = await seed();
      final setting = await pumpList(tester, repos, phone: true);
      expect(find.byKey(const ValueKey('programs-search')), findsOneWidget);
      await startSelecting(tester);
      expect(combined, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('programs-selection-exit')));
      await tester.pumpAndSettle();
      setting.value = false;
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(selectItem, findsNothing);
      expect(
        find.byKey(const ValueKey('programs-recently-deleted')),
        findsOneWidget,
      );
    });

    testWidgets('with every program archived and hidden, checked programs are '
        'still counted as not shown, and New program waits', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(program('a', 'Alpha', archived: true));
      await repos.programs.create(program('b', 'Beta', archived: true));
      await pumpList(tester, repos);
      await startSelecting(tester);
      await tester.tap(find.byKey(const ValueKey('empty-show-archived')));
      await tester.pumpAndSettle();
      await tester.tap(checkbox('a'));
      await tester.tap(checkbox('b'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-selection-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-toggle-archived')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('all-archived-state')), findsOneWidget);
      expect(find.text(' · 2 selected (2 not shown)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('programs-deselect-not-shown')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('empty-new-program')), findsNothing);
    });

    testWidgets('a checked program that is deleted is dropped, not counted as '
        'not shown', (tester) async {
      final repos = await seed();
      await pumpList(tester, repos);
      await startSelecting(tester);
      await tester.tap(checkbox('sat'));
      await tester.tap(checkbox('sun'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await repos.programs.softDelete('sat', at: now);
      await tester.pumpAndSettle();
      expect(checkbox('sat'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('programs-selection-not-shown')),
        findsNothing,
      );
      expect(combinedEnabled(tester), isFalse);
    });

    testWidgets('turning the setting off ends the selection', (tester) async {
      final repos = await seed();
      final setting = await pumpList(tester, repos);
      await startSelecting(tester);
      await tester.tap(checkbox('sat'));
      await tester.pumpAndSettle();
      expect(combined, findsOneWidget);

      setting.value = false;
      await tester.pumpAndSettle();
      expect(combined, findsNothing);
      expect(checkbox('sat'), findsNothing);

      setting.value = true;
      await tester.pumpAndSettle();
      expect(combined, findsNothing, reason: 'not resumed');
    });

    testWidgets('leaving the Programs destination forgets the selection', (
      tester,
    ) async {
      final repos = await seed();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await pumpList(tester, repos, active: active);
      await startSelecting(tester);
      await tester.tap(checkbox('sat'));
      await tester.pumpAndSettle();

      active.value = false;
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      expect(combined, findsNothing);
      await startSelecting(tester);
      expect(find.text('0 selected'), findsOneWidget);
    });
  });

  group('the combined view', () {
    List<String> blockHeadings(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('program-matrix-block-heading')),
          matching: find.byType(Text),
        ),
      ))
        text.data!,
    ];

    Future<void> pumpCombined(
      WidgetTester tester,
      CompendiumRepositories repos,
      Set<String> ids, {
      Size size = const Size(1200, 1200),
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) =>
              RepositoriesScope(repositories: repos, child: child!),
          home: CombinedProgramsScreen(programIds: ids),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('labels a block per program, in event-date order', (
      tester,
    ) async {
      final repos = await seed();
      await pumpCombined(tester, repos, {'sun', 'sat'});
      final headings = blockHeadings(tester);
      expect(headings, hasLength(2));
      expect(headings[0], startsWith('Saturday evening · '));
      expect(headings[1], startsWith('Sunday afternoon · '));
      // The single-program section badge is not shown.
      expect(find.text('1st'), findsNothing);
    });

    testWidgets('at phone width each dance names its program, with no '
        'section badge', (tester) async {
      final repos = await seed();
      await pumpCombined(tester, repos, {
        'sun',
        'sat',
      }, size: const Size(400, 900));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('program-matrix-block-heading')),
        findsNothing,
        reason: 'the compact layout groups by move, not by row',
      );
      expect(find.textContaining('Saturday evening · '), findsWidgets);
      expect(find.textContaining('Sunday afternoon · '), findsWidgets);
      expect(find.text('1st'), findsNothing);
    });

    testWidgets('the alternates toggle hides and shows alternate rows', (
      tester,
    ) async {
      final repos = await seed();
      await pumpCombined(tester, repos, {'sun', 'sat'});
      final toggle = find.byKey(
        const ValueKey('combined-matrix-toggle-alternates'),
      );
      final butterfly = find.descendant(
        of: find.byKey(const ValueKey('combined-matrix-table')),
        matching: find.text('Butterfly'),
      );
      // Saturday plans Butterfly; Sunday holds it as an alternate.
      expect(butterfly, findsNWidgets(2));
      expect(find.byTooltip('Hide alternate rows'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(butterfly, findsOneWidget, reason: 'Sunday\'s alternate hidden');
      expect(find.byTooltip('Show alternate rows'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(butterfly, findsNWidgets(2), reason: 'shown again');
    });

    testWidgets('Repeats lists dances in two programs, with where, and marks '
        'one that is only an alternate somewhere', (tester) async {
      final repos = await seed();
      await pumpCombined(tester, repos, {'sun', 'sat'});
      await tester.tap(find.byKey(const ValueKey('combined-tab-repeats')));
      await tester.pumpAndSettle();

      expect(
        find.text('2 dances appear in more than one program'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('combined-repeat-jig')), findsOneWidget);
      expect(find.byKey(const ValueKey('combined-repeat-fly')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('combined-repeat-rose')),
        findsNothing,
        reason: 'Baby Rose is in Friday too, but Friday is not selected',
      );
      expect(
        find.byKey(const ValueKey('combined-repeat-alternate-fly')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('combined-repeat-alternate-jig')),
        findsNothing,
      );
      expect(
        find.textContaining('Sunday afternoon · ', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining(': alternate for dance 2'),
        findsOneWidget,
        reason: 'Butterfly stands in for Sunday\'s second dance',
      );
    });

    testWidgets('Export or print matrix as PDF hands over a PDF of the '
        'combined matrix', (tester) async {
      final repos = await seed();
      String? jobName;
      LayoutCallback? captured;
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) =>
              RepositoriesScope(repositories: repos, child: child!),
          home: CombinedProgramsScreen(
            programIds: const {'sat', 'sun'},
            pdfLayouter: ({required name, required onLayout}) async {
              jobName = name;
              captured = onLayout;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('combined-matrix-export-pdf')),
      );
      await tester.pumpAndSettle();
      expect(jobName, 'Combined_matrix');
      expect(captured, isNotNull);
      final bytes = await tester.runAsync(
        () async => captured!(PdfPageFormat.a4),
      );
      expect(bytes, isNotEmpty);
      expect(find.byType(SnackBar), findsNothing, reason: 'no failure');
    });

    testWidgets('a program deleted while it is open drops out', (tester) async {
      final repos = await seed();
      await pumpCombined(tester, repos, {'sun', 'sat'});
      await repos.programs.softDelete('sat', at: now);
      await tester.pumpAndSettle();
      final labels = blockHeadings(tester);
      expect(labels, [startsWith('Sunday afternoon')]);
    });
  });

  testWidgets('Settings ▸ Experimental has the Weekends and series switch, '
      'off by default, and saves it', (tester) async {
    final repos = openTestRepositories();
    final notifier = ValueNotifier(false);
    addTearDown(notifier.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: WeekendsAndSeriesScope(
            notifier: notifier,
            child: const Scaffold(body: WeekendsAndSeriesSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekends and series'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(
      const ValueKey('experimental-weekends-and-series'),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(notifier.value, isTrue);
    expect(await repos.settings.get(kWeekendsAndSeriesEnabledKey), isTrue);
  });
}
