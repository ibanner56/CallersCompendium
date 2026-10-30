// Bulk delete and its Undo (N4-S3): softDeleteMany and restoreMany run the
// single-dance softDelete and restore inside one transaction each.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  final deletedAt = DateTime.utc(2026, 6, 1);
  final restoredAt = DateTime.utc(2026, 6, 2);

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  List<String> twelve() => [
    for (var i = 1; i <= 12; i++) 'd${i.toString().padLeft(2, '0')}',
  ];

  Future<void> createAll(List<String> ids) async {
    for (final id in ids) {
      await repos.dances.create(sampleDance(id: id, title: 'Dance $id'));
    }
  }

  Future<Set<String>> liveIds() async => {
    for (final dance in await repos.dances.listAll()) dance.id,
  };

  Future<int?> existenceAt(String id) async {
    final rows = await db
        .customSelect(
          'SELECT existence_at AS v FROM dances WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.single.data['v'] as int?;
  }

  // Makes the existence write for [id] fail, so a batch fails on that dance.
  Future<void> failWhen(String id, {required bool deleting}) =>
      db.customStatement(
        'CREATE TEMP TRIGGER fail_on_$id BEFORE UPDATE OF deleted_at '
        "ON dances WHEN NEW.id = '$id' AND NEW.deleted_at IS "
        "${deleting ? 'NOT ' : ''}NULL "
        "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );

  group('softDeleteMany', () {
    test('deletes the live dances and returns them in order', () async {
      await createAll(['a', 'b', 'c', 'gone']);
      await repos.dances.softDelete('gone', at: DateTime.utc(2026, 5, 1));

      final deleted = await repos.dances.softDeleteMany([
        'c',
        'gone',
        'missing',
        'a',
        'c',
      ], at: deletedAt);

      expect(deleted, ['c', 'a']);
      expect(await liveIds(), {'b'});
      final trashed = await repos.dances.getById('a', includeDeleted: true);
      expect(trashed!.deletedAt, deletedAt);
      // The dance already in the trash keeps its own deletion date.
      final earlier = await repos.dances.getById('gone', includeDeleted: true);
      expect(earlier!.deletedAt, DateTime.utc(2026, 5, 1));
    });

    test('a failure on the 7th of 12 leaves all 12 live', () async {
      final ids = twelve();
      await createAll(ids);
      await failWhen('d07', deleting: true);

      await expectLater(
        repos.dances.softDeleteMany(ids, at: deletedAt),
        throwsA(anything),
      );

      expect(await liveIds(), ids.toSet());
    });

    test('an empty list is a no-op', () async {
      expect(await repos.dances.softDeleteMany([], at: deletedAt), isEmpty);
    });
  });

  group('restoreMany', () {
    test('restores what softDeleteMany deleted', () async {
      final ids = twelve();
      await createAll(ids);
      final deleted = await repos.dances.softDeleteMany(ids, at: deletedAt);

      expect(await repos.dances.restoreMany(deleted, at: restoredAt), 12);

      expect(await liveIds(), ids.toSet());
      expect(
        await existenceAt('d01'),
        greaterThan(deletedAt.millisecondsSinceEpoch ~/ 1000),
        reason: 'the revival must outrank the tombstone, so it syncs',
      );
    });

    test('a failure on the 7th of 12 leaves all 12 in the trash', () async {
      final ids = twelve();
      await createAll(ids);
      await repos.dances.softDeleteMany(ids, at: deletedAt);
      await failWhen('d07', deleting: false);

      await expectLater(
        repos.dances.restoreMany(ids, at: restoredAt),
        throwsA(anything),
      );

      expect(await liveIds(), isEmpty);
    });

    test('revives a level deleted while its dances were in the trash, '
        'through restore', () async {
      // B9: the trash does not protect a dance's level (the maintainer's
      // trash-policy decision, 2026-10-29, option b), and restore revives it.
      // Bulk Undo must go through that same restore.
      final level = await repos.difficultyLevels.createCustom(
        label: 'Challenge',
        position: 9,
      );
      for (final id in ['a', 'b']) {
        await repos.dances.create(
          sampleDance(
            id: id,
            title: 'Dance $id',
          ).copyWith(difficultyLevelId: level.id),
        );
      }
      final deleted = await repos.dances.softDeleteMany([
        'a',
        'b',
      ], at: deletedAt);
      await repos.difficultyLevels.delete(
        level.id,
        at: DateTime.utc(2026, 6, 1, 12),
      );
      expect(await repos.difficultyLevels.getById(level.id), isNull);

      await repos.dances.restoreMany(deleted, at: restoredAt);

      expect(await repos.difficultyLevels.getById(level.id), level);
      expect((await repos.dances.getById('a'))!.difficultyLevelId, level.id);
      // The failure B8 left open, had the level stayed tombstoned.
      final back = (await repos.dances.getById('b'))!;
      await repos.dances.update(back.copyWith(title: 'Edited'));
    });

    test(
      'skips a dance that is already live, without re-stamping it',
      () async {
        await createAll(['a', 'b']);
        final deleted = await repos.dances.softDeleteMany([
          'a',
          'b',
        ], at: deletedAt);
        await repos.dances.restore('a', at: DateTime.utc(2026, 6, 1, 12));
        final stamp = await existenceAt('a');

        expect(await repos.dances.restoreMany(deleted, at: restoredAt), 1);

        expect(await existenceAt('a'), stamp);
        expect(await liveIds(), {'a', 'b'});
      },
    );

    test('skips a permanently deleted dance', () async {
      await createAll(['a', 'b']);
      final deleted = await repos.dances.softDeleteMany([
        'a',
        'b',
      ], at: deletedAt);
      await db.customStatement(
        "UPDATE dances SET deleted_at = 0 WHERE id = 'a'",
      );

      expect(await repos.dances.restoreMany(deleted, at: restoredAt), 1);

      expect(await liveIds(), {'b'});
    });
  });
}
