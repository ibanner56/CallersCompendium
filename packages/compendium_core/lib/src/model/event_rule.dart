import 'dart:convert';

import 'package:meta/meta.dart';

/// Most rules one program may apply. More than this is not a set of rules a
/// caller reads while building.
const int maxProgramEventRules = 64;

/// The stored form of `Program.eventRuleIds` (`programs.event_rule_ids`): a
/// JSON array of the rule ids, in order.
String encodeEventRuleIds(List<String> ids) => jsonEncode(ids);

/// The rule ids a stored `programs.event_rule_ids` value lists. Read
/// leniently: a value that is not a JSON array of strings reads as none, and
/// a repeated id once, so a hand-edited row never fails the program.
List<String> decodeEventRuleIds(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  Object? raw;
  try {
    raw = jsonDecode(stored);
  } on FormatException {
    return const [];
  }
  return normalizeEventRuleIds(raw is List ? raw : const []);
}

/// [ids] as a program keeps them: strings only, non-empty, each once, in
/// order, at most [maxProgramEventRules].
List<String> normalizeEventRuleIds(Iterable<Object?> ids) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final id in ids)
      if (id is String && id.isNotEmpty && seen.length < maxProgramEventRules)
        if (seen.add(id)) id,
  ]);
}

/// How many dances an [EventRule] allows (#2340).
///
/// Stored and sent as its [name] (`atMost`, `atLeast`, `none`), read
/// leniently ([eventRuleQuantifierFromName]) so a value a later build adds
/// makes the rule unreadable rather than failing the row.
enum EventRuleQuantifier {
  /// At most [EventRule.count] matching dances.
  atMost,

  /// At least [EventRule.count] matching dances.
  atLeast,

  /// No matching dance at all; [EventRule.count] is 0.
  none,
}

/// Where in a program an [EventRule] counts (#2340).
///
/// Stored and sent as its [name], read leniently ([eventRuleScopeFromName]).
enum EventRuleScope {
  /// Every primary dance of the program.
  wholeProgram,

  /// The dances before the first break: section 1 of
  /// `Program.sectionsForSlots`. A program with no break has no sections, so
  /// nothing is before (or after) a break, as the half summaries of calling
  /// history count it (`half_calling_stats.dart`).
  beforeFirstBreak,

  /// The dances after the first break: sections 2 and later together.
  afterFirstBreak,

  /// Each pair of neighbouring dances, counted pair by pair. Neighbours mean
  /// what the matrix's adjacent-dance alert means: a break separates two
  /// dances, a note or waltz between them does not
  /// (`programNeighbourIndices`).
  neighbouring,
}

/// The quantifier named [name], or null when this build does not know it.
EventRuleQuantifier? eventRuleQuantifierFromName(String name) {
  for (final q in EventRuleQuantifier.values) {
    if (q.name == name) return q;
  }
  return null;
}

/// The scope named [name], or null when this build does not know it.
EventRuleScope? eventRuleScopeFromName(String name) {
  for (final s in EventRuleScope.values) {
    if (s.name == name) return s;
  }
  return null;
}

/// The most an [EventRule.count] may be. A program longer than this is not
/// one a caller plans by count.
const int maxEventRuleCount = 99;

/// The most [EventRule.count] can usefully be for [quantifier] in [scope].
///
/// A neighbouring pair holds two dances, so "at most 2 or more" in it can
/// never break and "at least 3 or more" always does: there, at most is 1
/// (at most 0 is [EventRuleQuantifier.none]) and at least is 1 or 2. Any
/// other scope allows up to [maxEventRuleCount]. The rule editor keeps to
/// this; a stored rule outside it (another build's) is still read and
/// checked as it says.
int eventRuleCountLimit(EventRuleQuantifier quantifier, EventRuleScope scope) =>
    switch ((quantifier, scope)) {
      (EventRuleQuantifier.atMost, EventRuleScope.neighbouring) => 1,
      (EventRuleQuantifier.atLeast, EventRuleScope.neighbouring) => 2,
      _ => maxEventRuleCount,
    };

/// Longest typed name an [EventRule] may have, in UTF-16 code units.
const int maxEventRuleNameLength = 200;

/// An event rule (#2340): a sentence about a program, built from **which
/// dances** (a saved search, by id), **how many** ([quantifier] and [count])
/// and **where** ([scope]). "At most 1 dance matching *Petronella* in the
/// whole program."
///
/// A rule applies to a program only when the caller adds it there
/// (`Program.eventRuleIds`); none is ever added automatically.
///
/// [quantifierName] and [scopeName] are the stored text, known to this build
/// or not, so a rule a newer build wrote is carried and published again as it
/// came; [quantifier] and [scope] read them, and a rule either is null for is
/// shown as needing attention and never checked ([isReadable]).
@immutable
class EventRule {
  const EventRule({
    required this.id,
    required this.savedSearchId,
    required this.quantifierName,
    required this.count,
    required this.scopeName,
    this.name,
    this.position = 0,
  });

  /// A rule built from known values.
  EventRule.of({
    required String id,
    required String savedSearchId,
    required EventRuleQuantifier quantifier,
    int count = 0,
    required EventRuleScope scope,
    String? name,
    int position = 0,
  }) : this(
         id: id,
         savedSearchId: savedSearchId,
         quantifierName: quantifier.name,
         count: quantifier == EventRuleQuantifier.none ? 0 : count,
         scopeName: scope.name,
         name: name,
         position: position,
       );

  final String id;

  /// The saved search (#2325) that says which dances the rule means.
  final String savedSearchId;

  /// The stored quantifier ([EventRuleQuantifier.name]).
  final String quantifierName;

  /// How many dances the quantifier allows; 0 for [EventRuleQuantifier.none].
  final int count;

  /// The stored scope ([EventRuleScope.name]).
  final String scopeName;

  /// A name the caller typed for the rule, or null to show its sentence only.
  final String? name;

  /// Where the rule sits in the caller's list of rules.
  final int position;

  EventRuleQuantifier? get quantifier =>
      eventRuleQuantifierFromName(quantifierName);

  EventRuleScope? get scope => eventRuleScopeFromName(scopeName);

  /// Whether this build can check the rule: it knows its quantifier and scope,
  /// and the count is one the quantifier can use.
  bool get isReadable =>
      quantifier != null &&
      scope != null &&
      count >= 0 &&
      count <= maxEventRuleCount &&
      (quantifier != EventRuleQuantifier.none || count == 0);

  EventRule copyWith({
    String? savedSearchId,
    EventRuleQuantifier? quantifier,
    int? count,
    EventRuleScope? scope,
    String? name,
    bool clearName = false,
    int? position,
  }) {
    final q = quantifier?.name ?? quantifierName;
    return EventRule(
      id: id,
      savedSearchId: savedSearchId ?? this.savedSearchId,
      quantifierName: q,
      count: q == EventRuleQuantifier.none.name ? 0 : (count ?? this.count),
      scopeName: scope?.name ?? scopeName,
      name: clearName ? null : (name ?? this.name),
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EventRule &&
      other.id == id &&
      other.savedSearchId == savedSearchId &&
      other.quantifierName == quantifierName &&
      other.count == count &&
      other.scopeName == scopeName &&
      other.name == name &&
      other.position == position;

  @override
  int get hashCode => Object.hash(
    id,
    savedSearchId,
    quantifierName,
    count,
    scopeName,
    name,
    position,
  );

  @override
  String toString() =>
      'EventRule($id: $quantifierName $count of $savedSearchId '
      'in $scopeName)';
}
