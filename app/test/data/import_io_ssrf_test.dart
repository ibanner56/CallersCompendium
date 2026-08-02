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
        // Structurally leak-proof: the exception carries only a typed reason
        // (no prose, no URL/creds). Assert the generic reason and that even the
        // debug form never contains the secret host/token/lower-layer text.
        expect(e.reason, UrlFetchFailureReason.unreachable);
        expect(e.toString(), isNot(contains('secret-host')));
        expect(e.toString(), isNot(contains('token=abc123')));
        expect(e.toString(), isNot(contains('boom-secret')));
      }
    });

    test('aborts an over-limit response body', () async {
      final big = Uint8List(importMaxResponseBytes + 1);
      final client = MockClient((_) async => http.Response.bytes(big, 200));
      await expectLater(
        fetchImportUrl('https://example.com/big.json', client: client),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.responseTooLarge,
          ),
        ),
      );
    });
  });

  group('fetchImportUrl https-only enforcement', () {
    test(
      'rejects a cleartext http:// URL without calling the client',
      () async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('x', 200);
        });
        await expectLater(
          fetchImportUrl('http://example.com/dance.json', client: client),
          throwsA(
            isA<UrlFetchException>().having(
              (e) => e.reason,
              'reason',
              UrlFetchFailureReason.insecureScheme,
            ),
          ),
        );
        expect(called, isFalse);
      },
    );

    test('allows an https:// URL and returns its body', () async {
      final client = MockClient((_) async => http.Response('DANCE JSON', 200));
      final body = await fetchImportUrl(
        'https://example.com/dance.json',
        client: client,
      );
      expect(body, 'DANCE JSON');
    });

    test('refuses an https -> http downgrade in a redirect Location', () async {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        return http.Response(
          '',
          302,
          headers: {'location': 'http://example.org/final'},
        );
      });
      await expectLater(
        fetchImportUrl('https://example.com/start', client: client),
        throwsA(isA<UrlFetchException>()),
      );
      // Only the https origin hop was requested; the cleartext downgrade target
      // (a public host, blocked purely by the https requirement) never was.
      expect(requested, ['https://example.com/start']);
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

  // #743: the source allowlists used to be enforced only where a fetch URL is
  // built, so an allowlisted archive could 302 anywhere on the public internet
  // and have the body parsed as trusted import data. Every hop is now re-checked
  // against the allowlist of the source the fetch started on.
  group('redirect hops stay inside the origin source allowlist', () {
    const callersBoxJson =
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php'
        '?id=1&format=JSON';
    const contraDbDance = 'https://contradb.com/dances/1';

    /// A client that answers the first request with a 302 to [location] and
    /// anything after that with [body], recording every URL it was asked for.
    (http.Client, List<String>) redirectOnceTo(
      String location, {
      String body = 'FINAL BODY',
    }) {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        if (requested.length == 1) {
          return http.Response('', 302, headers: {'location': location});
        }
        return http.Response(body, 200);
      });
      return (client, requested);
    }

    Matcher throwsBlockedHost() => throwsA(
      isA<UrlFetchException>().having(
        (e) => e.reason,
        'reason',
        UrlFetchFailureReason.blockedHost,
      ),
    );

    test("refuses a Caller's Box hop to an off-allowlist host", () async {
      final (client, requested) = redirectOnceTo('https://evil.example.com/x');
      await expectLater(
        fetchImportUrl(callersBoxJson, client: client),
        throwsBlockedHost(),
      );
      // Refused before the request was issued: the attacker host is never
      // contacted, so it learns nothing (not even that the app followed).
      expect(requested, [callersBoxJson]);
    });

    test('refuses a ContraDB hop to an off-allowlist host', () async {
      final (client, requested) = redirectOnceTo('https://evil.example.com/x');
      await expectLater(
        fetchImportUrl(contraDbDance, client: client),
        throwsBlockedHost(),
      );
      expect(requested, [contraDbDance]);
    });

    test('refuses an off-allowlist hop on the search fetcher too', () async {
      // fetchCallersBoxSearch is a second _sendGuarded entry point; the guard
      // lives in the shared transport, so it must cover this path as well.
      final (client, requested) = redirectOnceTo('https://evil.example.com/x');
      await expectLater(
        fetchCallersBoxSearch(
          'https://www.ibiblio.org/contradance/thecallersbox/index.php'
          '?title=test',
          client: client,
        ),
        throwsBlockedHost(),
      );
      expect(requested, hasLength(1));
    });

    test('refuses a cross-source hop (ContraDB into Caller\'s Box)', () async {
      // The pin is per source, not "any allowlisted source": a ContraDB fetch
      // has no business landing on a Caller's Box page.
      final (client, requested) = redirectOnceTo(callersBoxJson);
      await expectLater(
        fetchImportUrl(contraDbDance, client: client),
        throwsBlockedHost(),
      );
      expect(requested, [contraDbDance]);
    });

    test('refuses an ibiblio hop off the /thecallersbox/ path', () async {
      // ibiblio.org hosts many unrelated archives, so host alone never makes a
      // URL "Caller's Box" — the path-segment half of the predicate has to be
      // enforced on hops too, not just on the pasted URL.
      final (client, requested) = redirectOnceTo(
        'https://www.ibiblio.org/contradance/someotherarchive/dance.php?id=1',
      );
      await expectLater(
        fetchImportUrl(callersBoxJson, client: client),
        throwsBlockedHost(),
      );
      expect(requested, [callersBoxJson]);
    });

    test('refusals never echo the refused host or the pasted URL', () async {
      final (client, _) = redirectOnceTo(
        'https://evil.example.com/x?token=abc123',
      );
      try {
        await fetchImportUrl(callersBoxJson, client: client);
        fail('expected a UrlFetchException');
      } on UrlFetchException catch (e) {
        expect(e.reason, UrlFetchFailureReason.blockedHost);
        expect(e.toString(), isNot(contains('evil.example.com')));
        expect(e.toString(), isNot(contains('token=abc123')));
        expect(e.toString(), isNot(contains('ibiblio')));
      }
    });

    test('follows www.contradb.com -> contradb.com (live 301)', () async {
      // Measured against the real site on 2026-08-02: www.contradb.com 301s to
      // contradb.com on /dances, /programs and /api paths. Both hosts are on
      // the ContraDB allowlist, and a pasted URL keeps its own host, so users
      // hit this whenever they paste a www. link. Pinning to host equality
      // instead of to the allowlist would break it.
      final (client, requested) = redirectOnceTo(
        contraDbDance,
        body: '<html>dance</html>',
      );
      expect(
        await fetchImportUrl(
          'https://www.contradb.com/dances/1',
          client: client,
        ),
        '<html>dance</html>',
      );
      expect(requested, ['https://www.contradb.com/dances/1', contraDbDance]);
    });

    test("follows an ibiblio -> thecallersbox.com hop", () async {
      // The other direction of the same rule: cross-host is fine as long as it
      // stays inside the source's allowlist.
      final (client, requested) = redirectOnceTo(
        'https://thecallersbox.com/dance.php?id=1&format=JSON',
        body: '{"dance":1}',
      );
      expect(
        await fetchImportUrl(callersBoxJson, client: client),
        '{"dance":1}',
      );
      expect(requested, hasLength(2));
    });

    test('follows a same-host hop within an allowlisted source', () async {
      final (client, requested) = redirectOnceTo(
        'https://contradb.com/dances/1?canonical=1',
        body: '<html>dance</html>',
      );
      expect(
        await fetchImportUrl(contraDbDance, client: client),
        '<html>dance</html>',
      );
      expect(requested, hasLength(2));
    });

    test('leaves a generic (unpinned) import free to hop hosts', () async {
      // A Caller's Compendium JSON URL is untrusted-by-design and may live
      // anywhere, so it belongs to no source and gets no pin — only the
      // source-neutral https/private-address guards.
      final (client, requested) = redirectOnceTo(
        'https://cdn.example.org/final.json',
        body: '{"dances":[]}',
      );
      expect(
        await fetchImportUrl('https://example.com/export.json', client: client),
        '{"dances":[]}',
      );
      expect(requested, hasLength(2));
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

  group('fetchContraDbSearch response cap', () {
    test('returns the response body on a normal search', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), contraDbSearchUrl);
        return http.Response('[{"id":1}]', 200);
      });
      final body = await fetchContraDbSearch('petronella', client: client);
      expect(body, '[{"id":1}]');
    });

    test('aborts an over-limit response body', () async {
      final big = Uint8List(importMaxResponseBytes + 1);
      final client = MockClient((_) async => http.Response.bytes(big, 200));
      await expectLater(
        fetchContraDbSearch('anything', client: client),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.responseTooLarge,
          ),
        ),
      );
    });

    test('does not leak the underlying error in the failure text', () async {
      final client = MockClient((_) async => throw Exception('boom-secret'));
      try {
        await fetchContraDbSearch('anything', client: client);
        fail('expected a UrlFetchException');
      } on UrlFetchException catch (e) {
        expect(e.reason, UrlFetchFailureReason.contraDbUnreachable);
        expect(e.toString(), isNot(contains('boom-secret')));
      }
    });
  });
}
