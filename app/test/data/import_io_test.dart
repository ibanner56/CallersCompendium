import 'package:compendium_app/src/data/import_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCallersBoxJsonUrl', () {
    test('a bare numeric id builds the canonical JSON endpoint', () {
      expect(
        buildCallersBoxJsonUrl('1'),
        'https://www.thecallersbox.com/dance.php?id=1&format=JSON',
      );
      // Surrounding whitespace is tolerated.
      expect(
        buildCallersBoxJsonUrl('  42 '),
        'https://www.thecallersbox.com/dance.php?id=42&format=JSON',
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

    test('a trailing slash, query, and fragment are dropped', () {
      expect(
        buildContraDbUrl('https://contradb.com/dances/7?foo=bar#notes'),
        'https://contradb.com/dances/7',
      );
    });

    test('a pasted URL keeps its own host (self-hosted instance)', () {
      final uri = Uri.parse(buildContraDbUrl('http://localhost:3000/dances/9'));
      expect(uri.host, 'localhost');
      expect(uri.port, 3000);
      expect(uri.path, '/dances/9');
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
  });
}
