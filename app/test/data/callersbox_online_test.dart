import 'dart:convert';

import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_repositories.dart';

/// A minimal Caller's Box per-dance JSON payload (trimmed to the fields
/// [CallersBoxAdapter] reads), used by the load/import policy tests.
String _danceJson({String id = '10600', String name = 'Money Musk'}) =>
    jsonEncode({
      'ID': id,
      'Name': name,
      'Authors': <String>['Traditional'],
      'InterpretedBy': <String>[],
      'Permission': 'full',
      'FormationBase': 'Triple Minor - Proper',
      'FormationDetail': '',
      'Progression': 'Single',
      'PhraseStructure': '',
      'CallingNotes': <String>[],
      'OtherNames': <String>[],
      'Music': <String>[],
      'Tunes': <String>[],
      'Appearances': <Map<String, Object?>>[],
      'phrases': <Map<String, Object?>>[
        {
          'name': 'A1',
          'figures': <String>['Actives balance and swing'],
        },
      ],
    });

/// A trimmed Caller's Box results page with a single result row, modelled on
/// the live HTML structure (bare table, leading icon cells, a `dance.php?id=N`
/// anchor, then author + formation cells).
const String _resultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 1.</p>
<table>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
  <td>Traditional</td>
  <td>Triple Minor - Proper</td>
</tr>
</table>
</body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildCallersBoxSearchUrl', () {
    test('encodes the title and targets the site root', () {
      final url = buildCallersBoxSearchUrl('Money Musk');
      final uri = Uri.parse(url);
      expect(uri.host, 'www.thecallersbox.com');
      expect(uri.path, '/');
      expect(uri.queryParameters['title'], 'Money Musk');
    });

    test('trims surrounding whitespace', () {
      expect(
        Uri.parse(buildCallersBoxSearchUrl('  Petronella ')).queryParameters,
        {'title': 'Petronella'},
      );
    });

    test('an explicit host is honoured (e.g. the ibiblio mirror)', () {
      final uri = Uri.parse(
        buildCallersBoxSearchUrl('x', host: 'www.ibiblio.org'),
      );
      expect(uri.host, 'www.ibiblio.org');
    });

    test('empty title throws a UrlFetchException', () {
      expect(
        () => buildCallersBoxSearchUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('decodeWindows1252', () {
    test('maps the 0x80–0x9F range that differs from latin1', () {
      // 0x92 → right single quote, 0x97 → em dash, 0x85 → ellipsis.
      expect(decodeWindows1252([0x92]), '\u2019');
      expect(decodeWindows1252([0x97]), '\u2014');
      expect(decodeWindows1252([0x85]), '\u2026');
    });

    test('passes ASCII and latin1 bytes through unchanged', () {
      expect(decodeWindows1252(utf8.encode('Money Musk')), 'Money Musk');
      // 0xE9 is é in both latin1 and windows-1252.
      expect(decodeWindows1252([0xE9]), 'é');
    });

    test('undefined windows-1252 slots pass through as the byte value', () {
      expect(decodeWindows1252([0x81]), '\u0081');
    });
  });

  group('fetchCallersBoxSearch', () {
    test('decodes a windows-1252 response body', () async {
      final client = MockClient((_) async {
        // "Money\u2019s" encoded as windows-1252 bytes (0x92 = ').
        final bytes = [...utf8.encode('Money'), 0x92, ...utf8.encode('s')];
        return http.Response.bytes(bytes, 200);
      });
      final body = await fetchCallersBoxSearch(
        'https://www.thecallersbox.com/?title=x',
        client: client,
      );
      expect(body, 'Money\u2019s');
    });

    test('a non-2xx status throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => fetchCallersBoxSearch(
          'https://www.thecallersbox.com/?title=x',
          client: client,
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('an empty body throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
        () => fetchCallersBoxSearch(
          'https://www.thecallersbox.com/?title=x',
          client: client,
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('an invalid URL throws before any request', () async {
      expect(
        () => fetchCallersBoxSearch('not a url'),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  group('CallersBoxOnline.search', () {
    test('fetches and parses the results page', () async {
      final online = CallersBoxOnline(searchFetcher: (_) async => _resultsHtml);
      final results = await online.search('Money Musk');
      expect(results, hasLength(1));
      expect(results.single.id, '10600');
      expect(results.single.name, 'Money Musk');
      expect(results.single.author, 'Traditional');
      expect(results.single.formation, 'Triple Minor - Proper');
    });

    test('propagates a UrlFetchException from the fetch seam', () async {
      final online = CallersBoxOnline(
        searchFetcher: (_) async => throw const UrlFetchException('offline'),
      );
      expect(online.search('x'), throwsA(isA<UrlFetchException>()));
    });
  });

  group('CallersBoxOnline.loadPreview / import', () {
    CallersBoxOnline onlineWithJson(String json) => CallersBoxOnline(
      searchFetcher: (_) async => _resultsHtml,
      jsonFetcher: (_) async => json,
    );

    CallersBoxSearchResult result({String id = '10600'}) =>
        CallersBoxSearchResult(
          id: id,
          name: 'Money Musk',
          author: 'Traditional',
          formation: 'Triple Minor - Proper',
        );

    test(
      'builds a preview with a synthetic Caller\'s Box provenance',
      () async {
        final repos = openTestRepositories();
        final online = onlineWithJson(_danceJson());
        final preview = await online.loadPreview(repos, result());

        expect(preview.detail.dance.title, 'Money Musk');
        expect(
          preview.detail.dance.provenance?.source,
          ProvenanceSource.callersbox,
        );
        expect(preview.detail.dance.provenance?.externalId, '10600');
        expect(preview.plan.verdict.kind, DedupeKind.isNew);
        expect(preview.alreadyInCollection, isFalse);
      },
    );

    test('import creates a brand-new dance', () async {
      final repos = openTestRepositories();
      final online = onlineWithJson(_danceJson());
      final preview = await online.loadPreview(repos, result());

      final imported = await online.import(repos, preview.plan);
      expect(imported.kind, CallersBoxImportKind.created);
      expect(imported.danceId, isNotNull);
      // Single-dance import: the count guards the UI auto-open behavior.
      expect(imported.danceCount, 1);

      final saved = await repos.dances.listAll();
      expect(saved.map((d) => d.title), contains("Money Musk"));
    });

    test('re-importing the same dance reports already-in-collection', () async {
      final repos = openTestRepositories();
      final online = onlineWithJson(_danceJson());

      final first = await online.loadPreview(repos, result());
      await online.import(repos, first.plan);

      // A second plan sees the committed dance → exact reimport verdict.
      final second = await online.loadPreview(repos, result());
      expect(second.plan.verdict.kind, DedupeKind.reimport);
      expect(second.alreadyInCollection, isTrue);

      final imported = await online.import(repos, second.plan);
      expect(imported.kind, CallersBoxImportKind.alreadyInCollection);
      expect(imported.danceCount, 1);

      // No silent duplicate was written.
      final saved = await repos.dances.listAll();
      expect(saved.where((d) => d.title == 'Money Musk'), hasLength(1));
    });
  });

  group('callersBoxImportMessage', () {
    test('created vs already-in-collection wording', () {
      expect(
        callersBoxImportMessage(
          const CallersBoxImportResult(
            kind: CallersBoxImportKind.created,
            title: 'Money Musk',
          ),
        ),
        'Imported "Money Musk".',
      );
      expect(
        callersBoxImportMessage(
          const CallersBoxImportResult(
            kind: CallersBoxImportKind.alreadyInCollection,
            title: 'Money Musk',
          ),
        ),
        '"Money Musk" is already in your collection.',
      );
    });
  });
}
