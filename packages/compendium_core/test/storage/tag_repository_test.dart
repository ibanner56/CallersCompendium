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
    // ignore: unused_result
    await repo.upsert(tag);
    expect(await repo.getById('t1'), tag);
  });

  test('round-trips a tag without a color', () async {
    final tag = Tag(id: 't1', name: 'workshop');
    // ignore: unused_result
    await repo.upsert(tag);
    expect(await repo.getById('t1'), tag);
  });

  test('clearing a colour persists as null, not as the previous colour', () async {
    // Guards the reset action in the tag-colour picker (issue #786). The
    // obvious `copyWith(color: null)` cannot express this — its `?? this.color`
    // fallback keeps the old value — so a naive implementation would leave the
    // colour on disk while the UI claimed it was cleared.
    // ignore: unused_result
    await repo.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3));
    expect((await repo.getById('t1'))!.color, 0xFF2196F3);

    // ignore: unused_result
    await repo.upsert((await repo.getById('t1'))!.withColor(null));
    expect((await repo.getById('t1'))!.color, isNull);
  });

  test('listAll orders by name', () async {
    // ignore: unused_result
    await repo.upsert(Tag(id: 't1', name: 'Zesty'));
    // ignore: unused_result
    await repo.upsert(Tag(id: 't2', name: 'Alpha'));
    expect((await repo.listAll()).map((t) => t.name), ['Alpha', 'Zesty']);
  });

  test('lists only tags referenced by live dances', () async {
    // ignore: unused_result
    await repo.upsert(Tag(id: 't1', name: 'Live'));
    // ignore: unused_result
    await repo.upsert(Tag(id: 't2', name: 'Archived'));
    await dances.create(
      Dance(
        id: 'd1',
        title: 'Live Dance',
        tagIds: const ['t1'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await dances.create(
      Dance(
        id: 'd2',
        title: 'Archived Dance',
        tagIds: const ['t2'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await dances.softDelete('d2', at: DateTime.utc(2026, 1, 2));

    expect((await repo.listReferencedByLiveDances()).map((tag) => tag.id), [
      't1',
    ]);
    expect((await repo.listAll()).map((tag) => tag.id), ['t2', 't1']);
  });

  test(
    'deleting and restoring a tag preserves its dance association',
    () async {
      // ignore: unused_result
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
      await repo.restore('t1', at: DateTime.utc(2026, 1, 2));
      expect((await dances.getById('d1'))!.tagIds, ['t1']);
    },
  );

  test('removing a tag association deletes an unreferenced tag row', () async {
    // ignore: unused_result
    await repo.upsert(Tag(id: 't1', name: 'chestnut'));
    final dance = Dance(
      id: 'd1',
      title: 'Some Dance',
      tagIds: const ['t1'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(dance);

    await dances.update(dance.copyWith(tagIds: const []));

    expect(await repo.listAllWithDeleted(), isEmpty);
  });

  test('retains a tag referenced by a soft-deleted dance', () async {
    // ignore: unused_result
    await repo.upsert(Tag(id: 't1', name: 'chestnut'));
    final archivedDance = Dance(
      id: 'd2',
      title: 'Archived Dance',
      tagIds: const ['t1'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(archivedDance);
    await dances.softDelete('d2', at: DateTime.utc(2026, 1, 2));

    final liveDance = Dance(
      id: 'd1',
      title: 'Live Dance',
      tagIds: const ['t1'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await dances.create(liveDance);
    await dances.update(liveDance.copyWith(tagIds: const []));

    expect((await repo.listAllWithDeleted()).map((entry) => entry.tag.id), [
      't1',
    ]);
  });
}
