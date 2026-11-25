// The program's rule picker (#2341): a rule's nickname as its title with the
// sentence beneath it, the search (nickname and sentence words, case and
// accents folded) with the pinned New rule… line that offers the typed text
// as a nickname when nothing matches, and Rule order (My order, Most used).
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

SavedSearchSpec _spec(FormationShape shape) {
  final facets = FacetSelections()..formations.add(shape);
  return SavedSearchSpec.fromPanelState(
    CollectionPanelState(facets: facets),
    today: DateTime.utc(2026, 1, 1),
  ).value!;
}

Program _program(String id, {List<String> rules = const []}) => Program(
  id: id,
  title: 'Night $id',
  eventRuleIds: rules,
  slots: [ProgramSlot(id: '$id-s', position: 0, text: 'Waltz')],
  createdAt: _now,
  updatedAt: _now,
);

class _Seeded {
  _Seeded(this.repos, this.becket, this.petronella);
  final CompendiumRepositories repos;
  final SavedSearch becket;
  final SavedSearch petronella;

  Future<EventRule> rule(
    SavedSearch search, {
    EventRuleQuantifier quantifier = EventRuleQuantifier.atMost,
    int count = 1,
    EventRuleScope scope = EventRuleScope.wholeProgram,
    String? nickname,
  }) => repos.eventRules.create(
    savedSearchId: search.id,
    quantifier: quantifier,
    count: count,
    scope: scope,
    nickname: nickname,
  );
}

Future<_Seeded> _seed() async {
  final repos = openTestRepositories();
  final becket = await repos.savedSearches.create(
    name: 'Becket',
    spec: _spec(FormationShape.becketCcw),
  );
  final petronella = await repos.savedSearches.create(
    name: 'Petronella',
    spec: _spec(FormationShape.dupleImproper),
  );
  await repos.programs.create(_program('p1'));
  return _Seeded(repos, becket, petronella);
}

/// Opens program p1 in the builder with Event rules on, then its picker.
Future<void> _openPicker(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final on = ValueNotifier(true);
  addTearDown(on.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: EventRulesEnabledScope(notifier: on, child: child!),
      ),
      home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('program-rules')));
  await tester.pumpAndSettle();
}

Finder _row(EventRule rule) => find.byKey(ValueKey('program-rule-${rule.id}'));

/// The rule ids the picker lists, top to bottom.
List<String> _listed(WidgetTester tester) {
  final tiles = tester
      .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
      .toList();
  final ids = [
    for (final tile in tiles)
      (tile.key! as ValueKey<String>).value.substring('program-rule-'.length),
  ];
  final tops = {
    for (final id in ids)
      id: tester.getTopLeft(find.byKey(ValueKey('program-rule-$id'))).dy,
  };
  return ids..sort((a, b) => tops[a]!.compareTo(tops[b]!));
}

final _search = find.byKey(const ValueKey('program-rules-search'));
final _newRule = find.byKey(const ValueKey('program-rules-new'));

