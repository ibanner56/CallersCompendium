import 'dart:convert';

// A full backup must carry a deleted tag and the `dance_tags` rows that
// `TagRepository.delete` deliberately retains, so that restoring the tag after
// a backup/restore round trip brings its dances back.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

void main() {
  final t0 = DateTime.utc(2026, 5, 1, 12);
  final exportedAt = DateTime.utc(2026, 7, 15);

  Dance dance(String id, {List<String> tagIds = const []}) => Dance(
    id: id,
    title: id,
    figures: [],
    tagIds: tagIds,
    createdAt: t0,
    updatedAt: t0,
  );

  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  /// Tag `t1` on live dance `d1` and tombstoned dance `d2`, then deleted.
  Future<void> seedDeletedTag() async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Easy', color: 0xFF112233));
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't2', name: 'Live'));
    await repos.dances.create(dance('d1', tagIds: const ['t1', 't2']));
    await repos.dances.create(dance('d2', tagIds: const ['t1']));
    await repos.dances.softDelete('d2', at: t0.add(const Duration(minutes: 1)));
    await repos.tags.delete('t1', at: t0.add(const Duration(minutes: 2)));
  }

  /// Backup-mode JSON round trip into a fresh database, replace restore.
  Future<CompendiumRepositories> roundTrip(CompendiumRepositories from) async {
    final archive = await ArchiveExporter(from).export(exportedAt: exportedAt);
    final json = encodeArchive(archive, mode: ArchiveSerializationMode.backup);
    final decoded = decodeArchive(json);
    expect(decoded.errors, isEmpty);
    final targetDb = openTestDatabase();
    addTearDown(targetDb.close);
    final target = CompendiumRepositories(targetDb, contraTaxonomy);
    final result = await ArchiveRestorer(target).restore(decoded.archive);
    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    return target;
  }

  test(
    'replace restore brings back the tombstone and the retained joins',
    () async {
      await seedDeletedTag();

      final target = await roundTrip(repos);

      final tags = await target.tags.listAllWithDeleted();
      expect(
        {for (final t in tags) t.tag.id: t.deleted},
        {'t1': true, 't2': false},
        reason: 'the deleted tag must still exist, as a tombstone',
      );
      expect(tags.firstWhere((t) => t.tag.id == 't1').tag.color, 0xFF112233);
      expect((await target.dances.getById('d1'))!.tagIds, ['t2']);

      await target.tags.restore('t1', at: DateTime.utc(2026, 8));
      expect((await target.dances.getById('d1'))!.tagIds, ['t2', 't1']);
      expect(
        (await target.dances.getById('d2', includeDeleted: true))!.tagIds,
        ['t1'],
        reason: 'a tombstoned dance keeps its retained join too',
      );
    },
  );

  test(
    'restore reports progress ending at the total and counts deleted tags',
    () async {
      await seedDeletedTag();
      final archive = await ArchiveExporter(
        repos,
      ).export(exportedAt: exportedAt);
      // 2 dances, 1 live tag, 1 tombstoned tag carrying a retained join.
      expect(archive.dances, hasLength(2));
      expect(archive.tags, hasLength(1));
      expect(archive.deletedTags.single.danceIds, isNotEmpty);

      final targetDb = openTestDatabase();
      addTearDown(targetDb.close);
      final target = CompendiumRepositories(targetDb, contraTaxonomy);
      final calls = <(int, int)>[];
      final result = await ArchiveRestorer(
        target,
      ).restore(archive, onProgress: (done, total) => calls.add((done, total)));
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

      // Every written entity counts once; each tombstoned tag counts twice
      // (its row, then its retained-join pass).
      final expectedTotal =
          archive.difficultyLevels.length +
          archive.publishedSources.length +
          archive.choreographers.length +
          archive.tags.length +
          archive.deletedTags.length * 2 +
          archive.customFields.length +
          archive.dances.length +
          archive.venues.length +
          archive.programs.length;
      expect(calls.first, (0, expectedTotal));
      expect(calls.last, (expectedTotal, expectedTotal));
      expect(calls.length, expectedTotal + 1);
      for (var i = 1; i < calls.length; i++) {
        expect(calls[i].$1, calls[i - 1].$1 + 1, reason: 'monotonic by one');
        expect(calls[i].$2, expectedTotal, reason: 'total never changes');
      }
    },
  );

  test('the restored tombstone is stamped causally, not left live', () async {
    await seedDeletedTag();
    final target = await roundTrip(repos);
    expect(await target.tags.getById('t1'), isNull);
    expect(await target.tags.listAll(), hasLength(1));
  });

  test('the stamp is v7 only when a tombstoned tag exists', () async {
    await seedDeletedTag();
    final withTombstone = await ArchiveExporter(
      repos,
    ).export(exportedAt: exportedAt);
    expect(
      requiredSchemaVersion(withTombstone),
      archiveSchemaVersionDeletedTags,
    );

    await repos.tags.restore('t1', at: DateTime.utc(2026, 8));
    final without = await ArchiveExporter(repos).export(exportedAt: exportedAt);
    expect(without.deletedTags, isEmpty);
    expect(
      requiredSchemaVersion(without),
      lessThan(archiveSchemaVersionDeletedTags),
    );
  });

  test('share mode never reveals a deleted tag', () async {
    await seedDeletedTag();
    final archive = await ArchiveExporter(repos).export(exportedAt: exportedAt);
    expect(archive.deletedTags, hasLength(1));

    final shared = encodeArchive(archive);
    expect(shared, isNot(contains('deletedTags')));
    expect(shared, isNot(contains('Easy')));
    expect(
      (jsonDecode(shared) as Map<String, Object?>)['schemaVersion'],
      lessThan(archiveSchemaVersionDeletedTags),
    );
  });

  test('a backup without deleted items omits the tombstones', () async {
    await seedDeletedTag();
    final archive = await ArchiveExporter(
      repos,
    ).export(exportedAt: exportedAt, includeDeleted: false);
    expect(archive.deletedTags, isEmpty);
  });

  test('merge restore does not tombstone a tag the user has live', () async {
    await seedDeletedTag();
    final archive = await ArchiveExporter(repos).export(exportedAt: exportedAt);

    final targetDb = openTestDatabase();
    addTearDown(targetDb.close);
    final target = CompendiumRepositories(targetDb, contraTaxonomy);
    // ignore: unused_result
    await target.tags.upsert(Tag(id: 't1', name: 'Easy'));
    await target.dances.create(dance('d1', tagIds: const ['t1']));

    final result = await ArchiveRestorer(
      target,
    ).restore(archive, mode: RestoreMode.merge);

    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    expect((await target.tags.getById('t1'))?.name, 'Easy');
    expect(
      (await target.tags.listAllWithDeleted())
          .firstWhere((t) => t.tag.id == 't1')
          .deleted,
      isFalse,
    );
  });

  test('merge restore keeps a live tag that shares only the id', () async {
    await seedDeletedTag();
    final archive = await ArchiveExporter(repos).export(exportedAt: exportedAt);

    final targetDb = openTestDatabase();
    addTearDown(targetDb.close);
    final target = CompendiumRepositories(targetDb, contraTaxonomy);
    // Same id as the archived tombstone, different name: only the id guard
    // in `restoreArchivedTombstone` protects this row.
    // ignore: unused_result
    await target.tags.upsert(Tag(id: 't1', name: 'Renamed'));

    final result = await ArchiveRestorer(
      target,
    ).restore(archive, mode: RestoreMode.merge);

    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    expect((await target.tags.getById('t1'))?.name, 'Renamed');
  });

  test(
    'a live name holder blocks a tombstone that holds only the id',
    () async {
      final at = DateTime.utc(2026, 7);
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'Old'));
      await repos.tags.delete('t1', at: at);
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't2', name: 'Easy'));

      final adopted = await repos.tags.restoreArchivedTombstone(
        Tag(id: 't1', name: 'Easy'),
        at: at,
      );

      expect(adopted, isNull);
    },
  );

  test('a retained join naming a dance that is not there is ignored', () async {
    final archive = CompendiumArchive(
      exportedAt: exportedAt,
      deletedTags: [
        ArchivedDeletedTag(
          tag: Tag(id: 't1', name: 'Easy'),
          deletedAt: t0,
          danceIds: const ['ghost'],
        ),
      ],
    );

    final result = await ArchiveRestorer(repos).restore(archive);

    expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));
    expect((await repos.tags.listAllWithDeleted()).single.deleted, isTrue);
    expect(await repos.tags.isInUse('t1'), isFalse);
  });

  test('a malformed deletedTags entry is reported, not fatal', () {
    final result = decodeArchive(
      '{"schemaVersion":7,"exportedAt":"2026-07-15T00:00:00Z",'
      '"deletedTags":[{"id":"t1","name":"Easy"},'
      '{"id":"t2","name":"Ok","deletedAt":"2026-05-01T12:00:00Z",'
      '"danceIds":["d1"]}]}',
    );
    expect(result.errors, hasLength(1));
    expect(result.errors.single.entityType, 'deletedTag');
    expect(result.archive.deletedTags.single.tag.id, 't2');
    expect(result.archive.deletedTags.single.danceIds, ['d1']);
  });
}
