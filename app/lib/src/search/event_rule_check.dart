import 'package:compendium_core/compendium_core.dart';

import '../widgets/saved_search_actions.dart'
    show SavedSearchMissing, describeSavedSearchMissing;

/// The core evaluator's shape ([evaluateEventRules]), as a seam: the builder
/// takes one so a test can watch whether it is called (#2340).
typedef EventRuleEvaluator =
    List<EventRuleBreach> Function({
      required List<ProgramSlot> slots,
      required List<EventRule> rules,
      required Map<String, Set<String>> matchingDanceIds,
    });

/// Why an applied rule is not checked: it needs attention instead.
sealed class EventRuleAttention {
  const EventRuleAttention();
}

/// A newer version of the app wrote the rule (a quantifier or scope this one
/// does not know).
final class EventRuleUnreadable extends EventRuleAttention {
  const EventRuleUnreadable();
}

/// Its saved search is gone, or cannot be read here.
final class EventRuleSearchGone extends EventRuleAttention {
  const EventRuleSearchGone();
}

/// Its saved search names things that are gone ([UnresolvableSavedSearch]),
/// each listed in [missing]. Checking it without them would change what the
/// rule means, so it is not checked.
final class EventRuleSearchUnresolvable extends EventRuleAttention {
  const EventRuleSearchUnresolvable(this.missing);
  final List<SavedSearchMissing> missing;
}

/// One rule applied to the program, and what became of checking it.
class EventRuleStatus {
  const EventRuleStatus({
    required this.rule,
    this.searchName,
    this.attention,
    this.breach,
  });

  final EventRule rule;

  /// The name of the saved search the rule uses, when it is here.
  final String? searchName;

  /// Why it was not checked, or null when it was.
  final EventRuleAttention? attention;

  /// How the program breaks it, or null when it does not (or was not
  /// checked).
  final EventRuleBreach? breach;
}

/// The result of checking a program's applied rules.
class EventRuleCheck {
  const EventRuleCheck(this.rules);

  static const empty = EventRuleCheck([]);

  /// Every applied rule still here, in the order the program applies them.
  final List<EventRuleStatus> rules;

  Iterable<EventRuleStatus> get broken => rules.where((r) => r.breach != null);

  Iterable<EventRuleStatus> get needingAttention =>
      rules.where((r) => r.attention != null);

  /// The rules each slot is flagged by, by slot id: the primaries that break
  /// a rule, and the alternates that would if called.
  Map<String, List<EventRuleStatus>> get bySlot {
    final out = <String, List<EventRuleStatus>>{};
    for (final status in broken) {
      final breach = status.breach!;
      for (final id in {...breach.slotIds, ...breach.alternateSlotIds}) {
        out.putIfAbsent(id, () => []).add(status);
      }
    }
    return out;
  }
}

/// Checks the rules [ruleIds] against [slots] (#2340).
///
/// For each rule: its saved search is resolved against [readContext]'s
/// context (read once, and only when some rule needs it); a rule whose search
/// is gone or does not resolve whole needs attention and is skipped. The
/// resolved filter runs once per rule, restricted to the program's dance ids
/// ([DanceRepository.matchingAmong], which keeps a dance in Recently deleted),
/// and [evaluate] counts in Dart. A rule id with no rule (deleted) is ignored.
Future<EventRuleCheck> checkEventRules({
  required CompendiumRepositories repos,
  required List<String> ruleIds,
  required List<ProgramSlot> slots,
  required Future<SavedSearchContext> Function() readContext,
  Dialect? dialect,
  SearchEnrichment? enrichment,
  EventRuleEvaluator evaluate = evaluateEventRules,
}) async {
  if (ruleIds.isEmpty) return EventRuleCheck.empty;
  final resolved = await _resolveEventRules(
    repos: repos,
    ruleIds: ruleIds,
    readContext: readContext,
  );
  if (resolved.rules.isEmpty) return EventRuleCheck.empty;
  final statuses = resolved.statuses;
  final danceIds = {for (final slot in slots) ?slot.danceId};
  final matching = await _matchSets(
    repos,
    resolved.checkable,
    danceIds,
    dialect: dialect,
    enrichment: enrichment,
  );
  if (resolved.checkable.isNotEmpty) {
    final breaches = evaluate(
      slots: slots,
      rules: [for (final (rule, _) in resolved.checkable) rule],
      matchingDanceIds: matching,
    );
    for (final breach in breaches) {
      final status = statuses[breach.rule.id]!;
      statuses[breach.rule.id] = EventRuleStatus(
        rule: status.rule,
        searchName: status.searchName,
        breach: breach,
      );
    }
  }
  return EventRuleCheck([
    for (final rule in resolved.rules) ?statuses[rule.id],
  ]);
}

/// Which applied rules each candidate dance would break in one place in the
/// program (#2345), with the names of the saved searches the rules use, for
/// their sentences.
class CandidateRuleMarks {
  const CandidateRuleMarks({this.check, this.searchNames = const {}});

  /// No rule checked: nothing is marked.
  static const empty = CandidateRuleMarks();

