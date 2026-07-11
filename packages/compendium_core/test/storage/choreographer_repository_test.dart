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
    await repo.upsert(c);
    expect(await repo.getById('c1'), c);
  });

  test('upsert updates in place (same id)', () async {
    await repo.upsert(Choreographer(id: 'c1', name: 'Old Name'));
    await repo.upsert(Choreographer(id: 'c1', name: 'New Name'));
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'New Name');
  });

  test('listAll orders by name', () async {
    await repo.upsert(Choreographer(id: 'c1', name: 'Zeke'));
    await repo.upsert(Choreographer(id: 'c2', name: 'Amy'));
    expect((await repo.listAll()).map((c) => c.name), ['Amy', 'Zeke']);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repo.getById('nope'), isNull);
  });

  test('delete removes an unreferenced choreographer', () async {
    await repo.upsert(Choreographer(id: 'c1', name: 'Solo'));
    await repo.delete('c1');
    expect(await repo.getById('c1'), isNull);
  });

  test('delete throws if the choreographer is still credited', () async {
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
}
