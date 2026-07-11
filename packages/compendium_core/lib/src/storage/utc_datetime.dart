/// The database always round-trips [DateTime]s as UTC: drift stores them as
/// unix-epoch seconds and, on read, reconstructs a local-flavored
/// [DateTime] for the same instant (see drift's `SqlTypes.mapToSqlVariable`).
/// Since `DateTime.==` considers the UTC flag (not just the instant), a
/// value read back from the database would otherwise never compare equal to
/// the UTC [DateTime] that was written. All repositories normalize with
/// [asUtc]/[asUtcOrNull] on every read, and expect (asserted, debug-only)
/// UTC inputs on every write.
DateTime asUtc(DateTime value) => value.toUtc();

DateTime? asUtcOrNull(DateTime? value) => value?.toUtc();

/// Debug-only guard: throws if [value] isn't UTC. Call at the top of any
/// repository write method that accepts caller-supplied timestamps, so a
/// caller passing local time fails fast instead of silently corrupting
/// equality checks after the next read.
void assertUtc(DateTime value, String name) {
  assert(value.isUtc, '$name must be a UTC DateTime, got $value');
}

void assertUtcOrNull(DateTime? value, String name) {
  if (value != null) assertUtc(value, name);
}
