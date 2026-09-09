/// The smallest timestamp increment that survives the database's unix-second
/// representation.
const Duration storedTimestampTick = Duration(seconds: 1);

/// Unix-seconds form of a stamp, matching drift's `DateTimeColumn` mapping.
int unixSeconds(DateTime at) => at.toUtc().millisecondsSinceEpoch ~/ 1000;

/// Returns a timestamp that is strictly later than every [current] stamp after
/// conversion to the database's unix-seconds precision.
///
/// Performed stamps use this when a later conditional rollback must distinguish
/// a new action from a prior or intervening write. A sub-second clock value is
/// normalized before comparison so it cannot round back down to a tied value
/// when it is persisted.
DateTime nextStoredTimestamp({
  required DateTime now,
  Iterable<DateTime?> current = const [],
}) {
  var candidate = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds(now) * 1000,
    isUtc: true,
  );
  for (final value in current) {
    if (value == null) continue;
    final stored = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds(value) * 1000,
      isUtc: true,
    );
    if (!candidate.isAfter(stored)) {
      candidate = stored.add(storedTimestampTick);
    }
  }
  return candidate;
}
