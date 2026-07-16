import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Seeds [repos] with a representative dataset spanning every entity type and
/// their joins, so the export/restore round-trip is exercised end to end.
Future<void> _seed(CompendiumRepositories repos) async {
  await repos.publishedSources.upsert(
    PublishedSource(
      id: 's1',
      title: 'Zesty Contras',
      author: 'Larry',
      year: 1983,
    ),
  );
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Alice', email: 'alice@example.com'),
  );
  await repos.choreographers.upsert(
    Choreographer(id: 'c2', name: 'Traditional'),
  );
  await repos.tags.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF112233));
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'f1',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    ),
  );
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'f2',
      key: 'difficulty',
      label: 'Difficulty',
      type: CustomFieldType.number,
    ),
  );

  // Metadata-only stub and a soft-deleted dance (created before d1, which
  // links to d2 via a relatedDance link).
  await repos.dances.create(
    Dance(
      id: 'd2',
      title: 'Stub',
      createdAt: DateTime.utc(2026, 1, 3),
      updatedAt: DateTime.utc(2026, 1, 3),
    ),
  );
  await repos.dances.create(
    Dance(
      id: 'd3',
      title: 'Deleted',
      createdAt: DateTime.utc(2026, 1, 4),
      updatedAt: DateTime.utc(2026, 1, 4),
      deletedAt: DateTime.utc(2026, 1, 5),
    ),
  );

  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Full Dance',
      authorIds: const ['c1', 'c2'],
      formation: const Formation(FormationShape.becketCw, detail: 'variant'),
      progression: Progression.double,
      phraseStructure: '6*8*2',
      figures: [
        Figure(move: 'swing', params: {'who': 'partner', 'beats': 16}),
        Figure(move: customMove, params: {'text': 'weave', 'beats': 8}),
      ],
      hook: 'zesty',
      callingNotes: 'teach it',
      level: DanceLevel.intermediate,
      rating: 4,
      tunes: const ['Reel'],
      customFields: [
        CustomFieldValue(fieldId: 'f1', value: 'New England'),
        CustomFieldValue(fieldId: 'f2', value: 3),
      ],
      tagIds: const ['t1'],
      links: [
        DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://v.example'),
        DanceLink(id: 'l2', kind: LinkKind.relatedDance, targetDanceId: 'd2'),
      ],
      sourceCitations: [SourceCitation(sourceId: 's1', page: '10')],
      provenance: Provenance(
        source: ProvenanceSource.callersbox,
        externalId: '3418',
        importedAt: DateTime.utc(2025, 1, 1),
        permission: 'full',
        rawPayload: '{"id":3418}',
      ),
      composedOn: PartialDate(1990),
      revisedOn: PartialDate(2001, 6),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    ),
  );

  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Spring Fling',
      eventDate: DateTime.utc(2026, 5, 1),
      venue: 'Grange',
      band: 'Fiddleheads',
      caller: 'Alice',
      dancerLevel: 'intermediate',
      notes: 'notes',
      status: ProgramStatus.performed,
      slots: [
        ProgramSlot(
          id: 'sl1',
          position: 0,
          danceId: 'd1',
          plannedMinutes: 12,
          performedAt: DateTime.utc(2026, 5, 1, 20),
        ),
        ProgramSlot(id: 'sl2', position: 1, text: 'break'),
      ],
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 2),
    ),
  );
  await repos.programs.create(
    Program(
      id: 'p2',
      title: 'Empty',
      createdAt: DateTime.utc(2026, 4, 3),
      updatedAt: DateTime.utc(2026, 4, 3),
    ),
  );
}

