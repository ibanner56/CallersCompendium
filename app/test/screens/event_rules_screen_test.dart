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
import 'package:compendium_app/src/widgets/app_bar_text_action.dart';

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
      find.byKey(const ValueKey('event-rule-nickname')),
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
      (edited.quantifier, edited.count, edited.scope, edited.nickname),
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
      nickname: 'No two Beckets',
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

  testWidgets('with Event rules off, the refusal says where the rules are '
      'and Manage rules opens them there and then; on, it offers only Manage '
      'rules', (tester) async {
    final repos = openTestRepositories();
    final search = await repos.savedSearches.create(
      name: 'Becket',
      spec: _spec(),
    );
    await repos.eventRules.create(
      savedSearchId: search.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.wholeProgram,
      nickname: 'No Beckets',
    );
    final on = await _pump(
      tester,
      repos,
      const Scaffold(body: CollectionSection(isActive: true)),
    );
    final delete = find.byKey(
      ValueKey('settings-saved-search-delete-${search.id}'),
    );
    await pumpUntilFound(tester, delete);
    const offText =
        'Event rules is off, but Manage rules can change your rules now. To '
        'check programs against them, turn on "Check programs against your '
        'rules" under Settings ▸ Experimental ▸ Event rules.';
    final manage = find.byKey(
      const ValueKey('saved-search-in-use-manage-rules'),
    );

    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text(offText), findsOneWidget);
    expect(manage, findsOneWidget);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byType(EventRulesScreen), findsOneWidget);
    expect(find.text('No Beckets'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-search-in-use')), findsNothing);

    on.value = true;
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text(offText), findsNothing);
    expect(manage, findsOneWidget);
    expect(await repos.savedSearches.get(search.id), isNotNull);
  });

  testWidgets('for any two neighboring dances the number is what a pair can '
      'hold: at most 1, at least 1 or 2', (tester) async {
    final repos = openTestRepositories();
    await repos.savedSearches.create(name: 'Becket', spec: _spec());
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    await tester.tap(find.byKey(const ValueKey('event-rules-new')));
    await tester.pumpAndSettle();
    await pickDropdownEntry(
      tester,
      find.byKey(const ValueKey('event-rule-search')),
      'Becket',
    );
    final count = find.byKey(const ValueKey('event-rule-count'));
    final save = find.byKey(const ValueKey('event-rule-save'));
    String countText() => tester.widget<TextField>(count).controller!.text;
    bool canSave() => tester.widget<AppBarTextAction>(save).onPressed != null;

    // At most 5 in the whole program is fine; for a pair, it becomes 1.
    await tester.enterText(count, '5');
    await tester.pumpAndSettle();
    expect(canSave(), isTrue);
    await tester.tap(
      find.byKey(const ValueKey('event-rule-scope-neighbouring')),
    );
    await tester.pumpAndSettle();
    expect(countText(), '1');
    expect(
      find.text('Two neighboring dances hold at most 2 matching dances.'),
      findsOneWidget,
    );
    await tester.enterText(count, '2');
    await tester.pumpAndSettle();
    expect(find.text('Enter 1, the only number allowed here.'), findsOneWidget);
    expect(canSave(), isFalse);

    // At least 2 is a pair of matching dances; 3 never is.
    await tester.tap(find.text('At least'));
    await tester.pumpAndSettle();
    expect(canSave(), isTrue);
    await tester.enterText(count, '3');
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 1 to 2.'), findsOneWidget);
    expect(canSave(), isFalse);
    await tester.enterText(count, '2');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final rule = (await repos.eventRules.listAll()).single;
    expect(
      (rule.quantifier, rule.count, rule.scope),
      (EventRuleQuantifier.atLeast, 2, EventRuleScope.neighbouring),
    );
  });

  testWidgets('a rule whose stored number is past what its scope now allows '
      'can still be renamed and saved as it is; the number is checked once '
      'it, the quantifier or the scope changes', (tester) async {
    final repos = openTestRepositories();
    final search = await repos.savedSearches.create(
      name: 'Becket',
      spec: _spec(),
    );
    // Stored by an older build, before a pair allowed at most 1.
    final rule = await repos.eventRules.create(
      savedSearchId: search.id,
      quantifier: EventRuleQuantifier.atMost,
      count: 3,
      scope: EventRuleScope.neighbouring,
    );
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    const sentence =
        'At most 3 dances matching "Becket" in any two neighboring dances';
    await pumpUntilFound(tester, find.text(sentence));
    await tester.tap(find.text(sentence));
    await tester.pumpAndSettle();
    final count = find.byKey(const ValueKey('event-rule-count'));
    final save = find.byKey(const ValueKey('event-rule-save'));
    bool canSave() => tester.widget<AppBarTextAction>(save).onPressed != null;
    expect(tester.widget<TextField>(count).controller!.text, '3');
    expect(find.text('Enter 1, the only number allowed here.'), findsNothing);
    expect(canSave(), isTrue);

    // Changing the number checks it.
    await tester.enterText(count, '2');
    await tester.pumpAndSettle();
    expect(find.text('Enter 1, the only number allowed here.'), findsOneWidget);
    expect(canSave(), isFalse);
    await tester.enterText(count, '3');
    await tester.pumpAndSettle();
    expect(canSave(), isFalse, reason: 'changed, so checked');

    // Opened again: a rename alone saves the rule with its number.
    Navigator.of(tester.element(count)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text(sentence));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('event-rule-nickname')),
      'Beckets apart',
    );
    await tester.pumpAndSettle();
    expect(canSave(), isTrue);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final stored = (await repos.eventRules.get(rule.id))!;
    expect(stored.nickname, 'Beckets apart');
    expect(
      (stored.quantifier, stored.count, stored.scope),
      (EventRuleQuantifier.atMost, 3, EventRuleScope.neighbouring),
    );
  });

  group('#2341', () {
    testWidgets('a nickname set in the editor is the title with the '
        'sentence beneath it; cleared, the sentence is the title again', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final search = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      final rule = await repos.eventRules.create(
        savedSearchId: search.id,
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
      );
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      const sentence = 'At most 1 dance matching "Becket" in the whole program';
      final row = find.byKey(ValueKey('event-rule-${rule.id}'));
      ListTile tile() => tester.widget<ListTile>(
        find.descendant(of: row, matching: find.byType(ListTile)),
      );
      await pumpUntilFound(tester, row);
      expect((tile().title! as Text).data, sentence);

      Future<void> setNickname(String text) async {
        await tester.tap(find.text(sentence).first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('event-rule-nickname')),
          text,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('event-rule-save')));
        await tester.pumpAndSettle();
      }

      await setNickname('Family');
      await pumpUntilFound(tester, find.text('Family'));
      expect((tile().title! as Text).data, 'Family');
      expect(
        find.descendant(of: row, matching: find.text(sentence)),
        findsOneWidget,
        reason: 'the sentence beneath the nickname',
      );
      expect((await repos.eventRules.get(rule.id))!.nickname, 'Family');

      await setNickname('   ');
      await pumpUntil(
        tester,
        () => find.text('Family').evaluate().isEmpty,
        description: 'the nickname gone',
      );
      expect((tile().title! as Text).data, sentence);
      expect(
        find.descendant(of: row, matching: find.text(sentence)),
        findsOneWidget,
        reason: 'shown once, as the title',
      );
      expect((await repos.eventRules.get(rule.id))!.nickname, isNull);
    });

    testWidgets('Manage rules reorders by move up / move down and by drag, '
        'and stores the order', (tester) async {
      final repos = openTestRepositories();
      final search = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      final ids = [
        for (final name in ['A', 'B', 'C'])
          (await repos.eventRules.create(
            savedSearchId: search.id,
            quantifier: EventRuleQuantifier.atMost,
            count: 1,
            scope: EventRuleScope.wholeProgram,
            nickname: name,
          )).id,
      ];
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      await pumpUntilFound(tester, find.text('C'));
      Future<List<String>> stored() async => [
        for (final r in await repos.eventRules.listAll()) r.nickname!,
      ];
      List<String> shown() {
        final titles = ['A', 'B', 'C'];
        final tops = {
          for (final t in titles) t: tester.getTopLeft(find.text(t)).dy,
        };
        return titles..sort((a, b) => tops[a]!.compareTo(tops[b]!));
      }

      IconButton button(String id, String which) => tester.widget<IconButton>(
        find.byKey(ValueKey('event-rule-$id-move-$which')),
      );
      expect(button(ids[0], 'up').onPressed, isNull, reason: 'first');
      expect(button(ids[2], 'down').onPressed, isNull, reason: 'last');
      expect(button(ids[0], 'up').tooltip, 'Move A up');

      await tester.tap(find.byKey(ValueKey('event-rule-${ids[2]}-move-up')));
      await tester.pumpAndSettle();
      expect(await stored(), ['A', 'C', 'B']);
      expect(shown(), ['A', 'C', 'B']);

      await tester.tap(find.byKey(ValueKey('event-rule-${ids[0]}-move-down')));
      await tester.pumpAndSettle();
      expect(await stored(), ['C', 'A', 'B']);

      // Drag: each row has its own handle, labelled for a screen reader.
      final list = find.byType(ReorderableListView);
      expect(
        find.descendant(
          of: list,
          matching: find.byType(ReorderableDragStartListener),
        ),
        findsNWidgets(3),
      );
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Drag to reorder B')),
        findsOneWidget,
      );
      semantics.dispose();
      tester.widget<ReorderableListView>(list).onReorderItem!(2, 0);
      await tester.pumpAndSettle();
      expect(await stored(), ['B', 'C', 'A']);
      await pumpUntil(
        tester,
        () => shown().first == 'B',
        description: 'B first',
      );
      expect(shown(), ['B', 'C', 'A']);
    });

    testWidgets('Rule order shows with Event rules on, My order by default, '
        'and stores Most used', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        const Scaffold(body: SingleChildScrollView(child: EventRulesSection())),
        enabled: true,
      );
      final field = find.byKey(
        const ValueKey('experimental-event-rule-order-field'),
      );
      await pumpUntilFound(tester, field);
      expect(find.text('Rule order'), findsOneWidget);
      expect(find.text('My order'), findsOneWidget);
      expect(await repos.settings.get(kEventRuleOrderKey), isNull);

      await pickDropdownEntry(tester, field, 'Most used');
      await tester.pumpAndSettle();
      expect(await repos.settings.get(kEventRuleOrderKey), 'mostUsed');
      expect(
        find.text(
          'The rule picker lists first the rules your programs use most, '
          'not counting programs in Recently deleted.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Rule order shows a value that arrives while it is open, as '
        'by Device Sync or a restore', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        const Scaffold(body: SingleChildScrollView(child: EventRulesSection())),
        enabled: true,
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('experimental-event-rule-order-field')),
      );
      expect(find.text('My order'), findsOneWidget);

      await repos.settings.set(kEventRuleOrderKey, 'mostUsed');
      await pumpUntilFound(tester, find.text('Most used'));
      expect(find.text('My order'), findsNothing);
    });
  });
}
