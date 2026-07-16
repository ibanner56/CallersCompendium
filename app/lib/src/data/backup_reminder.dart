/// App-only backup-reminder preference (ROADMAP G.5).
///
/// Back up / restore stores two small preferences via `SettingsRepository`:
/// a reminder *cadence* (how often the user wants to be nudged to back up) and
/// the timestamp of the last successful export. The ROADMAP frames the cadence
/// as a lightweight *preference* — we surface a "Last backup" date and a gentle
/// inline hint when overdue, not a nagging-notification system.
///
/// The key, enum, and resolvers below are Flutter-free pure functions so they
/// can be unit-tested directly, mirroring `soft_delete_retention.dart` and
/// `regional_formats.dart`.
library;

/// Key used to persist the backup-reminder cadence (ROADMAP G.5).
///
/// Stored as a stable string token: one of `off` (the default), `weekly`, or
/// `monthly`. Absent/unset or an unrecognized value ⇒ [BackupReminderCadence.off].
const String kBackupReminderCadenceKey = 'backup_reminder_cadence';

/// Key used to persist the timestamp of the last successful backup export.
///
/// Stored as an ISO-8601 UTC string. Absent/unset ⇒ never backed up. This value
/// is deliberately excluded from the backup document itself (it is metadata
/// about backups, not user content), so restoring an old file never rewrites a
/// misleading "last backup" time.
const String kLastBackupAtKey = 'last_backup_at';

/// How often the user wants to be reminded to back up.
enum BackupReminderCadence {
  /// No reminder — the default. The last-backup date is still shown, but no
  /// overdue hint is ever surfaced.
  off('off', null),

  /// Nudge weekly (overdue once more than 7 days have passed).
  weekly('weekly', Duration(days: 7)),

  /// Nudge monthly (overdue once more than 30 days have passed).
  monthly('monthly', Duration(days: 30));

  const BackupReminderCadence(this.token, this.interval);

  /// The stable token persisted via `SettingsRepository`.
  final String token;

  /// How long may elapse before a backup is considered overdue, or `null` when
  /// reminders are [off].
  final Duration? interval;
}

/// Resolves a persisted settings value into a [BackupReminderCadence].
///
/// A recognized token maps to its enum value; `null`, an unknown token, or any
/// non-string garbage falls back to the safe [BackupReminderCadence.off]
/// default so a corrupted value can never silently start nagging the user.
BackupReminderCadence backupReminderCadenceFromStored(Object? stored) {
  if (stored is String) {
    for (final c in BackupReminderCadence.values) {
      if (c.token == stored) return c;
    }
  }
  return BackupReminderCadence.off;
}

/// Parses a persisted last-backup timestamp into a UTC [DateTime], or `null`
/// when unset or unparseable (⇒ treated as "never backed up").
DateTime? lastBackupAtFromStored(Object? stored) {
  if (stored is String) {
    final parsed = DateTime.tryParse(stored);
    if (parsed != null) return parsed.toUtc();
  }
  return null;
}

/// Whether a backup is overdue for the chosen [cadence].
///
/// Rules:
/// - [BackupReminderCadence.off] ⇒ never overdue.
/// - reminders on but no backup ever taken ([lastBackupAt] `null`) ⇒ overdue.
/// - otherwise overdue once more than the cadence [interval] has elapsed since
///   [lastBackupAt], measured against [now].
bool isBackupOverdue({
  required BackupReminderCadence cadence,
  required DateTime? lastBackupAt,
  required DateTime now,
}) {
  final interval = cadence.interval;
  if (interval == null) return false;
  if (lastBackupAt == null) return true;
  return now.toUtc().difference(lastBackupAt.toUtc()) > interval;
}
