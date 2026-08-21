import 'dart:convert';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/online_search_labels.dart';
import 'package:compendium_app/src/data/online_title_lookup.dart';
import 'package:compendium_app/src/search/collection_query.dart'
    show ByPhraseSelections;
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';
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

/// A per-dance JSON payload at TCB's `search` permission tier: figures exist in
/// TCB's database and are searchable, but the endpoint serves none of them
/// (`phrases` is empty). Mirrors the live shape of id 5419 ("Cabin Contra"),
/// verified 2026-08-06.
String _searchTierDanceJson({
  String id = '5419',
  String name = 'Cabin Contra',
}) => jsonEncode({
  'ID': id,
  'Name': name,
  'Authors': <String>['Bob Howell'],
  'InterpretedBy': <String>[],
  'Permission': 'search',
  'FormationBase': 'Triple Minor',
  'FormationDetail': '',
  'Progression': 'Single',
  'PhraseStructure': '',
  'CallingNotes': <String>[],
  'OtherNames': <String>[],
  'Music': <String>[],
  'Tunes': <String>[],
  'Appearances': <Map<String, Object?>>[],
  'phrases': <Map<String, Object?>>[],
});

/// Two rows trimmed verbatim from the live `?title=moon` page (2026-08-06): one
/// carrying the Ⓕ figures-permission marker, one carrying only Ⓛ (a link to an
/// external source for the figures — NOT permission to show them). Confirmed
/// against the JSON endpoint: id 12037 is `Permission: full` with four phrases,
/// id 5419 is `Permission: search` with none.
const String _mixedTierResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the db, your query matches 2.</p>
<table>
<tr>
<td><span style='color: green'>&#x24bb;</span></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td></td>
<td><a href='dance.php?id=12037' target='_blank'>After the Honeymoon</a></td>
<td>Luke Donforth</td><td>Duple Minor - Improper</td>
</tr>
<tr>
<td></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td></td>
<td><a href='dance.php?id=5419' target='_blank'>Cabin Contra</a></td>
<td>Bob Howell</td><td>Triple Minor</td>
</tr>
</table>
</body></html>
''';

/// A results page whose every row lacks the Ⓕ marker.
const String _figurelessOnlyResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the db, your query matches 2.</p>
<table>
<tr>
<td></td><td><span style='color: green'>&#x24c1;</span></td><td></td>
<td><a href='dance.php?id=2191' target='_blank'>Circling the Moon</a></td>
<td>Somebody</td><td>Becket</td>
</tr>
<tr>
<td></td><td></td><td><span style='color: green'>&#x24cb;</span></td>
<td><a href='dance.php?id=14094' target='_blank'>Dark Side of the Moon</a></td>
<td>Someone Else</td><td>Becket</td>
</tr>
</table>
</body></html>
''';

