/// Suggestions that would break the program's event rules (#2345): which
/// applied rules a candidate dance would break if it took a given place in
/// the program, and a ranking with those candidates marked and listed last.
///
/// Pure and Flutter-free. It reuses the two evaluators as they are: the
/// place is a [SuggestionPosition], as [rankSuggestions] ranks for, and the
/// check is [evaluateEventRules] (#2340) on the program with the candidate
/// in that place. One position serves every host: the builder's end of the
/// program, an add before or after a slot, and **Replace…**
/// ([SuggestionPosition.replacing]); and Perform's swap sheet (#2347) the
/// place of the slot being swapped, with the swapped-out dance kept as an
/// alternate ([swapCandidatePosition]).
library;

import '../model/event_rule.dart';
import '../model/program.dart';
import 'event_rules.dart';
import 'suggestions.dart';

/// [evaluateEventRules]'s shape, so a test can count the evaluations.
typedef CandidateRuleEvaluator =
    List<EventRuleBreach> Function({
      required List<ProgramSlot> slots,
      required List<EventRule> rules,
      required Map<String, Set<String>> matchingDanceIds,
    });

/// Which of a program's applied [EventRule]s a dance would break if it took
/// the place [position] describes (#2345).
///
/// A dance **would break** a rule when, with the dance in that place, the
/// program breaks the rule and either
///
/// - the dance is one of the slots that break it, as [evaluateEventRules]
///   names them: the slot the builder's slot markers (#2340) would mark once
///   the dance is there; or
/// - the program as it stands now ([SuggestionPosition.slotsBefore], the
///   [SuggestionPosition.replaced] slot if any, then
///   [SuggestionPosition.slotsAfter]) meets the rule as planned, and with
///   the dance in that place it does not.
///
/// So:
///
/// - **At most** and **None** mark a dance the rule's search matches, when
///   the program with it holds too many in the rule's scope.
/// - **Neighbouring dances** mark a dance only when the pair it makes with a
///   neighbour breaks the rule; the neighbours are the matrix's, on both
///   sides of the place.
/// - **At least** over the whole program or a half never marks a dance being
///   added (adding one never lowers the count). It marks a dance replacing
///   one when the program meets the rule now and would not with that dance
///   in the slot: a replacement takes a dance away.
/// - A dance taking an alternate's place ([SuggestionPosition.isAlternate])
///   is checked as if called instead of its primary, as the builder checks
///   an alternate, and is marked when that would break a rule.
///
/// **No search per candidate.** The input is the evaluator's own: for each
/// rule id, the dance ids its saved search matches ([matchingDanceIds]),
/// worked out once per rule over the program's dances (the
/// [SuggestionPosition.replaced] one included) and the candidates.
/// What a dance would break depends only on which of those sets hold it, so
/// [brokenBy] evaluates the program once for each distinct combination it
/// meets (at most one per candidate, and at most 2^n for n rules) and answers
/// every other dance from that.
///
/// A rule missing from [matchingDanceIds], or one this build cannot read
/// ([EventRule.isReadable]), is never reported: it needs attention instead,
/// as in the builder.
class CandidateRuleCheck {
  CandidateRuleCheck({
    required this.position,
    required List<EventRule> rules,
    required Map<String, Set<String>> matchingDanceIds,
    this.evaluate = evaluateEventRules,
  }) : _rules = List.unmodifiable([
         for (final rule in rules)
           if (rule.isReadable && matchingDanceIds.containsKey(rule.id)) rule,
       ]),
       _slots = List.unmodifiable([
         ...position.slotsBefore,
         ProgramSlot(
           id: candidateSlotId,
           position: position.slotsBefore.length,
           danceId: _candidateDanceId,
           isAlt: position.isAlternate,
         ),
         ...position.slotsAfter,
       ]),
       _matching = matchingDanceIds;

  /// The program as it stands now: the place's slots, with the slot being
  /// replaced back in its place.
  List<ProgramSlot> get _currentSlots => [
    ...position.slotsBefore,
    ?position.replaced,
    ...position.slotsAfter,
  ];

