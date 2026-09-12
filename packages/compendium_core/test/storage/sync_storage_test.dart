import 'package:compendium_core/compendium_core.dart';
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
    'inbound dance writes preserve device-local custom-field values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'local-field',
          key: 'local_field',
          label: 'Local field',
          type: CustomFieldType.text,
          shareable: false,
        ),
      );
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
}
