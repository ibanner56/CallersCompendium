// Suggested and the program's event rules (#2345): a dance that would break
// an applied rule where the dance will go is marked, names the rule, and is
// listed after every other dance; nothing is hidden, and with Event rules
// off, Suggestions off, no rules applied, or another sort, the list is the
// one the picker shows without rules.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/search/event_rule_check.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/picker_suggestions.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

class _FixedClock extends SearchClock {
  const _FixedClock();

  @override
  DateTime today() => DateTime.utc(2026, 6, 15);
}

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// The reverse of the plain order, with one reason each.
Future<SuggestionRanking> _reversed(SuggestionRequest request) => Future.value(
  SuggestionRanking([
    for (final (i, dance) in request.candidates.reversed.indexed)
      RankedSuggestion(
        danceId: dance.id,
        score: -i.toDouble(),
        ranked: true,
        reasons: const [
          SuggestionReason(
            SuggestionReasonKind.fitsCurve,
            factor: SuggestionFactor.difficultyCurve,
            effect: 0.5,
          ),
        ],
      ),
  ]),
);

final _atMostOne = EventRule.of(
  id: 'r1',
  savedSearchId: 'petronella',
  quantifier: EventRuleQuantifier.atMost,
  count: 1,
  scope: EventRuleScope.wholeProgram,
);

const _sentence = 'At most 1 dance matching "Petronella" in the whole program';

/// One petronella (p1) already in the program; the program adds at the end.
final _context = PickerProgramContext(
  programId: 'prog',
  position: SuggestionPosition.atEnd([
    ProgramSlot(id: 's0', position: 0, danceId: 'p1'),
  ]),
);

/// The rule check, as the app's [checkCandidateEventRules] answers it:
/// petronellas are p1 and p2. Records each call; [hold] makes the next call
/// wait for the test.
class _Rules {
  final calls = <(SuggestionPosition, List<String>)>[];
  Completer<void>? hold;
  bool fail = false;

  Future<CandidateRuleMarks> check(
    SuggestionPosition position,
    List<String> ids,
  ) async {
    calls.add((position, ids));
    final wait = hold;
    if (wait != null) await wait.future;
    if (fail) throw StateError('check failed');
    return CandidateRuleMarks(
      check: CandidateRuleCheck(
        position: position,
        rules: [_atMostOne],
        matchingDanceIds: {
          _atMostOne.id: {'p1', 'p2'},
        },
      ),
      searchNames: {_atMostOne.id: 'Petronella'},
    );
  }
}

class _Harness {
  _Harness(this.suggestions, this.rulesOn, this.withRules);
  final ValueNotifier<bool> suggestions;
  final ValueNotifier<bool> rulesOn;

