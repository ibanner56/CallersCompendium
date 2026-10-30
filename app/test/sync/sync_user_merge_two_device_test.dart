import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

const _s = '00000000-0000-4000-8000-000000000001';
const _l = '00000000-0000-4000-8000-000000000002';
const _d1 = '00000000-0000-4000-8000-0000000000d1';
const _d2 = '00000000-0000-4000-8000-0000000000d2';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;

  setUp(() {
    server = InMemorySyncServer();
    a = InMemorySyncDevice(
      server,
      deviceId: 'device-a',
      repositories: openTestRepositories(),
    );
    b = InMemorySyncDevice(
      server,
      deviceId: 'device-b',
      repositories: openTestRepositories(),
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
  });

  Future<void> dance(InMemorySyncDevice device, String id, List<String> tags) =>
      device.repositories.dances.create(
        Dance(
          id: id,
          title: 'Dance $id',
          tagIds: tags,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

  Future<List<String>> state(InMemorySyncDevice device) async {
    final db = device.repositories.db;
    final tags = await db.select(db.tags).get();
    final joins = await db.select(db.danceTags).get();
    final pending = await device.repositories.syncLocal.listPendingDeletions();
    final queue = await device.repositories.syncLocal.listReviewQueue();
    return [
      for (final t in tags)
        'tag ${t.id.substring(34)} "${t.name}"${t.deletedAt == null ? '' : ' (deleted)'}',
      for (final j in joins) 'join ${j.danceId.substring(34)}->${j.tagId.substring(34)}',
      for (final p in pending) 'pending ${p.recordId.substring(34)}',
      for (final q in queue)
        'review ${q.reason} ${q.recordId.substring(34)}/${q.counterpartId.length > 34 ? q.counterpartId.substring(34) : q.counterpartId}',
    ];
  }

  /// What a user merge of S-renamed-to-"Flowy" into L writes on [device],
  /// by hand: the loser's name freed, joins re-pointed, survivor renamed,
  /// loser tombstoned, alias recorded.
  Future<void> simulatedMerge(InMemorySyncDevice device) async {
    final repos = device.repositories;
    final db = repos.db;
    await repos.transaction(() async {
      final now = DateTime.now().toUtc();
      await (db.update(db.tags)..where((t) => t.id.equals(_l))).write(
        TagsCompanion(
          name: const Value('Flowy_00000000'),
          updatedAt: Value(now),
        ),
      );
      final joins = await (db.select(
        db.danceTags,
      )..where((t) => t.tagId.equals(_l))).get();
      for (final j in joins) {
        await (db.update(db.danceTags)..where(
              (t) => t.danceId.equals(j.danceId) & t.tagId.equals(_l),
            ))
            .write(const DanceTagsCompanion(tagId: Value(_s)));
        final d = await (db.select(
          db.dances,
        )..where((t) => t.id.equals(j.danceId))).getSingle();
        await (db.update(db.dances)..where((t) => t.id.equals(j.danceId)))
            .write(
              DancesCompanion(
                updatedAt: Value(d.updatedAt.add(const Duration(seconds: 1))),
              ),
            );
      }
      // ignore: unused_result
      await repos.tags.upsert(
        Tag(id: _s, name: 'Flowy'),
        localUserEdit: true,
      );
      await repos.tags.delete(_l);
      await repos.syncLocal.remapIdentity(
        kind: SyncRecordKind.tag,
        losingId: _l,
        survivingId: _s,
      );
    });
  }

  test('explore: held peer after a merge', () async {
    // ignore: unused_result
    await a.repositories.tags.upsert(Tag(id: _s, name: 'Flowing'));
    // ignore: unused_result
    await a.repositories.tags.upsert(Tag(id: _l, name: 'Flowy'));
    await dance(a, _d1, [_l]);
    await a.sync();
    await b.sync();
    await a.sync();
    printOnFailure('B start: ${await state(b)}');

    await dance(b, _d2, [_l]);
    await simulatedMerge(a);
    print('A after merge: ${await state(a)}');
    await a.sync();
    print('A manifest tags: ${server.manifestOf('device-a')!.records[SyncRecordKind.tag]}');
    print('B manifest tags: ${server.manifestOf('device-b')!.records[SyncRecordKind.tag]}');
    server.fetches.clear();
    for (var pass = 1; pass <= 4; pass++) {
      final r = await b.sync();
      print('B pass $pass: ${await state(b)} fetched ${server.fetches}');
      server.fetches.clear();
      for (final rep in r.reports) {
        print('  report ${rep.code} ${rep.kind} ${rep.recordId} ${rep.message}');
      }
      await a.sync();
      print('A pass $pass: ${await state(a)}');
    }
  });
}
