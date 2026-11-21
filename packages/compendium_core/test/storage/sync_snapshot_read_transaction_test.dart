// `snapshot()` reads the whole library in a read transaction, not under the
// write lock (#1915). Every test that needs two connections pauses the sync
// worker's scan at its first read of the programs table — after the dances,
// before the tags — and acts from another connection while it is paused.
import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

const _tag = (kind: SyncRecordKind.tag, recordId: 't1');
const _dance = (kind: SyncRecordKind.dance, recordId: 'dance-1');
const _field = (kind: SyncRecordKind.customFieldDef, recordId: 'f1');

/// Runs [onPause] once, the first time the worker reads the programs table
/// after [arm], and holds that read until it completes.
final class _PauseMidScan extends QueryInterceptor {
  Future<void> Function()? _onPause;
  var paused = false;

  void arm(Future<void> Function() onPause) => _onPause = onPause;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final onPause = _onPause;
    if (onPause != null && statement.contains('FROM "programs"')) {
      _onPause = null;
      paused = true;
      await onPause();
    }
    return super.runSelect(executor, statement, args);
  }
}

CustomFieldDef _customField({required bool shareable}) => CustomFieldDef(
  id: 'f1',
  key: 'shared_field',
  label: 'Shared field',
  type: CustomFieldType.text,
  shareable: shareable,
);

