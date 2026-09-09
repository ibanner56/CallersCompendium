import 'package:compendium_core/src/model/difficulty_level.dart';
import 'package:compendium_core/src/model/enums.dart';
import 'package:compendium_core/src/model/formation.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:compendium_core/src/storage/repositories/difficulty_level_repository.dart';
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
}
