import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory dataDirectory;
  late AthenaeumApp app;
  late HttpServer server;
  late HttpClient client;
  const syncId = 'café-horse-battery-staple';

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('athenaeum-test-');
    final config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    app = AthenaeumApp(
      config: config,
      clientAddressResolver: (request) =>
          request.headers['x-test-ip'] ?? 'test',
    );
    server = await shelf_io.serve(app.handler, InternetAddress.loopbackIPv4, 0);
    client = HttpClient();
    _activeClient = client;
    _activeServer = server;
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    app.store.close();
    await dataDirectory.delete(recursive: true);
  });

  test('C2 loopback round trip preserves manifest and blob bytes', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    expect(created.statusCode, 201);
    final store = jsonDecode(await created.body()) as Map<String, Object?>;
    final epoch = store['epoch']! as String;
    final manifest = SyncManifest(
      deviceId: 'device-one',
      epoch: epoch,
      writtenAt: DateTime.utc(2026, 9, 3, 0, 0, 0),
      records: {
        SyncRecordKind.dance: {'dance-one': 'a' * 64},
      },
    );
    final manifestBytes = encodeSyncManifestUtf8(manifest);
    final manifestPut = await _send(
      'PUT',
      '/v1/manifests/device-one',
      syncId: syncId,
      body: manifestBytes,
      contentType: 'application/json; charset=utf-8',
    );
    expect(manifestPut.statusCode, 201);
    final repeatedManifestPut = await _send(
      'PUT',
      '/v1/manifests/device-one',
      syncId: syncId,
      body: manifestBytes,
      contentType: 'application/json; charset=utf-8',
    );
    expect(repeatedManifestPut.statusCode, 200);
    final manifestGet = await _send(
      'GET',
      '/v1/manifests/device-one',
      syncId: syncId,
    );
    expect(manifestGet.statusCode, 200);
    expect(await manifestGet.bodyBytes(), equals(manifestBytes));
    final etag = manifestGet.headers.value('etag')!;
    expect(etag, '"${sha256.convert(manifestBytes)}"');
    final unchanged = await _send(
      'GET',
      '/v1/manifests/device-one',
      syncId: syncId,
      headers: {'if-none-match': etag},
    );
    expect(unchanged.statusCode, 304);

    final blobBytes = Uint8List.fromList(List<int>.generate(257, (i) => i));
    final hash = sha256.convert(blobBytes).toString();
    final blobPut = await _send(
      'PUT',
      '/v1/blobs/$hash',
      syncId: syncId,
      body: blobBytes,
      contentType: 'application/octet-stream',
    );
    expect(blobPut.statusCode, 201);
    final duplicateBlobPut = await _send(
      'PUT',
      '/v1/blobs/$hash',
      syncId: syncId,
      body: blobBytes,
      contentType: 'application/octet-stream',
    );
    expect(duplicateBlobPut.statusCode, 200);
    final blobGet = await _send('GET', '/v1/blobs/$hash', syncId: syncId);
    expect(blobGet.statusCode, 200);
    expect(await blobGet.bodyBytes(), equals(blobBytes));
    expect(
      blobGet.headers.value('cache-control'),
      'private, max-age=31536000, immutable',
    );
  });

  test(
    'blob allow-list rejects non-shareable fields and tolerates new versions',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );

      final shareable = _recordBlob(
        kind: 'choreographer',
        id: 'c1',
        body: {'id': 'c1', 'name': 'Alice Choreo'},
      );
      final shareableHash = sha256.convert(shareable).toString();
      final accepted = await _send(
        'PUT',
        '/v1/blobs/$shareableHash',
        syncId: syncId,
        body: shareable,
        contentType: 'application/octet-stream',
      );
      expect(accepted.statusCode, 201);
      final acceptedFetch = await _send(
        'GET',
        '/v1/blobs/$shareableHash',
        syncId: syncId,
      );
      expect(acceptedFetch.statusCode, 200);
      expect(await acceptedFetch.bodyBytes(), equals(shareable));

      final nonShareable = _recordBlob(
        kind: 'choreographer',
        id: 'c2',
        body: {
          'id': 'c2',
          'name': 'Private Choreo',
          'email': 'private@example.com',
        },
      );
      final nonShareableHash = sha256.convert(nonShareable).toString();
      final rejected = await _send(
        'PUT',
        '/v1/blobs/$nonShareableHash',
        syncId: syncId,
        body: nonShareable,
        contentType: 'application/octet-stream',
      );
      expect(rejected.statusCode, 422);
      await rejected.drain<void>();
      final rejectedFetch = await _send(
        'GET',
        '/v1/blobs/$nonShareableHash',
        syncId: syncId,
      );
      expect(rejectedFetch.statusCode, 404);
      await rejectedFetch.drain<void>();

      final dottedKey = _recordBlob(
        kind: 'dance',
        id: 'dotted-key',
        body: {'formation.shape': 'private'},
      );
      final dottedKeyHash = sha256.convert(dottedKey).toString();
      final dottedKeyResponse = await _send(
        'PUT',
        '/v1/blobs/$dottedKeyHash',
        syncId: syncId,
        body: dottedKey,
        contentType: 'application/octet-stream',
      );
      expect(dottedKeyResponse.statusCode, 422);
      await dottedKeyResponse.drain<void>();
      final dottedKeyGet = await _send(
        'GET',
        '/v1/blobs/$dottedKeyHash',
        syncId: syncId,
      );
      expect(dottedKeyGet.statusCode, 404);
      await dottedKeyGet.drain<void>();

      final invalidEntityId = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'kind': 'choreographer',
            'id': 7,
            'updatedAt': '2026-09-03T00:00:00.000Z',
            'deletedAt': null,
            'existenceAt': '2026-09-03T00:00:00.000Z',
            'body': {'email': 'invalid-id-private@example.com'},
          }),
        ),
      );
      final invalidEntityIdHash = sha256.convert(invalidEntityId).toString();
      final invalidEntityIdResponse = await _send(
        'PUT',
        '/v1/blobs/$invalidEntityIdHash',
        syncId: syncId,
        body: invalidEntityId,
        contentType: 'application/octet-stream',
      );
      expect(invalidEntityIdResponse.statusCode, 422);
      await invalidEntityIdResponse.drain<void>();

      final duplicateBody = Uint8List.fromList(
        utf8.encode(
          '{"v":1,"kind":"choreographer","id":"duplicate-body",'
          '"updatedAt":"2026-09-03T00:00:00.000Z","deletedAt":null,'
          '"existenceAt":"2026-09-03T00:00:00.000Z",'
          '"body":{"email":"duplicate-private@example.com"},'
          '"body":{"id":"duplicate-body","name":"Public"}}',
        ),
      );
      final duplicateBodyHash = sha256.convert(duplicateBody).toString();
      final duplicateBodyResponse = await _send(
        'PUT',
        '/v1/blobs/$duplicateBodyHash',
        syncId: syncId,
        body: duplicateBody,
        contentType: 'application/octet-stream',
      );
      expect(duplicateBodyResponse.statusCode, 422);
      await duplicateBodyResponse.drain<void>();

      final duplicateNestedBody = Uint8List.fromList(
        utf8.encode(
          '{"v":1,"kind":"dance","id":"duplicate-nested",'
          '"updatedAt":"2026-09-03T00:00:00.000Z","deletedAt":null,'
          '"existenceAt":"2026-09-03T00:00:00.000Z",'
          '"body":{"id":"duplicate-nested",'
          '"formation":{"secret":"duplicate-private"},'
          '"formation":{"shape":"longways"}}}',
        ),
      );
      final duplicateNestedBodyHash = sha256
          .convert(duplicateNestedBody)
          .toString();
      final duplicateNestedBodyResponse = await _send(
        'PUT',
        '/v1/blobs/$duplicateNestedBodyHash',
        syncId: syncId,
        body: duplicateNestedBody,
        contentType: 'application/octet-stream',
      );
      expect(duplicateNestedBodyResponse.statusCode, 422);
      await duplicateNestedBodyResponse.drain<void>();
      final duplicateNestedBodyGet = await _send(
        'GET',
        '/v1/blobs/$duplicateNestedBodyHash',
        syncId: syncId,
      );
      expect(duplicateNestedBodyGet.statusCode, 404);
      await duplicateNestedBodyGet.drain<void>();

      final invalidBodyType = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'kind': 'choreographer',
            'id': 'invalid-body',
            'updatedAt': '2026-09-03T00:00:00.000Z',
            'deletedAt': null,
            'existenceAt': '2026-09-03T00:00:00.000Z',
            'body': [
              {'email': 'invalid-body-private@example.com'},
            ],
          }),
        ),
      );
      final invalidBodyTypeHash = sha256.convert(invalidBodyType).toString();
      final invalidBodyTypeResponse = await _send(
        'PUT',
        '/v1/blobs/$invalidBodyTypeHash',
        syncId: syncId,
        body: invalidBodyType,
        contentType: 'application/octet-stream',
      );
      expect(invalidBodyTypeResponse.statusCode, 422);
      await invalidBodyTypeResponse.drain<void>();

      final unknownEnvelopeField = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'kind': 'choreographer',
            'id': 'unknown-envelope-field',
            'updatedAt': '2026-09-03T00:00:00.000Z',
            'deletedAt': null,
            'existenceAt': '2026-09-03T00:00:00.000Z',
            'body': {'id': 'unknown-envelope-field', 'name': 'Public'},
            'email': 'unknown-envelope-private@example.com',
          }),
        ),
      );
      final unknownEnvelopeFieldHash = sha256
          .convert(unknownEnvelopeField)
          .toString();
      final unknownEnvelopeFieldResponse = await _send(
        'PUT',
        '/v1/blobs/$unknownEnvelopeFieldHash',
        syncId: syncId,
        body: unknownEnvelopeField,
        contentType: 'application/octet-stream',
      );
      expect(unknownEnvelopeFieldResponse.statusCode, 422);
      await unknownEnvelopeFieldResponse.drain<void>();

      final malformedEnvelope = Uint8List.fromList(
        utf8.encode(
          '{"v":1,"kind":"choreographer","id":"malformed",'
          '"updatedAt":"2026-09-03T00:00:00.000Z","deletedAt":null,'
          '"existenceAt":"2026-09-03T00:00:00.000Z",'
          '"body":{"email":"malformed-private@example.com"},}',
        ),
      );
      final malformedEnvelopeHash = sha256
          .convert(malformedEnvelope)
          .toString();
      final malformedEnvelopeResponse = await _send(
        'PUT',
        '/v1/blobs/$malformedEnvelopeHash',
        syncId: syncId,
        body: malformedEnvelope,
        contentType: 'application/octet-stream',
      );
      expect(malformedEnvelopeResponse.statusCode, 422);
      await malformedEnvelopeResponse.drain<void>();
      final malformedEnvelopeGet = await _send(
        'GET',
        '/v1/blobs/$malformedEnvelopeHash',
        syncId: syncId,
      );
      expect(malformedEnvelopeGet.statusCode, 404);
      await malformedEnvelopeGet.drain<void>();

      final futureShareable = _recordBlob(
        version: 99,
        kind: 'choreographer',
        id: 'c3',
        body: {'id': 'c3', 'name': 'Future Choreo'},
      );
      final futureShareableHash = sha256.convert(futureShareable).toString();
      final futureAccepted = await _send(
        'PUT',
        '/v1/blobs/$futureShareableHash',
        syncId: syncId,
        body: futureShareable,
        contentType: 'application/octet-stream',
      );
      expect(futureAccepted.statusCode, 201);

      final futureNonShareable = _recordBlob(
        version: 99,
        kind: 'choreographer',
        id: 'c4',
        body: {
          'id': 'c4',
          'name': 'Future Choreo',
          'email': 'future-private@example.com',
        },
      );
      final futureNonShareableHash = sha256
          .convert(futureNonShareable)
          .toString();
      final futureRejected = await _send(
        'PUT',
        '/v1/blobs/$futureNonShareableHash',
        syncId: syncId,
        body: futureNonShareable,
        contentType: 'application/octet-stream',
      );
      expect(futureRejected.statusCode, 422);
      await futureRejected.drain<void>();

      final unknownKind = _recordBlob(
        version: 99,
        kind: 'futureKind',
        id: 'future-1',
        body: {'secret': 'must not cross the boundary'},
      );
      final unknownKindHash = sha256.convert(unknownKind).toString();
      final unknownKindResponse = await _send(
        'PUT',
        '/v1/blobs/$unknownKindHash',
        syncId: syncId,
        body: unknownKind,
        contentType: 'application/octet-stream',
      );
      expect(unknownKindResponse.statusCode, 422);
      await unknownKindResponse.drain<void>();
      final unknownKindFetch = await _send(
        'GET',
        '/v1/blobs/$unknownKindHash',
        syncId: syncId,
      );
      expect(unknownKindFetch.statusCode, 404);
      await unknownKindFetch.drain<void>();

      final opaque = Uint8List.fromList([0, 1, 2, 255]);
      final opaqueHash = sha256.convert(opaque).toString();
      final opaquePut = await _send(
        'PUT',
        '/v1/blobs/$opaqueHash',
        syncId: syncId,
        body: opaque,
        contentType: 'application/octet-stream',
      );
      expect(opaquePut.statusCode, 201);
      final opaqueGet = await _send(
        'GET',
        '/v1/blobs/$opaqueHash',
        syncId: syncId,
      );
      expect(opaqueGet.statusCode, 200);
      expect(await opaqueGet.bodyBytes(), equals(opaque));

      final jsonOpaque = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'kind': 'choreographer',
            'id': 'json-opaque',
            'body': {
              'id': 'json-opaque',
              'name': 'Opaque JSON',
              'email': 'opaque@example.com',
            },
          }),
        ),
      );
      final jsonOpaqueHash = sha256.convert(jsonOpaque).toString();
      final jsonOpaquePut = await _send(
        'PUT',
        '/v1/blobs/$jsonOpaqueHash',
        syncId: syncId,
        body: jsonOpaque,
        contentType: 'application/octet-stream',
      );
      expect(jsonOpaquePut.statusCode, 201);
      final jsonOpaqueGet = await _send(
        'GET',
        '/v1/blobs/$jsonOpaqueHash',
        syncId: syncId,
      );
      expect(jsonOpaqueGet.statusCode, 200);
      expect(await jsonOpaqueGet.bodyBytes(), equals(jsonOpaque));

      final deepOpaque = Uint8List.fromList(
        utf8.encode(
          '{"payload":${'[' * (maxJsonDepth + 1)}0${']' * (maxJsonDepth + 1)}}',
        ),
      );
      final deepOpaqueHash = sha256.convert(deepOpaque).toString();
      final deepOpaquePut = await _send(
        'PUT',
        '/v1/blobs/$deepOpaqueHash',
        syncId: syncId,
        body: deepOpaque,
        contentType: 'application/octet-stream',
      );
      expect(deepOpaquePut.statusCode, 201);
      final deepOpaqueGet = await _send(
        'GET',
        '/v1/blobs/$deepOpaqueHash',
        syncId: syncId,
      );
      expect(deepOpaqueGet.statusCode, 200);
      expect(await deepOpaqueGet.bodyBytes(), equals(deepOpaque));

      final deepRecord = Uint8List.fromList(
        utf8.encode(
          '{"v":1,"kind":"choreographer","id":"deep","body":'
          '{"id":"deep","name":"Deep","nested":'
          '${'[' * (maxJsonDepth + 1)}0${']' * (maxJsonDepth + 1)}}}',
        ),
      );
      final deepRecordHash = sha256.convert(deepRecord).toString();
      final deepRecordPut = await _send(
        'PUT',
        '/v1/blobs/$deepRecordHash',
        syncId: syncId,
        body: deepRecord,
        contentType: 'application/octet-stream',
      );
      expect(deepRecordPut.statusCode, 413);
      await deepRecordPut.drain<void>();
      final deepRecordGet = await _send(
        'GET',
        '/v1/blobs/$deepRecordHash',
        syncId: syncId,
      );
      expect(deepRecordGet.statusCode, 404);
      await deepRecordGet.drain<void>();
    },
  );

  test(
    'blob allow-list resolves settings keys through the shared registry',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      settingsPrefixClassifications['test_shareable:'] =
          const DataClassification(
            term: DpvTerm.nonPersonal,
            subject: DataSubject.appUser,
            egress: EgressClass.shareable,
          );
      addTearDown(
        () => settingsPrefixClassifications.remove('test_shareable:'),
      );

      Future<HttpClientResponse> putSetting(String id, String value) {
        final body = _recordBlob(
          kind: 'setting',
          id: id,
          body: {'value': value},
        );
        final hash = sha256.convert(body).toString();
        return _send(
          'PUT',
          '/v1/blobs/$hash',
          syncId: syncId,
          body: body,
          contentType: 'application/octet-stream',
        );
      }

      expect((await putSetting('custom_dialects', 'exact')).statusCode, 201);
      expect(
        (await putSetting('test_shareable:one', 'prefix')).statusCode,
        201,
      );
      final unknown = await putSetting('unknown_runtime_key', 'secret');
      expect(unknown.statusCode, 422);
      await unknown.drain<void>();
    },
  );

  test('GET and POST store lifecycle remain distinct', () async {
    final missingOne = await _send('GET', '/v1/store', syncId: syncId);
    final missingTwo = await _send('GET', '/v1/store', syncId: syncId);
    expect(missingOne.statusCode, 404);
    expect(missingTwo.statusCode, 404);
    final created = await _send('POST', '/v1/store', syncId: syncId);
    expect(created.statusCode, 201);
    final before = jsonDecode(await created.body()) as Map<String, Object?>;
    final duplicate = await _send('POST', '/v1/store', syncId: syncId);
    expect(duplicate.statusCode, 409);
    final after = await _send('GET', '/v1/store', syncId: syncId);
    final afterBody = jsonDecode(await after.body()) as Map<String, Object?>;
    expect(afterBody['epoch'], before['epoch']);
    expect(afterBody['devices'], isEmpty);
  });

  test('weak structurally valid sync IDs are accepted', () async {
    final response = await _send(
      'POST',
      '/v1/store',
      syncId: 'one-two-three-four',
    );
    expect(response.statusCode, 201);
  });

  test('normalized sync IDs resolve to the same store', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    final before = jsonDecode(await created.body()) as Map<String, Object?>;
    for (final equivalent in [
      ' CAFÉ-HORSE-BATTERY-STAPLE ',
      ' cafe\u0301-horse-battery-staple ',
    ]) {
      final response = await _send('GET', '/v1/store', syncId: equivalent);
      final body = jsonDecode(await response.body()) as Map<String, Object?>;
      expect(response.statusCode, 200);
      expect(body['epoch'], before['epoch']);
    }
  });

  test(
    'concurrent creators share one epoch and reset creates a new one',
    () async {
      const concurrentId = 'concurrent-café-horse-staple';
      final responses = await Future.wait(
        List.generate(
          8,
          (_) => _send('POST', '/v1/store', syncId: concurrentId),
        ),
      );
      final statuses = responses
          .map((response) => response.statusCode)
          .toList();
      for (final response in responses) {
        await response.drain<void>();
      }
      expect(statuses.where((status) => status == 201), hasLength(1));
      expect(statuses.where((status) => status == 409), hasLength(7));
      final before = await _send('GET', '/v1/store', syncId: concurrentId);
      final beforeBody =
          jsonDecode(await before.body()) as Map<String, Object?>;
      expect(
        (await _send('DELETE', '/v1/store', syncId: concurrentId)).statusCode,
        204,
      );
      final recreated = await _send('POST', '/v1/store', syncId: concurrentId);
      final recreatedBody =
          jsonDecode(await recreated.body()) as Map<String, Object?>;
      expect(recreated.statusCode, 201);
      expect(recreatedBody['epoch'], isNot(beforeBody['epoch']));
      expect(recreatedBody['epoch'], hasLength(32));
    },
  );

  test(
    'credential, path, media type, and request boundary failures are typed',
    () async {
      final malformed = await _send(
        'GET',
        '/v1/store',
        credential: '%%%invalid',
      );
      expect(malformed.statusCode, 401);
      final malformedUtf8 = await _send(
        'GET',
        '/v1/store',
        credential: base64Url.encode([0xc3, 0x28]).replaceAll('=', ''),
      );
      expect(malformedUtf8.statusCode, 401);
      final invalidPath = await _send(
        'GET',
        '/v1/blobs/${'a' * 63}',
        syncId: syncId,
      );
      expect(invalidPath.statusCode, 400);
      final created = await _send('POST', '/v1/store', syncId: syncId);
      expect(created.statusCode, 201);
      final wrongType = await _send(
        'PUT',
        '/v1/blobs/${'a' * 64}',
        syncId: syncId,
        body: Uint8List(0),
        contentType: 'text/plain',
      );
      expect(wrongType.statusCode, 415);
      final missingType = await _send(
        'POST',
        '/v1/store',
        syncId: 'new-café-horse-staple',
      );
      expect(missingType.statusCode, 201);
      final tooLarge = await _send(
        'PUT',
        '/v1/blobs/${'a' * 64}',
        syncId: syncId,
        body: Uint8List(maxBlobBytes + 1),
        contentType: 'application/octet-stream',
      );
      expect(tooLarge.statusCode, 413);

      final oversizedManifest = Uint8List(maxManifestBytes + 1);
      final manifestTooLarge = await _send(
        'PUT',
        '/v1/manifests/device-one',
        syncId: syncId,
        body: oversizedManifest,
        contentType: 'application/json',
      );
      expect(manifestTooLarge.statusCode, 413);

      final deepJson = utf8.encode(
        '[' * (maxJsonDepth + 2) + ']' * (maxJsonDepth + 2),
      );
      final tooDeep = await _send(
        'POST',
        '/v1/blobs/missing',
        syncId: syncId,
        body: Uint8List.fromList(deepJson),
        contentType: 'application/json',
      );
      expect(tooDeep.statusCode, 413);

      final tooManyHashes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({'hashes': List<int>.filled(maxMissingHashes + 1, 0)}),
        ),
      );
      final tooMany = await _send(
        'POST',
        '/v1/blobs/missing',
        syncId: syncId,
        body: tooManyHashes,
        contentType: 'application/json',
      );
      expect(tooMany.statusCode, 413);

      final expanded = Uint8List.fromList(List<int>.filled(1024, 0x61));
      final compressed = Uint8List.fromList(gzip.encode(expanded));
      final expansion = await _send(
        'PUT',
        '/v1/blobs/${'b' * 64}',
        syncId: syncId,
        body: compressed,
        contentType: 'application/octet-stream',
        headers: {'content-encoding': 'gzip'},
      );
      expect(expansion.statusCode, 413);
      final malformedSource = Uint8List.fromList(
        List<int>.generate(1024, (index) => index % 251),
      );
      final malformedCompressed = Uint8List.fromList(
        gzip.encode(malformedSource),
      );
      malformedCompressed[10] ^= 0xff;
      final malformedGzip = await _send(
        'PUT',
        '/v1/blobs/${'c' * 64}',
        syncId: syncId,
        body: malformedCompressed.sublist(0, malformedCompressed.length - 1),
        contentType: 'application/octet-stream',
        headers: {'content-encoding': 'gzip'},
      );
      expect(malformedGzip.statusCode, 400);
      expect(await malformedGzip.body(), contains('malformed compressed body'));
    },
  );

  test('stale epochs are rejected and blobs are store-isolated', () async {
    final first = await _send('POST', '/v1/store', syncId: syncId);
    final firstBody = jsonDecode(await first.body()) as Map<String, Object?>;
    final stale = SyncManifest(
      deviceId: 'device-one',
      epoch: 'b' * 32,
      writtenAt: DateTime.utc(2026, 9, 3),
      records: const {},
    );
    final staleResponse = await _send(
      'PUT',
      '/v1/manifests/device-one',
      syncId: syncId,
      body: encodeSyncManifestUtf8(stale),
      contentType: 'application/json',
    );
    expect(staleResponse.statusCode, 409);
    expect(firstBody['epoch'], isNot('b' * 32));

    final bytes = Uint8List.fromList([1, 2, 3]);
    final hash = sha256.convert(bytes).toString();
    final upload = await _send(
      'PUT',
      '/v1/blobs/$hash',
      syncId: syncId,
      body: bytes,
      contentType: 'application/octet-stream',
    );
    expect(upload.statusCode, 201);
    final otherStore = await _send(
      'POST',
      '/v1/store',
      syncId: 'other-café-horse-staple',
    );
    expect(otherStore.statusCode, 201);
    final hidden = await _send(
      'GET',
      '/v1/blobs/$hash',
      syncId: 'other-café-horse-staple',
    );
    expect(hidden.statusCode, 404);
  });

  test('blob uploads reject a body whose hash differs from the path', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final wrongHash = 'a' * 64;
    final response = await _send(
      'PUT',
      '/v1/blobs/$wrongHash',
      syncId: syncId,
      body: bytes,
      contentType: 'application/octet-stream',
    );
    expect(response.statusCode, 400);
    final missing = await _send('GET', '/v1/blobs/$wrongHash', syncId: syncId);
    expect(missing.statusCode, 404);
  });

  test(
    'each failed store-resolution outcome consumes its own budget',
    () async {
      for (
        var attempt = 0;
        attempt < maxFailedResolutionsPerIpBurst;
        attempt++
      ) {
        final response = await _send('GET', '/v1/store', credential: '%%%bad');
        expect(response.statusCode, 401);
      }
      expect(
        (await _send('GET', '/v1/store', credential: '%%%bad')).statusCode,
        429,
      );
    },
  );

  test('structurally invalid credentials consume the failure budget', () async {
    final invalidCredential = base64Url
        .encode(utf8.encode('one-two-three'))
        .replaceAll('=', '');
    for (var attempt = 0; attempt < maxFailedResolutionsPerIpBurst; attempt++) {
      final response = await _send(
        'GET',
        '/v1/store',
        credential: invalidCredential,
      );
      expect(response.statusCode, 403);
    }
    expect(
      (await _send(
        'GET',
        '/v1/store',
        credential: invalidCredential,
      )).statusCode,
      429,
    );
  });

  test('unknown-store resolutions consume the failure budget', () async {
    for (var attempt = 0; attempt < maxFailedResolutionsPerIpBurst; attempt++) {
      final response = await _send(
        'GET',
        '/v1/store',
        syncId: 'unknown-$attempt-café-staple',
      );
      expect(response.statusCode, 404);
    }
    expect(
      (await _send(
        'GET',
        '/v1/store',
        syncId: 'unknown-final-café-staple',
      )).statusCode,
      429,
    );
  });

  test('duplicate creation consumes the failure budget', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    for (var attempt = 0; attempt < maxFailedResolutionsPerIpBurst; attempt++) {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        409,
      );
    }
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 429);
  });

  test('successful resolutions do not consume the failure budget', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    expect(created.statusCode, 201);
    for (
      var attempt = 0;
      attempt < maxFailedResolutionsPerIpBurst + 5;
      attempt++
    ) {
      expect((await _send('GET', '/v1/store', syncId: syncId)).statusCode, 200);
    }
  });

  test('failure-budget churn cannot reset an active address bucket', () async {
    final customApp = AthenaeumApp(
      config: app.config,
      clientAddressResolver: (request) => request.headers['x-test-ip']!,
      budgetLimits: const AthenaeumBudgetLimits(
        perIpFailureBurst: maxFailedResolutionsPerIpBurst,
        serverWideFailuresPerMinute: 2000,
      ),
    );
    Future<Response> failedRequest(String address) => customApp.call(
      Request(
        'GET',
        Uri.parse('http://127.0.0.1/v1/store'),
        headers: {'authorization': 'Bearer %%%bad', 'x-test-ip': address},
      ),
    );

    for (var attempt = 0; attempt < maxFailedResolutionsPerIpBurst; attempt++) {
      expect((await failedRequest('target')).statusCode, 401);
    }
    for (var attempt = 0; attempt < 999; attempt++) {
      expect((await failedRequest('other-$attempt')).statusCode, 401);
    }
    expect((await failedRequest('new-address')).statusCode, 429);
    expect((await failedRequest('target')).statusCode, 429);
  });

  test(
    'server-wide shedding preserves existing-store and resource behavior',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      for (
        var attempt = 0;
        attempt < maxFailedResolutionsServerWide;
        attempt++
      ) {
        final response = await _send(
          'GET',
          '/v1/store',
          syncId: 'global-$attempt-café-staple',
          headers: {'x-test-ip': 'address-$attempt'},
        );
        expect(response.statusCode, 404);
      }
      expect(
        (await _send(
          'GET',
          '/v1/store',
          syncId: 'global-final-café-staple',
          headers: {'x-test-ip': 'address-final'},
        )).statusCode,
        429,
      );
      expect((await _send('GET', '/v1/store', syncId: syncId)).statusCode, 200);
      final missingBlob = await _send(
        'GET',
        '/v1/blobs/${'c' * 64}',
        syncId: syncId,
      );
      expect(missingBlob.statusCode, 404);
    },
  );

  test('creation cap does not hide an existing-store conflict', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    for (var attempt = 0; attempt < maxStoreCreationsPerMinute - 1; attempt++) {
      expect(
        (await _send(
          'POST',
          '/v1/store',
          syncId: 'creation-$attempt-café-staple',
        )).statusCode,
        201,
      );
    }
    expect(
      (await _send(
        'POST',
        '/v1/store',
        syncId: 'over-cap-café-staple',
      )).statusCode,
      429,
    );
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 409);
  });

  test('failed store creation does not consume the creation budget', () async {
    final database = sqlite3.openInMemory();
    final customStore = AthenaeumStore(config: app.config, database: database);
    final customApp = AthenaeumApp(
      config: app.config,
      store: customStore,
      budgetLimits: const AthenaeumBudgetLimits(creationsPerMinute: 1),
    );
    addTearDown(customStore.close);
    database.execute(
      'CREATE TRIGGER fail_store_create BEFORE INSERT ON stores '
      "BEGIN SELECT RAISE(ABORT, 'injected create failure'); END",
    );
    Future<Response> createRequest() => customApp.call(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1/v1/store'),
        headers: {
          'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
        },
      ),
    );

    await expectLater(createRequest(), throwsA(isA<SqliteException>()));
    database.execute('DROP TRIGGER fail_store_create');
    expect((await createRequest()).statusCode, 201);
  });

  test('concurrent identical blob uploads are idempotent', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
    final hash = sha256.convert(bytes).toString();
    final responses = await Future.wait(
      List.generate(
        8,
        (_) => _send(
          'PUT',
          '/v1/blobs/$hash',
          syncId: syncId,
          body: bytes,
          contentType: 'application/octet-stream',
        ),
      ),
    );
    expect(
      responses.where((response) => response.statusCode == 201),
      hasLength(1),
    );
    expect(
      responses.where((response) => response.statusCode == 200),
      hasLength(7),
    );
    for (final response in responses) {
      await response.drain<void>();
    }
    final fetched = await _send('GET', '/v1/blobs/$hash', syncId: syncId);
    expect(await fetched.bodyBytes(), equals(bytes));
  });

  test('epoch changes are rejected at the write boundary', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    final createdBody =
        jsonDecode(await created.body()) as Map<String, Object?>;
    final epoch = createdBody['epoch']! as String;
    final manifest = SyncManifest(
      deviceId: 'device-one',
      epoch: epoch,
      writtenAt: DateTime.utc(2026, 9, 3),
      records: const {},
    );
    expect(
      (await _send('DELETE', '/v1/store', syncId: syncId)).statusCode,
      204,
    );
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
    final body = encodeSyncManifestUtf8(manifest);
    expect(
      () => app.store.putManifest(
        idKey: idKey,
        epoch: epoch,
        deviceId: manifest.deviceId,
        etag: rawBodyHash(body),
        writtenAt: manifest.writtenAt.millisecondsSinceEpoch ~/ 1000,
        body: body,
      ),
      throwsA(isA<StoreEpochMismatch>()),
    );
    expect(
      () => app.store.putBlob(
        idKey: idKey,
        epoch: epoch,
        hash: 'a' * 64,
        body: Uint8List(0),
      ),
      returnsNormally,
    );
    expect(app.store.blobFile(idKey, epoch, 'a' * 64).existsSync(), isTrue);
  });

  test('method-not-allowed responses advertise the route methods', () async {
    final store = await _send('PUT', '/v1/store', syncId: syncId);
    expect(store.statusCode, 405);
    expect(store.headers.value('allow'), 'GET, POST, DELETE');
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final blob = await _send('POST', '/v1/blobs/${'a' * 64}', syncId: syncId);
    expect(blob.statusCode, 405);
    expect(blob.headers.value('allow'), 'GET, PUT');
    final missing = await _send('GET', '/v1/blobs/missing', syncId: syncId);
    expect(missing.statusCode, 405);
    expect(missing.headers.value('allow'), 'POST');
  });

  test(
    'streaming body limits cancel input at the first oversized chunk',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      var yielded = 0;
      Stream<List<int>> oversizedBody() async* {
        yielded++;
        yield Uint8List(maxBlobBytes + 1);
        yielded++;
        yield Uint8List(1);
      }

      final request = Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/${'d' * 64}'),
        headers: {
          'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
          'content-type': 'application/octet-stream',
        },
        body: oversizedBody(),
      );
      final response = await app.call(request);
      expect(response.statusCode, 413);
      expect(yielded, 1);
    },
  );

  test(
    'missing-hash limits cancel input before retaining later chunks',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      var yielded = 0;
      final firstChunk = utf8.encode(
        '{"hashes":[${List<int>.filled(maxMissingHashes + 1, 0).join(',')}]',
      );
      Stream<List<int>> oversizedHashes() async* {
        yielded++;
        yield Uint8List.fromList(firstChunk);
        yielded++;
        yield Uint8List.fromList([0x7d]);
      }

      final response = await app.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/blobs/missing'),
          headers: {
            'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
            'content-type': 'application/json',
          },
          body: oversizedHashes(),
        ),
      );
      expect(response.statusCode, 413);
      expect(yielded, 1);
    },
  );

  test(
    'JSON depth limits cancel input before retaining later chunks',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      var yielded = 0;
      Stream<List<int>> overlyDeepJson() async* {
        yielded++;
        yield Uint8List.fromList(
          utf8.encode('{"hashes":${'[' * maxJsonDepth}'),
        );
        yielded++;
        yield Uint8List.fromList(utf8.encode("0${']' * maxJsonDepth}"));
      }

      final response = await app.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/blobs/missing'),
          headers: {
            'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
            'content-type': 'application/json',
          },
          body: overlyDeepJson(),
        ),
      );
      expect(response.statusCode, 413);
      expect(yielded, 1);
    },
  );

  test(
    'manifest JSON depth limits cancel input before retaining later chunks',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      var yielded = 0;
      Stream<List<int>> overlyDeepManifest() async* {
        yielded++;
        yield Uint8List.fromList(utf8.encode('[' * (maxJsonDepth + 1)));
        yielded++;
        yield Uint8List.fromList(utf8.encode(']' * (maxJsonDepth + 1)));
      }

      final response = await app.call(
        Request(
          'PUT',
          Uri.parse('http://127.0.0.1/v1/manifests/device-one'),
          headers: {
            'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
            'content-type': 'application/json',
          },
          body: overlyDeepManifest(),
        ),
      );
      expect(response.statusCode, 413);
      expect(yielded, 1);
    },
  );

  test(
    'escaped duplicate hashes keys are rejected before later chunks are read',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      var yielded = 0;
      Stream<List<int>> duplicateHashes() async* {
        yielded++;
        yield Uint8List.fromList(utf8.encode(r'{"hashes":[],"hash\u0065s":['));
        yielded++;
        yield Uint8List.fromList(utf8.encode('0' * (maxMissingHashes + 1)));
      }

      final response = await app.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/blobs/missing'),
          headers: {
            'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
            'content-type': 'application/json',
          },
          body: duplicateHashes(),
        ),
      );
      expect(response.statusCode, 400);
      expect(yielded, 1);
    },
  );

  test(
    'nested hashes extension fields remain opaque to the request scanner',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      final response = await _send(
        'POST',
        '/v1/blobs/missing',
        syncId: syncId,
        contentType: 'application/json',
        body: Uint8List.fromList(
          utf8.encode(
            '{"extension":{"hashes":[${List.filled(10001, '0').join(',')}]},'
            '"hashes":[]}',
          ),
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.body(), '{"missing":[]}');
    },
  );

  test('ordinary requests retry queued filesystem cleanup', () async {
    final customDirectory = await Directory.systemTemp.createTemp(
      'athenaeum-request-retry-',
    );
    var failDelete = true;
    final customConfig = AthenaeumConfig(
      dataDirectory: customDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    final customStore = AthenaeumStore(
      config: customConfig,
      deleteDirectory: (directory) {
        if (failDelete) {
          throw const FileSystemException('injected filesystem failure');
        }
        directory.deleteSync(recursive: true);
      },
    );
    final customApp = AthenaeumApp(config: customConfig, store: customStore);
    addTearDown(() async {
      customStore.close();
      await customDirectory.delete(recursive: true);
    });

    final idKey = deriveIncomingSyncIdKey(syncId, customConfig.pepper);
    final created = customStore.create(idKey);
    customStore.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'f' * 64,
      body: Uint8List.fromList([5]),
    );
    final blobFile = customStore.blobFile(idKey, created.epoch, 'f' * 64);
    customStore.deleteStore(idKey);
    expect(blobFile.existsSync(), isTrue);

    failDelete = false;
    final response = await customApp.call(
      Request(
        'GET',
        Uri.parse('http://127.0.0.1/v1/store'),
        headers: {'authorization': 'Bearer ${encodeSyncCredential(syncId)}'},
      ),
    );
    expect(response.statusCode, 404);
    expect(blobFile.existsSync(), isFalse);
  });

  test('manifest PUT collects old unreferenced blobs', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    final createdBody =
        jsonDecode(await created.body()) as Map<String, Object?>;
    final epoch = createdBody['epoch']! as String;
    final bytes = Uint8List.fromList([9, 8, 7]);
    final hash = sha256.convert(bytes).toString();
    expect(
      (await _send(
        'PUT',
        '/v1/blobs/$hash',
        syncId: syncId,
        body: bytes,
        contentType: 'application/octet-stream',
      )).statusCode,
      201,
    );
    final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
    final blobFile = app.store.blobFile(idKey, epoch, hash);
    app.store.database.execute(
      'UPDATE blob_refs SET uploaded_at = ? '
      'WHERE id_key = ? AND epoch = ? AND hash = ?',
      [
        DateTime.utc(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
        idKey,
        epoch,
        hash,
      ],
    );
    expect(blobFile.existsSync(), isTrue);

    final manifest = SyncManifest(
      deviceId: 'device-one',
      epoch: epoch,
      writtenAt: DateTime.utc(2026, 9, 3),
      records: const {},
    );
    expect(
      (await _send(
        'PUT',
        '/v1/manifests/device-one',
        syncId: syncId,
        body: encodeSyncManifestUtf8(manifest),
        contentType: 'application/json',
      )).statusCode,
      201,
    );
    expect(blobFile.existsSync(), isFalse);
  });

  test('manifest PUT collects stale-epoch unreferenced blobs', () async {
    final created = await _send('POST', '/v1/store', syncId: syncId);
    final currentEpoch =
        (jsonDecode(await created.body()) as Map<String, Object?>)['epoch']!
            as String;
    final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
    final staleEpoch = 'd' * 32;
    final bytes = Uint8List.fromList([6, 5, 4]);
    final hash = sha256.convert(bytes).toString();
    app.store.putBlob(idKey: idKey, epoch: staleEpoch, hash: hash, body: bytes);
    app.store.database.execute(
      'UPDATE blob_refs SET uploaded_at = ? '
      'WHERE id_key = ? AND epoch = ? AND hash = ?',
      [
        DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch ~/
            1000,
        idKey,
        staleEpoch,
        hash,
      ],
    );
    final staleBlobFile = app.store.blobFile(idKey, staleEpoch, hash);

    final manifest = SyncManifest(
      deviceId: 'device-stale-epoch',
      epoch: currentEpoch,
      writtenAt: DateTime.now(),
      records: const {},
    );
    expect(
      (await _send(
        'PUT',
        '/v1/manifests/device-stale-epoch',
        syncId: syncId,
        body: encodeSyncManifestUtf8(manifest),
        contentType: 'application/json',
      )).statusCode,
      201,
    );
    expect(staleBlobFile.existsSync(), isFalse);
  });

  test(
    'manifest publication succeeds when post-publication GC fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'athenaeum-manifest-gc-failure-',
      );
      final customStore = AthenaeumStore(
        config: AthenaeumConfig(
          dataDirectory: directory.path,
          pepper: List<int>.filled(32, 0x42),
        ),
        database: sqlite3.openInMemory(),
        breakGlassDatabase: sqlite3.openInMemory(),
        diagnosticDatabase: sqlite3.openInMemory(),
      );
      final customApp = AthenaeumApp(
        config: customStore.config,
        store: customStore,
      );
      addTearDown(() async {
        customStore.close();
        await directory.delete(recursive: true);
      });

      final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
      expect(
        (await customApp.call(
          Request(
            'POST',
            Uri.parse('http://127.0.0.1/v1/store'),
            headers: {'authorization': authorization},
          ),
        )).statusCode,
        201,
      );
      final idKey = deriveIncomingSyncIdKey(syncId, customStore.config.pepper);
      final epoch = customStore.lookup(idKey)!.epoch;
      customStore.database.execute(
        'INSERT INTO blob_refs (id_key, epoch, hash, size, uploaded_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [idKey, epoch, 'b' * 64, 1, 0],
      );
      customStore.database.execute(
        'INSERT INTO manifests '
        '(id_key, epoch, device_id, etag, written_at, body) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          idKey,
          epoch,
          'poisoned',
          'a' * 64,
          0,
          Uint8List.fromList([0]),
        ],
      );
      final manifest = SyncManifest(
        deviceId: 'device-one',
        epoch: epoch,
        writtenAt: DateTime.utc(2026, 9, 3),
        records: const {},
      );

      final response = await customApp.call(
        Request(
          'PUT',
          Uri.parse('http://127.0.0.1/v1/manifests/device-one'),
          headers: {
            'authorization': authorization,
            'content-type': 'application/json',
          },
          body: encodeSyncManifestUtf8(manifest),
        ),
      );

      expect(response.statusCode, 201);
      expect(customStore.manifest(idKey, epoch, 'device-one'), isNotNull);
    },
  );

  test('DELETE /v1/store removes a grace-protected blob immediately', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final bytes = Uint8List.fromList([4, 5, 6]);
    final hash = sha256.convert(bytes).toString();
    expect(
      (await _send(
        'PUT',
        '/v1/blobs/$hash',
        syncId: syncId,
        body: bytes,
        contentType: 'application/octet-stream',
      )).statusCode,
      201,
    );
    final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
    final epoch = app.store.lookup(idKey)!.epoch;
    final file = app.store.blobFile(idKey, epoch, hash);
    expect(file.existsSync(), isTrue);
    expect(
      (await _send('DELETE', '/v1/store', syncId: syncId)).statusCode,
      204,
    );
    expect(file.existsSync(), isFalse);
    expect(app.store.lookup(idKey), isNull);
  });

  test(
    'aggregate store quotas return 507 before persistent allocation',
    () async {
      final created = await _send('POST', '/v1/store', syncId: syncId);
      final createdBody =
          jsonDecode(await created.body()) as Map<String, Object?>;
      final epoch = createdBody['epoch']! as String;
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      app.store.database.execute(
        'UPDATE stores SET bytes_used = ? WHERE id_key = ?',
        [maxStoreBytes, idKey],
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final hash = sha256.convert(bytes).toString();
      final response = await _send(
        'PUT',
        '/v1/blobs/$hash',
        syncId: syncId,
        body: bytes,
        contentType: 'application/octet-stream',
      );
      expect(response.statusCode, 507);
      expect(app.store.blobFile(idKey, epoch, hash).existsSync(), isFalse);

      app.store.database.execute(
        'UPDATE stores SET bytes_used = 0 WHERE id_key = ?',
        [idKey],
      );
      for (var index = 0; index < maxStoreDevices; index++) {
        final manifest = SyncManifest(
          deviceId: 'quota-device-$index',
          epoch: epoch,
          writtenAt: DateTime.utc(2026, 9, 3),
          records: const {},
        );
        expect(
          (await _send(
            'PUT',
            '/v1/manifests/quota-device-$index',
            syncId: syncId,
            body: encodeSyncManifestUtf8(manifest),
            contentType: 'application/json',
          )).statusCode,
          201,
        );
      }
      final overDeviceLimit = SyncManifest(
        deviceId: 'quota-device-over-cap',
        epoch: epoch,
        writtenAt: DateTime.utc(2026, 9, 3),
        records: const {},
      );
      expect(
        (await _send(
          'PUT',
          '/v1/manifests/quota-device-over-cap',
          syncId: syncId,
          body: encodeSyncManifestUtf8(overDeviceLimit),
          contentType: 'application/json',
        )).statusCode,
        507,
      );
    },
  );

  test('blob-count quota rejects the next unique upload', () async {
    final directory = await Directory.systemTemp.createTemp(
      'athenaeum-blob-quota-',
    );
    final customStore = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: directory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 1),
    );
    final customApp = AthenaeumApp(
      config: customStore.config,
      store: customStore,
    );
    addTearDown(() async {
      customStore.close();
      await directory.delete(recursive: true);
    });
    final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
    Future<Response> request(String method, String path, {Uint8List? body}) =>
        customApp.call(
          Request(
            method,
            Uri.parse('http://127.0.0.1$path'),
            headers: {
              'authorization': authorization,
              if (body != null) 'content-type': 'application/octet-stream',
            },
            body: body,
          ),
        );

    expect((await request('POST', '/v1/store')).statusCode, 201);
    final firstBody = Uint8List.fromList([1]);
    final firstHash = sha256.convert(firstBody).toString();
    expect(
      (await request(
        'PUT',
        '/v1/blobs/$firstHash',
        body: firstBody,
      )).statusCode,
      201,
    );
    final secondBody = Uint8List.fromList([2]);
    final secondHash = sha256.convert(secondBody).toString();
    expect(
      (await request(
        'PUT',
        '/v1/blobs/$secondHash',
        body: secondBody,
      )).statusCode,
      507,
    );
    final idKey = deriveIncomingSyncIdKey(syncId, customStore.config.pepper);
    final epoch = customStore.lookup(idKey)!.epoch;
    expect(
      customStore.blobFile(idKey, epoch, secondHash).existsSync(),
      isFalse,
    );
  });

  test('streaming byte quota rejects before buffering later chunks', () async {
    final directory = await Directory.systemTemp.createTemp(
      'athenaeum-stream-quota-',
    );
    final customStore = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: directory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 3),
    );
    final customApp = AthenaeumApp(
      config: customStore.config,
      store: customStore,
    );
    addTearDown(() async {
      customStore.close();
      await directory.delete(recursive: true);
    });
    final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
    expect(
      (await customApp.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/store'),
          headers: {'authorization': authorization},
        ),
      )).statusCode,
      201,
    );
    final firstChunk = Uint8List.fromList([1, 2, 3, 4]);
    final hash = sha256.convert(firstChunk).toString();
    var yielded = 0;
    Stream<List<int>> body() async* {
      yielded++;
      yield firstChunk;
      yielded++;
      yield Uint8List.fromList([5]);
    }

    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/$hash'),
        headers: {
          'authorization': authorization,
          'content-type': 'application/octet-stream',
        },
        body: body(),
      ),
    );
    expect(response.statusCode, 507);
    expect(yielded, 1);
    final idKey = deriveIncomingSyncIdKey(syncId, customStore.config.pepper);
    final epoch = customStore.lookup(idKey)!.epoch;
    expect(customStore.blobFile(idKey, epoch, hash).existsSync(), isFalse);
  });

  test('device quota rejects before buffering the manifest body', () async {
    final directory = await Directory.systemTemp.createTemp(
      'athenaeum-device-quota-',
    );
    final customStore = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: directory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxDevices: 1),
    );
    final customApp = AthenaeumApp(
      config: customStore.config,
      store: customStore,
    );
    addTearDown(() async {
      customStore.close();
      await directory.delete(recursive: true);
    });
    final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
    expect(
      (await customApp.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/store'),
          headers: {'authorization': authorization},
        ),
      )).statusCode,
      201,
    );
    final idKey = deriveIncomingSyncIdKey(syncId, customStore.config.pepper);
    final epoch = customStore.lookup(idKey)!.epoch;
    customStore.putManifest(
      idKey: idKey,
      epoch: epoch,
      deviceId: 'device-one',
      etag: 'a' * 64,
      writtenAt: 0,
      body: Uint8List.fromList([1]),
    );
    var yielded = 0;
    Stream<List<int>> body() async* {
      yielded++;
      yield Uint8List.fromList([1]);
      yielded++;
      yield Uint8List.fromList([2]);
    }

    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/manifests/device-two'),
        headers: {
          'authorization': authorization,
          'content-type': 'application/json',
        },
        body: body(),
      ),
    );
    expect(response.statusCode, 507);
    expect(yielded, 0);
  });

  test('per-request size errors precede aggregate quota errors', () async {
    final directory = await Directory.systemTemp.createTemp(
      'athenaeum-size-quota-',
    );
    final customStore = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: directory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 0),
    );
    final customApp = AthenaeumApp(
      config: customStore.config,
      store: customStore,
    );
    addTearDown(() async {
      customStore.close();
      await directory.delete(recursive: true);
    });
    final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
    expect(
      (await customApp.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/store'),
          headers: {'authorization': authorization},
        ),
      )).statusCode,
      201,
    );
    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/${'a' * 64}'),
        headers: {
          'authorization': authorization,
          'content-type': 'application/octet-stream',
          'content-length': '${maxBlobBytes + 1}',
        },
      ),
    );
    expect(response.statusCode, 413);
  });

  test('gzip blob quota uses decompressed size', () async {
    final directory = await Directory.systemTemp.createTemp(
      'athenaeum-gzip-quota-',
    );
    final customStore = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: directory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: sqlite3.openInMemory(),
      breakGlassDatabase: sqlite3.openInMemory(),
      diagnosticDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 1),
    );
    final customApp = AthenaeumApp(
      config: customStore.config,
      store: customStore,
    );
    addTearDown(() async {
      customStore.close();
      await directory.delete(recursive: true);
    });
    final authorization = ['Bearer', encodeSyncCredential(syncId)].join(' ');
    expect(
      (await customApp.call(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/v1/store'),
          headers: {'authorization': authorization},
        ),
      )).statusCode,
      201,
    );
    final body = Uint8List.fromList([42]);
    final compressed = Uint8List.fromList(gzip.encode(body));
    final hash = sha256.convert(body).toString();
    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/$hash'),
        headers: {
          'authorization': authorization,
          'content-type': 'application/octet-stream',
          'content-encoding': 'gzip',
          'content-length': '${compressed.length}',
        },
        body: compressed,
      ),
    );
    expect(response.statusCode, 201);
  });

  test('production diagnostics persist and expire safely', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final hash = 'a' * 64;
    final response = await _send(
      'PUT',
      '/v1/blobs/$hash',
      syncId: syncId,
      body: Uint8List.fromList([1, 2, 3]),
      contentType: 'application/octet-stream',
    );
    expect(response.statusCode, 400);
    final rows = app.store.diagnosticDatabase.select(
      'SELECT status, id_key, hash, recorded_at FROM diagnostic_events',
    );
    expect(rows, hasLength(1));
    expect(rows.single['status'], 400);
    expect(rows.single['id_key'], isNot(syncId));
    expect(rows.single['hash'], hash);
    app.store.diagnosticDatabase
        .execute('UPDATE diagnostic_events SET recorded_at = ?', [
          DateTime.now()
                  .subtract(const Duration(days: 31))
                  .millisecondsSinceEpoch ~/
              1000,
        ]);
    app.store.purgeExpiredDiagnostics();
    expect(
      app.store.diagnosticDatabase.select('SELECT * FROM diagnostic_events'),
      isEmpty,
    );
  });

  test('declared oversized bodies produce safe diagnostics', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final hash = 'b' * 64;
    final response = await app.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/$hash'),
        headers: {
          'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
          'content-type': 'application/octet-stream',
          'content-length': '${maxBlobBytes + 1}',
        },
      ),
    );
    expect(response.statusCode, 413);
    final rows = app.store.diagnosticDatabase.select(
      'SELECT status, id_key, hash FROM diagnostic_events',
    );
    expect(rows, hasLength(1));
    expect(rows.single['status'], 413);
    expect(
      rows.single['id_key'],
      deriveIncomingSyncIdKey(syncId, app.config.pepper),
    );
    expect(rows.single['hash'], hash);
  });

  test('rejection diagnostics contain only derived identifiers', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final events = <AthenaeumDiagnosticEvent>[];
    final customApp = AthenaeumApp(
      config: app.config,
      store: app.store,
      diagnosticLogger: events.add,
    );
    final hash = 'a' * 64;
    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/$hash'),
        headers: {
          'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
          'content-type': 'application/octet-stream',
        },
        body: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(response.statusCode, 400);
    expect(events, hasLength(1));
    expect(events.single.status, 400);
    expect(
      events.single.idKey,
      deriveIncomingSyncIdKey(syncId, app.config.pepper),
    );
    expect(events.single.hash, hash);
    expect(events.single.retention, const Duration(days: 30));
    final serialized = jsonEncode(events.single.toJson());
    expect(serialized, isNot(contains(encodeSyncCredential(syncId))));
    expect(serialized, isNot(contains(syncId)));
    expect(serialized, isNot(contains('1,2,3')));
  });

  test('diagnostic sink failures do not replace protocol responses', () async {
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 201);
    final customApp = AthenaeumApp(
      config: app.config,
      store: app.store,
      diagnosticLogger: (_) {
        throw StateError('injected logger failure');
      },
    );
    final response = await customApp.call(
      Request(
        'PUT',
        Uri.parse('http://127.0.0.1/v1/blobs/${'c' * 64}'),
        headers: {
          'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
          'content-type': 'application/octet-stream',
        },
        body: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(response.statusCode, 400);
  });

  test(
    'manifest path device identifiers are absent from diagnostics',
    () async {
      expect(
        (await _send('POST', '/v1/store', syncId: syncId)).statusCode,
        201,
      );
      final rawDeviceId = 'a' * 64;
      final response = await app.call(
        Request(
          'PUT',
          Uri.parse('http://127.0.0.1/v1/manifests/$rawDeviceId'),
          headers: {
            'authorization': ['Bearer', encodeSyncCredential(syncId)].join(' '),
            'content-type': 'text/plain',
          },
        ),
      );
      expect(response.statusCode, 415);
      final rows = app.store.diagnosticDatabase.select(
        'SELECT status, id_key, hash FROM diagnostic_events',
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 415);
      expect(rows.single['hash'], isNull);
      expect(jsonEncode(rows.single), isNot(contains(rawDeviceId)));
    },
  );

  test('unauthenticated request failures do not create diagnostics', () async {
    final response = await app.call(
      Request('GET', Uri.parse('http://127.0.0.1/v1/blobs/not-a-hash')),
    );
    expect(response.statusCode, 400);
    expect(
      app.store.diagnosticDatabase.select('SELECT * FROM diagnostic_events'),
      isEmpty,
    );
  });

  test(
    'unknown stores do not create diagnostics from valid credentials',
    () async {
      final response = await app.call(
        Request(
          'GET',
          Uri.parse('http://127.0.0.1/v1/blobs/not-a-hash'),
          headers: {
            'authorization': [
              'Bearer',
              encodeSyncCredential('café-horse-battery-other'),
            ].join(' '),
          },
        ),
      );
      expect(response.statusCode, 400);
      expect(
        app.store.diagnosticDatabase.select('SELECT * FROM diagnostic_events'),
        isEmpty,
      );
    },
  );

  test('sweep controller cancels its hourly callback on shutdown', () {
    final timer = _FakeTimer();
    late void Function() fire;
    var sweeps = 0;
    final expiredIdKey = '9' * 64;
    app.store.create(expiredIdKey);
    app.store.database
        .execute('UPDATE stores SET last_seen = ? WHERE id_key = ?', [
          DateTime.now()
                  .subtract(const Duration(days: 31))
                  .millisecondsSinceEpoch ~/
              1000,
          expiredIdKey,
        ]);
    final controller = AthenaeumSweepController(
      app.store,
      schedule: (interval, callback) {
        expect(interval, const Duration(hours: 1));
        fire = () {
          if (timer.isActive) {
            sweeps++;
            callback(timer);
          }
        };
        return timer;
      },
    );
    controller.start();
    fire();
    expect(sweeps, 1);
    expect(app.store.lookup(expiredIdKey), isNull);
    controller.stop();
    expect(timer.isActive, isFalse);
    fire();
    expect(sweeps, 1);
  });

  test('sweep controller contains callback failures', () {
    final timer = _FakeTimer();
    late void Function() fire;
    var attempts = 0;
    final controller = AthenaeumSweepController(
      app.store,
      sweep: () {
        attempts++;
        if (attempts == 1) throw StateError('injected sweep failure');
      },
      schedule: (interval, callback) {
        fire = () {
          if (timer.isActive) callback(timer);
        };
        return timer;
      },
    );
    controller.start();
    fire();
    fire();
    expect(attempts, 2);
    controller.stop();
  });
}

