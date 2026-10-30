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

/// Returns the date a recency window gives one slot: [callingHistoryDateSql]
/// without its last fallback, the program's `updated_at`.
///
/// An edit is not a call. Under the full expression, fixing a typo in an old
/// undated program would date all its dances "this week", so a slot whose
/// program has no event date and which was never marked performed has no
/// recency date (NULL) and falls in no window. It still counts as called and
/// in "called ×N" (N1-3, maintainer decision 2026-10-30). The Dart side of the
/// same rule is `DanceCallingRecord.recencyDate`; the two must agree.
///
/// [slotTable] and [programTable] are internal, trusted SQL aliases, never
/// user input.
String callingHistoryRecencyDateSql({
  required String slotTable,
  required String programTable,
}) => 'COALESCE($programTable.event_date, $slotTable.performed_at)';

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
