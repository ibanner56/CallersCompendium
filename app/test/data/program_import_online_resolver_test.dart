import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:compendium_app/src/data/program_import_online_resolver.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Records calls and returns canned rows/previews/results so the resolver can be
/// driven without touching the network or the real Caller's Box parse path.
class _FakeOnlineService implements OnlineSearchService {
  _FakeOnlineService({
    this.rowsByTitle = const {},
    this.throwOnSearch = false,
    this.confidentTitles = const {},
  });

  /// Search rows keyed by the (lower-cased) query title.
  final Map<String, List<OnlineSearchResultRow>> rowsByTitle;
  final bool throwOnSearch;

  /// (Lower-cased) titles for which [loadPreview] should return a plan whose
  /// verdict is a confident local duplicate (issue #685) — simulates the
  /// previewed online dance already existing locally under the same
  /// (normalized) title with an overlapping tokenized author set.
  final Set<String> confidentTitles;

  final searchedTitles = <String>[];
  final loadedIds = <String>[];
  final importedIds = <String>[];

  @override
  OnlineSource get source => OnlineSource.callersBox;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    searchedTitles.add(query.title);
    if (throwOnSearch) throw Exception('offline');
    return rowsByTitle[query.title.trim().toLowerCase()] ?? const [];
  }

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
  }) async {
    loadedIds.add(result.id);
    final confident = confidentTitles.contains(
      result.name.trim().toLowerCase(),
    );
    return OnlinePreview(
      result: result,
      detail: _detail(result.name),
      plan: _plan(result.name, confident: confident),
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
  }) async {
    final title = plan.draft.dance.title;
    importedIds.add(title);
    return OnlineImportResult(
      kind: OnlineImportKind.created,
      title: title,
      danceId: 'imported-${title.toLowerCase()}',
      danceCount: 1,
    );
  }

  ImportRecordPlan _plan(String title, {bool confident = false}) =>
      ImportRecordPlan(
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
            source: ProvenanceSource.callersbox,
            externalId: '1',
            payload: '{}',
          ),
        ),
        verdict: confident
            ? DedupeVerdict.ambiguous([
                DedupeCandidate(
                  danceId: 'local-existing',
                  score: 0.8,
                  confident: true,
                ),
              ])
            : DedupeVerdict.isNew(),
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

OnlineSearchResultRow _row(String name, {String id = '1'}) =>
    OnlineSearchResultRow(
      source: OnlineSource.callersBox,
      id: id,
      name: name,
      author: '',
      formation: '',
    );

ParsedProgramLine _unmatched(String text) => ParsedProgramLine(
  text: text,
  resolution: PlaintextLineResolution.unmatched,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('unique exact-title hit is imported and linked to the slot', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk', id: '10600')],
      },
    );

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    );

    expect(service.searchedTitles, ['Money Musk']);
    expect(service.loadedIds, ['10600']);
    expect(service.importedIds, ['Money Musk']);

    final line = resolved.single;
    expect(line.resolution, PlaintextLineResolution.matched);
    expect(line.importedOnline, isTrue);
    expect(line.danceId, 'imported-money musk');
    expect(line.matchCount, 1);
  });

  test('case-insensitive exact match still links', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('MONEY MUSK')],
      },
    );

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('money musk')],
      service: service,
      repos: repos,
    );

    expect(resolved.single.importedOnline, isTrue);
  });

  test('no results keeps the note-slot fallback', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(rowsByTitle: const {});

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('Nonexistent Dance')],
      service: service,
      repos: repos,
    );

    expect(service.searchedTitles, ['Nonexistent Dance']);
    expect(service.loadedIds, isEmpty);
    expect(resolved.single.resolution, PlaintextLineResolution.unmatched);
    expect(resolved.single.importedOnline, isFalse);
  });

  test(
    'only fuzzy (non-exact) hits are not confident → stays a note',
    () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'money': [_row('Money Musk'), _row('Money in Both Pockets')],
        },
      );

      final resolved = await resolveUnmatchedOnline(
        [_unmatched('Money')],
        service: service,
        repos: repos,
      );

      expect(service.loadedIds, isEmpty);
      expect(resolved.single.resolution, PlaintextLineResolution.unmatched);
    },
  );

  test('multiple exact-title hits are ambiguous → stays a note', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'petronella': [
          _row('Petronella', id: '1'),
          _row('Petronella', id: '2'),
        ],
      },
    );

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('Petronella')],
      service: service,
      repos: repos,
    );

    expect(service.loadedIds, isEmpty);
    expect(resolved.single.resolution, PlaintextLineResolution.unmatched);
  });

  test(
    'confident local duplicate (issue #685) is never imported — the line '
    'falls back to the note-slot and service.import is never called',
    () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
        confidentTitles: {'money musk'},
      );

      final resolved = await resolveUnmatchedOnline(
        [_unmatched('Money Musk')],
        service: service,
        repos: repos,
      );

      expect(service.searchedTitles, ['Money Musk']);
      // The preview is still loaded (that's how the verdict is consulted)...
      expect(service.loadedIds, ['10600']);
      // ...but import must never be called on a confident match.
      expect(service.importedIds, isEmpty);

      final line = resolved.single;
      expect(line.resolution, PlaintextLineResolution.unmatched);
      expect(line.importedOnline, isFalse);
      expect(line.danceId, isNull);
    },
  );

  test('resolveConfidentOnlineDanceId itself returns null on a confident local '
      'duplicate without calling service.import', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk', id: '10600')],
      },
      confidentTitles: {'money musk'},
    );

    final danceId = await resolveConfidentOnlineDanceId(
      'Money Musk',
      service: service,
      repos: repos,
    );

    expect(danceId, isNull);
    expect(service.importedIds, isEmpty);
  });

  test('a search error keeps the note fallback and does not throw', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(throwOnSearch: true);

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    );

    expect(resolved.single.resolution, PlaintextLineResolution.unmatched);
  });

  test('non-unmatched lines pass through untouched', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk')],
      },
    );

    final input = [
      const ParsedProgramLine(
        text: 'Local Dance',
        resolution: PlaintextLineResolution.matched,
        danceId: 'd1',
        matchCount: 1,
      ),
      const ParsedProgramLine(
        text: 'Ambiguous Dance',
        resolution: PlaintextLineResolution.ambiguous,
        matchCount: 2,
      ),
      _unmatched('Money Musk'),
    ];

    final resolved = await resolveUnmatchedOnline(
      input,
      service: service,
      repos: repos,
    );

    // Only the unmatched title triggered a search.
    expect(service.searchedTitles, ['Money Musk']);
    expect(resolved[0].danceId, 'd1');
    expect(resolved[0].importedOnline, isFalse);
    expect(resolved[1].resolution, PlaintextLineResolution.ambiguous);
    expect(resolved[2].importedOnline, isTrue);
  });
}