extension on HttpClientResponse {
  Future<String> body() async => utf8.decode(await bodyBytes());

  Future<Uint8List> bodyBytes() async => Uint8List.fromList(
    await fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    }),
  );
}

Future<HttpClientResponse> _send(
  String method,
  String path, {
  String? syncId,
  String? credential,
  Uint8List? body,
  String? contentType,
  Map<String, String> headers = const {},
}) async {
  final request = await _activeClient.openUrl(method, _uri(path));
  final token = credential ?? encodeSyncCredential(syncId!);
  request.headers.set('authorization', 'Bearer $token');
  if (contentType != null) request.headers.set('content-type', contentType);
  headers.forEach(request.headers.set);
  if (body != null) {
    request.contentLength = body.length;
    request.add(body);
  }
  return request.close();
}

late HttpClient _activeClient;
late HttpServer _activeServer;

class _FakeTimer implements Timer {
  var _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

Uri _uri(String path) => Uri.http('127.0.0.1:${_activeServer.port}', path);

Uint8List _recordBlob({
  int version = 1,
  required String kind,
  required String id,
  required Map<String, Object?> body,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'v': version,
      'kind': kind,
      'id': id,
      'updatedAt': '2026-09-03T00:00:00.000Z',
      'deletedAt': null,
      'existenceAt': '2026-09-03T00:00:00.000Z',
      'body': body,
    }),
  ),
);
