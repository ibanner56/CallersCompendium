import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late ChoreographerRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = ChoreographerRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('round-trips a choreographer', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Bob Isaacs',
      website: 'https://example.com',
      notes: 'prolific',
    );
    // ignore: unused_result
    await repo.upsert(c);
    expect(await repo.getById('c1'), c);
  });

  test('round-trips contact fields (email/location/deceased)', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Cary Ravitz',
      email: 'cary@example.com',
      location: 'Lexington, KY',
      deceased: true,
    );
    // ignore: unused_result
    await repo.upsert(c);
    final read = await repo.getById('c1');
    expect(read!.email, 'cary@example.com');
    expect(read.location, 'Lexington, KY');
    expect(read.deceased, isTrue);
  });

  test('contact fields default to null/false when unset', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Minimal'));
    final read = await repo.getById('c1');
    expect(read!.email, isNull);
    expect(read.location, isNull);
    expect(read.deceased, isFalse);
  });

  test('normalizes empty/whitespace email & location to null', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(id: 'c1', name: 'Blank', email: '   ', location: ''),
    );
    final read = await repo.getById('c1');
    expect(read!.email, isNull);
    expect(read.location, isNull);
  });

  test('trims surrounding whitespace on email & location', () async {
    // ignore: unused_result
    await repo.upsert(
      Choreographer(
        id: 'c1',
        name: 'Trimmed',
        email: '  a@b.com  ',
        location: '  Portland  ',
      ),
    );
    final read = await repo.getById('c1');
    expect(read!.email, 'a@b.com');
    expect(read.location, 'Portland');
  });

  test('copyWith clear flags win over passed values', () async {
    final c = Choreographer(
      id: 'c1',
      name: 'Cleared',
      email: 'a@b.com',
      location: 'Portland',
    );
    final cleared = c.copyWith(
      email: 'ignored@b.com',
      clearEmail: true,
      location: 'Ignored',
      clearLocation: true,
    );
    expect(cleared.email, isNull);
    expect(cleared.location, isNull);
  });

  test('upsert updates in place (same id)', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Old Name'));
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'New Name'));
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'New Name');
  });

  test('listAll orders by name', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Zeke'));
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c2', name: 'Amy'));
    expect((await repo.listAll()).map((c) => c.name), ['Amy', 'Zeke']);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repo.getById('nope'), isNull);
  });

  test('delete removes an unreferenced choreographer', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Solo'));
    await repo.delete('c1');
    expect(await repo.getById('c1'), isNull);
  });

  test('delete throws if the choreographer is still credited', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        authorIds: const ['c1'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await expectLater(repo.delete('c1'), throwsA(isA<StateError>()));
    // still there, since delete failed
    expect(await repo.getById('c1'), isNotNull);
  });

  test('delete succeeds once the crediting dance is unlinked', () async {
    // ignore: unused_result
    await repo.upsert(Choreographer(id: 'c1', name: 'Credited'));
    final dance = Dance(
      id: 'd1',
      title: 'Some Dance',
      authorIds: const ['c1'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(dance);
    await dances.update(dance.copyWith(authorIds: const []));

    await repo.delete('c1');
    expect(await repo.getById('c1'), isNull);
  });
}
