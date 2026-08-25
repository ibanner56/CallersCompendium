import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/title_list_import.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A canned online source: no network, and `import` throws so an accidental
/// commit during resolution is a loud failure rather than a silent write.
class _FakeOnline implements OnlineSearchService {
  _FakeOnline({this.rowsByTitle = const {}});

  final Map<String, List<OnlineSearchResultRow>> rowsByTitle;
  final searchedTitles = <String>[];

  @override
  OnlineSource get source => OnlineSource.callersBox;

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
    DedupeIndex? index,
  }) async {
    final plan = _plan(result.name);
    return OnlinePreview(
      result: result,
      detail: _detail(plan.draft.dance),
      plan: plan,
    );
  }

  @override
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  }) async => throw StateError('the title-list path must not commit directly');
}

ImportRecordPlan _plan(String title, {DedupeVerdict? verdict}) =>
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

DanceDetailData _detail(Dance dance) => DanceDetailData(
  dance: dance,
  authorNames: const [],
  tagNames: const [],
  customFields: const [],
  relatedDanceTitles: const {},
  sourcesById: const {},
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

/// The title-list source on its own, so the dropdown is hidden and the pasted
/// input is the only affordance under test.
List<ImportSource> _titleListOnly() => [
  defaultImportSources().firstWhere(
    (s) => s.kind == ImportSourceKind.titleList,
  ),
];

/// The title-list source plus the generic-JSON source, so a test can run a
/// title-list import and then plan a different source in the same screen.
List<ImportSource> _titleListAndJson() => [
  defaultImportSources().firstWhere(
    (s) => s.kind == ImportSourceKind.titleList,
  ),
  defaultImportSources().firstWhere(
    (s) => s.kind == ImportSourceKind.genericJson,
  ),
];

/// A one-dance Caller's Compendium archive — the payload `GenericJsonAdapter`
/// consumes.
String _archivePayload(String title) => encodeArchive(
  CompendiumArchive(
    exportedAt: DateTime.utc(2026, 7, 15),
    dances: [
      Dance(
        id: 'incoming',
        title: title,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
  ),
);

/// Goes back to the input step, switches to the generic-JSON source, and plans
/// a one-dance archive through it.
Future<void> _thenImportJson(WidgetTester tester, String title) async {
  await tester.tap(find.byKey(const ValueKey('import-back-to-input')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('import-source-select')));
  await tester.pumpAndSettle();
  await tester.tap(find.text("a Caller's Compendium JSON file").last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('import-paste-field')),
    _archivePayload(title),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('import-continue')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required OnlineSearchService service,
  List<ImportSource>? sources,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          sources: sources ?? _titleListOnly(),
          onlineService: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Types [titles] into the paste field and taps "Review import".
Future<void> _paste(WidgetTester tester, String titles) async {
  await tester.enterText(
    find.byKey(const ValueKey('import-titles-field')),
    titles,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('import-continue')));
  await tester.pumpAndSettle();
}

/// Counts `listIdsAndTitles` so the review screen's own no-op read is
/// assertable. Subclasses the real repository, so behaviour is unchanged.
class _CountingDances extends DanceRepository {
  _CountingDances(super.db, super.taxonomy);

  int listIdsAndTitlesCalls = 0;

  @override
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) {
    listIdsAndTitlesCalls++;
    return super.listIdsAndTitles(includeDeleted: includeDeleted);
  }
}

class _CountingRepositories extends CompendiumRepositories {
  _CountingRepositories(CompendiumDatabase db)
    : countedDances = _CountingDances(db, contraTaxonomy),
      super(db, contraTaxonomy);

  final _CountingDances countedDances;

  @override
  DanceRepository get dances => countedDances;
}

void main() {
  group('pasted title list input (issue #823)', () {
    testWidgets('shows a title paste box and none of the file/URL '
        'affordances', (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, service: _FakeOnline());

      expect(find.byKey(const ValueKey('import-titles-field')), findsOneWidget);
      // A pasted list has nothing to pick or fetch, so those affordances must
      // not be offered.
      expect(find.byKey(const ValueKey('import-choose-file')), findsNothing);
      expect(find.byKey(const ValueKey('import-url-field')), findsNothing);
      expect(find.byKey(const ValueKey('import-fetch-url')), findsNothing);
    });

    testWidgets('counts distinct titles live and reports folded duplicates', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, service: _FakeOnline());

      await tester.enterText(
        find.byKey(const ValueKey('import-titles-field')),
        'Money Musk\nMONEY MUSK\n\nPetronella\n',
      );
      await tester.pumpAndSettle();

      expect(find.text('2 titles'), findsOneWidget);
      expect(find.text('1 repeated title ignored'), findsOneWidget);
    });

    testWidgets('T4a (UI): a paste over the cap is refused in place and no '
        'search is made', (tester) async {
      final repos = openTestRepositories();
      final service = _FakeOnline();
      await _pump(tester, repos, service: service);

      await _paste(
        tester,
        [for (var i = 0; i <= kMaxTitleListTitles; i++) 'Dance $i'].join('\n'),
      );

      // Still on the input screen, with the list intact and an explanation.
      expect(find.byKey(const ValueKey('import-titles-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('import-titles-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
      expect(
        service.searchedTitles,
        isEmpty,
        reason: 'a refused paste must never reach the network',
      );
    });
  });

  group('pasted title list review (issue #823)', () {
    testWidgets('T1: a title already in the collection is shown in its own '
        'group rather than vanishing', (tester) async {
      final repos = openTestRepositories();
      final author = Choreographer(id: 'a1', name: 'Ted Sannella');
      // ignore: unused_result
      await repos.choreographers.upsert(author);
      await repos.dances.create(
        _localDance(id: 'd1', title: 'Fiddleheads', authorIds: const ['a1']),
      );
      final service = _FakeOnline(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );
      await _pump(tester, repos, service: service);

      await _paste(tester, 'Fiddleheads\nMoney Musk');

      // The importable title got an ordinary review row…
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      // …and the owned one is present and explained, not dropped.
      expect(
        find.byKey(const ValueKey('import-titles-group-owned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-titles-owned-Fiddleheads')),
        findsOneWidget,
      );
      expect(
        find.text('You already have this, by Ted Sannella.'),
        findsOneWidget,
      );
      expect(find.text('1 already in your collection'), findsWidgets);
    });

    testWidgets('T2: a title nothing was found for is shown with its reason '
        'rather than vanishing', (tester) async {
      final repos = openTestRepositories();
      final service = _FakeOnline(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
          'ghost dance': const [],
        },
      );
      await _pump(tester, repos, service: service);

      await _paste(tester, 'Money Musk\nGhost Dance');

      expect(
        find.byKey(const ValueKey('import-titles-group-not-found')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-titles-not-found-Ghost Dance')),
        findsOneWidget,
      );
      expect(
        find.text("The Caller's Box has no dance by this name."),
        findsOneWidget,
      );
    });

    testWidgets('T3: resolution writes nothing — the collection is untouched '
        'until Import is tapped, and an ambiguous row defaults to skip', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final service = _FakeOnline(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
        },
      );
      await _pump(tester, repos, service: service);

      await _paste(tester, 'Money Musk');

      // Reached the review with a row to act on…
      expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      // …and NOTHING has been written. Reusing the program resolver as-is
      // would have imported this dance already, leaving nothing to review.
      expect(
        await repos.dances.listAll(),
        isEmpty,
        reason: 'the batch review owns the commit; resolution must not write',
      );

      // Committing from the review is what writes.
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();
      expect(
        (await repos.dances.listAll()).map((d) => d.title),
        contains('Money Musk'),
      );
    });

    testWidgets('T5: a list with nothing importable still shows the answer '
        'instead of dead-ending on "no dances found"', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(rowsByTitle: const {'ghost dance': []});
      await _pump(tester, repos, service: service);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await _paste(tester, 'Fiddleheads\nGhost Dance');

      // The generic dead end must NOT be what she sees.
      expect(find.text(l10n.importReviewNoDancesTitle), findsNothing);
      expect(
        find.byKey(const ValueKey('import-titles-nothing-to-import')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-titles-group-owned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-titles-group-not-found')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-titles-summary')),
        findsOneWidget,
      );
    });

    testWidgets('the result dialog keeps the already-owned / not-found counts '
        'so they survive the screen closing', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(
        rowsByTitle: {
          'money musk': [_row('Money Musk', id: '10600')],
          'ghost dance': const [],
        },
      );
      await _pump(tester, repos, service: service);

      await _paste(tester, 'Fiddleheads\nMoney Musk\nGhost Dance');
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-summary-AlreadyOwned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-summary-NotFound')),
        findsOneWidget,
      );
      expect(find.text('Already in your collection: 1'), findsOneWidget);
      expect(find.text('Not found: 1'), findsOneWidget);
    });
  });

  group('a title-list resolution must not outlive its plan (review of #842)', () {
    // Raised in review: `_titleList` had clearing discipline at one site while
    // `_titleListError` had it at three, so a resolution could survive into a
    // different plan. The fix couples `_titleList` to `_batch` in `_adoptBatch`,
    // the single place both are assigned.
    //
    // Falsification: reverting is the wrong target (pre-#823 code has no
    // `_titleList` at all and would go red incidentally). These mutate out the
    // fix instead — the naive "clear only the error" version — and catch that.

    testWidgets('a later import from another source does not inherit the title '
        'list\'s groups', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(rowsByTitle: const {'ghost dance': []});
      await _pump(
        tester,
        repos,
        service: service,
        sources: _titleListAndJson(),
      );

      // A paste where nothing is importable: owned + not-found groups only.
      await _paste(tester, 'Fiddleheads\nGhost Dance');
      expect(
        find.byKey(const ValueKey('import-titles-group-owned')),
        findsOneWidget,
      );

      await _thenImportJson(tester, 'Brand New Reel');

      // The JSON import's review is its own.
      expect(find.byKey(const ValueKey('import-row-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('import-titles-group-owned')),
        findsNothing,
        reason: 'a JSON import has no already-in-your-collection group',
      );
      expect(
        find.byKey(const ValueKey('import-titles-group-not-found')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('import-titles-summary')), findsNothing);
    });

    testWidgets('nor does its result dialog inherit the title list\'s counts', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(rowsByTitle: const {'ghost dance': []});
      await _pump(
        tester,
        repos,
        service: service,
        sources: _titleListAndJson(),
      );

      await _paste(tester, 'Fiddleheads\nGhost Dance');
      await _thenImportJson(tester, 'Brand New Reel');
      await tester.tap(find.byKey(const ValueKey('import-commit-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('import-summary-AlreadyOwned')),
        findsNothing,
        reason: 'a JSON import has no "already in your collection" answer',
      );
      expect(
        find.byKey(const ValueKey('import-summary-NotFound')),
        findsNothing,
      );
    });

    testWidgets('the nothing-importable review offers a way back, so the '
        'answer is not a dead end', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(rowsByTitle: const {'ghost dance': []});
      await _pump(tester, repos, service: service);

      await _paste(tester, 'Fiddleheads\nGhost Dance');
      expect(
        find.byKey(const ValueKey('import-back-to-input')),
        findsOneWidget,
        reason:
            'there is no Import button here; without Back the only way on '
            'is to close the whole import',
      );

      await tester.tap(find.byKey(const ValueKey('import-back-to-input')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('import-titles-field')), findsOneWidget);
    });
  });

  group('review round 2 (suppressed findings)', () {
    testWidgets('over-long lines are still counted as titles in the live '
        'count', (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, service: _FakeOnline());
      final long = 'x' * (kMaxTitleLength + 1);

      await tester.enterText(
        find.byKey(const ValueKey('import-titles-field')),
        '$long\n${long}y',
      );
      await tester.pumpAndSettle();

      // These two will never be searched, but they are titles the user pasted
      // and the review lists them both — so reporting "No titles yet" here would
      // contradict the very next screen.
      expect(find.text('2 titles'), findsOneWidget);
      expect(find.text('No titles yet'), findsNothing);
    });

    testWidgets('the raw-size refusal does not cite the title-count cap', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final service = _FakeOnline();
      await _pump(tester, repos, service: service);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Trips the character cap with far fewer than kMaxTitleListTitles titles
      // (one distinct title, repeated), so a message naming that limit would
      // misdescribe why the paste was refused.
      final line = 'a' * (kMaxTitleLength - 1);
      final huge = List.filled(
        kMaxTitleListChars ~/ kMaxTitleLength + 2,
        line,
      ).join('\n');
      await _paste(tester, huge);

      expect(find.byKey(const ValueKey('import-titles-error')), findsOneWidget);
      expect(find.text(l10n.importTitleListTextTooLong), findsOneWidget);
      expect(
        find.textContaining('$kMaxTitleListTitles'),
        findsNothing,
        reason: 'this is the paste-length cap, not the title-count cap',
      );
      expect(service.searchedTitles, isEmpty);
    });

    testWidgets('two preselected sources fail fast rather than picking by '
        'position', (tester) async {
      final repos = openTestRepositories();
      final base = defaultImportSources();
      ImportSource alsoPreselected(ImportSource s) => ImportSource(
        kind: s.kind,
        adapterFactory: s.adapterFactory,
        preselected: true,
      );

      await _pump(
        tester,
        repos,
        service: _FakeOnline(),
        sources: [alsoPreselected(base[0]), alsoPreselected(base[1])],
      );

      // Two preselected sources make the opening selection order-dependent
      // again — the coupling `preselected` exists to break — so it must fail
      // loudly in debug rather than silently pick by position.
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('no title lookup for a review with no rows (review of #842)', () {
    testWidgets('a paste with nothing importable does not load the '
        'collection\'s titles', (tester) async {
      final repos = _CountingRepositories(openWidgetTestDatabase());
      await repos.dances.create(_localDance(id: 'd1', title: 'Fiddleheads'));
      final service = _FakeOnline(rowsByTitle: const {'ghost dance': []});
      await _pump(tester, repos, service: service);

      // Resolution itself reads the collection once (the local-match stage), so
      // measure only what the review screen adds on top of that.
      final before = repos.countedDances.listIdsAndTitlesCalls;
      await _paste(tester, 'Fiddleheads\nGhost Dance');

      expect(
        find.byKey(const ValueKey('import-titles-group-owned')),
        findsOneWidget,
      );
      expect(
        repos.countedDances.listIdsAndTitlesCalls - before,
        1,
        reason:
            'only the local-match stage should read titles; an empty batch '
            'has no candidate rows to name',
      );
    });
  });
}
