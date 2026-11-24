// Event rules in the program builder (#2340): off by default with nothing
// shown and nothing checked; on, the Rules control and picker with its pinned
// New rule… line, the Rules strip, slot markers that pair an icon with text and
// name the rules to a screen reader, rules that need attention, and warnings
// that never block saving.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/settings/event_rules_screen.dart';
import 'package:compendium_app/src/widgets/program_event_rules.dart';

import 'support/dropdown.dart';
import 'support/l10n_harness.dart';
import 'support/pump_until.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title, FormationShape shape) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: Formation(shape),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

SavedSearchSpec _spec(void Function(FacetSelections facets) set) {
  final facets = FacetSelections();
  set(facets);
  return SavedSearchSpec.fromPanelState(
    CollectionPanelState(facets: facets),
    today: DateTime.utc(2026, 1, 1),
  ).value!;
}

class _Seeded {
  _Seeded(this.repos, this.becket, this.oneBecket, this.noBecketFirstHalf);
  final CompendiumRepositories repos;
  final SavedSearch becket;
  final EventRule oneBecket;
  final EventRule noBecketFirstHalf;
}

/// A Becket before the break, then an improper dance with a Becket alternate:
/// "at most 1 Becket" holds as planned and breaks only if the alternate is
/// called; "no Becket before the first break" breaks as planned.
Future<_Seeded> _seed({
  List<String>? applied,
  CompendiumRepositories? into,
}) async {
  final repos = into ?? openTestRepositories();
  await repos.dances.create(
    _dance('d-a', 'Becket Reel', FormationShape.becketCcw),
  );
  await repos.dances.create(
    _dance('d-c', 'Chorus Jig', FormationShape.dupleImproper),
  );
  await repos.dances.create(
    _dance('d-b', "Hull's Victory", FormationShape.becketCcw),
  );
  final becket = await repos.savedSearches.create(
    name: 'Becket',
    spec: _spec((f) => f.formations.add(FormationShape.becketCcw)),
  );
  final oneBecket = await repos.eventRules.create(
    savedSearchId: becket.id,
    quantifier: EventRuleQuantifier.atMost,
    count: 1,
    scope: EventRuleScope.wholeProgram,
  );
  final noBecketFirstHalf = await repos.eventRules.create(
    savedSearchId: becket.id,
    quantifier: EventRuleQuantifier.none,
    scope: EventRuleScope.beforeFirstBreak,
    name: 'Easy start',
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Night',
      eventRuleIds: applied ?? [oneBecket.id, noBecketFirstHalf.id],
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'd-a'),
        ProgramSlot(id: 'brk', position: 1, text: Program.breakSlotText),
        ProgramSlot(id: 's2', position: 2, danceId: 'd-c'),
        ProgramSlot(id: 's2alt', position: 3, danceId: 'd-b', isAlt: true),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return _Seeded(repos, becket, oneBecket, noBecketFirstHalf);
}

/// Records each call of the real evaluator.
class _Spy {
  final calls = <List<String>>[];

  List<EventRuleBreach> call({
    required List<ProgramSlot> slots,
    required List<EventRule> rules,
    required Map<String, Set<String>> matchingDanceIds,
  }) {
    calls.add([for (final r in rules) r.id]);
    return evaluateEventRules(
      slots: slots,
      rules: rules,
      matchingDanceIds: matchingDanceIds,
    );
  }
}

Future<ValueNotifier<bool>> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required bool enabled,
  _Spy? spy,
  void Function(String id)? onSaved,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
      home: ProgramEditorScreen(
        programId: 'p1',
        onSaved: onSaved ?? (_) {},
        eventRuleEvaluator: (spy ?? _Spy()).call,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return on;
}

final _strip = find.byKey(const ValueKey('program-rules-strip'));

