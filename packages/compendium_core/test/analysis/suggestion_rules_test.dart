import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Suggestions that would break the program's event rules (#2345):
/// [CandidateRuleCheck] says which applied rules a candidate would break in
/// the place being suggested for, and [markRuleBreakingSuggestions] marks
/// those candidates and lists them after every other, in [rankSuggestions]'
/// order otherwise.
///
/// Dance ids starting with `P` are petronellas: the rule's saved search
/// matches them.
void main() {
  final stamp = DateTime.utc(2026, 1, 1);
  final today = DateTime.utc(2026, 11, 23);

  Dance dance(String id, {DanceForm form = DanceForm.contra}) => Dance(
    id: id,
    title: id,
    form: form,
    formation: const Formation(FormationShape.dupleImproper),
    figures: [
      testFigure(move: 'swing', params: {'beats': 16}),
    ],
    createdAt: stamp,
    updatedAt: stamp,
  );

  ProgramSlot slot(String danceId, {bool alt = false}) =>
      ProgramSlot(id: 's-$danceId', position: 0, danceId: danceId, isAlt: alt);
  final breakSlot = ProgramSlot(
    id: 'brk',
    position: 0,
    text: Program.breakSlotText,
  );

  EventRule rule(
    String id,
    EventRuleQuantifier quantifier,
    EventRuleScope scope, [
    int count = 0,
  ]) => EventRule.of(
    id: id,
    savedSearchId: 'petronella',
    quantifier: quantifier,
    count: count,
    scope: scope,
  );

  final atMostOne = rule(
    'at-most-1',
    EventRuleQuantifier.atMost,
    EventRuleScope.wholeProgram,
    1,
  );
  final notNeighbours = rule(
    'neighbours',
    EventRuleQuantifier.atMost,
    EventRuleScope.neighbouring,
    1,
  );

  /// Every `P…` id among [ids]: what the rule's search returns for them.
  Set<String> petronellas(Iterable<String> ids) => {
    for (final id in ids)
      if (id.startsWith('P')) id,
  };

  CandidateRuleCheck checkAt(
    SuggestionPosition position,
    List<EventRule> rules,
    Iterable<String> candidates, {
    CandidateRuleEvaluator evaluate = evaluateEventRules,
  }) {
    final ids = {
      for (final s in [
        ...position.slotsBefore,
        ?position.replaced,
        ...position.slotsAfter,
      ])
        ?s.danceId,
      ...candidates,
    };
    return CandidateRuleCheck(
      position: position,
      rules: rules,
      matchingDanceIds: {for (final r in rules) r.id: petronellas(ids)},
      evaluate: evaluate,
    );
  }

  /// [rankSuggestions] with every factor off, so its order is the plain
  /// order (ties keep it), then English dances, then dances already in the
  /// program.
  SuggestionRanking rank(
    SuggestionPosition position,
    List<Dance> program,
    List<Dance> candidates,
  ) {
    var settings = SuggestionSettings.defaults;
    for (final f in SuggestionFactor.values) {
      settings = settings.withWeight(f, SuggestionWeight.off);
    }
    return rankSuggestions(
      SuggestionRequest(
        slotsBefore: position.slotsBefore,
        slotsAfter: position.slotsAfter,
        candidateIsAlternate: position.isAlternate,
        programDances: {
          for (final d in program) d.id: SuggestionCandidate.fromDance(d),
        },
        candidates: [
          for (final d in candidates) SuggestionCandidate.fromDance(d),
        ],
        settings: settings,
        today: today,
        taxonomy: shippedTaxonomies.anyForm,
      ),
    );
  }

  List<String> order(SuggestionRanking r) => [
    for (final s in r.order) s.danceId,
  ];

  group('at most 1 petronella, with one in the program', () {
    final program = [dance('P1'), dance('A')];
    final position = SuggestionPosition.atEnd([slot('P1'), slot('A')]);
    // The petronella is first in the plain order, and so first in the
    // ranking: listing it last is the check's doing.
    final candidates = [
      dance('P2'),
      dance('B'),
      dance('C'),
      dance('E', form: DanceForm.ecd),
      dance('A'),
    ];

    test('a petronella candidate is marked, names the rule, and is listed '
        'after every unmarked candidate', () {
      final ranking = rank(position, program, candidates);
      expect(order(ranking).first, 'P2', reason: 'the ranking alone');
      final check = checkAt(position, [atMostOne], order(ranking));
      final marked = markRuleBreakingSuggestions(ranking, check.brokenBy);
      // B and C ranked, E English, A already in the program, then P2.
      expect(order(marked), ['B', 'C', 'E', 'A', 'P2']);
      final p2 = marked.order.last;
      expect(p2.wouldBreak, [atMostOne]);
      for (final s in marked.order.take(4)) {
        expect(s.wouldBreak, isEmpty, reason: s.danceId);
      }
    });

    test('marking changes no score or reason', () {
      final ranking = rank(position, program, candidates);
      final check = checkAt(position, [atMostOne], order(ranking));
      final marked = markRuleBreakingSuggestions(ranking, check.brokenBy);
      final before = {for (final s in ranking.order) s.danceId: s};
      for (final s in marked.order) {
        expect(s.score, before[s.danceId]!.score);
        expect(s.ranked, before[s.danceId]!.ranked);
        expect(s.reasons, before[s.danceId]!.reasons);
      }
    });

    test('a second petronella already in the program is marked too', () {
      final check = checkAt(position, [atMostOne], ['P1']);
      expect(check.brokenBy('P1'), [atMostOne]);
    });
  });

  test('an English dance is left as the ranking lists it, unmarked; one '
      'already in the program is checked with the others there', () {
    final program = [dance('P1'), dance('PE1', form: DanceForm.ecd)];
    final position = SuggestionPosition.atEnd([slot('P1'), slot('PE1')]);
    final candidates = [
      dance('PE2', form: DanceForm.ecd),
      dance('B'),
      dance('PE1', form: DanceForm.ecd),
    ];
    final ranking = rank(position, program, candidates);
    expect(order(ranking), ['B', 'PE2', 'PE1']);
    final check = checkAt(position, [atMostOne], order(ranking));
    // The English petronella would break the rule, as the check says ...
    expect(check.brokenBy('PE2'), [atMostOne]);
    final marked = markRuleBreakingSuggestions(ranking, check.brokenBy);
    // ... but keeps its place among the English dances, unmarked (#2343's
    // handling). The one already in the program is marked and listed last.
    expect(order(marked), ['B', 'PE2', 'PE1']);
    expect(marked.order[1].wouldBreak, isEmpty);
    expect(marked.order[2].wouldBreak, [atMostOne]);
  });

  test('the result set is identical with and without rules applied', () {
    final program = [dance('P1'), dance('A')];
    final position = SuggestionPosition.atEnd([slot('P1'), slot('A')]);
    final candidates = [
      dance('P2'),
      dance('B'),
      dance('P3'),
      dance('E', form: DanceForm.ecd),
      dance('PE', form: DanceForm.ecd),
      dance('P1'),
      dance('A'),
    ];
    final ranking = rank(position, program, candidates);
    final without = markRuleBreakingSuggestions(
      ranking,
      checkAt(position, const [], order(ranking)).brokenBy,
    );
    final withRules = markRuleBreakingSuggestions(
      ranking,
      checkAt(position, [atMostOne, notNeighbours], order(ranking)).brokenBy,
    );
    expect(order(without), order(ranking));
    expect(order(withRules).toSet(), order(without).toSet());
    expect(order(withRules), hasLength(candidates.length));
    expect(order(withRules), isNot(order(without)));
  });

  group('a neighbouring-dances rule', () {
    List<String> marked(SuggestionPosition position, List<String> ids) {
      final check = checkAt(position, [notNeighbours], ids);
      return [
        for (final id in ids)
          if (check.brokenBy(id).isNotEmpty) id,
      ];
    }

    test('at the end, marks only against the last dance', () {
      expect(
        marked(SuggestionPosition.atEnd([slot('P1'), slot('A')]), ['P2', 'B']),
        isEmpty,
        reason: 'a petronella earlier in the program is not a neighbour',
      );
      expect(
        marked(SuggestionPosition.atEnd([slot('A'), slot('P1')]), ['P2', 'B']),
        ['P2'],
      );
    });

    test('a pair that already breaks the rule elsewhere marks no '
        'candidate', () {
      expect(
        marked(SuggestionPosition.atEnd([slot('P0'), slot('P1'), slot('A')]), [
          'P2',
          'B',
        ]),
        isEmpty,
      );
    });

    test('a break after the last dance means it is not a neighbour', () {
      expect(
        marked(SuggestionPosition.atEnd([slot('A'), slot('P1'), breakSlot]), [
          'P2',
        ]),
        isEmpty,
      );
    });

    test('an alternate of the last dance is not the last dance', () {
      expect(
        marked(SuggestionPosition.atEnd([slot('A'), slot('P1', alt: true)]), [
          'P2',
        ]),
        isEmpty,
      );
    });

    test('adding before or after a slot (#2344) checks both neighbours', () {
      final slots = [slot('P1'), slot('A'), slot('B'), slot('P3')];
      // Between A and B: neither is a petronella.
      expect(
        marked(SuggestionPosition.inserting(slots, 1, after: true), ['P2']),
        isEmpty,
      );
      // After P1: the previous dance.
      expect(
        marked(SuggestionPosition.inserting(slots, 0, after: true), ['P2']),
        ['P2'],
      );
      // Before P3: the next dance.
      expect(
        marked(SuggestionPosition.inserting(slots, 3, after: false), ['P2']),
        ['P2'],
      );
    });

    test('replacing a slot checks the dances either side of it', () {
      final slots = [slot('P1'), slot('A'), slot('B')];
      expect(marked(SuggestionPosition.replacing(slots, 1), ['P2', 'C']), [
        'P2',
      ]);
      expect(marked(SuggestionPosition.replacing(slots, 2), ['P2']), isEmpty);
    });
  });

  test('at least N over the whole program never marks a dance being '
      'added', () {
    final atLeastTwo = rule(
      'at-least-2',
      EventRuleQuantifier.atLeast,
      EventRuleScope.wholeProgram,
      2,
    );
    final check = checkAt(
      SuggestionPosition.atEnd([slot('A')]),
      [atLeastTwo],
      ['P2', 'B'],
    );
    expect(check.brokenBy('P2'), isEmpty);
    expect(check.brokenBy('B'), isEmpty);
  });

  group('at least N, replacing a dance', () {
    final atLeastOne = rule(
      'at-least-1',
      EventRuleQuantifier.atLeast,
      EventRuleScope.wholeProgram,
      1,
    );

    test('marks a dance that would take away the only match', () {
      // Replacing the only petronella: anything else breaks the rule.
      final check = checkAt(
        SuggestionPosition.replacing([slot('P1'), slot('A')], 0),
        [atLeastOne],
        ['B', 'P2'],
      );
      expect(check.brokenBy('B'), [atLeastOne]);
      expect(check.brokenBy('P2'), isEmpty);
    });

    test('marks nothing when another match stays', () {
      final check = checkAt(
        SuggestionPosition.replacing([slot('P1'), slot('A'), slot('P3')], 0),
        [atLeastOne],
        ['B'],
      );
      expect(check.brokenBy('B'), isEmpty);
    });

    test('marks nothing when the program already breaks it', () {
      final check = checkAt(
        SuggestionPosition.replacing([slot('A'), slot('C')], 0),
        [atLeastOne],
        ['B'],
      );
      expect(check.brokenBy('B'), isEmpty);
    });
  });

  test('a half scope counts the candidate in the half it lands in', () {
    final noneBefore = rule(
      'none-before',
      EventRuleQuantifier.none,
      EventRuleScope.beforeFirstBreak,
    );
    final slots = [slot('A'), breakSlot, slot('B')];
    expect(
      checkAt(
        SuggestionPosition.inserting(slots, 0, after: true),
        [noneBefore],
        ['P2'],
      ).brokenBy('P2'),
      [noneBefore],
    );
    expect(
      checkAt(
        SuggestionPosition.atEnd(slots),
        [noneBefore],
        ['P2'],
      ).brokenBy('P2'),
      isEmpty,
    );
  });

  test('a candidate for an alternate is marked when calling it would break '
      'a rule', () {
    final slots = [slot('P1'), slot('A'), slot('B', alt: true)];
    // Replacing B, the alternate of A: called instead of A, it would make two
    // petronellas.
    final check = checkAt(
      SuggestionPosition.replacing(slots, 2),
      [atMostOne],
      ['P2', 'C'],
    );
    expect(check.brokenBy('P2'), [atMostOne]);
    expect(check.brokenBy('C'), isEmpty);
  });

  test('a rule that cannot be read, or has no match set, is never '
      'reported', () {
    const unreadable = EventRule(
      id: 'newer',
      savedSearchId: 'petronella',
      quantifierName: 'someday',
      count: 0,
      scopeName: 'wholeProgram',
    );
    final position = SuggestionPosition.atEnd([slot('P1')]);
    final check = CandidateRuleCheck(
      position: position,
      rules: [unreadable, atMostOne],
      matchingDanceIds: {
        'newer': {'P1', 'P2'},
      },
    );
    expect(check.checksAnything, isFalse);
    expect(check.brokenBy('P2'), isEmpty);
  });

  test('each rule is evaluated once per combination of rules a candidate '
      'matches, never once per candidate', () {
    var evaluations = 0;
    List<EventRuleBreach> counting({
      required List<ProgramSlot> slots,
      required List<EventRule> rules,
      required Map<String, Set<String>> matchingDanceIds,
    }) {
      evaluations++;
      return evaluateEventRules(
        slots: slots,
        rules: rules,
        matchingDanceIds: matchingDanceIds,
      );
    }

    final candidates = [for (var i = 0; i < 500; i++) i.isEven ? 'P$i' : 'D$i'];
    final check = checkAt(
      SuggestionPosition.atEnd([slot('A'), slot('P1')]),
      [atMostOne, notNeighbours],
      candidates,
      evaluate: counting,
    );
    final marked = [
      for (final id in candidates)
        if (check.brokenBy(id).isNotEmpty) id,
    ];
    expect(marked, hasLength(250));
    expect(check.brokenBy(candidates.first), [atMostOne, notNeighbours]);
    // Both sets hold a petronella, neither holds the others: two
    // combinations, and at most once more for the program as it stands.
    expect(evaluations, lessThanOrEqualTo(3));
  });

  test('orderMarkedLast keeps each group in order and drops nothing', () {
    expect(orderMarkedLast([1, 2, 3, 4, 5, 6], (n) => n.isEven), [
      1,
      3,
      5,
      2,
      4,
      6,
    ]);
  });
}
