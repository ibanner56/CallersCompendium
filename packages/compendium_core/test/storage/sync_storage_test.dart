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
}
