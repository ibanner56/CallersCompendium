import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The evaluator of event rules (#2340), without a database: each test names
/// a program as a list of slot specs and the dances the rule's saved search
/// matches.
///
/// Slot specs: `M…` is a dance the search matches, any other bare word a dance
/// it does not; `alt:X` an alternate holding dance X; `|` the break;
/// `note:…` a free-text slot; `purged:…` a purged dance's caption;
/// `slot:…` an unfilled placeholder (#2338) labelled `…`.
void main() {
  List<ProgramSlot> program(List<String> specs) => [
    for (var i = 0; i < specs.length; i++) _slot(i, specs[i]),
  ];

  /// The dances the rule's search matches: every `M…` id, as the query would
  /// return them (a dance in Recently deleted included).
  Set<String> matchingIn(List<String> specs) => {
    for (final s in specs)
      for (final word in [s.startsWith('alt:') ? s.substring(4) : s])
        if (word.startsWith('M')) word,
  };

  EventRule rule(
    EventRuleQuantifier quantifier,
    EventRuleScope scope, [
    int count = 0,
  ]) => EventRule.of(
    id: 'r',
    savedSearchId: 'search',
    quantifier: quantifier,
    count: count,
    scope: scope,
  );

  List<EventRuleBreach> check(
    EventRule r,
    List<String> specs, {
    Set<String>? matching,
  }) => evaluateEventRules(
    slots: program(specs),
    rules: [r],
    matchingDanceIds: {r.id: matching ?? matchingIn(specs)},
  );

  /// The one breach of [r] over [specs], or null when it holds.
  EventRuleBreach? breach(
    EventRule r,
    List<String> specs, {
    Set<String>? matching,
  }) {
    final found = check(r, specs, matching: matching);
    expect(found.length, lessThanOrEqualTo(1));
    return found.isEmpty ? null : found.single;
  }

  const atMost = EventRuleQuantifier.atMost;
  const atLeast = EventRuleQuantifier.atLeast;
  const none = EventRuleQuantifier.none;
  const whole = EventRuleScope.wholeProgram;
  const before = EventRuleScope.beforeFirstBreak;
  const after = EventRuleScope.afterFirstBreak;
  const neighbours = EventRuleScope.neighbouring;

  group('each quantifier over the whole program', () {
    test('at most N: met at N, broken above it, naming the dances', () {
      expect(breach(rule(atMost, whole, 1), ['M1', 'a', '|', 'b']), isNull);
      final b = breach(rule(atMost, whole, 1), ['M1', 'a', '|', 'M2']);
      expect(b, isNotNull);
      expect(b!.brokenAsPlanned, isTrue);
      expect(b.count, 2);
      expect(b.slotIds, ['s0', 's3']);
    });

    test('at least N: met at N, broken below it, naming no dance', () {
      expect(breach(rule(atLeast, whole, 2), ['M1', '|', 'M2']), isNull);
      final b = breach(rule(atLeast, whole, 2), ['M1', 'a', '|', 'b']);
      expect(b!.count, 1);
      expect(b.slotIds, isEmpty);
    });

    test('none: met with none, broken by one', () {
      expect(breach(rule(none, whole), ['a', '|', 'b']), isNull);
      expect(breach(rule(none, whole), ['a', '|', 'M1'])!.slotIds, ['s2']);
    });
  });

  group('each quantifier before the first break', () {
    // One matching dance before the break, two after it.
    const specs = ['M1', 'a', '|', 'M2', 'M3'];

    test('at most counts only section 1', () {
      expect(breach(rule(atMost, before, 1), specs), isNull);
      final b = breach(rule(atMost, before, 1), ['M1', 'M4', '|', 'M2']);
      expect(b!.slotIds, ['s0', 's1']);
    });

    test('at least counts only section 1', () {
      expect(breach(rule(atLeast, before, 1), specs), isNull);
      expect(breach(rule(atLeast, before, 2), specs)!.count, 1);
    });

    test('none counts only section 1', () {
      expect(breach(rule(none, before), ['a', '|', 'M2']), isNull);
      expect(breach(rule(none, before), specs)!.slotIds, ['s0']);
    });
  });

  group('each quantifier after the first break', () {
    // One matching dance before the break, two after it; a second break
    // starts section 3, still after the first break.
    const specs = ['M1', 'a', '|', 'M2', '|', 'M3'];

    test('at most counts sections 2 and later together', () {
      expect(breach(rule(atMost, after, 2), specs), isNull);
      expect(breach(rule(atMost, after, 1), specs)!.slotIds, ['s3', 's5']);
    });

    test('at least counts sections 2 and later together', () {
      expect(breach(rule(atLeast, after, 2), specs), isNull);
      expect(breach(rule(atLeast, after, 3), specs)!.count, 2);
    });

    test('none counts sections 2 and later together', () {
      expect(breach(rule(none, after), ['M1', '|', 'a']), isNull);
      expect(breach(rule(none, after), specs)!.slotIds, ['s3', 's5']);
    });
  });

  group('each quantifier over neighbouring dances', () {
    test('at most 1: two matching dances in a row break it, pair by pair', () {
      expect(breach(rule(atMost, neighbours, 1), ['M1', 'a', 'M2']), isNull);
      final b = breach(rule(atMost, neighbours, 1), ['M1', 'M2', 'a', 'M3']);
      expect(b!.count, 1);
      expect(b.slotIds, ['s0', 's1']);
    });

    test('at least 1: a pair with no matching dance breaks it', () {
      expect(breach(rule(atLeast, neighbours, 1), ['M1', 'a', 'M2']), isNull);
      final b = breach(rule(atLeast, neighbours, 1), ['M1', 'a', 'b', 'M2']);
      expect(b!.count, 1);
      expect(b.slotIds, ['s1', 's2']);
    });

    test('none: any matching dance next to another dance breaks it', () {
      expect(breach(rule(none, neighbours), ['a', 'b']), isNull);
      expect(breach(rule(none, neighbours), ['a', 'M1'])!.slotIds, ['s1']);
    });
  });

  group('a program with no break', () {
    const specs = ['M1', 'a', 'M2'];

    test('has nothing before or after a break', () {
      expect(breach(rule(none, before), specs), isNull);
      expect(breach(rule(none, after), specs), isNull);
      expect(breach(rule(atLeast, before, 1), specs)!.count, 0);
      expect(breach(rule(atLeast, after, 1), specs)!.count, 0);
    });

    test('still counts the whole program and its neighbours', () {
      expect(breach(rule(atMost, whole, 1), specs)!.count, 2);
      expect(breach(rule(atMost, neighbours, 1), ['M1', 'M2']), isNotNull);
    });
  });

  group('neighbouring dances', () {
    test('a break between two dances separates them (not a pair)', () {
      expect(breach(rule(atMost, neighbours, 1), ['M1', '|', 'M2']), isNull);
    });

    test('a note between two dances does not (still a pair)', () {
      final b = breach(rule(atMost, neighbours, 1), ['M1', 'note:waltz', 'M2']);
      expect(b!.slotIds, ['s0', 's2']);
    });

    test('an unfilled placeholder stands for a dance: it separates the '
        'dances either side of it, and matches nothing itself', () {
      expect(
        breach(rule(atMost, neighbours, 1), ['M1', 'slot:Becket', 'M2']),
        isNull,
      );
      expect(breach(rule(none, neighbours), ['a', 'slot:Becket', 'b']), isNull);
      // A pair with the placeholder is not judged until it is filled.
      expect(
        breach(rule(atLeast, neighbours, 1), ['M1', 'slot:Becket', 'M2']),
        isNull,
      );
      // The dances next to each other still pair up.
      final b = breach(rule(atMost, neighbours, 1), [
        'M1',
        'M2',
        'slot:Becket',
        'M3',
      ]);
      expect(b!.slotIds, ['s0', 's1']);
      expect(b.count, 1);
    });
  });

  group('alternates', () {
    test('an alternate is not counted as a primary', () {
      // As planned there is one matching dance; the alternate of `a` is not
      // called unless it is swapped in.
      final b = breach(rule(atMost, whole, 1), ['M1', 'a', 'alt:M2']);
      expect(b!.brokenAsPlanned, isFalse);
      expect(b.count, 1);
      expect(b.slotIds, isEmpty);
      expect(b.alternateSlotIds, ['s2']);
    });

    test('breaks a rule only when swapped in', () {
      // The alternate of M1 replaces it: still one matching dance.
      expect(breach(rule(atMost, whole, 1), ['M1', 'alt:M2', 'a']), isNull);
      // A non-matching alternate of a matching primary drops an at-least rule
      // below its count when swapped in.
      final b = breach(rule(atLeast, whole, 1), ['M1', 'alt:b', 'a']);
      expect(b!.brokenAsPlanned, isFalse);
      expect(b.alternateSlotIds, ['s1']);
    });

    test('is checked against the dances on either side of its primary', () {
      // `b`'s alternate M2 would sit next to M1.
      final b = breach(rule(atMost, neighbours, 1), ['M1', 'b', 'alt:M2']);
      expect(b!.brokenAsPlanned, isFalse);
      expect(b.alternateSlotIds, ['s2']);
      // Not across a break.
      expect(
        breach(rule(atMost, neighbours, 1), ['M1', '|', 'b', 'alt:M2']),
        isNull,
      );
    });

    test('is listed with a broken program only when it is at fault', () {
      final b = breach(rule(atMost, whole, 1), [
        'M1',
        'M2',
        'a',
        'alt:M3',
        'c',
        'alt:d',
      ]);
      expect(b!.brokenAsPlanned, isTrue);
      expect(b.slotIds, ['s0', 's1']);
      expect(b.alternateSlotIds, ['s3']);
    });
  });

  group('slots that hold no dance', () {
    test('a free-text slot never matches, whatever it says', () {
      expect(
        breach(rule(none, whole), ['a', 'note:M1'], matching: {'M1'}),
        isNull,
      );
    });

    test('a dance in Recently deleted still counts', () {
      // The query returns a trashed dance's id like any other: the slot
      // still holds it.
      final b = breach(rule(none, whole), ['a', 'Mtrashed']);
      expect(b!.slotIds, ['s1']);
    });

    test('a purged dance does not', () {
      expect(
        breach(rule(none, whole), ['a', 'purged:M1'], matching: {'M1'}),
        isNull,
      );
    });
  });

  group('rules that cannot be checked', () {
    test('a rule without matching dances is skipped', () {
      expect(
        evaluateEventRules(
          slots: program(['M1', 'M2']),
          rules: [rule(none, whole)],
          matchingDanceIds: const {},
        ),
        isEmpty,
      );
    });

    test('a rule this build cannot read is skipped', () {
      const unknown = EventRule(
        id: 'r',
        savedSearchId: 'search',
        quantifierName: 'exactly',
        count: 1,
        scopeName: 'wholeProgram',
      );
      expect(unknown.isReadable, isFalse);
      expect(
        evaluateEventRules(
          slots: program(['M1', 'M2']),
          rules: [unknown],
          matchingDanceIds: const {
            'r': {'M1', 'M2'},
          },
        ),
        isEmpty,
      );
    });
  });
}

ProgramSlot _slot(int i, String spec) {
  final id = 's$i';
  if (spec == '|') {
    return ProgramSlot(id: id, position: i, text: Program.breakSlotText);
  }
  if (spec.startsWith('note:')) {
    return ProgramSlot(id: id, position: i, text: spec.substring(5));
  }
  if (spec.startsWith('slot:')) {
    return ProgramSlot(
      id: id,
      position: i,
      text: spec.substring(5),
      placeholderSearchId: 'search-${spec.substring(5)}',
    );
  }
  if (spec.startsWith('purged:')) {
    return ProgramSlot(
      id: id,
      position: i,
      text: spec.substring(7),
      isPurgedDance: true,
    );
  }
  if (spec.startsWith('alt:')) {
    return ProgramSlot(
      id: id,
      position: i,
      danceId: spec.substring(4),
      isAlt: true,
    );
  }
  return ProgramSlot(id: id, position: i, danceId: spec);
}