  /// The check, or null when no applied rule could be checked.
  final CandidateRuleCheck? check;

  /// The name of the saved search each rule uses, by rule id, when it is
  /// here.
  final Map<String, String?> searchNames;

  /// Whether any applied rule was checked.
  bool get checksAnything => check?.checksAnything ?? false;

  /// The rules [danceId] would break there.
  List<EventRule> brokenBy(String danceId) =>
      check?.brokenBy(danceId) ?? const [];
}

/// Checks [candidateIds] against the rules [ruleIds] for the place
/// [position] describes (#2345): which rules each candidate would break if
/// it went there, as the builder would mark its slot once it did
/// ([CandidateRuleCheck]).
///
/// Rules are read and resolved as [checkEventRules] does, and a rule that
/// needs attention is skipped. Each checkable rule's filter runs **once**,
/// over the program's dances and every candidate together
/// ([DanceRepository.matchingAmong]); nothing is searched per candidate.
/// [position] is the builder's add at the end, add before or after a slot,
/// or **Replace…** ([SuggestionPosition.replacing]), which Perform's swap
/// sheet uses for the slot being swapped.
Future<CandidateRuleMarks> checkCandidateEventRules({
  required CompendiumRepositories repos,
  required List<String> ruleIds,
  required SuggestionPosition position,
  required Iterable<String> candidateIds,
  required Future<SavedSearchContext> Function() readContext,
  Dialect? dialect,
  SearchEnrichment? enrichment,
}) async {
  if (ruleIds.isEmpty) return CandidateRuleMarks.empty;
  final resolved = await _resolveEventRules(
    repos: repos,
    ruleIds: ruleIds,
    readContext: readContext,
  );
  if (resolved.checkable.isEmpty) return CandidateRuleMarks.empty;
  final ids = {
    for (final slot in [...position.slotsBefore, ...position.slotsAfter])
      ?slot.danceId,
    ...candidateIds,
  };
  final matching = await _matchSets(
    repos,
    resolved.checkable,
    ids,
    dialect: dialect,
    enrichment: enrichment,
  );
  return CandidateRuleMarks(
    check: CandidateRuleCheck(
      position: position,
      rules: [for (final (rule, _) in resolved.checkable) rule],
      matchingDanceIds: matching,
    ),
    searchNames: {
      for (final (rule, _) in resolved.checkable)
        rule.id: resolved.statuses[rule.id]?.searchName,
    },
  );
}

/// The applied rules still here, in the order applied; what became of
/// resolving each ([statuses], by rule id, with no breach yet); and the
/// ones that can be checked, each with its filter.
typedef _ResolvedRules = ({
  List<EventRule> rules,
  Map<String, EventRuleStatus> statuses,
  List<(EventRule, DanceFilter)> checkable,
});

/// Reads the rules [ruleIds] and resolves each one's saved search against
/// [readContext]'s context, read once and only when some rule needs it.
Future<_ResolvedRules> _resolveEventRules({
  required CompendiumRepositories repos,
  required List<String> ruleIds,
  required Future<SavedSearchContext> Function() readContext,
}) async {
  final rules = await repos.eventRules.getMany(ruleIds);
  SavedSearchContext? ctx;
  final statuses = <String, EventRuleStatus>{};
  final checkable = <(EventRule, DanceFilter)>[];
  for (final rule in rules) {
    final search = await repos.savedSearches.get(rule.savedSearchId);
    if (!rule.isReadable) {
      statuses[rule.id] = EventRuleStatus(
        rule: rule,
        searchName: search?.name,
        attention: const EventRuleUnreadable(),
      );
      continue;
    }
    if (search == null) {
      statuses[rule.id] = EventRuleStatus(
        rule: rule,
        attention: const EventRuleSearchGone(),
      );
      continue;
    }
    ctx ??= await readContext();
    switch (resolveSavedSearch(search.spec, ctx)) {
      case UnresolvableSavedSearch(missing: final refs):
        statuses[rule.id] = EventRuleStatus(
          rule: rule,
          searchName: search.name,
          attention: EventRuleSearchUnresolvable(
            await describeSavedSearchMissing(repos, refs, ctx),
          ),
        );
      case ResolvedFilter(filter: final filter):
        statuses[rule.id] = EventRuleStatus(
          rule: rule,
          searchName: search.name,
        );
        checkable.add((rule, filter));
    }
  }
  return (rules: rules, statuses: statuses, checkable: checkable);
}

/// For each of [checkable], the dances among [danceIds] its filter matches:
/// one [DanceRepository.matchingAmong] per rule.
Future<Map<String, Set<String>>> _matchSets(
  CompendiumRepositories repos,
  List<(EventRule, DanceFilter)> checkable,
  Set<String> danceIds, {
  Dialect? dialect,
  SearchEnrichment? enrichment,
}) async => {
  for (final (rule, filter) in checkable)
    rule.id: danceIds.isEmpty
        ? const <String>{}
        : await repos.dances.matchingAmong(
            filter,
            danceIds,
            dialect: dialect,
            enrichment: enrichment,
          ),
};
