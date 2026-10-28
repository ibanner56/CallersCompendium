import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/plaintext_program_import.dart';
import 'package:compendium_app/src/data/program_import_online_resolver.dart';
import 'package:compendium_app/src/data/program_import_rollback.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
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
    this.source = OnlineSource.callersBox,
    this.searchError,
    this.loadErrors = const {},
    this.commitForReal = false,
  });

  /// Thrown by every [search] when set (a typed failure, unlike
  /// [throwOnSearch]'s generic one).
  final Exception? searchError;

  /// Row ids whose [loadPreview] throws the given exception.
  final Map<String, Exception> loadErrors;

  /// Whether [import] writes the dance through the real shared commit
  /// ([commitPreviewedOnlinePlan]) instead of returning a canned id, so the
  /// write can be undone.
  final bool commitForReal;

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
  final searchedQueries = <OnlineSearchQuery>[];
  final loadedIds = <String>[];
  final importedIds = <String>[];

  @override
  final OnlineSource source;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    searchedTitles.add(query.title);
    searchedQueries.add(query);
    if (throwOnSearch) throw Exception('offline');
    final error = searchError;
    if (error != null) throw error;
    final rows = rowsByTitle[query.title.trim().toLowerCase()] ?? const [];
    // Honour the #845 policy exactly as a real service does. Without this the
    // fake would return the same rows whatever the caller asked for, and any
    // test of the opt-out could only ever assert the flag was passed — never
    // that it changed the outcome.
    if (!query.requireFigures) return rows;
    return rows.where((r) => r.figuresAvailable).toList();
  }

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    loadedIds.add(result.id);
    final error = loadErrors[result.id];
    if (error != null) throw error;
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
    List<String> defaultTagIds = const [],
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
    if (commitForReal) {
      return commitPreviewedOnlinePlan(
        repos,
        plan,
        now: now,
        ambiguousResolution: ambiguousResolution,
        defaultTagIds: defaultTagIds,
        importFailedReason: UrlFetchFailureReason.callersBoxImportFailed,
        debugLabel: 'fake',
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
    crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
  );
}

