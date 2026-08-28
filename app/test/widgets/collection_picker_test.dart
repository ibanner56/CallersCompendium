import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

Dance _dance({
  required String id,
  required String title,
  List<Figure> figures = const [],
}) => Dance(
  id: id,
  title: title,
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

/// The standard four-phrase skeleton (A1/A2/B1/B2), each a 16-beat move, so
/// section-aware figure queries resolve to the expected phrase.
List<Figure> _phrases({
  required String a1,
  required String a2,
  required String b1,
  required String b2,
}) => [
  testFigure(move: a1, params: const {'beats': 16}),
  testFigure(move: a2, params: const {'beats': 16}),
  testFigure(move: b1, params: const {'beats': 16}),
  testFigure(move: b2, params: const {'beats': 16}),
];

Future<void> _pumpPicker(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required void Function(String danceId) onAddDance,
  SearchEnrichment? enrichment,
  PickerRowAction rowAction = PickerRowAction.add,
  bool enableOnlineSearch = false,
  OnlineSearchService? callersBoxOnline,
  OnlineSearchService? contraDbOnline,
  Future<void> Function(String danceId)? onDanceImported,
  void Function(String danceId)? onPreviewDanceStarted,
  void Function(String danceId)? onPreviewDanceEnded,
  void Function(String danceId)? onViewDanceDetails,
}) async {
  enrichment ??= SearchEnrichment.empty;
  // A tall surface so the search bar, filter/by-phrase/advanced panels and the
  // results list all lay out without scrolling, keeping control taps stable.
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final data = await CollectionData.load(repos);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: RepositoriesScope(
          repositories: repos,
          child: CollectionPicker(
            data: data,
            dialect: Dialect.larksRobins,
            enrichment: enrichment,
            onAddDance: onAddDance,
            rowAction: rowAction,
            enableOnlineSearch: enableOnlineSearch,
            callersBoxOnline: callersBoxOnline,
            contraDbOnline: contraDbOnline,
            onDanceImported: onDanceImported,
            onPreviewDanceStarted: onPreviewDanceStarted,
            onPreviewDanceEnded: onPreviewDanceEnded,
            onViewDanceDetails: onViewDanceDetails,
          ),
        ),
      ),
    ),
  );
}

class _DedupeOnlineService implements OnlineSearchService {
  _DedupeOnlineService(
    this.ambiguousKind, {
    this.onlineSource = OnlineSource.callersBox,
    this.alwaysCreate = false,
    this.importFailure,
  });

  final OnlineImportKind ambiguousKind;
  final OnlineSource onlineSource;
  final bool alwaysCreate;
  final Object? importFailure;
  var importCalls = 0;
  final searchedTitles = <String>[];

  @override
  OnlineSource get source => onlineSource;

  @override
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query) async {
    searchedTitles.add(query.title);
    return [
      OnlineSearchResultRow(
        source: onlineSource,
        id: 'remote',
        name: 'Remote Dance',
        author: '',
        formation: '',
      ),
    ];
  }

  @override
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
    DedupeIndex? index,
  }) async {
    final dance = _dance(id: '', title: result.name);
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
      plan: ImportRecordPlan(
        draft: StructuredDraft(
          dance: dance,
          raw: const RawRecord(
            source: ProvenanceSource.callersbox,
            externalId: 'remote',
            payload: '{}',
          ),
        ),
        verdict: DedupeVerdict.isNew(),
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
    importCalls++;
    if (importFailure != null) throw importFailure!;
    if (!alwaysCreate && ambiguousResolution == null) {
      return OnlineImportResult(
        kind: ambiguousKind,
        title: 'Existing Dance',
        danceId: 'existing',
      );
    }
    return const OnlineImportResult(
      kind: OnlineImportKind.created,
      title: 'Remote Dance',
      danceId: 'imported',
    );
  }
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openOnlineResult(
  WidgetTester tester,
  CompendiumRepositories repos,
  OnlineSearchService service,
  void Function(String danceId) onAddDance, {
  PickerRowAction rowAction = PickerRowAction.add,
  Future<void> Function(String danceId)? onDanceImported,
}) async {
  await _pumpPicker(
    tester,
    repos,
    onAddDance: onAddDance,
    rowAction: rowAction,
    enableOnlineSearch: true,
    callersBoxOnline: service,
    onDanceImported: onDanceImported,
  );
  await tester.pumpAndSettle();
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('picker-advanced-panel')),
  );
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('picker-online-search-enable')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('picker-search')),
    'Remote Dance',
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  final result = find.byType(OnlineResultTile);
  await tester.ensureVisible(result);
  await tester.tap(result);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Comfortably longer than the picker's own add-confirmation linger, so a pump
