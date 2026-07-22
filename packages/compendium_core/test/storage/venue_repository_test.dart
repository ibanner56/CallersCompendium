import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late VenueRepository repo;
  late ProgramRepository programs;

  setUp(() {
    db = openTestDatabase();
    repo = VenueRepository(db);
    programs = ProgramRepository(db);
  });

  tearDown(() => db.close());

  Program buildProgram({required String id, String? venueId}) => Program(
    id: id,
    title: 'Spring Contra',
    venueId: venueId,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    slots: [ProgramSlot(id: '$id-s1', position: 0, text: 'Welcome')],
  );

  test('round-trips a fully-populated venue', () async {
    final v = Venue(
      id: 'v1',
      name: 'Guiding Star Grange',
      address1: '401 Chapman St',
      address2: 'Hall B',
      city: 'Greenfield',
      stateProv: 'MA',
      country: 'USA',
      postalCode: '01301',
      plus4: '1234',
      website: 'https://example.com',
      sponsor: 'Greenfield Dance',
      eventName: 'Second Saturday Contra',
      time: '8pm',
      genericSchedule: '2nd Saturdays',
      price: '\$10',
      notes: 'wooden floor',
      contact1Name: 'Pat',
      contact1Phone: '555-0001',
      contact1Email: 'pat@example.com',
      contact2Name: 'Sam',
      contact2Phone: '555-0002',
      contact2Email: 'sam@example.com',
    );
    await repo.upsert(v);
    expect(await repo.getById('v1'), v);
  });

  test('optional fields default to null', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Minimal Hall'));
    final read = await repo.getById('v1');
    expect(read!.address1, isNull);
    expect(read.city, isNull);
    expect(read.contact1Email, isNull);
    expect(read.contact2Phone, isNull);
    expect(read.genericSchedule, isNull);
  });

  test('upsert updates in place (same id)', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Old Name'));
    await repo.upsert(Venue(id: 'v1', name: 'New Name', city: 'Amherst'));
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'New Name');
    expect(all.single.city, 'Amherst');
  });

  test('listAll orders by name, case-insensitively', () async {
    await repo.upsert(Venue(id: 'v1', name: 'zephyr Hall'));
    await repo.upsert(Venue(id: 'v2', name: 'Apple Barn'));
    await repo.upsert(Venue(id: 'v3', name: 'Birch Grange'));
    expect((await repo.listAll()).map((v) => v.name), [
      'Apple Barn',
      'Birch Grange',
      'zephyr Hall',
    ]);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repo.getById('nope'), isNull);
  });

  test('delete removes an unreferenced venue', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Solo Hall'));
    await repo.delete('v1');
    expect(await repo.getById('v1'), isNull);
  });

  test('delete throws while a program still references the venue', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Linked Hall'));
    await programs.create(buildProgram(id: 'p1', venueId: 'v1'));

    await expectLater(repo.delete('v1'), throwsA(isA<StateError>()));
    expect(await repo.getById('v1'), isNotNull);
  });

  test('delete succeeds once the referencing program is unlinked', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Linked Hall'));
    await programs.create(buildProgram(id: 'p1', venueId: 'v1'));

    final p = await programs.getById('p1');
    await programs.update(p!.copyWith(clearVenueId: true));

    await repo.delete('v1');
    expect(await repo.getById('v1'), isNull);
  });

  test('the delete guard counts every referencing program', () async {
    await repo.upsert(Venue(id: 'v1', name: 'Popular Hall'));
    await programs.create(buildProgram(id: 'p1', venueId: 'v1'));
    await programs.create(buildProgram(id: 'p2', venueId: 'v1'));

    await expectLater(
      repo.delete('v1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('2 program(s)'),
        ),
      ),
    );
  });
}
