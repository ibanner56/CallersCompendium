import 'package:meta/meta.dart';

/// Shared caller-scope SQL semantics for calling-history queries.
///
/// A non-blank caller restricts history to matching host callers and programs
/// whose host caller is unset. A blank caller means all callers.
String? normalizeCallingHistoryCaller(String? callerFilter) {
  final trimmed = callerFilter?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Returns the caller predicate for [callerColumn], including unattributed
/// programs in a configured caller's scope.
///
/// [callerColumn] is an internal, trusted SQL column expression (for example
/// `programs.caller` or `p.caller`), never user input.
String callingHistoryCallerClause(
  String? caller, {
  required String callerColumn,
}) => caller == null
    ? ''
    : 'AND ($callerColumn IS NULL OR TRIM($callerColumn) = \'\' '
          'OR LOWER(TRIM($callerColumn)) = LOWER(TRIM(?))) ';

/// Returns the alternate rule for a calling-history query over the
/// `program_slots` alias [slotTable] (for example `program_slots` or `ps`).
///
/// A primary slot counts as soon as its program contains the dance (#583's
/// documented default). An alternate slot counts only once that slot is marked
/// performed, because listing a dance as a fallback is not calling it
/// (maintainer ruling, 2026-10-28). The Dart side of the same rule is
/// `ProgramSlot.countsTowardCallingHistory`; the two must agree.
///
/// [slotTable] is an internal, trusted SQL alias, never user input.
String callingHistoryAlternateClause({required String slotTable}) =>
    'AND (NOT $slotTable.is_alt OR $slotTable.performed_at IS NOT NULL) ';

/// The four performance-tracking toggles that decide which slots date a
/// recency window and which slots date the history order. They never change
/// what counts as called: the counts, the Called filter's yes/no, venue stats
/// and half stats are decided by the two global gates alone
/// (`require_performed_for_history`, `require_event_date_for_history`).
///
/// A slot a global gate already excludes is excluded everywhere, whatever
/// these say. Every SQL helper below has a Dart mirror on [DanceCallingRecord]
/// that takes the same flags; the two must agree.
@immutable
class CallingHistoryTracking {
  const CallingHistoryTracking({
    this.recencyRequireEventDate = true,
    this.recencyRequirePerformed = false,
    this.orderIgnoreUndated = false,
    this.orderIgnoreUnperformed = false,
  });

  /// The shipped defaults. Recency counts only dated programs; performed is
  /// not required (the app resolves it to the global "require performed"
  /// setting until the caller sets it); every slot orders.
  static const CallingHistoryTracking defaults = CallingHistoryTracking();

  /// Recency counts a slot only if its program has an event date.
  final bool recencyRequireEventDate;

  /// Recency counts a slot only if it is marked performed.
  final bool recencyRequirePerformed;

  /// The history order and Last called give a slot no date if its program has
  /// no event date.
  final bool orderIgnoreUndated;

  /// The history order and Last called give a slot no date if it is not marked
  /// performed.
  final bool orderIgnoreUnperformed;

  @override
  bool operator ==(Object other) =>
      other is CallingHistoryTracking &&
      other.recencyRequireEventDate == recencyRequireEventDate &&
      other.recencyRequirePerformed == recencyRequirePerformed &&
      other.orderIgnoreUndated == orderIgnoreUndated &&
      other.orderIgnoreUnperformed == orderIgnoreUnperformed;

  @override
  int get hashCode => Object.hash(
    recencyRequireEventDate,
    recencyRequirePerformed,
    orderIgnoreUndated,
    orderIgnoreUnperformed,
  );
}

/// `COALESCE(event_date, performed_at, updated_at)` gated by the two
/// eligibility flags: NULL for a slot that fails a switched-on condition.
String _gatedDateSql({
  required String slotTable,
  required String programTable,
  required bool needEventDate,
  required bool needPerformed,
}) {
  final coalesce =
      'COALESCE($programTable.event_date, $slotTable.performed_at, '
      '$programTable.updated_at)';
  final conditions = [
    if (needEventDate) '$programTable.event_date IS NOT NULL',
    if (needPerformed) '$slotTable.performed_at IS NOT NULL',
  ];
  return conditions.isEmpty
      ? coalesce
      : 'CASE WHEN ${conditions.join(' AND ')} THEN $coalesce END';
}

/// Returns the date the history order and the Last-called sort give one slot,
/// over the `program_slots` alias [slotTable] and the `programs` alias
/// [programTable], or NULL when the slot has no ordering date.
///
/// The program's event date when it has one, else when the slot was marked
/// performed, else the program's last-updated time (GIG-2, maintainer decision
/// 2026-10-29). With [ignoreUndated] a slot whose program has no event date has
/// no date; with [ignoreUnperformed] a slot not marked performed has none. The
/// list keeps such a slot, last; Last called ignores it. The Dart side of the
/// same rule is `DanceCallingRecord.orderingDate`; the two must agree. The
/// history order and the Last-called sort both use this expression, so they
/// cannot drift.
///
/// [slotTable] and [programTable] are internal, trusted SQL aliases, never
/// user input.
String callingHistoryDateSql({
  required String slotTable,
  required String programTable,
  bool ignoreUndated = false,
  bool ignoreUnperformed = false,
}) => _gatedDateSql(
  slotTable: slotTable,
  programTable: programTable,
  needEventDate: ignoreUndated,
  needPerformed: ignoreUnperformed,
);

/// Returns the date a recency window gives one slot, or NULL when the slot is
/// in no window.
///
/// A slot is eligible only if ([requireEventDate] is off or its program has an
/// event date) and ([requirePerformed] is off or the slot is marked performed);
/// both on means both hold. An eligible slot's date is the event date, else the
/// performed time, else the program's `updated_at`, which is reachable only
/// while [requireEventDate] is off: that is how an undated program shows up by
/// its last edit. An ineligible slot still counts as called and in
/// "called ×N"; it falls in no window (N1-3, maintainer decision 2026-10-30;
/// the toggles are the maintainer's 2026-11-05 answer). The Dart side of the
/// same rule is `DanceCallingRecord.recencyDate`; the two must agree.
///
/// [slotTable] and [programTable] are internal, trusted SQL aliases, never
/// user input.
String callingHistoryRecencyDateSql({
  required String slotTable,
  required String programTable,
  bool requireEventDate = true,
  bool requirePerformed = false,
}) => _gatedDateSql(
  slotTable: slotTable,
  programTable: programTable,
  needEventDate: requireEventDate,
  needPerformed: requirePerformed,
);

/// The name of the SQL function that folds a program's typed venue the way
/// [callingHistoryVenueText] does. `applyCompendiumSqliteSetup` registers it on
/// every connection; a connection opened without that setup fails a typed-venue
/// scope with "no such function".
const String callingHistoryVenueKeySqlFunction = 'cc_venue_key';

/// Folds a program's typed venue into the text half of its venue key: trimmed,
/// each whitespace run collapsed to one space, and lower-cased. Returns null
/// for a null or blank venue, which has no key.
///
/// The repeated-venues summary groups by this fold, and a typed-venue
/// `CalledFilter` scope matches by it through the SQL function
/// [callingHistoryVenueKeySqlFunction], which calls this same function. SQLite
/// cannot do the fold itself: it has no regular expressions to collapse a run,
/// and its `LOWER` folds ASCII only, so `LOWER(TRIM(venue))` would split
/// "Salle  Église" from the summary's key.
String? callingHistoryVenueText(String? venue) {
  final trimmed = venue?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

/// Returns the event-date rule for a calling-history query over the `programs`
/// alias [programTable] (for example `programs` or `p`), or the empty string
/// when [requireEventDate] is false.
///
/// Off by default, so a program counts whether or not it has an event date
/// (#583's documented default). When the caller turns on "Require an event
/// date", a program with no event date counts nowhere history is read: a
/// duplicated or received program arrives undated, and stays out of history
/// until the caller dates it (maintainer decision, 2026-10-28).
///
/// [programTable] is an internal, trusted SQL alias, never user input.
String callingHistoryEventDateClause({
  required bool requireEventDate,
  required String programTable,
}) => requireEventDate ? 'AND $programTable.event_date IS NOT NULL ' : '';
