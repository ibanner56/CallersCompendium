import 'dart:typed_data';

import 'package:compendium_app/src/data/import_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isBlockedImportHost', () {
    test('rejects each reserved IPv4 class', () {
      for (final host in [
        '127.0.0.1', // loopback
        '10.0.0.5', // private 10/8
        '172.16.0.1', // private 172.16/12
        '192.168.1.1', // private 192.168/16
        '169.254.169.254', // link-local + cloud metadata
        '100.64.0.1', // CGNAT 100.64/10
        '0.0.0.0', // this-network
        '255.255.255.255', // broadcast
        '224.0.0.1', // multicast
      ]) {
        expect(isBlockedImportHost(host), isTrue, reason: host);
      }
    });

    test('rejects each reserved IPv6 class (incl. IPv4-mapped)', () {
      for (final host in [
        '::1', // loopback
        '::', // unspecified
        'fe80::1', // link-local
        'fc00::1', // unique local
        'ff02::1', // multicast
        '::ffff:127.0.0.1', // IPv4-mapped loopback
        '[::1]', // bracketed literal
      ]) {
        expect(isBlockedImportHost(host), isTrue, reason: host);
      }
    });

    test('rejects localhost and *.local hostnames', () {
      expect(isBlockedImportHost('localhost'), isTrue);
      expect(isBlockedImportHost('LOCALHOST'), isTrue);
      expect(isBlockedImportHost('api.localhost'), isTrue);
      expect(isBlockedImportHost('foo.local'), isTrue);
    });

    test('rejects trailing-dot FQDN forms (no bypass)', () {
      expect(isBlockedImportHost('localhost.'), isTrue);
      expect(isBlockedImportHost('foo.local.'), isTrue);
      expect(isBlockedImportHost('127.0.0.1.'), isTrue);
    });

    test('allows a normal public host and a public IP', () {
      expect(isBlockedImportHost('example.com'), isFalse);
      expect(isBlockedImportHost('www.contradb.com'), isFalse);
      expect(isBlockedImportHost('93.184.216.34'), isFalse);
      expect(isBlockedImportHost('8.8.8.8'), isFalse);
      expect(isBlockedImportHost('::ffff:8.8.8.8'), isFalse);
    });
  });

  group('fetchImportUrl SSRF guard', () {
    test(
      'blocks a cloud-metadata address without calling the client',
      () async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('x', 200);
        });
        await expectLater(
          fetchImportUrl(
            'http://169.254.169.254/latest/meta-data',
            client: client,
          ),
          throwsA(isA<UrlFetchException>()),
        );
        expect(called, isFalse);
      },
    );

    test('does not follow a redirect to a blocked host', () async {
      final requestedHosts = <String>[];
      final client = MockClient((req) async {
        requestedHosts.add(req.url.host);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://169.254.169.254/x'},
        );
      });
      await expectLater(
        fetchImportUrl('https://example.com/start', client: client),
        throwsA(isA<UrlFetchException>()),
      );
      // Only the initial hop was requested; the blocked target never was.
      expect(requestedHosts, ['example.com']);
    });

    test('follows a redirect to a public host and returns its body', () async {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        if (req.url.path == '/start') {
          return http.Response(
            '',
            301,
            headers: {'location': 'https://example.org/final'},
          );
        }
        return http.Response('FINAL BODY', 200);
      });
      final body = await fetchImportUrl(
        'https://example.com/start',
        client: client,
      );
      expect(body, 'FINAL BODY');
      expect(requested, [
        'https://example.com/start',
        'https://example.org/final',
      ]);
    });

    test('does not leak the pasted URL or credentials in error text', () async {
      final client = MockClient((_) async => throw Exception('boom-secret'));
      try {
        await fetchImportUrl(
          'https://secret-host.example.com/path?token=abc123',
          client: client,
        );
        fail('expected a UrlFetchException');
      } on UrlFetchException catch (e) {
        expect(e.message, isNot(contains('secret-host')));
        expect(e.message, isNot(contains('token=abc123')));
        expect(e.message, isNot(contains('boom-secret')));
      }
    });

    test('aborts an over-limit response body', () async {
      final big = Uint8List(importMaxResponseBytes + 1);
      final client = MockClient((_) async => http.Response.bytes(big, 200));
      await expectLater(
        fetchImportUrl('https://example.com/big.json', client: client),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });
  });

  group('fetchCallersBoxSearch SSRF guard', () {
    test('blocks a private-network host without calling the client', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('x', 200);
      });
      await expectLater(
        fetchCallersBoxSearch('http://192.168.1.1/index.php', client: client),
        throwsA(isA<UrlFetchException>()),
      );
      expect(called, isFalse);
    });
  });

  group('buildCallersBoxJsonUrl userinfo hardening', () {
    test('drops embedded credentials but keeps id + format=JSON', () {
      final url = buildCallersBoxJsonUrl(
        'https://user:pass@www.ibiblio.org/contradance/thecallersbox/dance.php?id=5',
      );
      expect(url, isNot(contains('user:pass@')));
      final uri = Uri.parse(url);
      expect(uri.userInfo, isEmpty);
      expect(uri.host, 'www.ibiblio.org');
      expect(uri.queryParameters['id'], '5');
      expect(uri.queryParameters['format'], 'JSON');
    });
  });
}