void main() {
  group('ArchiveExporter / ArchiveRestorer', () {
    test(
      'dataset -> export -> restore(replace) -> export is identity',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await _seed(repos);

        // First export of the seeded dataset.
        final export1 = await ArchiveExporter(
          repos,
        ).export(exportedAt: DateTime.utc(2026, 7, 15));
        final json1 = encodeArchive(export1);

        // Restore the archive over the same (already-populated) database.
        final restored = decodeArchive(json1);
        expect(restored.hasErrors, isFalse, reason: restored.errors.join('\n'));
        final result = await ArchiveRestorer(repos).restore(restored.archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // Re-export and compare: the dataset survived the replace unchanged.
        final export2 = await ArchiveExporter(
          repos,
        ).export(exportedAt: DateTime.utc(2026, 7, 15));
        expect(encodeArchive(export2), json1);
      },
    );

    test(
      'replace into an empty database materializes the whole archive',
      () async {
        // Build a source dataset in one database and export it.
        final sourceDb = openTestDatabase();
        addTearDown(sourceDb.close);
        final sourceRepos = CompendiumRepositories(sourceDb, contraTaxonomy);
        await _seed(sourceRepos);
        final archive = await ArchiveExporter(
          sourceRepos,
        ).export(exportedAt: DateTime.utc(2026, 7, 15));
        final sourceJson = encodeArchive(archive);

        // Restore it into a fresh, empty database.
        final targetDb = openTestDatabase();
        addTearDown(targetDb.close);
        final targetRepos = CompendiumRepositories(targetDb, contraTaxonomy);
        final result = await ArchiveRestorer(targetRepos).restore(archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        final reexport = await ArchiveExporter(
          targetRepos,
        ).export(exportedAt: DateTime.utc(2026, 7, 15));
        expect(encodeArchive(reexport), sourceJson);

        // Deep checks: the restored dance keeps figures, joins and provenance.
        final d1 = await targetRepos.dances.getById('d1');
        expect(d1, isNotNull);
        expect(d1!.authorIds, ['c1', 'c2']);
        expect(d1.tagIds, ['t1']);
        expect(d1.figures, hasLength(2));
        expect(d1.customFields, hasLength(2));
        expect(d1.provenance?.rawPayload, '{"id":3418}');
        // Soft-deleted dances are carried through by default.
        final d3 = await targetRepos.dances.getById('d3', includeDeleted: true);
        expect(d3?.isDeleted, isTrue);
      },
    );

    test(
      'replace overwrites pre-existing rows rather than duplicating',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await _seed(repos);

        // A stale row that is NOT in the archive must be gone after a replace.
        await repos.tags.upsert(Tag(id: 'stale', name: 'stale-tag'));
        final archive = await ArchiveExporter(repos).export();
        // The exported archive predates the stale tag only if we re-read; instead
        // build an archive without it explicitly.
        final withoutStale = CompendiumArchive(
          exportedAt: archive.exportedAt,
          dances: archive.dances,
          programs: archive.programs,
          choreographers: archive.choreographers,
          publishedSources: archive.publishedSources,
          customFields: archive.customFields,
          tags: archive.tags.where((t) => t.id != 'stale').toList(),
        );

        await ArchiveRestorer(repos).restore(withoutStale);

        final tags = await repos.tags.listAll();
        expect(tags.map((t) => t.id), isNot(contains('stale')));
        expect(tags.map((t) => t.id), contains('t1'));

        // Dances are not duplicated by the restore.
        final dances = await repos.dances.listAll(includeDeleted: true);
        expect(dances.map((d) => d.id).toList()..sort(), ['d1', 'd2', 'd3']);
      },
    );

    test('merge layers the archive onto existing rows by id', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);

      // Pre-existing row that must survive a merge.
      await repos.tags.upsert(Tag(id: 'keep', name: 'keep-me'));
      await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        tags: [Tag(id: 't1', name: 'chestnut')],
      );

      final result = await ArchiveRestorer(
        repos,
      ).restore(archive, mode: RestoreMode.merge);
      expect(result.hasErrors, isFalse);

      final tagIds = (await repos.tags.listAll()).map((t) => t.id).toSet();
      expect(tagIds, containsAll(<String>['keep', 't1']));
    });
  });
}
