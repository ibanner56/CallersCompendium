import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Guards for #1917: the server's connection waits briefly for a competing
/// writer instead of failing at once, and `--break-glass` opens the store
/// read-only so it can run against the live volume.
///
/// Every test uses real files, not in-memory databases: the hazards are the
/// WAL `-shm` file and a second process-like connection, which `:memory:`
/// cannot reproduce.
void main() {
  late Directory dataDirectory;
  late AthenaeumConfig config;
  const syncId = 'busy-breakglass-horse-staple';

  String databasePath() => '${dataDirectory.path}/athenaeum.sqlite';
  String idKey() => deriveIncomingSyncIdKey(syncId, config.pepper);

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('athenaeum-busy-');
    config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
  });

  tearDown(() => dataDirectory.deleteSync(recursive: true));

  /// A store with one manifest whose `manifest_refs` rows are then removed, so
  /// anything that runs the startup indexer leaves a visible trace.
  ({AthenaeumStore server, String epoch}) seedUnindexedStore() {
    final server = AthenaeumStore(config: config);
    final epoch = server.create(idKey()).epoch;
    server.putManifest(
      idKey: idKey(),
      epoch: epoch,
      deviceId: 'device-one',
      etag: 'etag-one',
      writtenAt: 1,
      body: encodeSyncManifestUtf8(
        SyncManifest(
          deviceId: 'device-one',
          epoch: epoch,
          writtenAt: DateTime.utc(2026, 10, 1),
          records: {
            SyncRecordKind.dance: {'dance-0': 'a' * 64},
          },
        ),
      ),
      referencedHashes: ['a' * 64],
    );
    server.database
      ..execute('DELETE FROM manifest_refs')
      ..execute('DELETE FROM indexed_manifests');
    return (server: server, epoch: epoch);
  }

  int count(Database database, String table) =>
      database.select('SELECT COUNT(*) AS n FROM $table').single['n'] as int;

  test('break-glass reads while another connection holds a write lock and '
      'runs none of the startup writes', () {
    final seeded = seedUnindexedStore();
    addTearDown(seeded.server.close);
    final locker = sqlite3.open(databasePath())..execute('BEGIN IMMEDIATE');
    addTearDown(locker.close);

    final store = AthenaeumStore.breakGlass(config: config);
    addTearDown(store.close);
    store.recordBreakGlassAccess(syncId);
    final current = store.lookup(idKey());
    expect(current?.epoch, seeded.epoch);
    expect(store.manifest(idKey(), seeded.epoch, 'device-one'), isNotNull);

    // The full constructor would have rebuilt this index.
    expect(count(locker, 'manifest_refs'), 0);
    expect(count(locker, 'indexed_manifests'), 0);
    locker.execute('ROLLBACK');
  });

  test('break-glass still records its access in the break-glass log', () {
    seedUnindexedStore().server.close();
    final store = AthenaeumStore.breakGlass(config: config);
    addTearDown(store.close);
    store.recordBreakGlassAccess(syncId);

    final log = sqlite3.open(
      '${dataDirectory.path}/athenaeum-break-glass.sqlite',
    );
    addTearDown(log.close);
    expect(count(log, 'break_glass_access'), 1);
    expect(
      log.select('SELECT id_key FROM break_glass_access').single['id_key'],
      idKey(),
    );
  });

  test('the break-glass handle cannot write the store database', () {
    final seeded = seedUnindexedStore();
    addTearDown(seeded.server.close);
    final store = AthenaeumStore.breakGlass(config: config);
    addTearDown(store.close);

    expect(() => store.touch(idKey()), throwsA(isA<SqliteException>()));
    expect(
      () => store.database.execute('DELETE FROM manifests'),
      throwsA(isA<SqliteException>()),
    );
    expect(count(seeded.server.database, 'manifests'), 1);
  });

  test('break-glass opens after a clean server shutdown left no -wal/-shm', () {
    final seeded = seedUnindexedStore();
    seeded.server.close();
    expect(File('${databasePath()}-wal').existsSync(), isFalse);
    expect(File('${databasePath()}-shm').existsSync(), isFalse);

    final store = AthenaeumStore.breakGlass(config: config);
    addTearDown(store.close);
    expect(store.lookup(idKey())?.epoch, seeded.epoch);
  });

  test('break-glass fails, and creates nothing, when the server never ran', () {
    expect(
      () => AthenaeumStore.breakGlass(config: config),
      throwsA(isA<SqliteException>()),
    );
    expect(File(databasePath()).existsSync(), isFalse);
  });

  test(
    'a request that meets a lock released within the timeout succeeds',
    () async {
      final app = AthenaeumApp(config: config);
      addTearDown(app.store.close);
      final key = idKey();
      app.store.create(key);

      // sqlite3 is synchronous, so the waiting request blocks this isolate; the
      // lock therefore has to be held, and released, from another one.
      final ready = ReceivePort();
      await Isolate.spawn(_holdLock, (
        ready.sendPort,
        databasePath(),
        const Duration(milliseconds: 80),
      ));
      final released = StreamIterator<Object?>(ready);
      expect(await released.moveNext() && released.current == 'locked', isTrue);

      final response = await app.handler(
        Request(
          'GET',
          Uri.parse('http://127.0.0.1/v1/store'),
          headers: {'authorization': 'Bearer ${encodeSyncCredential(syncId)}'},
        ),
      );
      expect(response.statusCode, 200);
      await released.cancel();
    },
  );
}

void _holdLock((SendPort, String, Duration) args) {
  final (port, path, hold) = args;
  final database = sqlite3.open(path)..execute('BEGIN IMMEDIATE');
  port.send('locked');
  sleep(hold);
  database.execute('ROLLBACK');
  database.close();
}