void main() {
  testWidgets('a nickname is the row\'s title with the sentence beneath it; '
      'a rule without one shows its sentence', (tester) async {
    final seeded = await _seed();
    final named = await seeded.rule(
      seeded.petronella,
      nickname: 'One per night',
    );
    final plain = await seeded.rule(seeded.becket);
    await _openPicker(tester, seeded.repos);
    await pumpUntilFound(tester, _row(named));

    final namedTile = tester.widget<CheckboxListTile>(_row(named));
    expect((namedTile.title! as Text).data, 'One per night');
    expect(
      (namedTile.subtitle! as Text).data,
      'At most 1 dance matching "Petronella" in the whole program',
    );
    final plainTile = tester.widget<CheckboxListTile>(_row(plain));
    expect(
      (plainTile.title! as Text).data,
      'At most 1 dance matching "Becket" in the whole program',
    );
    expect(plainTile.subtitle, isNull);
  });

  testWidgets('the search shows above $kEventRulePickerSearchThreshold rules, '
      'not at it', (tester) async {
    final seeded = await _seed();
    for (var i = 1; i <= kEventRulePickerSearchThreshold; i++) {
      await seeded.rule(seeded.becket, count: i);
    }
    await _openPicker(tester, seeded.repos);
    await pumpUntilFound(tester, find.byType(CheckboxListTile));
    expect(_search, findsNothing);
  });

  testWidgets('typing filters by nickname and sentence words, folding case '
      'and accents; New rule… stays pinned; with no match it offers the '
      'typed text as the new rule\'s nickname', (tester) async {
    final seeded = await _seed();
    final family = await seeded.rule(seeded.becket, nickname: 'Family');
    final petronella = await seeded.rule(
      seeded.petronella,
      nickname: 'One per night',
    );
    final ecole = await seeded.rule(
      seeded.becket,
      quantifier: EventRuleQuantifier.none,
      scope: EventRuleScope.neighbouring,
      nickname: 'École',
    );
    final others = [
      for (var i = 2; i <= 7; i++)
        await seeded.rule(
          seeded.becket,
          quantifier: EventRuleQuantifier.atLeast,
          count: i,
        ),
    ];
    await _openPicker(tester, seeded.repos);
    await pumpUntilFound(tester, _search);

    Future<void> type(String text) async {
      await tester.enterText(_search, text);
      await tester.pumpAndSettle();
    }

    void expectPinned() {
      expect(_newRule, findsOneWidget);
      for (final id in _listed(tester)) {
        expect(
          tester.getTopLeft(_newRule).dy,
          lessThan(
            tester.getTopLeft(find.byKey(ValueKey('program-rule-$id'))).dy,
          ),
          reason: 'New rule… stays pinned above the rules',
        );
      }
    }

    // By nickname, case folded.
    await type('FAMILY');
    expect(_listed(tester), [family.id]);
    expectPinned();
    // By a word of the sentence: the saved search's name.
    await type('petronella');
    expect(_listed(tester), [petronella.id]);
    expect(find.text('New rule…'), findsOneWidget);
    // Accents folded both ways.
    await type('ecole');
    expect(_listed(tester), [ecole.id]);
    // Every word, from the nickname or the sentence.
    await type('least 7');
    expect(_listed(tester), [others.last.id]);
    await type('family neighboring');
    expect(_listed(tester), isEmpty);

    // Nothing matches: the pinned line offers the typed text.
    await type('  no Becket late ');
    expect(_listed(tester), isEmpty);
    expect(
      find.byKey(const ValueKey('program-rules-no-matches')),
      findsOneWidget,
    );
    expect(find.text('New rule "no Becket late"…'), findsOneWidget);
    expectPinned();
    await tester.tap(_newRule);
    await tester.pumpAndSettle();
    expect(find.byType(EventRuleEditorScreen), findsOneWidget);
    final nickname = tester.widget<TextField>(
      find.byKey(const ValueKey('event-rule-nickname')),
    );
    expect(nickname.controller!.text, 'no Becket late');
    await pickDropdownEntry(
      tester,
      find.byKey(const ValueKey('event-rule-search')),
      'Becket',
    );
    await tester.tap(find.byKey(const ValueKey('event-rule-save')));
    await tester.pumpAndSettle();

    final made = (await seeded.repos.eventRules.listAll()).last;
    expect(made.nickname, 'no Becket late');
    expect((await seeded.repos.programs.getById('p1'))!.eventRuleIds, [
      made.id,
    ]);
    // The search is cleared so the new rule is in view, ticked.
    expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    await pumpUntilFound(tester, _row(made));
    expect(tester.widget<CheckboxListTile>(_row(made)).value, isTrue);
    expect(_listed(tester), hasLength(10));
  });

  testWidgets('My order follows Manage rules\' order; Most used puts the '
      'rules live programs apply most first, ties by title, and does not '
      'count programs in Recently deleted', (tester) async {
    final seeded = await _seed();
    final repos = seeded.repos;
    final a = await seeded.rule(seeded.becket, nickname: 'Alpha');
    final b = await seeded.rule(seeded.becket, nickname: 'Bravo');
    final c = await seeded.rule(seeded.becket, nickname: 'Charlie');
    final d = await seeded.rule(seeded.becket, nickname: 'Delta');
    await repos.eventRules.reorder([d.id, c.id, b.id, a.id]);
    // c: one live program and one archived one. b: one live. a: none live,
    // but three in Recently deleted, which a count of every program would
    // put first. d: none.
    await repos.programs.create(_program('live1', rules: [c.id, b.id]));
    await repos.programs.create(_program('archived', rules: [c.id]));
    await repos.programs.archive('archived', at: _now);
    for (final id in ['t1', 't2', 't3']) {
      await repos.programs.create(_program(id, rules: [a.id]));
      await repos.programs.softDelete(id, at: _now);
    }

    await _openPicker(tester, repos);
    await pumpUntilFound(tester, _row(a));
    expect(_listed(tester), [
      d.id,
      c.id,
      b.id,
      a.id,
    ], reason: 'My order, the default, is the manager\'s');

    await repos.settings.set(kEventRuleOrderKey, EventRuleOrder.mostUsed.name);
    // Open the builder afresh: the picker reads the order when it opens.
    await tester.pumpWidget(const SizedBox());
    await _openPicker(tester, repos);
    await pumpUntilFound(tester, _row(a));
    expect(_listed(tester), [
      c.id,
      b.id,
      a.id,
      d.id,
    ], reason: 'c (2) and b (1) first; a and d (0 live) by title');
  });

  // Laid out as the add-to-program sheet is (add-to-program-sheet.md §4.5):
  // with the keyboard up the sheet drops its title, so the pinned line, the
  // search field and a rule stay in view on a phone at any text size.
  for (final (name, scale) in [('', 1.0), (' at 200% text', 2.0)]) {
    testWidgets('at 360×640 with the keyboard up and a notch$name, New '
        'rule…, the search field and a rule are visible between the status '
        'bar and the keyboard', (tester) async {
      final seeded = await _seed();
      final rules = [
        for (var i = 1; i <= 12; i++)
          await seeded.rule(seeded.becket, count: i, nickname: 'Rule $i'),
      ];
      const keyboard = 300.0;
      const notch = 47.0;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      tester.view.padding = const FakeViewPadding(top: notch);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
        tester.view.resetPadding();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepositoriesScope(repositories: seeded.repos, child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open'),
                  onPressed: () => showProgramRulesPicker(
                    context,
                    applied: const [],
                    onChange: (_) async => null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await pumpUntilFound(tester, _row(rules.first));

      const visibleBottom = 640 - keyboard;
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(
        tester.getRect(find.byType(BottomSheet)).top,
        greaterThanOrEqualTo(notch),
      );
      for (final finder in [_newRule, _search]) {
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(notch), reason: '$finder');
        expect(
          rect.bottom,
          lessThanOrEqualTo(visibleBottom),
          reason: '$finder',
        );
      }
      expect(
        tester.getRect(_newRule).top,
        lessThan(tester.getRect(_search).top),
        reason:
            'New rule… is pinned above the search, as on the '
            'add-to-program sheet',
      );
      expect(find.text('Rules for this program'), findsNothing);
      final row = tester.getRect(_row(rules.first));
      expect(row.top, greaterThanOrEqualTo(notch));
      expect(row.top + 48, lessThanOrEqualTo(visibleBottom));
    });
  }

  testWidgets('with the keyboard down the picker shows its title', (
    tester,
  ) async {
    final seeded = await _seed();
    await seeded.rule(seeded.becket);
    await _openPicker(tester, seeded.repos);
    expect(find.text('Rules for this program'), findsOneWidget);
  });
}
