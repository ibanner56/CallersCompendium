import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/title_list_import.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Counts every call so the bounding guards can be asserted on **requests made**
/// rather than on results, which is the only way to prove a cap fired *before*
/// the network was touched.
class _CountingOnlineService implements OnlineSearchService {
  _CountingOnlineService({
    this.rowsByTitle = const {},
    this.throwOnSearchFor = const {},
    this.throwOnLoadFor = const {},
  });

  /// Search rows keyed by the lower-cased query title.
  final Map<String, List<OnlineSearchResultRow>> rowsByTitle;

  /// Lower-cased titles whose `search` throws (simulates an unreachable source).
  final Set<String> throwOnSearchFor;

  /// Result ids whose `loadPreview` throws (simulates a per-dance fetch that
  /// fails after a successful search).
  final Set<String> throwOnLoadFor;

  final searchedTitles = <String>[];
  final loadedIds = <String>[];

  @override
  OnlineSource get source => OnlineSource.callersBox;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    searchedTitles.add(query.title);
    final key = query.title.trim().toLowerCase();
    if (throwOnSearchFor.contains(key)) throw Exception('offline');
    return rowsByTitle[key] ?? const [];
  }

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    loadedIds.add(result.id);
    if (throwOnLoadFor.contains(result.id)) throw Exception('not published');
    final plan = _planFor(result.name);
    return OnlinePreview(
      result: result,
      detail: _detailFor(plan.draft.dance),
      plan: plan,
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async {
    // The Collection title-list path must never reach this. Failing loudly here
    // is what turns "it accidentally commits" into a red test rather than a
    // silent write.
    throw StateError(
      'resolveTitleList must never commit — it plans for the review screen',
    );
  }
}

ImportRecordPlan _planFor(String title, {DedupeVerdict? verdict}) =>
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
      verdict: verdict ?? DedupeVerdict.isNew(),
    );

DanceDetailData _detailFor(Dance dance) => DanceDetailData(
  dance: dance,
  authorNames: const [],
  tagNames: const [],
  customFields: const [],
  relatedDanceTitles: const {},
  sourcesById: const {},
  callingHistory: const [],
  crossRefLinker: DanceTitleLinker.build(const [], excludeId: ''),
);

OnlineSearchResultRow _row(String name, {String id = '1'}) =>
    OnlineSearchResultRow(
      source: OnlineSource.callersBox,
      id: id,
      name: name,
      author: '',
      formation: '',
    );

