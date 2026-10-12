import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// `PUT /v1/blobs/batch` (sync spec §5.2, §5.3, §5.4).
void main() {
  const syncId = 'café-horse-battery-staple';
  late Directory dataDirectory;
  late AthenaeumApp app;
  late String idKey;
  late String epoch;

  AthenaeumApp appWith({
    AthenaeumQuotaLimits quota = const AthenaeumQuotaLimits(),
  }) {
    final config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    final store = AthenaeumStore(
      config: config,
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: quota,
    );
    return AthenaeumApp(
      config: config,
      store: store,
      clientAddressResolver: (request) =>
          request.headers['x-test-ip'] ?? 'test',
      diagnosticLogger: (_) {},
      alertSink: (_) {},
    );
  }

  void open({AthenaeumQuotaLimits quota = const AthenaeumQuotaLimits()}) {
    app = appWith(quota: quota);
    idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
    epoch = app.store.create(idKey).epoch;
  }

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'athenaeum-blob-batch-upload-',
    );
    open();
  });

  tearDown(() async {
    app.store.close();
    await dataDirectory.delete(recursive: true);
  });

  List<int> frame(String hash, List<int> body) => [
    ...encodeSyncBlobBatchFrameHead(
      SyncBlobBatchFrameStatus.blob,
      hash,
      length: body.length,
    ),
    ...body,
  ];

  List<int> frames(List<List<int>> blobs) => [
    for (final blob in blobs) ...frame(sha256Hex(blob), blob),
  ];

  Future<Response> upload(
    List<int> body, {
    String id = syncId,
    Map<String, String> headers = const {},
  }) => app.call(
    Request(
      'PUT',
      Uri.parse('http://127.0.0.1/v1/blobs/batch'),
      headers: {
        'authorization': 'Bearer ${encodeSyncCredential(id)}',
        'content-type': syncBlobBatchMediaType,
        ...headers,
      },
      body: body,
    ),
  );

  Future<List<int>> statuses(Response response) async {
    expect(response.statusCode, 200);
    final decoded =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    return [
      for (final result in decoded['results']! as List)
        (result as Map)['status']! as int,
    ];
  }

  test('each blob gets the status a single PUT would give it, in request '
      'order', () async {
    final fresh = utf8.encode('{"fresh":true}');
    final held = utf8.encode('{"held":true}');
    app.store.putBlob(
      idKey: idKey,
      epoch: epoch,
      hash: sha256Hex(held),
      body: Uint8List.fromList(held),
    );
    // A recognisable record envelope with a key the allow-list refuses.
    final refused = utf8.encode(
      jsonEncode({
        'v': 1,
        'kind': 'tag',
        'id': 't',
        'updatedAt': '2026-10-12T00:00:00Z',
        'deletedAt': null,
        'existenceAt': '2026-10-12T00:00:00Z',
        'body': {'id': 't', 'name': 'T'},
        'extra': true,
      }),
    );
    final mislabelled = utf8.encode('{"mislabelled":true}');
    final body = [
      ...frames([fresh, held, refused]),
      ...frame(sha256Hex(utf8.encode('something else')), mislabelled),
    ];

    final response = await upload(body);

    expect(await statuses(response), [201, 200, 422, 400]);
    expect(app.store.blobRef(idKey, epoch, sha256Hex(fresh)), isNotNull);
    expect(
      app.store.blobFile(idKey, epoch, sha256Hex(fresh)).readAsBytesSync(),
      fresh,
    );
    expect(app.store.blobRef(idKey, epoch, sha256Hex(refused)), isNull);
  });

  test('past the quota every later new blob is 507, and the ones before it '
      'are stored', () async {
    app.store.close();
    await dataDirectory.delete(recursive: true);
    dataDirectory = await Directory.systemTemp.createTemp(
      'athenaeum-blob-batch-upload-',
    );
    open(quota: const AthenaeumQuotaLimits(maxBlobs: 2));
    final blobs = [for (var i = 0; i < 4; i++) utf8.encode('{"n":$i}')];

    final response = await upload(frames(blobs));

    expect(await statuses(response), [201, 201, 507, 507]);
    expect(app.store.blobRef(idKey, epoch, sha256Hex(blobs[1])), isNotNull);
    expect(app.store.blobRef(idKey, epoch, sha256Hex(blobs[2])), isNull);
    expect(
      app.store.lookup(idKey)!.bytesUsed,
      blobs[0].length + blobs[1].length,
    );
  });

  test('a held blob whose file was lost is written back, unless its size does '
      'not match the record', () async {
    final lost = utf8.encode('{"lost":true}');
    final hash = sha256Hex(lost);
    app.store.putBlob(
      idKey: idKey,
      epoch: epoch,
      hash: hash,
      body: Uint8List.fromList(lost),
    );
    final file = app.store.blobFile(idKey, epoch, hash);
    file.deleteSync();

    expect(await statuses(await upload(frame(hash, lost))), [200]);
    expect(file.readAsBytesSync(), lost);
  });

  group('refuses the whole request', () {
    test('past the frame cap, or with a blob over the size cap', () async {
      final many = [
        for (var i = 0; i <= syncBlobBatchMaxUploadBlobs; i++)
          utf8.encode('$i'),
      ];
      expect((await upload(frames(many))).statusCode, 413);
      final huge = List<int>.filled(maxBlobBytes + 1, 0x61);
      expect((await upload(frames([huge]))).statusCode, 413);
    });

    test('when it is malformed', () async {
      final blob = utf8.encode('{"a":1}');
      for (final body in [
        frames([blob, blob]),
        frame(sha256Hex(blob), blob).sublist(0, 40),
        [
          ...encodeSyncBlobBatchFrameHead(
            SyncBlobBatchFrameStatus.missing,
            sha256Hex(blob),
          ),
        ],
      ]) {
        expect((await upload(body)).statusCode, 400);
      }
      expect(app.store.blobRef(idKey, epoch, sha256Hex(blob)), isNull);
    });

    test('with the wrong media type', () async {
      final response = await upload(
        frames([utf8.encode('{}')]),
        headers: {'content-type': 'application/json'},
      );
      expect(response.statusCode, 415);
    });

    test('for a store that does not resolve, counted as a failed resolution '
        '(§5.4)', () async {
      for (
        var attempt = 0;
        attempt < maxFailedResolutionsPerIpBurst;
        attempt++
      ) {
        final response = await upload(
          frames([utf8.encode('{}')]),
          id: 'unknown-$attempt-café-staple',
        );
        expect(response.statusCode, 404);
      }
      final refused = await upload(
        frames([utf8.encode('{}')]),
        id: 'unknown-final-café-staple',
      );
      expect(refused.statusCode, 429);
    });
  });

  test('accepts a gzip body compressed past 10×', () async {
    final blobs = [
      for (var i = 0; i < 20; i++)
        utf8.encode(jsonEncode({'n': i, 'padding': 'a' * 2000})),
    ];
    final plain = frames(blobs);
    final compressed = gzip.encode(plain);
    expect(plain.length / compressed.length, greaterThan(10));

    final response = await upload(
      compressed,
      headers: {'content-encoding': 'gzip'},
    );

    expect(await statuses(response), List.filled(20, 201));
  });

  test('a GET on the batch route lists both methods it serves', () async {
    final response = await app.call(
      Request(
        'GET',
        Uri.parse('http://127.0.0.1/v1/blobs/batch'),
        headers: {'authorization': 'Bearer ${encodeSyncCredential(syncId)}'},
      ),
    );
    expect(response.statusCode, 405);
    expect(response.headers['allow'], 'POST, PUT');
  });
}
