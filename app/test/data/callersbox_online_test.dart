import 'dart:convert';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/online_search_labels.dart';
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
    Future<Dance> seedDance(CompendiumRepositories repos, {int? rating}) async {
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
      'confident match + identical figures: creates duplicate (no prompt — regression)',
      () async {
        // Acceptance criteria: "exact match keeps today's behaviour" — identical
        // figures bypass the detection block; the duplicate is created silently.
        final repos = openTestRepositories();
        final existing = await seedDance(repos);

        final plan = ambiguousPlan(
          candidateId: existing.id,
          figures: [customFigure('neighbors balance and swing')], // SAME
        );
        await CallersBoxOnline().import(repos, plan);

        // A second dance was created (existing behavior, unchanged).
        final saved = await repos.dances.listAll();
        expect(saved, hasLength(2));
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
