import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_app/src/screens/dance_detail/calling_history_section.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Tests for the app's first reactive read (issue #768).
///
/// The load-bearing one is "a program-side write with NO refresh scope mounted
/// updates the section": before this conversion the calling history was correct
/// only when a mutation site remembered to bump `ProgramsRefreshScope`, and
/// seven places did not. These tests mount the section with no scope at all, so
/// the only thing that can make them pass is the database telling the widget.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 1, 1);

  Dance dance(String id, String title) =>
      Dance(id: id, title: title, createdAt: now, updatedAt: now);

  Program program({
    required String id,
    required String title,
    List<ProgramSlot> slots = const [],
    String? venue,
    String? venueId,
    DateTime? updatedAt,
  }) => Program(
    id: id,
    title: title,
    venue: venue,
    venueId: venueId,
    slots: slots,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  Future<void> pumpSection(
    WidgetTester tester,
    CompendiumRepositories repos, {
    bool performedOnly = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        // Deliberately no CollectionRefreshScope / ProgramsRefreshScope: the
        // section must stay correct without any broadcast channel at all.
        home: Scaffold(
          body: SingleChildScrollView(
            child: CallingHistorySection(
              repositories: repos,
              danceId: 'd1',
              performedOnly: performedOnly,
              trackAllCallers: true,
              onOpenProgram: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder historyRows() => find.byWidgetPredicate(
    (w) =>
        w is CallingHistoryRow ||
        (w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('calling-history-') &&
            (w.key! as ValueKey<String>).value != 'calling-history-empty'),
  );

  testWidgets('renders the empty state for a dance never called', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));

    await pumpSection(tester, repos);

    expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);
  });

  testWidgets('renders the programs that include the dance', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );

    await pumpSection(tester, repos);

    expect(find.byKey(const ValueKey('calling-history-s1')), findsOne);
    expect(find.text('Autumn Ball'), findsOne);
    expect(find.byKey(const ValueKey('calling-history-empty')), findsNothing);
  });

  testWidgets(
    'a program-side write with NO refresh scope mounted updates the section',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(dance('d1', 'Petronella'));

      await pumpSection(tester, repos);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);

      // The write the seven gaps in #768 were all shaped like: made somewhere
      // else entirely, with nothing telling this widget about it.
      await repos.programs.create(
        program(
          id: 'p1',
          title: 'Autumn Ball',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(historyRows(), findsOne);
      expect(find.text('Autumn Ball'), findsOne);
      expect(find.byKey(const ValueKey('calling-history-empty')), findsNothing);
    },
  );

  testWidgets('deleting the program removes its row from the section', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await pumpSection(tester, repos);
    expect(historyRows(), findsOne);

    // A soft delete writes only the `programs` row — the case a `readsFrom`
    // set missing that table drops silently.
    await repos.programs.softDelete('p1', at: DateTime.utc(2026, 2));
    await tester.pumpAndSettle();

    expect(historyRows(), findsNothing);
    expect(find.byKey(const ValueKey('calling-history-empty')), findsOne);
  });

  testWidgets('renaming the program updates its row', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await pumpSection(tester, repos);
    expect(find.text('Autumn Ball'), findsOne);

    await repos.programs.update(
      program(
        id: 'p1',
        title: 'Autumn Ball (rescheduled)',
        updatedAt: DateTime.utc(2026, 2),
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn Ball (rescheduled)'), findsOne);
    expect(find.text('Autumn Ball'), findsNothing);
  });

  testWidgets('performedOnly restricts the section to performed slots', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [
          ProgramSlot(
            id: 's-performed',
            position: 0,
            danceId: 'd1',
            performedAt: DateTime.utc(2026, 10, 3, 20),
          ),
        ],
      ),
    );
    await repos.programs.create(
      program(
        id: 'p2',
        title: 'Spring Fling',
        slots: [ProgramSlot(id: 's-planned', position: 0, danceId: 'd1')],
      ),
    );

    await pumpSection(tester, repos, performedOnly: true);

    expect(find.byKey(const ValueKey('calling-history-s-performed')), findsOne);
    expect(
      find.byKey(const ValueKey('calling-history-s-planned')),
      findsNothing,
    );
  });

  testWidgets(
    'resolves venue labels per program (linked name, else free text)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(dance('d1', 'Petronella'));
      final grange = Venue(
        id: 'grange-hall',
        name: 'Grange Hall',
        city: 'Nelson',
      );
      await repos.venues.upsert(grange);
      await repos.programs.create(
        program(
          id: 'p-linked',
          title: 'Autumn Ball',
          venueId: 'grange-hall',
          slots: [ProgramSlot(id: 's-linked', position: 0, danceId: 'd1')],
        ),
      );
      await repos.programs.create(
        program(
          id: 'p-freetext',
          title: 'Spring Fling',
          venue: 'Town Hall',
          slots: [ProgramSlot(id: 's-freetext', position: 0, danceId: 'd1')],
        ),
      );

      await pumpSection(tester, repos);

      final linked = tester.widget<CallingHistoryRow>(
        find.byKey(const ValueKey('calling-history-s-linked')),
      );
      final freeText = tester.widget<CallingHistoryRow>(
        find.byKey(const ValueKey('calling-history-s-freetext')),
      );
      expect(linked.venueLabel, grange.displayName);
      expect(freeText.venueLabel, 'Town Hall');
    },
  );

  testWidgets('half-calling stats appear with the history, not a beat later', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));
    await repos.dances.create(dance('d2', 'Chase the Squirrel'));

    await pumpSection(tester, repos);
    expect(find.byKey(const ValueKey('half-calling-stats')), findsNothing);

    await repos.programs.create(
      program(
        id: 'p1',
        title: 'Autumn Ball',
        slots: [
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 'b1', position: 1, text: Program.breakSlotText),
          ProgramSlot(id: 's2', position: 2, danceId: 'd2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(historyRows(), findsOne);
    expect(
      find.byKey(const ValueKey('half-calling-stats')),
      findsOne,
      reason:
          'the stats ride the history stream, so they must land in the same '
          'rebuild rather than one emit behind it',
    );
  });
}