Dance _localDance({
  required String id,
  required String title,
  List<String> authorIds = const [],
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
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

/// Counts the full-collection reads a resolution performs, so "we don't do the
/// expensive thing when there's nothing to do" is asserted rather than assumed.
///
/// Subclasses the real repositories (rather than faking them) so the counted
/// calls still hit a real database and the rest of the resolution behaves
/// exactly as in production.
class _CountingDances extends DanceRepository {
  _CountingDances(super.db, super.taxonomy);

  int listAllCalls = 0;
  int listIdsAndTitlesCalls = 0;

  @override
  Future<List<Dance>> listAll({bool includeDeleted = false}) {
    listAllCalls++;
    return super.listAll(includeDeleted: includeDeleted);
  }

  @override
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) {
    listIdsAndTitlesCalls++;
    return super.listIdsAndTitles(includeDeleted: includeDeleted);
  }
}

class _CountingChoreographers extends ChoreographerRepository {
  _CountingChoreographers(super.db);

  int listAllCalls = 0;

  @override
  Future<List<Choreographer>> listAll() {
    listAllCalls++;
    return super.listAll();
  }
}

class _CountingRepositories extends CompendiumRepositories {
  _CountingRepositories(CompendiumDatabase db)
    : countedDances = _CountingDances(db, contraTaxonomy),
      countedChoreographers = _CountingChoreographers(db),
      super(db, contraTaxonomy);

  final _CountingDances countedDances;
  final _CountingChoreographers countedChoreographers;

  @override
  DanceRepository get dances => countedDances;

  @override
  ChoreographerRepository get choreographers => countedChoreographers;

  /// Reads that scan the whole collection: `buildDedupeIndex` performs one of
  /// each, and it is the pair this guard exists to prevent on the no-op path.
  int get fullCollectionReads =>
      countedDances.listAllCalls + countedChoreographers.listAllCalls;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('preflightTitleList (bounds)', () {
    test('trims, drops blank lines, and preserves paste order', () {
      final pre = preflightTitleList('  Money Musk \n\n\t\n Petronella\n');
      expect(pre.rejection, isNull);
      expect(pre.searchableTitles, ['Money Musk', 'Petronella']);
    });

    test('folds case-insensitive duplicates onto the first occurrence', () {
      final pre = preflightTitleList(
        'Money Musk\nMONEY MUSK\n money musk \nPetronella',
      );
      expect(pre.searchableTitles, ['Money Musk', 'Petronella']);
      expect(pre.duplicateLines, 2);
    });

    test(
      'a line over the per-title cap is kept as a row but not searchable',
      () {
        final long = 'x' * (kMaxTitleLength + 1);
        final pre = preflightTitleList('Money Musk\n$long');
        expect(pre.rejection, isNull);
        expect(pre.searchableTitles, ['Money Musk']);
        expect(pre.lines, hasLength(2));
        expect(pre.lines.last.rejected, TitleListNotFoundReason.lineTooLong);
        // Boundary: exactly at the cap is accepted.
        final atCap = preflightTitleList('y' * kMaxTitleLength);
        expect(atCap.searchableTitles, hasLength(1));
      },
    );

    test('a repeated over-long line is folded like any other duplicate', () {
      final long = 'x' * (kMaxTitleLength + 1);
      final pre = preflightTitleList('$long\n$long\n$long\nMoney Musk');

      // One row for the long line, not three: the review's premise is that
      // repeats were folded, and a line being unsearchable does not exempt it.
      final tooLong = pre.lines
          .where((l) => l.rejected == TitleListNotFoundReason.lineTooLong)
          .toList();
      expect(tooLong, hasLength(1));
      // …and the count that tells the user folding happened includes them.
      expect(pre.duplicateLines, 2);
      expect(pre.searchableTitles, ['Money Musk']);
    });

    test('an over-long line does not consume the fan-out budget', () {
      // The cap bounds requests, and an over-long line is never searched — so
      // it must not push a legitimate list over the limit.
      final long = 'y' * (kMaxTitleLength + 1);
      final titles = [
        for (var i = 0; i < kMaxTitleListTitles; i++) 'Dance $i',
      ].join('\n');
      final pre = preflightTitleList('$long\n$titles');

      expect(pre.rejection, isNull);
      expect(pre.searchableTitles, hasLength(kMaxTitleListTitles));
    });

    test(
      'refuses a paste over the distinct-title cap, counted after dedupe',
      () {
        final overCap = [
          for (var i = 0; i <= kMaxTitleListTitles; i++) 'Dance $i',
        ].join('\n');
        final refused = preflightTitleList(overCap);
        expect(refused.rejection, TitleListRejection.tooManyTitles);
        expect(refused.rejectionCount, kMaxTitleListTitles + 1);
        expect(refused.lines, isEmpty);

        // Exactly at the cap is accepted (the boundary is inclusive)…
        final atCap = [
          for (var i = 0; i < kMaxTitleListTitles; i++) 'Dance $i',
        ].join('\n');
        expect(preflightTitleList(atCap).rejection, isNull);

        // …and repeating ONE title far past the cap is one title, not a refusal,
        // because the cap counts distinct titles after de-duplication.
        final repeated = List.filled(
          kMaxTitleListTitles * 5,
          'Money Musk',
        ).join('\n');
        final deduped = preflightTitleList(repeated);
        expect(deduped.rejection, isNull);
        expect(deduped.searchableTitles, ['Money Musk']);
      },
    );

    test('refuses a paste over the raw character cap', () {
      final huge = 'a\n' * kMaxTitleListChars;
      final refused = preflightTitleList(huge);
      expect(refused.rejection, TitleListRejection.textTooLong);
      expect(refused.rejectionCount, greaterThan(kMaxTitleListChars));
      expect(refused.lines, isEmpty);
    });
  });

  group('resolveTitleList', () {
    test('T1: a title already in the collection is reported, not dropped, and '
        'is never searched online', () async {
      final repos = openTestRepositories();
      final author = Choreographer(id: 'a1', name: 'Ted Sannella');
      await repos.choreographers.upsert(author);
      await repos.dances.create(
        _localDance(id: 'd1', title: 'Fiddleheads', authorIds: const ['a1']),
      );
      final service = _CountingOnlineService();

      final result = await resolveTitleList(
        'Fiddleheads',
        service: service,
        repos: repos,
      );

      expect(result.batch.records, isEmpty);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.group, TitleListGroup.alreadyInCollection);
      expect(row.title, 'Fiddleheads');
      expect(row.localMatchCount, 1);
      // The author is what lets a caller tell a real match from a different
      // dance that happens to share a title.
      expect(row.localAuthors, ['Ted Sannella']);
      // Owning it means we never ask the source about it at all.
      expect(service.searchedTitles, isEmpty);
    });

    test('T1b: several local dances sharing the title still count as owned, '
        'with the count rather than a list of authors', () async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Heartbeat'));
      await repos.dances.create(_localDance(id: 'd2', title: 'heartbeat'));
      final service = _CountingOnlineService();

      final result = await resolveTitleList(
        'Heartbeat',
        service: service,
        repos: repos,
      );

      final row = result.rows.single;
      expect(row.group, TitleListGroup.alreadyInCollection);
      expect(row.localMatchCount, 2);
      expect(row.localAuthors, isEmpty);
      expect(service.searchedTitles, isEmpty);
    });

    test('T2: every way an online lookup can miss becomes its own reported '
        'reason, not a silent drop', () async {
      final repos = openTestRepositories();
      final service = _CountingOnlineService(
        rowsByTitle: {
          // no results at all
          'nothing here': const [],
          // results, but nothing titled exactly this
          'fuzzy only': [_row('Fuzzy Only Reel')],
          // two exact hits
          'twice over': [
            _row('Twice Over', id: '1'),
            _row('Twice Over', id: '2'),
          ],
          // search succeeds, per-dance fetch fails
          'bad fetch': [_row('Bad Fetch', id: '99')],
        },
        throwOnSearchFor: {'offline title'},
        throwOnLoadFor: {'99'},
      );

      final result = await resolveTitleList(
        'Nothing Here\nFuzzy Only\nTwice Over\nBad Fetch\nOffline Title',
        service: service,
        repos: repos,
      );

      expect(result.batch.records, isEmpty);
      expect(result.rows, hasLength(5));
      expect(
        result.rows.map((r) => r.group),
        everyElement(TitleListGroup.notFound),
      );
      expect(result.rows.map((r) => r.reason), [
        TitleListNotFoundReason.noResults,
        TitleListNotFoundReason.noExactMatch,
        TitleListNotFoundReason.multipleExactMatches,
        TitleListNotFoundReason.fetchError,
        TitleListNotFoundReason.fetchError,
      ]);
      // Paste order is preserved across the whole list.
      expect(result.rows.first.title, 'Nothing Here');
      expect(result.rows.last.title, 'Offline Title');
    });

    test('T3: a unique exact hit is PLANNED, never committed — nothing is '
        'written to the collection during resolution', () async {
      final repos = openTestRepositories();
      final service = _CountingOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );

      final result = await resolveTitleList(
        'Money Musk',
        service: service,
        repos: repos,
      );

      expect(result.batch.records, hasLength(1));
      expect(result.batch.records.single.draft.dance.title, 'Money Musk');
      expect(result.rows.single.group, TitleListGroup.toImport);
      expect(result.rows.single.planIndex, 0);
      // The whole point: resolution is non-destructive. The program path would
      // have imported this already; here the review screen owns the commit.
      expect(
        await repos.dances.listAll(),
        isEmpty,
        reason: 'resolveTitleList must plan only — the review screen commits',
      );
    });

    test(
      'T4a: a paste over the title cap is refused before ANY request',
      () async {
        final repos = openTestRepositories();
        final service = _CountingOnlineService();
        final overCap = [
          for (var i = 0; i <= kMaxTitleListTitles; i++) 'Dance $i',
        ].join('\n');

        await expectLater(
          resolveTitleList(overCap, service: service, repos: repos),
          throwsA(
            isA<TitleListTooLargeException>()
                .having(
                  (e) => e.rejection,
                  'rejection',
                  TitleListRejection.tooManyTitles,
                )
                .having((e) => e.count, 'count', kMaxTitleListTitles + 1),
          ),
        );
        expect(
          service.searchedTitles,
          isEmpty,
          reason: 'the fan-out cap must fire before the network is touched',
        );
        expect(service.loadedIds, isEmpty);
      },
    );

    test('T4a2: a paste over the raw character cap is refused before ANY '
        'request', () async {
      final repos = openTestRepositories();
      final service = _CountingOnlineService();

      await expectLater(
        resolveTitleList(
          'a\n' * kMaxTitleListChars,
          service: service,
          repos: repos,
        ),
        throwsA(isA<TitleListTooLargeException>()),
      );
      expect(service.searchedTitles, isEmpty);
    });

    test('T4b: an over-long line is reported without issuing a request, and '
        'the rest of the list still resolves', () async {
      final repos = openTestRepositories();
      final long = 'x' * (kMaxTitleLength + 1);
      final service = _CountingOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );

      final result = await resolveTitleList(
        '$long\nMoney Musk',
        service: service,
        repos: repos,
      );

      expect(service.searchedTitles, ['Money Musk']);
      expect(result.rows.first.group, TitleListGroup.notFound);
      expect(result.rows.first.reason, TitleListNotFoundReason.lineTooLong);
      expect(result.rows.last.group, TitleListGroup.toImport);
    });

    test('T4c: repeated titles cost exactly one lookup', () async {
      final repos = openTestRepositories();
      final service = _CountingOnlineService(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );

      final result = await resolveTitleList(
        'Money Musk\nMONEY MUSK\nmoney musk',
        service: service,
        repos: repos,
      );

      expect(service.searchedTitles, ['Money Musk']);
      expect(service.loadedIds, ['10600']);
      expect(result.rows, hasLength(1));
      expect(result.duplicateLines, 2);
    });

    test('T4d: one title failing does not abort the batch', () async {
      final repos = openTestRepositories();
      final service = _CountingOnlineService(
        rowsByTitle: {
          'good one': [_row('Good One', id: '1')],
          'good two': [_row('Good Two', id: '2')],
        },
        throwOnSearchFor: {'bad one'},
      );

      final result = await resolveTitleList(
        'Good One\nBad One\nGood Two',
        service: service,
        repos: repos,
      );

      expect(service.searchedTitles, ['Good One', 'Bad One', 'Good Two']);
      expect(result.batch.records, hasLength(2));
      expect(result.countIn(TitleListGroup.toImport), 2);
      expect(result.countIn(TitleListGroup.notFound), 1);
      expect(result.rows[1].reason, TitleListNotFoundReason.fetchError);
    });

    test(
      'reports progress and stops on cancel without further requests',
      () async {
        final repos = openTestRepositories();
        final service = _CountingOnlineService(
          rowsByTitle: {
            'one': [_row('One', id: '1')],
            'two': [_row('Two', id: '2')],
            'three': [_row('Three', id: '3')],
          },
        );
        final progress = <(int, int)>[];
        var seen = 0;

        await expectLater(
          resolveTitleList(
            'One\nTwo\nThree',
            service: service,
            repos: repos,
            onProgress: (done, total) => progress.add((done, total)),
            // Cancel after the first title has been looked up.
            isCancelled: () => seen++ >= 1,
          ),
          throwsA(isA<TitleListCancelled>()),
        );

        expect(progress.first, (0, 3));
        expect(
          service.searchedTitles,
          ['One'],
          reason: 'cancel must stop the batch before the next request',
        );
      },
    );

    test('a mixed paste splits cleanly across all three groups, in paste '
        'order', () async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Owned Dance'));
      final service = _CountingOnlineService(
        rowsByTitle: {
          'importable': [_row('Importable', id: '7')],
          'missing': const [],
        },
      );

      final result = await resolveTitleList(
        'Owned Dance\nImportable\nMissing',
        service: service,
        repos: repos,
      );

      expect(result.rows.map((r) => r.group), [
        TitleListGroup.alreadyInCollection,
        TitleListGroup.toImport,
        TitleListGroup.notFound,
      ]);
      expect(result.countIn(TitleListGroup.alreadyInCollection), 1);
      expect(result.countIn(TitleListGroup.toImport), 1);
      expect(result.countIn(TitleListGroup.notFound), 1);
      // Only the unmatched titles cost a request.
      expect(service.searchedTitles, ['Importable', 'Missing']);
    });
  });

  group('no full-collection read when there is nothing to look up', () {
    // `buildDedupeIndex` reads every dance and every choreographer. It exists to
    // dedupe *incoming* records, so a paste with no unmatched titles has nothing
    // to dedupe against — and that is exactly the path a user expects to be
    // instant. Raised in review of PR #842.

    test('a paste where every title is already owned performs zero '
        'full-collection reads', () async {
      final repos = _CountingRepositories(
        CompendiumDatabase(NativeDatabase.memory()),
      );
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      await repos.dances.create(_localDance(id: 'd2', title: 'Petronella'));
      final service = _CountingOnlineService();

      final result = await resolveTitleList(
        'Fiddleheads\nPetronella',
        service: service,
        repos: repos,
      );

      expect(result.countIn(TitleListGroup.alreadyInCollection), 2);
      expect(service.searchedTitles, isEmpty);
      expect(
        repos.fullCollectionReads,
        0,
        reason:
            'nothing needed deduping, so the index was never worth building',
      );
      // The batch carries no snapshot, because none was built.
      expect(result.batch.dedupeIndex, isNull);
    });

    test('a paste with something to look up still builds the snapshot exactly '
        'once, however many titles it has', () async {
      final repos = _CountingRepositories(
        CompendiumDatabase(NativeDatabase.memory()),
      );
      final service = _CountingOnlineService(
        rowsByTitle: {
          'one': [_row('One', id: '1')],
          'two': [_row('Two', id: '2')],
          'three': [_row('Three', id: '3')],
        },
      );

      final result = await resolveTitleList(
        'One\nTwo\nThree',
        service: service,
        repos: repos,
      );

      expect(result.countIn(TitleListGroup.toImport), 3);
      expect(repos.countedDances.listAllCalls, 1);
      expect(repos.countedChoreographers.listAllCalls, 1);
      expect(
        result.batch.dedupeIndex,
        isNotNull,
        reason: 'three titles were resolved against one shared snapshot',
      );
    });

    test(
      'a paste of only over-long lines reads nothing from the collection',
      () async {
        final repos = _CountingRepositories(
          CompendiumDatabase(NativeDatabase.memory()),
        );
        await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
        final service = _CountingOnlineService();
        final long = 'x' * (kMaxTitleLength + 1);

        final result = await resolveTitleList(
          '$long\n${long}y',
          service: service,
          repos: repos,
        );

        // Both lines are reported, so nothing is lost…
        expect(result.countIn(TitleListGroup.notFound), 2);
        expect(
          result.rows.map((r) => r.reason),
          everyElement(TitleListNotFoundReason.lineTooLong),
        );
        // …but nothing was searched and the collection was never read: stage 1
        // has nothing to match when no line survived the per-line bounds.
        expect(service.searchedTitles, isEmpty);
        expect(
          repos.countedDances.listIdsAndTitlesCalls,
          0,
          reason:
              'no searchable title means stage 1 has nothing to match against',
        );
        expect(repos.fullCollectionReads, 0);
      },
    );

    test('an over-cap paste is refused before any collection read', () async {
      final repos = _CountingRepositories(
        CompendiumDatabase(NativeDatabase.memory()),
      );
      final service = _CountingOnlineService();

      await expectLater(
        resolveTitleList(
          [
            for (var i = 0; i <= kMaxTitleListTitles; i++) 'Dance $i',
          ].join('\n'),
          service: service,
          repos: repos,
        ),
        throwsA(isA<TitleListTooLargeException>()),
      );
      expect(repos.fullCollectionReads, 0);
      expect(repos.countedDances.listIdsAndTitlesCalls, 0);
    });
  });
}
