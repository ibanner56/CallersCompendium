import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _startServer(
  FutureOr<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen(handler);
  return server;
}

void main() {
  group('SyncHttpClient transport', () {
    test('issues non-ASCII credentials with the Bearer scheme', () async {
      final requestSeen = Completer<HttpHeaders>();
      final server = await _startServer((request) async {
        if (!requestSeen.isCompleted) requestSeen.complete(request.headers);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'CAF\u0045\u0301-horse-battery-staple',
      );
      addTearDown(client.close);

      final result = await client.getStore(previouslyUsed: false);
      expect(result.response.kind, SyncResponseKind.success);
      expect(
        (await requestSeen.future).value('authorization'),
        'Bearer ${encodeSyncCredential('café-horse-battery-staple')}',
      );
    });

    test(
      'refuses a foreign redirect before issuing a second request',
      () async {
        var requests = 0;
        final server = await _startServer((request) async {
          requests++;
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set('location', 'https://foreign.example/v1/store');
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        final result = await client.getStore(previouslyUsed: false);

        expect(result.response.kind, SyncResponseKind.redirectRefused);
        expect(requests, 1);
      },
    );

    test('refuses malformed redirect locations as typed outcomes', () async {
      final server = await _startServer((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '%not-a-uri');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      final result = await client.getStore(previouslyUsed: false);

      expect(result.response.kind, SyncResponseKind.redirectRefused);
    });

    test(
      'refuses an untrusted certificate before sending authorization',
      () async {
        final context = SecurityContext()
          ..useCertificateChain('test/sync/fixtures/untrusted_sync_cert.pem')
          ..usePrivateKey('test/sync/fixtures/untrusted_sync_key.pem');
        var requests = 0;
        final server = await HttpServer.bindSecure('localhost', 0, context);
        server.listen((request) {
          requests++;
          request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final client = SyncHttpClient(
          endpoint: Uri.parse('https://localhost:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        await expectLater(
          client.request('GET', 'store'),
          throwsA(isA<HandshakeException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(requests, 0);
      },
    );

    test('requires exact local HTTP endpoint exemptions', () {
      for (final uri in [
        Uri.parse('http://localhost.example.com/'),
        Uri.parse('http://[::1]/'),
        Uri.parse('http://127.0.0.2/'),
        Uri.parse('http://2130706433/'),
        Uri.parse('http://0x7f000001/'),
      ]) {
        expect(
          () => validateSyncEndpoint(uri),
          throwsA(isA<SyncEndpointException>()),
          reason: uri.toString(),
        );
      }
      expect(
        validateSyncEndpoint(Uri.parse('https://sync.example/')).host,
        'sync.example',
      );
      expect(
        validateSyncEndpoint(Uri.parse('http://LOCALHOST:8080/')).host,
        'localhost',
      );
    });

    test('does not allow transport limits above protocol maxima', () {
      final endpoint = Uri.parse('http://localhost/');
      expect(
        () => SyncHttpClient(
          endpoint: endpoint,
          syncId: 'one-two-three-four',
          maxRedirects: syncMaxRedirects + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncHttpClient(
          endpoint: endpoint,
          syncId: 'one-two-three-four',
          maxResponseBytes: syncMaxResponseBytes + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncHttpClient(
          endpoint: endpoint,
          syncId: 'one-two-three-four',
          requestTimeout: syncRequestTimeout + const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test(
      'cancels stalled header and body waits at the request deadline',
      () async {
        var requests = 0;
        final holdFirstResponse = Completer<void>();
        final holdSecondResponse = Completer<void>();
        final server = await _startServer((request) async {
          requests++;
          if (requests == 1) {
            await holdFirstResponse.future;
            return;
          }
          request.response.add([0x61]);
          await request.response.flush();
          await holdSecondResponse.future;
        });
        addTearDown(() {
          holdFirstResponse.complete();
          holdSecondResponse.complete();
          return server.close(force: true);
        });

        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
          requestTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(client.close);

        await expectLater(
          client.getStore(previouslyUsed: false),
          throwsA(isA<SyncTransportException>()),
        );
        await expectLater(
          client.getStore(previouslyUsed: false),
          throwsA(isA<SyncTransportException>()),
        );
        expect(requests, 2);
      },
      timeout: const Timeout(Duration(seconds: 1)),
    );

    test('enforces the absolute decoded response-size cap', () async {
      var sentChunks = 0;
      final chunks = [
        for (var offset = 0; offset < 1024; offset += 8)
          List<int>.filled(min(8, 1024 - offset), 0x61),
      ];
      final server = await _startServer((request) async {
        request.response.bufferOutput = false;
        try {
          for (final chunk in chunks) {
            request.response.add(chunk);
            await request.response.flush();
            sentChunks++;
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } on IOException {
          // The client canceled the response after the limit was exceeded.
        }
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
        maxResponseBytes: 100,
      );
      addTearDown(client.close);

      await expectLater(
        client.request('GET', 'store'),
        throwsA(isA<SyncEndpointException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sentChunks, lessThan(chunks.length));
    });

    test('buffers plain and gzip response bodies as Uint8List', () async {
      final payload = utf8.encode(List.filled(4096, 'manifest ').join());
      final server = await _startServer((request) async {
        if (request.uri.path.endsWith('/gzip')) {
          request.response.headers.set('content-encoding', 'gzip');
          request.response.add(gzip.encode(payload));
        } else {
          request.response.add(payload);
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      for (final path in ['plain', 'gzip']) {
        final response = await client.request('GET', path);
        expect(response.body, isA<Uint8List>(), reason: path);
        expect(response.body, payload, reason: path);
      }
    });

    test('aborts a gzip response exceeding the decompression ratio', () async {
      final compressed = gzip.encode(List<int>.filled(1024 * 1024, 0x61));
      var sentChunks = 0;
      final chunks = [
        for (var offset = 0; offset < compressed.length; offset += 8)
          compressed.sublist(offset, min(offset + 8, compressed.length)),
      ];
      final server = await _startServer((request) async {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.bufferOutput = false;
        try {
          for (final chunk in chunks) {
            request.response.add(chunk);
            await request.response.flush();
            sentChunks++;
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } on IOException {
          // The client canceled the response after the limit was exceeded.
        }
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      await expectLater(
        client.request('GET', 'store'),
        throwsA(isA<SyncEndpointException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sentChunks, lessThan(chunks.length));
    });

    test('refuses every redirect from a configured non-default port', () async {
      var requests = 0;
      final server = await _startServer((request) async {
        requests++;
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '/v1/store');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      final result = await client.getStore(previouslyUsed: false);

      expect(result.response.kind, SyncResponseKind.redirectRefused);
      expect(requests, 1);
    });
  });

  group('SyncHttpClient outcomes', () {
    test(
      'distinguishes first-time and previously used missing stores',
      () async {
        final methods = <String>[];
        final server = await _startServer((request) async {
          methods.add(request.method);
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        final first = await client.getStore(previouslyUsed: false);
        final prior = await client.getStore(previouslyUsed: true);

        expect(first.missingKind, SyncStoreMissingKind.firstTime);
        expect(prior.missingKind, SyncStoreMissingKind.replacementRequired);
        expect(methods, ['GET', 'GET']);
      },
    );

    test('types conflicts, rejection, and Retry-After', () async {
      final responses = <(int, Map<String, String>)>[
        (HttpStatus.conflict, const {}),
        (HttpStatus.unprocessableEntity, const {}),
        (HttpStatus.tooManyRequests, const {'retry-after': '7'}),
        (
          HttpStatus.tooManyRequests,
          const {'retry-after': 'Wed, 01 Jan 2020 00:00:00 GMT'},
        ),
        (HttpStatus.tooManyRequests, const {'retry-after': 'not a date'}),
      ];
      final server = await _startServer((request) async {
        final (status, headers) = responses.removeAt(0);
        request.response.statusCode = status;
        headers.forEach(request.response.headers.set);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      expect((await client.createStore()).kind, SyncResponseKind.conflict);
      expect(
        (await client.request('PUT', 'manifests/device')).kind,
        SyncResponseKind.rejected,
      );
      final limited = await client.request('GET', 'store');
      expect(limited.kind, SyncResponseKind.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 7));
      final expired = await client.request('GET', 'store');
      expect(expired.retryAfter, Duration.zero);
      final malformed = await client.request('GET', 'store');
      expect(malformed.retryAfter, isNull);
    });

    test('types transient and unexpected statuses separately', () async {
      final statuses = [HttpStatus.serviceUnavailable, 418];
      final server = await _startServer((request) async {
        request.response.statusCode = statuses.removeAt(0);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      expect(
        (await client.request('GET', 'store')).kind,
        SyncResponseKind.serverError,
      );
      expect(
        (await client.request('GET', 'store')).kind,
        SyncResponseKind.unexpectedStatus,
      );
    });

    test('sends ETags and blob content types on the correct paths', () async {
      final requests = <HttpRequest>[];
      final server = await _startServer((request) async {
        requests.add(request);
        request.response.statusCode = requests.length == 1
            ? HttpStatus.notModified
            : HttpStatus.created;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      final response = await client.getManifest('device/id', etag: '"hash"');
      expect(response.kind, SyncResponseKind.notModified);
      expect(requests.single.uri.path, '/v1/manifests/device%2Fid');
      expect(requests.single.headers.value('if-none-match'), '"hash"');
      expect(
        requests.single.headers.value('authorization'),
        'Bearer ${encodeSyncCredential('one-two-three-four')}',
      );

      final blobResponse = await client.putBlob('hash', [1, 2, 3]);
      expect(blobResponse.kind, SyncResponseKind.created);
      expect(requests, hasLength(2));
      expect(requests[1].uri.path, '/v1/blobs/hash');
      expect(
        requests[1].headers.value('content-type'),
        'application/octet-stream',
      );
    });

    test('treats 304 outside conditional manifest GET as unexpected', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      expect(
        (await client.putBlob('hash', [1, 2, 3])).kind,
        SyncResponseKind.unexpectedStatus,
      );
      expect(
        (await client.getManifest('device')).kind,
        SyncResponseKind.unexpectedStatus,
      );
      expect(
        (await client.getManifest('device', etag: '"hash"')).kind,
        SyncResponseKind.notModified,
      );
    });

    test('carries the manifest epoch only in its body', () async {
      final requests = <HttpRequest>[];
      final server = await _startServer((request) async {
        requests.add(request);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      await client.putManifest('device', utf8.encode('{"epoch":"epoch-1"}'));

      expect(requests.single.headers.value('x-sync-epoch'), isNull);
    });

    test('removes one device manifest with a single DELETE at the encoded '
        'path', () async {
      final requests = <HttpRequest>[];
      final server = await _startServer((request) async {
        requests.add(request);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      // A device id is server-minted base64url, but it arrives here as an
      // opaque string the user picked off a list, so the path segment is
      // encoded rather than trusted: an unencoded `/` would address a
      // different route entirely.
      final response = await client.deleteManifest('peer/a b');

      expect(response.kind, SyncResponseKind.success);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'DELETE');
      expect(requests.single.uri.path, '/v1/manifests/peer%2Fa%20b');
      expect(
        requests.single.headers.value('authorization'),
        isNotNull,
        reason: 'a removal is authenticated like every other request',
      );

      // `Uri.encodeComponent` leaves dots alone, so a traversal attempt
      // survives encoding as literal `..` — and `_uri`'s whole-path check
      // rejects it before anything is sent. A server-minted id is base64url
      // and can never contain a dot, so this costs nothing real.
      await expectLater(
        client.deleteManifest('peer/../store'),
        throwsArgumentError,
      );
      expect(requests, hasLength(1), reason: 'nothing more was sent');
    });

    test('deletes the whole store with a single DELETE', () async {
      final requests = <HttpRequest>[];
      final server = await _startServer((request) async {
        requests.add(request);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      final response = await client.deleteStore();

      expect(response.kind, SyncResponseKind.success);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'DELETE');
      expect(requests.single.uri.path, '/v1/store');
    });

    test(
      'a wipe against a store that is already gone reads as notFound',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        expect(
          (await client.deleteStore()).kind,
          SyncResponseKind.notFound,
          reason: 'the controller treats this as the end state, not a failure',
        );
      },
    );

    test('posts the bounded missing-blob request as JSON', () async {
      final requests = <HttpRequest>[];
      final bodies = <Object?>[];
      final server = await _startServer((request) async {
        requests.add(request);
        final bytes = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        bodies.add(jsonDecode(utf8.decode(bytes)));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json;
        request.response.write('{"missing":[]}');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final hash = List.filled(64, 'a').join();
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);

      final response = await client.postMissing([hash]);

      expect(response.kind, SyncResponseKind.success);
      expect(requests.single.uri.path, '/v1/blobs/missing');
      expect(requests.single.headers.contentType?.mimeType, 'application/json');
      expect(bodies.single, {
        'hashes': [hash],
      });
    });

    test(
      'enforces manifest and blob response limits before allocation',
      () async {
        final server = await _startServer((request) async {
          final limit = request.uri.path.contains('/manifests/')
              ? syncMaxManifestResponseBytes
              : syncMaxBlobResponseBytes;
          request.response.add(List<int>.filled(limit + 1, 0x61));
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        await expectLater(
          client.getManifest('device'),
          throwsA(isA<SyncEndpointException>()),
        );
        await expectLater(
          client.getBlob('hash'),
          throwsA(isA<SyncEndpointException>()),
        );
      },
    );
  });

  group('SyncHttpClient.postBlobBatch (spec §5.2)', () {
    final first = sha256Hex(utf8.encode('first'));
    final second = sha256Hex(utf8.encode('second'));

    List<int> blobFrame(String hash, List<int> body) => [
      ...encodeSyncBlobBatchFrameHead(
        SyncBlobBatchFrameStatus.blob,
        hash,
        length: body.length,
      ),
      ...body,
    ];

    Future<SyncHttpClient> clientFor(
      FutureOr<void> Function(HttpRequest request) handler,
    ) async {
      final server = await _startServer(handler);
      addTearDown(() => server.close(force: true));
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        syncId: 'one-two-three-four',
      );
      addTearDown(client.close);
      return client;
    }

    test(
      'asks for gzip and hands each frame on, compressed past 10×',
      () async {
        // Twenty identical-shaped records compress far past the 10× guard the
        // other routes apply; a batch must still be read.
        final hashes = [
          for (var i = 0; i < 20; i++) sha256Hex(utf8.encode('$i')),
        ];
        final body = [
          for (final hash in hashes)
            ...blobFrame(hash, utf8.encode('{"padding":"${'a' * 2000}"}')),
        ];
        final compressed = gzip.encode(body);
        expect(body.length / compressed.length, greaterThan(10));
        String? acceptEncoding;
        final client = await clientFor((request) async {
          acceptEncoding = request.headers.value('accept-encoding');
          await request.drain<void>();
          request.response.headers
            ..set('content-type', syncBlobBatchMediaType)
            ..set('content-encoding', 'gzip');
          request.response.add(compressed);
          await request.response.close();
        });
        final frames = <SyncBlobBatchFrame>[];

        final response = await client.postBlobBatch(
          hashes,
          onFrame: frames.add,
        );

        expect(response.kind, SyncResponseKind.success);
        expect(acceptEncoding, contains('gzip'));
        expect([for (final f in frames) f.hash], hashes);
      },
    );

    test('a 200 that is not a batch comes back as unexpected', () async {
      final client = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>captive portal</html>');
        await request.response.close();
      });
      final frames = <SyncBlobBatchFrame>[];

      final response = await client.postBlobBatch([first], onFrame: frames.add);

      expect(response.statusCode, 200);
      expect(response.kind, SyncResponseKind.unexpectedStatus);
      expect(frames, isEmpty);
    });

    test('a response that ends cleanly before every hash is answered throws '
        'as a network failure, after handing on what arrived', () async {
      final client = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers.set('content-type', syncBlobBatchMediaType);
        request.response.add(blobFrame(first, utf8.encode('one')));
        await request.response.close();
      });
      final frames = <SyncBlobBatchFrame>[];

      await expectLater(
        client.postBlobBatch([first, second], onFrame: frames.add),
        throwsA(isA<HttpException>()),
      );
      expect([for (final f in frames) f.hash], [first]);
    });

    test('a malformed frame throws as a malformed reply', () async {
      final client = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers.set('content-type', syncBlobBatchMediaType);
        request.response.add(blobFrame(second, utf8.encode('two')));
        await request.response.close();
      });

      await expectLater(
        client.postBlobBatch([first], onFrame: (_) {}),
        throwsA(isA<SyncEndpointException>()),
      );
    });

    test('a corrupt gzip body throws as a malformed reply, so the caller '
        'falls back', () async {
      final client = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers
          ..set('content-type', syncBlobBatchMediaType)
          ..set('content-encoding', 'gzip');
        request.response.add(utf8.encode('this is not gzip at all'));
        await request.response.close();
      });

      await expectLater(
        client.postBlobBatch([first], onFrame: (_) {}),
        throwsA(isA<SyncEndpointException>()),
      );
    });

    test('caps the decoded response, and the encoded one', () async {
      // Blob frames of 1 MB each, more of them than the cap allows.
      final hashes = [
        for (var i = 0; i < 3; i++) sha256Hex(utf8.encode('big $i')),
      ];
      final body = [
        for (final hash in hashes)
          ...blobFrame(hash, List<int>.filled(syncMaxBlobResponseBytes, 0x61)),
      ];
      expect(body.length, greaterThan(syncMaxBlobBatchResponseBytes));
      final plain = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers.set('content-type', syncBlobBatchMediaType);
        request.response.add(body);
        await request.response.close();
      });
      await expectLater(
        plain.postBlobBatch(hashes, onFrame: (_) {}),
        throwsA(isA<SyncEndpointException>()),
      );

      // Empty gzip members decode to nothing, so only the encoded cap stops
      // them.
      final emptyMember = gzip.encode(const []);
      final members = [
        for (
          var i = 0;
          i * emptyMember.length <= syncMaxBlobBatchResponseBytes * 2;
          i++
        )
          ...emptyMember,
      ];
      final bomb = await clientFor((request) async {
        await request.drain<void>();
        request.response.headers
          ..set('content-type', syncBlobBatchMediaType)
          ..set('content-encoding', 'gzip');
        request.response.add(members);
        await request.response.close();
      });
      await expectLater(
        bomb.postBlobBatch([first], onFrame: (_) {}),
        throwsA(isA<SyncEndpointException>()),
      );
    });
  });

  group('SyncHttpClient.putBlobBatch (spec §5.2)', () {
    test(
      'sends gzip-compressed blob frames with the batch media type',
      () async {
        final blobs = [for (var i = 0; i < 3; i++) utf8.encode('{"n":$i}')];
        final received = <SyncBlobBatchFrame>[];
        String? contentType;
        String? encoding;
        final server = await _startServer((request) async {
          contentType = request.headers.value('content-type');
          encoding = request.headers.value('content-encoding');
          final body = await request.fold<List<int>>(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          );
          SyncBlobBatchFrameReader.upload(
              maxBlobBytes: syncMaxBlobResponseBytes,
            )
            ..add(gzip.decode(body), received.add)
            ..close();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'results': [
                for (final frame in received)
                  {'hash': frame.hash, 'status': 201},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));
        final client = SyncHttpClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        final response = await client.putBlobBatch([
          for (final blob in blobs) (hash: sha256Hex(blob), body: blob),
        ]);

        expect(response.kind, SyncResponseKind.success);
        expect(contentType, startsWith(syncBlobBatchMediaType));
        expect(encoding, 'gzip');
        expect([for (final frame in received) frame.body], blobs);
      },
    );
  });
}
