import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
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
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Alice', email: 'alice@example.com'),
  );
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'c2', name: 'Traditional'),
  );
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'chestnut', color: 0xFF112233));
  // ignore: unused_result
  await repos.customFieldDefs.upsert(
    CustomFieldDef(
      id: 'f1',
      key: 'origin',
      label: 'Origin',
      type: CustomFieldType.text,
    ),
  );
  // ignore: unused_result
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
        Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
        testFigure(move: customMove, params: {'text': 'weave', 'beats': 8}),
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
      provenance: Provenance(
        source: ProvenanceSource.callersCompanion,
        externalId: 'usr-9921',
        importedAt: DateTime.utc(2025, 4, 1, 8, 0, 0),
      ),
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
        // Program provenance round-trips too (issue #610: this was silently
        // dropped by the archive codec).
        final p1 = await targetRepos.programs.getById('p1');
        expect(p1?.provenance?.source, ProvenanceSource.callersCompanion);
        expect(p1?.provenance?.externalId, 'usr-9921');
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
        // ignore: unused_result
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

    test(
      'export runs its seven entity reads inside a single transaction',
      () async {
        // Regression test for #615: export() used to issue seven
        // independently-snapshotted reads with no enclosing transaction, so a
        // concurrent write between any two of them could produce a
        // cross-entity-inconsistent archive. Asserting exactly one
        // transaction is begun proves all the reads share one consistent
        // snapshot, matching ArchiveRestorer's existing transactional
        // guarantee.
        final counter = TransactionCounter();
        final db = openCountingTestDatabase(counter);
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);
        await _seed(repos);
        counter.reset();

        await ArchiveExporter(
          repos,
        ).export(exportedAt: DateTime.utc(2026, 7, 15));

        expect(counter.count, 1);
      },
    );

    test('merge layers the archive onto existing rows by id', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);

      // Pre-existing row that must survive a merge.
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 'keep', name: 'keep-me'));
      // ignore: unused_result
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

    test(
      'replace aborts and preserves live data when an entity fails to write',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // Live data that must survive a failed replace restore.
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'live-tag', name: 'Live'));
        await repos.dances.create(
          Dance(
            id: 'live-dance',
            title: 'Live Dance',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // An archive whose dance cannot be written: duplicate authorIds
        // violate the dance_authors primary key (danceId, choreographerId) on
        // the second row — an immediate failure the per-entity guard catches.
        final badArchive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'c1', name: 'Alice')],
          tags: [Tag(id: 'archive-tag', name: 'FromArchive')],
          dances: [
            Dance(
              id: 'archive-dance',
              title: 'Archive Dance',
              authorIds: const ['c1', 'c1'],
              createdAt: DateTime.utc(2026, 1, 2),
              updatedAt: DateTime.utc(2026, 1, 2),
            ),
          ],
        );

        final result = await ArchiveRestorer(repos).restore(badArchive);
        expect(result.hasErrors, isTrue);

        // The whole replace rolled back — the clear was undone — so live data
        // is intact and none of the archive's rows leaked in.
        final tags = (await repos.tags.listAll()).map((t) => t.id).toSet();
        expect(tags, contains('live-tag'));
        expect(tags, isNot(contains('archive-tag')));
        final dances = (await repos.dances.listAll()).map((d) => d.id).toSet();
        expect(dances, contains('live-dance'));
        expect(dances, isNot(contains('archive-dance')));
      },
    );

    test('replace aborts and preserves live data when a slot references a '
        'missing dance (commit-time FK failure)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);

      await repos.dances.create(
        Dance(
          id: 'live-dance',
          title: 'Live Dance',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      // A program slot points at a dance that is in neither the archive nor
      // the (about-to-be-cleared) database: the deferred FK fails at commit.
      final badArchive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        programs: [
          Program(
            id: 'p1',
            title: 'Orphaned',
            slots: [ProgramSlot(id: 'sl1', position: 0, danceId: 'ghost')],
            createdAt: DateTime.utc(2026, 4, 1),
            updatedAt: DateTime.utc(2026, 4, 1),
          ),
        ],
      );

      final result = await ArchiveRestorer(repos).restore(badArchive);
      expect(result.hasErrors, isTrue);

      final dances = (await repos.dances.listAll()).map((d) => d.id).toSet();
      expect(dances, contains('live-dance'));
      final programs = await repos.programs.listAll();
      expect(programs, isEmpty);
    });

    test(
      'merge stays partial-failure tolerant (records, does not abort)',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'keep', name: 'keep-me'));

        // A dance with duplicate authorIds fails to write, but a good tag in the
        // same archive must still land — merge does not abort on per-entity
        // failure the way replace does.
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'c1', name: 'Alice')],
          tags: [Tag(id: 't1', name: 'chestnut')],
          dances: [
            Dance(
              id: 'bad',
              title: 'Bad',
              authorIds: const ['c1', 'c1'],
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        );

        final result = await ArchiveRestorer(
          repos,
        ).restore(archive, mode: RestoreMode.merge);
        expect(result.hasErrors, isTrue);

        final tagIds = (await repos.tags.listAll()).map((t) => t.id).toSet();
        expect(tagIds, containsAll(<String>['keep', 't1']));
      },
    );
  });

  group('venue restore', () {
    Program programWithVenue(String? venueId) => Program(
      id: 'p1',
      title: 'Spring Fling',
      venueId: venueId,
      slots: const [],
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 20),
    );

    test(
      'replace materializes venues and resolves a program.venueId',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          programs: [programWithVenue('v1')],
          venues: [
            Venue(id: 'v1', name: 'Guiding Star Grange', city: 'Greenfield'),
          ],
        );

        final result = await ArchiveRestorer(repos).restore(archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // The venue landed and the program's link resolves (venues load first).
        final venue = await repos.venues.getById('v1');
        expect(venue, isNotNull);
        expect(venue!.city, 'Greenfield');
        final program = await repos.programs.getById('p1');
        expect(program!.venueId, 'v1');
      },
    );

    test('export -> restore round-trips venues and the venueId link', () async {
      final sourceDb = openTestDatabase();
      addTearDown(sourceDb.close);
      final sourceRepos = CompendiumRepositories(sourceDb, contraTaxonomy);
      await sourceRepos.venues.upsert(
        Venue(id: 'v1', name: 'Guiding Star Grange', contact1Email: 'p@x.com'),
      );
      await sourceRepos.programs.create(programWithVenue('v1'));

      final archive = await ArchiveExporter(
        sourceRepos,
      ).export(exportedAt: DateTime.utc(2026, 7, 15));
      final json = encodeArchive(archive);

      final targetDb = openTestDatabase();
      addTearDown(targetDb.close);
      final targetRepos = CompendiumRepositories(targetDb, contraTaxonomy);
      final decoded = decodeArchive(json);
      expect(decoded.hasErrors, isFalse, reason: decoded.errors.join('\n'));
      await ArchiveRestorer(targetRepos).restore(decoded.archive);

      final reexport = await ArchiveExporter(
        targetRepos,
      ).export(exportedAt: DateTime.utc(2026, 7, 15));
      expect(encodeArchive(reexport), json);

      expect(
        (await targetRepos.venues.getById('v1'))!.contact1Email,
        'p@x.com',
      );
      expect((await targetRepos.programs.getById('p1'))!.venueId, 'v1');
    });

    test(
      'a dangling venueId (venue absent everywhere) is nulled, not persisted',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // The program references 'ghost', which is in neither the archive nor db.
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          programs: [programWithVenue('ghost')],
        );

        final result = await ArchiveRestorer(repos).restore(archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        final program = await repos.programs.getById('p1');
        expect(program, isNotNull);
        // The dangling reference is cleared rather than left silently orphaned.
        expect(program!.venueId, isNull);
      },
    );

    test(
      'a venueId resolvable only in the target db is preserved on merge',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // The venue exists in the target database but not in the incoming bundle.
        await repos.venues.upsert(Venue(id: 'v1', name: 'Existing Hall'));

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          programs: [programWithVenue('v1')],
        );

        final result = await ArchiveRestorer(
          repos,
        ).restore(archive, mode: RestoreMode.merge);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // The link survives because the referenced venue resolves against the db.
        expect((await repos.programs.getById('p1'))!.venueId, 'v1');
      },
    );

    test(
      'replace mode calls _clearAll before _load (tombstone-safety pinning)',
      () async {
        // This test pins the first closure that keeps #906 latent: replace mode
        // hard-deletes all rows (via _clearAll) before _load runs, so no
        // tombstone can survive into the load phase to trigger natural-key
        // adoption. If _clearAll were moved after _load or removed, the remap
        // defect would become reachable in the most common user-facing path.
        //
        // Strategy: create a choreographer, soft-delete it (leaving a tombstone),
        // then restore an archive containing a choreographer with the *same name*
        // but a *different id*, in replace mode. After the restore the only
        // choreographer row must carry the archive's id — proving _clearAll
        // destroyed the tombstone before _load ran, and that adoption did not
        // silently remap the id.
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // ignore: unused_result
        await repos.choreographers.upsert(
          Choreographer(id: 'old-id', name: 'Alice'),
        );
        await repos.choreographers.delete('old-id');

        // The archive names the same person with a fresh id.
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'new-id', name: 'Alice')],
          dances: [
            Dance(
              id: 'd1',
              title: 'Pinning Dance',
              authorIds: const ['new-id'],
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        );

        final result = await ArchiveRestorer(repos).restore(archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // _clearAll wiped the tombstone, so 'new-id' landed without adoption.
        final choreographers = await repos.choreographers.listAll();
        expect(choreographers, hasLength(1));
        expect(choreographers.first.id, 'new-id');

        // The dance's authorId must resolve to 'new-id' (no adoption occurred).
        final dance = await repos.dances.getById('d1');
        expect(dance!.authorIds, ['new-id']);
      },
    );

    test(
      'merge mode with tombstone: dance authorId adopts the written id (remap)',
      () async {
        // Regression test for #906: _load discarded the id returned by upsert,
        // so when merge mode encountered a tombstoned choreographer that matched
        // by natural key, the dance's authorId was left pointing at the archived
        // id — a row that no longer exists.
        //
        // This test is the "red run" guard: before the remap fix it fails
        // because the dance's authorId still holds 'archived-id', which is the
        // tombstone's row (now adopted by 'live-id' after upsert).
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // Create a choreographer, then soft-delete it (leaving a tombstone).
        // The tombstone holds id='live-id' and name='Alice'.
        // ignore: unused_result
        await repos.choreographers.upsert(
          Choreographer(id: 'live-id', name: 'Alice'),
        );
        await repos.choreographers.delete('live-id');

        // The archive carries the same choreographer under a different id.
        // In merge mode, upsert will adopt the tombstoned 'live-id' row and
        // return 'live-id' — the dance must reference that id, not 'archived-id'.
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'archived-id', name: 'Alice')],
          dances: [
            Dance(
              id: 'd1',
              title: 'Remap Dance',
              authorIds: const ['archived-id'],
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        );

        final result = await ArchiveRestorer(
          repos,
        ).restore(archive, mode: RestoreMode.merge);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // After the fix, the dance's authorId must resolve to 'live-id'
        // (the id the upsert actually wrote to), not 'archived-id'.
        final dance = await repos.dances.getById('d1');
        expect(dance, isNotNull);
        expect(
          dance!.authorIds,
          ['live-id'],
          reason:
              'dance authorId must be remapped to the written id when '
              'upsert adopted a tombstoned choreographer',
        );
      },
    );

    test(
      'merge mode with tombstone: dance tagId adopts the written id (remap)',
      () async {
        // Analogous to the choreographer remap test — tags have the same
        // natural-key adoption path.
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 'live-tag', name: 'chestnut'));
        await repos.tags.delete('live-tag');

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          tags: [Tag(id: 'archived-tag', name: 'chestnut')],
          dances: [
            Dance(
              id: 'd1',
              title: 'Remap Tag Dance',
              tagIds: const ['archived-tag'],
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        );

        final result = await ArchiveRestorer(
          repos,
        ).restore(archive, mode: RestoreMode.merge);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        final dance = await repos.dances.getById('d1');
        expect(dance, isNotNull);
        expect(
          dance!.tagIds,
          ['live-tag'],
          reason:
              'dance tagId must be remapped to the written id when '
              'upsert adopted a tombstoned tag',
        );
      },
    );

    test('merge mode with tombstone: dance customFieldValue fieldId adopts the '
        'written id (remap)', () async {
      // Analogous to the choreographer remap test — custom field defs have
      // the same natural-key adoption path, and CustomFieldValue.fieldId
      // must be remapped too.
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);

      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'live-field',
          key: 'origin',
          label: 'Origin',
          type: CustomFieldType.text,
        ),
      );
      await repos.customFieldDefs.delete('live-field');

      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        customFields: [
          CustomFieldDef(
            id: 'archived-field',
            key: 'origin',
            label: 'Origin',
            type: CustomFieldType.text,
          ),
        ],
        dances: [
          Dance(
            id: 'd1',
            title: 'Remap Field Dance',
            customFields: [
              CustomFieldValue(fieldId: 'archived-field', value: 'Vermont'),
            ],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final result = await ArchiveRestorer(
        repos,
      ).restore(archive, mode: RestoreMode.merge);
      expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

      final dance = await repos.dances.getById('d1');
      expect(dance, isNotNull);
      expect(
        dance!.customFields.map((v) => v.fieldId).toList(),
        ['live-field'],
        reason:
            'customFieldValue.fieldId must be remapped to the written id '
            'when upsert adopted a tombstoned custom field def',
      );
    });

    test(
      'resolves every venueId from one preloaded set (no N+1 on restore)',
      () async {
        final counter = VenueSelectCounter();
        final db = openCountingTestDatabase(counter);
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);

        Program p(String id, String? venueId) => Program(
          id: id,
          title: 'P $id',
          venueId: venueId,
          slots: const [],
          createdAt: DateTime.utc(2026, 4, 1),
          updatedAt: DateTime.utc(2026, 4, 20),
        );
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          venues: [
            Venue(id: 'v1', name: 'Grange A'),
            Venue(id: 'v2', name: 'Grange B'),
          ],
          // Two venues shared across several programs, one venue-less program and
          // one dangling ref — the whole phase must resolve from one snapshot.
          programs: [
            p('p1', 'v1'),
            p('p2', 'v2'),
            p('p3', 'v1'),
            p('p4', null),
            p('p5', 'ghost'),
          ],
        );

        counter.reset();
        final result = await ArchiveRestorer(repos).restore(archive);
        expect(result.hasErrors, isFalse, reason: result.errors.join('\n'));

        // Exactly one venue SELECT (the preload) for the whole programs phase —
        // not two per venue-linked program (a resolve-or-null read here plus a
        // write-time guard read inside each program insert).
        expect(counter.count, 1);

        // The single snapshot still resolves / nulls links correctly.
        expect((await repos.programs.getById('p1'))!.venueId, 'v1');
        expect((await repos.programs.getById('p2'))!.venueId, 'v2');
        expect((await repos.programs.getById('p4'))!.venueId, isNull);
        expect((await repos.programs.getById('p5'))!.venueId, isNull);
      },
    );
  });
}
