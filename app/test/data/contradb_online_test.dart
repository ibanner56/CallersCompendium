import 'dart:convert';

import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_repositories.dart';

/// Tests for the ContraDB online search + direct-import orchestration.
///
/// All I/O is stubbed via the injected seams ([ContraDbSearchFetcher] JSON /
/// [UrlFetcher] HTML), so no live network is used. Fixtures mirror the live
/// ContraDB search JSON and the `contradb.com/dances/N` page HTML.

/// A canned ContraDB search response with a single dance row.
String _searchJson({String id = '1', String title = 'The Rendezvous'}) =>
    jsonEncode({
      'numberSearched': 2324,
      'numberMatching': 1,
      'dances': [
        {
          'id': int.parse(id),
          'title': title,
          'choreographer_id': 4,
          'choreographer_name': 'Dan Pearl',
          'formation': 'improper',
          'hook': '',
          'user_name': 'Someone',
          'publish': 'everywhere',
          'matching_figures_html': '',
        },
      ],
    });

/// A trimmed `contradb.com/dances/N` page, modeled on the confirmed live DOM.
const String _danceHtml = '''
<!DOCTYPE html><html><head><title>x</title></head>
<body class="dances-show-body">
<h1 class="dance-show-title">The Rendezvous</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Dan Pearl</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
<table class="table table-bordered table-condensed contra-table-nonfluid">
  <tr class="a1b1 dance-show-long-figure">
    <td>A1</td><td class=dance-show-beats>16</td>
    <td><div class="show-figure">neighbors balance &amp; swing</div></td>
  </tr>
  <tr class="a1b1 dance-show-long-figure">
    <td>B1</td><td class=dance-show-beats>16</td>
    <td><div class="show-figure">partners balance &amp; <u>swing</u></div></td>
  </tr>
</table>
</body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fetchContraDbSearch', () {
    test('POSTs a title-filter JSON body to the search endpoint', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_searchJson(), 200);
      });
      final body = await fetchContraDbSearch('rendezvous', client: client);

      expect(captured.method, 'POST');
      expect(captured.url.toString(), contraDbSearchUrl);
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(captured.body)['filter'], ['title', 'rendezvous']);
      expect(jsonDecode(body)['numberMatching'], 1);
    });

    test('a non-2xx status throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => fetchContraDbSearch('x', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('an empty body throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
        () => fetchContraDbSearch('x', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects a response that exceeds the size cap', () async {
      final client = MockClient(
        (_) async => http.Response('x' * 4096, 200),
      );
      await expectLater(
        fetchContraDbSearch('x', client: client, maxBytes: 8),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('preserves an exact application/json content type', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_searchJson(), 200);
      });
      await fetchContraDbSearch('rendezvous', client: client);
      expect(captured.headers['Content-Type'], 'application/json');
      expect(jsonDecode(captured.body)['filter'], ['title', 'rendezvous']);
    });
  });

  group('ContraDbOnline.search', () {
    test('fetches and parses the JSON results', () async {
      final online = ContraDbOnline(searchFetcher: (_) async => _searchJson());
      final results = await online.search(
        const OnlineSearchQuery(title: 'rendezvous'),
      );
      expect(results, hasLength(1));
      expect(results.single.source, OnlineSource.contraDb);
      expect(results.single.id, '1');
      expect(results.single.name, 'The Rendezvous');
      expect(results.single.author, 'Dan Pearl');
      expect(results.single.formation, 'improper');
    });

    test('an empty query throws before any fetch', () async {
      var called = false;
      final online = ContraDbOnline(
        searchFetcher: (_) async {
          called = true;
          return '';
        },
      );
      await expectLater(
        online.search(const OnlineSearchQuery(title: '   ')),
        throwsA(isA<UrlFetchException>()),
      );
      expect(called, isFalse);
    });

    test('propagates a UrlFetchException from the fetch seam', () async {
      final online = ContraDbOnline(
        searchFetcher: (_) async => throw const UrlFetchException('offline'),
      );
      expect(
        online.search(const OnlineSearchQuery(title: 'x')),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('ContraDbOnline.loadPreview / import', () {
    ContraDbOnline onlineWithHtml(String html) => ContraDbOnline(
      searchFetcher: (_) async => _searchJson(),
      htmlFetcher: (_) async => html,
    );

    OnlineSearchResultRow result({String id = '1'}) => OnlineSearchResultRow(
      source: OnlineSource.contraDb,
      id: id,
      name: 'The Rendezvous',
      author: 'Dan Pearl',
      formation: 'improper',
    );

    test('builds a preview with a synthetic ContraDB provenance', () async {
      final repos = openTestRepositories();
      final online = onlineWithHtml(_danceHtml);
      final preview = await online.loadPreview(repos, result());

      expect(preview.detail.dance.title, 'The Rendezvous');
      expect(
        preview.detail.dance.provenance?.source,
        ProvenanceSource.contradb,
      );
      expect(preview.detail.dance.provenance?.externalId, '1');
      expect(preview.plan.verdict.kind, DedupeKind.isNew);
      expect(preview.alreadyInCollection, isFalse);
    });

    test('import creates a brand-new dance', () async {
      final repos = openTestRepositories();
      final online = onlineWithHtml(_danceHtml);
      final preview = await online.loadPreview(repos, result());

      final imported = await online.import(repos, preview.plan);
      expect(imported.kind, OnlineImportKind.created);
      expect(imported.danceId, isNotNull);
      expect(imported.danceCount, 1);

      final saved = await repos.dances.listAll();
      expect(saved.map((d) => d.title), contains('The Rendezvous'));
    });

    test('re-importing the same dance reports already-in-collection', () async {
      final repos = openTestRepositories();
      final online = onlineWithHtml(_danceHtml);

      final first = await online.loadPreview(repos, result());
      await online.import(repos, first.plan);

      final second = await online.loadPreview(repos, result());
      expect(second.plan.verdict.kind, DedupeKind.reimport);
      expect(second.alreadyInCollection, isTrue);

      final imported = await online.import(repos, second.plan);
      expect(imported.kind, OnlineImportKind.alreadyInCollection);

      final saved = await repos.dances.listAll();
      expect(saved.where((d) => d.title == 'The Rendezvous'), hasLength(1));
    });
  });
}
