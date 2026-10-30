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
      repositories: CompendiumRepositories(db, contraTaxonomy),
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

  test('imports a field whose type differs under <key>_2 with a note, leaving '
      'the local field alone (INTAKE-2)', () async {
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

    final result =
        await ShareMetadataImporter(
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
                label: 'Their tempo',
                type: CustomFieldType.number,
              ),
            ],
          ),
          now: _now,
          newId: () => 'fresh',
        );

    expect(result.fieldIdByArchiveId['archive-field'], 'fresh');
    expect(result.insertedFieldIds, ['fresh']);
    final local = (await fields.getById('local-field'))!;
    expect(local.key, 'tempo');
    expect(local.type, CustomFieldType.text);
    final added = (await fields.getById('fresh'))!;
    expect(added.key, 'tempo_2');
    expect(added.type, CustomFieldType.number);
    expect(added.label, 'Their tempo');
    final note = result.issues.single;
    expect(note.code, 'archive_custom_field_key_conflict');
    expect(note.severity, ImportIssueSeverity.warning);
    // Names the receiver's own field, never the file's label.
    expect(note.data, {'label': 'Tempo', 'key': 'tempo_2'});
  });

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
        repositories: CompendiumRepositories(db, contraTaxonomy),
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
      repositories: CompendiumRepositories(db, contraTaxonomy),
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
      repositories: CompendiumRepositories(db, contraTaxonomy),
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

  test('a canonically-equivalent but incompatible key goes under the local '
      'key plus _2', () async {
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

    // Same canonical key (NFD here, NFC locally), incompatible type: a new
    // field under the receiver's own key plus `_2`, not a raw
    // UNIQUE-collision error and not an adoption.
    final result =
        await ShareMetadataImporter(
          tags: TagRepository(db),
          sources: PublishedSourceRepository(db),
          customFields: fields,
        ).commit(
          CompendiumArchive(
            exportedAt: _now,
            customFields: [
              CustomFieldDef(
                id: 'archive-field',
                key: 'tempö',
                label: 'Tempo',
                type: CustomFieldType.number,
              ),
            ],
          ),
          now: _now,
          newId: () => 'fresh-field',
        );
    final local = (await fields.getById('local-field'))!;
    expect(local.type, CustomFieldType.text);
    expect((await fields.getById('fresh-field'))!.key, 'tempö_2');
    expect(result.issues.single.data['key'], 'tempö_2');
  });

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

  test('in a mixed batch, a created dance keeps the deleted tag it revived '
      'while a re-imported one\'s goes back', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final tags = TagRepository(db);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
      repositories: CompendiumRepositories(db, contraTaxonomy),
      tags: tags,
      sources: PublishedSourceRepository(db),
      customFields: CustomFieldDefRepository(db),
    );
    Dance dance(String id, String tag) => Dance(
      id: id,
      title: 'Dance $id',
      tagIds: [tag],
      createdAt: _now,
      updatedAt: _now,
    );
    final first = CompendiumArchive(
      exportedAt: _now,
      dances: [dance('old', 't1')],
      tags: [Tag(id: 't1', name: 'chestnut')],
    );
    var nextId = 0;
    String newId() => 'receiver-${++nextId}';
    await importer.import(encodeArchive(first), first, now: _now, newId: newId);
    final later = _now.add(const Duration(days: 1));
    await tags.delete((await tags.listAll()).single.id, at: later);
    final oak = await tags.upsert(
      Tag(id: 'oak', name: 'oak'),
      at: later,
    );
    await tags.delete(oak, at: later);

    final mixed = CompendiumArchive(
      exportedAt: _now,
      dances: [dance('old', 't1'), dance('fresh', 't2')],
      tags: [
        Tag(id: 't1', name: 'chestnut'),
        Tag(id: 't2', name: 'oak'),
      ],
    );
    final result = await importer.import(
      encodeArchive(mixed),
      mixed,
      now: _now.add(const Duration(days: 2)),
      newId: newId,
    );

    expect(
      result.danceSession.records.map((r) => r.action),
      unorderedEquals([CommitAction.reimport, CommitAction.create]),
    );
    expect([for (final t in await tags.listAll()) t.name], ['oak']);
    final created = await dances.getById(
      result.danceSession.records
          .singleWhere((r) => r.action == CommitAction.create)
          .danceId!,
    );
    expect(created!.tagIds, [oak]);
    expect(result.metadata!.restoredTagIds, [oak]);
  });

  test('a row that fails after the metadata commit leaves nothing it needed '
      'behind', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final tags = TagRepository(db);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
      repositories: CompendiumRepositories(db, contraTaxonomy),
      tags: tags,
      sources: PublishedSourceRepository(db),
      customFields: CustomFieldDefRepository(db),
    );
    final chestnut = await tags.upsert(Tag(id: 'mine', name: 'chestnut'));
    await tags.delete(chestnut, at: _now);
    final archive = CompendiumArchive(
      exportedAt: _now,
      dances: [
        Dance(
          id: 'shared',
          title: 'Shared dance',
          tagIds: const ['t1', 't2'],
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
      tags: [
        Tag(id: 't1', name: 'chestnut'),
        Tag(id: 't2', name: 'brand new'),
      ],
    );
    final planned = await importer.plan(encodeArchive(archive));
    // Linked onto a dance that is gone by the time the commit runs: the
    // pipeline records the row as failed, after its tags were committed.
    final batch = ImportBatchResult(
      records: [
        ImportRecordPlan(
          draft: planned.records.single.draft,
          verdict: DedupeVerdict.ambiguous(const []),
        ),
      ],
    );
    var nextId = 0;

    final result = await importer.commit(
      batch,
      archive,
      now: _now.add(const Duration(days: 1)),
      newId: () => 'receiver-${++nextId}',
      resolutions: {0: DedupeResolution.link('gone')},
    );

    expect(result.danceSession.records.single.succeeded, isFalse);
    expect(await tags.listAll(), isEmpty);
    expect(
      [for (final t in await tags.listAllWithDeleted()) t.tag.name],
      ['chestnut'],
    );
    expect(result.metadata!.restoredTagIds, isEmpty);
    expect(result.metadata!.insertedTagIds, isEmpty);
  });

  test('a re-import takes back the tags, fields and sources it revived or '
      'created, since it writes none of them (INTAKE-7)', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dances = DanceRepository(db, contraTaxonomy);
    final tags = TagRepository(db);
    final sources = PublishedSourceRepository(db);
    final fields = CustomFieldDefRepository(db);
    final importer = CompendiumArchiveImporter(
      ImportPipeline(dances, ChoreographerRepository(db)),
      ProgramRepository(db),
      VenueRepository(db),
      repositories: CompendiumRepositories(db, contraTaxonomy),
      tags: tags,
      sources: sources,
      customFields: fields,
    );
    CompendiumArchive share({bool withNewTag = false}) => CompendiumArchive(
      exportedAt: _now,
      dances: [
        Dance(
          id: 'shared',
          title: 'Shared dance',
          tagIds: ['t1', if (withNewTag) 't2'],
          sourceCitations: [SourceCitation(sourceId: 's1')],
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'yes')],
          createdAt: _now,
          updatedAt: _now,
        ),
      ],
      tags: [
        Tag(id: 't1', name: 'chestnut'),
        if (withNewTag) Tag(id: 't2', name: 'brand new'),
      ],
      publishedSources: [PublishedSource(id: 's1', title: 'Shared source')],
      customFields: [
        CustomFieldDef(
          id: 'f1',
          key: 'swing',
          label: 'Swing',
          type: CustomFieldType.text,
        ),
      ],
    );
    var nextId = 0;
    String newId() => 'receiver-${++nextId}';

    await importer.import(
      encodeArchive(share()),
      share(),
      now: _now,
      newId: newId,
    );
    // The receiver drops the field value and citation, then deletes the
    // field, the source and the tag. A deleted tag keeps its join to the
    // dance, hidden.
    final imported = (await dances.listAll()).single;
    final tagId = imported.tagIds.single;
    final sourceId = imported.sourceCitations.single.sourceId;
    final fieldId = imported.customFields.single.fieldId;
    await dances.update(
      imported.copyWith(
        sourceCitations: const [],
        customFields: const [],
        updatedAt: _now.add(const Duration(days: 1)),
      ),
    );
    final later = _now.add(const Duration(days: 2));
    await fields.delete(fieldId, at: later);
    await sources.delete(sourceId, at: later);
    await tags.delete(tagId, at: later);
    Future<(DateTime?, DateTime?, DateTime?)> stampsOf(String id) async {
      final row = await (db.select(
        db.tags,
      )..where((t) => t.id.equals(id))).getSingle();
      return (row.deletedAt, row.existenceAt, row.updatedAt);
    }

    final deletedStamps = await stampsOf(tagId);

    final again = share(withNewTag: true);
    final result = await importer.import(
      encodeArchive(again),
      again,
      now: _now.add(const Duration(days: 3)),
      newId: newId,
    );

    expect(result.danceSession.records.single.action, CommitAction.reimport);
    expect(await tags.listAll(), isEmpty);
    expect(await sources.listAll(), isEmpty);
    expect(await fields.listAll(), isEmpty);
    expect((await dances.getById(imported.id))!.tagIds, isEmpty);
    // Never revived, so its deletion keeps its own stamps: a new one would
    // outrank a peer's later revival in sync.
    expect(await stampsOf(tagId), deletedStamps);
    // The tag the share would have created never existed.
    expect(
      [for (final t in await tags.listAllWithDeleted()) t.tag.name],
      ['chestnut'],
    );
    expect(result.metadata!.insertedTagIds, isEmpty);
    expect(result.metadata!.restoredTagIds, isEmpty);
    expect(result.metadata!.restoredFieldIds, isEmpty);
    expect(result.metadata!.restoredSourceIds, isEmpty);

    // Nothing is left for undo to revert, and it does not throw.
    await importer.undo(result);
    expect(await tags.listAll(), isEmpty);
  });
}

class _FailingProgramCreateRepository extends ProgramRepository {
  _FailingProgramCreateRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) =>
      Future.error(StateError('simulated downstream program persist failure'));
}
