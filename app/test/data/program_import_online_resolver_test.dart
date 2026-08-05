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
    this.previewFiguresByTitle = const {},
    this.needsConfirmationTitles = const {},
  });

  /// Search rows keyed by the (lower-cased) query title.
  final Map<String, List<OnlineSearchResultRow>> rowsByTitle;
  final bool throwOnSearch;

  /// (Lower-cased) titles for which [loadPreview] should return a plan whose
  /// verdict is a confident local duplicate (issue #685) — simulates the
  /// previewed online dance already existing locally under the same
  /// (normalized) title with an overlapping tokenized author set. The
  /// confident candidate's `danceId` is always `'local-existing'` — tests
  /// that need to exercise the figure-comparison branch (issue #686) must
  /// seed a real dance under that id via `repos.dances.create(...)`.
  final Set<String> confidentTitles;

  /// (Lower-cased) titles → the previewed draft's figures, for tests
  /// exercising issue #686's identical-vs-differing figure comparison. Titles
  /// not present here preview with no figures.
  final Map<String, List<Figure>> previewFiguresByTitle;

  /// (Lower-cased) titles for which [import] should return
  /// [OnlineImportKind.needsConfirmation] when [ambiguousResolution] is null,
  /// simulating the #797 detection block firing on a non-confident path.
  /// Used to test the explicit opt-out at program-import call sites without
  /// requiring a real repos/figures setup.
  final Set<String> needsConfirmationTitles;

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
    DedupeIndex? index,
  }) async {
    loadedIds.add(result.id);
    final confident = confidentTitles.contains(
      result.name.trim().toLowerCase(),
    );
    return OnlinePreview(
      result: result,
      detail: _detail(result.name),
      plan: _plan(
        result.name,
        confident: confident,
        figures: previewFiguresByTitle[result.name.trim().toLowerCase()],
      ),
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async {
    final title = plan.draft.dance.title;
    importedIds.add(title);
    // Simulate the #797 service detection when requested: if
    // ambiguousResolution is null and the title is in needsConfirmationTitles,
    // return needsConfirmation (as the real service would for a confident +
    // differing-figures plan). This lets call-site tests verify the explicit
    // opt-out without setting up real repos state.
    if (ambiguousResolution == null &&
        needsConfirmationTitles.contains(title.trim().toLowerCase())) {
      return OnlineImportResult(
        kind: OnlineImportKind.needsConfirmation,
        title: title,
        danceId: 'local-existing',
        danceCount: 1,
      );
    }
    return OnlineImportResult(
      kind: OnlineImportKind.created,
      title: title,
      danceId: 'imported-${title.toLowerCase()}',
      danceCount: 1,
    );
  }

  ImportRecordPlan _plan(
    String title, {
    bool confident = false,
    List<Figure>? figures,
  }) => ImportRecordPlan(
    draft: StructuredDraft(
      dance: Dance(
        id: '',
        title: title,
        authorIds: const [],
        tagIds: const [],
        form: DanceForm.contra,
        formation: const Formation(FormationShape.dupleImproper),
        status: DanceStatus.active,
        figures: figures ?? const [],
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

/// A minimal persisted local dance for seeding the "confident match" target
/// in issue #686 figure-comparison tests.
Dance _localDance({required String id, required List<Figure> figures}) => Dance(
  id: id,
  title: 'Money Musk',
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: figures,
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
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

  test('confident local duplicate whose target dance cannot be loaded '
      'conservatively falls back to the note-slot (never imports)', () async {
    // 'local-existing' is never seeded into `repos` — the resolver can't
    // confirm identical vs. differing figures, so it must fall back to the
    // pre-#686 skip rather than guessing.
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
    // ...but import must never be called on a confident match whose target
    // can't be confirmed.
    expect(service.importedIds, isEmpty);

    final line = resolved.single;
    expect(line.resolution, PlaintextLineResolution.unmatched);
    expect(line.importedOnline, isFalse);
    expect(line.danceId, isNull);
  });

  test('confident match + IDENTICAL figures (issue #686) still skips — #685\'s '
      'never-silently-duplicate rule is unchanged', () async {
    final repos = openTestRepositories();
    final sharedFigures = [
      Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      Figure(move: 'allemande', params: {'hand': 'left', 'beats': 8}),
    ];
    await repos.dances.create(
      _localDance(id: 'local-existing', figures: sharedFigures),
    );
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk', id: '10600')],
      },
      confidentTitles: {'money musk'},
      previewFiguresByTitle: {'money musk': sharedFigures},
    );

    final danceId = await resolveConfidentOnlineDanceId(
      'Money Musk',
      service: service,
      repos: repos,
    );

    expect(danceId, isNull);
    expect(service.importedIds, isEmpty);
    // No new dance was created, and the existing one is untouched.
    expect(await repos.dances.getById('local-existing'), isNotNull);
  });

  test(
    'confident match + DIFFERING figures (issue #686) auto-imports as a '
    'variation with a symmetric relatedDance link-back, no user prompt',
    () async {
      final repos = openTestRepositories();
      final targetFigures = [
        Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      ];
      final previewFigures = [
        Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 8}),
      ];
      await repos.dances.create(
        _localDance(id: 'local-existing', figures: targetFigures),
      );
      final service = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
        confidentTitles: {'money musk'},
        previewFiguresByTitle: {'money musk': previewFigures},
      );

      final danceId = await resolveConfidentOnlineDanceId(
        'Money Musk',
        service: service,
        repos: repos,
      );

      expect(danceId, isNotNull);
      expect(danceId, isNot('local-existing'));
      // Never routed through the interactive/manual `service.import` path —
      // the auto-variation commit goes straight through `ImportPipeline`.
      expect(service.importedIds, isEmpty);

      final created = await repos.dances.getById(danceId!);
      expect(created, isNotNull);
      expect(created!.title, 'Money Musk');
      expect(
        created.links,
        contains(
          isA<DanceLink>()
              .having((l) => l.kind, 'kind', LinkKind.relatedDance)
              .having(
                (l) => l.targetDanceId,
                'targetDanceId',
                'local-existing',
              ),
        ),
      );

      final target = await repos.dances.getById('local-existing');
      expect(
        target!.links,
        contains(
          isA<DanceLink>()
              .having((l) => l.kind, 'kind', LinkKind.relatedDance)
              .having((l) => l.targetDanceId, 'targetDanceId', danceId),
        ),
      );
    },
  );

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

  // #797: the non-confident-match fallback path (line 180 of
  // program_import_online_resolver.dart) must not return the pre-existing
  // candidate dance id when the service returns needsConfirmation.
  // Structurally, the real services cannot return needsConfirmation on this
  // path (verdict.hasConfidentMatch == false at line 180, and the detection
  // block requires hasConfidentMatch == true). The explicit
  // ambiguousResolution: duplicate() opt-out is belt-and-suspenders against
  // future refactors that change that guarantee.
  //
  // RED: without the fix, import() is called without ambiguousResolution →
  // fake returns needsConfirmation with danceId='local-existing' → resolver
  // links the slot to 'local-existing' (a pre-existing dance, not imported).
  // GREEN: fix passes ambiguousResolution: duplicate() → fake returns created
  // with danceId='imported-some dance'.
  test('#797 non-confident-match path: needsConfirmation is never returned '
      'to the caller — explicit opt-out protects against future refactors '
      '(red-run)', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'some dance': [_row('Some Dance', id: '99')],
      },
      // NOT in confidentTitles → non-confident path → reaches line 180.
      // IS in needsConfirmationTitles → import() returns needsConfirmation
      // when ambiguousResolution is null (simulating hypothetical future).
      needsConfirmationTitles: {'some dance'},
    );

    final resolved = await resolveUnmatchedOnline(
      [_unmatched('Some Dance')],
      service: service,
      repos: repos,
    );

    // Must link to the actually-imported dance, not to the candidate.
    // Without the fix the line is linked to 'local-existing' (wrong dance).
    expect(
      resolved.single.danceId,
      isNot('local-existing'),
      reason: 'program import must not silently return pre-existing dance id',
    );
    expect(resolved.single.danceId, 'imported-some dance');
    expect(resolved.single.importedOnline, isTrue);
  });

  // Regression pin for issue #823. The Collection-side title-list import shares
  // `lookupUniqueExactTitle` with this resolver but deliberately does NOT share
  // the commit: it previews and hands the plan to the review screen instead.
  // The simplification a future reader would reach for — "both callers just
  // need the plan, make resolveConfidentOnlineDanceId preview-only too" —
  // silently turns program import into a no-op, because a program line has no
  // review screen to commit it. This test catches that mutation.
  test('#823 regression: the PROGRAM path still imports on a confident hit — '
      'sharing only the lookup step must not make it preview-only', () async {
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

    // The shared lookup ran…
    expect(service.searchedTitles, ['Money Musk']);
    // …and, unlike the Collection path, this one went on to commit.
    expect(
      service.importedIds,
      ['Money Musk'],
      reason:
          'a preview-only program resolver would leave this empty and the '
          'program line permanently unresolved',
    );
    expect(resolved.single.resolution, PlaintextLineResolution.matched);
    expect(resolved.single.importedOnline, isTrue);
    expect(resolved.single.danceId, isNotNull);
  });
}
