// Event rules on a program template (#2342): the template editor's Rules row
// (only while Event rules is on), the list kept through a save with the
// feature off, a deleted rule shown as removed and brought back by Undo, a
// nicknamed rule's sentence shown beneath it, a rule whose saved search is
// gone marked as needing attention, a duplicate keeping the rules, and New
// program starting with exactly the template's live rules.
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/settings/program_templates_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/pump_until.dart';
import 'support/saved_searches.dart';
import 'support/test_repositories.dart';

Future<EventRule> _rule(CompendiumRepositories repos, String nickname) async {
  await storeSavedSearches(repos.settings, ['search-1']);
  return repos.eventRules.create(
    savedSearchId: 'search-1',
    quantifier: EventRuleQuantifier.atMost,
    count: 1,
    scope: EventRuleScope.wholeProgram,
    nickname: nickname,
  );
}

Future<ValueNotifier<bool>> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  Widget home, {
  required bool enabled,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final on = ValueNotifier<bool>(enabled);
  addTearDown(on.dispose);
  final confirm = ValueNotifier<bool>(false);
  addTearDown(confirm.dispose);
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  // The scope is what the screens show; the stored setting is what the
  // shared function a program is made by reads. The app keeps them equal.
  await repos.settings.set(kEventRulesEnabledKey, enabled);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ConfirmBeforeDeleteScope(
          notifier: confirm,
          child: ActiveDialectScope(
            notifier: dialect,
            child: EventRulesEnabledScope(notifier: on, child: child!),
          ),
        ),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return on;
}

Future<ProgramTemplate> _stored(
  CompendiumRepositories repos,
  String id,
) async => (await loadProgramTemplates(repos.settings)).byId(id)!;

final _rulesRow = find.byKey(const ValueKey('program-template-rules'));

