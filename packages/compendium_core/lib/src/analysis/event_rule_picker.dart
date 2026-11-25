import '../model/event_rule.dart';
import '../search/search_fold.dart';

/// How the program's rule picker lists the caller's rules (#2341): the
/// Experimental Event rules setting **Rule order**, stored under
/// `event_rule_order` as the value's [name].
enum EventRuleOrder {
  /// **My order**: the order in **Manage rules** ([EventRule.position]).
  manual,

  /// **Most used**: rules applied to the most live programs first, ties by
  /// title ([orderEventRules]).
  mostUsed;

  /// The order [stored] names; [manual], the default, for anything else: unset,
  /// the wrong type, or a value a later build added.
  static EventRuleOrder fromStored(Object? stored) {
    for (final order in values) {
      if (order.name == stored) return order;
    }
    return manual;
  }
}

/// [rules] in the picker's [order] (#2341).
///
/// - [EventRuleOrder.manual]: by [EventRule.position], then id, as **Manage
///   rules** lists them.
/// - [EventRuleOrder.mostUsed]: by how many programs apply each rule, most
///   first ([usage], by rule id; a rule it does not name counts 0), then by
///   [title] folded as the Collection's search folds it, then as the manual
///   order. [usage] counts live programs only
///   (`EventRuleRepository.usageCounts`); it is derived when the picker opens
///   and never stored.
List<EventRule> orderEventRules(
  Iterable<EventRule> rules,
  EventRuleOrder order, {
  Map<String, int> usage = const {},
  required String Function(EventRule rule) title,
}) {
  int manual(EventRule a, EventRule b) {
    final byPosition = a.position.compareTo(b.position);
    return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
  }

  final list = [...rules];
  switch (order) {
    case EventRuleOrder.manual:
      list.sort(manual);
    case EventRuleOrder.mostUsed:
      final titles = {for (final r in list) r.id: foldForSearch(title(r))};
      list.sort((a, b) {
        final byUse = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        if (byUse != 0) return byUse;
        final byTitle = titles[a.id]!.compareTo(titles[b.id]!);
        return byTitle != 0 ? byTitle : manual(a, b);
      });
  }
  return list;
}

/// Whether the picker's search [query] finds a rule (#2341): every word of
/// [query] appears in the rule's [nickname] or in its [sentence], case and
/// accents folded as the Collection's search folds them ([foldForSearch]),
/// so "petronella" finds a rule nicknamed "one per night" whose sentence
/// names the saved search *Petronella*. A blank [query] finds every rule.
bool eventRuleMatchesQuery(
  String query, {
  String? nickname,
  required String sentence,
}) {
  final words = foldForSearch(
    query,
  ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack =
      '${foldForSearch(nickname ?? '')}\n${foldForSearch(sentence)}';
  return words.every(haystack.contains);
}