  /// The id the candidate's slot has while it is checked. A real slot id is
  /// a UUID, so it never clashes.
  static const String candidateSlotId = '\u0000candidate-rule-slot';
  static const String _candidateDanceId = '\u0000candidate-rule-dance';

  /// The place checked: where the candidate would go.
  final SuggestionPosition position;

  /// The evaluator: [evaluateEventRules], or a test's counting wrapper.
  final CandidateRuleEvaluator evaluate;

  /// The rules that can be checked, in the order given.
  final List<EventRule> _rules;

  /// The program with the candidate's slot in the place checked.
  final List<ProgramSlot> _slots;
  final Map<String, Set<String>> _matching;

  /// Each rule's matches among the program's own dances, made once.
  late final Map<String, Set<String>> _programMatching = () {
    final programIds = {for (final slot in _currentSlots) ?slot.danceId};
    return {
      for (final rule in _rules)
        rule.id: {
          for (final id in programIds)
            if (_matching[rule.id]!.contains(id)) id,
        },
    };
  }();

  /// The answer for each combination of rules a dance matches, keyed by
  /// which of [_rules] match it.
  final _bySignature = <String, List<EventRule>>{};

  /// The ids of the rules the program as it stands now breaks as planned,
  /// worked out once.
  late final Set<String> _brokenNow = {
    for (final breach in evaluate(
      slots: _currentSlots,
      rules: _rules,
      matchingDanceIds: _programMatching,
    ))
      if (breach.brokenAsPlanned) breach.rule.id,
  };

  /// Whether any rule can be checked here. When false, [brokenBy] is always
  /// empty.
  bool get checksAnything => _rules.isNotEmpty;

  /// The rules [danceId] would break in [position]'s place, in the order
  /// they were given. Empty when it breaks none.
  List<EventRule> brokenBy(String danceId) {
    if (_rules.isEmpty) return const [];
    final signature = String.fromCharCodes([
      for (final rule in _rules)
        _matching[rule.id]!.contains(danceId) ? 0x31 : 0x30,
    ]);
    return _bySignature[signature] ??= _check(signature);
  }

  /// Evaluates the program with a candidate that matches exactly the rules
  /// [signature] marks.
  List<EventRule> _check(String signature) {
    final matching = <String, Set<String>>{
      for (var r = 0; r < _rules.length; r++)
        _rules[r].id: signature.codeUnitAt(r) == 0x31
            ? {..._programMatching[_rules[r].id]!, _candidateDanceId}
            : _programMatching[_rules[r].id]!,
    };
    final breaches = evaluate(
      slots: _slots,
      rules: _rules,
      matchingDanceIds: matching,
    );
    final broken = {
      for (final breach in breaches)
        if (breach.slotIds.contains(candidateSlotId) ||
            breach.alternateSlotIds.contains(candidateSlotId) ||
            (breach.brokenAsPlanned && !_brokenNow.contains(breach.rule.id)))
          breach.rule.id,
    };
    if (broken.isEmpty) return const [];
    return List.unmodifiable([
      for (final rule in _rules)
        if (broken.contains(rule.id)) rule,
    ]);
  }
}