  /// Whether the picker is given the program's rules (a program that
  /// applies none passes none).
  final ValueNotifier<bool> withRules;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required _Rules? rules,
  bool suggestions = true,
  bool rulesOn = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repos = openTestRepositories();
  for (final (id, title) in [
    ('a', 'Alpha'),
    ('b', 'Bravo'),
    ('p1', 'Petronella One'),
    ('p2', 'Petronella Two'),
  ]) {
    await repos.dances.create(_dance(id, title));
  }
  final suggestionsOn = ValueNotifier(suggestions);
  addTearDown(suggestionsOn.dispose);
  final rulesEnabled = ValueNotifier(rulesOn);
  addTearDown(rulesEnabled.dispose);
  final withRules = ValueNotifier(rules != null);
  addTearDown(withRules.dispose);
  final settings = ValueNotifier<SuggestionSettingsRead>((
    settings: const SuggestionSettings(),
    isNewer: false,
  ));
  addTearDown(settings.dispose);
  final data = await CollectionData.load(repos);
  await tester.pumpWidget(
    MaterialApp(
      // A new picker each time, never the state of one pumped before.
      key: UniqueKey(),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: RepositoriesScope(
          repositories: repos,
          child: SuggestionsEnabledScope(
            notifier: suggestionsOn,
            child: SuggestionSettingsScope(
              notifier: settings,
              child: EventRulesEnabledScope(
                notifier: rulesEnabled,
                child: ValueListenableBuilder(
                  valueListenable: withRules,
                  builder: (context, applied, _) => CollectionPicker(
                    data: data,
                    dialect: Dialect.larksRobins,
                    enrichment: SearchEnrichment.empty,
                    onAddDance: (_) {},
                    programContext: _context,
                    rankSuggestions: _reversed,
                    eventRules: applied && rules != null
                        ? PickerEventRules(check: rules.check, revision: 0)
                        : null,
                    clock: const _FixedClock(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(suggestionsOn, rulesEnabled, withRules);
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

Future<void> _chooseSuggested(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('picker-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('sort-suggested')));
  await tester.pumpAndSettle();
}

Future<void> _chooseTitleSort(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('picker-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<Object>, 'Title'));
  await tester.pumpAndSettle();
}

Finder _marker(String id) => find.byKey(ValueKey('suggestion-rule-marker-$id'));

final _anyMarker = find.byType(SuggestionRuleMarker);

/// The plain order, and the ranking without rules (the reverse of it).
const _plain = ['Alpha', 'Bravo', 'Petronella One', 'Petronella Two'];
const _ranked = ['Petronella Two', 'Petronella One', 'Bravo', 'Alpha'];

/// The ranking with the petronellas marked and listed last, in ranking
/// order: the one already in the program is marked too (a second one).
const _marked = ['Bravo', 'Alpha', 'Petronella Two', 'Petronella One'];

void main() {
  testWidgets('a dance that would break a rule is marked with an icon and '
      'text naming the rule, and listed after every unmarked dance', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final rules = _Rules();
    await _pump(tester, rules: rules);
    await _chooseSuggested(tester);

    expect(_titles(tester), _marked);
    expect(rules.calls, hasLength(1));
    expect(rules.calls.single.$1, _context.position);
    expect(rules.calls.single.$2.toSet(), {'a', 'b', 'p1', 'p2'});

    for (final id in ['p1', 'p2']) {
      final marker = _marker(id);
      expect(marker, findsOneWidget, reason: id);
      expect(
        find.descendant(of: marker, matching: find.byIcon(Icons.rule)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: marker,
          matching: find.text('Would break: $_sentence'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(marker),
        matchesSemantics(label: 'Would break the event rule: $_sentence'),
      );
    }
    expect(_marker('a'), findsNothing);
    expect(_marker('b'), findsNothing);
    // The reason line is still there, under the marker.
    expect(find.byKey(const ValueKey('suggestion-reason-p2')), findsOneWidget);

    // Why? names the rule first.
    await tester.tap(find.byKey(const ValueKey('picker-why-p2')));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('suggestion-why-dialog'));
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Would break: $_sentence'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the ranking shows unmarked first; the marks and the new order '
      'follow when the check finishes', (tester) async {
    final rules = _Rules()..hold = Completer<void>();
    await _pump(tester, rules: rules);
    await tester.tap(find.byKey(const ValueKey('picker-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sort-suggested')));
    // Not pumpAndSettle: the spinner animates while the check runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_titles(tester), _ranked);
    expect(_anyMarker, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    rules.hold!.complete();
    await tester.pumpAndSettle();
    expect(_titles(tester), _marked);
    expect(_anyMarker, findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the same dances are listed with and without rules applied', (
    tester,
  ) async {
    final rules = _Rules();
    final harness = await _pump(tester, rules: rules);
    await _chooseSuggested(tester);
    final withRules = _titles(tester);
    expect(withRules, _marked);

    harness.withRules.value = false;
    await tester.pumpAndSettle();
    final without = _titles(tester);
    expect(without, _ranked);
    expect(_anyMarker, findsNothing);

    expect(withRules.toSet(), without.toSet());
    expect(withRules, hasLength(without.length));
  });

  group('the list for a fixed fixture equals the list without this change', () {
    /// The titles the picker shows without rules, Suggested chosen or not.
    Future<List<String>> baseline(
      WidgetTester tester, {
      required bool suggested,
      bool suggestions = true,
    }) async {
      await _pump(tester, rules: null, suggestions: suggestions);
      if (suggested) await _chooseSuggested(tester);
      return _titles(tester);
    }

    testWidgets('with Event rules off', (tester) async {
      final expected = await baseline(tester, suggested: true);
      expect(expected, _ranked);

      final rules = _Rules();
      final harness = await _pump(tester, rules: rules, rulesOn: false);
      await _chooseSuggested(tester);
      expect(_titles(tester), expected);
      expect(_anyMarker, findsNothing);
      expect(rules.calls, isEmpty);

      // Turned on, the same picker marks; turned off again, it goes back.
      harness.rulesOn.value = true;
      await tester.pumpAndSettle();
      expect(_titles(tester), _marked);
      harness.rulesOn.value = false;
      await tester.pumpAndSettle();
      expect(_titles(tester), expected);
      expect(_anyMarker, findsNothing);
    });

    testWidgets('with Suggestions off', (tester) async {
      final expected = await baseline(
        tester,
        suggested: false,
        suggestions: false,
      );
      expect(expected, _plain);

      final rules = _Rules();
      await _pump(tester, rules: rules, suggestions: false);
      expect(find.byKey(const ValueKey('picker-sort')), findsOneWidget);
      expect(_titles(tester), expected);
      expect(_anyMarker, findsNothing);
      expect(rules.calls, isEmpty);
    });

    testWidgets('with no rules applied', (tester) async {
      final expected = await baseline(tester, suggested: true);

      final rules = _Rules();
      final harness = await _pump(tester, rules: rules);
      harness.withRules.value = false;
      await tester.pumpAndSettle();
      await _chooseSuggested(tester);
      expect(_titles(tester), expected);
      expect(_anyMarker, findsNothing);
      expect(rules.calls, isEmpty);
    });

    testWidgets('with a sort other than Suggested', (tester) async {
      final expected = await baseline(tester, suggested: false);
      expect(expected, _plain);

      final rules = _Rules();
      await _pump(tester, rules: rules);
      expect(_titles(tester), expected);
      // Suggested, then back to a plain sort.
      await _chooseSuggested(tester);
      expect(_titles(tester), _marked);
      await _chooseTitleSort(tester);
      expect(_titles(tester), expected);
      expect(_anyMarker, findsNothing);
      expect(rules.calls, hasLength(1));
    });
  });

  testWidgets('a check that fails leaves the ranking unmarked', (tester) async {
    final rules = _Rules()..fail = true;
    await _pump(tester, rules: rules);
    await _chooseSuggested(tester);
    expect(_titles(tester), _ranked);
    expect(_anyMarker, findsNothing);
  });
}
