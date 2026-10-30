import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

/// LIFE-2: "Permanently delete" erases an unpublished record, and blanks and
/// hides a published one, keeping only its deletion record.
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  final created = DateTime.utc(2026, 1, 1);
  final trashedAt = DateTime.utc(2026, 2, 1);
  final now = DateTime.utc(2026, 3, 1);

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  Future<void> publish(SyncRecordKind kind, String id) =>
      repos.syncLocal.markPublished(kind: kind, recordId: id);

  Future<DanceRow?> danceRow(String id) =>
      (db.select(db.dances)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ProgramRow?> programRow(String id) =>
      (db.select(db.programs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> count(String table, String column, String id) async =>
      (await db
              .customSelect(
                'SELECT 1 FROM $table WHERE $column = ?',
                variables: [Variable<String>(id)],
              )
              .get())
          .length;

  /// A dance with something in every content column and every join.
  Future<void> createFullDance(String id) async {
    // ignore: unused_result
    await repos.choreographers.upsert(
      Choreographer(id: 'c-$id', name: 'Private Person $id'),
      at: created,
    );
    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: 't-$id', name: 'tag $id'),
      at: created,
    );
    await repos.publishedSources.upsert(
      PublishedSource(id: 's-$id', title: 'Book $id'),
      at: created,
    );
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f-$id',
        key: 'field_$id',
        label: 'Field $id',
        type: CustomFieldType.text,
      ),
      at: created,
    );
    await repos.dances.create(
      sampleDance(
        id: id,
        title: 'Secret Title $id',
        authorIds: ['c-$id'],
        tagIds: ['t-$id'],
        sourceCitations: [SourceCitation(sourceId: 's-$id', page: '12')],
        customFields: [CustomFieldValue(fieldId: 'f-$id', value: 'secret')],
        links: [
          DanceLink(
            id: 'l-$id',
            kind: LinkKind.video,
            url: 'https://example.com/$id',
          ),
        ],
        provenance: Provenance(
          source: ProvenanceSource.callersbox,
          externalId: 'ext-$id',
          importedAt: created,
        ),
        createdAt: created,
        updatedAt: created,
      ).copyWith(
        walkthrough: 'Walk it through',
        rating: 4,
        tunes: ['Tune'],
        difficultyLevelId: DifficultyLevel.beginnerId,
        mixer: true,
      ),
    );
  }

  group('dances', () {
    test('an unpublished dance is erased', () async {
      await createFullDance('d1');
      await repos.dances.softDelete('d1', at: trashedAt);

      final outcome = await repos.dances.permanentlyDelete('d1', now: now);

      expect(outcome, PermanentDeletion.erased);
      expect(await danceRow('d1'), isNull);
    });

    test('a published dance is blanked down to its deletion record', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.dances.softDelete('d1', at: trashedAt);
      final before = (await danceRow('d1'))!;

      final outcome = await repos.dances.permanentlyDelete('d1', now: now);

      expect(outcome, PermanentDeletion.blanked);
      final row = (await danceRow('d1'))!;
      expect(isPermanentlyDeleted(row.deletedAt), isTrue);
      expect(row.title, blankedRecordTitle);
      expect(row.hook, isEmpty);
      expect(row.callingNotes, isEmpty);
      expect(row.walkthrough, isEmpty);
      expect(row.figuresJson, '[]');
      expect(row.tunesJson, '[]');
      expect(row.levelId, isNull);
      expect(row.rating, isNull);
      expect(row.mixer, isFalse);
      // A fresh content stamp, so the blank body wins last-writer-wins on
      // peers, and a causal existence stamp for the user's deletion.
      expect(row.updatedAt.toUtc(), now);
      expect(row.existenceAt!.isAfter(before.existenceAt!), isTrue);
      for (final table in const [
        'dance_authors',
        'dance_tags',
        'dance_links',
        'dance_sources',
        'custom_field_values',
        'provenance',
        'dance_figures',
        'dance_fts',
        'dance_substring_fts',
      ]) {
        expect(await count(table, 'dance_id', 'd1'), 0, reason: table);
      }
      // The unpublished choreographer only this dance cited is collected, as
      // a purge collects it.
      expect(await count('choreographers', 'id', 'c-d1'), 0);
      // The dance model still loads.
      final dance = await repos.dances.getById('d1', includeDeleted: true);
      expect(dance!.title, blankedRecordTitle);
    });

    test('a program slot keeps the dance title as a caption, and the program '
        'is restamped', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Saturday',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd1', text: 'Note'),
          ],
          createdAt: created,
          updatedAt: created,
        ),
      );
      await repos.dances.softDelete('d1', at: trashedAt);

      await repos.dances.permanentlyDelete('d1', now: now);

      final program = (await repos.programs.getById('p1'))!;
      final s1 = program.slots.firstWhere((s) => s.id == 's1');
      final s2 = program.slots.firstWhere((s) => s.id == 's2');
      expect(s1.danceId, isNull);
      expect(s1.text, 'Secret Title d1');
      expect(s1.isPurgedDance, isTrue);
      expect(s2.danceId, isNull);
      expect(s2.text, 'Note');
      expect(program.updatedAt, now);
    });

    test(
      'a related-dance link to it is deleted, and its owner restamped',
      () async {
        await createFullDance('d1');
        await publish(SyncRecordKind.dance, 'd1');
        await repos.dances.create(
          sampleDance(
            id: 'owner',
            links: [
              DanceLink(
                id: 'rel',
                kind: LinkKind.relatedDance,
                targetDanceId: 'd1',
              ),
            ],
            updatedAt: created,
          ),
        );
        await repos.dances.softDelete('d1', at: trashedAt);

        await repos.dances.permanentlyDelete('d1', now: now);

        final owner = (await repos.dances.getById('owner'))!;
        expect(owner.links, isEmpty);
        expect(owner.updatedAt, now);
      },
    );

    test('kept parts from a newer peer are removed with the content', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.syncLocal.setRetainedSyncFields(
        kind: SyncRecordKind.dance,
        recordId: 'd1',
        payload: '{"secret":"kept"}',
      );
      await repos.dances.softDelete('d1', at: trashedAt);

      await repos.dances.permanentlyDelete('d1', now: now);

      expect(await count('retained_sync_fields', 'record_id', 'd1'), 0);
    });

    test('a live or missing dance is left alone', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');

      expect(
        await repos.dances.permanentlyDelete('d1', now: now),
        PermanentDeletion.none,
      );
      expect(
        await repos.dances.permanentlyDelete('nope', now: now),
        PermanentDeletion.none,
      );
      final row = (await danceRow('d1'))!;
      expect(row.deletedAt, isNull);
      expect(row.title, 'Secret Title d1');
    });

    test('the sweep blanks a dance an older build marked, once', () async {
      // What "Permanently delete" did before blanking: backdate and purge,
      // which skipped the published row and left it whole.
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.dances.softDelete('d1', at: DateTime.utc(1970));
      expect((await danceRow('d1'))!.title, 'Secret Title d1');

      expect(await repos.dances.removePermanentlyDeleted(now: now), 1);
      final blanked = (await danceRow('d1'))!;
      expect(blanked.title, blankedRecordTitle);
      expect(await count('dance_authors', 'dance_id', 'd1'), 0);

      // A second launch neither restamps nor republishes it.
      final later = now.add(const Duration(days: 1));
      expect(await repos.dances.removePermanentlyDeleted(now: later), 0);
      expect((await danceRow('d1'))!.updatedAt, blanked.updatedAt);
    });

    test('the sweep clears what a blank row still holds, such as a peer\'s '
        'device-local custom-field values', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.dances.softDelete('d1', at: trashedAt);
      await repos.dances.permanentlyDelete('d1', now: now);
      // What applying a blank body leaves on a peer with a field of its own
      // that never syncs: `writeFromSync` preserves device-local values.
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'local',
          key: 'local_field',
          label: 'Local',
          type: CustomFieldType.text,
          shareable: false,
        ),
        at: created,
      );
      await db.customStatement(
        "INSERT INTO custom_field_values (dance_id, field_id, value_text) "
        "VALUES ('d1', 'local', 'private')",
      );

      final later = now.add(const Duration(days: 1));
      expect(await repos.dances.removePermanentlyDeleted(now: later), 1);
      expect(await count('custom_field_values', 'dance_id', 'd1'), 0);
      // And it is then blank for good.
      expect(
        await repos.dances.removePermanentlyDeleted(
          now: later.add(const Duration(days: 1)),
        ),
        0,
      );
    });

    test('the sweep leaves ordinary trashed dances alone', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await createFullDance('d2');
      await repos.dances.softDelete('d1', at: trashedAt);
      await repos.dances.softDelete('d2', at: trashedAt);

      expect(await repos.dances.removePermanentlyDeleted(now: now), 0);
      expect((await danceRow('d1'))!.title, 'Secret Title d1');
      expect((await danceRow('d2'))!.title, 'Secret Title d2');
    });

    test('a blank body outranks content stamped ahead of this clock', () async {
      await createFullDance('d1');
      await publish(SyncRecordKind.dance, 'd1');
      await repos.dances.softDelete('d1', at: trashedAt);
      final ahead = now.add(const Duration(days: 30));
      await (db.update(db.dances)..where((t) => t.id.equals('d1'))).write(
        DancesCompanion(updatedAt: Value(ahead)),
      );

      await repos.dances.permanentlyDelete('d1', now: now);

      expect((await danceRow('d1'))!.updatedAt.toUtc().isAfter(ahead), isTrue);
    });
  });

  group('programs', () {
    Future<void> createFullProgram(String id) async {
      await repos.dances.create(sampleDance(id: 'd-$id'));
      await repos.programs.create(
        Program(
          id: id,
          title: 'Secret Gig $id',
          eventDate: created,
          venue: 'Private Hall',
          band: 'The Band',
          caller: 'Someone',
          dancerLevel: 'Mixed',
          notes: 'Private notes',
          status: ProgramStatus.finalized,
          hideAlternates: true,
          dialectName: 'Gender-free',
          payMinorUnits: 15000,
          payCurrency: 'USD',
          slots: [ProgramSlot(id: 'slot-$id', position: 0, danceId: 'd-$id')],
          provenance: Provenance(
            source: ProvenanceSource.callersCompanion,
            externalId: 'ext-$id',
            importedAt: created,
          ),
          createdAt: created,
          updatedAt: created,
        ),
      );
    }

    test('an unpublished program is erased', () async {
      await createFullProgram('p1');
      await repos.programs.softDelete('p1', at: trashedAt);

      expect(
        await repos.programs.permanentlyDelete('p1', now: now),
        PermanentDeletion.erased,
      );
      expect(await programRow('p1'), isNull);
    });

    test(
      'a published program is blanked down to its deletion record',
      () async {
        await createFullProgram('p1');
        await publish(SyncRecordKind.program, 'p1');
        await repos.programs.softDelete('p1', at: trashedAt);
        final before = (await programRow('p1'))!;

        expect(
          await repos.programs.permanentlyDelete('p1', now: now),
          PermanentDeletion.blanked,
        );

        final row = (await programRow('p1'))!;
        expect(isPermanentlyDeleted(row.deletedAt), isTrue);
        expect(row.title, blankedRecordTitle);
        expect(row.eventDate, isNull);
        expect(row.venue, isNull);
        expect(row.band, isNull);
        expect(row.caller, isNull);
        expect(row.dancerLevel, isNull);
        expect(row.notes, isEmpty);
        expect(row.status, ProgramStatus.draft);
        expect(row.hideAlternates, isFalse);
        expect(row.dialectName, isNull);
        expect(row.payMinorUnits, isNull);
        expect(row.payCurrency, isNull);
        expect(row.updatedAt.toUtc(), now);
        expect(row.existenceAt!.isAfter(before.existenceAt!), isTrue);
        expect(await count('program_slots', 'program_id', 'p1'), 0);
        expect(await count('program_provenance', 'program_id', 'p1'), 0);
        // The dance it called is untouched.
        expect(await repos.dances.getById('d-p1'), isNotNull);
      },
    );

    test('the sweep blanks a program an older build marked, once', () async {
      await createFullProgram('p1');
      await publish(SyncRecordKind.program, 'p1');
      await repos.programs.softDelete('p1', at: DateTime.utc(1970));

      expect(await repos.programs.removePermanentlyDeleted(now: now), 1);
      final blanked = (await programRow('p1'))!;
      expect(blanked.title, blankedRecordTitle);

      final later = now.add(const Duration(days: 1));
      expect(await repos.programs.removePermanentlyDeleted(now: later), 0);
      expect((await programRow('p1'))!.updatedAt, blanked.updatedAt);
    });
  });

  group('Device Sync', () {
    test('a peer holding the tombstone takes the blank body', () async {
      // Device A blanks; device B holds the same tombstone, content intact,
      // and agreed with A at the last pass (its baseline names B's copy).
      // Two in-memory devices, not one database opened twice.
      final warned = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warned,
      );
      final dbB = openTestDatabase();
      addTearDown(dbB.close);
      final reposB = CompendiumRepositories(dbB, contraTaxonomy);
      final storageA = CompendiumSyncStorage(repos);
      final storageB = CompendiumSyncStorage(reposB);
      final address = (kind: SyncRecordKind.dance, recordId: 'd1');

      for (final r in [repos, reposB]) {
        await r.dances.create(
          sampleDance(id: 'd1', title: 'Secret', updatedAt: created),
        );
        await r.dances.softDelete('d1', at: trashedAt);
        await r.syncLocal.markPublished(kind: address.kind, recordId: 'd1');
      }
      final localB = (await storageB.snapshot()).local[address]!;

      await repos.dances.permanentlyDelete('d1', now: now);
      final fromA = (await storageA.snapshot()).local[address]!;
      expect(fromA.blob.body['title'], blankedRecordTitle);

      final plan = const SyncMergeEngine().plan(
        local: {address: localB},
        baseline: {
          address: SyncBaselineEntry(
            kind: address.kind,
            recordId: 'd1',
            wireHash: localB.wireHash,
          ),
        },
        peers: [
          {address: fromA},
        ],
      );
      final decision = plan.decisions.single;
      expect(decision.action, SyncMergeAction.download);

      final result = await const SyncApplyEngine().apply(
        candidates: [decision.winner!],
        storage: storageB,
      );
      expect(result.applied, [address]);
      final rowB = (await (dbB.select(
        dbB.dances,
      )..where((t) => t.id.equals('d1'))).getSingle());
      expect(rowB.title, blankedRecordTitle);
      expect(rowB.hook, isEmpty);
      expect(isPermanentlyDeleted(rowB.deletedAt), isTrue);
    });
  });
}