/// Two rows sharing one title, only one of which will serve its figures. Drives
/// the `lookupUniqueExactTitle` ambiguity-collapse case.
const String _duplicateTitleResultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<table>
<tr>
<td></td><td><span style='color: green'>&#x24c1;</span></td><td></td>
<td><a href='dance.php?id=5419' target='_blank'>Cabin Contra</a></td>
<td>Bob Howell</td><td>Triple Minor</td>
</tr>
<tr>
<td><span style='color: green'>&#x24bb;</span></td><td></td><td></td>
<td><a href='dance.php?id=9001' target='_blank'>Cabin Contra</a></td>
<td>Someone Else</td><td>Duple Minor - Improper</td>
</tr>
</table>
</body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildCallersBoxSearchUrl', () {
    test('encodes the title and targets the search endpoint', () {
      final url = buildCallersBoxSearchUrl('Money Musk');
      final uri = Uri.parse(url);
      expect(uri.host, 'www.ibiblio.org');
      expect(uri.path, '/contradance/thecallersbox/index.php');
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
      expect(uri.path, '/contradance/thecallersbox/index.php');
    });

    test('empty title throws a UrlFetchException', () {
      expect(
        () => buildCallersBoxSearchUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('an empty title with effective phrases does NOT throw', () {
      final url = buildCallersBoxSearchUrl(
        '   ',
        phrases: const CallersBoxPhraseQuery(
          phrasePos: {
            1: ['swing'],
          },
        ),
      );
      final params = Uri.parse(url).queryParameters;
      expect(params.containsKey('title'), isFalse);
      expect(params['phr1_pos_lines'], 'swing');
    });

    test('empty title and empty phrases throws', () {
      expect(
        () => buildCallersBoxSearchUrl(
          '',
          phrases: const CallersBoxPhraseQuery(),
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('per-phrase figures map onto phr1..phr4 with the right modes', () {
      final url = buildCallersBoxSearchUrl(
        '',
        phrases: const CallersBoxPhraseQuery(
          phrasePos: {
            1: ['swing', 'balance'],
            3: ['allemande'],
          },
          phraseNeg: {
            4: ['petronella'],
          },
        ),
      );
      final params = Uri.parse(url).queryParameters;
      // Positive lines are newline-joined; positive mode = all_any (must contain
      // every figure), negative mode = any_any (exclude if any appears).
      expect(params['phr1_pos_lines'], 'swing\nbalance');
      expect(params['phr1_pos_mode'], 'all_any');
      expect(params['phr3_pos_lines'], 'allemande');
      expect(params['phr3_pos_mode'], 'all_any');
      expect(params['phr4_neg_lines'], 'petronella');
      expect(params['phr4_neg_mode'], 'any_any');
      // No phr2 selections → no phr2 params emitted.
      expect(params.keys.where((k) => k.startsWith('phr2')), isEmpty);
    });

    test('global (any-phrase) figures map onto pos_lines/neg_lines', () {
      final url = buildCallersBoxSearchUrl(
        '',
        phrases: const CallersBoxPhraseQuery(
          globalPos: ['star thru', 'chain'],
          globalNeg: ['hey'],
        ),
      );
      final params = Uri.parse(url).queryParameters;
      expect(params['pos_lines'], 'star thru\nchain');
      expect(params['pos_mode'], 'all_any');
      expect(params['neg_lines'], 'hey');
      expect(params['neg_mode'], 'any_any');
    });

    test('title and phrase criteria combine in one request', () {
      final url = buildCallersBoxSearchUrl(
        'Money Musk',
        phrases: const CallersBoxPhraseQuery(
          phrasePos: {
            2: ['swing'],
          },
        ),
      );
      final params = Uri.parse(url).queryParameters;
      expect(params['title'], 'Money Musk');
      expect(params['phr2_pos_lines'], 'swing');
      expect(params['phr2_pos_mode'], 'all_any');
    });

    test('omits show_all by default and emits it when asked', () {
      // The default request must stay byte-identical to today's: show_all on a
      // broad query is megabytes, and search runs on an as-you-type debounce.
      final plain = Uri.parse(buildCallersBoxSearchUrl('Money Musk'));
      expect(plain.queryParameters.containsKey('show_all'), isFalse);

      final all = Uri.parse(
        buildCallersBoxSearchUrl('Money Musk', showAll: true),
      );
      expect(all.queryParameters.containsKey('show_all'), isTrue);
      expect(all.queryParameters['title'], 'Money Musk');
      // Verified live: TCB treats `show_all=` identically to the bare flag, so
      // this stays inside Uri.https rather than concatenating a query string.
      expect(all.queryParameters['show_all'], '');
    });

    test('show_all combines with by-phrase criteria', () {
      final uri = Uri.parse(
        buildCallersBoxSearchUrl(
          '',
          phrases: const CallersBoxPhraseQuery(globalPos: ['balance']),
          showAll: true,
        ),
      );
      expect(uri.queryParameters['pos_lines'], 'balance');
      expect(uri.queryParameters.containsKey('show_all'), isTrue);
    });
  });

  group('CallersBoxPhraseQuery.fromSelections', () {
    test('standard labels A1/A2/B1/B2 map to phr1..phr4 via display names', () {
      final selections = ByPhraseSelections();
      selections.match['A1'] = ['swing'];
      selections.match['B1'] = ['balance_the_ring'];
      selections.exclude['B2'] = ['allemande'];

      final query = CallersBoxPhraseQuery.fromSelections(
        selections,
        contraTaxonomy,
      );

      expect(query.phrasePos[1], ['swing']);
      // Move id → taxonomy display name ("balance the ring", not the raw id).
      expect(query.phrasePos[3], ['balance the ring']);
      expect(query.phraseNeg[4], ['allemande']);
      expect(query.globalPos, isEmpty);
      expect(query.globalNeg, isEmpty);
      expect(query.isEmpty, isFalse);
    });

    test('non-standard phrase labels fall back to the global fields', () {
      final selections = ByPhraseSelections();
      selections.match['C1'] = ['swing'];
      selections.exclude['C2'] = ['balance'];

      final query = CallersBoxPhraseQuery.fromSelections(
        selections,
        contraTaxonomy,
      );

      expect(query.phrasePos, isEmpty);
      expect(query.phraseNeg, isEmpty);
      expect(query.globalPos, ['swing']);
      expect(query.globalNeg, ['balance']);
    });

    test('an unknown move id falls back to the raw id as its line', () {
      final selections = ByPhraseSelections();
      selections.match['A1'] = ['not_a_real_move'];

      final query = CallersBoxPhraseQuery.fromSelections(
        selections,
        contraTaxonomy,
      );

      expect(query.phrasePos[1], ['not_a_real_move']);
    });

    test('no selected figures yields an empty query', () {
      final selections = ByPhraseSelections();
      selections.match['A1'] = [];

      final query = CallersBoxPhraseQuery.fromSelections(
        selections,
        contraTaxonomy,
      );

      expect(query.isEmpty, isTrue);
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
        'https://www.ibiblio.org/contradance/thecallersbox/index.php?title=x',
        client: client,
      );
      expect(body, 'Money\u2019s');
    });

    test('a non-2xx status throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => fetchCallersBoxSearch(
          'https://www.ibiblio.org/contradance/thecallersbox/index.php?title=x',
          client: client,
        ),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('an empty body throws a UrlFetchException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
        () => fetchCallersBoxSearch(
          'https://www.ibiblio.org/contradance/thecallersbox/index.php?title=x',
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
      final results = await online.search(
        const OnlineSearchQuery(title: 'Money Musk'),
      );
      expect(results, hasLength(1));
      expect(results.single.source, OnlineSource.callersBox);
      expect(results.single.id, '10600');
      expect(results.single.name, 'Money Musk');
      expect(results.single.author, 'Traditional');
      expect(results.single.formation, 'Triple Minor - Proper');
    });

    test('propagates a UrlFetchException from the fetch seam', () async {
      final online = CallersBoxOnline(
        searchFetcher: (_) async =>
            throw const UrlFetchException(UrlFetchFailureReason.unreachable),
      );
      expect(
        online.search(const OnlineSearchQuery(title: 'x')),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });

  // Issue #845. TCB serves figures only for `Permission: full` dances; the rest
  // import as metadata-only stubs, which is almost never what a dance search
  // was for. The results page marks the tier per row with Ⓕ (U+24BB), so the
  // rows that would yield a stub are excluded before the user ever sees them.
  //
  // These drive the real `CallersBoxOnline.search` path end to end (fetch seam
  // → parser → row mapping → filter), not the parse helper on its own.
  group('CallersBoxOnline.search — permission-tier filtering (#845)', () {
    test('rows without the figures marker are excluded from results', () async {
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _mixedTierResultsHtml,
      );
      final results = await online.search(
        const OnlineSearchQuery(title: 'moon'),
      );

      // Unconditional on both sides: what survives AND what does not.
      expect(results.map((r) => r.id), ['12037']);
      expect(results.map((r) => r.name), ['After the Honeymoon']);
      expect(results.every((r) => r.figuresAvailable), isTrue);
    });

    test(
      'an all-figureless page yields no results rather than stubs',
      () async {
        final online = CallersBoxOnline(
          searchFetcher: (_) async => _figurelessOnlyResultsHtml,
        );
        expect(
          await online.search(const OnlineSearchQuery(title: 'moon')),
          isEmpty,
        );
      },
    );

    test('a surviving row still carries every display field', () async {
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _mixedTierResultsHtml,
      );
      final r = (await online.search(
        const OnlineSearchQuery(title: 'moon'),
      )).single;
      expect(r.source, OnlineSource.callersBox);
      expect(r.author, 'Luke Donforth');
      expect(r.formation, 'Duple Minor - Improper');
      expect(r.figuresAvailable, isTrue);
    });

    test('a search-tier row survives when requireFigures is false', () async {
      // The opt-out must reach the row mapping, not just the lookup helper.
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _mixedTierResultsHtml,
      );
      final results = await online.search(
        const OnlineSearchQuery(title: 'moon', requireFigures: false),
      );
      expect(results.map((r) => r.id), ['12037', '5419']);
      // The flag is still reported truthfully; only the filtering changed.
      expect(results.map((r) => r.figuresAvailable), [true, false]);
    });

    test(
      'a search-tier dance imported by DIRECT URL still yields its stub',
      () async {
        // The filter is a SEARCH policy, not an import one. Pasting a TCB link
        // for a `search`-tier dance must still import the metadata-only stub
        // with its existing `callersbox_search_tier` warning — otherwise the
        // filter has leaked into the adapter. Drives the real loadPreview path
        // (UrlFetcher seam → ImportPipeline → CallersBoxAdapter).
        final repos = openTestRepositories();
        final online = CallersBoxOnline(
          searchFetcher: (_) async => _resultsHtml,
          jsonFetcher: (_) async => _searchTierDanceJson(),
        );
        final preview = await online.loadPreview(
          repos,
          const OnlineSearchResultRow(
            source: OnlineSource.callersBox,
            id: '5419',
            name: 'Cabin Contra',
            author: 'Bob Howell',
            formation: 'Triple Minor',
            figuresAvailable: false,
          ),
        );

        expect(preview.detail.dance.title, 'Cabin Contra');
        expect(preview.detail.dance.figures, isEmpty);
        expect(
          preview.plan.draft.issues.map((i) => i.code),
          contains('callersbox_search_tier'),
        );

        final imported = await online.import(repos, preview.plan);
        expect(imported.kind, OnlineImportKind.created);
        final saved = await repos.dances.listAll();
        expect(saved.map((d) => d.title), contains('Cabin Contra'));
      },
    );
  });

  // Issue #845, second-order effect. `CallersBoxOnline.search` is also consumed
  // by `lookupUniqueExactTitle`, which the program-paste resolver drives
  // UNATTENDED (it commits without a user present). Filtering therefore changes
  // that path too, and the change is asserted here rather than left to be
  // discovered: two same-title rows where one is figureless collapse from
  // `multipleExactMatches` (an unresolvable no-op) into a single confident hit.
  group('lookupUniqueExactTitle under permission-tier filtering (#845)', () {
    test(
      'a duplicate title resolves once its figureless twin is gone',
      () async {
        final online = CallersBoxOnline(
          searchFetcher: (_) async => _duplicateTitleResultsHtml,
        );
        final outcome = await lookupUniqueExactTitle(
          'Cabin Contra',
          service: online,
        );
        expect(outcome, isA<OnlineTitleHit>());
        expect((outcome as OnlineTitleHit).row.id, '9001');
      },
    );

    test('requireFigures: false keeps the pre-#845 ambiguity', () async {
      // The opt-out the unattended program resolver uses. Same two rows, same
      // real search path; only the policy differs, so this isolates it.
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _duplicateTitleResultsHtml,
      );
      final outcome = await lookupUniqueExactTitle(
        'Cabin Contra',
        service: online,
        requireFigures: false,
      );
      expect(outcome, isA<OnlineTitleMiss>());
      expect(
        (outcome as OnlineTitleMiss).failure,
        OnlineTitleLookupFailure.multipleExactMatches,
      );
    });

    test('a title whose only match is figureless misses instead of '
        'resolving to a stub', () async {
      final online = CallersBoxOnline(
        searchFetcher: (_) async => _figurelessOnlyResultsHtml,
      );
      final outcome = await lookupUniqueExactTitle(
        'Circling the Moon',
        service: online,
      );
      expect(outcome, isA<OnlineTitleMiss>());
      expect(
        (outcome as OnlineTitleMiss).failure,
        OnlineTitleLookupFailure.noResults,
      );
    });
  });

  // Issue #845, pagination half. TCB caps a normal response at 50 rows, so
  // filtering that page would compound the cap: the user would lose matches
  // twice over and learn about neither. `show_all` lifts the cap, but broad
  // queries are enormous (measured live: `?title=a` states 12,805 matches,
  // ~3.0 MB) and search runs on a 500 ms as-you-type debounce — so the second
  // request is issued only when the page's own stated total says it is cheap.
  group('CallersBoxOnline.search — two-phase show_all (#845)', () {
    /// Builds a results page stating [total] matches and containing [rows]
    /// result rows, every one of which carries the figures marker.
    String page({required int total, required int rows}) {
      final trs = [
        for (var i = 0; i < rows; i++)
          "<tr><td>\u24bb</td><td></td><td></td>"
              "<td><a href='dance.php?id=${1000 + i}'>Dance $i</a></td>"
              '<td>Auth</td><td>Form</td></tr>',
      ].join();
      return '<html><body>'
          '<p>Of 16874 dances in the db, your query matches $total.</p>'
          '<table>$trs</table></body></html>';
    }

    /// Records every URL the fetch seam is asked for, so the number of requests
    /// and their exact shape are both assertable.
    ({CallersBoxOnline online, List<String> urls}) recording(
      String Function(String url) respond,
    ) {
      final urls = <String>[];
      return (
        online: CallersBoxOnline(
          searchFetcher: (url) async {
            urls.add(url);
            return respond(url);
          },
        ),
        urls: urls,
      );
    }

    test(
      'a capped page under the limit is re-requested with show_all',
      () async {
        final r = recording(
          (url) => url.contains('show_all')
              ? page(total: 68, rows: 68)
              : page(total: 68, rows: 50),
        );
        final results = await r.online.search(
          const OnlineSearchQuery(title: 'moon'),
        );

        expect(r.urls, hasLength(2));
        expect(r.urls.first, isNot(contains('show_all')));
        expect(r.urls.last, contains('show_all'));
        // The full set is what gets filtered, not the capped page.
        expect(results, hasLength(68));
      },
    );

    test('a total above the limit is NOT re-requested', () async {
      // The guard that stops a one-character query pulling megabytes on every
      // debounce tick. Without it this issues a second, enormous request.
      final r = recording((_) => page(total: 12805, rows: 50));
      final results = await r.online.search(
        const OnlineSearchQuery(title: 'a'),
      );

      expect(r.urls, hasLength(1));
      expect(r.urls.single, isNot(contains('show_all')));
      expect(results, hasLength(50));
    });

    test('a complete first page is not re-requested', () async {
      // Everything already fits, so a second request would buy nothing. This is
      // the common narrow search and must stay exactly as cheap as it is today.
      final r = recording((_) => page(total: 9, rows: 9));
      await r.online.search(const OnlineSearchQuery(title: 'Money Musk'));

      expect(r.urls, hasLength(1));
      expect(r.urls.single, isNot(contains('show_all')));
    });

    test('a page with no readable total is not re-requested', () async {
      // Fails toward the cheap path: an unreadable count must never be treated
      // as a licence to fetch the whole corpus.
      final r = recording(
        (_) =>
            "<html><body><table><tr><td>\u24bb</td>"
            "<td><a href='dance.php?id=1'>D</a></td>"
            '<td>A</td><td>F</td></tr></table></body></html>',
      );
      final results = await r.online.search(
        const OnlineSearchQuery(title: 'moon'),
      );

      expect(r.urls, hasLength(1));
      expect(results, hasLength(1));
    });

    test('an oversized total is not re-requested', () async {
      // The count parser rejects >7 digits, so this reaches search as null and
      // must take the same cheap path. Catches an unguarded int.parse.
      final r = recording(
        (_) =>
            '<html><body>'
            '<p>Of 16874 dances in the db, your query matches 999999999.</p>'
            "<table><tr><td>\u24bb</td>"
            "<td><a href='dance.php?id=1'>D</a></td>"
            '<td>A</td><td>F</td></tr></table></body></html>',
      );
      await r.online.search(const OnlineSearchQuery(title: 'moon'));

      expect(r.urls, hasLength(1));
    });

    test('the show_all request differs ONLY by show_all', () async {
      // Both phases must stay inside the existing guarded fetch path, and the
      // re-request must carry every original criterion. Dropping `phrases` when
      // rebuilding the URL is the dangerous mutation: a by-phrase search would
      // silently re-request with no figure criteria at all and return an
      // unrelated slice of the corpus, which no count or row assertion catches.
      final r = recording(
        (url) => url.contains('show_all')
            ? page(total: 68, rows: 68)
            : page(total: 68, rows: 50),
      );
      await r.online.search(
        const OnlineSearchQuery(
          title: 'moon',
          phrases: CallersBoxPhraseQuery(
            globalPos: ['balance'],
            globalNeg: ['hey'],
          ),
        ),
      );

      expect(r.urls, hasLength(2));
      final first = Uri.parse(r.urls.first);
      final second = Uri.parse(r.urls.last);

      expect(second.scheme, 'https');
      expect(second.host, callersBoxHost);
      expect(second.path, startsWith(callersBoxPathPrefix));
      expect(second.queryParameters['show_all'], '');

      final rebuilt = Map<String, String>.from(second.queryParameters)
        ..remove('show_all');
      expect(rebuilt, first.queryParameters);
      // Named explicitly so a silently-dropped criterion cannot pass by both
      // maps happening to be empty.
      expect(rebuilt['title'], 'moon');
      expect(rebuilt['pos_lines'], 'balance');
      expect(rebuilt['neg_lines'], 'hey');
    });

    test('filtering applies to the re-requested full set', () async {
      // The two halves of #845 have to compose: fetch everything, then hide the
      // figureless rows — not filter the capped page and call it complete.
      String mixed({required int rows}) {
        final trs = [
          for (var i = 0; i < rows; i++)
            "<tr><td>${i.isEven ? '\u24bb' : ''}</td><td></td><td></td>"
                "<td><a href='dance.php?id=${2000 + i}'>Dance $i</a></td>"
                '<td>Auth</td><td>Form</td></tr>',
        ].join();
        return '<html><body>'
            '<p>Of 16874 dances in the db, your query matches 60.</p>'
            '<table>$trs</table></body></html>';
      }

      final r = recording(
        (url) => url.contains('show_all') ? mixed(rows: 60) : mixed(rows: 50),
      );
      final results = await r.online.search(
        const OnlineSearchQuery(title: 'moon'),
      );

      expect(r.urls, hasLength(2));
      // 60 rows, every other one figure-hidden → 30 survive. Filtering the
      // capped 50 would have yielded 25.
      expect(results, hasLength(30));
      expect(results.every((x) => x.figuresAvailable), isTrue);
    });
  });

  group('CallersBoxOnline.loadPreview / import', () {
    CallersBoxOnline onlineWithJson(String json) => CallersBoxOnline(
      searchFetcher: (_) async => _resultsHtml,
      jsonFetcher: (_) async => json,
    );

    OnlineSearchResultRow result({String id = '10600'}) =>
        OnlineSearchResultRow(
          source: OnlineSource.callersBox,
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
      expect(imported.kind, OnlineImportKind.created);
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
      expect(imported.kind, OnlineImportKind.alreadyInCollection);
      expect(imported.danceCount, 1);

      // No silent duplicate was written.
      final saved = await repos.dances.listAll();
      expect(saved.where((d) => d.title == 'Money Musk'), hasLength(1));
    });
  });

  // Issue #797: confident title+author match with differing figures should
  // not silently create a duplicate on the quick-import path.
  group('CallersBoxOnline.import — confident-match detection (#797)', () {
    final now = DateTime.utc(2024, 1, 1);

    /// Create an existing dance in repos with a specific figure and optional
    /// rating. Uses figures whose canonical keys differ from the draft figures
    /// in [_conflictPlan] so the detection block fires.
    Future<Dance> seedDance(
      CompendiumRepositories repos, {
      int? rating,
      ProvenanceSource? provenanceSource,
    }) async {
      final dance = Dance(
        id: 'existing-001',
        title: 'Tangled Yarns',
        form: DanceForm.contra,
        formation: const Formation(FormationShape.dupleImproper),
        status: DanceStatus.active,
        figures: [customFigure('neighbors balance and swing')],
        hook: '',
        rating: rating,
        createdAt: now,
        updatedAt: now,
        provenance: provenanceSource == null
            ? null
            : Provenance(source: provenanceSource, importedAt: now),
      );
      await repos.dances.create(dance);
      return dance;
    }

    /// A plan with an ambiguous+confident verdict pointing at [candidateId],
    /// carrying [figures] as the incoming draft's figure list.
    ImportRecordPlan ambiguousPlan({
      required String candidateId,
      required List<Figure> figures,
    }) {
      final draft = StructuredDraft(
        dance: Dance(
          id: 'draft-001',
          title: 'Tangled Yarns',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: figures,
          hook: '',
          createdAt: now,
          updatedAt: now,
        ),
        raw: const RawRecord(
          source: ProvenanceSource.callersbox,
          externalId: '99999',
          payload: '{}',
        ),
      );
      return ImportRecordPlan(
        draft: draft,
        verdict: DedupeVerdict.ambiguous([
          DedupeCandidate(danceId: candidateId, score: 0.95, confident: true),
        ]),
      );
    }

    test(
      'confident match + differing figures: nothing written (red-run)',
      () async {
        // RED on origin/main: import() calls DedupeResolution.duplicate() and
        // creates a second dance → hasLength(2). GREEN with fix: import()
        // returns needsConfirmation and writes nothing → hasLength(1).
        final repos = openTestRepositories();
        final existing = await seedDance(repos);

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('partners balance and swing')], // different
        );
        await CallersBoxOnline().import(repos, plan);

        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1));
      },
    );

    test(
      'confident match + variation resolution: new dance created, existing unchanged',
      () async {
        // "Import as a variation" is the headline path from #797 — the reporter
        // ended up with two copies because the importer created a duplicate
        // silently. Variation is the opt-in form of that: a second dance is
        // created, but the existing one is left intact (id, tags, rating all
        // preserved). This is the mirror of the link test, which documents the
        // deliberate data-loss; here there is no data-loss on the existing dance.
        final repos = openTestRepositories();
        final existing = await seedDance(repos, rating: 4);

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('partners balance and swing')], // different
        );
        final result = await CallersBoxOnline().import(
          repos,
          plan,
          ambiguousResolution: DedupeResolution.variation(
            existing.id,
            linkBack: true,
          ),
          now: now,
        );

        // A new dance was created (the variation).
        expect(result.kind, OnlineImportKind.created);
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
        // The existing dance is unchanged — id, rating all intact.
        final unchanged = await repos.dances.getById(existing.id);
        expect(unchanged, isNotNull);
        expect(unchanged!.rating, 4); // not overwritten
      },
    );

    test(
      'confident match + link resolution: preserves dance id, overwrites user data',
      () async {
        // Documents the intentional data-loss: link overwrites the existing
        // dance's fields (rating, figures, etc.) with the incoming draft.
        // The dance id is preserved so program-slot calling history still
        // references the same dance (call history is derived, not stored on
        // the dance record).
        final repos = openTestRepositories();
        final existing = await seedDance(repos, rating: 4);

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('partners balance and swing')], // different
        );
        await CallersBoxOnline().import(
          repos,
          plan,
          ambiguousResolution: DedupeResolution.link(existing.id),
          now: now,
        );

        // Dance id is preserved (program slots continue to reference it).
        final updated = await repos.dances.getById(existing.id);
        expect(updated, isNotNull);
        // Rating was overwritten by the incoming draft (which carries none).
        expect(updated!.rating, isNull);
      },
    );

    test(
      'confident match + identical figures + different source: returns needsConfirmationIdentical, nothing written (red-run)',
      () async {
        // RED (naive regression): removing the `else if (sources differ)` guard
        // restores the duplicate() fallthrough, creating a second dance →
        // hasLength(2). GREEN: import() returns needsConfirmationIdentical and
        // writes nothing.
        // Existing dance has ContraDB provenance; incoming plan is Caller's Box
        // → sources genuinely differ, so the cross-source dialog fires.
        final repos = openTestRepositories();
        final existing = await seedDance(
          repos,
          provenanceSource: ProvenanceSource.contradb,
        );

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('neighbors balance and swing')], // SAME
        );
        final result = await CallersBoxOnline().import(repos, plan);

        expect(result.kind, OnlineImportKind.needsConfirmationIdentical);
        expect(result.danceId, existing.id);
        // Nothing written — user must confirm before we commit.
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1));
      },
    );

    test(
      'confident match + identical figures + same source: falls through to duplicate (no prompt)',
      () async {
        // A same-source re-import with a drifted externalId produces an
        // ambiguous verdict (not reimport) but must NOT trigger the
        // cross-source dialog. Guard: existing.provenance.source == incoming
        // source → falls through to DedupeResolution.duplicate().
        final repos = openTestRepositories();
        final existing = await seedDance(
          repos,
          provenanceSource: ProvenanceSource.callersbox,
        );

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('neighbors balance and swing')], // SAME
        );
        final result = await CallersBoxOnline().import(repos, plan);

        // Falls through: no prompt, second copy created.
        expect(result.kind, isNot(OnlineImportKind.needsConfirmationIdentical));
        expect(result.kind, isNot(OnlineImportKind.needsConfirmation));
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
      },
    );

    test(
      'confident match + identical figures + null provenance (hand-entered): falls through to duplicate (no prompt)',
      () async {
        // A hand-entered dance has null provenance. Triggering the cross-source
        // dialog for it would falsely assert "from a different source". Guard:
        // existing.provenance == null → falls through to duplicate().
        final repos = openTestRepositories();
        // seedDance with no provenanceSource → provenance == null
        final existing = await seedDance(repos);

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('neighbors balance and swing')], // SAME
        );
        final result = await CallersBoxOnline().import(repos, plan);

        expect(result.kind, isNot(OnlineImportKind.needsConfirmationIdentical));
        expect(result.kind, isNot(OnlineImportKind.needsConfirmation));
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
      },
    );

    test(
      'confident match + identical figures + link resolution: updates existing, no second dance',
      () async {
        // User chose "Same dance" in the cross-source duplicate dialog (issue
        // #811). The existing dance is linked to the incoming record; no second
        // dance is created.
        final repos = openTestRepositories();
        final existing = await seedDance(
          repos,
          rating: 4,
          provenanceSource: ProvenanceSource.contradb,
        );

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('neighbors balance and swing')], // SAME
        );
        final result = await CallersBoxOnline().import(
          repos,
          plan,
          ambiguousResolution: DedupeResolution.link(existing.id),
          now: now,
        );

        expect(result.kind, OnlineImportKind.created);
        final saved = await repos.dances.listAll();
        // Only the original dance exists — the incoming record updated it.
        expect(saved, hasLength(1));
        // The dance id is preserved (program slots still reference it).
        expect(saved.first.id, existing.id);
      },
    );

    test(
      'confident match but candidate absent from repos: falls through to duplicate (regression)',
      () async {
        // If the candidate dance has been deleted from repos, the detection
        // block is bypassed and the import falls through to duplicate().
        final repos = openTestRepositories();

        final plan = ambiguousPlan(
          candidateId: 'nonexistent-dance-id',
          figures: [customFigure('partners balance and swing')],
        );
        await CallersBoxOnline().import(repos, plan);

        // One new dance created (fell through to duplicate behavior).
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1));
      },
    );
  });

  group('onlineImportMessage', () {
    test('created vs already-in-collection wording', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        onlineImportMessage(
          l10n,
          const OnlineImportResult(
            kind: OnlineImportKind.created,
            title: 'Money Musk',
          ),
        ),
        'Imported "Money Musk".',
      );
      expect(
        onlineImportMessage(
          l10n,
          const OnlineImportResult(
            kind: OnlineImportKind.alreadyInCollection,
            title: 'Money Musk',
          ),
        ),
        '"Money Musk" is already in your collection.',
      );
    });
  });
}
