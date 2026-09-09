/// The smallest timestamp increment that survives the database's unix-second
/// representation.
const Duration storedTimestampTick = Duration(seconds: 1);

/// Unix-seconds form of a stamp, matching drift's `DateTimeColumn` mapping.
int unixSeconds(DateTime at) => at.toUtc().millisecondsSinceEpoch ~/ 1000;

/// Returns the first unused timestamp at or after [now] after conversion to the
/// database's unix-seconds precision.
///
/// Performed stamps use this when a later conditional rollback must distinguish
/// a new action from a prior or intervening write. A sub-second clock value is
/// normalized before comparison so it cannot round back down to a tied value
/// when it is persisted. Unrelated future stamps do not move the result beyond
/// the intended action time.
DateTime nextStoredTimestamp({
  required DateTime now,
  Iterable<DateTime?> current = const [],
}) {
  var candidateSeconds = unixSeconds(now);
  final usedSeconds = <int>{};
  for (final value in current) {
    if (value == null) continue;
    usedSeconds.add(unixSeconds(value));
  }
  while (usedSeconds.contains(candidateSeconds)) {
    candidateSeconds++;
  }
  return DateTime.fromMillisecondsSinceEpoch(
    candidateSeconds * 1000,
    isUtc: true,
  );
}
