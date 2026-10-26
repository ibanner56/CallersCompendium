import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_failure.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_app/src/sync/sync_isolate.dart';
import 'package:compendium_app/src/sync/sync_invalidation.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the production store forwards the parent-undo capability', () {
    // The engine type-tests for `SyncApplyRestorableStorage` before it captures
    // anything, and the object it is handed in production is this adapter, not
    // `CompendiumSyncStorage`. An adapter that stopped forwarding the
    // capability would therefore lose per-record atomicity in production while
    // every core-level test, which passes the storage directly, kept it.
    final database = CompendiumDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = CompendiumSyncCoordinatorStore(
      CompendiumRepositories(database, contraTaxonomy),
    );
    expect(store, isA<SyncApplyRestorableStorage>());
  });

  test('opens the database and transport inside the pass isolate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-',
    );
    final database = CompendiumDatabase(
      NativeDatabase(File('${directory.path}/compendium.sqlite')),
    );
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({'epoch': 'epoch-1', 'devices': <String>[]}),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    final terminalSeen = Completer<void>();
    final release = Completer<void>();
    final operation = IsolatedSyncPassOperation(
      databasePath: '${directory.path}/compendium.sqlite',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      beforeTerminalAcknowledgement: () {
        terminalSeen.complete();
        return release.future;
      },
    );
    final handle = await operation.start();
    await terminalSeen.future;
    var completed = false;
    final resultFuture = handle.result.then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    release.complete();
    final result = await resultFuture;

    expect(result.status, SyncPassStatus.completed);
    // The store answered without a quota. That the worker read it must still
    // reach the parent, or an old "almost full" reading would stand (§5.2).
    expect(result.storeRead, isTrue);
    expect(result.quota, isNull);
    expect(requests, [
      'GET /v1/store',
      'POST /v1/blobs/missing',
      'PUT /v1/manifests/device-a',
    ]);
  });

  // A failure's cause must survive the port back to the parent: the status
  // surface can explain only what reaches it.
  test(
    "carries a failed pass's cause, step, status, Retry-After and the store's "
    'quota across the isolate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-sync-isolate-',
      );
      final database = CompendiumDatabase(
        NativeDatabase(File('${directory.path}/compendium.sqlite')),
      );
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/v1/store') {
          request.response.write(
            jsonEncode({
              'epoch': 'epoch-1',
              'devices': <String>[],
              'quota': {
                'blobs': 85,
                'bytes': 10,
                'maxBlobs': 100,
                'maxBytes': 1000,
              },
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path == '/v1/blobs/missing') {
          request.response.write(jsonEncode({'missing': <String>[]}));
        } else {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..headers.set('retry-after', '120')
            ..write('{}');
        }
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await database.close();
        await directory.delete(recursive: true);
      });

      final result = await IsolatedSyncPassOperation(
        databasePath: '${directory.path}/compendium.sqlite',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: 'alpha-beta-gamma-delta',
        deviceId: 'device-a',
      ).call();

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.serverError);
      expect(result.failure?.step, SyncFailureStep.publish);
      expect(result.failure?.statusCode, 503);
      expect(result.failure?.retryAfter, const Duration(seconds: 120));
      expect(result.quota?.blobs, 85);
      expect(result.quota?.maxBlobs, 100);
      expect(result.quota?.nearlyFull, isTrue);
    },
  );

  // A connection failure is thrown inside the worker and reaches the parent as
  // text, so the worker has to classify it before it is flattened.
  test('classifies a worker throw before it crosses the isolate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-',
    );
    final database = CompendiumDatabase(
      NativeDatabase(File('${directory.path}/compendium.sqlite')),
    );
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');
    // A port that was just listening and now is not: connection refused.
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await expectLater(
      IsolatedSyncPassOperation(
        databasePath: '${directory.path}/compendium.sqlite',
        endpoint: Uri.parse('http://127.0.0.1:$port'),
        syncId: 'alpha-beta-gamma-delta',
        deviceId: 'device-a',
      ).call(),
      throwsA(
        isA<SyncWorkerFailure>().having(
          (failure) => failure.cause,
          'cause',
          SyncFailureCause.unreachable,
        ),
      ),
    );
  });

  test(
    'round-trips a noncanonical-body report through the sync isolate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-sync-isolate-noncanonical-',
      );
      final databasePath = '${directory.path}/compendium.sqlite';
      final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

      final blob = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'default_program_band',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'e\u0301'},
      );
      final encodedBlob = encodeSyncRecordBlobUtf8(blob);
      final blobHash = sha256Hex(encodedBlob);
      final manifest = SyncManifest(
        deviceId: 'peer',
        epoch: 'epoch-1',
        writtenAt: DateTime.utc(2026, 7, 15, 12),
        records: {
          SyncRecordKind.setting: {blob.id: blobHash},
        },
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        await request.drain<void>();
        if (request.method == 'GET' && path == '/v1/store') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'epoch': 'epoch-1',
              'devices': ['peer'],
            }),
          );
        } else if (request.method == 'GET' && path == '/v1/manifests/peer') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(encodeSyncManifest(manifest));
        } else if (request.method == 'GET' && path == '/v1/blobs/$blobHash') {
          request.response.headers.contentType = ContentType(
            'application',
            'octet-stream',
          );
          request.response.add(encodedBlob);
        } else if (request.method == 'POST' && path == '/v1/blobs/missing') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'missing': <String>[]}));
        } else if (request.method == 'PUT' &&
            path == '/v1/manifests/device-a') {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.contentType = ContentType.json
            ..write('{}');
        }
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await database.close();
        await directory.delete(recursive: true);
      });

      final operation = IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: 'alpha-beta-gamma-delta',
        deviceId: 'device-a',
      );

      final result = await operation.call();

      expect(result.status, SyncPassStatus.completed);
      expect(result.reports, hasLength(1));
      expect(result.reports.single.code, SyncReportCode.nonCanonicalWireBody);
      expect(result.reports.single.peerId, 'peer');
    },
  );

  test(
    'a rate-limited pass crosses the isolate as a temporary failure, and the '
    'next pass reuses the blob it fetched but did not apply',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-sync-isolate-rate-limited-',
      );
      final databasePath = '${directory.path}/compendium.sqlite';
      final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');
      // Newer here than on the peer, so the peer's copy is fetched and then
      // loses the merge: nothing but the session's blob cache can spare the
      // next pass from fetching it again.
      await repositories.settings.set(
        'default_program_band',
        'Local band',
        at: DateTime.utc(2026, 7, 15, 13),
      );

      SyncRecordBlob setting(String id, String value) => SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: id,
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': value},
      );
      final losing = encodeSyncRecordBlobUtf8(
        setting('default_program_band', 'Peer band'),
      );
      final pending = encodeSyncRecordBlobUtf8(
        setting('default_program_caller', 'Peer caller'),
      );
      final losingHash = sha256Hex(losing);
      final pendingHash = sha256Hex(pending);
      final manifest = SyncManifest(
        deviceId: 'peer',
        epoch: 'epoch-1',
        writtenAt: DateTime.utc(2026, 7, 15, 12),
        records: {
          SyncRecordKind.setting: {
            'default_program_band': losingHash,
            'default_program_caller': pendingHash,
          },
        },
      );

      // First pass: the second blob meets the limit. Second pass: it is gone
      // from the store, so its report must carry the 404 across the isolate.
      var pass = 1;
      final blobRequests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        await request.drain<void>();
        if (request.method == 'GET' && path.startsWith('/v1/blobs/')) {
          final hash = path.substring('/v1/blobs/'.length);
          blobRequests.add(hash);
          if (hash == losingHash) {
            request.response.add(losing);
          } else if (pass == 1) {
            request.response
              ..statusCode = HttpStatus.tooManyRequests
              ..headers.set('retry-after', '60')
              ..headers.contentType = ContentType.json
              ..write('{"error":"rate limited"}');
          } else {
            request.response
              ..statusCode = HttpStatus.notFound
              ..headers.contentType = ContentType.json
              ..write('{}');
          }
        } else if (request.method == 'GET' && path == '/v1/store') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'epoch': 'epoch-1',
              'devices': ['peer'],
            }),
          );
        } else if (request.method == 'GET' && path == '/v1/manifests/peer') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(encodeSyncManifest(manifest));
        } else if (request.method == 'POST' && path == '/v1/blobs/missing') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'missing': <String>[]}));
        } else if (request.method == 'PUT' &&
            path == '/v1/manifests/device-a') {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.contentType = ContentType.json
            ..write('{}');
        }
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await database.close();
        await directory.delete(recursive: true);
      });

      final operation = IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: 'alpha-beta-gamma-delta',
        deviceId: 'device-a',
        peerManifestCache: SyncPeerManifestCache(),
      );

      final first = await operation.call();

      expect(first.status, SyncPassStatus.failed);
      expect(first.failure?.cause, SyncFailureCause.rateLimited);
      expect(first.failure?.retryAfter, const Duration(seconds: 60));
      expect(first.failure?.progressed, isTrue);
      expect(first.reports, isEmpty);
      expect(blobRequests, [losingHash, pendingHash]);
      expect(operation.peerManifestCache.fetchedBlob(losingHash), losing);

      pass = 2;
      blobRequests.clear();
      final second = await operation.call();

      expect(blobRequests, [pendingHash]);
      expect(second.status, SyncPassStatus.completed);
      final report = second.reports.singleWhere(
        (r) => r.code == SyncReportCode.unresolvedBlob,
      );
      expect(report.recordId, 'default_program_caller');
      expect(report.httpStatus, 404);
    },
  );

  test(
    'batches cross a real isolate and loopback server: gzip frames, a 429 on '
    'the second batch, and the next pass asks only for the rest',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-sync-isolate-batch-',
      );
      final databasePath = '${directory.path}/compendium.sqlite';
      final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

      final at = DateTime.utc(2026, 7, 15, 12);
      // Past one batch, so the second batch request is the one refused.
      final blobs = <String, List<int>>{};
      final tags = <String, String>{};
      for (var i = 0; i < syncBlobBatchMaxHashes + 50; i++) {
        final id = 'tag-${i.toString().padLeft(4, '0')}';
        final bytes = encodeSyncRecordBlobUtf8(
          SyncRecordBlob(
            kind: SyncRecordKind.tag,
            id: id,
            updatedAt: at,
            deletedAt: null,
            existenceAt: at,
            body: {'id': id, 'name': 'Tag $i', 'color': null},
          ),
        );
        final hash = sha256Hex(bytes);
        blobs[hash] = bytes;
        tags[id] = hash;
      }
      final manifest = SyncManifest(
        deviceId: 'peer',
        epoch: 'epoch-1',
        writtenAt: at,
        records: {SyncRecordKind.tag: tags},
      );

      var pass = 1;
      final batches = <List<String>>[];
      final acceptEncodings = <String?>[];
      var singleRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        final body = await utf8.decodeStream(request);
        final response = request.response;
        if (request.method == 'POST' && path == '/v1/blobs/batch') {
          final hashes = [
            for (final hash in (jsonDecode(body) as Map)['hashes'] as List)
              hash as String,
          ];
          batches.add(hashes);
          acceptEncodings.add(request.headers.value('accept-encoding'));
          if (pass == 1 && batches.length == 2) {
            response
              ..statusCode = HttpStatus.tooManyRequests
              ..headers.set('retry-after', '60')
              ..headers.contentType = ContentType.json
              ..write('{"error":"rate limited"}');
          } else {
            final frames = BytesBuilder(copy: false);
            for (final hash in hashes) {
              final bytes = blobs[hash]!;
              frames
                ..add(
                  encodeSyncBlobBatchFrameHead(
                    SyncBlobBatchFrameStatus.blob,
                    hash,
                    length: bytes.length,
                  ),
                )
                ..add(bytes);
            }
            response.headers
              ..set('content-type', syncBlobBatchMediaType)
              ..set('content-encoding', 'gzip');
            response.add(gzip.encode(frames.takeBytes()));
          }
        } else if (request.method == 'GET' && path.startsWith('/v1/blobs/')) {
          singleRequests++;
          response.statusCode = HttpStatus.notFound;
        } else if (request.method == 'GET' && path == '/v1/store') {
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'epoch': 'epoch-1',
              'devices': ['peer'],
            }),
          );
        } else if (request.method == 'GET' && path == '/v1/manifests/peer') {
          response.headers.contentType = ContentType.json;
          response.write(encodeSyncManifest(manifest));
        } else if (request.method == 'POST' && path == '/v1/blobs/missing') {
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'missing': <String>[]}));
        } else if (request.method == 'PUT' &&
            path == '/v1/manifests/device-a') {
          response.headers.contentType = ContentType.json;
          response.write('{}');
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await database.close();
        await directory.delete(recursive: true);
      });

      final operation = IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: 'alpha-beta-gamma-delta',
        deviceId: 'device-a',
        peerManifestCache: SyncPeerManifestCache(),
      );

      final first = await operation.call();

      expect(first.status, SyncPassStatus.failed);
      expect(first.failure?.cause, SyncFailureCause.rateLimited);
      expect(first.failure?.retryAfter, const Duration(seconds: 60));
      expect(first.failure?.progressed, isTrue);
      expect(first.reports, isEmpty);
      expect(batches, hasLength(2));
      expect(batches.first, hasLength(syncBlobBatchMaxHashes));
      expect(acceptEncodings.first, contains('gzip'));
      expect(singleRequests, 0);
      final ordered = tags.values.toList();
      expect(batches.first, ordered.sublist(0, syncBlobBatchMaxHashes));
      expect(await repositories.tags.getById('tag-0199'), isNotNull);
      expect(await repositories.tags.getById('tag-0200'), isNull);

      pass = 2;
      batches.clear();
      final second = await operation.call();

      expect(second.status, SyncPassStatus.completed);
      expect(second.reports, isEmpty);
      expect(batches, [ordered.sublist(syncBlobBatchMaxHashes)]);
      expect(await repositories.tags.getById('tag-0249'), isNotNull);
    },
  );

  test('a server without the batch route is remembered across the isolate for '
      'the rest of the session', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-no-batch-',
    );
    final databasePath = '${directory.path}/compendium.sqlite';
    final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final at = DateTime.utc(2026, 7, 15, 12);
    final blob = encodeSyncRecordBlobUtf8(
      SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'default_program_caller',
        updatedAt: at,
        deletedAt: null,
        existenceAt: at,
        body: {'value': 'Peer caller'},
      ),
    );
    final hash = sha256Hex(blob);
    final manifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: at,
      records: {
        SyncRecordKind.setting: {'default_program_caller': hash},
      },
    );
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      await request.drain<void>();
      requests.add('${request.method} $path');
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (path == '/v1/blobs/batch') {
        // What an Athenaeum from before the route answers: `batch` is not a
        // hash.
        response
          ..statusCode = HttpStatus.badRequest
          ..write('{"error":"invalid blob hash"}');
      } else if (path == '/v1/blobs/$hash') {
        response.headers.contentType = ContentType.binary;
        response.add(blob);
      } else if (path == '/v1/store') {
        response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (path == '/v1/manifests/peer') {
        response.write(encodeSyncManifest(manifest));
      } else if (path == '/v1/blobs/missing') {
        response.write(jsonEncode({'missing': <String>[]}));
      } else {
        response.write('{}');
      }
      await response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    final operation = IsolatedSyncPassOperation(
      databasePath: databasePath,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      peerManifestCache: SyncPeerManifestCache(),
    );

    final first = await operation.call();

    expect(first.status, SyncPassStatus.completed);
    expect(first.reports, isEmpty);
    expect(requests, contains('POST /v1/blobs/batch'));
    expect(requests, contains('GET /v1/blobs/$hash'));
    final cache = operation.peerManifestCache;
    expect(cache.blobBatchUnsupported, isTrue);
    expect(
      SyncPeerManifestCache.fromMessage(cache.toMessage()).blobBatchUnsupported,
      isTrue,
    );
    cache.clear();
    expect(
      cache.blobBatchUnsupported,
      isFalse,
      reason: 'clearing the cache, as a new session does, forgets it',
    );
  });

  test('the main isolate refuses a malformed cache as decoding it did, without '
      'decoding a manifest (#1934)', () {
    final cache = SyncPeerManifestCache()
      ..['peer'] = SyncPeerManifestCacheEntry(
        epoch: 'epoch-1',
        etag: '"peer-v1"',
        manifest: SyncManifest(
          deviceId: 'peer',
          epoch: 'epoch-1',
          writtenAt: DateTime.utc(2026, 7, 15, 12),
          records: const {},
        ),
      )
      ..rememberFetchedBlob('blob', [1, 2, 3]);
    final message = cache.toMessage();
    SyncPeerManifestCache.debugManifestBodiesDecoded = 0;
    SyncPeerManifestCache.checkMessage(message);
    SyncPeerManifestCache.checkMessage(null);
    expect(SyncPeerManifestCache.debugManifestBodiesDecoded, 0);

    Map<String, Object?> replacing(String key, Object? value) => {
      ...message,
      key: value,
    };
    final malformed = <Object?>[
      'not a map',
      replacing('_entries', null),
      replacing('_entries', {
        'peer': {'epoch': 'epoch-1', 'etag': '"peer-v1"', 'manifest': 7},
      }),
      replacing('_rejectedHashes', [1]),
      replacing('_publications', [
        {'kind': 'noSuchKind', 'recordId': 'r', 'hash': 'h', 'pass': 1},
      ]),
      replacing('_peerPublications', {
        'peer': [
          {'writtenAt': 'yesterday', 'pass': 1},
        ],
      }),
      replacing('_fetchedBlobs', {
        'blob': [1, 2, 3],
      }),
      replacing('_passSequence', -1),
      replacing('_publicationEpoch', 1),
      replacing('_blobBatchUnsupported', 'no'),
      replacing('_blobUploadBatchUnsupported', 'no'),
      replacing('_ownManifest', {'hash': 'h', 'blobHashes': 'all'}),
    ];
    for (final candidate in malformed) {
      expect(
        () => SyncPeerManifestCache.fromMessage(candidate),
        throwsFormatException,
      );
      expect(
        () => SyncPeerManifestCache.checkMessage(candidate),
        throwsFormatException,
        reason: '$candidate',
      );
    }
  });

  test('a malformed cache from the worker is refused on both terminal paths, '
      'and the pre-pass cache kept (#1934)', () async {
    final appliedKindCalls = <Set<SyncRecordKind>>[];
    IsolatedSyncPassOperation operation(
      void Function(Object? request) workerEntryPoint,
    ) => IsolatedSyncPassOperation(
      databasePath: 'unused',
      endpoint: Uri.parse('http://127.0.0.1:1'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      peerManifestCache: SyncPeerManifestCache(rejectedHashes: {'pre-pass'}),
      onAppliedKinds: appliedKindCalls.add,
      workerEntryPoint: workerEntryPoint,
    );

    // A completed pass whose cache is malformed fails, as decoding the cache
    // here made it, before its applied kinds are reported.
    final completed = operation(_completeWithMalformedCache);
    await expectLater(completed.call(), throwsFormatException);
    expect(appliedKindCalls, isEmpty);
    expect(completed.peerManifestCache.rejectedHashes, {'pre-pass'});

    // A failed pass's malformed cache is dropped, and its failure and applied
    // kinds still reach the caller.
    final failed = operation(_failWithMalformedCache);
    await expectLater(
      failed.call(),
      throwsA(
        isA<SyncWorkerFailure>()
            .having((failure) => failure.message, 'message', 'pass failed')
            .having((failure) => failure.appliedKinds, 'appliedKinds', {
              SyncRecordKind.setting,
            }),
      ),
    );
    expect(appliedKindCalls, [
      {SyncRecordKind.setting},
    ]);
    expect(failed.peerManifestCache.rejectedHashes, {'pre-pass'});
  });

  test('the session blob cache crosses the isolate and holds a byte cap', () {
    final cache = SyncPeerManifestCache();
    final small = List<int>.filled(16, 1);
    cache.rememberFetchedBlob('small', small);
    final restored = SyncPeerManifestCache.fromMessage(cache.toMessage());
    expect(restored.fetchedBlob('small'), small);

    // Two blobs of more than half the cap cannot both be kept: the older goes.
    final half = SyncPeerManifestCache.fetchedBlobBytesKept ~/ 2 + 1;
    restored
      ..rememberFetchedBlob('first', List<int>.filled(half, 2))
      ..rememberFetchedBlob('second', List<int>.filled(half, 3));
    expect(restored.fetchedBlob('first'), isNull);
    expect(restored.fetchedBlob('second'), hasLength(half));

    restored.clear();
    expect(restored.fetchedBlob('second'), isNull);
  });

  test('propagates a nonzero fresh-attach duplicate count', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-dedupe-',
    );
    final database = CompendiumDatabase(
      NativeDatabase(File('${directory.path}/compendium.sqlite')),
    );
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    final stamp = DateTime.utc(2026, 7, 15, 12);
    await repositories.dances.create(
      Dance(
        id: 'dance-a',
        title: 'The Shared Dance',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await repositories.dances.create(
      Dance(
        id: 'dance-b',
        title: 'shared dance',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({'epoch': 'epoch-1', 'devices': <String>[]}),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    final operation = IsolatedSyncPassOperation(
      databasePath: '${directory.path}/compendium.sqlite',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
    );

    final result = await operation.call();

    expect(result.status, SyncPassStatus.completed);
    expect(result.duplicateCount, 1);
  });

  test(
    'replacement consumes the validated store before the isolate continuation',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-sync-isolate-replacement-',
      );
      final databasePath = '${directory.path}/compendium.sqlite';
      final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      const syncId = 'alpha-beta-gamma-delta';
      // Deliberately the real derivation, with no `syncIdentityKdfIterations`
      // override: the pass runs in a spawned isolate whose copy of that global
      // is still 600,000, so a marker written at a lowered count would be
      // skipped there as a mismatch.
      await CompendiumSyncStorage(repositories).markSyncUsed(syncId);

      final requests = <String>[];
      var storeGets = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/v1/store') {
          storeGets++;
          if (storeGets == 1) {
            request.response
              ..statusCode = HttpStatus.notFound
              ..write('{}');
          } else {
            request.response.write(
              jsonEncode({'epoch': 'epoch-1', 'devices': <String>[]}),
            );
          }
        } else if (request.method == 'POST' &&
            request.uri.path == '/v1/store') {
          request.response
            ..statusCode = HttpStatus.created
            ..write('{}');
        } else if (request.method == 'POST' &&
            request.uri.path == '/v1/blobs/missing') {
          request.response.write(jsonEncode({'missing': <String>[]}));
        } else if (request.method == 'PUT' &&
            request.uri.path == '/v1/manifests/device-a') {
          request.response.write('{}');
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('{}');
        }
        await request.response.close();
      });

      final operation = IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: syncId,
        deviceId: 'device-a',
      );
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        syncId: syncId,
      );
      final coordinator = SyncCoordinator(
        syncId: syncId,
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repositories, syncId: syncId),
        transport: SyncHttpCoordinatorTransport(client),
        passOperation: operation.call,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await server.close(force: true);
        await database.close();
        await directory.delete(recursive: true);
      });

      expect(
        (await coordinator.onAppStart()).status,
        SyncPassStatus.replacementRequired,
      );
      final confirmation = await coordinator.confirmReplacement();
      expect(confirmation.status, SyncPassStatus.completed);
      expect(storeGets, 3);
      expect(requests, [
        'GET /v1/store',
        'POST /v1/store',
        'GET /v1/store',
        'POST /v1/blobs/missing',
        'GET /v1/store',
        'POST /v1/blobs/missing',
        'PUT /v1/manifests/device-a',
      ]);
    },
  );

  test('preserves peer manifest cache across isolated passes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-cache-',
    );
    final database = CompendiumDatabase(
      NativeDatabase(File('${directory.path}/compendium.sqlite')),
    );
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final peerManifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: DateTime.utc(2026, 7, 15, 12),
      records: const {},
    );
    final manifestEtags = <String?>[];
    final diagnosticAddress = (
      kind: SyncRecordKind.difficultyLevel,
      recordId: 'difficulty-beginner',
    );
    final rejectedHash = List.filled(64, 'f').join();
    // Evidence from earlier in the session: a publication under a hash the
    // store no longer has for that record, and one observation of the peer.
    final seed = SyncPeerManifestCache(
      rejectedHashes: {rejectedHash},
      publications: {
        diagnosticAddress: (hash: List.filled(64, 'e').join(), pass: 7),
      },
      peerPublications: {
        'peer': [(writtenAt: DateTime.utc(2026, 7, 15, 11), pass: 7)],
      },
      passSequence: 7,
      publicationEpoch: 'epoch-1',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/manifests/peer') {
        final etag = request.headers.value(HttpHeaders.ifNoneMatchHeader);
        manifestEtags.add(etag);
        request.response.headers.set(HttpHeaders.etagHeader, '"peer-v1"');
        if (etag == '"peer-v1"') {
          request.response.statusCode = HttpStatus.notModified;
        } else {
          request.response.write(encodeSyncManifest(peerManifest));
        }
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    final operation = IsolatedSyncPassOperation(
      databasePath: '${directory.path}/compendium.sqlite',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      peerManifestCache: seed,
    );
    SyncPeerManifestCache.debugManifestBodiesEncoded = 0;
    SyncPeerManifestCache.debugManifestBodiesDecoded = 0;

    final first = await operation.call();
    expect(first.status, SyncPassStatus.completed);
    expect((await operation.call()).status, SyncPassStatus.completed);
    expect(manifestEtags, [null, '"peer-v1"']);
    // The main isolate relays the cache and never reads it, so it neither
    // decodes the peer manifest the first pass returned nor re-encodes it
    // for the second; the counters are isolate-local, so the worker's own
    // decoding is not counted here (#1934). Read before the decoding getter.
    expect(SyncPeerManifestCache.debugManifestBodiesDecoded, 0);
    expect(SyncPeerManifestCache.debugManifestBodiesEncoded, 0);
    final peerManifestCache = operation.peerManifestCache;
    expect(
      peerManifestCache['peer']?.etag,
      '"peer-v1"',
      reason: 'the counters are zero for a cache that holds a manifest',
    );
    expect(SyncPeerManifestCache.debugManifestBodiesDecoded, 1);
    expect(peerManifestCache.rejectedHashes, {rejectedHash});
    // The peer summary crosses the boundary with the result: the peer lists
    // nothing, so everything this device publishes is waiting for it.
    final summary = first.peers!.single;
    expect(summary.peerId, 'peer');
    expect(summary.writtenAt, DateTime.utc(2026, 7, 15, 12));
    expect(summary.waitingCount, peerManifestCache.publications.length);
    expect(summary.waitingCount, greaterThan(0));
    // Both passes' evidence came back across the boundary: the sequence
    // advanced once per pass from where the session left it, the peer's new
    // `writtenAt` was recorded beside the older one on the first pass and
    // not again on the second, and the publications the first pass recorded
    // were still there — unrenumbered — after the second.
    expect(peerManifestCache.passSequence, 9);
    expect(peerManifestCache.peerPublications['peer'], [
      (writtenAt: DateTime.utc(2026, 7, 15, 11), pass: 7),
      (writtenAt: DateTime.utc(2026, 7, 15, 12), pass: 8),
    ]);
    expect(
      peerManifestCache.publications.keys,
      containsAll([
        diagnosticAddress,
        (
          kind: SyncRecordKind.difficultyLevel,
          recordId: 'difficulty-intermediate',
        ),
        (kind: SyncRecordKind.difficultyLevel, recordId: 'difficulty-advanced'),
      ]),
    );
    expect(
      peerManifestCache.publications[diagnosticAddress]?.pass,
      8,
      reason: 'a changed hash restarts the evidence for that record',
    );
    expect(peerManifestCache.publications.values.map((p) => p.pass).toSet(), {
      8,
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('refreshes a main-isolate watch after inbound worker write', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-watch-',
    );
    final databasePath = '${directory.path}/compendium.sqlite';
    final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.settings.set(
      'theme_mode',
      'before-first',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final incoming = _setting('theme_mode', 'after-first', seconds: 1);
    final incomingHash = sha256Hex(encodeSyncRecordBlobUtf8(incoming));
    final peerManifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: DateTime.utc(2026, 7, 15, 12),
      records: {
        SyncRecordKind.setting: {incoming.id: incomingHash},
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/manifests/peer') {
        request.response.write(encodeSyncManifest(peerManifest));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/blobs/$incomingHash') {
        request.response.add(encodeSyncRecordBlobUtf8(incoming));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });

    final changes = StreamIterator(
      (database.select(
        database.settings,
      )..where((table) => table.key.equals('theme_mode'))).watch(),
    );
    addTearDown(() async {
      await changes.cancel();
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(await changes.moveNext(), isTrue);
    expect(changes.current.single.valueJson, jsonEncode('before-first'));

    Set<SyncRecordKind>? appliedKinds;
    final operation = IsolatedSyncPassOperation(
      databasePath: databasePath,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      onAppliedKinds: (kinds) {
        appliedKinds = kinds;
        markSyncAppliedTablesUpdated(database, kinds);
      },
    );
    final result = await operation.call();
    expect(result.status, SyncPassStatus.completed);

    final persisted = await (database.select(
      database.settings,
    )..where((table) => table.key.equals('theme_mode'))).getSingle();
    expect(jsonDecode(persisted.valueJson), 'after-first');
    expect(appliedKinds, {SyncRecordKind.setting});
    expect(
      await changes.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(changes.current.single.valueJson, jsonEncode('after-first'));
  });

  test('a pass that throws after its apply committed still reports the kinds '
      'it applied (#1913)', () async {
    // The repro from #1913: the peer's setting is applied and committed, then
    // the manifest PUT loses its connection. The pass throws, and before the
    // fix the throw carried no applied kinds, so the main isolate's watch and
    // settings controllers stayed stale; the retry then found the row already
    // matching the peer, applied nothing, and never reported it either.
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-throw-',
    );
    final databasePath = '${directory.path}/compendium.sqlite';
    final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.settings.set(
      'theme_mode',
      'before-first',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final incoming = _setting('theme_mode', 'after-first', seconds: 1);
    final incomingHash = sha256Hex(encodeSyncRecordBlobUtf8(incoming));
    final peerManifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: DateTime.utc(2026, 7, 15, 12),
      records: {
        SyncRecordKind.setting: {incoming.id: incomingHash},
      },
    );
    var dropManifestPut = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a' &&
          dropManifestPut) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/manifests/peer') {
        request.response.headers.set(HttpHeaders.etagHeader, '"peer-v1"');
        request.response.write(encodeSyncManifest(peerManifest));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/blobs/$incomingHash') {
        request.response.add(encodeSyncRecordBlobUtf8(incoming));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });

    final changes = StreamIterator(
      (database.select(
        database.settings,
      )..where((table) => table.key.equals('theme_mode'))).watch(),
    );
    addTearDown(() async {
      await changes.cancel();
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(await changes.moveNext(), isTrue);
    expect(changes.current.single.valueJson, jsonEncode('before-first'));

    final appliedKindCalls = <Set<SyncRecordKind>>[];
    final operation = IsolatedSyncPassOperation(
      databasePath: databasePath,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      onAppliedKinds: (kinds) {
        appliedKindCalls.add(kinds);
        markSyncAppliedTablesUpdated(database, kinds);
      },
    );
    SyncPeerManifestCache.debugManifestBodiesEncoded = 0;
    SyncPeerManifestCache.debugManifestBodiesDecoded = 0;
    await expectLater(
      operation.call(),
      throwsA(
        isA<SyncWorkerFailure>()
            .having(
              (failure) => failure.cause,
              'cause',
              SyncFailureCause.unreachable,
            )
            .having((failure) => failure.appliedKinds, 'appliedKinds', {
              SyncRecordKind.setting,
            }),
      ),
    );

    final persisted = await (database.select(
      database.settings,
    )..where((table) => table.key.equals('theme_mode'))).getSingle();
    expect(
      jsonDecode(persisted.valueJson),
      'after-first',
      reason: 'the apply committed before the manifest PUT failed',
    );
    expect(appliedKindCalls, [
      {SyncRecordKind.setting},
    ]);
    expect(
      await changes.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(changes.current.single.valueJson, jsonEncode('after-first'));
    // The failed pass's cache was taken in without being decoded here (#1934);
    // read before the decoding getter below.
    expect(SyncPeerManifestCache.debugManifestBodiesDecoded, 0);
    // What the failed pass learned was adopted rather than the pre-pass
    // cache kept: the peer manifest it had verified.
    expect(operation.peerManifestCache['peer']?.etag, '"peer-v1"');

    // The retry is no substitute: the row already matches the peer, so it
    // applies and reports nothing. That is why the failed pass must report.
    dropManifestPut = false;
    SyncPeerManifestCache.debugManifestBodiesEncoded = 0;
    SyncPeerManifestCache.debugManifestBodiesDecoded = 0;
    final retry = await operation.call();
    expect(retry.status, SyncPassStatus.completed);
    expect(retry.appliedKinds, isEmpty);
    expect(appliedKindCalls, hasLength(1));
    // The main isolate relayed the failed pass's cache to the retry, and the
    // retry's back again, without decoding or re-encoding either (#1934).
    expect(SyncPeerManifestCache.debugManifestBodiesDecoded, 0);
    expect(SyncPeerManifestCache.debugManifestBodiesEncoded, 0);
  });

  test('a worker that dies of an uncaught error reports every kind, once '
      '(#1913)', () async {
    // The pass's own `try` catches what the pass throws; an error from a timer
    // or an unawaited future in the worker escapes it, and `errorsAreFatal`
    // ends the worker with no terminal message. What it had committed is then
    // as unknown as for a killed worker, so the same fallback must run, and
    // only once although both the error and the exit port hear of the death.
    final appliedKindCalls = <Set<SyncRecordKind>>[];
    final operation = IsolatedSyncPassOperation(
      databasePath: 'unused',
      endpoint: Uri.parse('http://127.0.0.1:1'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      onAppliedKinds: appliedKindCalls.add,
      workerEntryPoint: _crashWithUncaughtError,
    );

    await expectLater(
      operation.call(),
      throwsA(
        isA<SyncIsolateCrashed>()
            .having(
              (error) => error.message,
              'message',
              contains('uncaught in the worker'),
            )
            .having(
              (error) => syncAppliedKindsForError(error),
              'applied kinds',
              SyncRecordKind.values.toSet(),
            ),
      ),
    );
    // Give a late exit-port message the chance to report a second time.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(appliedKindCalls, [SyncRecordKind.values.toSet()]);
  });

  test('terminating during apply leaves an atomic database state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-',
    );
    final databasePath = '${directory.path}/compendium.sqlite';
    final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.settings.set(
      'theme_mode',
      'before-first',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.settings.set(
      'default_program_band',
      'before-second',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');
    await database.close();

    final first = _setting('theme_mode', 'after-first', seconds: 1);
    final second = _setting('default_program_band', 'after-second', seconds: 2);
    final firstHash = sha256Hex(encodeSyncRecordBlobUtf8(first));
    final secondHash = sha256Hex(encodeSyncRecordBlobUtf8(second));
    final peerManifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: DateTime.utc(2026, 7, 15, 12),
      records: {
        SyncRecordKind.setting: {first.id: firstHash, second.id: secondHash},
      },
    );
    final blobs = {
      firstHash: encodeSyncRecordBlobUtf8(first),
      secondHash: encodeSyncRecordBlobUtf8(second),
    };

    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/manifests/peer') {
        request.response.write(encodeSyncManifest(peerManifest));
      } else if (request.method == 'GET' &&
          request.uri.path.startsWith('/v1/blobs/')) {
        final blob = blobs[request.uri.pathSegments.last];
        if (blob == null) {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('{}');
        } else {
          request.response.add(blob);
        }
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });

    final applyControl = SyncIsolateApplyControl();
    CompendiumDatabase? verificationDatabase;
    addTearDown(() async {
      await applyControl.close();
      await server.close(force: true);
      await verificationDatabase?.close();
      await directory.delete(recursive: true);
    });

    final appliedKindCalls = <Set<SyncRecordKind>>[];
    final operation = IsolatedSyncPassOperation(
      databasePath: databasePath,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      onAppliedKinds: appliedKindCalls.add,
    );
    final handle = await operation.start(applyControl: applyControl);
    await applyControl.applyStarted.timeout(const Duration(seconds: 10));
    handle.kill();
    await expectLater(
      handle.result,
      throwsA(
        isA<SyncIsolateInterrupted>().having(
          (error) => syncAppliedKindsForError(error),
          'applied kinds',
          SyncRecordKind.values.toSet(),
        ),
      ),
    );
    // A dead worker says nothing about what it committed, so every kind is
    // reported rather than none (#1913). Without the fallback a worker that
    // dies after its apply commits leaves the main isolate stale for good.
    expect(appliedKindCalls, [SyncRecordKind.values.toSet()]);

    verificationDatabase = CompendiumDatabase(
      NativeDatabase(File(databasePath)),
    );
    final verificationRepositories = CompendiumRepositories(
      verificationDatabase,
      contraTaxonomy,
    );
    final values = {
      'theme_mode': await verificationRepositories.settings.get('theme_mode'),
      'default_program_band': await verificationRepositories.settings.get(
        'default_program_band',
      ),
    };
    expect(values, {
      'theme_mode': 'before-first',
      'default_program_band': 'before-second',
    });
    expect(
      await verificationRepositories.syncLocal.snapshotBaseline(),
      isEmpty,
    );
    expect(requests, contains('GET /v1/manifests/peer'));
  });
}

