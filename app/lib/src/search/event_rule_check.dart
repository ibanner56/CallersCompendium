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
  final rules = await repos.eventRules.getMany(ruleIds);
  if (rules.isEmpty) return EventRuleCheck.empty;
  final danceIds = {for (final slot in slots) ?slot.danceId};
  SavedSearchContext? ctx;
  final statuses = <String, EventRuleStatus>{};
  final checkable = <EventRule>[];
  final matching = <String, Set<String>>{};
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
        checkable.add(rule);
        matching[rule.id] = danceIds.isEmpty
            ? const {}
            : await repos.dances.matchingAmong(
                filter,
                danceIds,
                dialect: dialect,
                enrichment: enrichment,
              );
    }
  }
  if (checkable.isNotEmpty) {
    final breaches = evaluate(
      slots: slots,
      rules: checkable,
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
  return EventRuleCheck([for (final rule in rules) ?statuses[rule.id]]);
}
