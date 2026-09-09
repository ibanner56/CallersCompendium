import 'package:compendium_core/src/model/difficulty_level.dart';
import 'package:compendium_core/src/model/enums.dart';
import 'package:compendium_core/src/model/formation.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:compendium_core/src/storage/repositories/difficulty_level_repository.dart';
import 'package:compendium_core/src/sync/sync_codec.dart';
import 'package:compendium_core/src/sync/sync_record_kind.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

Future<void> insertDance(
  CompendiumDatabase db, {
  required String id,
  String? difficultyLevelId,
}) {
  final now = DateTime.utc(2026);
  return db
      .into(db.dances)
      .insert(
        DancesCompanion.insert(
          id: id,
          title: id,
          form: DanceForm.contra,
          formationShape: FormationShape.dupleImproper,
          progression: Progression.single,
          status: DanceStatus.active,
          levelId: Value(difficultyLevelId),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late CompendiumDatabase db;
  late DifficultyLevelRepository levels;

  setUp(() {
    db = CompendiumDatabase(NativeDatabase.memory());
    levels = DifficultyLevelRepository(db);
  });
  tearDown(() => db.close());

  test('fresh databases contain the fixed shipped difficulty levels', () async {
    expect(await levels.listAll(), DifficultyLevel.shipped);
  });

  test('creating a custom level assigns a generated ID', () async {
    final custom = await levels.createCustom(label: 'Challenge', position: 3);

    expect(custom.id, matches(RegExp(r'^[0-9a-f]{8}-')));
    expect((await levels.listAll()).last, custom);
  });

  test('recreating a deleted label revives its stable ID', () async {
    final original = await levels.createCustom(label: 'Challenge', position: 3);
    await levels.delete(original.id, at: DateTime.utc(2099, 1, 2));

    final recreated = await levels.createCustom(
      label: ' challenge ',
      position: 3,
    );

    expect(recreated.id, original.id);
    expect(await levels.getById(original.id), recreated);
  });

  test('reordering updates timestamps used by sync records', () async {
    final before = await (db.select(
      db.difficultyLevels,
    )..where((t) => t.id.equals(DifficultyLevel.beginnerId))).getSingle();
    final reorderedAt = DateTime.utc(2099, 1, 3);
    await levels.reorder([
      DifficultyLevel.intermediateId,
      DifficultyLevel.beginnerId,
      DifficultyLevel.advancedId,
    ], at: reorderedAt);

    final row = await (db.select(
      db.difficultyLevels,
    )..where((t) => t.id.equals(DifficultyLevel.beginnerId))).getSingle();
    expect(row.position, 1);
    expect(row.updatedAt?.toUtc(), reorderedAt);
    expect(row.updatedAt, isNot(before.updatedAt));

    final entity = (await levels.listAll()).singleWhere(
      (level) => level.id == DifficultyLevel.beginnerId,
    );
    final syncRecord = syncRecordBlobForEntity(
      SyncRecordKind.difficultyLevel,
      entity,
      updatedAt: row.updatedAt!,
      existenceAt: row.existenceAt!,
    )!;
    expect(syncRecord.updatedAt, reorderedAt);
    expect(syncRecord.body['position'], 1);
  });

  test('database rejects a dangling difficulty-level ID', () async {
    await expectLater(
      insertDance(db, id: 'dangling-level', difficultyLevelId: 'not-a-level'),
      throwsA(isA<sqlite3.SqliteException>()),
    );
    expect(
      await (db.select(
        db.dances,
      )..where((t) => t.id.equals('dangling-level'))).getSingleOrNull(),
      isNull,
    );
  });

  test('deleting a level in use is rejected without deleting it', () async {
    final custom = await levels.createCustom(label: 'Challenge', position: 3);
    await insertDance(db, id: 'uses-level', difficultyLevelId: custom.id);

    await expectLater(
      levels.delete(custom.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('still referenced by 1 dance(s)'),
        ),
      ),
    );
    expect(await levels.getById(custom.id), custom);
    final dance = await (db.select(
      db.dances,
    )..where((t) => t.id.equals('uses-level'))).getSingle();
    expect(dance.levelId, custom.id);
  });

  test('deleting an unused level creates a sync tombstone', () async {
    final custom = await levels.createCustom(label: 'Challenge', position: 3);
    final deletedAt = DateTime.utc(2099, 1, 2);

    await levels.delete(custom.id, at: deletedAt);

    expect(await levels.getById(custom.id), isNull);
    expect(
      (await levels.listAllWithDeleted()).singleWhere(
        (entry) => entry.level.id == custom.id,
      ),
      (level: custom, deleted: true),
    );
    final row = await (db.select(
      db.difficultyLevels,
    )..where((t) => t.id.equals(custom.id))).getSingle();
    expect(row.deletedAt?.toUtc(), deletedAt);
    expect(row.existenceAt?.toUtc(), deletedAt);
  });

  test('upserting a tombstoned level revives it causally', () async {
    final custom = await levels.createCustom(label: 'Challenge', position: 3);
    await levels.delete(custom.id, at: DateTime.utc(2099, 1, 2));

    final renamed = custom.copyWith(label: 'Hard');
    await levels.upsert(renamed, at: DateTime.utc(2099, 1, 1));

    expect(await levels.getById(custom.id), renamed);
    final row = await (db.select(
      db.difficultyLevels,
    )..where((t) => t.id.equals(custom.id))).getSingle();
    expect(row.deletedAt, isNull);
    expect(row.existenceAt?.toUtc(), DateTime.utc(2099, 1, 2, 0, 0, 1));
  });
}
