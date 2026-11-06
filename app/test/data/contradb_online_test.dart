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
          'choreographer_name': 'Adina Gordon',
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
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Adina Gordon</a></strong></p>
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

  group('a full page sets mayHaveMore on every row', () {
    String page(Iterable<int> ids) => jsonEncode({
      'numberMatching': ids.length,
      'dances': [
        for (final id in ids)
          {
            'id': id,
            'title': 'Dance $id',
            'choreographer_name': '',
            'formation': 'improper',
          },
      ],
    });

    Future<List<OnlineSearchResultRow>> run(
      OnlineSearchQuery query,
      Future<String> Function(ContraDbSearchRequest) fetch,
    ) => ContraDbOnline(searchFetcher: fetch).search(query);

    test('exactly a page: yes; one short of a page: no', () async {
      final full = await run(
        const OnlineSearchQuery(title: 'x'),
        (_) async => page(List.generate(contraDbSearchCount, (i) => i + 1)),
      );
      expect(full, hasLength(contraDbSearchCount));
      expect(full.every((row) => row.mayHaveMore), isTrue);

      final short = await run(
        const OnlineSearchQuery(title: 'x'),
        (_) async => page(List.generate(contraDbSearchCount - 1, (i) => i + 1)),
      );
      expect(short.every((row) => row.mayHaveMore), isFalse);
    });

    test('two short spellings that merge past a page: no', () async {
      // 12 + 12 distinct rows is 24 >= 20, but neither response was full.
      final rows = await run(
        const OnlineSearchQuery(title: "Mary's"),
        (request) async => request.query.contains('\u2019')
            ? page(List.generate(12, (i) => 100 + i))
            : page(List.generate(12, (i) => i + 1)),
      );
      expect(rows, hasLength(24));
      expect(rows.any((row) => row.mayHaveMore), isFalse);
    });

    test(
      'one spelling filled its page, the other did not: yes, for all',
      () async {
        final rows = await run(
          const OnlineSearchQuery(title: "Mary's"),
          (request) async => request.query.contains('\u2019')
              ? page([500])
              : page(List.generate(contraDbSearchCount, (i) => i + 1)),
        );
        expect(rows.every((row) => row.mayHaveMore), isTrue);
      },
    );

    test('a source that is not paged never sets it', () {
      const row = OnlineSearchResultRow(
        source: OnlineSource.callersBox,
        id: '1',
        name: 'x',
        author: '',
        formation: '',
      );
      expect(row.mayHaveMore, isFalse);
    });
  });

  group("a ContraDB response's numberMatching becomes totalMatching", () {
    String page(int shown, {Object? total}) => jsonEncode({
      'numberMatching': ?total,
      'dances': [
        for (var id = 1; id <= shown; id++)
          {
            'id': id,
            'title': 'Dance $id',
            'choreographer_name': '',
            'formation': 'improper',
          },
      ],
    });

    test('a single response: the total is on every row', () async {
      final rows = await ContraDbOnline(
        searchFetcher: (_) async => page(contraDbSearchCount, total: 143),
      ).search(const OnlineSearchQuery(title: 'x'));
      expect(rows, hasLength(contraDbSearchCount));
      expect(rows.every((row) => row.totalMatching == 143), isTrue);
    });

    test('no numberMatching, or a malformed one: no total', () async {
      for (final total in <Object?>[null, -1, 'many', 2.5]) {
        final rows = await ContraDbOnline(
          searchFetcher: (_) async => page(3, total: total),
        ).search(const OnlineSearchQuery(title: 'x'));
        expect(rows, hasLength(3), reason: '$total');
        expect(
          rows.every((row) => row.totalMatching == null),
          isTrue,
          reason: '$total',
        );
      }
    });

    test('two spellings merged: no total, since the counts overlap', () async {
      final rows = await ContraDbOnline(
        searchFetcher: (request) async => request.query.contains('\u2019')
            ? page(2, total: 2)
            : page(2, total: 2),
      ).search(const OnlineSearchQuery(title: "Mary's"));
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row.totalMatching == null), isTrue);
    });

    test(
      'a spelling that failed leaves one response: its total stands',
      () async {
        final rows = await ContraDbOnline(
          searchFetcher: (request) async {
            if (request.query.contains('\u2019')) throw Exception('down');
            return page(4, total: 9);
          },
        ).search(const OnlineSearchQuery(title: "Mary's"));
        expect(rows, hasLength(4));
        expect(rows.every((row) => row.totalMatching == 9), isTrue);
      },
    );
  });

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

    test(
      'POSTs a choreographer-filter JSON body for author searches',
      () async {
        late http.Request captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response(_searchJson(), 200);
        });
        await fetchContraDbSearch(
          'Alice Gordon',
          filter: 'choreographer',
          client: client,
        );

        expect(jsonDecode(captured.body)['filter'], [
          'choreographer',
          'Alice Gordon',
        ]);
      },
    );

    test('POSTs a figure-filter JSON body for Figure searches', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_searchJson(), 200);
      });
      await fetchContraDbSearch(
        'box circulate',
        filter: 'figure',
        client: client,
      );

      expect(jsonDecode(captured.body)['filter'], ['figure', 'box circulate']);
    });

    test('rejects an unsupported filter before making a request', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response(_searchJson(), 200);
      });

      await expectLater(
        fetchContraDbSearch('Alice', filter: 'unsupported', client: client),
        throwsA(isA<ArgumentError>()),
      );
      expect(called, isFalse);
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
  });

  group('ContraDbOnline.search', () {
    test('fetches and parses the JSON results', () async {
      final requests = <ContraDbSearchRequest>[];
      final online = ContraDbOnline(
        searchFetcher: (request) async {
          requests.add(request);
          return _searchJson();
        },
      );
      final results = await online.search(
        const OnlineSearchQuery(title: 'rendezvous'),
      );
      expect(requests.map((r) => r.query), ['rendezvous']);
      expect(results, hasLength(1));
      expect(results.single.source, OnlineSource.contraDb);
      expect(results.single.id, '1');
      expect(results.single.name, 'The Rendezvous');
      expect(results.single.author, 'Adina Gordon');
      expect(results.single.formation, 'improper');
    });

    test('searches an apostrophe in both spellings and merges by id', () async {
      // ContraDB stores both `'` and `’` and matches punctuation exactly.
      final byQuery = {
        "anna's": _searchJson(id: '7', title: "Anna's Reel"),
        'anna’s': jsonEncode({
          'numberSearched': 2415,
          'numberMatching': 2,
          'dances': [
            {'id': 3, 'title': 'Anna’s Ramble'},
            {'id': 7, 'title': "Anna's Reel"},
          ],
        }),
      };
      final requests = <ContraDbSearchRequest>[];
      final online = ContraDbOnline(
        searchFetcher: (request) async {
          requests.add(request);
          return byQuery[request.query]!;
        },
      );
      final results = await online.search(
        const OnlineSearchQuery(title: 'anna’s'),
      );
      expect(requests.map((r) => r.query), ["anna's", 'anna’s']);
      expect(requests.map((r) => r.filter).toSet(), {'title'});
      expect(results.map((r) => r.id), ['3', '7']);
    });

    test('a failed curly request alone keeps the ASCII results', () async {
      final online = ContraDbOnline(
        searchFetcher: (request) async {
          if (request.query.contains('’')) {
            throw const UrlFetchException(
              UrlFetchFailureReason.contraDbHttpStatus,
              statusCode: 500,
            );
          }
          return _searchJson(id: '7', title: "Anna's Reel");
        },
      );
      final results = await online.search(
        const OnlineSearchQuery(title: "anna's"),
      );
      expect(results.map((r) => r.id), ['7']);
    });

    test('a failed ASCII request still fails the search', () async {
      final online = ContraDbOnline(
        searchFetcher: (request) async {
          if (!request.query.contains('’')) {
            throw const UrlFetchException(
              UrlFetchFailureReason.contraDbUnreachable,
            );
          }
          return _searchJson(id: '3', title: 'Anna’s Ramble');
        },
      );
      expect(
        () => online.search(const OnlineSearchQuery(title: "anna's")),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnreachable,
          ),
        ),
      );
    });

    test('merged rows with the same title are ordered by id', () async {
      // The ASCII row arrives first; only the id tie-break ("10" < "2") puts
      // the curly row ahead of it.
      final online = ContraDbOnline(
        searchFetcher: (request) async => request.query.contains('’')
            ? _searchJson(id: '10', title: 'Anna’s Reel')
            : _searchJson(id: '2', title: "Anna's Reel"),
      );
      final results = await online.search(
        const OnlineSearchQuery(title: "anna's reel"),
      );
      expect(results.map((r) => r.id), ['10', '2']);
    });

    test(
      'passes the selected author filter through the injected seam',
      () async {
        late ContraDbSearchRequest request;
        final online = ContraDbOnline(
          searchFetcher: (value) async {
            request = value;
            return _searchJson();
          },
        );
        await online.search(const OnlineSearchQuery(author: '  Adina Gordon '));
        expect(request.query, 'Adina Gordon');
        expect(request.filter, 'choreographer');
      },
    );

    test(
      'passes the selected Figure filter through the injected seam',
      () async {
        late ContraDbSearchRequest request;
        final online = ContraDbOnline(
          searchFetcher: (value) async {
            request = value;
            return _searchJson();
          },
        );
        await online.search(
          const OnlineSearchQuery(figure: '  Box   Circulate  '),
        );
        expect(request.query, 'box circulate');
        expect(request.filter, 'figure');
      },
    );

    group('Advanced filter', () {
      final petronella = FigureFilter.leaf('petronella');

      Future<List<ContraDbSearchRequest>> run(OnlineSearchQuery query) async {
        final requests = <ContraDbSearchRequest>[];
        final online = ContraDbOnline(
          searchFetcher: (value) async {
            requests.add(value);
            return _searchJson();
          },
        );
        await online.search(query);
        return requests;
      }

      test('alone is sent as the translated expression', () async {
        final requests = await run(OnlineSearchQuery(advanced: petronella));
        expect(requests, hasLength(1));
        expect(requests.single.expression, ['figure', 'petronella']);
      });

      test('with title text is one dance-level and', () async {
        final requests = await run(
          OnlineSearchQuery(title: ' Rendezvous ', advanced: petronella),
        );
        expect(requests.single.expression, [
          'and',
          ['title', 'Rendezvous'],
          ['figure', 'petronella'],
        ]);
      });

      test('with author text uses the choreographer operator', () async {
        final requests = await run(
          OnlineSearchQuery(author: 'Adina Gordon', advanced: petronella),
        );
        expect(requests.single.expression, [
          'and',
          ['choreographer', 'Adina Gordon'],
          ['figure', 'petronella'],
        ]);
      });

      test('with Figure text combines both figures', () async {
        final requests = await run(
          OnlineSearchQuery(figure: 'Box Circulate', advanced: petronella),
        );
        expect(requests.single.expression, [
          'and',
          ['figure', 'box circulate'],
          ['figure', 'petronella'],
        ]);
      });

      test('keeps the apostrophe variants, each combined with it', () async {
        final requests = await run(
          OnlineSearchQuery(title: "anna's", advanced: petronella),
        );
        expect(requests.map((r) => r.expression), [
          [
            'and',
            ['title', "anna's"],
            ['figure', 'petronella'],
          ],
          [
            'and',
            ['title', 'anna’s'],
            ['figure', 'petronella'],
          ],
        ]);
      });

      test(
        'a then is sent as ContraDB then, with the text as an and',
        () async {
          final then = ThenFilter(FigureLeaf('swing'), FigureLeaf('chain'));
          final requests = await run(OnlineSearchQuery(advanced: then));
          expect(requests.single.expression, [
            'then',
            ['figure', 'swing'],
            ['figure', 'chain'],
          ]);
          final withText = await run(
            OnlineSearchQuery(title: 'x', advanced: then),
          );
          expect(withText.single.expression, [
            'and',
            ['title', 'x'],
            [
              'then',
              ['figure', 'swing'],
              ['figure', 'chain'],
            ],
          ]);
        },
      );

      test('a param ContraDB has no counterpart for is left out, applied '
          'for the rest, and flagged on every row', () async {
        final requests = <ContraDbSearchRequest>[];
        final online = ContraDbOnline(
          searchFetcher: (request) async {
            requests.add(request);
            return _searchJson();
          },
        );
        final rows = await online.search(
          OnlineSearchQuery(
            advanced: FigureFilter.leaf(
              'swing',
              params: const {'who': 'partners', 'endFacing': 'out'},
            ),
          ),
        );
        expect(requests.single.expression, ['figure', 'swing', 'partners']);
        expect(rows, isNotEmpty);
        expect(rows.every((row) => row.advancedPartlyApplied), isTrue);
      });

      test('nothing left out: the rows are not flagged', () async {
        final rows =
            await ContraDbOnline(
              searchFetcher: (_) async => _searchJson(),
            ).search(
              OnlineSearchQuery(
                advanced: FigureFilter.leaf(
                  'swing',
                  params: const {'beats': 8},
                ),
              ),
            );
        expect(rows.any((row) => row.advancedPartlyApplied), isFalse);
      });

      test('a text-only query is unchanged: no expression', () async {
        final requests = await run(const OnlineSearchQuery(title: 'x'));
        expect(requests.single.expression, isNull);
        expect(requests.single.filter, 'title');
      });

      test('a condition ContraDB cannot express is refused unsent', () async {
        for (final unsupported in <DanceFilter>[
          const TagFilter('t1'),
          ThenFilter(FigureLeaf('swing', section: 'A1'), FigureLeaf('chain')),
          FigureFilter.leaf('swing', section: 'B1'),
          AndFilter([petronella, const TagFilter('t1')]),
        ]) {
          var called = false;
          final online = ContraDbOnline(
            searchFetcher: (_) async {
              called = true;
              return _searchJson();
            },
          );
          await expectLater(
            online.search(OnlineSearchQuery(title: 'x', advanced: unsupported)),
            throwsA(
              isA<UrlFetchException>().having(
                (error) => error.reason,
                'reason',
                UrlFetchFailureReason.contraDbUnsupportedAdvanced,
              ),
            ),
          );
          expect(called, isFalse);
        }
      });

      test('transport posts the expression as the filter', () async {
        late http.Request captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response(_searchJson(), 200);
        });
        await fetchContraDbSearch(
          '',
          expression: const [
            'no',
            ['figure', 'swing'],
          ],
          client: client,
        );
        expect(jsonDecode(captured.body)['filter'], [
          'no',
          ['figure', 'swing'],
        ]);
      });
    });

    test('rejects an unknown Figure before making a request', () async {
      var called = false;
      final online = ContraDbOnline(
        searchFetcher: (_) async {
          called = true;
          return _searchJson();
        },
      );
      await expectLater(
        online.search(const OnlineSearchQuery(figure: 'box circul')),
        throwsA(
          isA<UrlFetchException>().having(
            (error) => error.reason,
            'reason',
            UrlFetchFailureReason.contraDbUnsupportedFigure,
          ),
        ),
      );
      expect(called, isFalse);
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

    test('rejects a query that supplies both title and author', () async {
      final online = ContraDbOnline(searchFetcher: (_) async => _searchJson());
      expect(
        online.search(
          const OnlineSearchQuery(title: 'Title', author: 'Author'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a query that supplies title and Figure', () async {
      final online = ContraDbOnline(searchFetcher: (_) async => _searchJson());
      expect(
        online.search(const OnlineSearchQuery(title: 'Title', figure: 'swing')),
        throwsArgumentError,
      );
    });

    test('rejects a query that supplies author and Figure', () async {
      final online = ContraDbOnline(searchFetcher: (_) async => _searchJson());
      expect(
        online.search(
          const OnlineSearchQuery(author: 'Author', figure: 'swing'),
        ),
        throwsArgumentError,
      );
    });

    test('propagates a UrlFetchException from the fetch seam', () async {
      final online = ContraDbOnline(
        searchFetcher: (_) async =>
            throw const UrlFetchException(UrlFetchFailureReason.unreachable),
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
      author: 'Adina Gordon',
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

  // Issue #797: symmetrical red-run test for the ContraDB path.
  group('ContraDbOnline.import — confident-match detection (#797)', () {
    final now = DateTime.utc(2024, 1, 1);

    test(
      'confident match + differing figures: nothing written (red-run)',
      () async {
        // RED on origin/main: import() calls DedupeResolution.duplicate() and
        // creates a second dance → hasLength(2). GREEN with fix: import()
        // returns needsConfirmation and writes nothing → hasLength(1).
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-002',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-002',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [
                customFigure('partners balance and swing'),
              ], // different
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '99999',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.95, confident: true),
          ]),
        );

        await ContraDbOnline().import(repos, plan);

        // No second dance should have been written.
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1));
      },
    );

    test(
      'confident match + variation resolution: new dance created, existing unchanged',
      () async {
        // Symmetric variation test for ContraDB: confirms ambiguousResolution
        // plumbing works on both source paths.
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-003',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-003',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [customFigure('partners balance and swing')],
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '99999',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.95, confident: true),
          ]),
        );

        await ContraDbOnline().import(
          repos,
          plan,
          ambiguousResolution: DedupeResolution.variation(
            existing.id,
            linkBack: true,
          ),
        );

        // Two dances: the original and the new variation.
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
        // Existing dance untouched.
        final unchanged = await repos.dances.getById(existing.id);
        expect(unchanged, isNotNull);
      },
    );

    test(
      'confident match + identical figures + different source: returns needsConfirmationIdentical, nothing written (red-run)',
      () async {
        // RED (naive regression): removing the `else if (sources differ)` guard
        // restores the duplicate() fallthrough, creating a second dance →
        // hasLength(2). GREEN: import() returns needsConfirmationIdentical and
        // writes nothing.
        // Existing dance has Caller's Box provenance; incoming plan is ContraDB
        // → sources genuinely differ, so the cross-source dialog fires.
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-id-identical',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
          provenance: Provenance(
            source: ProvenanceSource.callersbox,
            importedAt: now,
          ),
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-identical',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [customFigure('neighbors balance and swing')], // SAME
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '11111',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.97, confident: true),
          ]),
        );

        final result = await ContraDbOnline().import(repos, plan);

        expect(result.kind, OnlineImportKind.needsConfirmationIdentical);
        expect(result.danceId, existing.id);
        // Nothing written — user must confirm before we commit.
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1));
      },
    );

    test(
      'confident match + identical figures + link resolution: updates existing, no second dance',
      () async {
        // User chose "Same dance" in the cross-source duplicate dialog (issue
        // #811). The existing dance is linked to the incoming record; no second
        // dance is created.
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-id-link',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
          provenance: Provenance(
            source: ProvenanceSource.callersbox,
            importedAt: now,
          ),
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-link',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [customFigure('neighbors balance and swing')], // SAME
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '22222',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.97, confident: true),
          ]),
        );

        final result = await ContraDbOnline().import(
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
      'confident match + identical figures + same source: falls through to duplicate (no prompt)',
      () async {
        // A same-source re-import with drifted externalId produces an ambiguous
        // verdict (not reimport) but must NOT trigger the cross-source dialog.
        // Guard: existing.provenance.source == incoming source → falls through.
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-id-same-source',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
          provenance: Provenance(
            source: ProvenanceSource.contradb,
            importedAt: now,
          ),
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-same-source',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [customFigure('neighbors balance and swing')], // SAME
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '99999', // drifted
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.97, confident: true),
          ]),
        );

        final result = await ContraDbOnline().import(repos, plan);

        // Falls through: no prompt, second copy created.
        expect(result.kind, isNot(OnlineImportKind.needsConfirmationIdentical));
        expect(result.kind, isNot(OnlineImportKind.needsConfirmation));
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
      },
    );

    test(
      'confident match + identical figures + null provenance (hand-entered): prompts, writes nothing',
      () async {
        // A hand-entered dance has null provenance. It used to fall through to
        // a silent second copy, because the dialog then said "from a different
        // source". Its wording now names no source, so a hand-entered match
        // asks like any other (INTAKE-5).
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-id-hand-entered',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
          // provenance: null — hand-entered
        );
        await repos.dances.create(existing);

        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-hand-entered',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: [customFigure('neighbors balance and swing')], // SAME
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '77777',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.97, confident: true),
          ]),
        );

        final result = await ContraDbOnline().import(repos, plan);

        expect(result.kind, OnlineImportKind.needsConfirmationIdentical);
        expect(result.danceId, existing.id);
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1), reason: 'nothing written without consent');
      },
    );

    test(
      'an undecodable existing transcription never compares as identical (#1347, ContraDB)',
      () async {
        // The trap this guards: mapping an undecodable side to an empty list
        // made BOTH sides empty when the incoming dance legitimately has no
        // figures, so `figuresCanonicallyIdentical` returned true and the flow
        // skipped confirmation — acting on a comparison that was impossible.
        final repos = openTestRepositories();
        final existing = Dance(
          id: 'existing-id-unreadable',
          title: 'The Rendezvous',
          form: DanceForm.contra,
          formation: const Formation(FormationShape.dupleImproper),
          status: DanceStatus.active,
          figures: [customFigure('neighbors balance and swing')],
          hook: '',
          createdAt: now,
          updatedAt: now,
          provenance: Provenance(
            source: ProvenanceSource.callersbox,
            importedAt: now,
          ),
        );
        await repos.dances.create(existing);
        await repos.db.customStatement(
          'UPDATE dances SET figures_json = ? WHERE id = ?',
          ['[{"kind":', existing.id],
        );

        // Incoming draft carries NO figures, which is what makes the empty-list
        // mapping collide with the undecodable side.
        final plan = ImportRecordPlan(
          draft: StructuredDraft(
            dance: Dance(
              id: 'draft-unreadable',
              title: 'The Rendezvous',
              form: DanceForm.contra,
              formation: const Formation(FormationShape.dupleImproper),
              status: DanceStatus.active,
              figures: const [],
              hook: '',
              createdAt: now,
              updatedAt: now,
            ),
            raw: const RawRecord(
              source: ProvenanceSource.contradb,
              externalId: '99999',
              payload: '{}',
            ),
          ),
          verdict: DedupeVerdict.ambiguous([
            DedupeCandidate(danceId: existing.id, score: 0.95, confident: true),
          ]),
        );
        final result = await ContraDbOnline().import(repos, plan);

        expect(
          result.kind,
          OnlineImportKind.needsConfirmation,
          reason: 'an unreadable side cannot be compared, so the user decides',
        );
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(1), reason: 'nothing written without consent');
      },
    );
  });
}
