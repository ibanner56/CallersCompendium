import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Guards for #1910: garbage collection reads blob reachability from the
/// `manifest_refs` index written at manifest `PUT`, not from manifest bodies.
///
/// The cost guard does not count decodes through a test hook. It replaces
/// already-indexed manifest bodies with bytes that cannot decode, keeping their
/// etags, so any GC that reads one of them throws and collects nothing. GC
/// that succeeds therefore read none of them, whatever their number or size.
void main() {
  late Directory dataDirectory;
  late Database database;
  late DateTime now;
  late AthenaeumConfig config;
  late AthenaeumStore store;
  late AthenaeumApp app;
  const syncId = 'garbage-manifest-horse-staple';
  const junkSyncId = 'garbage-manifest-horse-battery';

  AthenaeumStore openStore() => AthenaeumStore(
    config: config,
    database: database,
    breakGlassDatabase: sqlite3.openInMemory(),
    diagnosticDatabase: sqlite3.openInMemory(),
    clock: () => now,
  );

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('athenaeum-refs-');
    database = sqlite3.openInMemory();
    now = DateTime.utc(2026, 10, 1, 12);
    config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    store = openStore();
    app = AthenaeumApp(
      config: config,
      store: store,
      clientAddressResolver: (_) => 'test',
      clock: () => now,
    );
  });

  tearDown(() {
    store.close();
    dataDirectory.deleteSync(recursive: true);
  });

  Future<Response> send(
    String method,
    String path, {
    Uint8List? body,
    String? contentType,
    String sync = syncId,
  }) async {
    final response = await app.handler(
      Request(
        method,
        Uri.parse('http://127.0.0.1$path'),
        headers: {
          'authorization': 'Bearer ${encodeSyncCredential(sync)}',
          'content-type': ?contentType,
          if (body != null) 'content-length': '${body.length}',
        },
        body: body,
      ),
    );
    return response;
  }

  Future<String> createStore({String sync = syncId}) async {
    final response = await send('POST', '/v1/store', sync: sync);
    expect(response.statusCode, 201);
    final decoded =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    return decoded['epoch']! as String;
  }

  Future<String> uploadBlob(int seed, {String sync = syncId}) async {
    final bytes = Uint8List.fromList(List<int>.generate(97, (i) => i ^ seed));
    final hash = sha256.convert(bytes).toString();
    final response = await send(
      'PUT',
      '/v1/blobs/$hash',
      body: bytes,
      contentType: 'application/octet-stream',
      sync: sync,
    );
    expect(response.statusCode, anyOf(200, 201));
    return hash;
  }

  Uint8List manifestBody(String epoch, String deviceId, List<String> hashes) =>
      encodeSyncManifestUtf8(
        SyncManifest(
          deviceId: deviceId,
          epoch: epoch,
          writtenAt: now,
          records: {
            SyncRecordKind.dance: {
              for (var i = 0; i < hashes.length; i++) 'dance-$i': hashes[i],
            },
          },
        ),
      );

  Future<void> putManifest(
    String epoch,
    String deviceId,
    List<String> hashes,
  ) async {
    final response = await send(
      'PUT',
      '/v1/manifests/$deviceId',
      body: manifestBody(epoch, deviceId, hashes),
      contentType: 'application/json; charset=utf-8',
    );
    expect(response.statusCode, anyOf(200, 201));
  }

  String idKeyOf(String epoch) =>
      database.select('SELECT id_key FROM stores WHERE epoch = ?', [
            epoch,
          ]).single['id_key']
          as String;

  /// Replaces stored bodies with bytes that are neither UTF-8 nor JSON,
  /// leaving every etag as it was.
  void makeBodiesUndecodable(String epoch, List<String> deviceIds) {
    for (final deviceId in deviceIds) {
      database.execute(
        'UPDATE manifests SET body = ? WHERE epoch = ? AND device_id = ?',
        [
          Uint8List.fromList([0xff, 0xfe]),
          epoch,
          deviceId,
        ],
      );
    }
  }

  bool held(String epoch, String hash) =>
      store.blobRef(idKeyOf(epoch), epoch, hash) != null;

  test('post-PUT GC reads no other device manifest body', () async {
    final epoch = await createStore();
    final named = <String>[
      for (var seed = 1; seed <= 8; seed++) await uploadBlob(seed),
    ];
    final unnamed = await uploadBlob(100);
    final others = [for (var i = 0; i < 8; i++) 'device-$i'];
    for (var i = 0; i < others.length; i++) {
      await putManifest(epoch, others[i], [named[i]]);
    }
    now = now.add(const Duration(hours: 25));
    final recent = await uploadBlob(101);
    makeBodiesUndecodable(epoch, others);

    await putManifest(epoch, 'device-pusher', const []);

    expect(held(epoch, unnamed), isFalse, reason: 'stale and unnamed');
    for (final hash in named) {
      expect(held(epoch, hash), isTrue, reason: 'named by another device');
    }
    expect(held(epoch, recent), isTrue, reason: 'inside the 24 h grace');
  });

  test(
    'a replaced manifest stops protecting what it no longer names',
    () async {
      final epoch = await createStore();
      final dropped = await uploadBlob(1);
      final kept = await uploadBlob(2);
      final other = await uploadBlob(3);
      await putManifest(epoch, 'device-one', [dropped, kept]);
      await putManifest(epoch, 'device-two', [other]);
      now = now.add(const Duration(hours: 25));
      final added = await uploadBlob(4);
      now = now.add(const Duration(hours: 25));

      await putManifest(epoch, 'device-one', [kept, added]);

      expect(held(epoch, dropped), isFalse);
      expect(held(epoch, kept), isTrue);
      expect(held(epoch, added), isTrue, reason: 'newly named, past grace');
      expect(held(epoch, other), isTrue, reason: "device-two's manifest");

      // A later GC must not fall back to device-one's body to find `added`.
      makeBodiesUndecodable(epoch, const ['device-one']);
      await putManifest(epoch, 'device-two', const []);
      expect(held(epoch, added), isTrue);
      expect(held(epoch, other), isFalse);
    },
  );

  test('a deleted manifest stops protecting its blobs', () async {
    final epoch = await createStore();
    final hash = await uploadBlob(1);
    await putManifest(epoch, 'device-one', [hash]);
    now = now.add(const Duration(hours: 25));

    final deleted = await send('DELETE', '/v1/manifests/device-one');
    expect(deleted.statusCode, 204);
    await putManifest(epoch, 'device-two', const []);

    expect(held(epoch, hash), isFalse);
  });

  int indexRows(String table, String epoch) =>
      database.select('SELECT COUNT(*) AS n FROM $table WHERE epoch = ?', [
            epoch,
          ]).single['n']
          as int;

  test('deleting the store removes its index rows', () async {
    final epoch = await createStore();
    await putManifest(epoch, 'device-one', [await uploadBlob(1)]);
    expect(indexRows('manifest_refs', epoch), 1);
    expect(indexRows('indexed_manifests', epoch), 1);

    final deleted = await send('DELETE', '/v1/store');
    expect(deleted.statusCode, anyOf(200, 204));

    expect(indexRows('manifest_refs', epoch), 0);
    expect(indexRows('indexed_manifests', epoch), 0);
  });

  test('startup indexes manifests stored before the index existed', () async {
    final epoch = await createStore();
    final named = await uploadBlob(1);
    final unnamed = await uploadBlob(2);
    await putManifest(epoch, 'device-one', [named]);
    final junkEpoch = await createStore(sync: junkSyncId);
    final junkHash = await uploadBlob(3, sync: junkSyncId);
    // The layout a pre-#1910 database has: manifests with no index, one of
    // them a body that does not decode.
    database.execute('DROP TABLE IF EXISTS manifest_refs');
    database.execute('DROP TABLE IF EXISTS indexed_manifests');
    database.execute(
      'INSERT INTO manifests (id_key, epoch, device_id, etag, written_at, body) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        idKeyOf(junkEpoch),
        junkEpoch,
        'device-junk',
        '9' * 64,
        0,
        Uint8List.fromList([0xff]),
      ],
    );

    final restarted = openStore();
    makeBodiesUndecodable(epoch, const ['device-one']);
    now = now.add(const Duration(hours: 25));

    restarted.collectGarbageForStore(idKeyOf(epoch));
    expect(restarted.blobRef(idKeyOf(epoch), epoch, named), isNotNull);
    expect(restarted.blobRef(idKeyOf(epoch), epoch, unnamed), isNull);

    // The body that never decoded is still read by GC, which fails closed on
    // it exactly as it did before the index existed.
    expect(
      () => restarted.collectGarbageForStore(idKeyOf(junkEpoch)),
      throwsFormatException,
    );
    expect(
      restarted.blobRef(idKeyOf(junkEpoch), junkEpoch, junkHash),
      isNotNull,
    );
  });

  test(
    'a manifest rewritten without its index is read and reindexed',
    () async {
      final epoch = await createStore();
      final first = await uploadBlob(1);
      final second = await uploadBlob(2);
      await putManifest(epoch, 'device-one', [first]);
      // What an earlier server image does after a rollback: it replaces the
      // body and etag and knows nothing of the index.
      final rewritten = manifestBody(epoch, 'device-one', [second]);
      database.execute(
        'UPDATE manifests SET body = ?, etag = ? WHERE device_id = ?',
        [rewritten, sha256.convert(rewritten).toString(), 'device-one'],
      );
      now = now.add(const Duration(hours: 25));

      store.collectGarbageForStore(idKeyOf(epoch));
      expect(held(epoch, second), isTrue, reason: 'read from the new body');

      final restarted = openStore();
      makeBodiesUndecodable(epoch, const ['device-one']);
      restarted.collectGarbageForStore(idKeyOf(epoch));
      expect(restarted.blobRef(idKeyOf(epoch), epoch, second), isNotNull);
      expect(restarted.blobRef(idKeyOf(epoch), epoch, first), isNull);

      // An earlier image deleting the manifest leaves index rows behind; the
      // next start drops them.
      database.execute('DELETE FROM manifests WHERE device_id = ?', [
        'device-one',
      ]);
      openStore();
      expect(indexRows('manifest_refs', epoch), 0);
      expect(indexRows('indexed_manifests', epoch), 0);
    },
  );
}