void main() {
  testWidgets('with Event rules off (the default) no Rules control, strip or '
      'marker appears, and the evaluator is never called', (tester) async {
    final seeded = await _seed();
    final spy = _Spy();
    final on = await _pump(tester, seeded.repos, enabled: false, spy: spy);
    // Give any stray check every chance to run before asserting none did.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(find.byKey(const ValueKey('program-rules')), findsNothing);
    expect(_strip, findsNothing);
    expect(find.byKey(const ValueKey('slot-s1-rule-marker')), findsNothing);
    expect(find.text('Breaks a rule'), findsNothing);
    expect(spy.calls, isEmpty);

    // The same program with the feature on is checked: the seam is live.
    on.value = true;
    await pumpUntilFound(tester, _strip);
    expect(spy.calls, isNotEmpty);

    // And turned off again, everything goes.
    on.value = false;
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
    expect(find.byKey(const ValueKey('program-rules')), findsNothing);
  });

  testWidgets('a broken rule shows in the Rules strip with its sentence and '
      'the dances that break it; an alternate is named only as a swap', (
    tester,
  ) async {
    final seeded = await _seed();
    await _pump(tester, seeded.repos, enabled: true);
    await pumpUntilFound(tester, _strip);

    expect(find.text('2 rules not met'), findsOneWidget);
    expect(find.text('Rules (2)'), findsOneWidget);
    await tester.tap(find.text('2 rules not met'));
    await tester.pumpAndSettle();

    // At most 1 Becket: met as planned, broken only by calling the alternate.
    final oneBecket = find.byKey(
      ValueKey('program-rule-broken-${seeded.oneBecket.id}'),
    );
    expect(
      find.descendant(
        of: oneBecket,
        matching: find.text(
          'At most 1 dance matching "Becket" in the whole program',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: oneBecket,
        matching: find.text("If you call Hull's Victory"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: oneBecket, matching: find.textContaining('Dances:')),
      findsNothing,
    );

    // The named rule: its name, its sentence, and the dance that breaks it.
    final easyStart = find.byKey(
      ValueKey('program-rule-broken-${seeded.noBecketFirstHalf.id}'),
    );
    for (final text in [
      'Easy start',
      'No dance matching "Becket" before the first break',
      '1 matching dance',
      'Dances: Becket Reel',
    ]) {
      expect(
        find.descendant(of: easyStart, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('slot markers pair an icon with text and name the rules to a '
      'screen reader; a slot that breaks nothing has none', (tester) async {
    final semantics = tester.ensureSemantics();
    final seeded = await _seed();
    await _pump(tester, seeded.repos, enabled: true);
    await pumpUntilFound(tester, _strip);

    final primary = find.byKey(const ValueKey('slot-s1-rule-marker'));
    expect(primary, findsOneWidget);
    expect(
      find.descendant(of: primary, matching: find.text('Breaks a rule')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primary, matching: find.byIcon(Icons.rule)),
      findsOneWidget,
    );
    expect(tester.getSemantics(primary).label, 'Breaks the rule: Easy start');

    final alternate = find.byKey(const ValueKey('slot-s2alt-rule-marker'));
    expect(
      find.descendant(
        of: alternate,
        matching: find.text('Breaks a rule if called'),
      ),
      findsOneWidget,
    );
    // Its own label: it breaks the rule only if called (#2340 review).
    expect(
      tester.getSemantics(alternate).label,
      'Breaks the rule if called: At most 1 dance matching "Becket" in the '
      'whole program',
    );
    expect(find.byKey(const ValueKey('slot-s2-rule-marker')), findsNothing);
    semantics.dispose();
  });

  testWidgets('the picker pins New rule… first; a rule made there is applied '
      'to the program, and unticking a rule removes it', (tester) async {
    final seeded = await _seed(applied: const []);
    await _pump(tester, seeded.repos, enabled: true);
    expect(_strip, findsNothing, reason: 'no rule is applied by itself');

    await tester.tap(find.byKey(const ValueKey('program-rules')));
    await tester.pumpAndSettle();
    final newRule = find.byKey(const ValueKey('program-rules-new'));
    final firstRule = find.byKey(
      ValueKey('program-rule-${seeded.oneBecket.id}'),
    );
    await pumpUntilFound(tester, firstRule);
    expect(
      tester.getTopLeft(newRule).dy,
      lessThan(tester.getTopLeft(firstRule).dy),
      reason: 'New rule… is pinned above the rules',
    );

    await tester.tap(newRule);
    await tester.pumpAndSettle();
    expect(find.byType(EventRuleEditorScreen), findsOneWidget);
    await pickDropdownEntry(
      tester,
      find.byKey(const ValueKey('event-rule-search')),
      'Becket',
    );
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('event-rule-scope-neighbouring')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No dance matching "Becket" in any two neighboring dances'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('event-rule-save')));
    await tester.pumpAndSettle();

    final made = (await seeded.repos.eventRules.listAll()).last;
    expect(made.quantifier, EventRuleQuantifier.none);
    expect(made.scope, EventRuleScope.neighbouring);
    expect((await seeded.repos.programs.getById('p1'))!.eventRuleIds, [
      made.id,
    ]);
    final tick = tester.widget<CheckboxListTile>(
      find.byKey(ValueKey('program-rule-${made.id}')),
    );
    expect(tick.value, isTrue);

    await tester.tap(firstRule);
    await tester.pumpAndSettle();
    expect((await seeded.repos.programs.getById('p1'))!.eventRuleIds, [
      made.id,
      seeded.oneBecket.id,
    ]);
    await tester.tap(find.byKey(ValueKey('program-rule-${made.id}')));
    await tester.pumpAndSettle();
    expect((await seeded.repos.programs.getById('p1'))!.eventRuleIds, [
      seeded.oneBecket.id,
    ]);
  });

  testWidgets('a rule whose saved search is gone or unresolvable needs '
      'attention, names what is missing, and is never evaluated', (
    tester,
  ) async {
    final seeded = await _seed();
    const level = 'lvl-hard';
    await seeded.repos.difficultyLevels.upsert(
      DifficultyLevel(id: level, label: 'Hard', position: 9),
    );
    final hard = await seeded.repos.savedSearches.create(
      name: 'Hard',
      spec: _spec((f) => f.levels.add(level)),
    );
    await seeded.repos.difficultyLevels.delete(level);
    final unresolvable = await seeded.repos.eventRules.create(
      savedSearchId: hard.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.wholeProgram,
    );
    const gone = EventRule(
      id: 'rule-gone',
      savedSearchId: 'search-gone',
      quantifierName: 'atMost',
      count: 1,
      scopeName: 'wholeProgram',
    );
    await seeded.repos.eventRules.writeFromSync(gone);
    await seeded.repos.programs.setEventRuleIds('p1', [
      unresolvable.id,
      gone.id,
    ]);
    final spy = _Spy();
    await _pump(tester, seeded.repos, enabled: true, spy: spy);
    await pumpUntilFound(tester, _strip);

    expect(find.text('2 rules need attention'), findsOneWidget);
    await tester.tap(find.text('2 rules need attention'));
    await tester.pumpAndSettle();
    final first = find.byKey(
      ValueKey('program-rule-attention-${unresolvable.id}'),
    );
    expect(
      find.descendant(
        of: first,
        matching: find.text('• The level Hard, which was deleted'),
      ),
      findsOneWidget,
    );
    final second = find.byKey(
      const ValueKey('program-rule-attention-rule-gone'),
    );
    expect(
      find.descendant(
        of: second,
        matching: find.text(
          "Its saved search was deleted or can't be read, so it is not "
          'checked.',
        ),
      ),
      findsOneWidget,
    );
    expect(spy.calls, isEmpty, reason: 'neither rule is checked at all');
  });

  testWidgets('a broken rule never blocks saving, and the save keeps the '
      'applied rules', (tester) async {
    final seeded = await _seed();
    final saved = <String>[];
    await _pump(tester, seeded.repos, enabled: true, onSaved: saved.add);
    await pumpUntilFound(tester, _strip);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Night'),
      'Saturday',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await tester.pumpAndSettle();
    await pumpUntil(
      tester,
      () => saved.isNotEmpty,
      description: 'the program to save',
    );
    final stored = (await seeded.repos.programs.getById('p1'))!;
    expect(stored.title, 'Saturday');
    expect(stored.eventRuleIds, [
      seeded.oneBecket.id,
      seeded.noBecketFirstHalf.id,
    ]);
  });

  testWidgets('editing the saved search a rule uses updates the strip, with '
      'no edit to the program', (tester) async {
    final seeded = await _seed();
    await _pump(tester, seeded.repos, enabled: true);
    await pumpUntilFound(tester, _strip);

    // Becket now means the improper dances: nothing before the break matches,
    // and only one dance in the program does.
    await seeded.repos.savedSearches.save(
      SavedSearch(
        id: seeded.becket.id,
        name: 'Becket',
        spec: _spec((f) => f.formations.add(FormationShape.dupleImproper)),
      ),
    );
    await pumpUntil(
      tester,
      () => _strip.evaluate().isEmpty,
      description: 'the strip to go once no rule is broken',
    );
    expect(find.byKey(const ValueKey('slot-s1-rule-marker')), findsNothing);
  });

  /// A controller over [seeded]'s program, counting each check it delivers
  /// (a new [ProgramEventRulesController.check], not every notification: the
  /// first rules list notifies too) and each search-context read.
  Future<_Harness> harness(WidgetTester tester, _Seeded seeded) async {
    final program = (await seeded.repos.programs.getById('p1'))!;
    final h = _Harness(
      tester,
      ProgramEventRulesController(repos: seeded.repos),
      program,
    );
    addTearDown(h.controller.dispose);
    return h;
  }

  testWidgets('the search context is read once and kept across program '
      'changes; a change to what it reads reads it again', (tester) async {
    final seeded = await _seed();
    final repos = seeded.repos;
    final h = await harness(tester, seeded);

    h.update(h.program.slots);
    await h.checked(1);
    expect(h.controller.check.broken, isNotEmpty);
    expect(h.reads, 1);

    // A slot edit re-checks without reading the context again.
    h.update(h.program.slots.take(2).toList());
    await h.checked(2);
    expect(h.reads, 1);

    // A new tag changes what a search can name: read again.
    final _ = await repos.tags.upsert(Tag(id: 't-new', name: 'Family'));
    await h.checked(3);
    expect(h.reads, 2);

    // A dance edit re-checks with the context kept.
    final dance = (await repos.dances.getById('d-c'))!;
    await repos.dances.update(dance.copyWith(title: 'Chorus Jig Too'));
    await h.checked(4);
    expect(h.reads, 2);

    // The host's own inputs to the context changed: read again.
    h.update(h.program.slots.take(2).toList(), key: 'another program id');
    await h.checked(5);
    expect(h.reads, 3);
  });

  testWidgets('a settings write that changes no saved search (a draft '
      'autosave, a window size) neither re-checks nor reads the context; a '
      'saved-search edit re-checks', (tester) async {
    final seeded = await _seed();
    final repos = seeded.repos;
    final h = await harness(tester, seeded);
    h.update(h.program.slots);
    await h.checked(1);
    expect(h.reads, 1);

    await repos.settings.set('program_draft:p1', {'title': 'Night, drafted'});
    await repos.settings.set('window_size', {'width': 900, 'height': 700});
    await h.settle();
    expect(h.checks, 1, reason: 'nothing a check reads changed');
    expect(h.reads, 1);

    // The saved search itself: checked again. It is read by the check, not
    // kept in the context, so the context stands.
    await repos.savedSearches.save(
      SavedSearch(
        id: seeded.becket.id,
        name: 'Becket',
        spec: _spec((f) => f.formations.add(FormationShape.dupleImproper)),
      ),
    );
    await h.checked(2);
    expect(h.controller.check.broken, isEmpty);
    expect(h.reads, 1);
  });

  testWidgets('rules applied while a save is in flight survive the save', (
    tester,
  ) async {
    final delayed = openTestRepositoriesWithDelayedPrograms();
    final seeded = await _seed(into: delayed.repos, applied: const []);
    await _pump(tester, delayed.repos, enabled: true);
    await tester.enterText(
      find.byKey(const ValueKey('program-title')),
      'Night renamed',
    );
    await tester.pump();

    // The save has read the program and is held just before its write; the
    // picker (or another device) applies a rule in that gap.
    delayed.programs.holdNextWrite();
    await tester.tap(find.byKey(const ValueKey('save-program')));
    await delayed.programs.writeStarted;
    await delayed.repos.programs.setEventRuleIds('p1', [seeded.oneBecket.id]);
    delayed.programs.releaseWrite();
    await tester.pumpAndSettle();

    final stored = (await delayed.repos.programs.getById('p1'))!;
    expect(stored.title, 'Night renamed');
    expect(stored.eventRuleIds, [seeded.oneBecket.id]);
    // The builder takes the stored list, so its next pick starts from it.
    expect(find.text('Rules (1)'), findsOneWidget);
  });

  testWidgets("the picker's write keeps what changed while it was in flight, "
      "and adopts the stored stamp", (tester) async {
    final delayed = openTestRepositoriesWithDelayedPrograms();
    final seeded = await _seed(into: delayed.repos, applied: const []);
    await delayed.repos.programs.archive('p1', at: DateTime.utc(2026, 2, 1));
    await _pump(tester, delayed.repos, enabled: true);
    expect(find.byTooltip('Unarchive'), findsOneWidget);

    // The picker's write is held; meanwhile the program is unarchived here.
    delayed.programs.holdNextWrite();
    await tester.tap(find.byKey(const ValueKey('program-rules')));
    await tester.pumpAndSettle();
    final rule = find.byKey(ValueKey('program-rule-${seeded.oneBecket.id}'));
    await pumpUntilFound(tester, rule);
    await tester.tap(rule);
    await delayed.programs.writeStarted;
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-program')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Archive'), findsOneWidget);

    delayed.programs.releaseWrite();
    await tester.pumpAndSettle();
    final stored = (await delayed.repos.programs.getById('p1'))!;
    expect(stored.eventRuleIds, [seeded.oneBecket.id]);
    expect(stored.isArchived, isFalse);
    // The builder's copy is not put back to the archived one it held before.
    expect(find.byTooltip('Archive'), findsOneWidget);
    expect(find.byTooltip('Unarchive'), findsNothing);
  });

  testWidgets('a rule another writer applies stays when the picker ticks '
      'another, and the builder shows it', (tester) async {
    final seeded = await _seed(applied: const []);
    final repos = seeded.repos;
    final third = await repos.eventRules.create(
      savedSearchId: seeded.becket.id,
      quantifier: EventRuleQuantifier.atLeast,
      count: 1,
      scope: EventRuleScope.wholeProgram,
      name: 'Some Becket',
    );
    await _pump(tester, repos, enabled: true);
    expect(find.text('Rules'), findsOneWidget);

    // Sync applies a rule while the builder is open: the builder takes it.
    await repos.programs.setEventRuleIds('p1', [seeded.oneBecket.id]);
    await pumpUntilFound(tester, find.text('Rules (1)'));

    // The picker opens, then another writer applies a second rule before the
    // caller ticks a third: all three stay.
    await tester.tap(find.byKey(const ValueKey('program-rules')));
    await tester.pumpAndSettle();
    final box = find.byKey(ValueKey('program-rule-${third.id}'));
    await pumpUntilFound(tester, box);
    await repos.programs.setEventRuleIds('p1', [
      seeded.oneBecket.id,
      seeded.noBecketFirstHalf.id,
    ]);
    await tester.pumpAndSettle();
    await tester.tap(box);
    await tester.pumpAndSettle();
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.eventRuleIds, [
      seeded.oneBecket.id,
      seeded.noBecketFirstHalf.id,
      third.id,
    ]);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey('program-rule-${seeded.noBecketFirstHalf.id}')),
          )
          .value,
      isTrue,
      reason: "the picker shows the other writer's rule",
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Rules (3)'), findsOneWidget);
  });

  testWidgets('the Rules button counts a rule not on this device yet, but '
      'not a deleted one kept for its Undo', (tester) async {
    final seeded = await _seed();
    // A rule another device applied that has not arrived here: applied all
    // the same.
    await seeded.repos.programs.setEventRuleIds('p1', [
      'r-not-here-yet',
      seeded.oneBecket.id,
      seeded.noBecketFirstHalf.id,
    ]);
    await seeded.repos.eventRules.delete(seeded.noBecketFirstHalf.id);
    await _pump(tester, seeded.repos, enabled: true);
    await pumpUntilFound(tester, find.text('Rules (2)'));
    expect(find.text('Rules (1)'), findsNothing);
    expect(find.text('Rules (3)'), findsNothing);
  });

  testWidgets('a program applies at most $maxProgramEventRules rules, '
      "counting one not on this device yet: a deleted rule's id makes room, "
      'and a rule past the most is never shown ticked', (tester) async {
    final seeded = await _seed(applied: const []);
    final repos = seeded.repos;
    // A rule another device applied that has not arrived here, the two
    // seeded rules and more up to two short of the most, applied, and one
    // deleted (kept for its Undo) to fill the list.
    const notHereYet = 'r-not-here-yet';
    final live = [seeded.oneBecket.id, seeded.noBecketFirstHalf.id];
    while (live.length < maxProgramEventRules - 2) {
      live.add(
        (await repos.eventRules.create(
          savedSearchId: seeded.becket.id,
          quantifier: EventRuleQuantifier.atMost,
          count: live.length + 1,
          scope: EventRuleScope.wholeProgram,
        )).id,
      );
    }
    final gone = await repos.eventRules.create(
      savedSearchId: seeded.becket.id,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.afterFirstBreak,
    );
    await repos.programs.setEventRuleIds('p1', [notHereYet, gone.id, ...live]);
    await repos.eventRules.delete(gone.id);
    Future<EventRule> another(int n) => repos.eventRules.create(
      savedSearchId: seeded.becket.id,
      quantifier: EventRuleQuantifier.atLeast,
      count: n,
      scope: EventRuleScope.wholeProgram,
      name: 'Extra $n',
    );
    final last = await another(1);
    final past = await another(2);
    await _pump(tester, repos, enabled: true);

    await tester.tap(find.byKey(const ValueKey('program-rules')));
    await tester.pumpAndSettle();
    Finder box(EventRule rule) =>
        find.byKey(ValueKey('program-rule-${rule.id}'));
    bool ticked(EventRule rule) =>
        tester.widget<CheckboxListTile>(box(rule)).value ?? false;
    await pumpUntilFound(tester, box(seeded.oneBecket));
    final sheet = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    // Brings [rule]'s box on screen and checks a tap at its centre lands on
    // it: a list builds rows past its edge, and a tap there would miss and
    // prove nothing.
    Future<void> reach(EventRule rule) async {
      await tester.scrollUntilVisible(box(rule), 200, scrollable: sheet);
      await tester.ensureVisible(box(rule));
      await tester.pumpAndSettle();
      expect(box(rule).hitTestable(), findsOneWidget, reason: 'on screen');
    }

    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    // The deleted rule's id goes to make room for the last one; the rule not
    // here yet stays.
    await reach(last);
    await tester.tap(box(last));
    await tester.pumpAndSettle();
    expect(ticked(last), isTrue);
    var stored = (await repos.programs.getById('p1'))!;
    expect(stored.eventRuleIds, [notHereYet, ...live, last.id]);

    // Now full: one more is refused, and not shown ticked.
    await reach(past);
    await tester.tap(box(past));
    await tester.pumpAndSettle();
    expect(ticked(past), isFalse);
    expect(
      find.text(
        'This program uses $maxProgramEventRules rules, the most it can. '
        'Untick one to add another.',
      ),
      findsOneWidget,
    );
    stored = (await repos.programs.getById('p1'))!;
    expect(stored.eventRuleIds, [notHereYet, ...live, last.id]);
  });
}

/// Drives a [ProgramEventRulesController] directly, counting the checks it
/// delivers and its search-context reads.
class _Harness {
  _Harness(this.tester, this.controller, this.program) {
    var last = controller.check;
    controller.addListener(() {
      if (identical(controller.check, last)) return;
      last = controller.check;
      checks++;
    });
  }

  final WidgetTester tester;
  final ProgramEventRulesController controller;
  final Program program;
  int checks = 0;
  int reads = 0;

  Future<SavedSearchContext> _read() async {
    reads++;
    return SavedSearchContext(
      today: DateTime.utc(2026, 1, 1),
      taxonomy: contraTaxonomy,
    );
  }

  void update(List<ProgramSlot> slots, {Object? key}) => controller.update(
    enabled: true,
    ruleIds: program.eventRuleIds,
    slots: slots,
    readContext: _read,
    contextKey: key,
  );

  /// Waits until exactly [n] checks have been delivered.
  Future<void> checked(int n) async {
    await pumpUntil(tester, () => checks >= n, description: 'check $n');
    expect(checks, n, reason: 'one check, not more');
  }

  /// Gives any pending write notification, frame and check every chance to
  /// run: frames and event-loop turns, not a wait for time to pass.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }
}
