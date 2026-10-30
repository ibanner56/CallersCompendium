// Restore copes with what its record uses having been deleted meanwhile (B9).
//
// The maintainer's trash-policy decision (2026-10-29, option b) means a dance
// or program in Recently deleted no longer protects its difficulty level,
// custom fields or venue, so each can be deleted while the record is in the
// trash. Restoring the record revives them; duplicating a program whose venue
// is gone drops the dead link instead of failing (LIFE-4).
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  final created = DateTime.utc(2026, 1, 1);
  final trashed = DateTime.utc(2026, 2, 1);
  final referenceDeleted = DateTime.utc(2026, 3, 1);
  final restored = DateTime.utc(2026, 4, 1);

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  Future<int?> rawStamp(String table, String column, String id) async {
    final rows = await db
        .customSelect(
          'SELECT $column AS v FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.data['v'] as int?;
  }

  Future<void> markPermanentlyDeleted(String table, String id) =>
      db.customStatement('UPDATE $table SET deleted_at = 0 WHERE id = ?', [id]);

  Dance dance({String? levelId, List<CustomFieldValue> fields = const []}) =>
      Dance(
        id: 'd1',
        title: 'Chase the Squirrel',
        difficultyLevelId: levelId,
        customFields: fields,
        createdAt: created,
        updatedAt: created,
      );

  group('restoring a dance', () {
    late DifficultyLevel level;

    setUp(() async {
      level = await repos.difficultyLevels.createCustom(
        label: 'Challenge',
        position: 9,
      );
    });

    test('revives the level deleted while it was in the trash', () async {
      await repos.dances.create(dance(levelId: level.id));
      await repos.dances.softDelete('d1', at: trashed);
      await repos.difficultyLevels.delete(level.id, at: referenceDeleted);
      expect(await repos.difficultyLevels.getById(level.id), isNull);

      await repos.dances.restore('d1', at: restored);

      expect(await repos.difficultyLevels.getById(level.id), level);
      expect(
        await rawStamp('difficulty_levels', 'existence_at', level.id),
        greaterThan(referenceDeleted.millisecondsSinceEpoch ~/ 1000),
        reason: 'the revival must outrank the tombstone, so it syncs',
      );
      // The failure B8 left open: the restored dance's next save.
      final back = (await repos.dances.getById('d1'))!;
      await repos.dances.update(back.copyWith(title: 'Edited'));
      expect((await repos.dances.getById('d1'))!.difficultyLevelId, level.id);
    });

    test('revives a custom field deleted while it was in the trash', () async {
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'feel',
          label: 'Feel',
          type: CustomFieldType.text,
        ),
        at: created,
      );
      await repos.dances.create(
        dance(
          fields: [CustomFieldValue(fieldId: 'f1', value: 'lyrical')],
        ),
      );
      await repos.dances.softDelete('d1', at: trashed);
      await repos.customFieldDefs.delete('f1', at: referenceDeleted);
      expect(await repos.customFieldDefs.getById('f1'), isNull);

      await repos.dances.restore('d1', at: restored);

      expect(await repos.customFieldDefs.getById('f1'), isNotNull);
      // Revived before the search index is rebuilt, so search finds it.
      expect(await repos.dances.searchText('lyrical'), ['d1']);
      expect((await repos.dances.getById('d1'))!.customFields, [
        CustomFieldValue(fieldId: 'f1', value: 'lyrical'),
      ]);
    });

    test('leaves its references alone without reviveReferences', () async {
      await repos.dances.create(dance(levelId: level.id));
      await repos.dances.softDelete('d1', at: trashed);
      await repos.difficultyLevels.delete(level.id, at: referenceDeleted);

      await repos.dances.restore('d1', at: restored, reviveReferences: false);

      expect(await repos.dances.getById('d1'), isNotNull);
      expect(await repos.difficultyLevels.getById(level.id), isNull);
    });

    test(
      'neither restores nor revives for a permanently deleted dance',
      () async {
        // An epoch `deleted_at` that still names its level: the mark builds
        // before blanking left (`permanent_deletion.dart`).
        await repos.dances.create(dance(levelId: level.id));
        await repos.dances.softDelete('d1', at: trashed);
        await repos.difficultyLevels.delete(level.id, at: referenceDeleted);
        await markPermanentlyDeleted('dances', 'd1');

        await repos.dances.restore('d1', at: restored);

        expect(await repos.dances.getById('d1'), isNull);
        expect(await rawStamp('dances', 'deleted_at', 'd1'), 0);
        expect(await repos.difficultyLevels.getById(level.id), isNull);
      },
    );
  });

  group('restoring a program', () {
    Program program({String? venueId, String? venue}) => Program(
      id: 'p1',
      title: 'Spring dance',
      venue: venue,
      venueId: venueId,
      createdAt: created,
      updatedAt: created,
    );

    setUp(() async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Grange'),
        at: created,
      );
    });

    test('revives the venue deleted while it was in the trash', () async {
      await repos.programs.create(program(venueId: 'v1'));
      await repos.programs.softDelete('p1', at: trashed);
      await repos.venues.delete('v1', at: referenceDeleted);
      expect(await repos.venues.getById('v1'), isNull);

      await repos.programs.restore('p1', at: restored);

      expect((await repos.venues.getById('v1'))?.name, 'Grange');
      expect(
        await rawStamp('venues', 'existence_at', 'v1'),
        greaterThan(referenceDeleted.millisecondsSinceEpoch ~/ 1000),
        reason: 'the revival must outrank the tombstone, so it syncs',
      );
      expect((await repos.programs.getById('p1'))!.venueId, 'v1');
    });

    test('keeps a venue id that names no venue at all', () async {
      // A peer's program can arrive before its venue; clearing the id would
      // sync the loss.
      await repos.programs.create(program(venueId: 'v1', venue: 'The hall'));
      await repos.programs.softDelete('p1', at: trashed);
      await db.customStatement("DELETE FROM venues WHERE id = 'v1'");

      await repos.programs.restore('p1', at: restored);

      final back = (await repos.programs.getById('p1'))!;
      expect(back.venueId, 'v1');
      await repos.programs.update(back.copyWith(title: 'Edited'));
    });

    test(
      'neither restores nor revives for a permanently deleted program',
      () async {
        await repos.programs.create(program(venueId: 'v1'));
        await repos.programs.softDelete('p1', at: trashed);
        await repos.venues.delete('v1', at: referenceDeleted);
        await markPermanentlyDeleted('programs', 'p1');

        await repos.programs.restore('p1', at: restored);

        expect(await repos.programs.getById('p1'), isNull);
        expect(await rawStamp('programs', 'deleted_at', 'p1'), 0);
        expect(await repos.venues.getById('v1'), isNull);
      },
    );
  });

  group('duplicating a program whose venue is gone (LIFE-4)', () {
    Future<void> seedProgramWithDeletedVenue() async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Grange'),
        at: created,
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Spring dance',
          venue: 'The hall',
          venueId: 'v1',
          createdAt: created,
          updatedAt: created,
        ),
      );
      await repos.programs.softDelete('p1', at: trashed);
      await repos.venues.delete('v1', at: referenceDeleted);
      // How a program came back without its venue before restore revived it.
      await repos.programs.restore('p1', at: restored, reviveReferences: false);
    }

    var slot = 0;
    String newSlotId() => 's${slot++}';

    test('copies everything but the dead venue link', () async {
      await seedProgramWithDeletedVenue();

      final copy = await repos.programs.duplicate(
        id: 'p1',
        newId: 'p2',
        newSlotId: newSlotId,
        now: restored,
      );

      expect(copy.venueId, isNull);
      expect(copy.venue, 'The hall');
      expect((await repos.programs.getById('p2'))!.venueId, isNull);
      expect(
        await repos.venues.getById('v1'),
        isNull,
        reason: 'duplicating is not a request to undo the venue delete',
      );
      expect((await repos.programs.getById('p1'))!.venueId, 'v1');
    });

    test('still copies a live venue link', () async {
      await repos.venues.upsert(
        Venue(id: 'v1', name: 'Grange'),
        at: created,
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Spring dance',
          venueId: 'v1',
          createdAt: created,
          updatedAt: created,
        ),
      );

      final copy = await repos.programs.duplicate(
        id: 'p1',
        newId: 'p2',
        newSlotId: newSlotId,
        now: restored,
      );

      expect(copy.venueId, 'v1');
    });
  });
}
