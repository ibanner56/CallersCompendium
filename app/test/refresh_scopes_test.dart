import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/require_performed_for_history_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

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
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  /// Repositories whose detail-record loads are counted, so a test can assert
  /// how many times the detail screen re-read its data.
  ///
  /// ## Why this counts a repository call and not a settings read
  ///
  /// It used to count reads of [kDefaultDanceDetailRenderingKey], on the
  /// grounds that the detail screen's load read that key exactly once per load.
  /// That stopped being true when the screen moved to a stream (issue #768):
  /// the rendering preference is a per-mount seed now, not part of the record,
  /// so the key is read **once per mount** no matter how many times the record
  /// reloads.
  ///
  /// Two of the three ceilings below broke loudly when that happened. The third
  /// — "a program-side write must not reload the detail screen" — kept passing,
  /// because a counter pinned at 1 satisfies "did not increase" for free. That
  /// is the failure worth designing against: breakage announces itself and
  /// vacuity does not.
  ///
  /// [DanceDetailData.load] calls `dances.listIdsAndTitles()` exactly once, to
  /// build its cross-reference linker, and nothing else on these screens calls
  /// it — so it is an exact per-load marker. Counted by **overriding the
  /// method**, not by matching SQL text in a `QueryInterceptor`: a substring
  /// counter reads zero both when the load never ran and when the query stopped
  /// looking like the string, and it would also count the Collection snapshot's
  /// own loads in the split-pane test below, where both screens are mounted. An
  /// override is compile-checked and belongs to one caller.
  ({CompendiumRepositories repos, _CountingDances dances}) countingRepos() {
    final db = openWidgetTestDatabase();
    addTearDown(db.close);
    final dances = _CountingDances(db, contraTaxonomy);
    return (
      repos: CompendiumRepositories(db, contraTaxonomy, dances: dances),
      dances: dances,
    );
  }

  /// Mounts [child] under the real refresh scopes plus the scopes the
  /// Collection/Programs screens read. Returns the collection revision notifier
  /// so a test can bump it directly where it is asserting the *subscriber*
  /// rather than a mutation site.
  ///
  /// There is only one notifier to return now: `ProgramsRefreshScope` was
  /// retired once every program view became stream-driven (issue #768).
  Future<ValueNotifier<int>> pump(
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
                          child: inner!,
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
    return collection;
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
    "a program-side write with NO refresh scope mounted updates a row's "
    'called-count badge',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await pump(
        tester,
        repos,
        const DanceListScreen(),
        mountRefreshScopes: false,
      );
      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);

      // Written from nowhere in particular, with no channel to announce it —
      // the shape of every gap in issue #768. The badge is derived from
      // `program_slots`, which this list now watches (issue #768).
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Friday Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('called-count-d1')), findsOne);

      // ...and the reverse: a programs-only write (soft delete) takes it away.
      await repos.programs.softDelete(
        'p1',
        at: now.add(const Duration(days: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);
    },
  );

  testWidgets(
    'issue #340: a program-side write updates the badge WITHOUT re-running the '
    'search query',
    (tester) async {
      // The Collection list re-derives its rows from the loaded snapshot, so a
      // write that can only move the per-dance tallies must not re-run the
      // (expensive) filter/FTS query behind `search()`. Converting the screen
      // to a stream makes that easy to lose: every emit is a fresh snapshot,
      // and the naive response is to re-search on each one.
      final counter = _SearchCounter();
      final db = openWidgetTestDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await pump(tester, repos, const DanceListScreen());
      final searchesAfterOpen = counter.count;
      expect(searchesAfterOpen, greaterThan(0), reason: 'the list did search');
      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);

      // Program-side write: changes the tallies, cannot change which dances
      // match the query or their order under the default (title) sort.
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Friday Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('called-count-d1')),
        findsOne,
        reason: 'the badge must still update',
      );
      expect(
        counter.count,
        searchesAfterOpen,
        reason:
            'a tallies-only change must not re-run the search query; '
            'the rows are re-derived from the snapshot instead',
      );
    },
  );

  testWidgets(
    'renaming a choreographer re-sorts the list when sorted by author',
    (tester) async {
      // The author sort orders by choreographer NAME, not by the ids stored on
      // the dance — so a rename reorders the results while every dance row is
      // byte-identical. The in-memory re-derivation this screen does for
      // cheap updates would otherwise refresh the visible author labels and
      // leave the ORDER stale, which looks like a sorting bug rather than a
      // refresh one.
      final repos = openTestRepos();
      // ignore: unused_result
      await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Adams'));
      // ignore: unused_result
      await repos.choreographers.upsert(Choreographer(id: 'c2', name: 'Baker'));
      await repos.dances.create(
        dance(id: 'd1', title: 'Alpha').copyWith(authorIds: const ['c1']),
      );
      await repos.dances.create(
        dance(id: 'd2', title: 'Beta').copyWith(authorIds: const ['c2']),
      );
      await pump(tester, repos, const DanceListScreen());

      // Switch to the author sort: Adams (Alpha) before Baker (Beta).
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Author').last);
      await tester.pumpAndSettle();

      List<String> order() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t == 'Alpha' || t == 'Beta')
          .toList();
      expect(order(), ['Alpha', 'Beta'], reason: 'Adams sorts before Baker');

      // Rename Adams so it now sorts AFTER Baker. No dance row changes.
      // ignore: unused_result
      await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Zulu'));
      await tester.pumpAndSettle();

      expect(
        order(),
        ['Beta', 'Alpha'],
        reason:
            'the rename reorders the author sort; a labels-only refresh '
            'would leave the old order',
      );
    },
  );

  testWidgets(
    'issue #340: a write does not make the program summary re-subscribe and '
    'reload the snapshot twice',
    (tester) async {
      // This pane reloads wholesale on every emit — the program, its dances
      // and its venue all have to be re-fetched. The trap is that the reload
      // re-enters the subscription helper: cancelling and re-opening the
      // stream re-runs `CollectionData.load`, so one write costs an EXTRA
      // full snapshot load on top of the one the stream already did, and
      // hands back a freshly-armed coalescer each time.
      //
      // `custom_field_defs` is read by `CollectionData.load` and by nothing
      // else in this flow, so counting it counts snapshot loads.
      //
      // On the bound: `CollectionData.watch` legitimately loads once per
      // emit, and one `create` produces more than one emit here (the write
      // touches several tables and the coalescer emits on both edges). The
      // ceiling below is therefore calibrated to this fixture rather than
      // derived, and its MEANING is "at most one load per emit" — the
      // re-subscribing version costs 5 against the same fixture, so the
      // assertion discriminates the defect rather than the emit count. If
      // drift's notification behaviour changes, re-measure rather than
      // widen: a number that only ever goes up stops testing anything.
      final counter = _SnapshotLoadCounter();
      final db = openWidgetTestDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
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
        ProgramSummaryPane(
          programId: 'p1',
          onOpenBuilder: () {},
          onDeleted: () {},
          onNavigateTo: (_) {},
        ),
      );
      final loadsAfterOpen = counter.count;
      expect(loadsAfterOpen, greaterThan(0), reason: 'the pane did load');

      await repos.dances.create(dance(id: 'd2', title: 'Beta'));
      await tester.pumpAndSettle();

      expect(
        counter.count - loadsAfterOpen,
        lessThanOrEqualTo(3),
        reason:
            'the pane must reuse the snapshot the stream just delivered; '
            're-subscribing re-runs the whole snapshot load for a value it '
            'already has',
      );
    },
  );

  // REMOVED: 'a re-entrant load during a caller-filter change never presents
  // the previous filter's snapshot'.
  //
  // The gate it guarded is still in `_watchCollectionData` and still correct.
  // The test is gone because this PR made the state it needed unreachable, and
  // a guard that cannot fail is worse than an absent one — it reads as coverage.
  //
  // What changed: the pane's `refreshTrigger` was removed with the rest of the
  // Programs refresh plumbing, so the coalescer is now `_load`'s only caller.
  // Re-entering `_load` is therefore no longer something a test can request; it
  // is a race inside the two DB reads that precede `_watchCollectionData`.
  //
  // A replacement was written and then withdrawn. It parked `getById` to hold
  // one load open while another completed the filter change, which is
  // deterministic — but the clause under test (`_pendingFirst == null`) only
  // changes the outcome while the replacement subscription is STILL PENDING,
  // and holding it pending as well leaves nothing to settle the pane at all.
  // The mutation confirmed it rather than the reasoning: with
  // `_pendingFirst == null` deleted, that test still passed.
  //
  // Deliberately not replaced with a proxy assertion. Nothing this pane renders
  // depends on the caller filter — it draws `choreographersById` and a
  // `canPerform` gate, and hands the filtered fields to `PerformProgramScreen`
  // — so any on-screen assertion would be testing something other than the
  // gate. See `program_editor_screen`, where `_resubscribePicker` makes the
  // same replace path reachable and is covered there.

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
      // ignore: unused_result
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
      final collectionRevision = await pump(
        tester,
        repos,
        ProgramSummaryPane(
          programId: 'p1',
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
      collectionRevision.value++;
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
      await pump(tester, repos, const ProgramsListScreen());

      expect(find.text('Imported Programme'), findsNothing);

      // Stands in for the import commit. It used to write and then broadcast
      // on `ProgramsRefreshScope`; that scope has been retired, so the write
      // is now the whole of the notification and this asserts strictly more
      // than it did — the bump could previously have carried a list that the
      // stream would not have refreshed on its own.
      await repos.programs.create(
        program(id: 'p9', title: 'Imported Programme'),
      );
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
    'deleting a dance opened through a related-dance link refreshes the row '
    'that opened it — the delete path broadcasts nothing',
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
      // Mounted WITH both scopes — production-like, and the point of the test.
      // `_delete` soft-deletes and pops `true` without bumping either channel
      // (the list screen reloads from the popped result instead), so the
      // subscription cannot rescue this one the way it does an edit.
      await pump(tester, repos, const DanceDetailScreen(danceId: 'd1'));

      // Fixture check: the link resolves to a real dance, so "(missing dance)"
      // below is a change of state rather than the starting condition.
      expect(find.text('Bravo'), findsOne);
      expect(find.text('(missing dance)'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('link-row-l1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-dance')).last);
      await tester.pumpAndSettle();

      expect(find.text('(missing dance)'), findsOne);
      expect(find.text('Bravo'), findsNothing);
    },
  );

  testWidgets(
    'undoing a program delete from the summary refreshes program views, even '
    'though the undo outlives the pane that offered it',
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
      var paneVisible = true;
      late void Function(void Function()) rebuildHost;

      await pump(
        tester,
        repos,
        StatefulBuilder(
          builder: (context, setHostState) {
            rebuildHost = setHostState;
            return panes(
              const DanceListScreen(),
              // Unmounted when the program is deleted, mirroring both real
              // layouts: the wide shell swaps in its empty pane and the narrow
              // route pops. That unmount is what makes a `mounted`-guarded
              // broadcast in the undo callback dead code.
              paneVisible
                  ? ProgramSummaryPane(
                      programId: 'p1',
                      onOpenBuilder: () {},
                      onDeleted: () => rebuildHost(() => paneVisible = false),
                      onNavigateTo: (_) {},
                    )
                  // A Scaffold, like the real empty pane: the messenger needs
                  // one for the undo snackbar to survive the swap.
                  : const Scaffold(body: SizedBox.shrink()),
            );
          },
        ),
      );

      // Fixture check: the badge is present before the delete, so its return
      // after undo is a real change of state.
      expect(find.byKey(const ValueKey('called-count-d1')), findsOne);

      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('called-count-d1')), findsNothing);

      // The pane that armed this undo is gone by now.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('called-count-d1')), findsOne);
    },
  );

  testWidgets(
    'undoing a dance delete refreshes other views, on a route that passes no '
    'onRestored — which is every route but the Collection row tap',
    (tester) async {
      final repos = openTestRepos();
      await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      final listRefresh = ValueNotifier<int>(0);
      addTearDown(listRefresh.dispose);

      // Models the five live routes: a caller that pushes DanceDetailScreen
      // with no onRestored, and handles only the popped `deleted` result — the
      // shape of the search palette, _openDance, the duplicate landing, the
      // post-import auto-open and the program slot row.
      await pump(
        tester,
        repos,
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: DanceListScreen()),
              Builder(
                builder: (context) => ElevatedButton(
                  key: const ValueKey('open-detail'),
                  onPressed: () async {
                    final deleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => const DanceDetailScreen(danceId: 'd1'),
                      ),
                    );
                    if (deleted == true) listRefresh.value++;
                  },
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Alpha'), findsOne);

      await tester.tap(find.byKey(const ValueKey('open-detail')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-dance')).last);
      await tester.pumpAndSettle();

      // Fixture check: the delete really did reach the list, so the assertion
      // below is a restore rather than a row that never left.
      expect(find.text('Alpha'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOne);
    },
  );

  group('the scopes a screen depends on', () {
    // Issue #768: a screen that only ever *broadcasts* on a refresh scope must
    // resolve it with `notifierOf`, not `maybeOf`. `maybeOf` registers a
    // rebuild dependency, so every bump made anywhere rebuilt every bumper —
    // over-firing (issue #340) bought with no benefit, and disclaimed by the
    // very comments sitting above those calls.
    //
    // Asserted by counting builds of a real screen. `DanceListScreen` is the
    // interesting one: it is stream-driven and bumps, so it is a pure bumper.
    // Tested on the scope itself rather than through a screen, deliberately.
    //
    // Two screen-level attempts failed and BOTH passed against the mutant: one
    // counted dirty elements after `pumpAndSettle` (zero by construction), the
    // other read `element.dirty` straight after the bump — but `InheritedNotifier`
    // calls `notifyClients` during its OWN build, not synchronously on notify,
    // so the flag is not set yet at that moment. A rebuild of a large screen is
    // simply not observable from outside it.
    //
    // The claim is a property of the resolver, so a probe that counts its own
    // builds observes it exactly, and the paired assertion below makes the
    // negative non-vacuous: the same probe under `maybeOf` DOES rebuild.
    testWidgets('notifierOf registers no dependency; maybeOf does', (
      tester,
    ) async {
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      var withNotifierOf = 0;
      var withMaybeOf = 0;

      await tester.pumpWidget(
        CollectionRefreshScope(
          revision: revision,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    CollectionRefreshScope.notifierOf(context);
                    withNotifierOf++;
                    return const SizedBox.shrink();
                  },
                ),
                Builder(
                  builder: (context) {
                    CollectionRefreshScope.maybeOf(context);
                    withMaybeOf++;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(withNotifierOf, 1);
      expect(withMaybeOf, 1);

      revision.value++;
      await tester.pump();

      expect(
        withNotifierOf,
        1,
        reason: 'notifierOf must not register a rebuild dependency',
      );
      expect(
        withMaybeOf,
        2,
        reason: 'maybeOf must — without this the negative above is vacuous',
      );
    });

    // A source-level ratchet, and named as one: the behavioural test above
    // proves what the two resolvers DO, but nothing stops a future edit calling
    // the depending one from a widget that only broadcasts — which is the
    // regression this PR fixes, in four places at once.
    //
    // Exactly one widget may register a dependency, and it is the one that
    // genuinely listens.
    test('only the screen that listens resolves the scope with maybeOf', () {
      // A `Set` of separator-normalised paths: `listSync` order is not
      // specified and `file.path` is `\`-separated on Windows, either of which
      // would fail this ratchet on correct code. A ratchet that fails for
      // reasons unrelated to its claim gets edited reflexively, and then it is
      // inert while still reading green.
      // Resolved from either cwd. `flutter test` runs from the package root,
      // so 'lib' is the normal case; a runner invoked from the repo root would
      // otherwise throw a FileSystemException whose message says nothing about
      // what this test was trying to do.
      final lib = [
        Directory('lib'),
        Directory('app/lib'),
      ].firstWhere((d) => d.existsSync(), orElse: () => Directory('lib'));
      expect(
        lib.existsSync(),
        isTrue,
        reason:
            'ratchet could not locate app/lib from ${Directory.current.path}',
      );

      final offenders = <String>{};
      var scanned = 0;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        // Relative to the resolved directory, so the recorded path does not
        // depend on which candidate matched. Recording `file.path` verbatim
        // made the expectation below cwd-dependent — the repo-root fallback
        // would have produced `app/lib/...` and failed on correct code, which
        // is a defect this ratchet acquired while being made cwd-independent.
        final path = file.path
            .replaceAll(r'\', '/')
            .substring(lib.path.replaceAll(r'\', '/').length + 1);
        if (!path.endsWith('.dart')) continue;
        if (path.endsWith('collection_refresh_scope.dart')) continue;
        scanned++;
        for (final line in file.readAsLinesSync()) {
          if (line.contains('CollectionRefreshScope.maybeOf(')) {
            // The FILE, not the line: pinning a line number would make this
            // ratchet fail on any unrelated edit above the call — the same
            // reflexive-edit failure as above, from a different direction.
            offenders.add(path);
          }
        }
      }
      // Assert the scan actually happened. Today an empty scan fails anyway,
      // because the expectation below is non-empty — but the moment
      // DanceDetailScreen is converted and that set becomes `{}`, a scan that
      // found nothing would pass for the wrong reason. This is the same rule
      // the rest of this PR's tests follow: assert the precondition, not just
      // the conclusion.
      expect(scanned, greaterThan(50), reason: 'scanned only $scanned files');

      expect(
        offenders,
        <String>{},
        reason:
            'a widget that only broadcasts must use notifierOf; maybeOf '
            'registers a rebuild dependency and wakes it on every bump. '
            'Scope is app/lib deliberately: maybeOf still has one caller, the '
            'test above, which is what keeps the negative checkable',
      );
    });

    // The inverse of the test this replaces, which asserted that the detail
    // screen still reloaded on a bump — true while its record came from a
    // one-shot load, and the reason the channel could not be retired.
    //
    // Both halves are needed and neither is decoration. On its own the negative
    // is satisfied by a screen that has stopped updating altogether, which is
    // the staleness this whole issue is about — so the positive is what
    // distinguishes "no longer listens to the channel" from "no longer works".
    testWidgets(
      'the detail screen no longer reloads on a bump, and DOES reload on the '
      'write itself',
      (tester) async {
        final repos = openTestRepos();
        await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
        final collectionRevision = await pump(
          tester,
          repos,
          const DanceDetailScreen(danceId: 'd1'),
        );
        expect(find.text('Alpha'), findsWidgets);

        // A bump with nothing written behind it. Nothing should change,
        // because there is nothing to change to — but if the screen still
        // listened, this is where it would re-read.
        collectionRevision.value++;
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsWidgets);

        // Now the write, with NO bump after it. This is the half that used to
        // be the precondition for the opposite claim: the same edit that could
        // not reach this screen on its own now does.
        final stored = await repos.dances.getById('d1');
        await repos.dances.update(
          stored!.copyWith(title: 'Renamed', updatedAt: DateTime.utc(2026, 2)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Renamed'),
          findsWidgets,
          reason: 'the write alone must reach this screen, with no broadcast',
        );
      },
    );
  });

  testWidgets(
    'issue #340 guard: an external dance write reloads the detail screen '
    'exactly once',
    (tester) async {
      final counted = countingRepos();
      await counted.repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await pump(tester, counted.repos, const DanceDetailScreen(danceId: 'd1'));
      expect(counted.dances.loads, 1, reason: 'the initial load');

      // The ceiling this has always asserted: one user action reloads this
      // screen once, not twice. What drives it has changed with the screen —
      // it began as a coalescing guard over two refresh channels, became a
      // single-bump guard when the programs channel was retired, and is now a
      // database write, because the screen reads from a stream and a bump
      // reaches it no longer (issue #768).
      //
      // One write is one commit, so the coalescer's leading edge emits it
      // immediately and nothing trails it. Two loads here would mean the screen
      // had acquired a second path to the same data.
      await counted.repos.dances.update(
        dance(id: 'd1', title: 'Alpha').copyWith(title: 'Renamed'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Renamed'), findsWidgets);
      expect(counted.dances.loads, 2);
    },
  );

  testWidgets(
    'issue #340 guard: a program-side write updates the calling history '
    'WITHOUT reloading the whole detail screen',
    (tester) async {
      final counted = countingRepos();
      await counted.repos.dances.create(dance(id: 'd1', title: 'Alpha'));
      await pump(tester, counted.repos, const DanceDetailScreen(danceId: 'd1'));
      final loadsAfterFirstBuild = counted.dances.loads;
      expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);

      // The whole point of converting this section: the write reaches the one
      // widget that renders it, rather than re-running the ~15 queries behind
      // every other section to refresh a list the dance itself cannot change.
      await counted.repos.programs.create(
        program(
          id: 'p1',
          title: 'Autumn Ball',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(callingHistoryRows(), findsOne);
      expect(
        counted.dances.loads,
        loadsAfterFirstBuild,
        reason:
            'a program write must not reload the detail screen: nothing else '
            'on it is program-derived',
      );

      // The negative above is "the counter did not move", which a dead counter
      // satisfies for free — and this assertion used to be exactly that. It
      // counted a settings read that the screen made once per load, until the
      // screen stopped reading settings per load and pinned it at 1; the
      // ceiling then held for a reason that had nothing to do with program
      // writes. So show the counter CAN move, on the same screen, in the same
      // test, with the only difference being which table was written.
      await counted.repos.dances.update(
        dance(id: 'd1', title: 'Alpha').copyWith(title: 'Renamed'),
      );
      await tester.pumpAndSettle();

      expect(
        counted.dances.loads,
        loadsAfterFirstBuild + 1,
        reason:
            'a DANCE write must reload it — without this the negative above '
            'passes against a counter that never moves',
      );
    },
  );

  testWidgets(
    'issue #340 guard: a batch across many dances reloads the detail pane a '
    'bounded number of times, not once per dance',
    (tester) async {
      final counted = countingRepos();
      for (var i = 0; i < 5; i++) {
        await counted.repos.dances.create(dance(id: 'd$i', title: 'Dance $i'));
      }
      // Batch tagging writes one row at a time in a loop, unlike batch level
      // (a single `setLevelForMany`), so it is the case where a reload could
      // plausibly happen per item.
      // ignore: unused_result
      await counted.repos.tags.upsert(Tag(id: 't1', name: 'Gentle'));
      await pump(
        tester,
        counted.repos,
        const CollectionShell(),
        surfaceSize: const Size(1400, 3000),
      );

      await tester.tap(find.text('Dance 0').first);
      await tester.pumpAndSettle();
      final before = counted.dances.loads;
      expect(before, greaterThan(0), reason: 'the pane loaded at all');

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

      // Five dances written in five transactions, so five wakes reach the
      // stream. The bound is a *rate*, not a total: the coalescing window emits
      // on the leading edge and flushes at most once per window thereafter, so
      // a burst this size settles in two. Asserting exactly one would be
      // asserting the trailing flush away, and the trailing flush is what
      // guarantees the last write is not dropped.
      //
      // The claim being defended is the gap between 2 and 5 — one reload per
      // dance written, for a pane showing one of them.
      expect(
        counted.dances.loads - before,
        lessThanOrEqualTo(2),
        reason:
            'a 5-dance batch must not reload this pane once per dance; '
            'saw ${counted.dances.loads - before}',
      );
    },
  );
}

/// In-memory repositories for these tests.
CompendiumRepositories openTestRepos() =>
    CompendiumRepositories(openWidgetTestDatabase(), contraTaxonomy);

/// Counts detail-record loads, so a test can count screen reloads without
/// reaching inside the widget under test.
///
/// [DanceDetailData.load] calls [listIdsAndTitles] exactly once per load, and
/// nothing else mounted in these tests calls it at all — so [loads] is an exact
/// count of "how many times the detail record was re-read". See `countingRepos`
/// for why this is an override rather than a SQL-matching interceptor.
class _CountingDances extends DanceRepository {
  _CountingDances(super.db, super.taxonomy);

  int loads = 0;

  @override
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) {
    loads++;
    return super.listIdsAndTitles(includeDeleted: includeDeleted);
  }
}

/// Counts reads of `custom_field_defs`, which only [CollectionData.load]
/// issues in the program-summary flow — so the count is "how many times the
/// whole snapshot was loaded".
///
/// **This counter does not observe the search.** It is a marker for the
/// snapshot load, and the substring it matches (`custom_field_defs`) is what
/// makes it one: any query touching that table would be counted, so adding an
/// unrelated read of it to this flow would silently inflate every ceiling
/// asserted against this counter.
class _SnapshotLoadCounter extends drift.QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('custom_field_defs')) count++;
    return executor.runSelect(statement, args);
  }
}

/// Counts executions of the Collection's compiled filter query.
///
/// `FilterCompiler` emits `SELECT id FROM dances …` (`filter_compiler.dart:92`),
/// which nothing else in this screen's load issues — the snapshot reads dances
/// through drift's own builder — so it is a precise marker for "the search ran".
///
/// **That precision rests on a SQL substring, which no compiler checks.** If
/// `FilterCompiler` is refactored to emit a different prefix — aliasing the
/// table, selecting another column, or adding a `DISTINCT` — this counter
/// silently drops to zero and every `expect(counter.count, …)` below it
/// becomes an assertion about nothing rather than a failure. A ceiling of the
/// form "the search ran at most N times" is satisfied trivially by a search
/// that is no longer observed. If you change that query, change this string
/// and confirm the counts move.
class _SearchCounter extends drift.QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('SELECT id FROM dances')) count++;
    return executor.runSelect(statement, args);
  }
}
