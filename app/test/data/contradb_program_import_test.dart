import 'package:compendium_app/src/data/contradb_program_import.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_repositories.dart';

/// A seam-backed [OnlineSearchService] for both sources: no network. It records
/// every call so the resolver's fetch behavior can be asserted, and can be made
/// to fail a ContraDB identity import for specific ids (simulating an
/// unpublished/removed dance) or return canned Caller's Box search rows.
class _FakeService implements OnlineSearchService {
  _FakeService(
    this.source, {
    this.failLoadIds = const {},
    this.rowsByTitle = const {},
  });

  @override
  final OnlineSource source;

  /// ContraDB dance ids whose [loadPreview] should throw (unpublished/removed).
  final Set<String> failLoadIds;

  /// Caller's Box search rows keyed by the lower-cased query title.
  final Map<String, List<OnlineSearchResultRow>> rowsByTitle;

  final loadedIds = <String>[];
  final searchedTitles = <String>[];
  final importedTitles = <String>[];

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    searchedTitles.add(query.title);
    return rowsByTitle[query.title.trim().toLowerCase()] ?? const [];
  }

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
  }) async {
    loadedIds.add(result.id);
    if (failLoadIds.contains(result.id)) {
      throw Exception('This dance is not published.');
    }
    return OnlinePreview(
      result: result,
      detail: _detail(result.name),
      plan: _plan(result.name),
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
  }) async {
    final title = plan.draft.dance.title;
    importedTitles.add(title);
    final prefix = source == OnlineSource.contraDb ? 'cdb' : 'tcb';
    return OnlineImportResult(
      kind: OnlineImportKind.created,
      title: title,
      danceId: '$prefix-${title.toLowerCase()}',
      danceCount: 1,
    );
  }

  ImportRecordPlan _plan(String title) => ImportRecordPlan(
    draft: StructuredDraft(
      dance: Dance(
        id: '',
        title: title,
        authorIds: const [],
        tagIds: const [],
        form: DanceForm.contra,
        formation: const Formation(FormationShape.dupleImproper),
        status: DanceStatus.active,
        figures: const [],
        customFields: const [],
        hook: '',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      raw: const RawRecord(
        source: ProvenanceSource.contradb,
        externalId: '1',
        payload: '<html></html>',
      ),
    ),
    verdict: DedupeVerdict.isNew(),
  );

  DanceDetailData _detail(String title) => DanceDetailData(
    dance: _plan(title).draft.dance,
    authorNames: const [],
    tagNames: const [],
    customFields: const [],
    relatedDanceTitles: const {},
    sourcesById: const {},
    callingHistory: const [],
    crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
  );
}

OnlineSearchResultRow _tcbRow(String name, {String id = '1'}) =>
    OnlineSearchResultRow(
      source: OnlineSource.callersBox,
      id: id,
      name: name,
      author: '',
      formation: '',
    );

