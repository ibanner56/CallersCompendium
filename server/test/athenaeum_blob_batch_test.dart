import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// `POST /v1/blobs/batch` (sync spec §5.2, §5.3, §5.4).
void main() {
  const syncId = 'café-horse-battery-staple';
  late Directory dataDirectory;
  late AthenaeumConfig config;
  late AthenaeumApp app;
  late String idKey;
  late String epoch;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'athenaeum-blob-batch-',
    );
    config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    app = AthenaeumApp(
      config: config,
      clientAddressResolver: (request) =>
          request.headers['x-test-ip'] ?? 'test',
    );
    idKey = deriveIncomingSyncIdKey(syncId, config.pepper);
    epoch = app.store.create(idKey).epoch;
  });

  tearDown(() async {
    app.store.close();
    await dataDirectory.delete(recursive: true);
  });

  String put(List<int> bytes) {
    final body = Uint8List.fromList(bytes);
    final hash = sha256Hex(body);
    app.store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: body);
    return hash;
  }

  Request batchRequest(
    Object? body, {
    String id = syncId,
    String method = 'POST',
    Map<String, String> headers = const {},
  }) => Request(
    method,
    Uri.parse('http://127.0.0.1/v1/blobs/batch'),
    headers: {
      'authorization': 'Bearer ${encodeSyncCredential(id)}',
      'content-type': 'application/json',
      ...headers,
    },
    body: method == 'POST' ? utf8.encode(jsonEncode(body)) : null,
  );

  Future<List<SyncBlobBatchFrame>> frames(
    Response response,
    List<String> hashes,
  ) async {
    final reader = SyncBlobBatchFrameReader(hashes, maxBlobBytes: maxBlobBytes);
    final result = <SyncBlobBatchFrame>[];
    await for (final chunk in response.read()) {
      result.addAll(reader.add(chunk));
    }
    reader.close();
    return result;
  }

  test('answers every hash once, in request order, with its bytes or '
      'missing', () async {
    final first = put(utf8.encode('{"first":true}'));
    final second = put(utf8.encode('{"second":true}'));
    final unreferenced = sha256Hex(utf8.encode('never uploaded'));
    final fileLost = put(utf8.encode('{"lost":true}'));
    app.store.blobFile(idKey, epoch, fileLost).deleteSync();
    final hashes = [second, unreferenced, first, fileLost];

    final response = await app.call(batchRequest({'hashes': hashes}));

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], syncBlobBatchMediaType);
    expect(response.headers['cache-control'], 'no-store');
    expect(response.headers['content-encoding'], isNull);
    final answered = await frames(response, hashes);
    expect([for (final frame in answered) frame.hash], hashes);
    expect(
      [for (final frame in answered) frame.status],
      [
        SyncBlobBatchFrameStatus.blob,
        SyncBlobBatchFrameStatus.missing,
        SyncBlobBatchFrameStatus.blob,
        SyncBlobBatchFrameStatus.missing,
      ],
    );
    expect(utf8.decode(answered[0].body!), '{"second":true}');
    expect(utf8.decode(answered[2].body!), '{"first":true}');
  });

  test('a blob only another store holds is missing', () async {
    final hash = put(utf8.encode('{"old":true}'));
    app.store.create(
      deriveIncomingSyncIdKey('other-horse-battery-staple', config.pepper),
    );
    // Blobs are namespaced by store and epoch (§7.1): the same hash uploaded
    // to another store is not this one's to serve.
    final response = await app.call(
      batchRequest({
        'hashes': [hash],
      }, id: 'other-horse-battery-staple'),
    );
    final answered = await frames(response, [hash]);
    expect(answered.single.status, SyncBlobBatchFrameStatus.missing);
  });

  test('caps the hashes one request may name', () async {
    String hash(int i) => sha256Hex(utf8.encode('$i'));
    final atCap = await app.call(
      batchRequest({
        'hashes': [for (var i = 0; i < syncBlobBatchMaxHashes; i++) hash(i)],
      }),
    );
    expect(atCap.statusCode, 200);
    await atCap.read().drain<void>();

    final overCap = await app.call(
      batchRequest({
        'hashes': [for (var i = 0; i <= syncBlobBatchMaxHashes; i++) hash(i)],
      }),
    );
    expect(overCap.statusCode, 413);
  });

  test('a body larger than the request cap is refused before it is '
      'parsed', () async {
    final response = await app.call(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1/v1/blobs/batch'),
        headers: {
          'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
          'content-type': 'application/json',
        },
        body: Uint8List(maxBlobBatchRequestBytes + 1),
      ),
    );
    expect(response.statusCode, 413);
  });

  test('stops at the byte cap and lists the rest as not sent', () async {
    // Three blobs of 0.9 MB: the first two fit under the 2 MB cap, the third
    // does not. The fourth is small enough to fit, and is still not sent: a
    // response never skips ahead, so what it carries is a prefix.
    const size = 900 * 1024;
    final big = [
      for (var i = 0; i < 3; i++) put(List<int>.filled(size, 0x30 + i)),
    ];
    final small = put(utf8.encode('{"small":true}'));
    final hashes = [...big, small];

    final response = await app.call(batchRequest({'hashes': hashes}));
    final answered = await frames(response, hashes);

    expect(
      [for (final frame in answered) frame.status],
      [
        SyncBlobBatchFrameStatus.blob,
        SyncBlobBatchFrameStatus.blob,
        SyncBlobBatchFrameStatus.notSent,
        SyncBlobBatchFrameStatus.notSent,
      ],
    );
    final sent = answered.fold<int>(
      0,
      (total, frame) => total + (frame.body?.length ?? 0),
    );
    expect(sent, lessThanOrEqualTo(syncBlobBatchMaxBlobBytes));

    // Asked again, the rest arrive.
    final rest = hashes.sublist(2);
    final again = await frames(
      await app.call(batchRequest({'hashes': rest})),
      rest,
    );
    expect(
      [for (final frame in again) frame.status],
      [SyncBlobBatchFrameStatus.blob, SyncBlobBatchFrameStatus.blob],
    );
  });

  test('a blob of the largest size is always sent first', () async {
    final hash = put(List<int>.filled(maxBlobBytes, 0x31));
    final answered = await frames(
      await app.call(
        batchRequest({
          'hashes': [hash],
        }),
      ),
      [hash],
    );
    expect(answered.single.status, SyncBlobBatchFrameStatus.blob);
    expect(answered.single.body, hasLength(maxBlobBytes));
  });

  test('streams: a blob is read only when its frame is reached', () async {
    final first = put(utf8.encode('{"first":true}'));
    final last = put(utf8.encode('{"last":true}'));
    final hashes = [first, last];
    final response = await app.call(batchRequest({'hashes': hashes}));
    final reader = SyncBlobBatchFrameReader(hashes, maxBlobBytes: maxBlobBytes);
    final answered = <SyncBlobBatchFrame>[];
    final iterator = StreamIterator(response.read());
    while (answered.isEmpty && await iterator.moveNext()) {
      answered.addAll(reader.add(iterator.current));
    }
    expect(answered.single.hash, first);
    // A response built before it was sent would already hold this blob.
    app.store.blobFile(idKey, epoch, last).deleteSync();
    while (await iterator.moveNext()) {
      answered.addAll(reader.add(iterator.current));
    }
    reader.close();
    expect(answered.last.hash, last);
    expect(answered.last.status, SyncBlobBatchFrameStatus.missing);
  });

  group('gzip', () {
    late List<String> hashes;

    setUp(() {
      hashes = [
        for (var i = 0; i < 20; i++)
          put(
            utf8.encode(
              jsonEncode({
                'kind': 'dance',
                'id': 'dance-$i',
                'body': {'title': 'Dance $i', 'figures': List.filled(8, 'x')},
              }),
            ),
          ),
      ];
    });

    test('compresses when the client accepts it', () async {
      final plain = await app.call(batchRequest({'hashes': hashes}));
      final plainBytes = await _bytes(plain);
      final compressed = await app.call(
        batchRequest(
          {'hashes': hashes},
          headers: {'accept-encoding': 'deflate, gzip;q=0.5'},
        ),
      );
      expect(compressed.headers['content-encoding'], 'gzip');
      expect(compressed.headers['vary'], 'accept-encoding');
      final wire = await _bytes(compressed);
      expect(wire.length, lessThan(plainBytes.length));
      expect(gzip.decode(wire), plainBytes);
    });

    test('does not compress for a client that refuses it', () async {
      for (final header in ['identity', 'gzip;q=0', 'gzip; q=0.0']) {
        final response = await app.call(
          batchRequest(
            {'hashes': hashes},
            headers: {'accept-encoding': header},
          ),
        );
        expect(response.headers['content-encoding'], isNull, reason: header);
        await response.read().drain<void>();
      }
    });
  });

  test('rejects malformed requests', () async {
    final hash = sha256Hex(utf8.encode('x'));
    for (final (body, status) in [
      ({'hashes': 'nope'}, 400),
      (<String, Object?>{}, 400),
      (
        {
          'hashes': ['ABC'],
        },
        400,
      ),
      (
        {
          'hashes': [hash.toUpperCase()],
        },
        400,
      ),
      (
        {
          'hashes': [hash, hash],
        },
        400,
      ),
    ]) {
      final response = await app.call(batchRequest(body));
      expect(response.statusCode, status, reason: '$body');
    }
    final get = await app.call(batchRequest(null, method: 'GET'));
    expect(get.statusCode, 405);
    expect(get.headers['allow'], 'POST');
    final wrongType = await app.call(
      batchRequest(
        {
          'hashes': [hash],
        },
        headers: {'content-type': 'text/plain'},
      ),
    );
    expect(wrongType.statusCode, 415);
  });

  test('an unknown store is a failed resolution (§5.4)', () async {
    for (var attempt = 0; attempt < maxFailedResolutionsPerIpBurst; attempt++) {
      final response = await app.call(
        batchRequest({
          'hashes': <String>[],
        }, id: 'unknown-$attempt-café-staple'),
      );
      expect(response.statusCode, 404);
    }
    final refused = await app.call(
      batchRequest({'hashes': <String>[]}, id: 'unknown-final-café-staple'),
    );
    expect(refused.statusCode, 429);
    // A store that resolves is still served while the failure budget sheds.
    final served = await app.call(batchRequest({'hashes': <String>[]}));
    expect(served.statusCode, 200);
  });

  test('a single-blob GET is unchanged beside it', () async {
    final hash = put(utf8.encode('{"single":true}'));
    final response = await app.call(
      Request(
        'GET',
        Uri.parse('http://127.0.0.1/v1/blobs/$hash'),
        headers: {'authorization': 'Bearer ${encodeSyncCredential(syncId)}'},
      ),
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'application/octet-stream');
    expect(
      response.headers['cache-control'],
      'private, max-age=31536000, immutable',
    );
    expect(utf8.decode(await _bytes(response)), '{"single":true}');
  });
}

Future<Uint8List> _bytes(Response response) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response.read()) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
