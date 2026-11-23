import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// [ProgramRepository.latestCallByDance]: the "called at this venue" input to
/// suggestions (#2343). It must select exactly the slots a [CalledFilter]
/// counts, so the builder's Suggested sort and the picker's history filters
/// never disagree about whether a dance was called here.
void main() {
  final now = DateTime.utc(2026, 10, 30, 12);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<void> dance(String id) =>
      dances.create(Dance(id: id, title: id, createdAt: now, updatedAt: now));

  Future<void> program(
    String id, {
    String? venue,
    DateTime? eventDate,
    required List<ProgramSlot> slots,
  }) => programs.create(
    Program(
      id: id,
      title: id,
      venue: venue,
      eventDate: eventDate,
      slots: slots,
      createdAt: DateTime.utc(2020),
      updatedAt: DateTime.utc(2020),
    ),
  );

  ProgramSlot slot(
    String id,
    String danceId, {
    int position = 0,
    DateTime? performedAt,
    bool isAlt = false,
  }) => ProgramSlot(
    id: id,
    position: position,
    danceId: danceId,
    performedAt: performedAt,
    isAlt: isAlt,
  );

  final grange = VenueKey.typed('Grange');

  Future<void> seed() async {
    for (final id in ['old', 'recent', 'undated', 'elsewhere', 'tonight']) {
      await dance(id);
    }
    await program(
      'march',
      venue: 'Grange',
      eventDate: DateTime.utc(2026, 3, 14),
      slots: [slot('m1', 'old'), slot('m2', 'recent', position: 1)],
    );
    await program(
      'october',
      venue: ' grange ',
      eventDate: DateTime.utc(2026, 10, 3),
      slots: [slot('o1', 'recent')],
    );
    // Undated and not performed: called, but with no recency date.
    await program('draft', venue: 'Grange', slots: [slot('d1', 'undated')]);
    await program(
      'hall',
      venue: 'Town Hall',
      eventDate: DateTime.utc(2026, 10, 10),
      slots: [slot('h1', 'elsewhere')],
    );
    // The program being built, at the same venue.
    await program(
      'being-built',
      venue: 'Grange',
      eventDate: DateTime.utc(2026, 11, 28),
      slots: [slot('b1', 'tonight'), slot('b2', 'old', position: 1)],
    );
  }

  test('maps each dance called at the venue to its latest recency date, '
      'leaving out the program being built', () async {
    await seed();
    final filter = CalledFilter(
      called: true,
      venue: grange,
      currentProgramId: 'being-built',
    );
    final latest = await programs.latestCallByDance(filter);
    expect(latest, {
      'old': DateTime.utc(2026, 3, 14),
      'recent': DateTime.utc(2026, 10, 3),
      'undated': null,
    });
    // The same dances the Called filter finds.
    expect(latest.keys.toSet(), (await dances.search(filter)).toSet());
  });

  test('without currentProgramId the program being built counts', () async {
    await seed();
    final filter = CalledFilter(called: true, venue: grange);
    final latest = await programs.latestCallByDance(filter);
    expect(latest['tonight'], DateTime.utc(2026, 11, 28));
    expect(latest['old'], DateTime.utc(2026, 11, 28));
    expect(latest.keys.toSet(), (await dances.search(filter)).toSet());
  });

  test('follows the calling-history settings the filter carries', () async {
    await seed();
    final filter = CalledFilter(
      called: true,
      venue: grange,
      currentProgramId: 'being-built',
      requireEventDate: true,
    );
    final latest = await programs.latestCallByDance(filter);
    expect(latest.keys.toSet(), {'old', 'recent'});
    expect(latest.keys.toSet(), (await dances.search(filter)).toSet());
  });
}
