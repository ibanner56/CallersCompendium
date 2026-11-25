import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Perform's swap sheet and the program's event rules (#2347): a swap
/// candidate is checked with [CandidateRuleCheck] at
/// [swapCandidatePosition], the program as a swap stores it — the candidate
/// in the swapped slot and the swapped-out dance kept as an alternate
/// ([Program.swapSlotDanceKeepingAlternate]).
///
/// Dance ids starting with `P` are petronellas: the rule's saved search
/// matches them.
void main() {
  ProgramSlot slot(String id, String danceId, {bool alt = false}) =>
      ProgramSlot(id: id, position: 0, danceId: danceId, isAlt: alt);

  EventRule rule(
    String id,
    EventRuleQuantifier quantifier,
    EventRuleScope scope,
    int count,
  ) => EventRule.of(
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
  final atLeastOne = rule(
    'at-least-1',
    EventRuleQuantifier.atLeast,
    EventRuleScope.wholeProgram,
    1,
  );
  final noNeighbours = rule(
    'neighbours',
    EventRuleQuantifier.atMost,
    EventRuleScope.neighbouring,
    1,
  );

  /// Tonight: a called opener, the current dance B with its alternate D,
  /// the program's one petronella P1, then C and F.
  List<ProgramSlot> tonight() => [
    slot('s0', 'A'),
    slot('s1', 'B'),
    slot('s1-alt', 'D', alt: true),
    slot('s2', 'P1'),
    slot('s3', 'C'),
    slot('s4', 'F'),
  ];

  CandidateRuleCheck checkSwap(
    List<ProgramSlot> slots,
    int index,
    List<EventRule> rules,
    Iterable<String> candidates, {
    SuggestionPosition Function(List<ProgramSlot> slots, int index)? at,
  }) {
    final position = (at ?? swapCandidatePosition)(slots, index);
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
      matchingDanceIds: {
        for (final r in rules)
          r.id: {
            for (final id in ids)
              if (id.startsWith('P')) id,
          },
      },
    );
  }

  group('the place a swap puts its candidate', () {
    test('a planned dance: the candidate in its slot, the swapped-out dance '
        'kept as an alternate right after it', () {
      final slots = tonight();
      final position = swapCandidatePosition(slots, 3);
      expect(position.slotsBefore, slots.sublist(0, 3));
      expect(position.isAlternate, isFalse);
      expect(position.replaced, slots[3]);
      expect(position.slotsAfter.first.id, swappedOutSlotId);
      expect(position.slotsAfter.first.danceId, 'P1');
      expect(position.slotsAfter.first.isAlt, isTrue);
      expect(position.slotsAfter.skip(1), slots.sublist(4));
    });

    test('an alternate is promoted to lead its group, its old primary and '
        'the swapped-out dance kept as alternates, as the swap stores it', () {
      final slots = tonight();
      final position = swapCandidatePosition(slots, 2);
      expect(position.slotsBefore, slots.sublist(0, 1));
      expect(position.isAlternate, isFalse, reason: 'promoted');
      expect(position.replaced, slots[1], reason: 'B is planned there now');
      expect(
        [for (final s in position.slotsAfter.take(2)) (s.danceId, s.isAlt)],
        [('D', true), ('B', true)],
      );
      expect(position.slotsAfter.skip(2), slots.sublist(3));
      // The same program the swap itself stores, with the candidate in place.
      final stored = Program.swapSlotDanceKeepingAlternate(
        slots,
        2,
        danceId: 'X',
        alternateId: swappedOutSlotId,
      );
      expect(
        [
          for (final s in [
            ...position.slotsBefore,
            null,
            ...position.slotsAfter,
          ])
            (s?.danceId ?? 'X', s?.isAlt ?? false),
        ],
        [for (final s in stored) (s.danceId, s.isAlt)],
      );
    });
  });

  group('at most 1 petronella, with one in the program', () {
    for (final (name, index) in [
      ('the current dance', 1),
      (
        'an upcoming '
            'dance',
        4,
      ),
    ]) {
      test('swapping $name, a petronella candidate is marked and listed '
          'after the unmarked ones', () {
        final check = checkSwap(tonight(), index, [atMostOne], ['P2', 'E']);
        expect(check.brokenBy('P2'), [atMostOne]);
        expect(check.brokenBy('E'), isEmpty);
        expect(
          orderMarkedLast(['P2', 'E'], (id) => check.brokenBy(id).isNotEmpty),
          ['E', 'P2'],
        );
      });
    }

    test('swapping the petronella itself, a petronella candidate is not '
        'marked: the dance swapped out is no longer planned', () {
      final check = checkSwap(tonight(), 3, [atMostOne], ['P2', 'E']);
      expect(check.brokenBy('P2'), isEmpty);
      expect(check.brokenBy('E'), isEmpty);
    });

    test('swapping an alternate for a petronella is marked: the swap makes '
        'it the planned dance', () {
      final check = checkSwap(tonight(), 2, [atMostOne], ['P2', 'E']);
      expect(check.brokenBy('P2'), [atMostOne]);
      expect(check.brokenBy('E'), isEmpty);
    });
  });

  test('at least 1 petronella: swapping out the only one is marked, '
      'although it stays an alternate, which is not planned', () {
    final check = checkSwap(tonight(), 3, [atLeastOne], ['P2', 'E']);
    expect(check.brokenBy('E'), [atLeastOne]);
    expect(check.brokenBy('P2'), isEmpty);
  });

  group('not two petronellas side by side: the dances on either side of '
      'the slot count', () {
    test('the slot before the petronella', () {
      final check = checkSwap(tonight(), 1, [noNeighbours], ['P2', 'E']);
      expect(check.brokenBy('P2'), [noNeighbours]);
      expect(check.brokenBy('E'), isEmpty);
    });

    test('the slot after it', () {
      final check = checkSwap(tonight(), 4, [noNeighbours], ['P2']);
      expect(check.brokenBy('P2'), [noNeighbours]);
    });

    test('a slot with a dance between it and the petronella', () {
      final check = checkSwap(tonight(), 5, [noNeighbours], ['P2']);
      expect(check.brokenBy('P2'), isEmpty);
    });

    test('the swapped-out dance, kept as an alternate, is no neighbour', () {
      // P0 ‹swapped› P1: with P0 swapped for E, P0 is only an alternate.
      final slots = [slot('s0', 'P0'), slot('s1', 'P1')];
      final check = checkSwap(slots, 0, [noNeighbours], ['E', 'P2']);
      expect(check.brokenBy('E'), isEmpty);
      expect(check.brokenBy('P2'), [noNeighbours]);
    });
  });

  test('with includeEnglish, an English dance the ranking lists unranked is '
      'marked and listed last; without it, it is left as ranked', () {
    const english = SuggestionReason(SuggestionReasonKind.englishNotCovered);
    final ranking = SuggestionRanking([
      const RankedSuggestion(
        danceId: 'P-eng',
        score: 0,
        ranked: false,
        reasons: [english],
      ),
      const RankedSuggestion(
        danceId: 'E-eng',
        score: 0,
        ranked: false,
        reasons: [english],
      ),
    ]);
    List<EventRule> wouldBreak(String id) =>
        id.startsWith('P') ? [atMostOne] : const [];

    final asRanked = markRuleBreakingSuggestions(ranking, wouldBreak);
    expect(asRanked.order.map((r) => r.danceId), ['P-eng', 'E-eng']);
    expect(asRanked.order.every((r) => r.wouldBreak.isEmpty), isTrue);

    final marked = markRuleBreakingSuggestions(
      ranking,
      wouldBreak,
      includeEnglish: true,
    );
    expect(marked.order.map((r) => r.danceId), ['E-eng', 'P-eng']);
    expect(marked.order.last.wouldBreak, [atMostOne]);
  });
}
