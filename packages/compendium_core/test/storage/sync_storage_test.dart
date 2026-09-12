import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  test(
    'snapshots and applies through the real repository transaction seam',
    () async {
      final localStamp = DateTime.utc(2025, 1, 1, 12);
      final remoteStamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(
          id: 'c1',
          name: 'Local name',
          email: 'private@example.com',
          location: 'Private locality',
        ),
        at: localStamp,
      );

      final snapshot = await storage.snapshot();
      final local =
          snapshot.local[(kind: SyncRecordKind.choreographer, recordId: 'c1')];
      expect(local, isNotNull);
      expect(local!.blob.body, isNot(contains('email')));

      final remote = SyncRecordBlob(
        kind: SyncRecordKind.choreographer,
        id: 'c1',
        updatedAt: remoteStamp,
        deletedAt: null,
        existenceAt: localStamp,
        body: const {'id': 'c1', 'name': 'Remote name'},
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: remote)],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: 'c1'),
      ]);
      final stored = await repositories.choreographers.getById('c1');
      expect(stored!.name, 'Remote name');
      expect(stored.email, 'private@example.com');
      expect(stored.location, 'Private locality');

      final row = await (db.select(
        db.choreographers,
      )..where((table) => table.id.equals('c1'))).getSingle();
      expect(row.updatedAt!.toUtc(), remoteStamp);
      expect(row.existenceAt!.toUtc(), localStamp);
      expect(row.deletedAt, isNull);
    },
  );

  test(
    'tracks prior use by sync identity even when the collection is empty',
    () async {
      expect(
        (await storage.snapshot(syncId: 'sync-a')).previouslyUsed,
        isFalse,
      );

      await storage.markSyncUsed('sync-a');

      expect((await storage.snapshot(syncId: 'sync-a')).previouslyUsed, isTrue);
      expect(
        (await storage.snapshot(syncId: 'sync-b')).previouslyUsed,
        isFalse,
      );

      await storage.markSyncUsed('sync-b');

      expect((await storage.snapshot(syncId: 'sync-a')).previouslyUsed, isTrue);
      expect((await storage.snapshot(syncId: 'sync-b')).previouslyUsed, isTrue);
    },
  );

  test(
    'skips an inbound record with an unavailable reference and applies peers',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final invalidDance = Dance(
        id: 'bad-dance',
        title: 'Bad dance',
        difficultyLevelId: 'missing-level',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final validChoreographer = Choreographer(
        id: 'c2',
        name: 'Remote choreographer',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: invalidDance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, invalidDance),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: validChoreographer.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.choreographer,
                validChoreographer,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: 'c2'),
      ]);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(await repositories.choreographers.getById('c2'), isNotNull);
      expect(await repositories.dances.getById('bad-dance'), isNull);
    },
  );

  test(
    'applies forward and cyclic dance references after parent rows',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      Dance dance({
        required String id,
        required String target,
        required String linkId,
      }) => Dance(
        id: id,
        title: id,
        links: [
          DanceLink(
            id: linkId,
            kind: LinkKind.relatedDance,
            targetDanceId: target,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final source = dance(
        id: 'a-source',
        target: 'z-target',
        linkId: 'forward-link',
      );
      final target = Dance(
        id: 'z-target',
        title: 'z-target',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final cycleA = dance(
        id: 'cycle-a',
        target: 'cycle-b',
        linkId: 'cycle-a-link',
      );
      final cycleB = dance(
        id: 'cycle-b',
        target: 'cycle-a',
        linkId: 'cycle-b-link',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          for (final dance in [source, target, cycleA, cycleB])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.dance,
                id: dance.id,
                updatedAt: stamp,
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.dance, dance),
              ),
            ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: 'a-source'),
        (kind: SyncRecordKind.dance, recordId: 'cycle-a'),
        (kind: SyncRecordKind.dance, recordId: 'cycle-b'),
        (kind: SyncRecordKind.dance, recordId: 'z-target'),
      ]);
      expect(result.reports, isEmpty);
      expect(
        (await repositories.dances.getById(
          'a-source',
        ))!.links.single.targetDanceId,
        'z-target',
      );
      expect(
        (await repositories.dances.getById(
          'cycle-a',
        ))!.links.single.targetDanceId,
        'cycle-b',
      );
      expect(
        (await repositories.dances.getById(
          'cycle-b',
        ))!.links.single.targetDanceId,
        'cycle-a',
      );
    },
  );

  test('does not resolve references to tombstoned inbound parents', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final tombstoneStamp = stamp.add(const Duration(minutes: 1));
    final tombstoneChoreographer = Choreographer(
      id: 'tomb-choreographer',
      name: 'Tombstoned choreographer',
    );
    final tombstoneTag = Tag(id: 'tomb-tag', name: 'Tombstoned tag');
    final tombstoneField = CustomFieldDef(
      id: 'tomb-field',
      key: 'tomb_field',
      label: 'Tombstoned field',
      type: CustomFieldType.text,
    );
    final tombstoneDance = Dance(
      id: 'tomb-dance',
      title: 'Tombstoned dance',
      createdAt: stamp,
      updatedAt: stamp,
    );
    final dances = [
      Dance(
        id: 'uses-choreographer',
        title: 'Uses choreographer',
        authorIds: [tombstoneChoreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-tag',
        title: 'Uses tag',
        tagIds: [tombstoneTag.id],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-field',
        title: 'Uses field',
        customFields: [
          CustomFieldValue(fieldId: tombstoneField.id, value: 'remote'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-dance',
        title: 'Uses dance',
        links: [
          DanceLink(
            id: 'uses-tombstone-link',
            kind: LinkKind.relatedDance,
            targetDanceId: tombstoneDance.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    ];

    SyncMergeCandidate entityCandidate({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
    }) => SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: stamp,
        deletedAt: tombstoneStamp,
        existenceAt: stamp,
        body: syncBodyForEntity(
          kind,
          entity,
          allowedCustomFieldIds: kind == SyncRecordKind.dance
              ? {tombstoneField.id}
              : const {},
        ),
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        entityCandidate(
          kind: SyncRecordKind.choreographer,
          id: tombstoneChoreographer.id,
          entity: tombstoneChoreographer,
        ),
        entityCandidate(
          kind: SyncRecordKind.tag,
          id: tombstoneTag.id,
          entity: tombstoneTag,
        ),
        entityCandidate(
          kind: SyncRecordKind.customFieldDef,
          id: tombstoneField.id,
          entity: tombstoneField,
        ),
        entityCandidate(
          kind: SyncRecordKind.dance,
          id: tombstoneDance.id,
          entity: tombstoneDance,
        ),
        for (final dance in dances)
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                dance,
                allowedCustomFieldIds: {tombstoneField.id},
              ),
            ),
          ),
      ],
      storage: storage,
    );

    expect(result.applied, [
      (kind: SyncRecordKind.choreographer, recordId: tombstoneChoreographer.id),
      (kind: SyncRecordKind.tag, recordId: tombstoneTag.id),
      (kind: SyncRecordKind.customFieldDef, recordId: tombstoneField.id),
      (kind: SyncRecordKind.dance, recordId: tombstoneDance.id),
    ]);
    expect(
      result.reports.where(
        (report) => report.code == SyncReportCode.unresolvedReference,
      ),
      hasLength(4),
    );
    for (final dance in dances) {
      expect(await repositories.dances.getById(dance.id), isNull);
    }
  });

  test('does not resolve relations to a locally tombstoned dance', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final tombstoneStamp = stamp.add(const Duration(minutes: 1));
    final tombstone = Dance(
      id: 'local-tombstone',
      title: 'Locally tombstoned',
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: tombstoneStamp,
    );
    await repositories.dances.create(tombstone);

    final linkedDance = Dance(
      id: 'linked-to-local-tombstone',
      title: 'Linked dance',
      links: [
        DanceLink(
          id: 'local-tombstone-link',
          kind: LinkKind.relatedDance,
          targetDanceId: tombstone.id,
        ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    final program = Program(
      id: 'program-with-local-tombstone',
      title: 'Program',
      slots: [
        ProgramSlot(
          id: 'local-tombstone-slot',
          position: 0,
          danceId: tombstone.id,
        ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );

    SyncMergeCandidate candidate({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
    }) => SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: stamp,
        deletedAt: null,
        existenceAt: stamp,
        body: syncBodyForEntity(kind, entity),
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        candidate(
          kind: SyncRecordKind.dance,
          id: linkedDance.id,
          entity: linkedDance,
        ),
        candidate(
          kind: SyncRecordKind.program,
          id: program.id,
          entity: program,
        ),
      ],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(
      result.reports
          .where((report) => report.code == SyncReportCode.unresolvedReference)
          .length,
      2,
    );
    expect(await repositories.dances.getById(linkedDance.id), isNull);
    expect(await repositories.programs.getById(program.id), isNull);
    expect(
      await repositories.dances.getById(tombstone.id, includeDeleted: true),
      isNotNull,
    );
  });

  test(
    'does not retain a parent when an inbound tombstone invalidates its join',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final choreographer = Choreographer(
        id: 'existing-choreographer',
        name: 'Existing choreographer',
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(choreographer, at: stamp);

      final dance = Dance(
        id: 'dance-with-tombstoned-author',
        title: 'Dance with tombstoned author',
        authorIds: [choreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final tombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: choreographer.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: tombstoneStamp,
          body: syncBodyForEntity(SyncRecordKind.choreographer, choreographer),
        ),
      );
      final inboundDance = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: dance.id,
          updatedAt: stamp,
          deletedAt: null,
          existenceAt: stamp,
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [inboundDance, tombstone],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: choreographer.id),
      ]);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(await repositories.dances.getById(dance.id), isNull);
      expect(
        await repositories.choreographers.getById(choreographer.id),
        isNull,
      );
    },
  );

  test(
    'inbound dance writes preserve device-local custom-field values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'local-field',
          key: 'local_field',
          label: 'Local field',
          type: CustomFieldType.text,
          shareable: false,
        ),
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'shared-field',
          key: 'shared_field',
          label: 'Shared field',
          type: CustomFieldType.text,
        ),
      );
      final local = Dance(
        id: 'dance-fields',
        title: 'Local dance',
        customFields: [
          CustomFieldValue(fieldId: 'local-field', value: 'keep me'),
          CustomFieldValue(fieldId: 'shared-field', value: 'old'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(local);

      final remote = local.copyWith(
        title: 'Remote dance',
        customFields: [CustomFieldValue(fieldId: 'shared-field', value: 'new')],
        updatedAt: stamp.add(const Duration(hours: 1)),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: remote.id,
              updatedAt: remote.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                remote,
                allowedCustomFieldIds: {'shared-field'},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: remote.id),
      ]);
      final stored = await repositories.dances.getById(remote.id);
      expect(
        stored!.customFields,
        containsAll([
          CustomFieldValue(fieldId: 'local-field', value: 'keep me'),
          CustomFieldValue(fieldId: 'shared-field', value: 'new'),
        ]),
      );
    },
  );

  test(
    'inbound performed programs preserve peer slot content without stamping it',
    () async {
      final originalStamp = DateTime.utc(2025, 1, 1, 12);
      final remoteStamp = DateTime.utc(2025, 1, 2, 12);
      final original = Program(
        id: 'p1',
        title: 'Program',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: originalStamp,
        updatedAt: originalStamp,
      );
      await repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Dance',
          createdAt: originalStamp,
          updatedAt: originalStamp,
        ),
      );
      await repositories.programs.create(original);

      final remote = original.copyWith(
        status: ProgramStatus.performed,
        updatedAt: remoteStamp,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.program,
              id: remote.id,
              updatedAt: remoteStamp,
              deletedAt: null,
              existenceAt: originalStamp,
              body: syncBodyForEntity(SyncRecordKind.program, remote),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [(kind: SyncRecordKind.program, recordId: 'p1')]);
      final stored = await repositories.programs.getById('p1');
      expect(stored!.status, ProgramStatus.performed);
      expect(stored.slots.single.performedAt, isNull);
      expect(stored.updatedAt, remoteStamp);
    },
  );

  test(
    'does not retain a parent when a stored custom-field definition is corrupt',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final preservedDef = CustomFieldDef(
        id: 'preserved-field',
        key: 'preserved_field',
        label: 'Preserved field',
        type: CustomFieldType.text,
      );
      final corruptDef = CustomFieldDef(
        id: 'corrupt-field',
        key: 'corrupt_field',
        label: 'Corrupt field',
        type: CustomFieldType.choice,
        choices: ['valid'],
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(preservedDef, at: stamp);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(corruptDef, at: stamp);
      await (db.update(
        db.customFieldDefs,
      )..where((row) => row.id.equals(corruptDef.id))).write(
        const CustomFieldDefsCompanion(choicesJson: Value('{not valid json')),
      );

      final original = Dance(
        id: 'dance-with-corrupt-field',
        title: 'Original title',
        customFields: [
          CustomFieldValue(fieldId: preservedDef.id, value: 'preserve me'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(original);

      final inbound = original.copyWith(
        title: 'Inbound title',
        customFields: [
          CustomFieldValue(fieldId: corruptDef.id, value: 'invalid definition'),
        ],
        updatedAt: stamp.add(const Duration(minutes: 1)),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: inbound.id,
              updatedAt: inbound.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                inbound,
                allowedCustomFieldIds: {corruptDef.id},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      final stored = await repositories.dances.getById(original.id);
      expect(stored!.title, original.title);
      expect(stored.customFields, original.customFields);
    },
  );

  test(
    'defers derived maintenance during sync relation writes to the batch rebuild',
    () async {
      final counter = FtsDeleteByDanceCounter();
      final countingDb = openCountingTestDatabase(counter);
      await db.close();
      db = countingDb;
      final countingRepositories = CompendiumRepositories(
        countingDb,
        contraTaxonomy,
      );
      final countingStorage = CompendiumSyncStorage(countingRepositories);
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final dance = Dance(
        id: 'sync-derived-batch',
        title: 'Sync dance',
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: dance.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, dance),
            ),
          ),
        ],
        storage: countingStorage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: dance.id),
      ]);
      expect(
        counter.count,
        0,
        reason:
            'sync relation writes must defer per-dance derived maintenance '
            'until the final bulk rebuild',
      );
    },
  );
}
