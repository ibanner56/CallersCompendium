import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/programs_refresh_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';

import 'support/l10n_harness.dart';

/// Regression tests for issue #768: a write made *elsewhere* left every other
/// live view showing pre-write data until the app restarted.
///
/// Each test drives the real screen widgets (never a helper in isolation) and
/// asserts on rendered output, because the defect was precisely that the data
/// was correct in the database and stale on screen.
///
/// Several tests mount two screens side by side under one pair of refresh
/// scopes. That is not a layout the app ships, but the screens and the scopes
/// are the real ones, and it reproduces the condition that matters: two views
/// alive at once, one of them mutating data the other renders — exactly the
/// `IndexedStack`-kept-alive tab and the split pane the issue describes.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 1, 1);

  Dance dance({required String id, required String title, DanceLevel? level}) =>
      Dance(
        id: id,
        title: title,
        authorIds: const [],
        tagIds: const [],
        form: DanceForm.contra,
        formation: const Formation(FormationShape.dupleImproper),
        status: DanceStatus.active,
        level: level,
        figures: const [],
        customFields: const [],
        hook: '',
        createdAt: now,
        updatedAt: now,
      );

  Program program({
    required String id,
    required String title,
    List<ProgramSlot> slots = const [],
  }) => Program(
    id: id,
    title: title,
    status: ProgramStatus.draft,
    slots: slots,
    createdAt: now,
    updatedAt: now,
  );

  /// Repositories whose settings reads are counted, so a test can assert how
  /// many times a screen reloaded. [DanceDetailScreen.\_load] reads
  /// [kDefaultDanceDetailRenderingKey] exactly once per load, which makes that
  /// key an exact reload counter for the detail screen.
  ({CompendiumRepositories repos, _CountingSettings settings}) countingRepos() {
    final db = CompendiumDatabase(NativeDatabase.memory());
    final settings = _CountingSettings(db);
    return (
      repos: CompendiumRepositories(db, contraTaxonomy, settings: settings),
      settings: settings,
    );
  }

  /// Mounts [child] under the real refresh scopes plus the scopes the
  /// Collection/Programs screens read. Returns the two revision notifiers so a
  /// test can bump them directly where it is asserting the *subscriber* rather
  /// than a mutation site.
  Future<({ValueNotifier<int> collection, ValueNotifier<int> programs})> pump(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget child, {
    Size surfaceSize = const Size(1400, 3000),
    bool requirePerformedForHistory = false,
    bool mountRefreshScopes = true,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final collection = ValueNotifier<int>(0);
    addTearDown(collection.dispose);
    final programs = ValueNotifier<int>(0);
    addTearDown(programs.dispose);
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
    addTearDown(theme.dispose);
    final requirePerformed = ValueNotifier<bool>(requirePerformedForHistory);
    addTearDown(requirePerformed.dispose);
    final customThemes = CustomThemesController(repos.settings);
    await customThemes.load();
    addTearDown(customThemes.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, inner) => RepositoriesScope(
          repositories: repos,
          child: AppThemeScope(
            notifier: theme,
            child: CustomThemesScope(
              controller: customThemes,
              child: ActiveDialectScope(
                notifier: dialect,
                child: RequirePerformedForHistoryScope(
                  notifier: requirePerformed,
                  child: mountRefreshScopes
                      ? CollectionRefreshScope(
                          revision: collection,
                          child: ProgramsRefreshScope(
                            revision: programs,
                            child: inner!,
                          ),
                        )
                      : inner!,
                ),
              ),
            ),
          ),
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
    return (collection: collection, programs: programs);
  }

  /// Two real screens alive at once, each in its own [ScaffoldMessenger] the
  /// way both shells mount their panes.
  Widget panes(Widget left, Widget right) => Scaffold(
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: ScaffoldMessenger(child: left)),
        Expanded(child: ScaffoldMessenger(child: right)),
      ],
    ),
  );

  Finder callingHistoryRows() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('calling-history-') &&
        (w.key! as ValueKey<String>).value != 'calling-history-empty',
  );

  testWidgets(
    'gap 1: adding this dance to a program from the detail screen updates its '
    'calling history without leaving the screen',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await repos.programs.create(program(id: 'p1', title: 'Friday Night'));
      await pump(tester, repos, const DanceDetailScreen(danceId: 'd1'));

      // Fixture check: the history starts empty, so the assertion below is not
      // satisfied by pre-existing data.
      expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);

      await tester.tap(find.byKey(const ValueKey('add-dance-to-program')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-pick-p1')));
      await tester.pumpAndSettle();

      expect(callingHistoryRows(), findsOne);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsNothing);
    },
  );

  testWidgets(
    'gap 2: adding a dance to a program from a Collection row updates that '
    "row's called-count badge",
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await repos.programs.create(program(id: 'p1', title: 'Friday Night'));
      await pump(tester, repos, const DanceListScreen());

      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dance-action-add-to-program')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-pick-p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('called-count-d1')), findsOne);
    },
  );

  testWidgets(
    'gap 3: mark-all-performed in a program summary updates a live Collection '
    "row's called-count badge",
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Friday Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);
      await pump(
        tester,
        repos,
        panes(
          const DanceListScreen(),
          ProgramSummaryPane(
            programId: 'p1',
            refreshTrigger: refresh,
            onOpenBuilder: () {},
            onDeleted: () {},
            onNavigateTo: (_) {},
          ),
        ),
        // With mark-performed required, the badge counts only performed slots,
        // so it is absent until the summary marks them — isolating this test to
        // the mark-performed write rather than the slot's mere existence.
        requirePerformedForHistory: true,
      );

      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mark-all-performed')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('called-count-d1')), findsOne);
    },
  );

  testWidgets(
    "gap 4: deleting a program updates a live dance detail's calling history",
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Friday Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await pump(
        tester,
        repos,
        panes(
          const ProgramsListScreen(),
          const DanceDetailScreen(danceId: 'd1'),
        ),
      );

      expect(callingHistoryRows(), findsOne);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      expect(callingHistoryRows(), findsNothing);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);
    },
  );

  testWidgets(
    'gap 5: a batch tag change in the wide layout updates the detail pane '
    'beside it, which is keyed on the selection and never re-created',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await repos.tags.upsert(Tag(id: 't1', name: 'Gentle'));
      // CollectionShell splits at 900 and AppShell puts an 80 px rail beside
      // it, so a real split needs >= 980; 1400 is comfortably past that. No
      // iPhone can reach it, which is why this gap is iPad/desktop only.
      await pump(
        tester,
        repos,
        const CollectionShell(),
        surfaceSize: const Size(1400, 3000),
      );

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      // Fixture check: the detail pane really is showing this dance, so the
      // level assertion below is about a refresh and not about an empty pane.
      expect(find.byKey(const ValueKey('detail-d1')), findsOne);
      // Scoped to the pane on purpose: the list row renders a tag chip with the
      // same text, and an unscoped finder passes whether or not the pane ever
      // reloaded — the first version of this test used one, read as rigorous,
      // and stayed green against the unfixed code.
      Finder paneTag() => find.descendant(
        of: find.byKey(const ValueKey('detail-d1')),
        matching: find.text('Gentle'),
      );
      expect(paneTag(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('batch-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-checkbox-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
      await tester.pumpAndSettle();

      // The pane is still the same widget (same key) — it reloaded rather than
      // being re-created, which is what the fix does and what the key prevents.
      expect(find.byKey(const ValueKey('detail-d1')), findsOne);
      expect(paneTag(), findsOne);
    },
  );

  testWidgets(
    "gaps 6 and 7: editing a dance's level updates a program summary that is "
    'already mounted and rendering it',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(
        dance(id: 'd1', title: 'Alpha', level: DanceLevel.beginner),
      );
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Friday Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);
      final revisions = await pump(
        tester,
        repos,
        ProgramSummaryPane(
          programId: 'p1',
          refreshTrigger: refresh,
          onOpenBuilder: () {},
          onDeleted: () {},
          onNavigateTo: (_) {},
        ),
      );

      // Fixture check: the pane renders the level, so a change to it is visible.
      expect(find.textContaining('Beginner'), findsWidgets);

      // The dance is edited from a screen this pane pushed (its slot rows open
      // DanceDetailScreen, which opens the editor); the editor bumps the
      // collection revision on save. Bumping it directly here keeps the test on
      // the subscriber under test rather than on the editor's own coverage.
      await repos.dances.update(
        (await repos.dances.getById('d1'))!.copyWith(
          level: DanceLevel.intermediate,
          updatedAt: now.add(const Duration(days: 1)),
        ),
      );
      revisions.collection.value++;
      await tester.pumpAndSettle();

      expect(find.textContaining('Intermediate'), findsWidgets);
      expect(find.textContaining('Beginner'), findsNothing);
    },
  );

  testWidgets(
    'a program created by an import appears in a live Programs list without a '
    'relaunch (the shared-bundle asymmetry)',
    (tester) async {
      final repos = openTestRepos();
      final revisions = await pump(tester, repos, const ProgramsListScreen());

      expect(find.text('Imported Programme'), findsNothing);

      // Stands in for the import commit, which writes through the archive
      // importer and then broadcasts.
      await repos.programs.create(
        program(id: 'p9', title: 'Imported Programme'),
      );
      revisions.programs.value++;
      await tester.pumpAndSettle();

      expect(find.text('Imported Programme'), findsOne);
    },
  );

  testWidgets(
    'the un-awaited-push class: returning from a dance opened through a '
    'related-dance link refreshes the row that opened it',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd2', title: 'Bravo'));
      await repos.dances.create(
        dance(id: 'd1', title: 'Alpha').copyWith(
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'd2',
            ),
          ],
        ),
      );
      // Mounted WITHOUT the refresh scopes on purpose. Scoped, the subscription
      // would refresh this screen and the test would pass whether or not the
      // push is awaited — the vacuous case. Unscoped, the only thing that can
      // refresh the row is the await plus fallback reload, which is the change
      // under test.
      await pump(
        tester,
        repos,
        const DanceDetailScreen(danceId: 'd1'),
        mountRefreshScopes: false,
      );

      // Fixture check: the link row really resolves and renders d2's title, so
      // the assertion below is about a refresh rather than a missing row.
      expect(find.byKey(const ValueKey('link-row-l1')), findsOne);
      expect(find.text('Bravo'), findsOne);

      await tester.tap(find.byKey(const ValueKey('link-row-l1')));
      await tester.pumpAndSettle();

      // Renamed while the pushed screen is on top, standing in for an edit made
      // there (the editor is what a user would use; the write is the same).
      await repos.dances.update(
        (await repos.dances.getById('d2'))!.copyWith(
          title: 'Bravo Renamed',
          updatedAt: now.add(const Duration(days: 1)),
        ),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Bravo Renamed'), findsOne);
      expect(find.text('Bravo'), findsNothing);
    },
  );

  testWidgets(
    'issue #340 guard: a write that broadcasts on both channels reloads a '
    'both-channels subscriber exactly once',
    (tester) async {
      final counted = countingRepos();
      await counted.repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      final revisions = await pump(
        tester,
        counted.repos,
        const DanceDetailScreen(danceId: 'd1'),
      );
      final loadsAfterFirstBuild = counted.settings.reads(
        kDefaultDanceDetailRenderingKey,
      );
      expect(loadsAfterFirstBuild, 1);

      // A shared-bundle commit writes dances and programs, so it bumps both
      // channels back to back in one synchronous block.
      revisions.collection.value++;
      revisions.programs.value++;
      await tester.pumpAndSettle();

      expect(
        counted.settings.reads(kDefaultDanceDetailRenderingKey),
        loadsAfterFirstBuild + 1,
      );
    },
  );

  testWidgets(
    'issue #340 guard: a batch across many dances reloads the detail pane once, '
    'not once per dance',
    (tester) async {
      final counted = countingRepos();
      for (var i = 0; i < 5; i++) {
        await counted.repos.dances.create(dance(id: 'd$i', title: 'Dance $i'));
      }
      // Batch tagging writes one row at a time in a loop, unlike batch level
      // (a single `setLevelForMany`), so it is the case where a broadcast could
      // plausibly be written per item.
      await counted.repos.tags.upsert(Tag(id: 't1', name: 'Gentle'));
      await pump(
        tester,
        counted.repos,
        const CollectionShell(),
        surfaceSize: const Size(1400, 3000),
      );

      await tester.tap(find.text('Dance 0').first);
      await tester.pumpAndSettle();
      final before = counted.settings.reads(kDefaultDanceDetailRenderingKey);
      expect(before, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('batch-select')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(ValueKey('batch-checkbox-d$i')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('batch-add-tags')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-tag-option-t1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-tag-confirm')));
      await tester.pumpAndSettle();

      // Five dances written, one broadcast, one reload.
      expect(
        counted.settings.reads(kDefaultDanceDetailRenderingKey),
        before + 1,
      );
    },
  );
}

/// In-memory repositories for these tests.
CompendiumRepositories openTestRepos() => CompendiumRepositories(
  CompendiumDatabase(NativeDatabase.memory()),
  contraTaxonomy,
);

/// Counts settings reads by key, so a test can count screen reloads without
/// reaching inside the widget under test.
class _CountingSettings extends SettingsRepository {
  _CountingSettings(super.db);

  final Map<String, int> _reads = {};

  int reads(String key) => _reads[key] ?? 0;

  @override
  Future<Object?> get(String key) {
    _reads.update(key, (v) => v + 1, ifAbsent: () => 1);
    return super.get(key);
  }
}
