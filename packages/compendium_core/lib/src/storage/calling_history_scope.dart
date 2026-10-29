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

/// Returns the date a calling-history query gives one slot, over the
/// `program_slots` alias [slotTable] and the `programs` alias [programTable].
///
/// The program's event date when it has one, else when the slot was marked
/// performed, else the program's last-updated time (GIG-2, maintainer decision
/// 2026-10-29). The Dart side of the same rule is
/// `DanceCallingRecord.effectiveDate`; the two must agree. The history order
/// and the Last-called sort both use this expression, so they cannot drift.
///
/// [slotTable] and [programTable] are internal, trusted SQL aliases, never
/// user input.
String callingHistoryDateSql({
  required String slotTable,
  required String programTable,
}) =>
    'COALESCE($programTable.event_date, $slotTable.performed_at, '
    '$programTable.updated_at)';

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
