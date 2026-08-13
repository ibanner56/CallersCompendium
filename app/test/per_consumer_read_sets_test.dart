import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/venue_entity_mode_scope.dart';
import 'package:compendium_app/src/screens/dance_detail/calling_history_section.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';

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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
  });
}