/// The place a Perform swap (#2346) puts its replacement, for checking a
/// candidate against the program's event rules (#2347): the program as
/// [Program.swapSlotDanceKeepingAlternate] stores it once the dance of the
/// slot at [index] (in a position-ordered [slots]) is swapped, with the
/// candidate in the swapped slot.
///
/// So the dance being swapped out is **kept as an alternate** right after
/// the candidate, where the swap puts it, and counts as an alternate does
/// (not as a planned dance); an alternate being swapped is promoted to lead
/// its group and its group's old primary becomes an alternate, as the swap
/// does. [SuggestionPosition.replaced] is the dance planned in that place
/// now (the group's primary, for a promoted alternate), so
/// [CandidateRuleCheck] compares with the program as it stands.
///
/// When the candidate is one of the group's own alternates, the swap trades
/// the two dances' places instead of adding one; that differs only among
/// the group's alternates, none of which a rule counts as planned, so one
/// position serves every candidate. A slot with no dance cannot be swapped:
/// its place is [SuggestionPosition.replacing]'s.
///
/// The ranking is not given this position: it ranks for
/// [SuggestionPosition.replacing], with the swapped-out dance left out
/// (#2348).
SuggestionPosition swapCandidatePosition(List<ProgramSlot> slots, int index) {
  RangeError.checkValidIndex(index, slots, 'index');
  final slot = slots[index];
  if (slot.danceId == null) return SuggestionPosition.replacing(slots, index);
  final swapped = Program.swapSlotDanceKeepingAlternate(
    slots,
    index,
    danceId: _swapCandidateDanceId,
    alternateId: swappedOutSlotId,
  );
  final at = swapped.indexWhere((s) => s.id == slot.id);
  return SuggestionPosition(
    slotsBefore: List.unmodifiable(swapped.sublist(0, at)),
    slotsAfter: List.unmodifiable(swapped.sublist(at + 1)),
    isAlternate: swapped[at].isAlt,
    // Promoted, the candidate takes its group's primary's place: that is
    // the dance planned there now.
    replaced: at == index ? slot : slots[at],
  );
}

/// The id [swapCandidatePosition] gives the swapped-out dance's alternate
/// slot. A real slot id is a UUID, so it never clashes.
const String swappedOutSlotId = '\u0000swapped-out-slot';

/// The placeholder dance [swapCandidatePosition] swaps in before taking its
/// slot out: never a real dance id, so it never trades with an alternate.
const String _swapCandidateDanceId = '\u0000swap-candidate-dance';

/// [items] with every one [isMarked] says is marked moved after every one it
/// does not, each group in its own order. Nothing is added or dropped.
List<T> orderMarkedLast<T>(Iterable<T> items, bool Function(T item) isMarked) {
  final unmarked = <T>[];
  final marked = <T>[];
  for (final item in items) {
    (isMarked(item) ? marked : unmarked).add(item);
  }
  return [...unmarked, ...marked];
}

/// [ranking] with each dance [wouldBreak] names rules for marked
/// ([RankedSuggestion.wouldBreak]) and listed after every unmarked dance
/// (#2345). Each group keeps the ranking's order, so the unmarked dances are
/// still the ranked ones first, then the English ones, then those already in
/// the program, and so are the marked ones. Every dance comes back once:
/// nothing is hidden.
///
/// An English dance the ranking lists unranked
/// ([SuggestionReasonKind.englishNotCovered]) is left as [rankSuggestions]
/// lists it, never marked: the issue's decision is that English candidates
/// are handled as #2343 handles them. An English dance already in the
/// program is in that group with every other form, and is checked with it.
/// With [includeEnglish], as Perform's swap sheet asks (#2347: every swap
/// result that would break a rule is marked), English dances are checked
/// and marked too, and a marked one is listed after every unmarked dance.
///
/// [wouldBreak] is usually a [CandidateRuleCheck]'s [CandidateRuleCheck.brokenBy].
SuggestionRanking markRuleBreakingSuggestions(
  SuggestionRanking ranking,
  List<EventRule> Function(String danceId) wouldBreak, {
  bool includeEnglish = false,
}) {
  final marked = [
    for (final suggestion in ranking.order)
      if (!includeEnglish &&
          suggestion.reasons.any(
            (r) => r.kind == SuggestionReasonKind.englishNotCovered,
          ))
        suggestion
      else
        switch (wouldBreak(suggestion.danceId)) {
          final rules when rules.isEmpty && suggestion.wouldBreak.isEmpty =>
            suggestion,
          final rules => suggestion.withWouldBreak(rules),
        },
  ];
  return SuggestionRanking(
    orderMarkedLast(marked, (s) => s.wouldBreak.isNotEmpty),
  );
}
