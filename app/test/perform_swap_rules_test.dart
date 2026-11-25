// Perform's swap sheet and the program's event rules (#2347): Settings ▸
// Experimental ▸ Event rules ▸ Check Perform's Swap this dance. A dance that
// would break an applied rule in the swapped slot is marked, names the rule,
// and is listed after every unmarked dance; nothing is hidden, and with the
// setting off, Event rules off, or no rules applied, the sheet is as #2346
// ships it.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/screens/perform_adjust_sheet.dart';
import 'package:compendium_app/src/screens/perform_swap_sheet.dart'
    show kPerformSwapMinTarget;
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/picker_suggestions.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Every dance is a Becket contra at the same level, so the default Keep
/// items (same formation, this level or easier, not already in tonight's
/// program) keep every candidate: only the rules tell them apart.
Dance _dance(String id, String title, {DanceForm form = DanceForm.contra}) =>
    Dance(
      id: id,
      title: title,
      form: form,
      formation: const Formation(FormationShape.becketCw),
      difficultyLevelId: DifficultyLevel.intermediateId,
      figures: const [],
      status: DanceStatus.active,
      createdAt: _now,
      updatedAt: _now,
    );

final _programDances = [
  _dance('d0', 'Opener'),
  _dance('d1', 'Current Reel'),
  _dance('alt', 'Backup Jig'),
  _dance('pet', 'Petronella Hey'),
  _dance('d3', 'Later Reel'),
];

/// The candidates, in their plain (title) order: the petronellas are first
/// and last, so listing them last is the check's doing.
final _candidates = [
  _dance('pa', 'Apple Petronella'),
  _dance('b', 'Birch Reel'),
  _dance('c', 'Cedar Reel'),
  _dance('pd', 'Petronella Dream'),
];

const _plainOrder = ['pa', 'b', 'c', 'pd'];
const _marked = {'pa', 'pd'};
const _markedLast = ['b', 'c', 'pa', 'pd'];

const _sentence = 'At most 1 dance matching "Petronella" in the whole program';

/// Called opener · current (with an alternate) · the petronella · later.
List<ProgramSlot> _slots({String altDance = 'alt'}) => [
  ProgramSlot(id: 's0', position: 0, danceId: 'd0', performedAt: _now),
  ProgramSlot(id: 's1', position: 1, danceId: 'd1'),
  ProgramSlot(id: 's1-alt', position: 2, danceId: altDance, isAlt: true),
  ProgramSlot(id: 's2', position: 3, danceId: 'pet'),
  ProgramSlot(id: 's3', position: 4, danceId: 'd3'),
];

/// Holds each rule's [matchingAmong] until the test releases it, when
/// [hold] is set; counts the calls.
class _GatedDances extends DanceRepository {
  _GatedDances(super.db, super.taxonomy);

  Completer<void>? hold;
  int calls = 0;

  @override
  Future<Set<String>> matchingAmong(
    DanceFilter filter,
    Iterable<String> ids, {
    Dialect? dialect,
    SearchEnrichment? enrichment,
  }) async {
    calls++;
    final wait = hold;
    if (wait != null) await wait.future;
    return super.matchingAmong(
      filter,
      ids,
      dialect: dialect,
      enrichment: enrichment,
    );
  }
}

class _Harness {
  _Harness(this.dances, this.rulesOn, this.checkSwap);
  final _GatedDances dances;
  final ValueNotifier<bool> rulesOn;
  final ValueNotifier<bool> checkSwap;
}

