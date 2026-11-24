// Settings ▸ Experimental ▸ Event rules (#2340): the switch, off by default,
// Manage rules once it is on, the rules manager (add, edit, delete with Undo)
// and the saved-search delete guard naming the rules that use the search.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings/collection_section.dart';
import 'package:compendium_app/src/screens/settings/event_rules_screen.dart';
import 'package:compendium_app/src/screens/settings/experimental_section.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';
import '../support/pump_until.dart';
import '../support/test_repositories.dart';

SavedSearchSpec _spec() {
  final facets = FacetSelections()..formations.add(FormationShape.becketCcw);
  return SavedSearchSpec.fromPanelState(
    CollectionPanelState(facets: facets),
    today: DateTime.utc(2026, 1, 1),
  ).value!;
}

Future<ValueNotifier<bool>> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  Widget home, {
  bool enabled = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final on = ValueNotifier(enabled);
  addTearDown(on.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: EventRulesEnabledScope(notifier: on, child: child!),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return on;
}

void main() {
  testWidgets('the switch is off by default and only in Experimental; on, it '
      'saves event_rules_enabled and shows Manage rules', (tester) async {
    final repos = openTestRepositories();
    final on = await _pump(
      tester,
      repos,
      const Scaffold(body: SingleChildScrollView(child: EventRulesSection())),
    );
    expect(find.text('Event rules'), findsOneWidget);
    await tester.tap(find.text('Event rules'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('experimental-event-rules'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    final manage = find.byKey(
      const ValueKey('experimental-manage-event-rules'),
    );
    expect(manage, findsNothing);
    expect(await repos.settings.get(kEventRulesEnabledKey), isNull);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(on.value, isTrue);
    expect(await repos.settings.get(kEventRulesEnabledKey), isTrue);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byType(EventRulesScreen), findsOneWidget);
  });

  testWidgets('Manage rules adds, edits and deletes a rule, with Undo', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.savedSearches.create(name: 'Becket', spec: _spec());
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    expect(find.byKey(const ValueKey('event-rules-empty')), findsOneWidget);

    // Add.
    await tester.tap(find.byKey(const ValueKey('event-rules-new')));
    await tester.pumpAndSettle();
    await pickDropdownEntry(
      tester,
      find.byKey(const ValueKey('event-rule-search')),
      'Becket',
    );
    await tester.tap(
      find.byKey(const ValueKey('event-rule-scope-neighbouring')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-rule-save')));
    await tester.pumpAndSettle();
    final sentence =
        'At most 1 dance matching "Becket" in any two neighboring dances';
    await pumpUntilFound(tester, find.text(sentence));
    final rule = (await repos.eventRules.listAll()).single;
    expect(rule.quantifier, EventRuleQuantifier.atMost);
    expect(rule.count, 1);

    // Edit: at least 2 in the whole program, with a name.
    await tester.tap(find.text(sentence));
    await tester.pumpAndSettle();
    await tester.tap(find.text('At least'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-rule-count')), '2');
    await tester.tap(
      find.byKey(const ValueKey('event-rule-scope-wholeProgram')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('event-rule-name')),
      'Two Beckets',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-rule-save')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Two Beckets'));
    expect(
      find.text('At least 2 dances matching "Becket" in the whole program'),
      findsOneWidget,
    );
    final edited = (await repos.eventRules.get(rule.id))!;
    expect(
      (edited.quantifier, edited.count, edited.scope, edited.name),
      (
        EventRuleQuantifier.atLeast,
        2,
        EventRuleScope.wholeProgram,
        'Two Beckets',
      ),
    );

    // Delete, then Undo.
    await tester.tap(find.byKey(ValueKey('event-rule-delete-${rule.id}')));
    await tester.pumpAndSettle();
    expect(await repos.eventRules.listAll(), isEmpty);
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('event-rules-empty')),
    );
    await tester.tap(find.byKey(const ValueKey('event-rule-undo')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Two Beckets'));
    expect((await repos.eventRules.listAll()).single.id, rule.id);
  });

  testWidgets('deleting a saved search a rule uses is refused, naming the '
      'rules; once no rule uses it, it is deleted', (tester) async {
    final repos = openTestRepositories();
    final search = await repos.savedSearches.create(
      name: 'Becket',
      spec: _spec(),
    );
    final named = await repos.eventRules.create(
      savedSearchId: search.id,
      quantifier: EventRuleQuantifier.atMost,
      count: 1,
      scope: EventRuleScope.neighbouring,
      name: 'No two Beckets',
    );
    final unnamed = await repos.eventRules.create(
      savedSearchId: search.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.afterFirstBreak,
    );
    await _pump(
      tester,
      repos,
      const Scaffold(body: CollectionSection(isActive: true)),
    );
    final delete = find.byKey(
      ValueKey('settings-saved-search-delete-${search.id}'),
    );
    await pumpUntilFound(tester, delete);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('saved-search-in-use'));
    await pumpUntilFound(tester, dialog);
    for (final text in [
      'No two Beckets',
      'At most 1 dance matching "Becket" in any two neighboring dances',
      'No dance matching "Becket" after the first break',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await repos.savedSearches.get(search.id), isNotNull);

    // A rule in the trash does not count; once neither uses it, it goes.
    await repos.eventRules.delete(named.id);
    await repos.eventRules.delete(unnamed.id);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-search-in-use')), findsNothing);
    expect(await repos.savedSearches.get(search.id), isNull);
  });
}
