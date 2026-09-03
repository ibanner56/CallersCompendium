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
}