/// The adjust sheet on the current slot `s1` of a program applying "At most
/// 1 dance matching Petronella in the whole program" (unless [applied] is
/// false), with Event rules and Check Perform's Swap this dance as given.
Future<_Harness> _pump(
  WidgetTester tester, {
  bool rulesOn = true,
  bool checkSwap = true,
  bool applied = true,
  bool suggestions = false,
  String altDance = 'alt',
  String currentSlotId = 's1',
  List<Dance> extra = const [],
  Completer<void>? hold,
}) async {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = openWidgetTestDatabase();
  final dances = _GatedDances(db, contraTaxonomy);
  final repos = CompendiumRepositories(db, contraTaxonomy, dances: dances);
  for (final d in [
    for (final d in _programDances)
      if (d.id != 'alt' || altDance == 'alt') d,
    ..._candidates,
    if (altDance == 'palt') _dance('palt', 'Petronella Alt'),
    ...extra,
  ]) {
    await repos.dances.create(d);
  }
  final search = await repos.savedSearches.create(
    name: 'Petronella',
    spec: SavedSearchSpec.fromPanelState(
      CollectionPanelState(text: 'Petronella', scope: FullTextScope.title),
      today: _now,
    ).value!,
  );
  final rule = await repos.eventRules.create(
    savedSearchId: search.id,
    quantifier: EventRuleQuantifier.atMost,
    count: 1,
    scope: EventRuleScope.wholeProgram,
  );
  final data = await CollectionData.load(repos);
  final on = ValueNotifier<bool>(rulesOn);
  addTearDown(on.dispose);
  final check = ValueNotifier<bool>(checkSwap);
  addTearDown(check.dispose);
  final suggest = ValueNotifier<bool>(suggestions);
  addTearDown(suggest.dispose);
  dances.hold = hold;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: SuggestionsEnabledScope(
          notifier: suggest,
          child: SuggestionsInPerformSwapScope(
            notifier: suggest,
            child: EventRulesEnabledScope(
              notifier: on,
              child: EventRulesCheckPerformSwapScope(
                notifier: check,
                child: child!,
              ),
            ),
          ),
        ),
      ),
      home: Scaffold(
        body: PerformAdjustSheet(
          program: Program(
            id: 'p1',
            title: 'Spring Dance',
            slots: _slots(altDance: altDance),
            eventRuleIds: applied ? [rule.id] : const [],
            createdAt: _now,
            updatedAt: _now,
          ),
          currentGroupIndex: 1,
          currentSlotId: currentSlotId,
          data: data,
          dialect: Dialect.larksRobins,
          enrichment: SearchEnrichment.empty,
          // The real scorer, on the test's own isolate.
          rankSuggestions: (request) => Future.value(rankSuggestions(request)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(dances, on, check);
}

Finder _inSwap(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('adjust-swap-sheet')),
  matching: matching,
);

/// Opens the swap sheet from [button] and lets it settle, or, with
/// [settle] false, only lets the sheet open and its search land: a check
/// held open keeps a progress indicator spinning.
Future<void> _openSwap(
  WidgetTester tester,
  String button, {
  bool settle = true,
}) async {
  final finder = find.byKey(ValueKey(button));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The dance ids the swap sheet lists, top to bottom: Your alternates, then
/// the results.
List<String> _shown(WidgetTester tester) => tester
    .widgetList<DanceListTile>(_inSwap(find.byType(DanceListTile)))
    .map((tile) => tile.entry.dance.id)
    .toList();

/// The results under Your alternates, when [pinned] heads the list.
List<String> _results(WidgetTester tester, {List<String> pinned = const []}) {
  final shown = _shown(tester);
  expect(shown.take(pinned.length), pinned, reason: 'Your alternates first');
  return shown.skip(pinned.length).toList();
}

Finder _marker(String id) =>
    _inSwap(find.byKey(ValueKey('suggestion-rule-marker-$id')));

final _anyMarker = _inSwap(find.byType(SuggestionRuleMarker));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with the setting off, Event rules off, or no rules applied, the '
      'swap sheet is as #2346 ships it', () {
    for (final (name, rulesOn, checkSwap, applied) in [
      ("Check Perform's Swap this dance off", true, false, true),
      ('Event rules off', false, true, true),
      ('no rules applied', true, true, false),
    ]) {
      testWidgets('$name: the plain order, no markers, nothing checked', (
        tester,
      ) async {
        final h = await _pump(
          tester,
          rulesOn: rulesOn,
          checkSwap: checkSwap,
          applied: applied,
        );
        for (final button in ['adjust-swap-current', 'adjust-swap-s3']) {
          await _openSwap(tester, button);
          expect(
            _results(
              tester,
              pinned: button == 'adjust-swap-current' ? ['alt'] : const [],
            ),
            _plainOrder,
            reason: button,
          );
          expect(_anyMarker, findsNothing, reason: button);
          Navigator.of(
            tester.element(find.byKey(const ValueKey('adjust-swap-sheet'))),
          ).pop();
          await tester.pumpAndSettle();
        }
        expect(h.dances.calls, 0, reason: 'no rule was checked');
      });
    }
  });

  group('at most 1 petronella, with one in the program', () {
    for (final (button, pinned) in [
      ('adjust-swap-current', ['alt']),
      ('adjust-swap-s3', <String>[]),
    ]) {
      testWidgets('$button: each petronella is marked with the rule and '
          'listed after the unmarked results', (tester) async {
        await _pump(tester);
        await _openSwap(tester, button);
        expect(_results(tester, pinned: pinned), _markedLast);
        for (final id in _plainOrder) {
          expect(
            _marker(id),
            _marked.contains(id) ? findsOneWidget : findsNothing,
            reason: id,
          );
        }
        expect(
          find.descendant(of: _marker('pa'), matching: find.byType(Icon)),
          findsOneWidget,
          reason: 'an icon',
        );
        expect(
          find.descendant(
            of: _marker('pa'),
            matching: find.text('Would break: $_sentence'),
          ),
          findsOneWidget,
          reason: 'and the rule in words',
        );
      });
    }

    testWidgets('swapping the petronella itself, no petronella is marked: '
        'the dance swapped out stays only as an alternate', (tester) async {
      await _pump(tester);
      await _openSwap(tester, 'adjust-swap-s2');
      expect(_results(tester), _plainOrder);
      expect(_anyMarker, findsNothing);
    });

    testWidgets('the same dances are listed with the setting on or off, '
        'also when it is turned on and off with the sheet open', (
      tester,
    ) async {
      final h = await _pump(tester, checkSwap: false);
      await _openSwap(tester, 'adjust-swap-current');
      final off = _shown(tester);
      expect(off, ['alt', ..._plainOrder]);

      h.checkSwap.value = true;
      await tester.pumpAndSettle();
      final on = _shown(tester);
      expect(on, ['alt', ..._markedLast]);
      expect(on, hasLength(off.length));
      expect(on.toSet(), off.toSet());

      h.checkSwap.value = false;
      await tester.pumpAndSettle();
      expect(_shown(tester), off, reason: 'back as #2346 ships it');
      expect(_anyMarker, findsNothing);
    });

    testWidgets('the results show at once, unmarked, and the marks follow '
        'when the check is done', (tester) async {
      final hold = Completer<void>();
      final h = await _pump(tester, hold: hold);
      await _openSwap(tester, 'adjust-swap-current', settle: false);
      expect(h.dances.calls, greaterThan(0), reason: 'the check started');
      expect(_results(tester, pinned: ['alt']), _plainOrder);
      expect(_anyMarker, findsNothing);
      expect(
        tester.widget<DanceListTile>(
          _inSwap(find.byKey(const ValueKey('picker-tile-pa'))),
        ),
        isNotNull,
        reason: 'a tap target already',
      );

      hold.complete();
      await tester.pumpAndSettle();
      expect(_results(tester, pinned: ['alt']), _markedLast);
      expect(_marker('pa'), findsOneWidget);
    });

    testWidgets('a marked dance still swaps in with one tap', (tester) async {
      await _pump(tester);
      await _openSwap(tester, 'adjust-swap-current');
      await tester.tap(_inSwap(find.byKey(const ValueKey('picker-add-pa'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adjust-swap-sheet')), findsNothing);
      expect(find.text('Apple Petronella'), findsWidgets);
    });

    testWidgets('a marker has a screen-reader label naming the rule, and '
        'the row keeps its 44 pt target', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      await _openSwap(tester, 'adjust-swap-current');
      expect(
        tester.getSemantics(_marker('pa')),
        matchesSemantics(label: 'Would break the event rule: $_sentence'),
      );
      final row = tester.getSize(
        _inSwap(find.byKey(const ValueKey('picker-tile-pa'))),
      );
      expect(row.height, greaterThanOrEqualTo(kPerformSwapMinTarget));
      final swap = tester.getSize(
        _inSwap(find.byKey(const ValueKey('picker-add-pa'))),
      );
      expect(swap.height, greaterThanOrEqualTo(kPerformSwapMinTarget));
      expect(swap.width, greaterThanOrEqualTo(kPerformSwapMinTarget));
      semantics.dispose();
    });

    testWidgets('under Suggested too: marked dances, English ones included, '
        'are listed after the unmarked ones (#2348)', (tester) async {
      final english = _dance('pe', 'Petronella Bourrée', form: DanceForm.ecd);
      await _pump(tester, suggestions: true, extra: [english]);
      await _openSwap(tester, 'adjust-swap-current');
      final results = _results(tester, pinned: ['alt']);
      expect(results.toSet(), {..._plainOrder, 'pe'});
      expect(results.take(2).toSet(), {'b', 'c'}, reason: 'unmarked first');
      expect(results.skip(2).toSet(), {'pa', 'pd', 'pe'});
      expect(_marker('pe'), findsOneWidget, reason: 'English, marked too');
    });
  });

  group('Your alternates (#2347: checked as the other results are)', () {
    testWidgets('a petronella alternate is marked and stays under Your '
        'alternates', (tester) async {
      await _pump(tester, altDance: 'palt');
      await _openSwap(tester, 'adjust-swap-current');
      expect(_results(tester, pinned: ['palt']), _markedLast);
      expect(_marker('palt'), findsOneWidget);
    });

    testWidgets('swapping the alternate on screen checks it as the dance the '
        'swap makes planned, and lists the slot\'s primary unmarked', (
      tester,
    ) async {
      await _pump(tester, altDance: 'palt', currentSlotId: 's1-alt');
      await _openSwap(tester, 'adjust-swap-current');
      // The slot's other choice is its primary, Current Reel.
      expect(_results(tester, pinned: ['d1']), _markedLast);
      expect(_marker('d1'), findsNothing);
    });

    testWidgets('with the setting off, an alternate is not marked', (
      tester,
    ) async {
      await _pump(tester, altDance: 'palt', checkSwap: false);
      await _openSwap(tester, 'adjust-swap-current');
      expect(_results(tester, pinned: ['palt']), _plainOrder);
      expect(_anyMarker, findsNothing);
    });
  });
}