void main() {
  testWidgets('with Event rules on, the Rules row adds and removes rules '
      'through the rule picker, and each change is saved', (tester) async {
    final repos = openTestRepositories();
    final family = await _rule(repos, 'Family friendly');
    final easy = await _rule(repos, 'Easy start');
    const template = ProgramTemplate(id: 't', name: 'Family dance');
    await saveProgramTemplate(repos.settings, template);
    await _pump(
      tester,
      repos,
      const ProgramTemplateEditorScreen(template: template),
      enabled: true,
    );

    expect(_rulesRow, findsOneWidget);
    expect(
      find.descendant(of: _rulesRow, matching: find.text('None')),
      findsOneWidget,
    );
    await tester.tap(_rulesRow);
    await tester.pumpAndSettle();
    expect(find.text('Rules for this template'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('program-rules-new')),
      findsOneWidget,
      reason: 'the same picker, New rule… pinned',
    );
    await tester.tap(find.byKey(ValueKey('program-rule-${easy.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('program-rule-${family.id}')));
    await tester.pumpAndSettle();
    expect((await _stored(repos, 't')).eventRuleIds, [easy.id, family.id]);

    await tester.tap(find.byKey(ValueKey('program-rule-${easy.id}')));
    await tester.pumpAndSettle();
    expect((await _stored(repos, 't')).eventRuleIds, [family.id]);

    Navigator.of(tester.element(find.text('Rules for this template'))).pop();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _rulesRow, matching: find.text('Family friendly')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _rulesRow, matching: find.text('Easy start')),
      findsNothing,
    );
  });

  testWidgets('with Event rules off there is no Rules row, but a save keeps '
      "the template's rules, which are used again once it is back on", (
    tester,
  ) async {
    final repos = openTestRepositories();
    final family = await _rule(repos, 'Family friendly');
    final template = ProgramTemplate(
      id: 't',
      name: 'Family dance',
      eventRuleIds: [family.id],
    );
    await saveProgramTemplate(repos.settings, template);
    final on = await _pump(
      tester,
      repos,
      ProgramTemplateEditorScreen(template: template),
      enabled: false,
    );

    expect(_rulesRow, findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('program-template-editor-name')),
      'Family night',
    );
    await tester.tap(
      find.byKey(const ValueKey('program-template-insert-break')),
    );
    await tester.pumpAndSettle();
    final saved = await _stored(repos, 't');
    expect(saved.name, 'Family night', reason: 'the edits were saved');
    expect(saved.entries, isNotEmpty, reason: 'the edits were saved');
    expect(saved.eventRuleIds, [family.id]);
    expect(
      await newProgramEventRuleIds(repos, saved),
      isEmpty,
      reason: 'a program made while it is off gets no rules',
    );

    on.value = true;
    await repos.settings.set(kEventRulesEnabledKey, true);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _rulesRow, matching: find.text('Family friendly')),
      findsOneWidget,
    );
    expect(await newProgramEventRuleIds(repos, await _stored(repos, 't')), [
      family.id,
    ]);
  });

  testWidgets('a deleted rule is shown as removed, and the Undo of its delete '
      'brings it back on the template', (tester) async {
    final repos = openTestRepositories();
    final family = await _rule(repos, 'Family friendly');
    final easy = await _rule(repos, 'Easy start');
    final template = ProgramTemplate(
      id: 't',
      name: 'Family dance',
      eventRuleIds: [family.id, easy.id, 'never-here'],
    );
    await saveProgramTemplate(repos.settings, template);
    await _pump(
      tester,
      repos,
      ProgramTemplateEditorScreen(template: template),
      enabled: true,
    );
    Finder line(String id) => find.byKey(ValueKey('program-template-rule-$id'));
    String text(String id) => tester.widget<Text>(line(id)).data!;

    expect(text(family.id), 'Family friendly');
    expect(text('never-here'), "Removed: a rule that isn't on this device");

    await repos.eventRules.delete(family.id);
    await pumpUntilFound(tester, find.text('Removed: Family friendly'));
    // Saving the template meanwhile keeps the deleted rule's id.
    await tester.tap(
      find.byKey(const ValueKey('program-template-insert-break')),
    );
    await tester.pumpAndSettle();
    expect((await _stored(repos, 't')).eventRuleIds, [
      family.id,
      easy.id,
      'never-here',
    ]);
    expect(await newProgramEventRuleIds(repos, await _stored(repos, 't')), [
      easy.id,
    ]);

    // Undo of the rule's delete.
    await repos.eventRules.restore(family.id);
    await pumpUntilFound(tester, find.text('Family friendly'));
    expect(text(family.id), 'Family friendly');
    expect(await newProgramEventRuleIds(repos, await _stored(repos, 't')), [
      family.id,
      easy.id,
    ]);
  });

  testWidgets('a nicknamed rule shows its sentence beneath its nickname, '
      'removed or not; a rule without one shows its sentence once', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final facets = FacetSelections()..formations.add(FormationShape.becketCcw);
    final becket = await repos.savedSearches.create(
      name: 'Becket',
      spec: SavedSearchSpec.fromPanelState(
        CollectionPanelState(facets: facets),
        today: DateTime.utc(2026, 1, 1),
      ).value!,
    );
    final named = await repos.eventRules.create(
      savedSearchId: becket.id,
      quantifier: EventRuleQuantifier.atMost,
      count: 1,
      scope: EventRuleScope.wholeProgram,
      nickname: 'One becket',
    );
    final plain = await repos.eventRules.create(
      savedSearchId: becket.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.beforeFirstBreak,
    );
    final template = ProgramTemplate(
      id: 't',
      name: 'Family dance',
      eventRuleIds: [named.id, plain.id],
    );
    await saveProgramTemplate(repos.settings, template);
    await _pump(
      tester,
      repos,
      ProgramTemplateEditorScreen(template: template),
      enabled: true,
    );
    Finder sentence(String id) =>
        find.byKey(ValueKey('program-template-rule-$id-sentence'));
    const namedSentence =
        'At most 1 dance matching "Becket" in the whole program';
    await pumpUntilFound(tester, find.text(namedSentence));

    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey('program-template-rule-${named.id}')),
          )
          .data,
      'One becket',
    );
    expect(tester.widget<Text>(sentence(named.id)).data, namedSentence);
    // Its line is its sentence already: not shown twice.
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey('program-template-rule-${plain.id}')),
          )
          .data,
      'No dance matching "Becket" before the first break',
    );
    expect(sentence(plain.id), findsNothing);

    // A deleted rule, shown as removed, still says what it required.
    await repos.eventRules.delete(named.id);
    await pumpUntilFound(tester, find.text('Removed: One becket'));
    expect(tester.widget<Text>(sentence(named.id)).data, namedSentence);
  });

  testWidgets(
    'a live rule whose saved search is gone needs attention, as in '
    'Manage rules; a rule whose search is there, or a removed one, does not',
    (tester) async {
      final repos = openTestRepositories();
      final facets = FacetSelections()
        ..formations.add(FormationShape.becketCcw);
      final becket = await repos.savedSearches.create(
        name: 'Becket',
        spec: SavedSearchSpec.fromPanelState(
          CollectionPanelState(facets: facets),
          today: DateTime.utc(2026, 1, 1),
        ).value!,
      );
      final fine = await repos.eventRules.create(
        savedSearchId: becket.id,
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        nickname: 'One becket',
      );
      // A rule whose saved search is not stored, as a sync can bring it (its
      // search deleted on another device). [_rule]'s search is stored.
      const gone = EventRule(
        id: 'rule-gone',
        savedSearchId: 'search-gone',
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
        nickname: 'Lost search',
      );
      await repos.eventRules.writeFromSync(gone);
      // Removed, and its search is not stored either: still not flagged.
      const removed = EventRule(
        id: 'rule-removed',
        savedSearchId: 'search-gone',
        quantifierName: 'atMost',
        count: 1,
        scopeName: 'wholeProgram',
        nickname: 'Old rule',
      );
      await repos.eventRules.writeFromSync(removed);
      await repos.eventRules.delete(removed.id);
      final template = ProgramTemplate(
        id: 't',
        name: 'Family dance',
        eventRuleIds: [fine.id, gone.id, removed.id],
      );
      await saveProgramTemplate(repos.settings, template);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
        enabled: true,
      );
      Finder attention(String id) =>
          find.byKey(ValueKey('program-template-rule-$id-attention'));
      await pumpUntilFound(tester, attention(gone.id));

      for (final text in [
        'Needs attention',
        "Its saved search was deleted or can't be read, so it is not checked.",
      ]) {
        expect(
          find.descendant(of: attention(gone.id), matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(attention(fine.id), findsNothing);
      expect(find.text('Removed: Old rule'), findsOneWidget);
      expect(attention(removed.id), findsNothing);
    },
  );

  testWidgets('Duplicate keeps the rules, and Rename leaves them alone', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final family = await _rule(repos, 'Family friendly');
    await saveProgramTemplate(
      repos.settings,
      ProgramTemplate(id: 't', name: 'Family', eventRuleIds: [family.id]),
    );
    await saveProgramTemplateOrder(repos.settings, const ['t']);
    await _pump(tester, repos, const ProgramTemplatesScreen(), enabled: false);

    await tester.tap(find.byKey(const ValueKey('program-template-menu-t')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-template-duplicate')));
    await tester.pumpAndSettle();
    final templates = (await loadProgramTemplates(repos.settings)).templates;
    expect(templates, hasLength(2));
    for (final t in templates) {
      expect(t.eventRuleIds, [family.id], reason: t.name);
    }

    await tester.tap(find.byKey(const ValueKey('program-template-menu-t')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-template-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('program-template-name-field')),
      'Family night',
    );
    await tester.tap(find.byKey(const ValueKey('program-template-name-save')));
    await tester.pumpAndSettle();
    final renamed = await _stored(repos, 't');
    expect(renamed.name, 'Family night');
    expect(renamed.eventRuleIds, [family.id]);
  });

  group('New program from a template that carries rules', () {
    Future<(EventRule, EventRule)> seed(CompendiumRepositories repos) async {
      final family = await _rule(repos, 'Family friendly');
      final gone = await _rule(repos, 'Deleted rule');
      await repos.eventRules.delete(gone.id);
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(
          id: 'family',
          name: 'Family',
          entries: const [ProgramTemplateEntry(text: 'Waltz')],
          eventRuleIds: [gone.id, family.id],
        ),
      );
      await saveProgramTemplate(
        repos.settings,
        const ProgramTemplate(id: 'plain', name: 'Plain'),
      );
      await saveProgramTemplateOrder(repos.settings, const ['plain', 'family']);
      await saveProgramTemplateDefault(repos.settings, 'plain');
      return (family, gone);
    }

    Future<Program> makeProgram(
      WidgetTester tester,
      CompendiumRepositories repos, {
      required bool enabled,
    }) async {
      String? savedId;
      await _pump(
        tester,
        repos,
        ProgramEditorScreen(
          onSaved: (id) => savedId = id,
          templateChoice: const ProgramTemplateChoice.template('family'),
        ),
        enabled: enabled,
      );
      expect(find.text('Waltz'), findsOneWidget, reason: 'its slots came');
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Family dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();
      return (await repos.programs.getById(savedId!))!;
    }

    testWidgets("starts with exactly the template's live rules, and a later "
        'edit to the template changes no program made from it', (tester) async {
      final repos = openTestRepositories();
      final (family, _) = await seed(repos);
      final program = await makeProgram(tester, repos, enabled: true);
      expect(program.eventRuleIds, [family.id]);
      expect(find.text('Rules (1)'), findsOneWidget);

      final later = await _rule(repos, 'Later');
      await saveProgramTemplate(
        repos.settings,
        (await _stored(repos, 'family')).copyWith(eventRuleIds: [later.id]),
      );
      expect((await repos.programs.getById(program.id))!.eventRuleIds, [
        family.id,
      ]);
    });

    testWidgets('with Event rules off, starts with no rules', (tester) async {
      final repos = openTestRepositories();
      await seed(repos);
      final program = await makeProgram(tester, repos, enabled: false);
      expect(program.eventRuleIds, isEmpty);
    });

    testWidgets("an unsaved program's autosaved draft keeps the template's "
        'rules, and restoring it in another New program brings them, not that '
        "program's template's", (tester) async {
      final repos = openTestRepositories();
      final (family, _) = await seed(repos);
      final plainRule = await _rule(repos, 'Plain rule');
      await saveProgramTemplate(
        repos.settings,
        ProgramTemplate(
          id: 'plain',
          name: 'Plain',
          eventRuleIds: [plainRule.id],
        ),
      );
      await _pump(
        tester,
        repos,
        const ProgramEditorScreen(
          templateChoice: ProgramTemplateChoice.template('family'),
        ),
        enabled: true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Left behind',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // A second New program, from the plain template, offers the draft.
      String? savedId;
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        repos,
        ProgramEditorScreen(
          key: UniqueKey(),
          onSaved: (id) => savedId = id,
          templateChoice: const ProgramTemplateChoice.template('plain'),
        ),
        enabled: true,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-draft-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-program')));
      await tester.pumpAndSettle();
      final program = (await repos.programs.getById(savedId!))!;
      expect(program.title, 'Left behind');
      expect(program.eventRuleIds, [family.id]);
    });
  });

  test('a program made with no template gets no rules', () async {
    final repos = openTestRepositories();
    await repos.settings.set(kEventRulesEnabledKey, true);
    await _rule(repos, 'Family friendly');
    expect(await newProgramEventRuleIds(repos, null), isEmpty);
  });
}