/// of this length always lands after the revert.
const _confirmationLingers = Duration(seconds: 2);

/// The glyph currently drawn on a result row's trailing add affordance.
IconData _addIcon(WidgetTester tester, String danceId) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(ValueKey('picker-add-$danceId')),
        matching: find.byType(Icon),
      ),
    )
    .icon!;

String _addTooltip(WidgetTester tester, String danceId) => tester
    .widget<IconButton>(find.byKey(ValueKey('picker-add-$danceId')))
    .tooltip!;

/// Types [text] into the keyed By-Phrase move input and picks [option] from the
/// type-ahead overlay.
Future<void> _addPhraseMove(
  WidgetTester tester,
  String inputKey,
  String text,
  String option,
) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(inputKey)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picker text search keeps the default Omni scope', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'title', title: 'Swing Title'));
    await repos.dances.create(
      _dance(
        id: 'figure',
        title: 'Plain Title',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}),
        ],
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: (_) {});
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'swing',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(_titles(tester), ['Plain Title', 'Swing Title']);
  });

  testWidgets('by phrase: figure-in-A1 query filters the picker results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // petronella in A1.
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: _phrases(
          a1: 'petronella',
          a2: 'swing',
          b1: 'balance',
          b2: 'long_lines',
        ),
      ),
    );
    // petronella in B1, not A1 → filtered out.
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'B1 Petronella',
        figures: _phrases(
          a1: 'swing',
          a2: 'swing',
          b1: 'petronella',
          b2: 'long_lines',
        ),
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: (_) {});
    await tester.pumpAndSettle();

    // Both dances show before any query is applied.
    expect(_titles(tester), containsAll(['A1 Petronella', 'B1 Petronella']));

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-by-phrase-panel')),
    );
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    expect(_titles(tester), ['A1 Petronella']);
  });

  testWidgets('by phrase: add-in-one-tap still works on a filtered result', (
    tester,
  ) async {
    final added = <String>[];
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'A1 Petronella',
        figures: _phrases(
          a1: 'petronella',
          a2: 'swing',
          b1: 'balance',
          b2: 'long_lines',
        ),
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'B1 Petronella',
        figures: _phrases(
          a1: 'swing',
          a2: 'swing',
          b1: 'petronella',
          b2: 'long_lines',
        ),
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: added.add);
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-by-phrase-panel')),
    );
    await _addPhraseMove(tester, 'match-A1-input-0', 'petro', 'petronella');

    // Only the A1 match survives; its one-tap add affordance still fires.
    expect(_titles(tester), ['A1 Petronella']);
    await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
    expect(added, ['a']);
  });

  testWidgets('advanced builder: add a figure row filters the picker results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'a',
        title: 'Has Petronella',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 16}),
        ],
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'b',
        title: 'Just Swing',
        figures: [
          Figure(move: 'swing', params: const {'beats': 16}),
        ],
      ),
    );

    await _pumpPicker(tester, repos, onAddDance: (_) {});
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-enable')),
    );
    await _tapVisible(tester, find.text('Add'));
    await _tapVisible(tester, find.text('Has figure'));

    final moveField = find.byType(TextField).last;
    await tester.ensureVisible(moveField);
    await tester.enterText(moveField, 'petro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('petronella').last);
    await tester.pumpAndSettle();

    // The advanced tree compiles through buildCollectionFilter and re-runs the
    // search, so only the dance with the figure survives.
    expect(_titles(tester), ['Has Petronella']);
  });

  group('search enrichment (saved-dialect vocabulary)', () {
    // A saved dialect the user is NOT actively using (active is Larks/Robins):
    // maps role2 → follow, so "follows" should resolve to role2s via the union
    // enrichment even though that dialect is inactive — parity with the main
    // Collection search (search_integration_test's union-enrichment group).
    SearchEnrichment savedFollows() => SearchEnrichment.fromDialects([
      Dialect(
        name: 'Leads/Follows (saved)',
        roles: const {'role1': RoleTerm('lead'), 'role2': RoleTerm('follow')},
      ),
    ]);

    Future<CompendiumRepositories> reposWithRole2Dance() async {
      final repos = openTestRepositories();
      // Canonical FTS stores 'role2s' for this dance's swing.
      await repos.dances.create(
        _dance(
          id: 'chain',
          title: 'Chain Dance',
          figures: [
            Figure(move: 'swing', params: const {'who': 'role2s', 'beats': 8}),
          ],
        ),
      );
      return repos;
    }

    testWidgets(
      'a saved-dialect term ("follows") resolves in the picker via enrichment',
      (tester) async {
        final repos = await reposWithRole2Dance();
        await _pumpPicker(
          tester,
          repos,
          onAddDance: (_) {},
          enrichment: savedFollows(),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('picker-search')),
          'follows',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(_titles(tester), ['Chain Dance']);
      },
    );

    testWidgets(
      'without enrichment the same saved-dialect term does not match',
      (tester) async {
        final repos = await reposWithRole2Dance();
        // Default empty enrichment: "follows" is neither active-dialect nor
        // legacy vocabulary, so it must not resolve to role2s.
        await _pumpPicker(tester, repos, onAddDance: (_) {});
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('picker-search')),
          'follows',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(_titles(tester), isEmpty);
      },
    );
  });

  // --- Transient add confirmation (#796) -------------------------------------

  group('transient add confirmation', () {
    Future<CompendiumRepositories> reposWithTwoDances() async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));
      await repos.dances.create(_dance(id: 'b', title: 'Bravo Jig'));
      return repos;
    }

    testWidgets('the tapped row shows a check, then reverts to the plus', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));
      await _pumpPicker(tester, repos, onAddDance: (_) {});
      await tester.pumpAndSettle();

      expect(_addIcon(tester, 'a'), Icons.add_circle_outline);

      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));

      // The confirmation is an icon *shape* change, never colour alone
      // (WCAG 1.4.1, docs/design/ux.md:125).
      expect(_addIcon(tester, 'a'), Icons.check_circle);

      await tester.pump(_confirmationLingers);
      await tester.pumpAndSettle();

      expect(_addIcon(tester, 'a'), Icons.add_circle_outline);
    });

    testWidgets('the confirming row keeps a tooltip naming the dance', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));
      await _pumpPicker(tester, repos, onAddDance: (_) {});
      await tester.pumpAndSettle();

      final addTooltip = _addTooltip(tester, 'a');
      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));

      // Leaving the "Add Alpha Reel" tooltip in place under a check icon would
      // describe an action the glyph no longer offers.
      final confirmTooltip = _addTooltip(tester, 'a');
      expect(confirmTooltip, isNot(addTooltip));
      expect(confirmTooltip, contains('Alpha Reel'));
    });

    testWidgets('the button stays enabled, so the same dance can be added '
        'twice in a row', (tester) async {
      final added = <String>[];
      final repos = await reposWithTwoDances();
      await _pumpPicker(tester, repos, onAddDance: added.add);
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('picker-add-a')))
            .onPressed,
        isNotNull,
        reason: 'a dance may legitimately appear twice in one program',
      );

      // Re-tapping mid-confirmation restarts the linger rather than stacking a
      // second timer that would revert the icon early.
      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
      expect(added, ['a', 'a']);
      expect(_addIcon(tester, 'a'), Icons.check_circle);

      await tester.pump(_confirmationLingers);
      await tester.pumpAndSettle();
      expect(_addIcon(tester, 'a'), Icons.add_circle_outline);
    });

    testWidgets('the confirmation is scoped to the row that was tapped', (
      tester,
    ) async {
      final repos = await reposWithTwoDances();
      await _pumpPicker(tester, repos, onAddDance: (_) {});
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));

      expect(_addIcon(tester, 'a'), Icons.check_circle);
      expect(_addIcon(tester, 'b'), Icons.add_circle_outline);
    });

    testWidgets('tapping the row body confirms the same way as the button', (
      tester,
    ) async {
      final added = <String>[];
      final repos = await reposWithTwoDances();
      await _pumpPicker(tester, repos, onAddDance: added.add);
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const ValueKey('picker-tile-a')));

      expect(added, ['a']);
      expect(_addIcon(tester, 'a'), Icons.check_circle);
    });

    testWidgets('a pending confirmation does not outlive the picker', (
      tester,
    ) async {
      final repos = await reposWithTwoDances();
      // Perform's insert sheet pops inside onAddDance
      // (perform_adjust_sheet.dart:245), disposing the picker while the
      // confirmation timer is still pending.
      await _pumpPicker(tester, repos, onAddDance: (_) {});
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Reaching here without a pending-timer teardown failure is the
      // assertion: dispose() must cancel the confirmation timers.
      expect(find.byType(CollectionPicker), findsNothing);
    });
  });

  // --- rowAction (issue #964) -------------------------------------------------

  testWidgets('saved preview ends only for its recognized holding pointer', (
    tester,
  ) async {
    final started = <String>[];
    final ended = <String>[];
    final added = <String>[];
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));
    await _pumpPicker(
      tester,
      repos,
      onAddDance: added.add,
      onPreviewDanceStarted: started.add,
      onPreviewDanceEnded: ended.add,
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(
      find.byKey(const ValueKey('picker-tile-a')),
    );

    final tap = await tester.startGesture(center, pointer: 4);
    await tap.up();
    await tester.pump();
    expect(started, isEmpty);
    expect(ended, isEmpty);
    expect(added, ['a']);
    added.clear();

    final scroll = await tester.startGesture(center, pointer: 3);
    await scroll.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 600));
    await scroll.up();
    await tester.pump();
    expect(started, isEmpty);
    expect(ended, isEmpty);

    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    expect(started, ['a']);
    expect(added, isEmpty);

    final secondPointer = await tester.startGesture(center, pointer: 2);
    await secondPointer.up();
    await tester.pump();
    expect(ended, isEmpty);

    await gesture.cancel();
    await tester.pump();
    expect(ended, ['a']);
    expect(added, isEmpty);
  });

  testWidgets('View details is a separate saved-result action', (tester) async {
    final opened = <String>[];
    final added = <String>[];
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));
    await _pumpPicker(
      tester,
      repos,
      onAddDance: added.add,
      onViewDanceDetails: opened.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('picker-details-a')));
    expect(opened, ['a']);
    expect(added, isEmpty);
  });

  group('rowAction', () {
    // M5 (issue #964): the paired assertion matters as much as the replace
    // one — a mutation that deletes the rowAction branch would make row
    // labels read "Add {title}" unconditionally, which passes a test that
    // only checks the replace-mode string. Checking BOTH modes in one test
    // is what makes the mutation observable.
    testWidgets('replace mode labels rows as replace, not add (issue #964)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));

      await _pumpPicker(tester, repos, onAddDance: (_) {});
      await tester.pumpAndSettle();
      expect(_addTooltip(tester, 'a'), 'Add Alpha Reel');
      expect(_addIcon(tester, 'a'), Icons.add_circle_outline);

      await _pumpPicker(
        tester,
        repos,
        onAddDance: (_) {},
        rowAction: PickerRowAction.replace,
      );
      await tester.pumpAndSettle();
      expect(_addTooltip(tester, 'a'), 'Replace with Alpha Reel');
      expect(_addIcon(tester, 'a'), Icons.swap_horiz);
    });

    testWidgets(
      'replace mode still fires onAddDance like add mode (issue #964)',
      (tester) async {
        final added = <String>[];
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'a', title: 'Alpha Reel'));

        await _pumpPicker(
          tester,
          repos,
          onAddDance: added.add,
          rowAction: PickerRowAction.replace,
        );
        await tester.pumpAndSettle();

        await _tapVisible(tester, find.byKey(const ValueKey('picker-add-a')));
        expect(added, ['a']);
      },
    );
  });

  testWidgets('an online result imports and adds the persisted dance', (
    tester,
  ) async {
    final added = <String>[];
    final repos = openTestRepositories();
    final online = CallersBoxOnline(
      searchFetcher: (_) async => '''
        <html><body>
        <p>Of 1 dances in the database, your query matches 1.</p>
        <table><tr>
          <td>&#x24bb;</td><td></td><td></td>
          <td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
          <td>Traditional</td><td>Triple Minor - Proper</td>
        </tr></table>
        </body></html>
      ''',
      jsonFetcher: (_) async => '''
        {
          "ID":"10600","Name":"Money Musk","Authors":["Traditional"],
          "InterpretedBy":[],"Permission":"full",
          "FormationBase":"Triple Minor - Proper","FormationDetail":"",
          "Progression":"Single","PhraseStructure":"","CallingNotes":[],
          "OtherNames":[],"Music":[],"Tunes":[],"Appearances":[],
          "phrases":[{"name":"A1","figures":["Actives balance and swing"]}]
        }
      ''',
    );

    await _pumpPicker(
      tester,
      repos,
      onAddDance: added.add,
      enableOnlineSearch: true,
      callersBoxOnline: online,
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Money Musk',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byType(OnlineResultTile));

    expect(added, hasLength(1));
    expect(
      find.byKey(const ValueKey('picker-online-added-callersBox-10600')),
      findsOneWidget,
    );
    expect((await repos.dances.listAll()).map((dance) => dance.title), [
      'Money Musk',
    ]);

    // The direct-pick flow treats an exact re-import as selecting the existing
    // dance: it must add that id again without creating a duplicate.
    await _tapVisible(tester, find.byType(OnlineResultTile));
    expect(added, hasLength(2));
    expect((await repos.dances.listAll()).map((dance) => dance.title), [
      'Money Musk',
    ]);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Traditional'), findsOneWidget);
  });

  testWidgets('disabling online search returns to local results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'local', title: 'Local Dance'));
    final online = _DedupeOnlineService(OnlineImportKind.created);
    final added = <String>[];

    await _pumpPicker(
      tester,
      repos,
      onAddDance: added.add,
      enableOnlineSearch: true,
      callersBoxOnline: online,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Remote Dance',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineResultTile), findsOneWidget);

    await _pumpPicker(
      tester,
      repos,
      onAddDance: added.add,
      enableOnlineSearch: false,
      callersBoxOnline: online,
    );
    expect(find.byType(OnlineResultTile), findsNothing);
    expect(_titles(tester), contains('Local Dance'));
  });

  testWidgets('typing a new online query immediately clears stale results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final online = _DedupeOnlineService(OnlineImportKind.created);
    await _pumpPicker(
      tester,
      repos,
      onAddDance: (_) {},
      enableOnlineSearch: true,
      callersBoxOnline: online,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'First query',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineResultTile), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Second query',
    );
    await tester.pump();

    expect(find.byType(OnlineResultTile), findsNothing);
  });

  testWidgets('changing an online phrase immediately clears stale results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final online = _DedupeOnlineService(OnlineImportKind.created);
    await _pumpPicker(
      tester,
      repos,
      onAddDance: (_) {},
      enableOnlineSearch: true,
      callersBoxOnline: online,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Remote Dance',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineResultTile), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-by-phrase-panel')),
    );
    final field = find.descendant(
      of: find.byKey(const ValueKey('match-A1-input-0')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'petro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('petronella').last);
    await tester.pump();

    expect(find.byType(OnlineResultTile), findsNothing);
  });

  testWidgets('online replacement imports before notifying the host', (
    tester,
  ) async {
    final events = <String>[];
    final service = _DedupeOnlineService(
      OnlineImportKind.created,
      alwaysCreate: true,
    );
    final repos = openTestRepositories();

    await _openOnlineResult(
      tester,
      repos,
      service,
      (danceId) => events.add('add:$danceId'),
      rowAction: PickerRowAction.replace,
      onDanceImported: (danceId) async => events.add('import:$danceId'),
    );

    expect(events, ['import:imported', 'add:imported']);
  });

  testWidgets('online import errors preserve the result for retry', (
    tester,
  ) async {
    final service = _DedupeOnlineService(
      OnlineImportKind.created,
      alwaysCreate: true,
      importFailure: StateError('import failed'),
    );
    final repos = openTestRepositories();

    await _openOnlineResult(tester, repos, service, (_) {});

    expect(find.byType(OnlineResultTile), findsOneWidget);
    expect(find.text('Couldn\'t import that dance.'), findsOneWidget);
  });

  testWidgets('overlay hydration failure still adds the imported dance', (
    tester,
  ) async {
    final service = _DedupeOnlineService(
      OnlineImportKind.created,
      alwaysCreate: true,
    );
    final added = <String>[];
    final repos = openTestRepositories();

    await _openOnlineResult(
      tester,
      repos,
      service,
      added.add,
      onDanceImported: (_) async => throw StateError('overlay failed'),
    );

    expect(added, ['imported']);
    expect(
      find.byKey(const ValueKey('picker-online-added-callersBox-remote')),
      findsOneWidget,
    );
  });

  group('online picker dedupe resolution', () {
    testWidgets('variation cancellation does not add a dance', (tester) async {
      final service = _DedupeOnlineService(OnlineImportKind.needsConfirmation);
      final added = <String>[];
      final repos = openTestRepositories();

      await _openOnlineResult(tester, repos, service, added.add);
      expect(
        find.byKey(const ValueKey('online-import-variation-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-cancel')),
      );
      await tester.pumpAndSettle();

      expect(service.importCalls, 1);
      expect(added, isEmpty);
    });

    testWidgets('variation confirmation retries and adds the imported dance', (
      tester,
    ) async {
      final service = _DedupeOnlineService(OnlineImportKind.needsConfirmation);
      final added = <String>[];
      final repos = openTestRepositories();

      await _openOnlineResult(tester, repos, service, added.add);
      await tester.tap(
        find.byKey(const ValueKey('online-import-variation-as-variation')),
      );
      await tester.pumpAndSettle();

      expect(service.importCalls, 2);
      expect(added, ['imported']);
    });

    testWidgets('cross-source cancellation does not add a dance', (
      tester,
    ) async {
      final service = _DedupeOnlineService(
        OnlineImportKind.needsConfirmationIdentical,
      );
      final added = <String>[];
      final repos = openTestRepositories();

      await _openOnlineResult(tester, repos, service, added.add);
      expect(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-dialog'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('online-import-cross-source-duplicate-cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.importCalls, 1);
      expect(added, isEmpty);
    });

    testWidgets(
      'cross-source confirmation retries and adds the imported dance',
      (tester) async {
        final service = _DedupeOnlineService(
          OnlineImportKind.needsConfirmationIdentical,
        );
        final added = <String>[];
        final repos = openTestRepositories();

        await _openOnlineResult(tester, repos, service, added.add);
        await tester.tap(
          find.byKey(
            const ValueKey('online-import-cross-source-duplicate-import-copy'),
          ),
        );
        await tester.pumpAndSettle();

        expect(service.importCalls, 2);
        expect(added, ['imported']);
      },
    );
  });

  testWidgets('online picker routes title-only searches through ContraDB', (
    tester,
  ) async {
    final callersBox = _DedupeOnlineService(OnlineImportKind.needsConfirmation);
    final contraDb = _DedupeOnlineService(
      OnlineImportKind.needsConfirmation,
      onlineSource: OnlineSource.contraDb,
    );
    final repos = openTestRepositories();

    await _pumpPicker(
      tester,
      repos,
      onAddDance: (_) {},
      enableOnlineSearch: true,
      callersBoxOnline: callersBox,
      contraDbOnline: contraDb,
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.tap(find.text('ContraDB'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Remote Dance',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(callersBox.searchedTitles, isEmpty);
    expect(contraDb.searchedTitles, ['Remote Dance']);
    expect(find.byKey(const ValueKey('picker-by-phrase-panel')), findsNothing);
  });

  testWidgets('online add indicators are scoped to their source', (
    tester,
  ) async {
    final callersBox = _DedupeOnlineService(
      OnlineImportKind.needsConfirmation,
      alwaysCreate: true,
    );
    final contraDb = _DedupeOnlineService(
      OnlineImportKind.needsConfirmation,
      onlineSource: OnlineSource.contraDb,
      alwaysCreate: true,
    );
    final repos = openTestRepositories();

    await _pumpPicker(
      tester,
      repos,
      onAddDance: (_) {},
      enableOnlineSearch: true,
      callersBoxOnline: callersBox,
      contraDbOnline: contraDb,
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-advanced-panel')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('picker-online-search-enable')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Remote Dance',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('picker-online-added-callersBox-remote')),
      findsOneWidget,
    );

    await tester.tap(find.text('ContraDB'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('picker-online-result-contraDb-remote')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('picker-online-added-contraDb-remote')),
      findsNothing,
    );
  });
}
