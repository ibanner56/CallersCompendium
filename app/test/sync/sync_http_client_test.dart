import 'dart:async';
import 'dart:io';

import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SyncHttpClient transport', () {
    test('issues non-ASCII credentials with the Bearer scheme', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final requestSeen = Completer<HttpHeaders>();
      final subscription = server.listen((request) {
        if (!requestSeen.isCompleted) requestSeen.complete(request.headers);
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

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
        final requests = <http.BaseRequest>[];
        final mock = MockClient((request) async {
          requests.add(request);
          return http.Response(
            '',
            HttpStatus.found,
            headers: {'location': 'https://foreign.example/v1/store'},
          );
        });
        final client = SyncHttpClient(
          endpoint: Uri.parse('http://localhost:8080/'),
          syncId: 'one-two-three-four',
          client: mock,
        );
        addTearDown(client.close);

        final result = await client.getStore(previouslyUsed: false);

        expect(result.response.kind, SyncResponseKind.redirectRefused);
        expect(requests, hasLength(1));
      },
    );

    test(
      'refuses an untrusted certificate before sending authorization',
      () async {
        final context = SecurityContext()
          ..useCertificateChain('test/sync/fixtures/untrusted_sync_cert.pem')
          ..usePrivateKey('test/sync/fixtures/untrusted_sync_key.pem');
        var requests = 0;
        final server = await HttpServer.bindSecure('localhost', 0, context);
        final subscription = server.listen((request) {
          requests++;
          request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });

        final client = SyncHttpClient(
          endpoint: Uri.parse('https://localhost:${server.port}/'),
          syncId: 'one-two-three-four',
        );
        addTearDown(client.close);

        expect(
          () => client.request('GET', 'store'),
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

    test('aborts an oversized gzip response while inflating', () async {
      final compressed = gzip.encode(List<int>.filled(1000, 0x61));
      final mock = MockClient(
        (_) async => http.Response.bytes(
          compressed,
          HttpStatus.ok,
          headers: {'content-encoding': 'gzip'},
        ),
      );
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://localhost/'),
        syncId: 'one-two-three-four',
        client: mock,
        maxResponseBytes: 100,
      );
      addTearDown(client.close);

      expect(
        () => client.request('GET', 'store'),
        throwsA(isA<SyncEndpointException>()),
      );
    });
  });

  group('SyncHttpClient outcomes', () {
    test(
      'distinguishes first-time and previously used missing stores',
      () async {
        final methods = <String>[];
        final client = SyncHttpClient(
          endpoint: Uri.parse('http://localhost/'),
          syncId: 'one-two-three-four',
          client: MockClient((request) async {
            methods.add(request.method);
            return http.Response('', HttpStatus.notFound);
          }),
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
      final responses = <http.Response>[
        http.Response('', HttpStatus.conflict),
        http.Response('', HttpStatus.unprocessableEntity),
        http.Response(
          '',
          HttpStatus.tooManyRequests,
          headers: {'retry-after': '7'},
        ),
      ];
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://localhost/'),
        syncId: 'one-two-three-four',
        client: MockClient((_) async => responses.removeAt(0)),
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
    });

    test('sends ETags and blob content types on the correct paths', () async {
      late http.BaseRequest received;
      final client = SyncHttpClient(
        endpoint: Uri.parse('http://localhost/'),
        syncId: 'one-two-three-four',
        client: MockClient((request) async {
          received = request;
          return http.Response('', HttpStatus.notModified);
        }),
      );
      addTearDown(client.close);

      final response = await client.getManifest('device/id', etag: '"hash"');

      expect(response.kind, SyncResponseKind.notModified);
      expect(received.url.path, '/v1/manifests/device%2Fid');
      expect(received.headers['if-none-match'], '"hash"');
      expect(
        received.headers['authorization'],
        'Bearer ${encodeSyncCredential('one-two-three-four')}',
      );
    });
  });
}
