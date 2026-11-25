import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The rule picker's order and search (#2341), in pure Dart.
void main() {
  EventRule rule(String id, {int position = 0, String? nickname}) =>
      EventRule.of(
        id: id,
        savedSearchId: 's-$id',
        quantifier: EventRuleQuantifier.atMost,
        count: 1,
        scope: EventRuleScope.wholeProgram,
        nickname: nickname,
        position: position,
      );

  group('EventRuleOrder', () {
    test('reads its stored name, and anything else as My order', () {
      expect(EventRuleOrder.fromStored('mostUsed'), EventRuleOrder.mostUsed);
      expect(EventRuleOrder.fromStored('manual'), EventRuleOrder.manual);
      for (final other in [null, '', 'MostUsed', 'byName', 1, true]) {
        expect(
          EventRuleOrder.fromStored(other),
          EventRuleOrder.manual,
          reason: '$other',
        );
      }
    });
  });

  group('orderEventRules', () {
    final rules = [
      rule('c', position: 2, nickname: 'Zebra'),
      rule('a', position: 0, nickname: 'émile'),
      rule('b', position: 1, nickname: 'Apple'),
      rule('d', position: 1, nickname: 'apple'),
    ];
    String title(EventRule r) => r.nickname!;

    test('My order is the manager\'s: position, then id', () {
      expect(
        [
          for (final r in orderEventRules(
            rules,
            EventRuleOrder.manual,
            usage: const {'c': 9},
            title: title,
          ))
            r.id,
        ],
        ['a', 'b', 'd', 'c'],
        reason: 'usage never moves a rule in My order',
      );
    });

    test('Most used puts the most applied first, then ties by folded '
        'title, then as My order', () {
      expect(
        [
          for (final r in orderEventRules(
            rules,
            EventRuleOrder.mostUsed,
            usage: const {'c': 3, 'a': 1, 'b': 1, 'd': 1},
            title: title,
          ))
            r.id,
        ],
        // c is applied most. a, b and d tie: "Apple" and "apple" fold alike
        // and come before "émile" (folded "emile"); b before d by position
        // and id.
        ['c', 'b', 'd', 'a'],
      );
    });

    test('a rule no program applies counts 0', () {
      expect(
        [
          for (final r in orderEventRules(
            [rule('x', nickname: 'B'), rule('y', nickname: 'A')],
            EventRuleOrder.mostUsed,
            usage: const {'x': 1},
            title: title,
          ))
            r.id,
        ],
        ['x', 'y'],
      );
    });
  });

  group('eventRuleMatchesQuery', () {
    const sentence =
        'At most 1 dance matching "Petronella" in the whole program';

    test('matches the nickname and the sentence, folding case and accents', () {
      expect(
        eventRuleMatchesQuery('FAMILY', nickname: 'Family', sentence: sentence),
        isTrue,
      );
      expect(
        eventRuleMatchesQuery(
          'petronella',
          nickname: 'one per night',
          sentence: sentence,
        ),
        isTrue,
        reason: 'the sentence names the saved search',
      );
      expect(
        eventRuleMatchesQuery('ecole', nickname: 'École', sentence: sentence),
        isTrue,
      );
      expect(
        eventRuleMatchesQuery(
          'école',
          sentence: 'No dance matching "Ecole" before the first break',
        ),
        isTrue,
      );
    });

    test('every word must be found, in either', () {
      expect(
        eventRuleMatchesQuery(
          'family petronella',
          nickname: 'Family',
          sentence: sentence,
        ),
        isTrue,
      );
      expect(
        eventRuleMatchesQuery(
          'family becket',
          nickname: 'Family',
          sentence: sentence,
        ),
        isFalse,
      );
    });

    test('a blank query finds every rule', () {
      expect(eventRuleMatchesQuery('  ', sentence: sentence), isTrue);
    });
  });
}
