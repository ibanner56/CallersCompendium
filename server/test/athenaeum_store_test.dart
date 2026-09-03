import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('store deletion rolls back all metadata when a delete fails', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'a' * 64;
    final created = store.create(idKey);
    store.putManifest(
      idKey: idKey,
      epoch: created.epoch,
      deviceId: 'device-one',
      etag: 'b' * 64,
      writtenAt: 0,
      body: Uint8List.fromList([1]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'c' * 64,
      body: Uint8List.fromList([2]),
    );
    database.execute(
      'CREATE TRIGGER fail_blob_delete BEFORE DELETE ON blob_refs '
      "BEGIN SELECT RAISE(ABORT, 'injected delete failure'); END",
    );
    expect(() => store.deleteStore(idKey), throwsA(isA<SqliteException>()));
    expect(store.lookup(idKey), isNotNull);
    expect(store.manifest(idKey, created.epoch, 'device-one'), isNotNull);
  });

  test('filesystem deletion failures remain queued for retry', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    var failDelete = true;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      deleteDirectory: (directory) {
        if (failDelete) {
          throw const FileSystemException('injected filesystem failure');
        }
        directory.deleteSync(recursive: true);
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'd' * 64;
    final created = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'e' * 64,
      body: Uint8List.fromList([2]),
    );
    final blobFile = store.blobFile(idKey, created.epoch, 'e' * 64);

    store.deleteStore(idKey);
    expect(blobFile.existsSync(), isTrue);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(1));
    expect(store.lookup(idKey), isNull);

    final recreated = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'e' * 64,
      body: Uint8List.fromList([3]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: recreated.epoch,
      hash: 'f' * 64,
      body: Uint8List.fromList([4]),
    );
    store.deleteStore(idKey);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(2));

    failDelete = false;
    store.retryPendingDeletions();
    expect(blobFile.existsSync(), isFalse);
    expect(database.select('SELECT * FROM deletion_jobs'), isEmpty);
  });

  test('deleting a recreated store cleans stale epoch directories', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'f' * 64;
    final first = store.create(idKey);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: first.epoch,
      hash: '1' * 64,
      body: Uint8List.fromList([3]),
    );
    final staleFile = store.blobFile(idKey, first.epoch, '1' * 64);
    final currentFile = store.blobFile(idKey, recreated.epoch, '2' * 64);
    currentFile.parent.createSync(recursive: true);
    currentFile.writeAsBytesSync([4]);

    store.deleteStore(idKey);
    store.retryPendingDeletions();

    expect(staleFile.existsSync(), isFalse);
    expect(currentFile.existsSync(), isFalse);
  });
}
