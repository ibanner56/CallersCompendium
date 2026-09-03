import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
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
  });

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
          jsonEncode({
            'hashes': List<String>.filled(maxMissingHashes + 1, 'a' * 64),
          }),
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
    expect((await _send('POST', '/v1/store', syncId: syncId)).statusCode, 409);
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

Uri _uri(String path) => Uri.http('127.0.0.1:${_activeServer.port}', path);
