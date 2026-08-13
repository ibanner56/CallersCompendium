import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:compendium_app/src/data/program_ambiguous_review.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// A minimal fake that previews any row into a fresh, always-new plan (or
/// throws for a configured id), tagged with a fixed [OnlineSource]. Records
/// which ids were previewed so tests can assert per-source routing.
class _FakePreviewService implements OnlineSearchService {
  _FakePreviewService(this._source, {this.throwForIds = const {}});

  final OnlineSource _source;
  final Set<String> throwForIds;
  final previewedIds = <String>[];

  @override
  OnlineSource get source => _source;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async =>
      const [];

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    previewedIds.add(result.id);
    if (throwForIds.contains(result.id)) {
      throw Exception('preview failed');
    }
    final dance = Dance(
      id: '',
      title: result.name,
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
    );
    final plan = ImportRecordPlan(
      draft: StructuredDraft(
        dance: dance,
        raw: RawRecord(
          source: _source == OnlineSource.callersBox
              ? ProvenanceSource.callersbox
              : ProvenanceSource.contradb,
          externalId: result.id,
          payload: '{}',
        ),
      ),
      verdict: DedupeVerdict.isNew(),
    );
    return OnlinePreview(
      result: result,
      detail: DanceDetailData(
        dance: dance,
        authorNames: const [],
        tagNames: const [],
        customFields: const [],
        relatedDanceTitles: const {},
        sourcesById: const {},
        crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
      ),
      plan: plan,
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async => throw UnimplementedError('not exercised by these tests');
}

OnlineSearchResultRow _row(
  String id, {
  String name = 'Petronella',
  OnlineSource source = OnlineSource.callersBox,
}) => OnlineSearchResultRow(
  source: source,
  id: id,
  name: name,
  author: '',
  formation: '',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a line with no online candidates contributes nothing', () async {
    final repos = openTestRepositories();
    final lines = [
      const ParsedProgramLine(
        text: 'Money Musk',
        resolution: PlaintextLineResolution.matched,
        danceId: 'd1',
        matchCount: 1,
      ),
    ];

    final result = await buildProgramAmbiguousImport(
      lines,
      servicesBySource: const {},
      repos: repos,
    );

    expect(result, isNull);
  });

  test(
    'each candidate is previewed against its OWN originating source',
    () async {
      final repos = openTestRepositories();
      final callersBox = _FakePreviewService(OnlineSource.callersBox);
      final contraDb = _FakePreviewService(OnlineSource.contraDb);
      final lines = [
        ParsedProgramLine(
          text: 'Petronella',
          resolution: PlaintextLineResolution.unmatched,
          onlineCandidates: [
            _row('1'),
            _row('55', source: OnlineSource.contraDb),
          ],
        ),
      ];

      final result = await buildProgramAmbiguousImport(
        lines,
        servicesBySource: {
          OnlineSource.callersBox: callersBox,
          OnlineSource.contraDb: contraDb,
        },
        repos: repos,
      );

      expect(callersBox.previewedIds, ['1']);
      expect(contraDb.previewedIds, ['55']);
      expect(result, isNotNull);
      expect(result!.lines, hasLength(1));
      expect(result.lines.single.originalLineIndex, 0);
      expect(result.lines.single.lineText, 'Petronella');
      expect(result.lines.single.candidates, hasLength(2));
    },
  );

  test('preserves original-line index across a mix of resolved and ambiguous '
      'lines', () async {
    final repos = openTestRepositories();
    final callersBox = _FakePreviewService(OnlineSource.callersBox);
    final lines = [
      const ParsedProgramLine(
        text: 'Matched',
        resolution: PlaintextLineResolution.matched,
        danceId: 'd1',
        matchCount: 1,
      ),
      ParsedProgramLine(
        text: 'Petronella',
        resolution: PlaintextLineResolution.unmatched,
        onlineCandidates: [_row('1'), _row('2')],
      ),
      const ParsedProgramLine(
        text: 'Reel',
        resolution: PlaintextLineResolution.unmatched,
      ),
    ];

    final result = await buildProgramAmbiguousImport(
      lines,
      servicesBySource: {OnlineSource.callersBox: callersBox},
      repos: repos,
    );

    expect(result, isNotNull);
    expect(result!.lines, hasLength(1));
    // Index 1, not 0 — the position in the FULL lines list, not among only
    // the ambiguous ones, so the caller can link back into the right slot.
    expect(result.lines.single.originalLineIndex, 1);
  });

  test('a candidate whose preview throws is dropped; the line still reviews '
      'with the survivors', () async {
    final repos = openTestRepositories();
    final callersBox = _FakePreviewService(
      OnlineSource.callersBox,
      throwForIds: {'2'},
    );
    final lines = [
      ParsedProgramLine(
        text: 'Petronella',
        resolution: PlaintextLineResolution.unmatched,
        onlineCandidates: [_row('1'), _row('2'), _row('3')],
      ),
    ];

    final result = await buildProgramAmbiguousImport(
      lines,
      servicesBySource: {OnlineSource.callersBox: callersBox},
      repos: repos,
    );

    expect(result, isNotNull);
    expect(result!.lines.single.candidates, hasLength(2));
  });

  test(
    'a line whose every candidate fails to preview contributes nothing',
    () async {
      final repos = openTestRepositories();
      final callersBox = _FakePreviewService(
        OnlineSource.callersBox,
        throwForIds: {'1'},
      );
      final lines = [
        ParsedProgramLine(
          text: 'Petronella',
          resolution: PlaintextLineResolution.unmatched,
          onlineCandidates: [_row('1')],
        ),
      ];

      final result = await buildProgramAmbiguousImport(
        lines,
        servicesBySource: {OnlineSource.callersBox: callersBox},
        repos: repos,
      );

      expect(result, isNull);
    },
  );

  test('a candidate cap bounds the fetches for one line', () async {
    final repos = openTestRepositories();
    final callersBox = _FakePreviewService(OnlineSource.callersBox);
    final manyRows = [
      for (var i = 0; i < kMaxAmbiguousCandidatesPerLine + 3; i++) _row('$i'),
    ];
    final lines = [
      ParsedProgramLine(
        text: 'Petronella',
        resolution: PlaintextLineResolution.unmatched,
        onlineCandidates: manyRows,
      ),
    ];

    final result = await buildProgramAmbiguousImport(
      lines,
      servicesBySource: {OnlineSource.callersBox: callersBox},
      repos: repos,
    );

    expect(callersBox.previewedIds, hasLength(kMaxAmbiguousCandidatesPerLine));
    expect(
      result!.lines.single.candidates,
      hasLength(kMaxAmbiguousCandidatesPerLine),
    );
  });
}