OnlineSearchResultRow _row(
  String name, {
  String id = '1',
  bool figuresAvailable = true,
  OnlineSource source = OnlineSource.callersBox,
}) => OnlineSearchResultRow(
  source: source,
  id: id,
  name: name,
  author: '',
  formation: '',
  figuresAvailable: figuresAvailable,
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
  test('unique exact-title hit is imported and linked to the slot', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk', id: '10600')],
      },
    );

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('money musk')],
      service: service,
      repos: repos,
    )).lines;

    expect(resolved.single.importedOnline, isTrue);
  });

  test('no results keeps the note-slot fallback', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(rowsByTitle: const {});

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Nonexistent Dance')],
      service: service,
      repos: repos,
    )).lines;

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

      final resolved = (await resolveUnmatchedOnline(
        [_unmatched('Money')],
        service: service,
        repos: repos,
      )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Petronella')],
      service: service,
      repos: repos,
    )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    )).lines;

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

  test('a dance created for a program slot gets no default import tags '
      '(#1476)', () async {
    final repos = openTestRepositories();
    final _ = await repos.tags.upsert(Tag(id: 'no-card', name: 'No card'));
    await repos.settings.set(
      kDefaultImportTagNamesKey,
      encodeDefaultImportTagNames(['No card']),
    );
    await repos.dances.create(
      _localDance(
        id: 'local-existing',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
        ],
      ),
    );
    final service = _FakeOnlineService(
      rowsByTitle: {
        'money musk': [_row('Money Musk', id: '10600')],
      },
      confidentTitles: {'money musk'},
      previewFiguresByTitle: {
        'money musk': [
          Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 8}),
        ],
      },
    );

    final danceId = await resolveConfidentOnlineDanceId(
      'Money Musk',
      service: service,
      repos: repos,
    );

    final created = (await repos.dances.getById(danceId!))!;
    expect(created.id, isNot('local-existing'));
    expect(created.tagIds, isEmpty);
  });

  test('a search error keeps the note fallback and does not throw', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(throwOnSearch: true);

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      input,
      service: service,
      repos: repos,
    )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Some Dance')],
      service: service,
      repos: repos,
    )).lines;

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

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Money Musk')],
      service: service,
      repos: repos,
    )).lines;

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

  // Issue #845, as revised by INTAKE-13 (2026-10 behaviour audit). The Caller's
  // Box search excludes dances whose figures TCB will not serve. This path used
  // to opt out and keep the wider, pre-#845 result set, which let an unattended
  // program import bring in a dance with NO figures. It now keeps the default,
  // as the Collection title-list import does (imports.md, "a list of titles").
  //
  // These drive the real resolver entry points rather than
  // `lookupUniqueExactTitle` directly, so they cover the actual call site.
  test('#845: the program path asks only for dances with figures', () async {
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'petronella': [_row('Petronella', id: '1')],
      },
    );

    await resolveUnmatchedOnline(
      [_unmatched('Petronella')],
      service: service,
      repos: repos,
    );

    // Unconditional: assert the query was made AND what it asked for. A
    // `.where(...).firstOrNull`-style check would pass vacuously if the search
    // never happened at all.
    expect(service.searchedQueries, hasLength(1));
    expect(service.searchedQueries.single.requireFigures, isTrue);
  });

  test('#845: a title held only by a figure-hidden dance stays a note', () async {
    // The behavioural consequence, end to end. `_FakeOnlineService` honours
    // `requireFigures`, so the old opt-out makes this line import the figureless
    // stub — red on what the code DID, not merely on which flag it passed.
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'petronella': [_row('Petronella', id: '1', figuresAvailable: false)],
      },
    );

    final resolved = (await resolveUnmatchedOnline(
      [_unmatched('Petronella')],
      service: service,
      repos: repos,
    )).lines;

    expect(resolved.single.resolution, PlaintextLineResolution.unmatched);
    expect(service.loadedIds, isEmpty);
    expect(service.importedIds, isEmpty);
  });

  test('#845: a figure-hidden twin no longer hides the dance that has '
      'figures', () async {
    // Two rows share the title and only ONE serves its figures. Filtering
    // leaves a single exact hit, which is imported: the twin could only ever
    // have arrived as an empty stub. The Collection title list resolves the
    // same paste the same way.
    final repos = openTestRepositories();
    final service = _FakeOnlineService(
      rowsByTitle: {
        'petronella': [
          _row('Petronella', id: '1', figuresAvailable: false),
          _row('Petronella', id: '2'),
        ],
      },
    );

    final danceId = await resolveConfidentOnlineDanceId(
      'Petronella',
      service: service,
      repos: repos,
    );

    expect(danceId, 'imported-petronella');
    expect(service.loadedIds, ['2']);
    expect(service.searchedQueries.single.requireFigures, isTrue);
  });

  // Issue #943: the ContraDB fallback. `resolveUnmatchedOnline`'s `fallbacks`
  // param widens the single-source resolver into an ordered chain — Caller's
  // Box first, then each fallback in turn — stopping at the first source that
  // resolves a line confidently (ruling 1). These tests use a second
  // `_FakeOnlineService` tagged `OnlineSource.contraDb` to stand in for the
  // fallback source; every prior test above still drives the single-source
  // `service:` param alone and is the regression pin that the single-source
  // behaviour is unchanged.
  group('#943 ContraDB fallback', () {
    test('the fallback is tried, and imported from, when the primary source '
        'has no results', () async {
      final repos = openTestRepositories();
      final callersBox = _FakeOnlineService(rowsByTitle: const {});
      final contraDb = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [
            _row('Money Musk', id: '10600', source: OnlineSource.contraDb),
          ],
        },
        source: OnlineSource.contraDb,
      );

      final resolved = (await resolveUnmatchedOnline(
        [_unmatched('Money Musk')],
        service: callersBox,
        fallbacks: [contraDb],
        repos: repos,
      )).lines;

      expect(callersBox.searchedTitles, ['Money Musk']);
      expect(contraDb.searchedTitles, ['Money Musk']);
      expect(contraDb.loadedIds, ['10600']);
      final line = resolved.single;
      expect(line.resolution, PlaintextLineResolution.matched);
      expect(line.importedOnline, isTrue);
      expect(line.danceId, 'imported-money musk');
    });

    test('order/stop rule: a confident primary-source hit never triggers a '
        'fallback search', () async {
      final repos = openTestRepositories();
      final callersBox = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );
      final contraDb = _FakeOnlineService(source: OnlineSource.contraDb);

      final resolved = (await resolveUnmatchedOnline(
        [_unmatched('Money Musk')],
        service: callersBox,
        fallbacks: [contraDb],
        repos: repos,
      )).lines;

      expect(contraDb.searchedTitles, isEmpty);
      expect(resolved.single.importedOnline, isTrue);
    });

    // The falsification pin for the trap this issue's plan identified: a
    // naive "null → try the next source" would ask ContraDB for a dance the
    // local collection already has (issue #685's decline), and — if
    // ContraDB's rendition of the SAME dance differs canonically — issue
    // #686's variation branch would then auto-import it as a "genuinely
    // different choreography", unattended. Mutating `_SourceDeclined` cases
    // in `_resolveLineAcrossSources` to `continue` (fall through) instead of
    // `return line` reproduces exactly that and turns this test red.
    test('a #685 decline on the primary source stops the chain — the fallback '
        'is never searched, even though it has a differing-figures rendition '
        'of the same dance', () async {
      final repos = openTestRepositories();
      final sharedFigures = [
        Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      ];
      await repos.dances.create(
        _localDance(id: 'local-existing', figures: sharedFigures),
      );
      final callersBox = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
        confidentTitles: {'money musk'},
        previewFiguresByTitle: {'money musk': sharedFigures}, // identical
      );
      final contraDb = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [
            _row('Money Musk', id: '77', source: OnlineSource.contraDb),
          ],
        },
        source: OnlineSource.contraDb,
      );

      final resolved = (await resolveUnmatchedOnline(
        [_unmatched('Money Musk')],
        service: callersBox,
        fallbacks: [contraDb],
        repos: repos,
      )).lines;

      expect(
        contraDb.searchedTitles,
        isEmpty,
        reason:
            'a #685 decline is a fact about the local collection, not the '
            'source — the fallback must never be asked',
      );
      final line = resolved.single;
      expect(line.resolution, PlaintextLineResolution.unmatched);
      expect(line.danceId, isNull);
      expect(line.onlineCandidates, isEmpty);
    });

    test(
      'ambiguous on the primary, miss on the fallback: the line stays a note '
      'but carries the primary\'s candidates',
      () async {
        final repos = openTestRepositories();
        final callersBox = _FakeOnlineService(
          rowsByTitle: {
            'petronella': [
              _row('Petronella', id: '1'),
              _row('Petronella', id: '2'),
            ],
          },
        );
        final contraDb = _FakeOnlineService(
          rowsByTitle: const {},
          source: OnlineSource.contraDb,
        );

        final resolved = (await resolveUnmatchedOnline(
          [_unmatched('Petronella')],
          service: callersBox,
          fallbacks: [contraDb],
          repos: repos,
        )).lines;

        expect(contraDb.searchedTitles, ['Petronella']);
        final line = resolved.single;
        expect(line.resolution, PlaintextLineResolution.unmatched);
        expect(line.onlineCandidates, hasLength(2));
        expect(line.onlineCandidates.map((r) => r.id), ['1', '2']);
      },
    );

    test(
      'ambiguous on both sources accumulates candidates from each, in order',
      () async {
        final repos = openTestRepositories();
        final callersBox = _FakeOnlineService(
          rowsByTitle: {
            'petronella': [
              _row('Petronella', id: '1'),
              _row('Petronella', id: '2'),
            ],
          },
        );
        final contraDb = _FakeOnlineService(
          rowsByTitle: {
            'petronella': [
              _row('Petronella', id: '55', source: OnlineSource.contraDb),
              _row('Petronella', id: '56', source: OnlineSource.contraDb),
            ],
          },
          source: OnlineSource.contraDb,
        );

        final resolved = (await resolveUnmatchedOnline(
          [_unmatched('Petronella')],
          service: callersBox,
          fallbacks: [contraDb],
          repos: repos,
        )).lines;

        final line = resolved.single;
        expect(line.resolution, PlaintextLineResolution.unmatched);
        expect(line.onlineCandidates, hasLength(4));
        expect(line.onlineCandidates.map((r) => r.id), ['1', '2', '55', '56']);
        expect(line.onlineCandidates.map((r) => r.source), [
          OnlineSource.callersBox,
          OnlineSource.callersBox,
          OnlineSource.contraDb,
          OnlineSource.contraDb,
        ]);
      },
    );

    test(
      'a primary-source fetch error is isolated: the fallback is still tried '
      'and can resolve the line',
      () async {
        final repos = openTestRepositories();
        final callersBox = _FakeOnlineService(throwOnSearch: true);
        final contraDb = _FakeOnlineService(
          rowsByTitle: {
            'money musk': [
              _row('Money Musk', id: '10600', source: OnlineSource.contraDb),
            ],
          },
          source: OnlineSource.contraDb,
        );

        final resolved = (await resolveUnmatchedOnline(
          [_unmatched('Money Musk')],
          service: callersBox,
          fallbacks: [contraDb],
          repos: repos,
        )).lines;

        expect(contraDb.searchedTitles, ['Money Musk']);
        expect(resolved.single.importedOnline, isTrue);
      },
    );

    test('multiple fallbacks are tried in the given order until one resolves '
        'confidently', () async {
      final repos = openTestRepositories();
      final callersBox = _FakeOnlineService(rowsByTitle: const {});
      final secondFallback = _FakeOnlineService(
        rowsByTitle: const {},
        source: OnlineSource.contraDb,
      );
      final thirdFallback = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [
            _row('Money Musk', id: '99', source: OnlineSource.contraDb),
          ],
        },
        source: OnlineSource.contraDb,
      );

      final resolved = (await resolveUnmatchedOnline(
        [_unmatched('Money Musk')],
        service: callersBox,
        fallbacks: [secondFallback, thirdFallback],
        repos: repos,
      )).lines;

      expect(secondFallback.searchedTitles, ['Money Musk']);
      expect(thirdFallback.searchedTitles, ['Money Musk']);
      expect(resolved.single.importedOnline, isTrue);
      expect(resolved.single.danceId, 'imported-money musk');
    });

    // Regression pin (raised in review of PR #959). `resolveUnmatchedOnline`
    // can run more than once on the same unresolved text — the screen re-feeds
    // its previous `_resolvedOverride` in on a second "Resolve unmatched
    // online" tap — so a line entering this function may already carry
    // `onlineCandidates` from an EARLIER pass. Both early-return branches in
    // `_resolveLineAcrossSources` (a #685 decline, and "every source missed
    // this time") must never let that stale list survive into the result.
    test('a #685 decline on a re-run clears a stale onlineCandidates list from '
        'an earlier ambiguous run', () async {
      final repos = openTestRepositories();
      final sharedFigures = [
        Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      ];
      await repos.dances.create(
        _localDance(id: 'local-existing', figures: sharedFigures),
      );
      final callersBox = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
        confidentTitles: {'money musk'},
        previewFiguresByTitle: {'money musk': sharedFigures}, // identical
      );

      // A stale line as it would exist after a PRIOR resolve pass found
      // Caller's Box ambiguous — carrying candidates this pass must not
      // repeat, since this pass's Caller's Box search is a #685 decline.
      final staleLine = ParsedProgramLine(
        text: 'Money Musk',
        resolution: PlaintextLineResolution.unmatched,
        onlineCandidates: [
          _row('Money Musk', id: '1'),
          _row('Money Musk', id: '2'),
        ],
      );

      final resolved = (await resolveUnmatchedOnline(
        [staleLine],
        service: callersBox,
        repos: repos,
      )).lines;

      final line = resolved.single;
      expect(line.resolution, PlaintextLineResolution.unmatched);
      expect(
        line.onlineCandidates,
        isEmpty,
        reason:
            'a #685 decline must clear stale candidates from an earlier '
            'ambiguous run, not just leave the line unchanged',
      );
    });

    test('a clean re-run miss clears a stale onlineCandidates list from an '
        'earlier ambiguous run', () async {
      final repos = openTestRepositories();
      // This run: no results at all (a clean miss), unlike the earlier run
      // that produced the stale candidates below.
      final callersBox = _FakeOnlineService(rowsByTitle: const {});

      final staleLine = ParsedProgramLine(
        text: 'Money Musk',
        resolution: PlaintextLineResolution.unmatched,
        onlineCandidates: [
          _row('Money Musk', id: '1'),
          _row('Money Musk', id: '2'),
        ],
      );

      final resolved = (await resolveUnmatchedOnline(
        [staleLine],
        service: callersBox,
        repos: repos,
      )).lines;

      final line = resolved.single;
      expect(line.resolution, PlaintextLineResolution.unmatched);
      expect(line.onlineCandidates, isEmpty);
    });
  });

  // ── 2026-10 audit, batch F12 (FAIL-2, INTAKE-4) ──────────────────────────
  group('stopping, progress and undo', () {
    test('an unreachable source stops the pass at the first title, without '
        'asking the fallback, and says so', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        searchError: const UrlFetchException(
          UrlFetchFailureReason.callersBoxUnreachable,
        ),
      );
      final fallback = _FakeOnlineService(source: OnlineSource.contraDb);

      final result = await resolveUnmatchedOnline(
        [_unmatched('One'), _unmatched('Two'), _unmatched('Three')],
        service: service,
        fallbacks: [fallback],
        repos: repos,
      );

      expect(result.stoppedAfterConnectionFailure, isTrue);
      expect(result.cancelled, isFalse);
      expect(service.searchedTitles, ['One']);
      expect(fallback.searchedTitles, isEmpty);
      expect(result.lines.map((l) => l.text), ['One', 'Two', 'Three']);
      expect(
        result.lines.map((l) => l.resolution),
        everyElement(PlaintextLineResolution.unmatched),
      );
    });

    test('a connection failure fetching the dance itself stops the pass '
        'too', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
          'two': [_row('Two', id: '2')],
        },
        loadErrors: {
          '1': const UrlFetchException(
            UrlFetchFailureReason.timeout,
            timeoutSeconds: 30,
          ),
        },
      );

      final result = await resolveUnmatchedOnline(
        [_unmatched('One'), _unmatched('Two')],
        service: service,
        repos: repos,
      );

      expect(result.stoppedAfterConnectionFailure, isTrue);
      expect(service.searchedTitles, ['One']);
    });

    test("a dance page that answers 404 is that dance's miss, not a "
        'connection failure', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
          'two': [_row('Two', id: '2')],
        },
        loadErrors: {
          '1': const UrlFetchException(
            UrlFetchFailureReason.httpStatus,
            statusCode: 404,
          ),
        },
      );

      final result = await resolveUnmatchedOnline(
        [_unmatched('One'), _unmatched('Two')],
        service: service,
        repos: repos,
      );

      expect(result.stoppedAfterConnectionFailure, isFalse);
      expect(service.searchedTitles, ['One', 'Two']);
      expect(result.lines[0].resolution, PlaintextLineResolution.unmatched);
      expect(result.lines[1].resolution, PlaintextLineResolution.matched);
    });

    test('reports progress over the unmatched lines and stops when '
        'cancelled', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService();
      final progress = <(int, int)>[];

      final result = await resolveUnmatchedOnline(
        [
          _unmatched('One'),
          const ParsedProgramLine(
            text: 'Local',
            resolution: PlaintextLineResolution.matched,
            danceId: 'd1',
            matchCount: 1,
          ),
          _unmatched('Two'),
          _unmatched('Three'),
        ],
        service: service,
        repos: repos,
        onProgress: (done, total) => progress.add((done, total)),
        isCancelled: () => service.searchedTitles.length >= 2,
      );

      expect(progress, [(0, 3), (1, 3), (2, 3)]);
      expect(result.cancelled, isTrue);
      expect(result.stoppedAfterConnectionFailure, isFalse);
      expect(service.searchedTitles, ['One', 'Two']);
      expect(result.lines, hasLength(4));
      expect(result.lines[3].text, 'Three');
    });

    test('every dance the pass writes is recorded, and rolling back removes '
        'them', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
        },
        commitForReal: true,
      );
      final rollback = ProgramImportRollback(repos);

      final result = await resolveUnmatchedOnline(
        [_unmatched('One')],
        service: service,
        repos: repos,
        rollback: rollback,
      );

      final danceId = result.lines.single.danceId!;
      expect(await repos.dances.getById(danceId), isNotNull);
      expect(rollback.isEmpty, isFalse);

      await rollback.rollBack();
      expect(await repos.dances.listAll(), isEmpty);
    });

    test("rolling back an auto-imported variation (#686) restores its "
        "original's links", () async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _localDance(
          id: 'local-existing',
          figures: [
            Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
          ],
        ),
      );
      final before = (await repos.dances.getById('local-existing'))!;
      final service = _FakeOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
        confidentTitles: {'money musk'},
        previewFiguresByTitle: {
          'money musk': [
            Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 8}),
          ],
        },
      );
      final rollback = ProgramImportRollback(repos);

      final danceId = await resolveConfidentOnlineDanceId(
        'Money Musk',
        service: service,
        repos: repos,
        rollback: rollback,
      );
      expect(danceId, isNotNull);

      await rollback.rollBack();
      expect(await repos.dances.getById(danceId!), isNull);
      final after = (await repos.dances.getById('local-existing'))!;
      expect(after.links, before.links);
    });

    test(
      'rolling back keeps a dance another program has linked since',
      () async {
        final repos = openTestRepositories();
        final service = _FakeOnlineService(
          rowsByTitle: {
            'one': [_row('One', id: '1')],
          },
          commitForReal: true,
        );
        final rollback = ProgramImportRollback(repos);
        final result = await resolveUnmatchedOnline(
          [_unmatched('One')],
          service: service,
          repos: repos,
          rollback: rollback,
        );
        final danceId = result.lines.single.danceId!;
        final now = DateTime.utc(2026, 10, 28);
        await repos.programs.create(
          Program(
            id: 'other',
            title: 'Built meanwhile',
            slots: [ProgramSlot(id: 's1', position: 0, danceId: danceId)],
            createdAt: now,
            updatedAt: now,
          ),
        );

        await rollback.rollBack();

        expect(await repos.dances.getById(danceId), isNotNull);
        expect(
          (await repos.programs.getById('other'))!.slots.single.danceId,
          danceId,
        );
      },
    );

    test("rolling back ignores the undone program's own tombstone", () async {
      // A program sync has published is tombstoned, not erased, and keeps its
      // slots — they must not read as "linked since".
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
        },
        commitForReal: true,
      );
      final rollback = ProgramImportRollback(repos);
      final result = await resolveUnmatchedOnline(
        [_unmatched('One')],
        service: service,
        repos: repos,
        rollback: rollback,
      );
      final danceId = result.lines.single.danceId!;
      final now = DateTime.utc(2026, 10, 28);
      await repos.programs.create(
        Program(
          id: 'imported',
          title: 'Imported',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: danceId)],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repos.db.customStatement(
        "INSERT INTO published_records (kind, record_id) "
        "VALUES ('program', 'imported')",
      );
      await repos.programs.hardDelete(['imported']);
      // Precondition: the tombstone really does still hold the slot.
      expect(
        (await repos.programs.getById(
          'imported',
          includeDeleted: true,
        ))!.slots.single.danceId,
        danceId,
      );

      await rollback.rollBack(undoneProgramId: 'imported');

      expect(await repos.dances.getById(danceId), isNull);
    });

    test('a two-dance session with one dance linked since removes only the '
        'other', () async {
      final repos = openTestRepositories();
      ImportRecordPlan plan(String title, String externalId) =>
          ImportRecordPlan(
            draft: StructuredDraft(
              dance: _localDance(
                id: '',
                figures: const [],
              ).copyWith(title: title),
              raw: RawRecord(
                source: ProvenanceSource.callersbox,
                externalId: externalId,
                payload: '{}',
              ),
            ),
            verdict: DedupeVerdict.isNew(),
          );
      final session = await ImportPipeline(repos.dances, repos.choreographers)
          .commit(
            ImportBatchResult(records: [plan('Alpha', 'a'), plan('Beta', 'b')]),
            now: DateTime.utc(2026, 10, 28),
            newId: uuidV4,
          );
      final [alpha, beta] = session.insertedDanceIds;
      final rollback = ProgramImportRollback(repos);
      await rollback.record(session);
      final now = DateTime.utc(2026, 10, 28);
      await repos.programs.create(
        Program(
          id: 'other',
          title: 'Built meanwhile',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: alpha)],
          createdAt: now,
          updatedAt: now,
        ),
      );

      await rollback.rollBack();

      expect(await repos.dances.getById(alpha), isNotNull);
      expect(await repos.dances.getById(beta), isNull);
    });

    test('a session recorded after rolling back is reverted at once', () async {
      final repos = openTestRepositories();
      final service = _FakeOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
        },
        commitForReal: true,
      );
      final rollback = ProgramImportRollback(repos);
      await rollback.rollBack();

      final result = await resolveUnmatchedOnline(
        [_unmatched('One')],
        service: service,
        repos: repos,
        rollback: rollback,
      );

      expect(result.lines.single.danceId, isNotNull);
      expect(await repos.dances.listAll(), isEmpty);
    });
  });
}
