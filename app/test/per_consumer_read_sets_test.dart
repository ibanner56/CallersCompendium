import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/screens/dance_detail/calling_history_section.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_app/src/search/dance_editor_reference_data.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Issue #944: a venue renamed elsewhere is re-rendered by every surface that
/// displays a venue label — and issue #768: it is the *consumer's* read set,
/// not the query's, that decides which tables are watched.
///
/// ## The property under test, and why it is one property four times
///
/// Every test renames a venue **through the repository, from outside the
/// widget**, with no refresh scope mounted, and asserts the rendered label
/// changes with no interaction. Before this change the row's `venueId` still
/// resolved after a rename, so nothing anywhere told these screens to look
/// again: PR 4 made the venue *manager* reactive, which is a different screen
/// from the four that display what it edits.
///
/// The four surfaces are not four copies of one fix. Each reaches the venue
/// catalogue by a different route — a stream mapper, a shared `CollectionData`
/// snapshot, a once-only `_load`, and a cache — and only the first is fixed by
/// adding a table to a read set. That is the argument this file is evidence
/// for.
///
/// ## Why a rename and not a create or a delete
///
/// A create or a delete changes which ids resolve, so a consumer that re-reads
/// only when it meets an id it cannot resolve would recover on its own and the
/// test would pass against the unfixed code. A rename leaves the id resolvable
/// and only the *value* behind it different, so it is the narrowest write that
/// discriminates. `calling_history_section`'s cache is the clearest case: it
/// re-reads exactly on unresolvable ids, so a create-based test could never
/// have caught it.
///
/// ## Mutation targets
///
/// * drop `venues` from any per-consumer read set (`includeVenues: false`,
///   `watchVenues: false`) — the surface stops re-rendering.
/// * revert `_venuesDirty` in `calling_history_section.dart` — the stream still
///   fires and the section still re-runs, and the label stays stale anyway.
///   That mutation is the reason the cache case is stated separately: it
///   survives a correct read set.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  Program program({
    String id = 'p1',
    String title = 'Barn Dance',
    String? venue,
    String? venueId,
    List<ProgramSlot> slots = const [],
  }) => Program(
    id: id,
    title: title,
    venue: venue,
    venueId: venueId,
    status: ProgramStatus.draft,
    slots: slots,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> pump(
    WidgetTester tester,
    CompendiumRepositories repos,
    Widget home, {
    Size size = const Size(1000, 1800),
    bool enrichedVenues = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final venueMode = ValueNotifier<bool>(enrichedVenues);
    addTearDown(venueMode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        // Deliberately no refresh scope of any kind: the only channel that can
        // carry the rename to these widgets is the database itself.
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: VenueEntityModeScope(notifier: venueMode, child: child!),
          ),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Renames `v1` and lets the stream deliver. Written as one helper so every
  /// test performs the identical write and any difference in outcome is a
  /// property of the surface rather than of the write.
  Future<void> renameVenue(
    WidgetTester tester,
    CompendiumRepositories repos,
    String name,
  ) async {
    await repos.venues.upsert(Venue(id: 'v1', name: name));
    await tester.pumpAndSettle();
  }

  group('surfaces that display a venue label', () {
    testWidgets('programs list re-renders a venue renamed elsewhere', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(
        program(venue: 'ignored free text', venueId: 'v1'),
      );

      await pump(
        tester,
        repos,
        const ProgramsListScreen(),
        size: const Size(600, 1200),
      );
      expect(find.textContaining('Grange Hall'), findsOneWidget);

      await renameVenue(tester, repos, 'The Grange');

      expect(find.textContaining('The Grange'), findsOneWidget);
      expect(find.textContaining('Grange Hall'), findsNothing);
    });

    testWidgets('program summary re-renders a venue renamed elsewhere', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(
        program(venue: 'ignored free text', venueId: 'v1'),
      );

      await pump(tester, repos, const ProgramSummaryScreen(programId: 'p1'));
      expect(find.textContaining('Grange Hall'), findsOneWidget);

      await renameVenue(tester, repos, 'The Grange');

      expect(find.textContaining('The Grange'), findsOneWidget);
      expect(find.textContaining('Grange Hall'), findsNothing);
    });

    testWidgets('program editor re-renders a venue renamed elsewhere', (
      tester,
    ) async {
      // The editor is the surface where opting into `venues` is necessary and
      // NOT sufficient: its `_load` runs once, so the linked venue has to be
      // re-resolved from the subscription. Without that the picker would wake
      // and the label beside it would not — a partial refresh, which reads as
      // correct at a glance.
      //
      // ## Why this pumps SIMPLE mode, and why the first version was worthless
      //
      // Written first in enriched mode, it passed with `watchVenues: false` —
      // a survived mutation. Enriched mode renders `VenuePicker`, which PR 4
      // gave its own `venues.watchAll()` subscription, so the name updated
      // through a seam this PR does not touch and the assertion never reached
      // `_linkedVenue` at all.
      //
      // Simple mode renders the read-only linked hint from `_linkedVenue`
      // directly and mounts no picker, so the only path to a fresh name is the
      // one under test. The finder is scoped to the hint's key for the same
      // reason: an unscoped `textContaining` is how the first version passed.
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(program(venueId: 'v1'));

      await pump(
        tester,
        repos,
        const ProgramEditorScreen(programId: 'p1'),
        enrichedVenues: false,
      );
      final hint = find.byKey(const ValueKey('program-venue-linked-hint'));
      expect(hint, findsOneWidget);
      expect(
        find.descendant(of: hint, matching: find.textContaining('Grange Hall')),
        findsOneWidget,
      );

      await renameVenue(tester, repos, 'The Grange');

      expect(
        find.descendant(of: hint, matching: find.textContaining('The Grange')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hint, matching: find.textContaining('Grange Hall')),
        findsNothing,
      );
    });

    testWidgets('calling history re-renders a venue renamed elsewhere', (
      tester,
    ) async {
      // The cache case. A read set alone does not fix this one: the section
      // re-runs on the emit and would still serve the old name from
      // `_venuesById`, because the record's id is still resolvable.
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(id: 'd1', title: 'Petronella', createdAt: now, updatedAt: now),
      );
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(
        program(
          venue: 'ignored free text',
          venueId: 'v1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      await pump(
        tester,
        repos,
        Scaffold(
          body: SingleChildScrollView(
            child: CallingHistorySection(
              repositories: repos,
              danceId: 'd1',
              performedOnly: false,
              trackAllCallers: true,
              onOpenProgram: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Grange Hall'), findsOneWidget);

      await renameVenue(tester, repos, 'The Grange');

      expect(find.textContaining('The Grange'), findsOneWidget);
      expect(find.textContaining('Grange Hall'), findsNothing);
    });
  });

  group('a failed catalogue read is retried', () {
    testWidgets('a rename survives a transient venues read failure', (
      tester,
    ) async {
      // Prompted by a review finding on #966 (the dirty flag being cleared
      // before the read that consumes it). **That finding does not hold** —
      // clearing eagerly is behaviourally identical, because the subscription
      // re-arms the flag on every emit — and this test does NOT discriminate
      // the two orderings. Stated plainly because a test named for a hazard it
      // cannot detect is worse than no test.
      //
      // What it does guard is the property the review made visible and nothing
      // else covered: a transient failure of the venue catalogue read is
      // **recovered from**, rather than leaving the section permanently stale.
      // Mutating out the dirty-flag retry entirely (`hasUnresolved` alone)
      // turns this red.
      final failer = _FailOneVenuesSelect();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(failer),
          closeOnTearDown: false,
        ),
        contraTaxonomy,
      );
      addTearDown(repos.db.close);

      await repos.dances.create(
        Dance(id: 'd1', title: 'Petronella', createdAt: now, updatedAt: now),
      );
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await repos.programs.create(
        program(
          venue: 'ignored free text',
          venueId: 'v1',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );

      await pump(
        tester,
        repos,
        Scaffold(
          body: SingleChildScrollView(
            child: CallingHistorySection(
              repositories: repos,
              danceId: 'd1',
              performedOnly: false,
              trackAllCallers: true,
              onOpenProgram: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Grange Hall'), findsOneWidget);

      // The rename's own emit re-reads the catalogue, and that read fails.
      failer.arm();
      await renameVenue(tester, repos, 'The Grange');
      expect(
        failer.fired,
        isTrue,
        reason: 'the transient failure must actually have been injected',
      );

      // Any later emit — here, a second unrelated program write — must retry.
      // With the flag cleared eagerly it never would, because a rename leaves
      // every id resolvable.
      await repos.programs.create(
        program(id: 'p2', title: 'Second', venue: 'free text only'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('The Grange'), findsOneWidget);
      expect(find.textContaining('Grange Hall'), findsNothing);
    });
  });

  group('the read set stays the consumer\'s', () {
    // A plain `test`, not `testWidgets`: the claim is about which tables a
    // stream watches, which is a repository property with no widget in it. It
    // also needs real timers — under `pumpAndSettle`'s fake clock the drift
    // emit does not arrive, and the first version of this test read that as
    // "the stream did not fire", which is the same observation the property
    // predicts. A test that cannot tell those two apart proves nothing.
    test('a venue write does not disturb a consumer that renders none', () async {
      // The mirror of the four surface tests, and the reason `includeVenues` is
      // a parameter rather than a widening of the shared set: the Collection
      // list renders no venue, so waking it on every venue write would be issue
      // #340's failure — over-firing — bought with the fix for this one.
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));

      var plain = 0;
      final plainSub = repos.watchCollectionSources().listen((_) => plain++);
      addTearDown(plainSub.cancel);

      var opted = 0;
      final optedSub = repos
          .watchCollectionSources(includeVenues: true)
          .listen((_) => opted++);
      addTearDown(optedSub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final plainBefore = plain;
      final optedBefore = opted;

      await repos.venues.upsert(Venue(id: 'v1', name: 'The Grange'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Both halves matter. Without the second, the first would pass against a
      // stream that never fires at all — which is the failure this whole issue
      // is about, asserted as if it were the fix.
      expect(
        plain,
        plainBefore,
        reason: 'a venue rename must not wake a consumer that renders no venue',
      );
      expect(
        opted,
        greaterThan(optedBefore),
        reason: 'the same write must wake the consumer that does render one',
      );
    });

    /// Subscribes to both sentinels — in the order given — writes a program
    /// slot, and reports how many times each woke.
    ///
    /// The order is a parameter because the defect this guards is
    /// order-dependent: drift caches query streams by `(sql, variables)` and
    /// ignores `readsFrom`, so two sentinels whose SQL text is equal are ONE
    /// stream and whichever subscribed first decides the read set for both. A
    /// single-order test passes against that bug half the time, which is worse
    /// than not testing it — the half that passes looks like proof.
    Future<({int dance, int collection})> wakesForProgramWrite({
      required bool danceFirst,
    }) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Alpha',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      var dance = 0;
      var collection = 0;
      late StreamSubscription<void> first;
      late StreamSubscription<void> second;
      if (danceFirst) {
        first = repos.watchDanceSources().listen((_) => dance++);
        second = repos.watchCollectionSources().listen((_) => collection++);
      } else {
        first = repos.watchCollectionSources().listen((_) => collection++);
        second = repos.watchDanceSources().listen((_) => dance++);
      }
      addTearDown(first.cancel);
      addTearDown(second.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final danceBefore = dance;
      final collectionBefore = collection;

      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Autumn Ball',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      return (
        dance: dance - danceBefore,
        collection: collection - collectionBefore,
      );
    }

    for (final danceFirst in [true, false]) {
      final label = danceFirst ? 'dance sentinel first' : 'collection first';
      test(
        'a program write wakes only the collection sentinel ($label)',
        () async {
          final wakes = await wakesForProgramWrite(danceFirst: danceFirst);

          expect(
            wakes.dance,
            0,
            reason:
                'a dance record carries nothing program-derived, so the dance '
                'sentinel must not wake for a program write',
          );
          // Paired, and load-bearing beyond non-vacuity: if the two sentinels
          // collide into one stream, this is the half that shows the write was
          // dispatched at all, so a zero above means "declined" rather than
          // "nothing happened".
          expect(
            wakes.collection,
            greaterThan(0),
            reason: 'the collection sentinel watches programs and must wake',
          );
        },
      );
    }
  });

  group('DanceEditorReferenceData and DanceDetailData share one drift stream '
      '(issue #768, PR 9)', () {
    // Both types watch `CompendiumRepositories.watchDanceSources()` directly —
    // deliberately, since PR 9's editor read set is entry-for-entry identical
    // to that sentinel's (see `dance_editor_reference_data.dart`). Drift keys
    // its query stream cache by `(sql, variables)` and ignores `readsFrom`, so
    // two subscribers reading the same SQL text are, correctly, one stream
    // here — there is no second sentinel to collide. What must still be
    // guarded is the property a narrower sentinel would need to preserve: each
    // subscriber wakes for a write to the shared set and neither wakes for a
    // program write, in EITHER subscription order. A single order passes
    // deterministically against half of a future collision (the `readsFrom`
    // hazard `wakesForProgramWrite` above already guards for the two
    // dance/collection sentinels) — see that helper's doc for why order is a
    // parameter and not a default.
    Future<({int editor, int detail})> wakesFor({
      required bool editorFirst,
      required Future<void> Function(CompendiumRepositories repos) write,
    }) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(id: 'd1', title: 'Alpha', createdAt: now, updatedAt: now),
      );

      var editor = 0;
      var detail = 0;
      late StreamSubscription<void> first;
      late StreamSubscription<void> second;
      if (editorFirst) {
        first = DanceEditorReferenceData.watch(repos).listen((_) => editor++);
        second = DanceDetailData.watch(repos, 'd1').listen((_) => detail++);
      } else {
        first = DanceDetailData.watch(repos, 'd1').listen((_) => detail++);
        second = DanceEditorReferenceData.watch(repos).listen((_) => editor++);
      }
      addTearDown(first.cancel);
      addTearDown(second.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final editorBefore = editor;
      final detailBefore = detail;

      await write(repos);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      return (editor: editor - editorBefore, detail: detail - detailBefore);
    }

    for (final editorFirst in [true, false]) {
      final label = editorFirst
          ? 'editor sentinel first'
          : 'detail sentinel first';

      test('a choreographer write wakes both ($label)', () async {
        final wakes = await wakesFor(
          editorFirst: editorFirst,
          write: (repos) async {
            // ignore: unused_result
            await repos.choreographers.upsert(
              Choreographer(id: 'c1', name: 'Gene Hubert'),
            );
          },
        );

        expect(
          wakes.editor,
          greaterThan(0),
          reason: 'the editor watches choreographers',
        );
        expect(
          wakes.detail,
          greaterThan(0),
          reason: 'the detail screen watches choreographers too',
        );
      });

      test('a program write wakes neither ($label)', () async {
        final wakes = await wakesFor(
          editorFirst: editorFirst,
          write: (repos) async {
            await repos.programs.create(
              Program(
                id: 'p1',
                title: 'Autumn Ball',
                status: ProgramStatus.draft,
                slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
                createdAt: now,
                updatedAt: now,
              ),
            );
          },
        );

        expect(
          wakes.editor,
          0,
          reason:
              'the editor renders nothing program-derived, so a program '
              'write must not wake it',
        );
        expect(
          wakes.detail,
          0,
          reason:
              'the detail screen watches the same sentinel and must decline '
              'the same write',
        );
      });
    }
  });
}

/// Fails exactly one `venues` select once armed, then delegates normally.
///
/// Models a transient read failure (a teardown race, a locked database) rather
/// than a permanent one: the point is that the *recovery* happens, which a
/// permanently-failing store could not distinguish from never retrying.
class _FailOneVenuesSelect extends drift.QueryInterceptor {
  bool _armed = false;
  bool _fired = false;

  /// Whether the injected failure actually happened.
  bool get fired => _fired;

  void arm() => _armed = true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    // drift quotes table names: `SELECT * FROM "venues" WHERE ...`. The first
    // version of this matched `FROM venues` unquoted, never fired, and the
    // test passed against BOTH the fix and its mutant — a green that measured
    // nothing. Hence `fired`, asserted below: an injection that silently fails
    // to inject is indistinguishable from behaviour that survived it.
    if (_armed && !_fired && statement.contains('FROM "venues"')) {
      _fired = true;
      throw Exception('injected transient venues read failure');
    }
    return executor.runSelect(statement, args);
  }
}
