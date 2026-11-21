import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

/// The server-wide limits of sync spec §5.4: large-body requests in flight,
/// the free-space floor, and the per-address store-creation row.
void main() {
  late Directory dataDirectory;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'athenaeum-server-limits-',
    );
  });

  tearDown(() async {
    await dataDirectory.delete(recursive: true);
  });

  final alerts = <AthenaeumOperationalAlert>[];

  AthenaeumApp appWith({
    int minFreeBytes = 0,
    int maxLargeBodiesInFlight = defaultMaxLargeBodiesInFlight,
    int maxLargeBodiesInFlightPerIp = defaultMaxLargeBodiesInFlightPerIp,
    Duration largeBodyReadTimeout = defaultLargeBodyReadTimeout,
    AthenaeumFreeSpaceProbe? probe,
    AthenaeumBudgetLimits budgetLimits = const AthenaeumBudgetLimits(),
    AthenaeumStore Function(AthenaeumConfig config)? store,
    bool defaultAddressing = false,
  }) {
    alerts.clear();
    final config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
      minFreeBytes: minFreeBytes,
      maxLargeBodiesInFlight: maxLargeBodiesInFlight,
      maxLargeBodiesInFlightPerIp: maxLargeBodiesInFlightPerIp,
      largeBodyReadTimeout: largeBodyReadTimeout,
    );
    final app = AthenaeumApp(
      config: config,
      store: store == null ? _memoryStore(config) : store(config),
      clientAddressResolver: defaultAddressing
          ? null
          : (request) => request.headers['x-test-ip'] ?? 'test',
      budgetLimits: budgetLimits,
      diagnosticLogger: (_) {},
      alertSink: alerts.add,
      freeSpaceProbe: probe ?? (_) => null,
    );
    addTearDown(app.store.close);
    return app;
  }

  group('large-body requests in flight', () {
    const syncId = 'café-horse-battery-staple';

    /// A request whose body never ends until [body] is closed: the route
    /// reading it stays in flight, holding its slot.
    ({Future<Response> response, StreamController<List<int>> body}) stall(
      AthenaeumApp app,
      String method,
      String path, {
      required String ip,
      required String contentType,
    }) {
      final body = StreamController<List<int>>();
      final response = app.call(
        _request(
          method,
          path,
          syncId: syncId,
          ip: ip,
          headers: {'content-type': contentType},
          body: body.stream,
        ),
      );
      body.add(utf8.encode('{'));
      return (response: response, body: body);
    }

    Future<Response> manifestPut(AthenaeumApp app, {required String ip}) =>
        app.call(
          _request(
            'PUT',
            '/v1/manifests/device-one',
            syncId: syncId,
            ip: ip,
            headers: {'content-type': 'application/json'},
            body: Stream.value(utf8.encode('{}')),
          ),
        );

    test('a client past its share is answered 429 with Retry-After, '
        'and another client is still served', () async {
      final app = appWith(maxLargeBodiesInFlightPerIp: 2);
      app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
      final first = stall(
        app,
        'PUT',
        '/v1/manifests/device-one',
        ip: 'a',
        contentType: 'application/json',
      );
      final second = stall(
        app,
        'PUT',
        '/v1/manifests/device-two',
        ip: 'a',
        contentType: 'application/json',
      );

      final refused = await manifestPut(app, ip: 'a');
      expect(refused.statusCode, 429);
      expect(refused.headers['retry-after'], '5');

      // Another address is not held to the first one's share. Its malformed
      // manifest is `400`: the route ran.
      expect((await manifestPut(app, ip: 'b')).statusCode, 400);

      // A request with no large body is never counted.
      final lookup = await app.call(
        _request('GET', '/v1/store', syncId: syncId, ip: 'a'),
      );
      expect(lookup.statusCode, 200);

      await first.body.close();
      await second.body.close();
      expect((await first.response).statusCode, 400);
      expect((await second.response).statusCode, 400);
      expect((await manifestPut(app, ip: 'a')).statusCode, 400);
    });

    test('the server past its cap is answered 503 with Retry-After', () async {
      final app = appWith(
        maxLargeBodiesInFlight: 2,
        maxLargeBodiesInFlightPerIp: 2,
      );
      app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
      final first = stall(
        app,
        'PUT',
        '/v1/manifests/device-one',
        ip: 'a',
        contentType: 'application/json',
      );
      final second = stall(
        app,
        'PUT',
        '/v1/manifests/device-two',
        ip: 'b',
        contentType: 'application/json',
      );

      final refused = await manifestPut(app, ip: 'c');
      expect(refused.statusCode, 503);
      expect(refused.headers['retry-after'], '5');
      expect(alerts.map((alert) => alert.kind), ['capacity_exhaustion']);

      // A body that fails part-way gives its slot back too.
      first.body.addError(const HttpException('connection reset'));
      await first.body.close();
      expect((await first.response).statusCode, 500);
      expect((await manifestPut(app, ip: 'c')).statusCode, 400);

      await second.body.close();
      await second.response;
    });

    for (final (method, path, contentType) in [
      ('PUT', '/v1/manifests/device-one', 'application/json'),
      ('POST', '/v1/blobs/missing', 'application/json'),
      ('PUT', '/v1/blobs/${'a' * 64}', 'application/octet-stream'),
      ('PUT', '/v1/blobs/batch', syncBlobBatchMediaType),
    ]) {
      test('$method $path holds a large-body slot', () async {
        final app = appWith(maxLargeBodiesInFlightPerIp: 1);
        app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
        final held = stall(
          app,
          method,
          path,
          ip: 'a',
          contentType: contentType,
        );
        expect((await manifestPut(app, ip: 'a')).statusCode, 429);
        await held.body.close();
        await held.response;
        expect((await manifestPut(app, ip: 'a')).statusCode, 400);
      });
    }

    test(
      'a body that does not arrive in time is given up on and frees its slot',
      () async {
        final app = appWith(
          maxLargeBodiesInFlightPerIp: 1,
          largeBodyReadTimeout: const Duration(milliseconds: 200),
        );
        app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
        final held = stall(
          app,
          'PUT',
          '/v1/manifests/device-one',
          ip: 'a',
          contentType: 'application/json',
        );
        expect((await manifestPut(app, ip: 'a')).statusCode, 429);
        // Bytes keep arriving, slower than the deadline allows for the whole.
        final trickle = Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => held.body.add(utf8.encode(' ')),
        );
        addTearDown(trickle.cancel);
        expect((await held.response).statusCode, 408);
        trickle.cancel();
        expect((await manifestPut(app, ip: 'a')).statusCode, 400);
      },
    );

    test(
      'a body that stops arriving altogether is given up on and frees its slot',
      () async {
        final app = appWith(
          maxLargeBodiesInFlightPerIp: 1,
          largeBodyReadTimeout: const Duration(milliseconds: 200),
        );
        app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
        for (final (encoding, opening) in [
          (null, utf8.encode('{')),
          // Part of a gzip member: the decoder waits on it too.
          ('gzip', gzip.encode(utf8.encode('{"a":1}')).sublist(0, 12)),
        ]) {
          final body = StreamController<List<int>>();
          addTearDown(body.close);
          final response = app.call(
            _request(
              'PUT',
              '/v1/manifests/device-one',
              syncId: syncId,
              ip: 'a',
              headers: {
                'content-type': 'application/json',
                'content-encoding': ?encoding,
              },
              body: body.stream,
            ),
          );
          body.add(opening);
          // Nothing more is ever sent.
          expect(
            (await response.timeout(const Duration(seconds: 5))).statusCode,
            408,
          );
          expect((await manifestPut(app, ip: 'a')).statusCode, 400);
        }
      },
    );

    test('a refused request does not hold a slot', () async {
      final app = appWith(maxLargeBodiesInFlightPerIp: 1);
      app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
      final held = stall(
        app,
        'PUT',
        '/v1/manifests/device-one',
        ip: 'a',
        contentType: 'application/json',
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        expect((await manifestPut(app, ip: 'a')).statusCode, 429);
      }
      await held.body.close();
      await held.response;
      expect((await manifestPut(app, ip: 'a')).statusCode, 400);
    });
  });

  group('free-space floor', () {
    const syncId = 'café-horse-battery-staple';
    final blob = Uint8List.fromList(utf8.encode('blob-one'));
    final blobHash = sha256Hex(blob);

    Future<Response> send(
      AthenaeumApp app,
      String method,
      String path, {
      List<int>? body,
      String? contentType,
    }) => app.call(
      _request(
        method,
        path,
        syncId: syncId,
        ip: 'a',
        headers: {'content-type': ?contentType},
        body: body == null ? null : Stream.value(body),
      ),
    );

    Uint8List manifestFor(String epoch) => encodeSyncManifestUtf8(
      SyncManifest(
        deviceId: 'device-one',
        epoch: epoch,
        writtenAt: DateTime.utc(2026, 11, 11),
        records: {
          SyncRecordKind.dance: {'dance-one': blobHash},
        },
      ),
    );

    List<int> batchOf(List<Uint8List> blobs) => [
      for (final blob in blobs) ...[
        ...encodeSyncBlobBatchFrameHead(
          SyncBlobBatchFrameStatus.blob,
          sha256Hex(blob),
          length: blob.length,
        ),
        ...blob,
      ],
    ];

    test('below the floor, blob and manifest writes are 507 while reads and '
        'deletes still work', () async {
      var available = 2000;
      final probed = <String>[];
      final app = appWith(
        minFreeBytes: 1000,
        probe: (directory) {
          probed.add(directory);
          return available;
        },
      );
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.create(idKey).epoch;

      // Above the floor: stored.
      expect(
        (await send(
          app,
          'PUT',
          '/v1/blobs/$blobHash',
          body: blob,
          contentType: 'application/octet-stream',
        )).statusCode,
        201,
      );
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-one',
          body: manifestFor(epoch),
          contentType: 'application/json',
        )).statusCode,
        201,
      );
      expect(probed, everyElement(dataDirectory.path));

      available = 999;
      final other = Uint8List.fromList(utf8.encode('blob-two'));
      final blobPut = await send(
        app,
        'PUT',
        '/v1/blobs/${sha256Hex(other)}',
        body: other,
        contentType: 'application/octet-stream',
      );
      expect(blobPut.statusCode, 507);
      expect(app.store.blobRef(idKey, epoch, sha256Hex(other)), isNull);
      expect(alerts.map((alert) => alert.source), contains('free_space_floor'));
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-two',
          body: manifestFor(epoch),
          contentType: 'application/json',
        )).statusCode,
        507,
      );
      expect(app.store.manifestHead(idKey, epoch, 'device-two'), isNull);

      // A device's manifest may still be replaced by one no larger, which is
      // how records are given up; never by a larger one.
      final stored = manifestFor(epoch);
      final smaller = encodeSyncManifestUtf8(
        SyncManifest(
          deviceId: 'device-one',
          epoch: epoch,
          writtenAt: DateTime.utc(2026, 11, 12),
          records: const {},
        ),
      );
      final larger = encodeSyncManifestUtf8(
        SyncManifest(
          deviceId: 'device-one',
          epoch: epoch,
          writtenAt: DateTime.utc(2026, 11, 12),
          records: {
            SyncRecordKind.dance: {
              'dance-one': blobHash,
              'dance-two': blobHash,
            },
          },
        ),
      );
      expect(smaller.length, lessThan(stored.length));
      expect(larger.length, greaterThan(stored.length));
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-one',
          body: larger,
          contentType: 'application/json',
        )).statusCode,
        507,
      );
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-one',
          body: smaller,
          contentType: 'application/json',
        )).statusCode,
        200,
      );
      expect(
        app.store.manifestHead(idKey, epoch, 'device-one')!.size,
        smaller.length,
      );
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-one',
          body: stored,
          contentType: 'application/json',
        )).statusCode,
        507,
        reason: 'the allowance is the manifest stored now, not an earlier one',
      );
      expect(
        (await send(
          app,
          'PUT',
          '/v1/manifests/device-one',
          body: smaller,
          contentType: 'application/json',
        )).statusCode,
        200,
      );

      // A batch is answered 200, every blob that passed its checks 507, and
      // nothing stored; a malformed blob is still its own 400.
      final batch = await send(
        app,
        'PUT',
        '/v1/blobs/batch',
        body: [
          ...batchOf([other, blob]),
          ...encodeSyncBlobBatchFrameHead(
            SyncBlobBatchFrameStatus.blob,
            'f' * 64,
            length: 1,
          ),
          0x7b,
        ],
        contentType: syncBlobBatchMediaType,
      );
      expect(batch.statusCode, 200);
      final results =
          (jsonDecode(await batch.readAsString()) as Map)['results'] as List;
      expect(
        [for (final result in results) (result as Map)['status']],
        [507, 507, 400],
      );
      expect(app.store.blobRef(idKey, epoch, sha256Hex(other)), isNull);

      // Reads still work.
      expect((await send(app, 'GET', '/v1/store')).statusCode, 200);
      final blobGet = await send(app, 'GET', '/v1/blobs/$blobHash');
      expect(blobGet.statusCode, 200);
      expect(blobGet.headers['content-length'], '${blob.length}');
      expect(await _bytes(blobGet), blob);
      final manifestGet = await send(app, 'GET', '/v1/manifests/device-one');
      expect(manifestGet.statusCode, 200);
      expect(await _bytes(manifestGet), smaller);
      final missing = await send(
        app,
        'POST',
        '/v1/blobs/missing',
        body: utf8.encode(
          jsonEncode({
            'hashes': [blobHash],
          }),
        ),
        contentType: 'application/json',
      );
      expect(missing.statusCode, 200);

      // Deletes still work.
      expect(
        (await send(app, 'DELETE', '/v1/manifests/device-one')).statusCode,
        204,
      );
      expect((await send(app, 'DELETE', '/v1/store')).statusCode, 204);
    });

    test('a floor of zero is never measured', () async {
      final app = appWith(
        minFreeBytes: 0,
        probe: (_) => throw StateError('probed'),
      );
      app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
      expect(
        (await send(
          app,
          'PUT',
          '/v1/blobs/$blobHash',
          body: blob,
          contentType: 'application/octet-stream',
        )).statusCode,
        201,
      );
    });

    test('a free space that cannot be read admits the write', () async {
      for (final probe in <AthenaeumFreeSpaceProbe>[
        (_) => null,
        (_) => throw const FileSystemException('statvfs failed'),
      ]) {
        final app = appWith(minFreeBytes: 1 << 40, probe: probe);
        app.store.create(deriveIncomingSyncIdKey(syncId, app.config.pepper));
        expect(
          (await send(
            app,
            'PUT',
            '/v1/blobs/$blobHash',
            body: blob,
            contentType: 'application/octet-stream',
          )).statusCode,
          201,
        );
      }
    });

    test('statvfs reads the free space of a real directory', () {
      final available = statvfsAvailableBytes(dataDirectory.path);
      if (!Platform.isLinux) {
        expect(available, isNull);
        return;
      }
      expect(available, isNotNull);
      expect(available, greaterThan(0));
      // Against df's own reading, which a wrong struct offset (total size,
      // free blocks counted in the wrong unit) would not match. Within 64 MiB:
      // other processes write between the two readings.
      final df = Process.runSync('df', [
        '-B1',
        '--output=avail',
        dataDirectory.path,
      ]);
      if (df.exitCode == 0) {
        final reported = int.parse(
          (df.stdout as String).trim().split('\n').last.trim(),
        );
        expect((available! - reported).abs(), lessThan(64 * 1024 * 1024));
      }
      expect(statvfsAvailableBytes('${dataDirectory.path}/missing'), isNull);
    });
  });

  group('per-address store creation', () {
    Future<Response> create(AthenaeumApp app, String syncId, String ip) =>
        app.call(_request('POST', '/v1/store', syncId: syncId, ip: ip));

    test(
      'an honest address can create while another exhausts its own share',
      () async {
        final app = appWith();
        for (var index = 0; index < maxStoreCreationsPerIpBurst; index++) {
          expect(
            (await create(
              app,
              'attacker-$index-café-staple',
              'attacker',
            )).statusCode,
            201,
          );
        }
        final refused = await create(
          app,
          'attacker-over-café-staple',
          'attacker',
        );
        expect(refused.statusCode, 429);
        // A token refills every 12 minutes at 5 an hour.
        expect(int.parse(refused.headers['retry-after']!), greaterThan(60));

        expect(
          (await create(app, 'honest-first-café-staple', 'honest')).statusCode,
          201,
        );
      },
    );

    test('a refusal by the per-address row does not spend the server-wide '
        'one', () async {
      final app = appWith(
        budgetLimits: const AthenaeumBudgetLimits(
          creationsPerMinute: 2,
          perIpCreationBurst: 1,
        ),
      );
      expect((await create(app, 'one-café-horse-staple', 'a')).statusCode, 201);
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(
          (await create(app, 'again-$attempt-café-staple', 'a')).statusCode,
          429,
        );
      }
      expect((await create(app, 'two-café-horse-staple', 'b')).statusCode, 201);
      expect(
        (await create(app, 'three-café-horse-staple', 'c')).statusCode,
        429,
      );
    });

    test('a failed creation refunds the address\'s share', () async {
      final database = sqlite3.sqlite3.openInMemory();
      final app = appWith(
        budgetLimits: const AthenaeumBudgetLimits(perIpCreationBurst: 1),
        store: (config) => AthenaeumStore(
          config: config,
          database: database,
          breakGlassDatabase: sqlite3.sqlite3.openInMemory(),
          diagnosticDatabase: sqlite3.sqlite3.openInMemory(),
        ),
      );
      database.execute(
        'CREATE TRIGGER fail_store_create BEFORE INSERT ON stores '
        "BEGIN SELECT RAISE(ABORT, 'injected create failure'); END",
      );
      expect((await create(app, 'one-café-horse-staple', 'a')).statusCode, 500);
      database.execute('DROP TRIGGER fail_store_create');
      expect((await create(app, 'two-café-horse-staple', 'a')).statusCode, 201);
    });

    test('addresses in one IPv6 /64 share a share', () async {
      final app = appWith(
        budgetLimits: const AthenaeumBudgetLimits(perIpCreationBurst: 1),
        defaultAddressing: true,
      );
      final server = await shelf_io.serve(
        app.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      Future<int> createFrom(String syncId, String forwardedFor) async {
        final request = await client.post(
          '127.0.0.1',
          server.port,
          '/v1/store',
        );
        request.headers
          ..set('authorization', 'Bearer ${encodeSyncCredential(syncId)}')
          ..set('x-forwarded-for', forwardedFor);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await createFrom('one-café-horse-staple', '2001:db8:1:2::1'), 201);
      expect(
        await createFrom('two-café-horse-staple', '2001:db8:1:2:ffff::9'),
        429,
      );
      expect(
        await createFrom('three-café-horse-staple', '2001:db8:1:3::1'),
        201,
      );
    });
  });

  group('manifest GET', () {
    const syncId = 'café-horse-battery-staple';

    test('streams the stored bytes in bounded chunks', () async {
      late _CountingStore store;
      final app = appWith(store: (config) => store = _CountingStore(config));
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.create(idKey).epoch;
      final body = Uint8List.fromList(
        List<int>.generate(
          manifestResponseChunkBytes * 2 + 12345,
          (index) => index % 251,
        ),
      );
      store.insertManifest(idKey, epoch, 'device-one', 'e' * 64, body);

      final response = await app.call(
        _request('GET', '/v1/manifests/device-one', syncId: syncId, ip: 'a'),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-length'], '${body.length}');
      expect(response.headers['etag'], '"${'e' * 64}"');
      expect(store.chunkReads, isEmpty, reason: 'nothing read before sent');
      expect(await _bytes(response), body);
      expect(store.chunkReads, hasLength(3));
      expect(
        store.chunkReads,
        everyElement(lessThanOrEqualTo(manifestResponseChunkBytes)),
      );
    });

    test('a manifest replaced while it is sent ends the body short, and the '
        'client fails the request', () async {
      late _CountingStore store;
      final app = appWith(store: (config) => store = _CountingStore(config));
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.create(idKey).epoch;
      final body = Uint8List(manifestResponseChunkBytes * 2);
      store
        ..insertManifest(idKey, epoch, 'device-one', 'e' * 64, body)
        ..beforeSecondChunk = () => store.database.execute(
          "UPDATE manifests SET etag = ?, body = ? WHERE device_id = 'device-one'",
          [
            'f' * 64,
            Uint8List(manifestResponseChunkBytes * 2)..fillRange(0, 10, 1),
          ],
        );
      // shelf logs a response stream's error itself only in the root zone;
      // under package:test it would reach the test, so catch it here, where
      // it is what shelf would have written to the log.
      final serverErrors = <Object>[];
      final server = await runZonedGuarded(
        () => shelf_io.serve(app.handler, InternetAddress.loopbackIPv4, 0),
        (error, _) => serverErrors.add(error),
      )!;
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      final request = await client.get(
        '127.0.0.1',
        server.port,
        '/v1/manifests/device-one',
      );
      request.headers.set(
        'authorization',
        'Bearer ${encodeSyncCredential(syncId)}',
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      await expectLater(
        response.fold<int>(0, (total, chunk) => total + chunk.length),
        throwsA(isA<HttpException>()),
      );
      expect(serverErrors, hasLength(1));
      expect(serverErrors.single.toString(), isNot(contains('device-one')));
    });

    test('a blob GET streams the file, and a file gone by then fails the '
        'stream without naming its path', () async {
      final app = appWith();
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.create(idKey).epoch;
      final blob = Uint8List.fromList(List<int>.generate(200000, (i) => i % 7));
      final hash = sha256Hex(blob);
      expect(
        app.store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: blob),
        isTrue,
      );

      final whole = await app.call(
        _request('GET', '/v1/blobs/$hash', syncId: syncId, ip: 'a'),
      );
      expect(whole.headers['content-length'], '${blob.length}');
      final chunks = await whole.read().toList();
      expect(chunks.length, greaterThan(1));
      expect([for (final chunk in chunks) ...chunk], blob);

      final cut = await app.call(
        _request('GET', '/v1/blobs/$hash', syncId: syncId, ip: 'a'),
      );
      expect(cut.statusCode, 200);
      app.store.blobFile(idKey, epoch, hash).deleteSync();
      Object? failure;
      await cut.read().drain<void>().catchError(
        (Object error) => failure = error,
      );
      expect(failure, isNotNull);
      for (final secret in [idKey, epoch, hash, dataDirectory.path]) {
        expect(failure.toString(), isNot(contains(secret)));
      }
    });

    test('a body cut short fails with an error that names no store, device or '
        'statement', () async {
      late _CountingStore store;
      final app = appWith(store: (config) => store = _CountingStore(config));
      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.create(idKey).epoch;
      store.insertManifest(
        idKey,
        epoch,
        'device-one',
        'e' * 64,
        Uint8List(manifestResponseChunkBytes * 2),
      );
      for (final interrupt in <void Function()>[
        // Replaced part-way.
        () => store.database.execute(
          "UPDATE manifests SET etag = ? WHERE device_id = 'device-one'",
          ['f' * 64],
        ),
        // A read that fails, as a busy or broken database would.
        () => store.failNextChunk = true,
      ]) {
        store
          ..chunkReads.clear()
          ..beforeSecondChunk = interrupt;
        final response = await app.call(
          _request('GET', '/v1/manifests/device-one', syncId: syncId, ip: 'a'),
        );
        expect(response.statusCode, 200);
        Object? failure;
        await response.read().drain<void>().catchError(
          (Object error) => failure = error,
        );
        expect(failure, isNotNull);
        final text = failure.toString();
        for (final secret in [idKey, epoch, 'device-one', 'SELECT']) {
          expect(text, isNot(contains(secret)));
        }
        store.database.execute(
          "UPDATE manifests SET etag = ? WHERE device_id = 'device-one'",
          ['e' * 64],
        );
      }
    });
  });
}