void main() {
  late File file;
  late _PauseMidScan pause;
  late CompendiumRepositories worker;
  late CompendiumSyncStorage storage;
  late CompendiumRepositories app;

  setUp(() async {
    final warned = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warned,
    );
    final dir = await Directory.systemTemp.createTemp('sync_snapshot_read');
    addTearDown(() => dir.delete(recursive: true));
    file = File('${dir.path}/compendium.sqlite');
    pause = _PauseMidScan();
    final workerDb = CompendiumDatabase(
      NativeDatabase(
        file,
        setup: applyCompendiumSqliteSetup,
      ).interceptWith(pause),
    );
    addTearDown(workerDb.close);
    worker = CompendiumRepositories(workerDb, contraTaxonomy);
    storage = CompendiumSyncStorage(worker);
    await worker.dances.create(sampleDance());
    // ignore: unused_result
    await worker.tags.upsert(
      Tag(id: 't1', name: 'One'),
      at: _stamp,
    );
    // In the background, as the app's connection is: a busy wait on this
    // isolate would also stall the scan it is waiting for.
    final appDb = CompendiumDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: applyCompendiumSqliteSetup,
      ),
    );
    addTearDown(appDb.close);
    app = CompendiumRepositories(appDb, contraTaxonomy);
  });

  test('an app write during the scan commits without waiting for it', () async {
    final before = await storage.snapshot();
    var appWriteDone = false;
    pause.arm(() async {
      // Deterministic, whatever the machine's speed: a connection that will
      // not wait (busy_timeout 0) writes at once. Under `BEGIN IMMEDIATE` the
      // scan holds the write lock and this throws SQLITE_BUSY.
      final probe = sqlite3.open(file.path);
      try {
        probe.execute(
          "UPDATE tags SET name = 'probe' WHERE id = 'no-such-tag'",
        );
      } on SqliteException catch (error) {
        fail('the scan holds the write lock: $error');
      } finally {
        probe.close();
      }
      // And the app's own write, through its own connection, completes
      // while the scan is still paused.
      // ignore: unused_result
      await app.tags
          .upsert(
            Tag(id: 't1', name: 'Edited in the app'),
            at: _stamp.add(const Duration(minutes: 5)),
          )
          .timeout(const Duration(seconds: 5));
      appWriteDone = true;
    });

    final during = await storage.snapshot();

    expect(pause.paused, isTrue, reason: 'the scan never reached the pause');
    expect(appWriteDone, isTrue);
    // The scan read one view, from before the write: the edit is not in it.
    expect(during.local[_tag]!.wireHash, before.local[_tag]!.wireHash);
    // It is in the next one.
    final after = await storage.snapshot();
    expect(after.local[_tag]!.wireHash, isNot(before.local[_tag]!.wireHash));
  });

  test('a write committed mid-scan is not half visible', () async {
    final before = await storage.snapshot();
    pause.arm(() async {
      // One transaction over a record the scan has already read (the dance)
      // and one it has not (the tag). Separate statements would see the tag
      // edit and miss the dance edit; one read view sees neither.
      final probe = sqlite3.open(file.path);
      try {
        probe
          ..execute('BEGIN')
          ..execute(
            "UPDATE dances SET title = 'Edited mid-scan' "
            "WHERE id = 'dance-1'",
          )
          ..execute("UPDATE tags SET name = 'Edited mid-scan' WHERE id = 't1'")
          ..execute('COMMIT');
      } finally {
        probe.close();
      }
    });

    final during = await storage.snapshot();

    expect(pause.paused, isTrue, reason: 'the scan never reached the pause');
    expect(during.local[_dance]!.wireHash, before.local[_dance]!.wireHash);
    expect(during.local[_tag]!.wireHash, before.local[_tag]!.wireHash);
    final after = await storage.snapshot();
    expect(
      after.local[_dance]!.wireHash,
      isNot(before.local[_dance]!.wireHash),
    );
    expect(after.local[_tag]!.wireHash, isNot(before.local[_tag]!.wireHash));
  });

  test('kept fields the scan saw orphaned are kept when an edit mid-scan '
      'needs them again', () async {
    // A peer's definition carries a field this build does not know, so it is
    // kept. The user turns "shareable" off: the next snapshot finds the kept
    // parts orphaned. While it scans, the user turns it back on. The sweep
    // must judge the library as it is when it deletes, not as the scan saw
    // it, or the peer's field is lost from a definition this device shares.
    final shared = syncRecordBlobForEntity(
      SyncRecordKind.customFieldDef,
      _customField(shareable: true),
      updatedAt: _stamp,
      existenceAt: _stamp,
    )!;
    final peer = SyncRecordBlob(
      kind: SyncRecordKind.customFieldDef,
      id: shared.id,
      updatedAt: shared.updatedAt,
      deletedAt: null,
      existenceAt: shared.existenceAt,
      body: {...shared.body, 'addedLater': 'kept'},
    );
    final result = await const SyncApplyEngine().apply(
      candidates: [SyncMergeCandidate(blob: peer)],
      storage: storage,
    );
    expect(result.applied, [_field]);
    // ignore: unused_result
    await worker.customFieldDefs.upsert(
      _customField(shareable: false),
      at: _stamp.add(const Duration(hours: 1)),
    );

    pause.arm(() async {
      // ignore: unused_result
      await app.customFieldDefs
          .upsert(
            _customField(shareable: true),
            at: _stamp.add(const Duration(hours: 2)),
          )
          .timeout(const Duration(seconds: 5));
    });
    final during = await storage.snapshot();

    expect(pause.paused, isTrue, reason: 'the scan never reached the pause');
    expect(
      during.local.containsKey(_field),
      isFalse,
      reason: 'the scan read the definition while it was private',
    );
    expect(
      await worker.syncLocal.listRetainedSyncFields(),
      hasLength(1),
      reason: 'the sweep deleted kept fields the definition needs again',
    );
    final after = await storage.snapshot();
    expect(after.local[_field]!.blob.body['addedLater'], 'kept');
  });

  test('kept fields still orphaned when the sweep runs are deleted', () async {
    // The other side of the re-check: an edit mid-scan that does not concern
    // them leaves the sweep to do its job.
    final shared = syncRecordBlobForEntity(
      SyncRecordKind.customFieldDef,
      _customField(shareable: true),
      updatedAt: _stamp,
      existenceAt: _stamp,
    )!;
    await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.customFieldDef,
            id: shared.id,
            updatedAt: shared.updatedAt,
            deletedAt: null,
            existenceAt: shared.existenceAt,
            body: {...shared.body, 'addedLater': 'kept'},
          ),
        ),
      ],
      storage: storage,
    );
    // ignore: unused_result
    await worker.customFieldDefs.upsert(
      _customField(shareable: false),
      at: _stamp.add(const Duration(hours: 1)),
    );
    pause.arm(() async {
      // ignore: unused_result
      await app.tags
          .upsert(
            Tag(id: 't1', name: 'Unrelated'),
            at: _stamp,
          )
          .timeout(const Duration(seconds: 5));
    });

    await storage.snapshot();

    expect(pause.paused, isTrue, reason: 'the scan never reached the pause');
    expect(await worker.syncLocal.listRetainedSyncFields(), isEmpty);
  });

  group('readTransaction', () {
    late CompendiumDatabase db;
    late CompendiumRepositories repositories;

    setUp(() {
      db = openTestDatabase();
      repositories = CompendiumRepositories(db, contraTaxonomy);
    });

    tearDown(() => db.close());

    test('refuses a write, and leaves the connection writable after', () async {
      await expectLater(
        repositories.readTransaction(
          () => repositories.tags.upsert(Tag(id: 't1', name: 'One')),
        ),
        throwsA(isA<SqliteException>()),
      );
      // ignore: unused_result
      await repositories.tags.upsert(Tag(id: 't1', name: 'One'));
      expect((await repositories.tags.getById('t1'))!.name, 'One');
    });

    test('inside a transaction, sees its uncommitted writes, and snapshot() '
        'runs in it', () async {
      final storage = CompendiumSyncStorage(repositories);
      await repositories.transaction(() async {
        // ignore: unused_result
        await repositories.tags.upsert(
          Tag(id: 't1', name: 'One'),
          at: _stamp,
        );
        expect(
          await repositories.readTransaction(
            () => repositories.tags.getById('t1'),
          ),
          isNotNull,
        );
        expect((await storage.snapshot()).local.containsKey(_tag), isTrue);
      });
    });
  });
}
