import 'dart:typed_data';

import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fmp_fixture_builder.dart';
import '../support/test_repositories.dart';

Dance _dance(
  String id,
  String title, {
  List<Figure> figures = const [],
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  provenance: provenance,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Encodes a one-or-more-dance [CompendiumArchive] as the generic-JSON payload
/// the [GenericJsonAdapter] consumes.
String _archivePayload(List<Dance> dances) => encodeArchive(
  CompendiumArchive(exportedAt: DateTime.utc(2026, 7, 15), dances: dances),
);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required String payload,
  SourceAdapter Function()? adapterFactory,
  List<ImportSource>? sources,
  UrlFetcher? fetcher,
  ImportBytePicker? bytePicker,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          sources:
              sources ??
              [
                ImportSource(
                  label: 'test JSON',
                  adapterFactory: adapterFactory ?? GenericJsonAdapter.new,
                ),
              ],
          picker: () async => payload,
          bytePicker: bytePicker,
          fetcher: fetcher,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives input → planning → review: taps "Choose file…" (canned picker) then
/// "Review import".
Future<void> _toReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('import-choose-file')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('import-continue')));
  await tester.pumpAndSettle();
}

/// Types [url] into the URL field and taps "Fetch".
Future<void> _fetch(WidgetTester tester, String url) async {
  await tester.enterText(find.byKey(const ValueKey('import-url-field')), url);
  await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a new-dance row and commits it into the collection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('d1', 'Brand New Reel')]),
    );

    await _toReview(tester);

    expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
    expect(find.text('Brand New Reel'), findsOneWidget);
    // A new dance defaults to import (importable count = 1).
    expect(find.text('1 of 1 will be imported'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-result-dialog')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('import-summary-Created')),
      findsOneWidget,
    );

    final all = await repos.dances.listAll();
    expect(all.map((d) => d.title), contains('Brand New Reel'));
  });

  testWidgets('reimport row updates the matched dance in place', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        'existing',
        'Old Title',
        provenance: Provenance(
          source: ProvenanceSource.json,
          externalId: 'ext1',
          importedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );

    await _pump(
      tester,
      repos,
      payload: _archivePayload([
        _dance(
          'incoming',
          'Refreshed Title',
          provenance: Provenance(
            source: ProvenanceSource.json,
            externalId: 'ext1',
            importedAt: DateTime.utc(2026, 6, 1),
          ),
        ),
      ]),
    );
    await _toReview(tester);

    // The reimport option is offered and selected by default.
    expect(find.byKey(const ValueKey('import-row-0-reimport')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 1);
    expect(all.single.id, 'existing');
    expect(all.single.title, 'Refreshed Title');
  });

  testWidgets('ambiguous row defaults to skip and is not committed silently', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('existing', "Sackett's Harbor"));

    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('incoming', 'Sacketts Harbor')]),
    );
    await _toReview(tester);

    // Ambiguous → link/duplicate/skip offered; skip is the default, so nothing
    // is importable until the user chooses.
    expect(find.byKey(const ValueKey('import-row-0-skip')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('import-row-0-duplicate')),
      findsOneWidget,
    );
    expect(find.textContaining('Link to'), findsOneWidget);
    expect(find.text('0 of 1 will be imported'), findsOneWidget);
    // Commit is disabled while everything is skipped (no misleading control).
    final commit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('import-commit-button')),
    );
    expect(commit.onPressed, isNull);

    // Choosing "duplicate" makes it importable and commits a new dance.
    await tester.tap(find.byKey(const ValueKey('import-row-0-duplicate')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 will be imported'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 2);
  });

  testWidgets('linking an ambiguous row updates the chosen candidate', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('cand', "Sackett's Harbor"));

    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('incoming', 'Sacketts Harbor')]),
    );
    await _toReview(tester);

    await tester.tap(find.byKey(const ValueKey('import-row-0-link-cand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    expect(all.length, 1);
    expect(all.single.id, 'cand');
    expect(all.single.title, 'Sacketts Harbor');
    expect(find.byKey(const ValueKey('import-summary-Linked')), findsOneWidget);
  });

  testWidgets('batch errors are surfaced without blocking the good record', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: 'ignored',
      adapterFactory: () => _PartlyBrokenAdapter(),
    );
    await _toReview(tester);

    // One record read, one couldn't be read.
    expect(find.byKey(const ValueKey('import-batch-errors')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-row-1')), findsNothing);
    expect(find.text('1 of 1 will be imported'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    final all = await repos.dances.listAll();
    expect(all.map((d) => d.title), contains('Good One'));
  });

  testWidgets('undo reverts a committed import', (tester) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      payload: _archivePayload([_dance('d1', 'Undo Me')]),
    );
    await _toReview(tester);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    expect((await repos.dances.listAll()).length, 1);

    await tester.tap(find.byKey(const ValueKey('import-undo-button')));
    await tester.pumpAndSettle();

    expect((await repos.dances.listAll()).isEmpty, isTrue);
    expect(
      find.byKey(const ValueKey('import-undone-snackbar')),
      findsOneWidget,
    );
  });

  testWidgets('a payload with no dances shows an empty state', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, payload: _archivePayload([]));
    await _toReview(tester);
    expect(find.text('No dances found'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-commit-button')), findsNothing);
  });

  testWidgets('an undecodable payload shows an honest error', (tester) async {
    final repos = openTestRepositories();
    await _pump(tester, repos, payload: 'not json at all');
    await _toReview(tester);
    expect(find.text("Couldn't read the import"), findsOneWidget);
  });

  group('end-to-end through the real pipeline', () {
    test('GenericJsonAdapter + ImportPipeline lands multiple dances', () async {
      final repos = openTestRepositories();
      final payload = _archivePayload([
        _dance('a', 'Alpha'),
        _dance('b', 'Beta'),
      ]);

      final pipeline = ImportPipeline(repos.dances, repos.choreographers);
      final batch = await pipeline.plan(
        GenericJsonAdapter(),
        ImportRequest(payload: payload),
      );
      expect(batch.plannedCount, 2);
      expect(batch.hasErrors, isFalse);

      final session = await pipeline.commit(
        batch,
        now: DateTime.utc(2026, 7, 15),
        newId: uuidV4,
      );
      expect(session.committedCount, 2);
      final titles = (await repos.dances.listAll()).map((d) => d.title).toSet();
      expect(titles, containsAll(['Alpha', 'Beta']));
    });
  });

  group('Import from URL', () {
    testWidgets('a fetched archive drives the review queue and commits', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final payload = _archivePayload([_dance('u1', 'Fetched Reel')]);
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => payload,
      );

      await _fetch(tester, 'https://example.com/archive.json');
      // The fetched body populates the payload field.
      expect(find.text(payload), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('Fetched Reel'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-result-dialog')),
        findsOneWidget,
      );
      final all = await repos.dances.listAll();
      expect(all.map((d) => d.title), contains('Fetched Reel'));
    });

    testWidgets('the fetched URL is carried onto ImportRequest.uri', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final adapter = _CapturingAdapter();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        adapterFactory: () => adapter,
        fetcher: (url) async => 'body',
      );

      await _fetch(tester, 'https://example.com/archive.json');
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest?.uri, 'https://example.com/archive.json');
      expect(adapter.lastRequest?.payload, 'body');
    });

    testWidgets('a fetch failure shows the error and does not crash', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => throw const UrlFetchException(
          'The server responded with HTTP 404.',
        ),
      );

      await _fetch(tester, 'https://example.com/missing.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(find.text('The server responded with HTTP 404.'), findsOneWidget);
      // Still on the input phase; nothing crashed and no review list appeared.
      expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty-body failure surfaces its message', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => throw const UrlFetchException(
          'The URL returned an empty response.',
        ),
      );

      await _fetch(tester, 'https://example.com/empty.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(find.text('The URL returned an empty response.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-UrlFetchException is still surfaced without crashing', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        fetcher: (url) async => throw StateError('boom'),
      );

      await _fetch(tester, 'https://example.com/x.json');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group("Caller's Box routing", () {
    // Minimal real-shaped TCB per-dance JSON (id=1, "The Nice Combination").
    const tcbJson =
        '{"ID":1,"Name":"The Nice Combination","Permission":"full"}';

    List<ImportSource> sourcesFor() => [
      ImportSource(label: 'test JSON', adapterFactory: GenericJsonAdapter.new),
      ImportSource(
        label: "The Caller's Box",
        adapterFactory: CallersBoxAdapter.new,
        urlBuilder: buildCallersBoxJsonUrl,
      ),
    ];

    Future<void> selectCallersBox(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("The Caller's Box").last);
      await tester.pumpAndSettle();
    }

    testWidgets('a bare id is resolved to the &format=JSON endpoint and '
        'parsed by CallersBoxAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      await _fetch(tester, '1');

      // The bare id became the canonical TCB JSON endpoint.
      expect(
        fetchedUrl,
        'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1&format=JSON',
      );

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // The dance was parsed by CallersBoxAdapter and reached the review queue.
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('The Nice Combination'), findsOneWidget);
    });

    testWidgets('a pasted dance URL gains format=JSON and is fetched', (
      tester,
    ) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      await _fetch(tester, 'https://www.thecallersbox.com/dance.php?id=1');

      expect(fetchedUrl, contains('id=1'));
      expect(fetchedUrl, contains('format=JSON'));
    });

    testWidgets('a bad Caller\'s Box input shows an inline error, no fetch', (
      tester,
    ) async {
      final repos = openTestRepositories();
      var fetchCalls = 0;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchCalls++;
          return tcbJson;
        },
      );

      await selectCallersBox(tester);
      // A URL with no dance id can't be turned into an endpoint.
      await _fetch(tester, 'https://www.thecallersbox.com/dances.php');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(fetchCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching source clears stale URL provenance', (tester) async {
      final repos = openTestRepositories();
      final adapter = _CapturingAdapter();
      // A generic-JSON source using a provenance-capturing adapter, plus the
      // Caller's Box source. Fetch under Caller's Box, then switch back to
      // generic and plan: the previous fetch URL must NOT be reattached.
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: [
          ImportSource(label: 'test JSON', adapterFactory: () => adapter),
          ImportSource(
            label: "The Caller's Box",
            adapterFactory: CallersBoxAdapter.new,
            urlBuilder: buildCallersBoxJsonUrl,
          ),
        ],
        fetcher: (url) async => 'body',
      );

      await selectCallersBox(tester);
      await _fetch(tester, '1');

      // Switch back to the generic JSON source.
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test JSON').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // Provenance was dropped on the switch, so it plans as a paste.
      expect(adapter.lastRequest?.uri, isNull);
    });
  });

  group('ContraDB routing', () {
    // Minimal real-shaped ContraDB dance page (id=1, "The Rendezvous").
    const contraDbPage =
        '<!DOCTYPE html><html><body class="dances-show-body">'
        '<h1 class="dance-show-title">The Rendezvous</h1>'
        '<p class="dance-show-choreographer">by: '
        '<strong><a href="/choreographers/4">Dan Pearl</a></strong></p>'
        '<p class="dance-show-formation">formation: improper </p>'
        '<table class="contra-table-nonfluid">'
        '<tr><td>A1</td><td class=dance-show-beats>16</td>'
        '<td><div class="show-figure">neighbors balance &amp; swing</div></td>'
        '</tr></table></body></html>';

    List<ImportSource> sourcesFor() => [
      ImportSource(label: 'test JSON', adapterFactory: GenericJsonAdapter.new),
      ImportSource(
        label: 'ContraDB',
        adapterFactory: ContraDbHtmlAdapter.new,
        urlBuilder: buildContraDbUrl,
      ),
    ];

    Future<void> selectContraDb(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ContraDB').last);
      await tester.pumpAndSettle();
    }

    testWidgets('a bare id resolves to the dance page and is scraped by '
        'ContraDbHtmlAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchedUrl = url;
          return contraDbPage;
        },
      );

      await selectContraDb(tester);
      await _fetch(tester, '1');

      // The bare id became the canonical ContraDB dance page URL.
      expect(fetchedUrl, 'https://contradb.com/dances/1');

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();

      // The dance was parsed by ContraDbHtmlAdapter and reached the queue.
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(find.text('The Rendezvous'), findsOneWidget);
    });

    testWidgets('a bad ContraDB input shows an inline error, no fetch', (
      tester,
    ) async {
      final repos = openTestRepositories();
      var fetchCalls = 0;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(),
        fetcher: (url) async {
          fetchCalls++;
          return contraDbPage;
        },
      );

      await selectContraDb(tester);
      // A URL with no dance id can't be turned into a dance page URL.
      await _fetch(tester, 'https://contradb.com/dances');

      expect(find.byKey(const ValueKey('import-url-error')), findsOneWidget);
      expect(fetchCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('URL source auto-detection', () {
    const tcbJson =
        '{"ID":1,"Name":"The Nice Combination","Permission":"full"}';

    ImportSource selectedSource(WidgetTester tester) => tester
        .widget<DropdownButton<ImportSource>>(
          find.byKey(const ValueKey('import-source-select')),
        )
        .value!;

    Future<void> typeUrl(WidgetTester tester, String url) async {
      await tester.enterText(
        find.byKey(const ValueKey('import-url-field')),
        url,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a Caller\'s Box URL flips the selector to The Caller\'s Box '
        'and routes through CallersBoxAdapter', (tester) async {
      final repos = openTestRepositories();
      String? fetchedUrl;
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async {
          fetchedUrl = url;
          return tcbJson;
        },
      );

      // Default selection is the generic-JSON source.
      expect(selectedSource(tester).label, "a Caller's Compendium JSON file");

      await typeUrl(tester, 'https://www.thecallersbox.com/dance.php?id=1');
      // The selector auto-flipped to Caller's Box without the user touching it.
      expect(selectedSource(tester).label, "The Caller's Box");

      await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
      await tester.pumpAndSettle();
      expect(fetchedUrl, contains('format=JSON'));

      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
      // Parsed by CallersBoxAdapter (the auto-detected source).
      expect(find.text('The Nice Combination'), findsOneWidget);
    });

    testWidgets('a ContraDB URL flips the selector to ContraDB', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async => 'unused',
      );

      await typeUrl(tester, 'https://contradb.com/dances/42');
      expect(selectedSource(tester).label, 'ContraDB');
    });

    testWidgets('a manual source choice is respected (no auto-flip after)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: defaultImportSources(),
        fetcher: (url) async => 'unused',
      );

      // User explicitly picks ContraDB…
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ContraDB').last);
      await tester.pumpAndSettle();
      expect(selectedSource(tester).label, 'ContraDB');

      // …then pastes a Caller's Box URL: the manual choice wins, no auto-flip.
      await typeUrl(tester, 'https://www.thecallersbox.com/dance.php?id=1');
      expect(selectedSource(tester).label, 'ContraDB');
    });
  });

  group("Caller's Companion .USR import", () {
    // A minimal but structurally real CC `.USR` byte image: two dances
    // (external ids 4/7 → "Simplicity Swing", "Petronella"), one set whose
    // Location becomes the program title ("Grange Hall"), and a SetItem
    // referencing an absent dance (99) so a program note is produced.
    Uint8List ccUsrBytes() => buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
        rows: [
          MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
          MapEntry(11, {1: '7', 2: 'Petronella', 3: 'Trad'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Set',
        columnNames: [
          'zk_Set_ID',
          'Date',
          'Location',
          'Band',
          'Caller',
          'Notes',
        ],
        rows: [
          MapEntry(20, {
            1: '1',
            2: '3/14/2020',
            3: 'Grange Hall',
            4: 'The Band',
            5: 'Jane',
            6: 'a good night',
          }),
        ],
      ),
      FmpFixtureTable(
        index: 3,
        name: 'SetItem',
        columnNames: [
          'zk_Set_ID',
          'zk_SetItem_ID',
          'zk_Dance_ID',
          'Order',
          'Time',
          'Break',
        ],
        rows: [
          MapEntry(30, {1: '1', 2: '101', 3: '4', 4: '1', 5: '8'}),
          MapEntry(31, {1: '1', 2: '102', 3: '7', 4: '2'}),
          MapEntry(32, {1: '1', 2: '103', 4: '3', 6: 'Waltz break'}),
          MapEntry(33, {1: '1', 2: '104', 3: '99', 4: '4'}),
        ],
      ),
    ]);

    List<ImportSource> sourcesFor(ImportBytePicker picker) => [
      ImportSource(label: 'test JSON', adapterFactory: GenericJsonAdapter.new),
      ImportSource(
        label: "a Caller's Companion .USR file",
        adapterFactory: CallersCompanionUsrAdapter.new,
        bytePicker: picker,
      ),
    ];

    Future<void> selectUsr(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-source-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("a Caller's Companion .USR file").last);
      await tester.pumpAndSettle();
    }

    Future<void> chooseAndReview(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-continue')));
      await tester.pumpAndSettle();
    }

    testWidgets('the byte source shows a .USR file button, not URL/paste', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);

      expect(
        find.byKey(const ValueKey('import-choose-usr-file')),
        findsOneWidget,
      );
      // Text-only affordances are hidden for a binary source.
      expect(find.byKey(const ValueKey('import-url-field')), findsNothing);
      expect(find.byKey(const ValueKey('import-paste-field')), findsNothing);
      expect(find.byKey(const ValueKey('import-choose-file')), findsNothing);
    });

    testWidgets('planning lists the .USR dances for review', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);

      expect(find.text('Simplicity Swing'), findsOneWidget);
      expect(find.text('Petronella'), findsOneWidget);
      expect(find.text('2 of 2 will be imported'), findsOneWidget);
    });

    testWidgets('committing persists dances AND programs and surfaces the '
        'program names + notes', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);

      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // Result dialog surfaces both dances and programs.
      expect(
        find.byKey(const ValueKey('import-result-dialog')),
        findsOneWidget,
      );
      expect(find.text('Created: 2'), findsOneWidget);
      expect(find.text('Programs: 1'), findsOneWidget);
      // Program name-level confirmation (the Set's Location).
      expect(find.text('• Grange Hall'), findsOneWidget);
      // The SetItem referencing an absent dance (99) produced a note.
      expect(
        find.byKey(const ValueKey('import-program-notes')),
        findsOneWidget,
      );

      // Both dances and the program are actually in the database.
      final dances = await repos.dances.listAll();
      expect(
        dances.map((d) => d.title),
        containsAll(<String>['Simplicity Swing', 'Petronella']),
      );
      final programs = await repos.programs.listAll();
      expect(programs, hasLength(1));
      expect(programs.single.title, 'Grange Hall');
    });

    testWidgets('re-importing a Set dedupes onto the existing program and '
        'the dialog reports it as updated', (tester) async {
      final repos = openTestRepositories();
      // Pre-seed a CC-imported program whose provenance key matches the Set's
      // zk_Set_ID ('1') — simulating a prior import of the same file.
      await repos.programs.create(
        Program(
          id: 'existing-prog',
          title: 'Old Title',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          provenance: Provenance(
            source: ProvenanceSource.callersCompanion,
            externalId: '1',
            importedAt: DateTime.utc(2025, 1, 1),
            sourceVersion: 'cc-usr-1',
          ),
        ),
      );

      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      // The dialog reports one program, surfaced as updated (re-imported).
      expect(find.text('Programs: 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('import-programs-updated')),
        findsOneWidget,
      );
      expect(find.text('1 updated (re-imported)'), findsOneWidget);

      // No duplicate: the existing program was overwritten in place.
      final programs = await repos.programs.listAll();
      expect(programs, hasLength(1));
      expect(programs.single.id, 'existing-prog');
      expect(programs.single.title, 'Grange Hall');
    });

    testWidgets('Undo reverts the imported dances AND programs', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        payload: 'unused',
        sources: sourcesFor(() async => ccUsrBytes()),
        bytePicker: () async => ccUsrBytes(),
      );

      await selectUsr(tester);
      await chooseAndReview(tester);
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('import-undo-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-undone-snackbar')),
        findsOneWidget,
      );
      expect(await repos.dances.listAll(), isEmpty);
      expect(await repos.programs.listAll(), isEmpty);
    });
  });

  group('fetchImportUrl (default seam)', () {
    test('returns the body on a 200', () async {
      final client = MockClient(
        (_) async => http.Response('{"schemaVersion":1}', 200),
      );
      expect(
        await fetchImportUrl('https://example.com/a.json', client: client),
        '{"schemaVersion":1}',
      );
    });

    test('rejects an empty URL', () async {
      await expectLater(
        fetchImportUrl('   '),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('rejects a non-http(s) URL', () async {
      await expectLater(
        fetchImportUrl('ftp://example.com/a.json'),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('throws on a non-2xx status', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('throws on an empty body', () async {
      final client = MockClient((_) async => http.Response('   ', 200));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });

    test('wraps a transport failure', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      await expectLater(
        fetchImportUrl('https://example.com/a.json', client: client),
        throwsA(isA<UrlFetchException>()),
      );
    });
  });
}

/// A [SourceAdapter] that records the [ImportRequest] it was planned with, so a
/// test can assert the source URL was stashed on [ImportRequest.uri]. Produces
/// one trivial new dance so the review queue renders.
class _CapturingAdapter implements SourceAdapter {
  ImportRequest? lastRequest;

  @override
  ProvenanceSource get source => ProvenanceSource.json;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    lastRequest = request;
    return const [
      DiscoveredRecord(source: ProvenanceSource.json, externalId: 'c1'),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async => RawRecord(
    source: source,
    externalId: record.externalId,
    payload: 'captured',
    contentType: 'text/plain',
  );

  @override
  StructuredDraft parse(RawRecord raw) => StructuredDraft(
    dance: Dance(
      id: 'captured',
      title: 'Captured Dance',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    raw: raw,
  );
}

/// A [SourceAdapter] that discovers two records but fails to fetch one — used
/// to exercise the review UI's non-blocking batch-error handling.
class _PartlyBrokenAdapter implements SourceAdapter {
  @override
  ProvenanceSource get source => ProvenanceSource.json;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async =>
      const [
        DiscoveredRecord(source: ProvenanceSource.json, externalId: 'ok'),
        DiscoveredRecord(source: ProvenanceSource.json, externalId: 'broken'),
      ];

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    if (record.externalId == 'broken') {
      throw fetchError(source, 'boom', externalId: 'broken');
    }
    return RawRecord(
      source: source,
      externalId: record.externalId,
      payload: 'ok',
      contentType: 'text/plain',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) => StructuredDraft(
    dance: Dance(
      id: 'good',
      title: 'Good One',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    raw: raw,
  );
}
