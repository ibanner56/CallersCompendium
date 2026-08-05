import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/title_list_import.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
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

/// The title-list source on its own, so the dropdown is hidden and the pasted
/// input is the only affordance under test.
List<ImportSource> _titleListOnly() => [
  defaultImportSources().firstWhere(
    (s) => s.kind == ImportSourceKind.titleList,
  ),
];

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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
}
