// The program builder's picker under Suggested with the program's event
// rules applied (#2345): a dance that would break a rule where it would be
// added is marked, naming the rule, and listed after every unmarked dance;
// each rule's saved search runs once over all the candidates, never once per
// candidate.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title, FormationShape shape) => Dance(
  id: id,
  title: title,
  form: DanceForm.contra,
  formation: Formation(shape),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

/// Records the dance ids each [matchingAmong] call is asked about.
class _CountingDances extends DanceRepository {
  _CountingDances(super.db, super.taxonomy);

  final calls = <Set<String>>[];

  @override
  Future<Set<String>> matchingAmong(
    DanceFilter filter,
    Iterable<String> ids, {
    Dialect? dialect,
    SearchEnrichment? enrichment,
  }) {
    calls.add(ids.toSet());
    return super.matchingAmong(
      filter,
      ids,
      dialect: dialect,
      enrichment: enrichment,
    );
  }
}

/// A program of one Becket and one improper dance, applying "At most 1
/// dance matching Becket in the whole program" unless [applied] says
/// otherwise.
Future<(CompendiumRepositories, _CountingDances)> _seed({
  bool applied = true,
}) async {
  final db = openWidgetTestDatabase();
  final dances = _CountingDances(db, contraTaxonomy);
  final repos = CompendiumRepositories(db, contraTaxonomy, dances: dances);
  for (final (id, title, shape) in [
    ('d-a', 'Becket Reel', FormationShape.becketCcw),
    ('d-c', 'Chorus Jig', FormationShape.dupleImproper),
    ('d-n', 'New Becket', FormationShape.becketCcw),
    ('d-m', 'Money Musk', FormationShape.dupleImproper),
  ]) {
    await repos.dances.create(_dance(id, title, shape));
  }
  final facets = FacetSelections()..formations.add(FormationShape.becketCcw);
  final becket = await repos.savedSearches.create(
    name: 'Becket',
    spec: SavedSearchSpec.fromPanelState(
      CollectionPanelState(facets: facets),
      today: _now,
    ).value!,
  );
  final rule = await repos.eventRules.create(
    savedSearchId: becket.id,
    quantifier: EventRuleQuantifier.atMost,
    count: 1,
    scope: EventRuleScope.wholeProgram,
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Night',
      eventRuleIds: applied ? [rule.id] : const [],
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'd-a'),
        ProgramSlot(id: 's2', position: 1, danceId: 'd-c'),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return (repos, dances);
}

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool rulesOn = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final suggestions = ValueNotifier(true);
  addTearDown(suggestions.dispose);
  final rules = ValueNotifier(rulesOn);
  addTearDown(rules.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: SuggestionsEnabledScope(
          notifier: suggestions,
          child: EventRulesEnabledScope(notifier: rules, child: child!),
        ),
      ),
      home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

final _picker = find.byKey(const ValueKey('inline-picker'));

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(
      find.descendant(of: _picker, matching: find.byType(DanceListTile)),
    )
    .map((t) => t.entry.title)
    .toList();

Finder _marker(String id) => find.descendant(
  of: _picker,
  matching: find.byKey(ValueKey('suggestion-rule-marker-$id')),
);

/// Chooses Suggested and pumps, with real time for the ranking isolate and
/// the rule check, until [done] holds, failing after a deadline.
Future<void> _suggest(WidgetTester tester, bool Function() done) async {
  await tester.tap(
    find.descendant(
      of: _picker,
      matching: find.byKey(const ValueKey('picker-sort')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('sort-suggested')));
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'not done by the deadline');
}

bool _ranked(WidgetTester tester) => find
    .descendant(
      of: _picker,
      matching: find.byKey(const ValueKey('suggestion-reason-d-m')),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('a Becket is marked with the rule, listed after every '
      'unmarked dance, and the rule searches once over every candidate', (
    tester,
  ) async {
    final (repos, dances) = await _seed();
    await _pump(tester, repos);
    await _suggest(tester, () => _marker('d-n').evaluate().isNotEmpty);

    // Money Musk ranks; Chorus Jig is already in the program; then the two
    // Beckets, each a second Becket, Becket Reel being already in it too.
    expect(_titles(tester), [
      'Money Musk',
      'Chorus Jig',
      'New Becket',
      'Becket Reel',
    ]);
    expect(
      find.descendant(
        of: _marker('d-n'),
        matching: find.text(
          'Would break: At most 1 dance matching "Becket" in the whole '
          'program',
        ),
      ),
      findsOneWidget,
    );
    expect(_marker('d-a'), findsOneWidget);
    expect(_marker('d-m'), findsNothing);
    expect(_marker('d-c'), findsNothing);

    // Every check that asked about a candidate asked about all of them at
    // once.
    final candidateCalls = [
      for (final ids in dances.calls)
        if (ids.contains('d-n') || ids.contains('d-m')) ids,
    ];
    expect(candidateCalls, isNotEmpty);
    for (final ids in candidateCalls) {
      expect(ids, containsAll(['d-a', 'd-c', 'd-n', 'd-m']));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with Event rules off, or no rules applied, nothing is marked '
      'and no candidate is checked', (tester) async {
    for (final (rulesOn, applied) in [(false, true), (true, false)]) {
      final (repos, dances) = await _seed(applied: applied);
      await _pump(tester, repos, rulesOn: rulesOn);
      await _suggest(tester, () => _ranked(tester));
      // Give a stray check every chance to land.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final reason = 'rules on: $rulesOn, applied: $applied';
      expect(
        find.descendant(
          of: _picker,
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'suggestion-rule-marker-',
                ),
          ),
        ),
        findsNothing,
        reason: reason,
      );
      expect(
        [
          for (final ids in dances.calls)
            if (ids.contains('d-n') || ids.contains('d-m')) ids,
        ],
        isEmpty,
        reason: reason,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
