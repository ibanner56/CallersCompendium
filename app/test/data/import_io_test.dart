import 'dart:typed_data';

import 'package:compendium_app/src/data/import_io.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCallersBoxJsonUrl', () {
    test('a bare numeric id builds the canonical JSON endpoint', () {
      expect(
        buildCallersBoxJsonUrl('1'),
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1&format=JSON',
      );
      // Surrounding whitespace is tolerated.
      expect(
        buildCallersBoxJsonUrl('  42 '),
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=42&format=JSON',
      );
    });

    test('a pasted human dance URL gains format=JSON', () {
      final url = buildCallersBoxJsonUrl(
        'https://www.thecallersbox.com/dance.php?id=1',
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters['id'], '1');
      expect(uri.queryParameters['format'], 'JSON');
    });

    test('an already-format=JSON URL is not doubled', () {
      final url = buildCallersBoxJsonUrl(
        'https://www.thecallersbox.com/dance.php?id=1&format=JSON',
      );
      expect('format=JSON'.allMatches(url).length, 1);
      expect(Uri.parse(url).queryParameters['format'], 'JSON');
    });

    test('an existing non-JSON format value is overwritten', () {
      final url = buildCallersBoxJsonUrl(
        'https://www.thecallersbox.com/dance.php?id=1&format=html',
      );
      expect(Uri.parse(url).queryParameters['format'], 'JSON');
      expect(url, isNot(contains('html')));
    });

    test('a pasted URL keeps its own host (e.g. the ibiblio mirror)', () {
      final url = buildCallersBoxJsonUrl(
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=7',
      );
      final uri = Uri.parse(url);
      expect(uri.host, 'www.ibiblio.org');
      expect(uri.queryParameters['id'], '7');
      expect(uri.queryParameters['format'], 'JSON');
    });

    test('empty input throws a UrlFetchException', () {
      expect(
        () => buildCallersBoxJsonUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a URL with no dance id throws a UrlFetchException', () {
      expect(
        () =>
            buildCallersBoxJsonUrl('https://www.thecallersbox.com/dances.php'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a non-http(s) / non-numeric input throws a UrlFetchException', () {
      expect(
        () => buildCallersBoxJsonUrl('ftp://example.com/dance.php?id=1'),
        throwsA(isA<UrlFetchException>()),
      );
      expect(
        () => buildCallersBoxJsonUrl('not a url or id'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a plain thecallersbox.com URL is accepted', () {
      final url = buildCallersBoxJsonUrl(
        'https://thecallersbox.com/dance.php?id=3',
      );
      final uri = Uri.parse(url);
      expect(uri.host, 'thecallersbox.com');
      expect(uri.queryParameters['id'], '3');
      expect(uri.queryParameters['format'], 'JSON');
    });

    test(
      'a bare ibiblio.org URL (no www) under the mirror path is accepted',
      () {
        final url = buildCallersBoxJsonUrl(
          'https://ibiblio.org/contradance/thecallersbox/dance.php?id=9',
        );
        final uri = Uri.parse(url);
        expect(uri.host, 'ibiblio.org');
        expect(uri.queryParameters['id'], '9');
      },
    );

    test(
      'an ibiblio.org URL NOT under the /thecallersbox/ path is rejected',
      () {
        expect(
          () => buildCallersBoxJsonUrl(
            'https://www.ibiblio.org/someotherarchive/dance.php?id=1',
          ),
          throwsA(isA<UrlFetchException>()),
        );
      },
    );

    test('a dot-segment path trick that resolves away from the mirror '
        'directory is rejected, not accepted via substring match', () {
      // `/contradance/thecallersbox/../someotherarchive/...` contains the
      // substring "/thecallersbox/" but normalizes (RFC 3986 dot-segment
      // removal) to `/contradance/someotherarchive/...`, which is NOT the
      // mirror path.
      expect(
        () => buildCallersBoxJsonUrl(
          'https://www.ibiblio.org/contradance/thecallersbox/../someotherarchive/dance.php?id=1',
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.callersBoxUnsupportedHost,
          ),
        ),
      );
    });

    test('an ibiblio.org path that merely contains the mirror substring '
        '(not an exact path segment) is rejected', () {
      expect(
        () => buildCallersBoxJsonUrl(
          'https://www.ibiblio.org/notthecallersboxfeed/dance.php?id=1',
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.callersBoxUnsupportedHost,
          ),
        ),
      );
    });

    test('an http:// (non-https) URL is rejected as an insecure scheme', () {
      expect(
        () => buildCallersBoxJsonUrl(
          'http://www.thecallersbox.com/dance.php?id=1',
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.insecureScheme,
          ),
        ),
      );
    });

    test('a URL whose host is not on the allowlist is rejected', () {
      expect(
        () => buildCallersBoxJsonUrl('https://example.com/dance.php?id=1'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.callersBoxUnsupportedHost,
          ),
        ),
      );
    });

    test(
      'lookalike hosts (suffix/prefix tricks) are rejected, not fetched',
      () {
        for (final host in [
          'thecallersbox.com.evil.com',
          'evilthecallersbox.com',
          'notthecallersbox.com',
          'ibiblio.org.evil.com',
        ]) {
          expect(
            () => buildCallersBoxJsonUrl('https://$host/dance.php?id=1'),
            throwsA(
              isA<UrlFetchException>().having(
                (e) => e.reason,
                'reason',
                UrlFetchFailureReason.callersBoxUnsupportedHost,
              ),
            ),
            reason: 'expected $host to be rejected',
          );
        }
      },
    );

    test('a userinfo ("@") trick does not smuggle an untrusted host past the '
        'allowlist', () {
      // Uri.host resolves to the real authority (evil.com) here, not the
      // string before the "@" — this documents/regression-tests that the
      // allowlist check is applied to the parsed host, not the raw string.
      expect(
        () => buildCallersBoxJsonUrl(
          'https://www.thecallersbox.com@evil.com/dance.php?id=1',
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.callersBoxUnsupportedHost,
          ),
        ),
      );
    });

    test('a malformed URL is rejected cleanly, not thrown as a raw error', () {
      expect(
        () => buildCallersBoxJsonUrl('https://[not-a-valid-host'),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('buildContraDbUrl', () {
    test('a bare numeric id builds the canonical dance page URL', () {
      expect(buildContraDbUrl('1'), 'https://contradb.com/dances/1');
      // Surrounding whitespace is tolerated.
      expect(buildContraDbUrl('  42 '), 'https://contradb.com/dances/42');
    });

    test('a pasted dance URL is canonicalized to /dances/N', () {
      expect(
        buildContraDbUrl('https://contradb.com/dances/1'),
        'https://contradb.com/dances/1',
      );
    });

    test('a bare www.contradb.com URL is accepted', () {
      final url = buildContraDbUrl('https://www.contradb.com/dances/3');
      expect(Uri.parse(url).host, 'www.contradb.com');
      expect(Uri.parse(url).path, '/dances/3');
    });

    test('a trailing slash, query, and fragment are dropped', () {
      expect(
        buildContraDbUrl('https://contradb.com/dances/7?foo=bar#notes'),
        'https://contradb.com/dances/7',
      );
    });

    test('user-info credentials are dropped from the canonical URL', () {
      final url = buildContraDbUrl('https://user:pass@contradb.com/dances/5');
      expect(url, 'https://contradb.com/dances/5');
      expect(Uri.parse(url).userInfo, isEmpty);
    });

    test('empty input throws a UrlFetchException', () {
      expect(() => buildContraDbUrl('   '), throwsA(isA<UrlFetchException>()));
    });

    test('a URL with no dance id throws a UrlFetchException', () {
      expect(
        () => buildContraDbUrl('https://contradb.com/dances'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a non-http(s) / non-numeric input throws a UrlFetchException', () {
      expect(
        () => buildContraDbUrl('ftp://contradb.com/dances/1'),
        throwsA(isA<UrlFetchException>()),
      );
      expect(
        () => buildContraDbUrl('not a url or id'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a bare http:// (non-https) URL is rejected as an insecure scheme, '
        'even on an allowlisted host', () {
      expect(
        () => buildContraDbUrl('http://contradb.com/dances/1'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.insecureScheme,
          ),
        ),
      );
    });

    test('a pasted URL to a non-allowlisted host (self-hosted mirror) is '
        'rejected, not fetched (#667/#621)', () {
      // Self-hosted-ContraDB-mirror support is intentionally dropped: the
      // host must be on the fixed allowlist, so a pasted URL can no longer
      // "keep its own host" the way it could before #667.
      expect(
        () => buildContraDbUrl('https://localhost:3000/dances/9'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
      expect(
        () => buildContraDbUrl('https://my-contradb-mirror.example/dances/9'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
    });

    test(
      'lookalike hosts (suffix/prefix tricks) are rejected, not fetched',
      () {
        for (final host in [
          'contradb.com.evil.com',
          'evilcontradb.com',
          'notcontradb.com',
        ]) {
          expect(
            () => buildContraDbUrl('https://$host/dances/1'),
            throwsA(
              isA<UrlFetchException>().having(
                (e) => e.reason,
                'reason',
                UrlFetchFailureReason.contraDbUnsupportedHost,
              ),
            ),
            reason: 'expected $host to be rejected',
          );
        }
      },
    );

    test('a userinfo ("@") trick does not smuggle an untrusted host past the '
        'allowlist', () {
      // Uri.host resolves to the real authority (evil.com) here, not the
      // string before the "@" — this documents/regression-tests that the
      // allowlist check is applied to the parsed host, not the raw string.
      expect(
        () => buildContraDbUrl('https://contradb.com@evil.com/dances/1'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
    });

    test('a malformed URL is rejected cleanly, not thrown as a raw error', () {
      expect(
        () => buildContraDbUrl('https://[not-a-valid-host'),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('buildContraDbProgramUrl', () {
    test('a bare numeric id builds the canonical program page URL', () {
      expect(buildContraDbProgramUrl('33'), 'https://contradb.com/programs/33');
      // Surrounding whitespace is tolerated.
      expect(
        buildContraDbProgramUrl('  7 '),
        'https://contradb.com/programs/7',
      );
    });

    test('a pasted program URL is canonicalized to /programs/N', () {
      expect(
        buildContraDbProgramUrl('https://contradb.com/programs/12'),
        'https://contradb.com/programs/12',
      );
    });

    test('a bare www.contradb.com URL is accepted', () {
      final url = buildContraDbProgramUrl(
        'https://www.contradb.com/programs/3',
      );
      expect(Uri.parse(url).host, 'www.contradb.com');
      expect(Uri.parse(url).path, '/programs/3');
    });

    test('a trailing slash, query, and fragment are dropped', () {
      expect(
        buildContraDbProgramUrl(
          'https://contradb.com/programs/7?foo=bar#notes',
        ),
        'https://contradb.com/programs/7',
      );
    });

    test('user-info credentials are dropped from the canonical URL', () {
      final url = buildContraDbProgramUrl(
        'https://user:pass@contradb.com/programs/5',
      );
      expect(url, 'https://contradb.com/programs/5');
      expect(Uri.parse(url).userInfo, isEmpty);
    });

    test('empty input throws a UrlFetchException', () {
      expect(
        () => buildContraDbProgramUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a URL with no program id throws a UrlFetchException', () {
      expect(
        () => buildContraDbProgramUrl('https://contradb.com/programs'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a non-http(s) / non-numeric input throws a UrlFetchException', () {
      expect(
        () => buildContraDbProgramUrl('ftp://contradb.com/programs/1'),
        throwsA(isA<UrlFetchException>()),
      );
      expect(
        () => buildContraDbProgramUrl('not a url or id'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('a bare http:// (non-https) URL is rejected as an insecure scheme, '
        'even on an allowlisted host', () {
      expect(
        () => buildContraDbProgramUrl('http://contradb.com/programs/1'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.insecureScheme,
          ),
        ),
      );
    });

    test('a pasted URL to a non-allowlisted host (self-hosted mirror) is '
        'rejected, not fetched (#667/#621)', () {
      expect(
        () => buildContraDbProgramUrl('https://localhost:3000/programs/9'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
      expect(
        () => buildContraDbProgramUrl(
          'https://my-contradb-mirror.example/programs/9',
        ),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
    });

    test(
      'lookalike hosts (suffix/prefix tricks) are rejected, not fetched',
      () {
        for (final host in [
          'contradb.com.evil.com',
          'evilcontradb.com',
          'notcontradb.com',
        ]) {
          expect(
            () => buildContraDbProgramUrl('https://$host/programs/1'),
            throwsA(
              isA<UrlFetchException>().having(
                (e) => e.reason,
                'reason',
                UrlFetchFailureReason.contraDbUnsupportedHost,
              ),
            ),
            reason: 'expected $host to be rejected',
          );
        }
      },
    );

    test('a userinfo ("@") trick does not smuggle an untrusted host past the '
        'allowlist', () {
      expect(
        () =>
            buildContraDbProgramUrl('https://contradb.com@evil.com/programs/1'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedHost,
          ),
        ),
      );
    });

    test('a malformed URL is rejected cleanly, not thrown as a raw error', () {
      expect(
        () => buildContraDbProgramUrl('https://[not-a-valid-host'),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('validateSharedContraDbProgramUrl', () {
    test('accepts an https contradb.com program URL and canonicalizes it', () {
      expect(
        validateSharedContraDbProgramUrl('https://contradb.com/programs/33'),
        'https://contradb.com/programs/33',
      );
      // Surrounding whitespace is tolerated.
      expect(
        validateSharedContraDbProgramUrl('  https://contradb.com/programs/7 '),
        'https://contradb.com/programs/7',
      );
      // A trailing slash is tolerated.
      expect(
        validateSharedContraDbProgramUrl('https://contradb.com/programs/12/'),
        'https://contradb.com/programs/12',
      );
    });

    test('drops query, fragment, and user-info from the canonical URL', () {
      // Build with embedded credentials via Uri so no literal secret sits in
      // the source; the validator must strip them from the canonical result.
      final input = Uri(
        scheme: 'https',
        userInfo: 'alice:hunter2',
        host: 'contradb.com',
        path: '/programs/5',
        query: 'foo=bar',
        fragment: 'notes',
      ).toString();
      final url = validateSharedContraDbProgramUrl(input);
      expect(url, 'https://contradb.com/programs/5');
      expect(Uri.parse(url).userInfo, isEmpty);
    });

    test('host match is case-insensitive', () {
      expect(
        validateSharedContraDbProgramUrl('https://ContraDB.COM/programs/9'),
        'https://contradb.com/programs/9',
      );
    });

    test('rejects a non-https scheme', () {
      for (final input in const [
        'http://contradb.com/programs/1',
        'ftp://contradb.com/programs/1',
        'file:///programs/1',
        'javascript:alert(1)//contradb.com/programs/1',
        'data:text/html,contradb.com/programs/1',
        'content://contradb.com/programs/1',
        'callerscompendium://contradb.com/programs/1',
      ]) {
        expect(
          () => validateSharedContraDbProgramUrl(input),
          throwsA(isA<UrlFetchException>()),
          reason: input,
        );
      }
    });

    test('rejects any host other than contradb.com', () {
      for (final input in const [
        'https://evil.com/programs/1',
        'https://contradb.com.evil.com/programs/1',
        'https://notcontradb.com/programs/1',
        'https://localhost/programs/1',
        'https://169.254.169.254/programs/1',
        'https://contradb.com@evil.com/programs/1',
      ]) {
        expect(
          () => validateSharedContraDbProgramUrl(input),
          throwsA(isA<UrlFetchException>()),
          reason: input,
        );
      }
    });

    test('rejects a non-program path', () {
      for (final input in const [
        'https://contradb.com/dances/1',
        'https://contradb.com/programs',
        'https://contradb.com/programs/',
        'https://contradb.com/programs/abc',
        'https://contradb.com/programs/1/edit',
        'https://contradb.com/',
      ]) {
        expect(
          () => validateSharedContraDbProgramUrl(input),
          throwsA(isA<UrlFetchException>()),
          reason: input,
        );
      }
    });

    test('rejects empty, garbage, and oversized input', () {
      expect(
        () => validateSharedContraDbProgramUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
      expect(
        () => validateSharedContraDbProgramUrl('not a url'),
        throwsA(isA<UrlFetchException>()),
      );
      final oversized =
          'https://contradb.com/programs/1?x=${'a' * kMaxSharedImportUrlLength}';
      expect(
        () => validateSharedContraDbProgramUrl(oversized),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('the rejection message never echoes the shared input', () {
      const secret = 'https://evil.com/programs/1?token=SUPERSECRET';
      try {
        validateSharedContraDbProgramUrl(secret);
        fail('expected a UrlFetchException');
      } on UrlFetchException catch (e) {
        expect(e.reason, UrlFetchFailureReason.contraDbInvalidProgramLink);
        expect(e.toString(), isNot(contains('SUPERSECRET')));
        expect(e.toString(), isNot(contains('evil.com')));
      }
    });
  });

  group('extractSharedContraDbProgramUrl', () {
    // Chrome / Samsung Internet share a bare URL in EXTRA_TEXT (the page title
    // travels separately in EXTRA_SUBJECT).
    test('accepts a bare shared URL (Chrome / Samsung Internet) and '
        'canonicalizes it', () {
      expect(
        extractSharedContraDbProgramUrl('https://contradb.com/programs/33'),
        'https://contradb.com/programs/33',
      );
    });

    // Firefox for Android puts "title\nurl" in EXTRA_TEXT — the URL must be
    // pulled out of the longer payload rather than rejected wholesale.
    test('extracts the URL from a Firefox "title\\nurl" payload', () {
      expect(
        extractSharedContraDbProgramUrl(
          'A Lovely Contra Program\nhttps://contradb.com/programs/42',
        ),
        'https://contradb.com/programs/42',
      );
    });

    test('extracts the URL when the title precedes it on the same line', () {
      expect(
        extractSharedContraDbProgramUrl(
          'Check out https://contradb.com/programs/8 today',
        ),
        'https://contradb.com/programs/8',
      );
    });

    test('runs the full validator on the extracted token '
        '(rejects a non-ContraDB host embedded after a title)', () {
      expect(
        () => extractSharedContraDbProgramUrl(
          'Nice page\nhttps://evil.com/programs/1',
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects a payload with no https URL token (title only)', () {
      expect(
        () => extractSharedContraDbProgramUrl('Just a program title, no link'),
        throwsA(isA<UrlFetchException>()),
      );
      // A bare http:// token is not an https candidate → zero candidates.
      expect(
        () => extractSharedContraDbProgramUrl('http://contradb.com/programs/1'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects an ambiguous payload carrying more than one https URL', () {
      // A second, attacker-controlled URL must not be silently smuggled past a
      // human by hiding it alongside a legitimate-looking one.
      expect(
        () => extractSharedContraDbProgramUrl(
          'https://contradb.com/programs/1 https://evil.com/programs/2',
        ),
        throwsA(isA<UrlFetchException>()),
      );
      expect(
        () => extractSharedContraDbProgramUrl(
          'https://evil.com/x https://contradb.com/programs/1',
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects empty / whitespace / oversized raw payloads', () {
      expect(
        () => extractSharedContraDbProgramUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
      final oversized =
          'title https://contradb.com/programs/1 '
          '${'a' * kMaxSharedImportTextLength}';
      expect(
        () => extractSharedContraDbProgramUrl(oversized),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('the rejection message never echoes the shared payload', () {
      const secret = 'My Page\nhttps://evil.com/programs/1?token=SUPERSECRET';
      try {
        extractSharedContraDbProgramUrl(secret);
        fail('expected a UrlFetchException');
      } on UrlFetchException catch (e) {
        expect(e.reason, UrlFetchFailureReason.contraDbInvalidProgramLink);
        expect(e.toString(), isNot(contains('SUPERSECRET')));
        expect(e.toString(), isNot(contains('evil.com')));
        expect(e.toString(), isNot(contains('My Page')));
      }
    });
  });

  group('defaultImportSources', () {
    test('returns the canonical [GenericJson, CallersBox, ContraDB, CC .USR] '
        'list', () {
      final sources = defaultImportSources();
      expect(sources, hasLength(4));
      expect(sources[0].kind, ImportSourceKind.genericJson);
      expect(sources[1].kind, ImportSourceKind.callersBox);
      expect(sources[2].kind, ImportSourceKind.contraDb);
      expect(sources[3].kind, ImportSourceKind.callersCompanionUsr);
      // Only the URL-backed sources carry a urlBuilder / matchesUrl; the
      // generic-JSON default is file/paste only.
      expect(sources[0].urlBuilder, isNull);
      expect(sources[0].matchesUrl, isNull);
      expect(sources[1].urlBuilder, isNotNull);
      expect(sources[2].urlBuilder, isNotNull);
      // The CC source is the only byte-based source (a binary .USR picker);
      // it has no URL affordances.
      expect(sources[3].bytePicker, isNotNull);
      expect(sources[3].urlBuilder, isNull);
      expect(sources[3].matchesUrl, isNull);
    });
  });

  group('detectSourceForUrl', () {
    final sources = defaultImportSources();
    ImportSource? detect(String input) => detectSourceForUrl(input, sources);

    test('a Caller\'s Box host resolves to The Caller\'s Box', () {
      expect(
        detect('https://www.thecallersbox.com/dance.php?id=1'),
        same(sources[1]),
      );
      // Bare (no www.) host also matches.
      expect(
        detect('http://thecallersbox.com/dance.php?id=7&format=JSON'),
        same(sources[1]),
      );
    });

    test('the ibiblio mirror path resolves to The Caller\'s Box', () {
      expect(
        detect(
          'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1',
        ),
        same(sources[1]),
      );
    });

    test('an ibiblio URL without the mirror path does not match', () {
      expect(detect('https://www.ibiblio.org/something/else'), isNull);
    });

    test('a ContraDB host resolves to ContraDB', () {
      expect(detect('https://contradb.com/dances/42'), same(sources[2]));
      expect(detect('https://www.contradb.com/dances/42'), same(sources[2]));
    });

    test('an unrecognized host returns null (never forces generic)', () {
      expect(detect('https://example.com/dances/1'), isNull);
    });

    test('a bare numeric id returns null (keep current selection)', () {
      expect(detect('1'), isNull);
      expect(detect('  42 '), isNull);
    });

    test('empty / garbage / non-http input returns null', () {
      expect(detect(''), isNull);
      expect(detect('   '), isNull);
      expect(detect('not a url'), isNull);
      expect(detect('ftp://contradb.com/dances/1'), isNull);
    });
  });

  group('import file size cap', () {
    // A picked file is untrusted input (OWASP A04/A05 — uncontrolled resource
    // consumption). The cap is enforced by reading the file as a BOUNDED stream
    // and failing closed the instant more than maxBytes bytes are consumed — we
    // never trust a separate XFile.length() probe (a file can grow or be
    // swapped after it is picked: a TOCTOU window). Tests inject an in-memory
    // XFile / synthetic stream + a small maxBytes (mirroring
    // ArchiveIntakeService's injectable maxBytes) so no real picker plugin runs
    // and no giant allocation is needed.
    XFile fileOf(List<int> bytes) =>
        XFile.fromData(Uint8List.fromList(bytes), name: 'import.bin');

    test('carries the length as a typed field with a debug-only toString', () {
      const e = ImportFileTooLargeException(999999999);
      // The length is kept for diagnostics but is never baked into user prose;
      // toString is a debug-only form and the user-facing message is produced
      // by importFileTooLargeMessage() at the presentation layer.
      expect(e.length, 999999999);
      expect(e.toString(), 'ImportFileTooLargeException(length: 999999999)');
    });

    test(
      'readCappedBytes concatenates chunks up to the inclusive boundary',
      () async {
        Stream<Uint8List> chunks() async* {
          yield Uint8List.fromList([1, 2, 3]);
          yield Uint8List.fromList([4, 5]);
        }

        // 5 bytes total, cap 5 -> accepted (boundary inclusive), reassembled.
        expect(await readCappedBytes(chunks(), maxBytes: 5), [1, 2, 3, 4, 5]);
      },
    );

    test(
      'readCappedBytes rejects a growing stream without draining it',
      () async {
        var emitted = 0;
        // A stream that would yield 4 KiB if fully consumed. The cap must trip
        // during consumption, so we must NOT pull every chunk — proving the
        // read is bounded even against a file that keeps producing bytes
        // (TOCTOU / uncontrolled-resource-consumption guard).
        Stream<Uint8List> chunks() async* {
          for (var i = 0; i < 1000; i++) {
            emitted++;
            yield Uint8List(4);
          }
        }

        await expectLater(
          readCappedBytes(chunks(), maxBytes: 8),
          throwsA(isA<ImportFileTooLargeException>()),
        );
        // Cap 8 B = two 4-byte chunks; the third (total 12 B) trips it, so the
        // stream is abandoned far short of its 1000 chunks.
        expect(emitted, lessThan(10));
      },
    );

    test(
      'readImportBytesCapped returns bytes for a file within the cap',
      () async {
        final bytes = List<int>.generate(16, (i) => i);
        expect(await readImportBytesCapped(fileOf(bytes), maxBytes: 32), bytes);
      },
    );

    test(
      'readImportBytesCapped rejects a file over the cap while reading',
      () async {
        await expectLater(
          readImportBytesCapped(
            fileOf(List<int>.filled(20, 0x41)),
            maxBytes: 8,
          ),
          throwsA(isA<ImportFileTooLargeException>()),
        );
      },
    );

    test(
      'readImportTextCapped returns text for a file within the cap',
      () async {
        expect(
          await readImportTextCapped(fileOf('hello'.codeUnits), maxBytes: 32),
          'hello',
        );
      },
    );

    test(
      'readImportTextCapped rejects a file over the cap while reading',
      () async {
        await expectLater(
          readImportTextCapped(fileOf(List<int>.filled(20, 0x41)), maxBytes: 8),
          throwsA(isA<ImportFileTooLargeException>()),
        );
      },
    );

    test('the default cap is aligned with the 25 MiB archive intake cap', () {
      expect(kMaxImportFileBytes, 25 * 1024 * 1024);
    });

    test(
      'a file exactly at the cap is accepted (boundary is inclusive)',
      () async {
        final bytes = List<int>.filled(8, 0x42);
        expect(await readImportBytesCapped(fileOf(bytes), maxBytes: 8), bytes);
      },
    );
  });

  group('contraDbProgramIdFromInput', () {
    test('extracts a bare numeric id', () {
      expect(contraDbProgramIdFromInput('33'), '33');
      expect(contraDbProgramIdFromInput('  33  '), '33');
    });

    test('extracts the id from a /programs/N URL', () {
      expect(
        contraDbProgramIdFromInput('https://contradb.com/programs/42'),
        '42',
      );
      expect(
        contraDbProgramIdFromInput('http://contradb.com/programs/7?x=1#frag'),
        '7',
      );
    });

    test('returns null for empty or non-program input', () {
      expect(contraDbProgramIdFromInput(''), isNull);
      expect(contraDbProgramIdFromInput('   '), isNull);
      expect(contraDbProgramIdFromInput('not a url'), isNull);
      expect(
        contraDbProgramIdFromInput('https://contradb.com/programs/new'),
        isNull,
      );
    });

    test('rejects an absurdly long run of digits (length cap)', () {
      expect(contraDbProgramIdFromInput('1' * 19), isNull);
      expect(contraDbProgramIdFromInput('1' * 18), '1' * 18);
    });
  });
}
