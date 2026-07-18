import 'package:compendium_app/src/data/contradb_program_search.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests for [ContraDbProgramSearch] and [filterProgramIndex].
///
/// All I/O is stubbed — either a plain injected [UrlFetcher] closure, or the
/// real hardened [fetchImportUrl] wired to a `package:http` `MockClient` — so no
/// live network is used.
const String _indexHtml = '''
<html><body>
  <a href="/programs">Programs</a>
  <a href="/programs/new">New</a>
  <a href="/programs/33">Harrisburg Contra</a>
  <a href="/programs/671">Pocatello Contra Dance</a>
  <a href="/programs/806">Winter Wonderland</a>
</body></html>
''';

void main() {
  group('filterProgramIndex', () {
    final entries = parseContraDbProgramIndex(_indexHtml);

    test('matches by case-insensitive substring', () {
      final hits = filterProgramIndex(entries, 'CONTRA');
      expect(hits.map((e) => e.id), ['33', '671']);
    });

    test('blank query returns nothing', () {
      expect(filterProgramIndex(entries, ''), isEmpty);
      expect(filterProgramIndex(entries, '   '), isEmpty);
    });

    test('no match returns empty', () {
      expect(filterProgramIndex(entries, 'zzz nonexistent'), isEmpty);
    });
  });

  group('ContraDbProgramSearch', () {
    test('search filters parsed entries from the fetched index', () async {
      final search = ContraDbProgramSearch(fetch: (_) async => _indexHtml);
      final hits = await search.search('winter');
      expect(hits, [
        const ContraDbProgramIndexEntry(id: '806', name: 'Winter Wonderland'),
      ]);
    });

    test('blank query does not fetch and returns empty', () async {
      var calls = 0;
      final search = ContraDbProgramSearch(
        fetch: (_) async {
          calls++;
          return _indexHtml;
        },
      );
      expect(await search.search('  '), isEmpty);
      expect(calls, 0);
      expect(search.isLoaded, isFalse);
    });

    test('fetches once and caches for later searches', () async {
      var calls = 0;
      final search = ContraDbProgramSearch(
        fetch: (url) async {
          calls++;
          expect(url, contraDbProgramIndexUrl);
          return _indexHtml;
        },
      );
      await search.search('contra');
      await search.search('winter');
      expect(calls, 1);
      expect(search.isLoaded, isTrue);
    });

    test('malformed HTML yields empty results, not a crash', () async {
      final search = ContraDbProgramSearch(fetch: (_) async => '<html');
      expect(await search.search('anything'), isEmpty);
      expect(search.isLoaded, isTrue);
    });

    test('a fetch failure surfaces a UrlFetchException', () async {
      final search = ContraDbProgramSearch(
        fetch: (_) async => throw const UrlFetchException('boom'),
      );
      await expectLater(
        search.search('contra'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test(
      'routes through the hardened fetchImportUrl to the canonical URL',
      () async {
        Uri? requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response(_indexHtml, 200);
        });
        final search = ContraDbProgramSearch(
          fetch: (url) => fetchImportUrl(url, client: client),
        );
        final hits = await search.search('pocatello');
        expect(requested.toString(), 'https://contradb.com/programs');
        expect(hits.single.id, '671');
      },
    );
  });
}