AthenaeumStore _memoryStore(AthenaeumConfig config) => AthenaeumStore(
  config: config,
  database: sqlite3.sqlite3.openInMemory(),
  breakGlassDatabase: sqlite3.sqlite3.openInMemory(),
  diagnosticDatabase: sqlite3.sqlite3.openInMemory(),
);

class _CountingStore extends AthenaeumStore {
  _CountingStore(AthenaeumConfig config)
    : super(
        config: config,
        database: sqlite3.sqlite3.openInMemory(),
        breakGlassDatabase: sqlite3.sqlite3.openInMemory(),
        diagnosticDatabase: sqlite3.sqlite3.openInMemory(),
      );

  final List<int> chunkReads = [];
  void Function()? beforeSecondChunk;
  bool failNextChunk = false;

  void insertManifest(
    String idKey,
    String epoch,
    String deviceId,
    String etag,
    Uint8List body,
  ) => database.execute(
    'INSERT INTO manifests (id_key, epoch, device_id, etag, written_at, body) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [idKey, epoch, deviceId, etag, 0, body],
  );

  @override
  Uint8List? manifestChunk(
    String idKey,
    String epoch,
    String deviceId, {
    required String etag,
    required int offset,
    required int length,
  }) {
    if (chunkReads.length == 1) beforeSecondChunk?.call();
    if (failNextChunk) {
      failNextChunk = false;
      throw sqlite3.SqliteException(
        extendedResultCode: 5,
        message: 'database is locked',
        causingStatement: 'SELECT substr(body) FROM manifests',
        parametersToStatement: [idKey, epoch, deviceId],
      );
    }
    final chunk = super.manifestChunk(
      idKey,
      epoch,
      deviceId,
      etag: etag,
      offset: offset,
      length: length,
    );
    if (chunk != null) chunkReads.add(chunk.length);
    return chunk;
  }
}

Request _request(
  String method,
  String path, {
  required String syncId,
  required String ip,
  Map<String, String> headers = const {},
  Stream<List<int>>? body,
}) => Request(
  method,
  Uri.parse('http://127.0.0.1$path'),
  headers: {
    'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
    'x-test-ip': ip,
    ...headers,
  },
  body: body,
);

Future<List<int>> _bytes(Response response) async => [
  for (final chunk in await response.read().toList()) ...chunk,
];
