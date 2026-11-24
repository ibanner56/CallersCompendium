import 'package:meta/meta.dart';

import '../model/event_rule.dart';
import '../model/program.dart';
import 'program_matrix.dart' show programNeighbourIndices;

/// One applied [EventRule] that a program breaks (#2340), as
/// [evaluateEventRules] finds it.
///
/// A rule counts primaries: [brokenAsPlanned] says whether the program as
/// planned breaks it, and [slotIds] are the primary slots that break it. An
/// alternate is checked as if it were called instead of its primary, and is
/// listed in [alternateSlotIds] only when that swap would break the rule.
@immutable
class EventRuleBreach {
  const EventRuleBreach({
    required this.rule,
    required this.brokenAsPlanned,
    required this.count,
    this.slotIds = const [],
    this.alternateSlotIds = const [],
  });

  final EventRule rule;

  /// Whether the program as planned (its primaries) breaks the rule. When
  /// false, only calling one of [alternateSlotIds] would.
  final bool brokenAsPlanned;

  /// How many primaries in the rule's scope match it, for a whole-program or
  /// half scope; for the neighbouring scope, how many neighbouring pairs
  /// break it.
  final int count;

  /// The primary slots that break the rule, in program order: the matching
  /// dances, for **at most** and **none**; the slots of each pair that breaks
  /// it, for the neighbouring scope. Empty for **at least** over the whole
  /// program or a half, where no one dance is at fault.
  final List<String> slotIds;

  /// The alternates that would break the rule if called instead of their
  /// primary, in program order.
  final List<String> alternateSlotIds;

  @override
  String toString() =>
      'EventRuleBreach(${rule.id}, asPlanned: $brokenAsPlanned, '
      'count: $count, slots: $slotIds, alternates: $alternateSlotIds)';
}

/// Checks each of [rules] against a program's [slots] (position-ordered),
/// given, for each rule id, the dance ids its saved search matches
/// ([matchingDanceIds]). Returns the rules the program breaks, in [rules]'
/// order. Pure: no database, no clock.
///
/// A rule missing from [matchingDanceIds], or one this build cannot read
/// ([EventRule.isReadable]), is skipped: the caller reports it as needing
/// attention. It is never checked with part of its criteria dropped.
///
/// - **Which slots count.** A rule counts primaries (every slot that is not
///   [ProgramSlot.isAlt]). Only a slot holding a dance can match: a free-text
///   slot never does, and nor does a purged dance's caption, which holds no
///   dance id. A dance in Recently deleted is still in the program, so it
///   matches when its id is in the set.
/// - **Where.** Sections come from [Program.sectionsForSlots]: before the
///   first break is section 1, after it sections 2 and later. A program with
///   no break has neither. Neighbours come from [programNeighbourIndices],
///   the matrix's rule, over the program's dance slots: a break separates two
///   dances, a note between them does not.
/// - **Alternates.** Each alternate is checked as if it were called instead
///   of its group's primary ([Program.alternateGroupsForSlots]); a leading
///   alternate with no primary is checked as if it were called where it
///   stands. It is listed when that program breaks the rule and either the
///   program as planned does not, or the alternate is itself among the slots
///   that break it.
List<EventRuleBreach> evaluateEventRules({
  required List<ProgramSlot> slots,
  required List<EventRule> rules,
  required Map<String, Set<String>> matchingDanceIds,
}) {
  final sections = Program.sectionsForSlots(slots);
  final groups = Program.alternateGroupsForSlots(slots);
  final planned = [
    for (var i = 0; i < slots.length; i++)
      if (!slots[i].isAlt) i,
  ];
  final breaches = <EventRuleBreach>[];
  for (final rule in rules) {
    final matching = matchingDanceIds[rule.id];
    if (matching == null || !rule.isReadable) continue;
    bool matches(int i) {
      final danceId = slots[i].danceId;
      return danceId != null && matching.contains(danceId);
    }

    final base = _check(rule, planned, slots, sections, matches);
    final alternates = <String>[];
    for (var a = 0; a < slots.length; a++) {
      if (!slots[a].isAlt) continue;
      final called = _calledInstead(planned, groups, slots, a);
      final swapped = _check(rule, called, slots, sections, matches);
      if (!swapped.broken) continue;
      if (!base.broken || swapped.involved.contains(a)) {
        alternates.add(slots[a].id);
      }
    }
    if (!base.broken && alternates.isEmpty) continue;
    breaches.add(
      EventRuleBreach(
        rule: rule,
        brokenAsPlanned: base.broken,
        count: base.count,
        slotIds: [for (final i in base.involved) slots[i].id],
        alternateSlotIds: alternates,
      ),
    );
  }
  return breaches;
}

/// [planned] with the alternate at [a] called instead of its group's primary,
/// or, for a leading alternate with no primary, called where it stands.
List<int> _calledInstead(
  List<int> planned,
  List<int> groups,
  List<ProgramSlot> slots,
  int a,
) {
  final primary = planned.indexWhere((i) => groups[i] == groups[a]);
  if (primary >= 0) return [...planned]..[primary] = a;
  final at = planned.indexWhere((i) => i > a);
  return [...planned]..insert(at < 0 ? planned.length : at, a);
}

typedef _Check = ({bool broken, int count, List<int> involved});

_Check _check(
  EventRule rule,
  List<int> called,
  List<ProgramSlot> slots,
  List<int?> sections,
  bool Function(int) matches,
) {
  final quantifier = rule.quantifier!;
  bool breaks(int n) => switch (quantifier) {
    EventRuleQuantifier.atMost => n > rule.count,
    EventRuleQuantifier.atLeast => n < rule.count,
    EventRuleQuantifier.none => n > 0,
  };
  final scope = rule.scope!;
  if (scope == EventRuleScope.neighbouring) {
    // The dance rows of the program being called, as the matrix's rows are:
    // free-text slots are left out, so a note between two dances does not
    // separate them, and each row is its own group (alternates were swapped
    // in above).
    final rows = [
      for (final i in called)
        if (slots[i].danceId != null) i,
    ];
    final rowSections = [for (final i in rows) sections[i]];
    final rowGroups = [for (var r = 0; r < rows.length; r++) r];
    final involved = <int>{};
    var brokenPairs = 0;
    for (var r = 0; r < rows.length; r++) {
      final neighbours = programNeighbourIndices(
        sections: rowSections,
        alternateGroups: rowGroups,
        index: r,
      );
      for (final n in neighbours) {
        if (n <= r) continue; // each pair once
        final pair = [rows[r], rows[n]];
        if (!breaks(pair.where(matches).length)) continue;
        brokenPairs++;
        involved.addAll(
          quantifier == EventRuleQuantifier.atLeast
              ? pair
              : pair.where(matches),
        );
      }
    }
    return (
      broken: brokenPairs > 0,
      count: brokenPairs,
      involved: involved.toList()..sort(),
    );
  }
  final inScope = [
    for (final i in called)
      if (switch (scope) {
        EventRuleScope.wholeProgram => true,
        EventRuleScope.beforeFirstBreak => sections[i] == 1,
        EventRuleScope.afterFirstBreak => (sections[i] ?? 0) >= 2,
        EventRuleScope.neighbouring => false,
      })
        i,
  ];
  final matched = inScope.where(matches).toList();
  final broken = breaks(matched.length);
  return (
    broken: broken,
    count: matched.length,
    involved: broken && quantifier != EventRuleQuantifier.atLeast
        ? matched
        : const [],
  );
}