ContraDbProgram _program(List<ContraDbProgramActivity> activities) =>
    ContraDbProgram(title: 'Test Program', activities: activities);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('linked dances import via ContraDB identity, in order', () async {
    final repos = openTestRepositories();
    final contraDb = _FakeService(OnlineSource.contraDb);
    final callersBox = _FakeService(OnlineSource.callersBox);

    final resolved = await resolveContraDbProgram(
      _program([
        ContraDbProgramActivity.dance(danceId: '185', title: 'Courageous Soul'),
        ContraDbProgramActivity.note('Waltz'),
        ContraDbProgramActivity.dance(
          danceId: '173',
          title: 'Boys From Urbana',
        ),
      ]),
      contraDb: contraDb,
      callersBox: callersBox,
      repos: repos,
    );

    // Identity import fetched each dance by its id, in order.
    expect(contraDb.loadedIds, ['185', '173']);
    // Notes are never searched online.
    expect(callersBox.searchedTitles, isEmpty);

    expect(resolved[0].resolution, ContraDbActivityResolution.linkedContraDb);
    expect(resolved[0].danceId, 'cdb-courageous soul');
    expect(resolved[1].resolution, ContraDbActivityResolution.note);
    expect(resolved[1].text, 'Waltz');
    expect(resolved[2].danceId, 'cdb-boys from urbana');
  });

  test('a linked dance carries its attached note onto the slot', () async {
    final repos = openTestRepositories();
    final contraDb = _FakeService(OnlineSource.contraDb);
    final callersBox = _FakeService(OnlineSource.callersBox);

    final resolved = await resolveContraDbProgram(
      _program([
        ContraDbProgramActivity.dance(
          danceId: '162',
          title: 'Yo Ho Ho',
          note: 'Called as pirates/wenches',
        ),
      ]),
      contraDb: contraDb,
      callersBox: callersBox,
      repos: repos,
    );

    expect(resolved.single.danceId, 'cdb-yo ho ho');
    expect(resolved.single.text, 'Called as pirates/wenches');

    final slots = buildContraDbProgramSlots(resolved, newSlotId: uuidV4);
    expect(slots.single.danceId, 'cdb-yo ho ho');
    expect(slots.single.text, 'Called as pirates/wenches');
  });

  test(
    'ContraDB scrape failure falls back to Caller\'s Box by title',
    () async {
      final repos = openTestRepositories();
      // The ContraDB dance (id 9) is unpublished → loadPreview throws.
      final contraDb = _FakeService(OnlineSource.contraDb, failLoadIds: {'9'});
      final callersBox = _FakeService(
        OnlineSource.callersBox,
        rowsByTitle: {
          'hidden gem': [_tcbRow('Hidden Gem', id: '500')],
        },
      );

      final resolved = await resolveContraDbProgram(
        _program([
          ContraDbProgramActivity.dance(danceId: '9', title: 'Hidden Gem'),
        ]),
        contraDb: contraDb,
        callersBox: callersBox,
        repos: repos,
      );

      expect(contraDb.loadedIds, ['9']);
      expect(callersBox.searchedTitles, ['Hidden Gem']);
      expect(
        resolved.single.resolution,
        ContraDbActivityResolution.linkedCallersBox,
      );
      expect(resolved.single.danceId, 'tcb-hidden gem');
    },
  );

  test(
    'both paths fail → verbatim note floor keeps title + attached note',
    () async {
      final repos = openTestRepositories();
      final contraDb = _FakeService(OnlineSource.contraDb, failLoadIds: {'9'});
      final callersBox = _FakeService(OnlineSource.callersBox); // no TCB rows

      final resolved = await resolveContraDbProgram(
        _program([
          ContraDbProgramActivity.dance(
            danceId: '9',
            title: 'Unfindable',
            note: 'do it slowly',
          ),
        ]),
        contraDb: contraDb,
        callersBox: callersBox,
        repos: repos,
      );

      expect(resolved.single.resolution, ContraDbActivityResolution.note);
      // Both real strings preserved, nothing invented or dropped.
      expect(resolved.single.text, 'Unfindable — do it slowly');
      expect(resolved.single.danceId, isNull);
    },
  );

  test(
    'buildContraDbProgramSlots preserves order and numbers positions',
    () async {
      final repos = openTestRepositories();
      final contraDb = _FakeService(OnlineSource.contraDb);
      final callersBox = _FakeService(OnlineSource.callersBox);

      final resolved = await resolveContraDbProgram(
        _program([
          ContraDbProgramActivity.dance(danceId: '1', title: 'One'),
          ContraDbProgramActivity.note('Break'),
          ContraDbProgramActivity.dance(danceId: '2', title: 'Two'),
        ]),
        contraDb: contraDb,
        callersBox: callersBox,
        repos: repos,
      );

      final slots = buildContraDbProgramSlots(resolved, newSlotId: uuidV4);
      expect(slots.map((s) => s.position), [0, 1, 2]);
      expect(slots[0].danceId, 'cdb-one');
      expect(slots[0].text, isNull);
      expect(slots[1].danceId, isNull);
      expect(slots[1].text, 'Break');
      expect(slots[2].danceId, 'cdb-two');
      // Every slot id is unique.
      expect(slots.map((s) => s.id).toSet(), hasLength(3));
    },
  );

  // #332/#314: the program import screen builds its fetch URL with
  // buildContraDbProgramUrl and fetches it through the shared, SSRF-hardened
  // fetchImportUrl. A crafted "program link" whose host is an internal/reserved
  // address (the shared-link attack: a victim pastes it and taps Fetch) must be
  // rejected by the host guard BEFORE any network call, and the error must not
  // echo the URL back.
  test('a blocked-host program URL is rejected before any fetch', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('should never be reached', 200);
    });

    // The builder faithfully preserves the pasted (malicious) host...
    const pasted = 'http://169.254.169.254/programs/1';
    final url = buildContraDbProgramUrl(pasted);
    expect(url, 'http://169.254.169.254/programs/1');

    // ...but the guarded fetch throws without ever touching the network.
    await expectLater(
      () => fetchImportUrl(url, client: client),
      throwsA(
        isA<UrlFetchException>().having(
          (e) => e.toString(),
          'toString',
          allOf(isNot(contains('169.254.169.254')), isNot(contains(url))),
        ),
      ),
    );
    expect(requests, 0, reason: 'no request should be sent to a blocked host');
  });
}