/// A worker entry point that dies the way a real worker's stray async error
/// would: thrown outside any `try`, after the entry point has returned.
/// Posts [message] as a worker's terminal message and waits, as the real
/// worker does, for the acknowledgement.
Future<void> _postTerminal(
  Object? request,
  Map<String, Object?> message,
) async {
  final acknowledgement = ReceivePort();
  syncPassResultPort(
    request,
  ).send({...message, 'ack': acknowledgement.sendPort});
  await acknowledgement.first;
  acknowledgement.close();
}

const _malformedCache = {'_entries': 'not a map'};

void _completeWithMalformedCache(Object? request) => unawaited(
  _postTerminal(request, {
    'type': 'result',
    'result': {
      'status': 'completed',
      'appliedKinds': ['setting'],
      'reports': <Object?>[],
      '_peerManifestCache': _malformedCache,
    },
  }),
);

void _failWithMalformedCache(Object? request) => unawaited(
  _postTerminal(request, {
    'type': 'error',
    'message': 'pass failed',
    'failureCause': 'unreachable',
    'appliedKinds': ['setting'],
    '_peerManifestCache': _malformedCache,
  }),
);

void _crashWithUncaughtError(Object? request) {
  Timer.run(() => throw StateError('uncaught in the worker'));
}

SyncRecordBlob _setting(String id, String value, {int seconds = 0}) {
  final stamp = DateTime.utc(2026, 7, 15, 12).add(Duration(seconds: seconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.setting,
    id: id,
    updatedAt: stamp,
    deletedAt: null,
    existenceAt: stamp,
    body: {'value': value},
  );
}
