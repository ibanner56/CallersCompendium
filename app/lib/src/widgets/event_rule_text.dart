import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/event_rule_check.dart';
import 'saved_search_actions.dart' show savedSearchMissingText;

/// An event rule as the sentence the app shows (#2340): "At most 1 dance
/// matching "Petronella" in the whole program". [searchName] is the name of
/// the saved search the rule uses, or null when it is gone.
String eventRuleSentence(
  AppLocalizations l10n,
  EventRule rule,
  String? searchName,
) {
  final quantifier = rule.quantifier;
  final scope = rule.scope;
  if (!rule.isReadable || quantifier == null || scope == null) {
    return l10n.eventRuleSentenceUnreadable;
  }
  final search = searchName ?? l10n.eventRuleSearchUnknown;
  final count = rule.count;
  return switch ((quantifier, scope)) {
    (EventRuleQuantifier.atMost, EventRuleScope.wholeProgram) =>
      l10n.eventRuleSentenceAtMostWhole(count, search),
    (EventRuleQuantifier.atMost, EventRuleScope.beforeFirstBreak) =>
      l10n.eventRuleSentenceAtMostBefore(count, search),
    (EventRuleQuantifier.atMost, EventRuleScope.afterFirstBreak) =>
      l10n.eventRuleSentenceAtMostAfter(count, search),
    (EventRuleQuantifier.atMost, EventRuleScope.neighbouring) =>
      l10n.eventRuleSentenceAtMostNeighbouring(count, search),
    (EventRuleQuantifier.atLeast, EventRuleScope.wholeProgram) =>
      l10n.eventRuleSentenceAtLeastWhole(count, search),
    (EventRuleQuantifier.atLeast, EventRuleScope.beforeFirstBreak) =>
      l10n.eventRuleSentenceAtLeastBefore(count, search),
    (EventRuleQuantifier.atLeast, EventRuleScope.afterFirstBreak) =>
      l10n.eventRuleSentenceAtLeastAfter(count, search),
    (EventRuleQuantifier.atLeast, EventRuleScope.neighbouring) =>
      l10n.eventRuleSentenceAtLeastNeighbouring(count, search),
    (EventRuleQuantifier.none, EventRuleScope.wholeProgram) =>
      l10n.eventRuleSentenceNoneWhole(search),
    (EventRuleQuantifier.none, EventRuleScope.beforeFirstBreak) =>
      l10n.eventRuleSentenceNoneBefore(search),
    (EventRuleQuantifier.none, EventRuleScope.afterFirstBreak) =>
      l10n.eventRuleSentenceNoneAfter(search),
    (EventRuleQuantifier.none, EventRuleScope.neighbouring) =>
      l10n.eventRuleSentenceNoneNeighbouring(search),
  };
}

/// What a rule is called in a list: its typed name, else its sentence.
String eventRuleTitle(
  AppLocalizations l10n,
  EventRule rule,
  String? searchName,
) => rule.name ?? eventRuleSentence(l10n, rule, searchName);

/// Why a rule is not checked, as lines to show: the reason, then each
/// missing thing its saved search names.
List<String> eventRuleAttentionLines(
  AppLocalizations l10n,
  EventRuleAttention attention,
) => switch (attention) {
  EventRuleUnreadable() => [l10n.eventRuleAttentionUnreadable],
  EventRuleSearchGone() => [l10n.eventRuleAttentionSearchGone],
  EventRuleSearchUnresolvable(:final missing) => [
    l10n.eventRuleAttentionUnresolvable,
    for (final m in missing) '• ${savedSearchMissingText(l10n, m)}',
  ],
};

/// The label of a quantifier, as the rule editor offers it.
String eventRuleQuantifierLabel(
  AppLocalizations l10n,
  EventRuleQuantifier quantifier,
) => switch (quantifier) {
  EventRuleQuantifier.atMost => l10n.eventRuleQuantifierAtMost,
  EventRuleQuantifier.atLeast => l10n.eventRuleQuantifierAtLeast,
  EventRuleQuantifier.none => l10n.eventRuleQuantifierNone,
};

/// The label of a scope, as the rule editor offers it.
String eventRuleScopeLabel(AppLocalizations l10n, EventRuleScope scope) =>
    switch (scope) {
      EventRuleScope.wholeProgram => l10n.eventRuleScopeWholeProgram,
      EventRuleScope.beforeFirstBreak => l10n.eventRuleScopeBeforeFirstBreak,
      EventRuleScope.afterFirstBreak => l10n.eventRuleScopeAfterFirstBreak,
      EventRuleScope.neighbouring => l10n.eventRuleScopeNeighbouring,
    };

/// The icon every event-rule warning carries, beside its text: never colour
/// alone.
const IconData eventRuleWarningIcon = Icons.rule;
