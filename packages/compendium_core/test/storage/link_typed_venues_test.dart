import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// GIG-7 = (b), branch B3: `ProgramRepository.linkTypedVenues` links older
/// programs' typed venue to a venue record, matching by [VenueKey].
void main() {
  final stamp = DateTime.utc(2026, 10, 30, 12);
  final old = DateTime.utc(2020);

  late CompendiumDatabase db;
  late ProgramRepository programs;
  late DanceRepository dances;
  late VenueRepository venues;

  setUp(() async {
    db = openTestDatabase();
    programs = ProgramRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
    venues = VenueRepository(db);
    await dances.create(
      Dance(id: 'd1', title: 'd1', createdAt: old, updatedAt: old),
    );
    await venues.upsert(Venue(id: 'grange', name: 'Grange Hall'));
  });

  tearDown(() => db.close());

  Future<void> program(
    String id, {
    String? venue,
    String? venueId,
    DateTime? deletedAt,
    String slotSuffix = '',
  }) => programs.create(
    Program(
      id: id,
      title: id,
      venue: venue,
      venueId: venueId,
      deletedAt: deletedAt,
      slots: [ProgramSlot(id: 's-$id', position: 0, danceId: 'd1')],
      createdAt: old,
      updatedAt: old,
    ),
  );

  Future<Program> read(String id) async =>
      (await programs.getById(id, includeDeleted: true))!;

  Future<int> link({String? exclude}) => programs.linkTypedVenues(
    venueId: 'grange',
    name: 'Grange Hall',
    updatedAt: stamp,
    excludeProgramId: exclude,
  );

  test('links typed programs by venue key and keeps the typed text', () async {
    await program('exact', venue: 'Grange Hall');
    await program('folded', venue: '  GRANGE\tHALL ');
    await program('other', venue: 'Town Hall');

    expect(await programs.countTypedVenuePrograms('Grange Hall'), 2);
    expect(await link(), 2);

    for (final id in ['exact', 'folded']) {
      final p = await read(id);
      expect(p.venueId, 'grange');
      expect(p.venue, isNotNull, reason: 'the link is lossless');
      expect(p.updatedAt, stamp, reason: 'a newer stamp for sync');
    }
    expect((await read('exact')).venue, 'Grange Hall');
    expect((await read('other')).venueId, isNull);
    expect((await read('other')).updatedAt, old);
    expect(await programs.countTypedVenuePrograms('Grange Hall'), 0);
  });

  test('a trashed program keeps its typed venue', () async {
    await program('live', venue: 'Grange Hall');
    await program(
      'trashed',
      venue: 'Grange Hall',
      deletedAt: DateTime.utc(2026, 2, 1),
    );

    expect(await programs.countTypedVenuePrograms('Grange Hall'), 1);
    expect(await link(), 1);

    final trashed = await read('trashed');
    expect(trashed.venueId, isNull);
    expect(trashed.updatedAt, old);
    expect(trashed.deletedAt, isNotNull);
  });

  test('programs already linked to any record are left alone', () async {
    await venues.upsert(Venue(id: 'other', name: 'Other Hall'));
    await program('elsewhere', venue: 'Grange Hall', venueId: 'other');

    expect(await link(), 0);
    expect((await read('elsewhere')).venueId, 'other');
  });

  test('excludeProgramId leaves the editor\'s own program alone', () async {
    await program('open', venue: 'Grange Hall');
    await program('closed', venue: 'Grange Hall');

    expect(
      await programs.countTypedVenuePrograms(
        'Grange Hall',
        excludeProgramId: 'open',
      ),
      1,
    );
    expect(await link(exclude: 'open'), 1);
    expect((await read('open')).venueId, isNull);
    expect((await read('closed')).venueId, 'grange');
  });

  test('a blank name links nothing', () async {
    await program('typed', venue: 'Grange Hall');
    expect(await programs.countTypedVenuePrograms('  '), 0);
    expect(
      await programs.linkTypedVenues(
        venueId: 'grange',
        name: ' ',
        updatedAt: stamp,
      ),
      0,
    );
  });

  test('refuses a venue that is not live', () async {
    await program('typed', venue: 'Grange Hall');
    await venues.delete('grange');
    await expectLater(link(), throwsA(isA<StateError>()));
    await expectLater(
      programs.linkTypedVenues(venueId: 'nope', name: 'x', updatedAt: stamp),
      throwsA(isA<StateError>()),
    );
    expect((await read('typed')).venueId, isNull);
  });

  test('a linked program counts under the record in the venue scope and the '
      'repeated-venues list', () async {
    // One call at the record, one under the same name typed in: two keys.
    await program('linked', venue: null, venueId: 'grange');
    await program('typed', venue: 'Grange Hall');
    await dances.create(
      Dance(id: 'd2', title: 'd2', createdAt: old, updatedAt: old),
    );
    await programs.create(
      Program(
        id: 'typed2',
        title: 'typed2',
        venue: 'grange hall',
        slots: [ProgramSlot(id: 's-typed2', position: 0, danceId: 'd2')],
        createdAt: old,
        updatedAt: old,
      ),
    );

    Future<Set<String>> called(VenueKey key) async =>
        (await dances.search(CalledFilter(called: true, venue: key))).toSet();

    expect(await called(const VenueKey.record('grange')), {'d1'});
    expect(await called(VenueKey.typed('Grange Hall')), {'d1', 'd2'});
    expect((await programs.calledVenues()).map((v) => v.key).toSet(), {
      const VenueKey.record('grange'),
      VenueKey.typed('Grange Hall'),
    });

    expect(await link(), 2);

    expect(await called(const VenueKey.record('grange')), {'d1', 'd2'});
    expect(await called(VenueKey.typed('Grange Hall')), isEmpty);
    final listed = await programs.calledVenues();
    expect(listed, hasLength(1));
    expect(listed.single.key, const VenueKey.record('grange'));
    expect(listed.single.programCount, 3);
  });
}
