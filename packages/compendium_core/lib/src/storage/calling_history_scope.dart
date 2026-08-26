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
