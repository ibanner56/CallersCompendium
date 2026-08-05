import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late TagRepository repo;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    repo = TagRepository(db);
    dances = DanceRepository(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test('round-trips a tag with a color', () async {
    final tag = Tag(id: 't1', name: 'chestnut', color: 0xFF00FF00);
    await repo.upsert(tag);
    expect(await repo.getById('t1'), tag);
  });

  test('round-trips a tag without a color', () async {
    final tag = Tag(id: 't1', name: 'workshop');
    await repo.upsert(tag);
    expect(await repo.getById('t1'), tag);
  });

  test('clearing a colour persists as null, not as the previous colour', () async {
    // Guards the reset action in the tag-colour picker (issue #786). The
    // obvious `copyWith(color: null)` cannot express this — its `?? this.color`
    // fallback keeps the old value — so a naive implementation would leave the
    // colour on disk while the UI claimed it was cleared.
    await repo.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3));
    expect((await repo.getById('t1'))!.color, 0xFF2196F3);

    await repo.upsert((await repo.getById('t1'))!.withColor(null));
    expect((await repo.getById('t1'))!.color, isNull);
  });

  test('listAll orders by name', () async {
    await repo.upsert(Tag(id: 't1', name: 'Zesty'));
    await repo.upsert(Tag(id: 't2', name: 'Alpha'));
    expect((await repo.listAll()).map((t) => t.name), ['Alpha', 'Zesty']);
  });

  test('deleting a tag cascades to dance_tags', () async {
    await repo.upsert(Tag(id: 't1', name: 'chestnut'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Some Dance',
        tagIds: const ['t1'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await repo.delete('t1');
    final loaded = await dances.getById('d1');
    expect(loaded!.tagIds, isEmpty);
  });
}
