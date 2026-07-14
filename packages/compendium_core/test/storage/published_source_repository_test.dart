import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late PublishedSourceRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = PublishedSourceRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('round-trips a published source', () async {
    final s = PublishedSource(
      id: 's1',
      title: 'Zesty Contras',
      author: 'Larry Jennings',
      year: 1983,
      url: 'https://example.com/zesty',
      notes: 'seminal collection',
    );
    await repo.upsert(s);
    expect(await repo.getById('s1'), s);
  });

  test('optional fields default to null', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'Minimal'));
    final read = await repo.getById('s1');
    expect(read!.author, isNull);
    expect(read.year, isNull);
    expect(read.url, isNull);
    expect(read.notes, isNull);
  });

  test('upsert updates in place (same id)', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'Old Title'));
    await repo.upsert(PublishedSource(id: 's1', title: 'New Title'));
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.title, 'New Title');
  });

  test('listAll orders by title, case-insensitively', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'zesty'));
    await repo.upsert(PublishedSource(id: 's2', title: 'Apples'));
    await repo.upsert(PublishedSource(id: 's3', title: 'Bananas'));
    expect((await repo.listAll()).map((s) => s.title), [
      'Apples',
      'Bananas',
      'zesty',
    ]);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repo.getById('nope'), isNull);
  });

  test('delete removes an unreferenced source', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'Solo'));
    await repo.delete('s1');
    expect(await repo.getById('s1'), isNull);
  });

  test('delete throws while the source is still cited', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'Cited'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        sourceCitations: [SourceCitation(sourceId: 's1', page: '12')],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await expectLater(repo.delete('s1'), throwsA(isA<StateError>()));
    expect(await repo.getById('s1'), isNotNull);
  });

  test('delete succeeds once the citation is removed', () async {
    await repo.upsert(PublishedSource(id: 's1', title: 'Cited'));
    final dance = Dance(
      id: 'd1',
      title: 'Some Dance',
      sourceCitations: [SourceCitation(sourceId: 's1')],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(dance);
    await dances.update(dance.copyWith(sourceCitations: const []));
    await repo.delete('s1');
    expect(await repo.getById('s1'), isNull);
  });
}
