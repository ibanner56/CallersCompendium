import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

final _now = DateTime.utc(2026, 1, 1);

void main() {
  test('remaps live metadata collisions without changing local rows', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final tags = TagRepository(db);
    final sources = PublishedSourceRepository(db);
    final fields = CustomFieldDefRepository(db);
    expect(
      await tags.upsert(Tag(id: 'local-tag', name: 'chestnut', color: 7)),
      'local-tag',
    );
    await sources.upsert(
      PublishedSource(id: 's1', title: 'Local source', author: 'Local'),
    );

    final result =
        await ShareMetadataImporter(
          tags: tags,
          sources: sources,
          customFields: fields,
        ).commit(
          CompendiumArchive(
            exportedAt: _now,
            tags: [Tag(id: 'archive-tag', name: 'chestnut', color: 9)],
            publishedSources: [
              PublishedSource(
                id: 's1',
                title: 'Shared source',
                author: 'Shared',
              ),
            ],
          ),
          now: _now,
          newId: () => 'fresh-source',
        );

    expect(result.tagIdByArchiveId['archive-tag'], 'local-tag');
    expect((await tags.getById('local-tag'))!.color, 0xFF000007);
    expect(result.sourceIdByArchiveId['s1'], 'fresh-source');
    expect((await sources.getById('s1'))!.title, 'Local source');
    expect((await sources.getById('fresh-source'))!.title, 'Shared source');
  });

  test(
    'rejects an incompatible live custom-field key before writing',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = CustomFieldDefRepository(db);
      expect(
        await fields.upsert(
          CustomFieldDef(
            id: 'local-field',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
        ),
        'local-field',
      );

      expect(
        () =>
            ShareMetadataImporter(
              tags: TagRepository(db),
              sources: PublishedSourceRepository(db),
              customFields: fields,
            ).commit(
              CompendiumArchive(
                exportedAt: _now,
                customFields: [
                  CustomFieldDef(
                    id: 'archive-field',
                    key: 'tempo',
                    label: 'Tempo',
                    type: CustomFieldType.number,
                  ),
                ],
              ),
              now: _now,
              newId: () => 'fresh',
            ),
        throwsStateError,
      );
      expect((await fields.listAll()).single.id, 'local-field');
    },
  );

  test(
    'archive importer Undo removes metadata created by the import',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, contraTaxonomy);
      final choreographers = ChoreographerRepository(db);
      final programs = ProgramRepository(db);
      final venues = VenueRepository(db);
      final importer = CompendiumArchiveImporter(
        ImportPipeline(dances, choreographers),
        programs,
        venues,
        tags: TagRepository(db),
        sources: PublishedSourceRepository(db),
        customFields: CustomFieldDefRepository(db),
      );
      final archive = CompendiumArchive(
        exportedAt: _now,
        dances: [
          Dance(
            id: 'd1',
            title: 'Shared dance',
            tagIds: const ['t1'],
            sourceCitations: [SourceCitation(sourceId: 's1')],
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'yes')],
            createdAt: _now,
            updatedAt: _now,
          ),
        ],
        tags: [Tag(id: 't1', name: 'shared')],
        publishedSources: [PublishedSource(id: 's1', title: 'Shared source')],
        customFields: [
          CustomFieldDef(
            id: 'f1',
            key: 'teach',
            label: 'Needs teaching',
            type: CustomFieldType.text,
          ),
        ],
      );

      var nextId = 0;
      final result = await importer.import(
        encodeArchive(archive),
        archive,
        now: _now,
        newId: () => 'receiver-${++nextId}',
      );
      expect(result.importedMetadataCount, 3);
      expect(await (TagRepository(db)).listAll(), isNotEmpty);
      expect(await (PublishedSourceRepository(db)).listAll(), isNotEmpty);
      expect(await (CustomFieldDefRepository(db)).listAll(), isNotEmpty);

      await importer.undo(result);

      expect(await (TagRepository(db)).listAll(), isEmpty);
      expect(await (PublishedSourceRepository(db)).listAll(), isEmpty);
      expect(await (CustomFieldDefRepository(db)).listAll(), isEmpty);
      expect(await dances.listAll(), isEmpty);
    },
  );

  test('rejects dangling metadata references before creating rows', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final tags = TagRepository(db);
    final importer = ShareMetadataImporter(
      tags: tags,
      sources: PublishedSourceRepository(db),
      customFields: CustomFieldDefRepository(db),
    );

    expect(
      () => importer.commit(
        CompendiumArchive(
          exportedAt: _now,
          dances: [
            Dance(
              id: 'd1',
              title: 'Broken',
              tagIds: const ['missing'],
              createdAt: _now,
              updatedAt: _now,
            ),
          ],
        ),
        now: _now,
        newId: () => 'new',
      ),
      throwsStateError,
    );
    expect(await tags.listAll(), isEmpty);
  });
}
