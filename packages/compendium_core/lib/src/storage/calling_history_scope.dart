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
