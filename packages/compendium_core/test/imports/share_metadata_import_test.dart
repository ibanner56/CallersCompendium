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

  test(
    'adopts a live tag whose name is canonically equivalent (NFC vs NFD)',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final tags = TagRepository(db);
      final sources = PublishedSourceRepository(db);
      final fields = CustomFieldDefRepository(db);
      // Local tag stored in NFC (single precomposed U+00E9).
      expect(
        await tags.upsert(Tag(id: 'local-tag', name: 'café', color: 7)),
        'local-tag',
      );

      // The incoming archive tag carries the NFD spelling (e + combining acute
      // U+0301) under a different id — exactly what a decoded archive delivers,
      // since the codec sanitizes but does not NFC-normalize.
      final result =
          await ShareMetadataImporter(
            tags: tags,
            sources: sources,
            customFields: fields,
          ).commit(
            CompendiumArchive(
              exportedAt: _now,
              tags: [Tag(id: 'archive-tag', name: 'café', color: 9)],
            ),
            now: _now,
            newId: () => 'fresh-tag',
          );

      // Adopted onto the live local row rather than minted as a colliding tag.
      expect(result.tagIdByArchiveId['archive-tag'], 'local-tag');
      expect(result.insertedTagIds, isEmpty);
      // Local row untouched: original NFC name and color preserved.
      final local = (await tags.getById('local-tag'))!;
      expect(local.name, 'café');
      expect(local.color, 0xFF000007);
      expect((await tags.listAll()).length, 1);
    },
  );

  test(
    'adopts a live custom field whose key is canonically equivalent',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = CustomFieldDefRepository(db);
      // Local field key stored NFC (precomposed U+00F6).
      expect(
        await fields.upsert(
          CustomFieldDef(
            id: 'local-field',
            key: 'tempö',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
        ),
        'local-field',
      );

      final result =
          await ShareMetadataImporter(
            tags: TagRepository(db),
            sources: PublishedSourceRepository(db),
            customFields: fields,
          ).commit(
            CompendiumArchive(
              exportedAt: _now,
              customFields: [
                // NFD key (o + combining diaeresis U+0308), otherwise identical
                // to the live local field.
                CustomFieldDef(
                  id: 'archive-field',
                  key: 'tempö',
                  label: 'Tempo',
                  type: CustomFieldType.text,
                ),
              ],
            ),
            now: _now,
            newId: () => 'fresh-field',
          );

      expect(result.fieldIdByArchiveId['archive-field'], 'local-field');
      expect(result.insertedFieldIds, isEmpty);
      expect((await fields.listAll()).single.id, 'local-field');
    },
  );

  test(
    'rejects a canonically-equivalent but incompatible custom-field key',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = CustomFieldDefRepository(db);
      expect(
        await fields.upsert(
          CustomFieldDef(
            id: 'local-field',
            key: 'tempö',
            label: 'Tempo',
            type: CustomFieldType.text,
          ),
        ),
        'local-field',
      );

      // Same canonical key, incompatible type: must raise the precise conflict
      // StateError, not silently adopt and not a raw UNIQUE-collision error.
      await expectLater(
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
                key: 'tempö',
                label: 'Tempo',
                type: CustomFieldType.number,
              ),
            ],
          ),
          now: _now,
          newId: () => 'fresh-field',
        ),
        throwsStateError,
      );
      final local = (await fields.listAll()).single;
      expect(local.id, 'local-field');
      expect(local.type, CustomFieldType.text);
    },
  );

  test('archive decode preserves NFD names (does not compose to NFC)', () {
    // Pins the live gap at the codec boundary: the decoder reaching the planner
    // sanitizes but never NFC-normalizes, so a non-composed incoming name
    // survives verbatim into planning.
    final json = encodeArchive(
      CompendiumArchive(
        exportedAt: _now,
        tags: [Tag(id: 'archive-tag', name: 'café')],
      ),
    );
    final decoded = decodeArchive(json).archive;
    expect(decoded.tags.single.name, 'café');
    expect(decoded.tags.single.name, isNot('café'));
  });

  test(
    'canonical bucket with multiple live raw rows adopts the exact raw match',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      // Two live tags that are canonically equal ("café") but stored in
      // distinct raw forms — the state the normalisation-skip repair leaves
      // behind. Insert raw, because upsert would normalise (and collide).
      await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
        't-nfd',
        'café',
      ]);
      await db.customStatement('INSERT INTO tags (id, name) VALUES (?, ?)', [
        't-nfc',
        'café',
      ]);
      final tags = TagRepository(db);

      final result =
          await ShareMetadataImporter(
            tags: tags,
            sources: PublishedSourceRepository(db),
            customFields: CustomFieldDefRepository(db),
          ).commit(
            CompendiumArchive(
              exportedAt: _now,
              // Incoming exactly matches the NFD row's raw form.
              tags: [Tag(id: 'archive-tag', name: 'café')],
            ),
            now: _now,
            newId: () => 'fresh-tag',
          );

      // Exact raw match wins deterministically; the canonical twin is not
      // chosen by load order, and nothing new is minted.
      expect(result.tagIdByArchiveId['archive-tag'], 't-nfd');
      expect(result.insertedTagIds, isEmpty);
      expect(result.restoredTagIds, isEmpty);
      expect(
        (await tags.listAll()).map((t) => t.id),
        containsAll(['t-nfd', 't-nfc']),
      );
    },
  );

  test(
    'canonical match revives a tombstoned raw variant instead of colliding',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      // A tombstoned tag stored as NFC "café" (deleted_at set).
      await db.customStatement(
        'INSERT INTO tags (id, name, deleted_at) VALUES (?, ?, ?)',
        ['t-nfc', 'café', 1000],
      );
      final tags = TagRepository(db);

      final result =
          await ShareMetadataImporter(
            tags: tags,
            sources: PublishedSourceRepository(db),
            customFields: CustomFieldDefRepository(db),
          ).commit(
            CompendiumArchive(
              exportedAt: _now,
              // NFD spelling: no exact raw match, but canonically equal to the
              // tombstone, so it is revived rather than minted into a collision.
              tags: [Tag(id: 'archive-tag', name: 'café')],
            ),
            now: _now,
            newId: () => 'fresh-tag',
          );

      expect(result.tagIdByArchiveId['archive-tag'], 't-nfc');
      expect(result.insertedTagIds, isEmpty);
      expect(result.restoredTagIds, ['t-nfc']);
      expect(await tags.getById('t-nfc'), isNotNull);
    },
  );
}

class _FailingProgramCreateRepository extends ProgramRepository {
  _FailingProgramCreateRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) =>
      Future.error(StateError('simulated downstream program persist failure'));
}
