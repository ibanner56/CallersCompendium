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

  test('keeps distinct archive ids for identical published sources', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
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
          sourceCitations: [
            SourceCitation(sourceId: 's1'),
            SourceCitation(sourceId: 's2'),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
      publishedSources: [
        PublishedSource(id: 's1', title: 'Same source'),
        PublishedSource(id: 's2', title: 'Same source'),
      ],
    );
    var nextId = 0;

    final result = await importer.import(
      encodeArchive(archive),
      archive,
      now: _now,
      newId: () => 'receiver-${++nextId}',
    );

    final imported = (await dances.listAll()).single;
    expect(imported.sourceCitations.map((c) => c.sourceId), [
      'receiver-1',
      'receiver-2',
    ]);
    expect(result.importedMetadataCount, 2);
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

  test('downstream program failure compensates dances and metadata', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final choreographers = ChoreographerRepository(db);
    final programs = _FailingProgramCreateRepository(db);
    final venues = VenueRepository(db);
    final tags = TagRepository(db);
    final sources = PublishedSourceRepository(db);
    final fields = CustomFieldDefRepository(db);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, choreographers),
      programs,
      venues,
      tags: tags,
      sources: sources,
      customFields: fields,
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
      programs: [
        Program(
          id: 'p1',
          title: 'Shared program',
          slots: [ProgramSlot(id: 'slot1', position: 0, danceId: 'd1')],
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

    await expectLater(
      importer.import(
        encodeArchive(archive),
        archive,
        now: _now,
        newId: () => 'receiver-${++nextId}',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await programs.listAll(), isEmpty);
    expect(await dances.listAll(), isEmpty);
    expect(await choreographers.listAll(), isEmpty);
    expect(await tags.listAll(), isEmpty);
    expect(await sources.listAll(), isEmpty);
    expect(await fields.listAll(), isEmpty);
  });

  test('undo preserves metadata linked by a later local dance', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
      tags: TagRepository(db),
      sources: PublishedSourceRepository(db),
      customFields: CustomFieldDefRepository(db),
    );
    final archive = CompendiumArchive(
      exportedAt: _now,
      dances: [
        Dance(
          id: 'shared',
          title: 'Shared dance',
          tagIds: const ['t1', 't2'],
          sourceCitations: [
            SourceCitation(sourceId: 's1'),
            SourceCitation(sourceId: 's2'),
          ],
          customFields: [
            CustomFieldValue(fieldId: 'f1', value: 'yes'),
            CustomFieldValue(fieldId: 'f2', value: 'no'),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
      tags: [
        Tag(id: 't1', name: 'kept'),
        Tag(id: 't2', name: 'removed'),
      ],
      publishedSources: [
        PublishedSource(id: 's1', title: 'Kept source'),
        PublishedSource(id: 's2', title: 'Removed source'),
      ],
      customFields: [
        CustomFieldDef(
          id: 'f1',
          key: 'kept',
          label: 'Kept',
          type: CustomFieldType.text,
        ),
        CustomFieldDef(
          id: 'f2',
          key: 'removed',
          label: 'Removed',
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
    final imported = (await dances.listAll()).single;
    await dances.create(
      Dance(
        id: 'local',
        title: 'Local dance',
        tagIds: [imported.tagIds.first],
        sourceCitations: [imported.sourceCitations.first],
        customFields: [imported.customFields.first],
        createdAt: _now,
        updatedAt: _now,
      ),
    );

    await importer.undo(result);

    expect(await (TagRepository(db)).getById(imported.tagIds.first), isNotNull);
    expect(
      await (PublishedSourceRepository(
        db,
      )).getById(imported.sourceCitations.first.sourceId),
      isNotNull,
    );
    expect(
      await (CustomFieldDefRepository(
        db,
      )).getById(imported.customFields.first.fieldId),
      isNotNull,
    );
    expect(await (TagRepository(db)).getById(imported.tagIds.last), isNull);
    expect(
      await (PublishedSourceRepository(
        db,
      )).getById(imported.sourceCitations.last.sourceId),
      isNull,
    );
    expect(
      await (CustomFieldDefRepository(
        db,
      )).getById(imported.customFields.last.fieldId),
      isNull,
    );
    expect(await dances.getById('local'), isNotNull);
  });

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

class _FailingProgramCreateRepository extends ProgramRepository {
  _FailingProgramCreateRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) =>
      Future.error(StateError('simulated downstream program persist failure'));
}
