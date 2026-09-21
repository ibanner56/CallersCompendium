import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test(
    'published records survive hard-delete and purge entry points',
    () async {
      final stamp = DateTime.utc(2026, 1, 2);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'published-choreographer', name: 'Published'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 'published-tag', name: 'Published'),
        at: stamp,
      );
      await repositories.publishedSources.upsert(
        PublishedSource(id: 'published-source', title: 'Published'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'published-field',
          key: 'published_field',
          label: 'Published',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(id: 'published-level', label: 'Published', position: 0),
        at: stamp,
      );
      await repositories.venues.upsert(
        Venue(id: 'published-venue', name: 'Published'),
        at: stamp,
      );
      await repositories.dances.create(
        Dance(
          id: 'published-dance',
          title: 'Published',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.programs.create(
        Program(
          id: 'published-program',
          title: 'Published',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.settings.set('custom_dialects', const {
        'published': true,
      }, at: stamp);

      await repositories.syncLocal.markPublishedAll(const [
        (
          kind: SyncRecordKind.choreographer,
          recordId: 'published-choreographer',
        ),
        (kind: SyncRecordKind.tag, recordId: 'published-tag'),
        (kind: SyncRecordKind.publishedSource, recordId: 'published-source'),
        (kind: SyncRecordKind.customFieldDef, recordId: 'published-field'),
        (kind: SyncRecordKind.difficultyLevel, recordId: 'published-level'),
        (kind: SyncRecordKind.venue, recordId: 'published-venue'),
        (kind: SyncRecordKind.dance, recordId: 'published-dance'),
        (kind: SyncRecordKind.program, recordId: 'published-program'),
        (kind: SyncRecordKind.setting, recordId: 'custom_dialects'),
      ]);

      await repositories.choreographers.delete(
        'published-choreographer',
        at: stamp.add(const Duration(minutes: 1)),
        permanent: true,
      );
      await repositories.tags.hardDelete(['published-tag']);
      await repositories.publishedSources.hardDelete(['published-source']);
      await repositories.customFieldDefs.hardDelete(['published-field']);
      await repositories.difficultyLevels.hardDelete(['published-level']);
      await repositories.venues.hardDelete(['published-venue']);
      await repositories.dances.hardDelete(['published-dance']);
      await repositories.programs.hardDelete(['published-program']);
      await repositories.settings.remove('custom_dialects', permanent: true);
      expect(
        await repositories.dances.purgeDeleted(
          now: DateTime.utc(2099),
          retention: Duration.zero,
        ),
        0,
      );
      expect(
        await repositories.programs.purgeDeleted(
          now: DateTime.utc(2099),
          retention: Duration.zero,
        ),
        0,
      );

      final choreographer = await (db.select(
        db.choreographers,
      )..where((row) => row.id.equals('published-choreographer'))).getSingle();
      final tag = await (db.select(
        db.tags,
      )..where((row) => row.id.equals('published-tag'))).getSingle();
      final source = await (db.select(
        db.publishedSources,
      )..where((row) => row.id.equals('published-source'))).getSingle();
      final field = await (db.select(
        db.customFieldDefs,
      )..where((row) => row.id.equals('published-field'))).getSingle();
      final level = await (db.select(
        db.difficultyLevels,
      )..where((row) => row.id.equals('published-level'))).getSingle();
      final venue = await (db.select(
        db.venues,
      )..where((row) => row.id.equals('published-venue'))).getSingle();
      final dance = await (db.select(
        db.dances,
      )..where((row) => row.id.equals('published-dance'))).getSingle();
      final program = await (db.select(
        db.programs,
      )..where((row) => row.id.equals('published-program'))).getSingle();
      final setting = await (db.select(
        db.settings,
      )..where((row) => row.key.equals('custom_dialects'))).getSingle();

      expect(choreographer.deletedAt, isNotNull);
      expect(tag.deletedAt, isNotNull);
      expect(source.deletedAt, isNotNull);
      expect(field.deletedAt, isNotNull);
      expect(level.deletedAt, isNotNull);
      expect(venue.deletedAt, isNotNull);
      expect(dance.deletedAt, isNotNull);
      expect(program.deletedAt, isNotNull);
      expect(setting.deletedAt, isNotNull);
    },
  );
}
