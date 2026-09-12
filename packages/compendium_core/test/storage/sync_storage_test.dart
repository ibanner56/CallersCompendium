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

      expect(
        (await storage.snapshot(syncId: 'sync-a')).previouslyUsed,
        isFalse,
      );
      expect((await storage.snapshot(syncId: 'sync-b')).previouslyUsed, isTrue);
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
