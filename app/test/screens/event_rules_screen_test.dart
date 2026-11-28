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
import 'package:compendium_app/src/widgets/empty_state.dart';
import 'package:compendium_app/src/widgets/load_error_view.dart';

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

  testWidgets("Check Perform's Swap this dance (#2347): shown only while "
      'Event rules is on, on by default with nothing saved, and saves '
      'event_rules_check_perform_swap as a bool', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final on = ValueNotifier(false);
    addTearDown(on.dispose);
    // As the app builds it: on with no stored value.
    final checkSwap = ValueNotifier(true);
    addTearDown(checkSwap.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: EventRulesEnabledScope(
            notifier: on,
            child: EventRulesCheckPerformSwapScope(
              notifier: checkSwap,
              child: child!,
            ),
          ),
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: EventRulesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event rules'));
    await tester.pumpAndSettle();
    final swapSwitch = find.byKey(
      const ValueKey('experimental-event-rules-perform-swap'),
    );
    expect(swapSwitch, findsNothing, reason: 'Event rules is off');

    on.value = true;
    await tester.pumpAndSettle();
    expect(swapSwitch, findsOneWidget);
    expect(find.text("Check Perform's Swap this dance"), findsOneWidget);
    expect(tester.widget<SwitchListTile>(swapSwitch).value, isTrue);
    expect(await repos.settings.get(kEventRulesCheckPerformSwapKey), isNull);

    await tester.tap(swapSwitch);
    await tester.pumpAndSettle();
    expect(checkSwap.value, isFalse);
    expect(await repos.settings.get(kEventRulesCheckPerformSwapKey), isFalse);
    await tester.tap(swapSwitch);
    await tester.pumpAndSettle();
    expect(checkSwap.value, isTrue);
    expect(await repos.settings.get(kEventRulesCheckPerformSwapKey), isTrue);
  });

  testWidgets('with no ancestor, the setting reads as on, and checks only '
      'while Event rules is on', (tester) async {
    late bool stored;
    late bool active;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          stored = EventRulesCheckPerformSwapScope.of(context);
          active = EventRulesCheckPerformSwapScope.activeOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(stored, isTrue);
    expect(active, isFalse, reason: 'Event rules is off by default');
  });

  testWidgets('a failed read of the saved search names still lists the rules, '
      'flagging only a newer-version rule; a good read flags a gone search', (
    tester,
  ) async {
    final db = openWidgetTestDatabase();
    final settings = FailingSavedSearchReadsSettings(db);
    final repos = CompendiumRepositories(
      db,
      contraTaxonomy,
      settings: settings,
    );
    final becket = await repos.savedSearches.create(
      name: 'Becket',
      spec: _spec(),
    );
    await repos.eventRules.create(
      savedSearchId: becket.id,
      quantifier: EventRuleQuantifier.atMost,
      count: 1,
      scope: EventRuleScope.wholeProgram,
    );
    // Its saved search is not stored, as a sync can bring it.
    await repos.eventRules.writeFromSync(
      const EventRule(
        id: 'rule-gone',
        savedSearchId: 'search-gone',
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
        nickname: 'Lost search',
      ),
    );
    // A newer version of the app wrote it.
    await repos.eventRules.writeFromSync(
      EventRule(
        id: 'rule-newer',
        savedSearchId: becket.id,
        quantifierName: 'mostly',
        count: 1,
        scopeName: 'wholeProgram',
        nickname: 'From the future',
      ),
    );
    settings.failSearchReads = true;
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    await pumpUntilFound(tester, find.text('Lost search'));

    Finder needsAttention(String id) => find.descendant(
      of: find.byKey(ValueKey('event-rule-$id')),
      matching: find.text('Needs attention'),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('From the future'), findsOneWidget);
    // Not read is not gone: no rule is flagged for its search.
    expect(needsAttention('rule-gone'), findsNothing);
    expect(needsAttention('rule-newer'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);

    // The next change to the rules reads the names again.
    settings.failSearchReads = false;
    await repos.eventRules.create(
      savedSearchId: becket.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.beforeFirstBreak,
    );
    await pumpUntilFound(tester, needsAttention('rule-gone'));
    expect(needsAttention('rule-newer'), findsOneWidget);

    // A later failed read: a rule a sync brings with a new saved search is
    // not flagged from the names last read, which lack that search.
    final late = await repos.savedSearches.create(
      name: 'Late search',
      spec: _spec(),
    );
    settings.failSearchReads = true;
    await repos.eventRules.writeFromSync(
      EventRule(
        id: 'rule-late',
        savedSearchId: late.id,
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
        nickname: 'Late rule',
      ),
    );
    await pumpUntilFound(tester, find.text('Late rule'));
    expect(needsAttention('rule-late'), findsNothing);
    expect(needsAttention('rule-gone'), findsNothing);
    expect(needsAttention('rule-newer'), findsOneWidget);
  });

  testWidgets('Manage rules adds, edits and deletes a rule, with Undo', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.savedSearches.create(name: 'Becket', spec: _spec());
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    expect(find.byKey(const ValueKey('event-rules-empty')), findsOneWidget);

    // Add, from the empty state's own button.
    await tester.tap(find.byKey(const ValueKey('event-rules-empty-add')));
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

  // Audit F-05: the manager uses the shared patterns the other managers do.
  group('Manage rules, shared patterns', () {
    Future<List<EventRule>> seedRules(CompendiumRepositories repos) async {
      final search = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      return [
        for (final name in ['A', 'B'])
          await repos.eventRules.create(
            savedSearchId: search.id,
            quantifier: EventRuleQuantifier.atMost,
            count: 1,
            scope: EventRuleScope.wholeProgram,
            nickname: name,
          ),
      ];
    }

    testWidgets('empty, it shows the shared empty state with its own New '
        'rule button, and no floating one', (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      final empty = find.byKey(const ValueKey('event-rules-empty'));
      expect(tester.widget(empty), isA<EmptyState>());
      expect(
        find.byKey(const ValueKey('event-rules-empty-add')),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('in a short window (a phone in landscape) New rule folds to '
        'its icon, named by its tooltip', (tester) async {
      final repos = openTestRepositories();
      await seedRules(repos);
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      await pumpUntilFound(tester, find.text('B'));
      FloatingActionButton fab() => tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('event-rules-new')),
      );
      expect(fab().isExtended, isTrue);

      await tester.binding.setSurfaceSize(const Size(800, 360));
      await tester.pumpAndSettle();
      expect(fab().isExtended, isFalse);
      expect(fab().tooltip, 'New rule…');
    });

    testWidgets('a failed read of the rules says so with Try again, not a '
        'spinner that never ends', (tester) async {
      final repos = openTestRepositories();
      await seedRules(repos);
      // The rules table is gone, as a damaged database's can be.
      await repos.db.customStatement('DROP TABLE event_rules');
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LoadErrorView), findsOneWidget);
      expect(
        find.text("Couldn't load your rules. Nothing was changed. Try again."),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      // Try again reads again (and fails again here), rather than doing
      // nothing.
      await tester.tap(find.byKey(const ValueKey('load-error-retry')));
      await tester.pumpAndSettle();
      expect(find.byType(LoadErrorView), findsOneWidget);
    });

    testWidgets('a failed delete says the rule was not deleted', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final rules = await seedRules(repos);
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      await pumpUntilFound(tester, find.text('B'));
      await repos.db.customStatement('DROP TABLE event_rules');
      await tester.tap(
        find.byKey(ValueKey('event-rule-delete-${rules.first.id}')),
      );
      await tester.pumpAndSettle();
      final snack = find.byKey(const ValueKey('event-rule-delete-failed'));
      expect(snack, findsOneWidget);
      expect(
        find.descendant(
          of: snack,
          matching: find.text("Couldn't delete the rule. Try again."),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('event-rule-undo')), findsNothing);
    });

    testWidgets('a failed move says so and puts the rule back', (tester) async {
      final repos = openTestRepositories();
      final rules = await seedRules(repos);
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      await pumpUntilFound(tester, find.text('B'));
      await repos.db.customStatement('DROP TABLE event_rules');
      await tester.tap(
        find.byKey(ValueKey('event-rule-${rules.first.id}-move-down')),
      );
      await tester.pumpAndSettle();
      final snack = find.byKey(const ValueKey('event-rule-move-failed'));
      expect(snack, findsOneWidget);
      expect(
        find.descendant(
          of: snack,
          matching: find.text("Couldn't move the rule. Try again."),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('A')).dy,
        lessThan(tester.getTopLeft(find.text('B')).dy),
      );
    });
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

  group('leaving the rule editor (pre-release audit finding F-02)', () {
    Future<void> openNew(
      WidgetTester tester,
      CompendiumRepositories repos,
    ) async {
      await repos.savedSearches.create(name: 'Becket', spec: _spec());
      await _pump(tester, repos, const EventRulesScreen(), enabled: true);
      await tester.tap(find.byKey(const ValueKey('event-rules-new')));
      await tester.pumpAndSettle();
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('event-rule-nickname')),
      );
    }

    testWidgets('with a typed nickname, Close asks first; Keep editing keeps '
        'it, and Discard leaves saving nothing', (tester) async {
      final repos = openTestRepositories();
      await openNew(tester, repos);
      final nickname = find.byKey(const ValueKey('event-rule-nickname'));
      await tester.enterText(nickname, 'No Beckets twice');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(nickname).controller!.text,
        'No Beckets twice',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(EventRuleEditorScreen), findsNothing);
      expect(await repos.eventRules.listAll(includeDeleted: true), isEmpty);
    });

    testWidgets('a changed choice asks first too', (tester) async {
      final repos = openTestRepositories();
      await openNew(tester, repos);
      await tester.tap(
        find.byKey(const ValueKey('event-rule-scope-neighbouring')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
    });

    testWidgets('untouched, it leaves without asking', (tester) async {
      final repos = openTestRepositories();
      await openNew(tester, repos);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsNothing);
      expect(find.byType(EventRuleEditorScreen), findsNothing);
    });

    testWidgets('editing a rule whose saved search is gone, untouched, '
        'leaves without asking', (tester) async {
      final repos = openTestRepositories();
      await repos.savedSearches.create(name: 'Becket', spec: _spec());
      // A rule naming a saved search that is no longer there (deleted on a
      // peer, say): the editor opens with no search chosen.
      final rule = EventRule.of(
        id: 'r1',
        savedSearchId: 'gone',
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        position: 0,
      );
      await _pump(
        tester,
        repos,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => EventRuleEditorScreen(rule: rule),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('event-rule-nickname')),
      );
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsNothing);
      expect(find.byType(EventRuleEditorScreen), findsNothing);
    });
  });

  testWidgets('a saved search deleted while the editor is open: Save says '
      'so, adds no rule and clears the choice (#2529)', (tester) async {
    final repos = openTestRepositories();
    final search = await repos.savedSearches.create(
      name: 'Becket',
      spec: _spec(),
    );
    await _pump(tester, repos, const EventRulesScreen(), enabled: true);
    await tester.tap(find.byKey(const ValueKey('event-rules-new')));
    await tester.pumpAndSettle();
    await pickDropdownEntry(
      tester,
      find.byKey(const ValueKey('event-rule-search')),
      'Becket',
    );
    // Deleted elsewhere (the Collection, or a peer by sync) meanwhile.
    await repos.savedSearches.delete(search.id);

    await tester.tap(find.byKey(const ValueKey('event-rule-save')));
    await tester.pumpAndSettle();

    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('event-rule-saved-search-gone')),
    );
    expect(
      find.text(
        "That saved search was just deleted, so the rule wasn't saved. "
        'Choose another.',
      ),
      findsOneWidget,
    );
    expect(await repos.eventRules.listAll(includeDeleted: true), isEmpty);
    // Still in the editor, which now offers only what is left: nothing.
    await pumpUntilFound(
      tester,
      find.text(
        'Save a search in the Collection first: a rule uses a saved search '
        'to say which dances it means.',
      ),
    );
    expect(find.byKey(const ValueKey('event-rule-save')), findsOneWidget);
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

  group('the rule editor', () {
    Future<void> openEditor(
      WidgetTester tester,
      CompendiumRepositories repos, [
      EventRule? rule,
    ]) async {
      await _pump(
        tester,
        repos,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventRuleEditor(context, rule: rule),
            child: const Text('open'),
          ),
        ),
        enabled: true,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('event-rule-nickname')),
      );
    }

    final save = find.byKey(const ValueKey('event-rule-save'));
    VoidCallback? saveAction(WidgetTester tester) =>
        tester.widget<AppBarTextAction>(save).onPressed;

    testWidgets('a rule whose saved search is gone says so, and can be '
        'renamed and saved, keeping its search', (tester) async {
      final repos = openTestRepositories();
      await repos.savedSearches.create(name: 'Becket', spec: _spec());
      // Its saved search was deleted on another device: the rule arrives (or
      // stays) naming a search that is not stored.
      const rule = EventRule(
        id: 'rule-gone',
        savedSearchId: 'search-gone',
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
      );
      await repos.eventRules.writeFromSync(rule);
      await openEditor(tester, repos, rule);

      expect(find.text('Needs attention'), findsOneWidget);
      expect(
        find.text(
          "Its saved search was deleted or can't be read, so it is not "
          'checked.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-rule-nickname')),
        'One per night',
      );
      await tester.pumpAndSettle();
      expect(saveAction(tester), isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.byType(EventRuleEditorScreen), findsNothing);
      final stored = (await repos.eventRules.get('rule-gone'))!;
      expect(stored.nickname, 'One per night');
      expect(stored.savedSearchId, 'search-gone');
    });

    testWidgets('a newly chosen search deleted before Save is refused, and the '
        "rule's own gone search is still kept for a rename", (tester) async {
      final repos = openTestRepositories();
      final becket = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      const rule = EventRule(
        id: 'rule-gone',
        savedSearchId: 'search-gone',
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
      );
      await repos.eventRules.writeFromSync(rule);
      await openEditor(tester, repos, rule);
      await pickDropdownEntry(
        tester,
        find.byKey(const ValueKey('event-rule-search')),
        'Becket',
      );
      await tester.pumpAndSettle();
      // Deleted elsewhere meanwhile.
      await repos.savedSearches.delete(becket.id);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('event-rule-saved-search-gone')),
      );
      expect(
        (await repos.eventRules.get('rule-gone'))!.savedSearchId,
        'search-gone',
      );

      // The rule's own search is still kept: a rename saves.
      await tester.enterText(
        find.byKey(const ValueKey('event-rule-nickname')),
        'One per night',
      );
      await tester.pumpAndSettle();
      expect(saveAction(tester), isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final stored = (await repos.eventRules.get('rule-gone'))!;
      expect(stored.nickname, 'One per night');
      expect(stored.savedSearchId, 'search-gone');
    });

    testWidgets('when the saved searches cannot be read, the editor says so '
        'rather than spinning, and a rule can still be renamed', (
      tester,
    ) async {
      final db = openWidgetTestDatabase();
      final settings = FailingSavedSearchReadsSettings(db);
      final repos = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: settings,
      );
      final becket = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      final rule = await repos.eventRules.create(
        savedSearchId: becket.id,
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
      );
      settings.failSearchReads = true;
      await openEditor(tester, repos, rule);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('event-rule-searches-unreadable')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Your saved searches can't be read right now, so none can be "
          'chosen here.',
        ),
        findsOneWidget,
      );
      // Not read is not gone, and not "save a search first".
      expect(find.text('Needs attention'), findsNothing);
      expect(
        find.byKey(const ValueKey('event-rule-no-searches')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-rule-nickname')),
        'One Becket',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final stored = (await repos.eventRules.get(rule.id))!;
      expect(stored.nickname, 'One Becket');
      expect(stored.savedSearchId, becket.id);
    });

    testWidgets('at the rule limit, Save says why and keeps the editor open', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final becket = await repos.savedSearches.create(
        name: 'Becket',
        spec: _spec(),
      );
      for (var i = 0; i < maxEventRules; i++) {
        await repos.eventRules.writeFromSync(
          EventRule(
            id: 'r$i',
            savedSearchId: becket.id,
            quantifierName: 'atMost',
            count: 1,
            scopeName: 'wholeProgram',
            position: i,
          ),
        );
      }
      await openEditor(tester, repos);
      await pickDropdownEntry(
        tester,
        find.byKey(const ValueKey('event-rule-search')),
        'Becket',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      final snack = find.byKey(const ValueKey('event-rule-save-failed'));
      expect(snack, findsOneWidget);
      expect(
        find.descendant(
          of: snack,
          matching: find.text(
            'This device holds $maxEventRules rules, the most it can. Delete '
            'one to add another.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(EventRuleEditorScreen), findsOneWidget);
      expect(saveAction(tester), isNotNull, reason: 'Save can be tried again');
      expect(await repos.eventRules.listAll(), hasLength(maxEventRules));
    });

    testWidgets('a failed write says the rule was not saved', (tester) async {
      final repos = openTestRepositories();
      await repos.savedSearches.create(name: 'Becket', spec: _spec());
      await openEditor(tester, repos);
      await pickDropdownEntry(
        tester,
        find.byKey(const ValueKey('event-rule-search')),
        'Becket',
      );
      await tester.pumpAndSettle();
      // The rules table is gone, as a damaged database's can be.
      await repos.db.customStatement('DROP TABLE event_rules');
      await tester.tap(save);
      await tester.pumpAndSettle();

      final snack = find.byKey(const ValueKey('event-rule-save-failed'));
      expect(snack, findsOneWidget);
      expect(
        find.descendant(
          of: snack,
          matching: find.text("Couldn't save the rule. Try again."),
        ),
        findsOneWidget,
      );
      expect(find.byType(EventRuleEditorScreen), findsOneWidget);
    });
  });
}
