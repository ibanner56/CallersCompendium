import 'dart:async';
import 'dart:io';
import 'dart:math';

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
        request.response.statusCode = HttpStatus.notModified;
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
    });
  });
}
