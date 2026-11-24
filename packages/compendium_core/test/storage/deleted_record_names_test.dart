import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// `CompendiumRepositories.deletedRecordNames`: the name of a record a saved
/// search still refers to after it was deleted, so a notice can say "uses the
/// tag *Bouncey*, which was deleted" (#2325). Only tombstoned rows answer.
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  test(
    'a deleted tag is named; a live one and an unknown id are not',
    () async {
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't-gone', name: 'Bouncey'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't-live', name: 'Smooth'));
      await repos.tags.delete('t-gone');

      final names = await repos.deletedRecordNames(SyncRecordKind.tag, [
        't-gone',
        't-live',
        'never-was',
      ]);

      expect(names, {'t-gone': 'Bouncey'});
    },
  );

  test('authors, sources, venues, levels and custom fields', () async {
    final _ = await repos.choreographers.upsert(
      Choreographer(id: 'a1', name: 'Mary Wesley'),
    );
    await repos.choreographers.delete('a1');
    await repos.publishedSources.upsert(
      PublishedSource(id: 's1', title: 'Give and Take'),
    );
    await repos.publishedSources.delete('s1');
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await repos.venues.delete('v1');
    final level = await repos.difficultyLevels.createCustom(
      label: 'Wobbly',
      position: 99,
    );
    await repos.difficultyLevels.delete(level.id);
    final fieldId = await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'tempo',
        label: 'Tempo',
        type: CustomFieldType.text,
      ),
    );
    await repos.customFieldDefs.delete(fieldId);

    expect(
      await repos.deletedRecordNames(SyncRecordKind.choreographer, ['a1']),
      {'a1': 'Mary Wesley'},
    );
    expect(
      await repos.deletedRecordNames(SyncRecordKind.publishedSource, ['s1']),
      {'s1': 'Give and Take'},
    );
    expect(await repos.deletedRecordNames(SyncRecordKind.venue, ['v1']), {
      'v1': 'Grange Hall',
    });
    expect(
      await repos.deletedRecordNames(SyncRecordKind.difficultyLevel, [
        level.id,
      ]),
      {level.id: 'Wobbly'},
    );
    expect(
      await repos.deletedRecordNames(SyncRecordKind.customFieldDef, [fieldId]),
      {fieldId: 'Tempo'},
    );
  });

  test('another kind, or no ids, names nothing and reads nothing', () async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Bouncey'));
    await repos.tags.delete('t1');

    // The id belongs to a tag, not an author.
    expect(
      await repos.deletedRecordNames(SyncRecordKind.choreographer, ['t1']),
      isEmpty,
    );
    expect(
      await repos.deletedRecordNames(SyncRecordKind.dance, ['t1']),
      isEmpty,
    );
    expect(
      await repos.deletedRecordNames(SyncRecordKind.tag, const []),
      isEmpty,
    );
  });

  test('a live record of every kind is not named', () async {
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Live tag'));
    final _ = await repos.choreographers.upsert(
      Choreographer(id: 'a1', name: 'Live author'),
    );
    await repos.publishedSources.upsert(
      PublishedSource(id: 's1', title: 'Live source'),
    );
    await repos.venues.upsert(Venue(id: 'v1', name: 'Live hall'));
    final level = await repos.difficultyLevels.createCustom(
      label: 'Live level',
      position: 99,
    );
    final fieldId = await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'tempo',
        label: 'Live field',
        type: CustomFieldType.text,
      ),
    );

    for (final (kind, id) in [
      (SyncRecordKind.tag, 't1'),
      (SyncRecordKind.choreographer, 'a1'),
      (SyncRecordKind.publishedSource, 's1'),
      (SyncRecordKind.venue, 'v1'),
      (SyncRecordKind.difficultyLevel, level.id),
      (SyncRecordKind.customFieldDef, fieldId),
    ]) {
      expect(
        await repos.deletedRecordNames(kind, [id]),
        isEmpty,
        reason: kind.name,
      );
    }
  });
}
