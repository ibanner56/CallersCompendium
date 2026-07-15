/// App-only setting for the soft-delete purge retention window (ROADMAP G.4).
///
/// The startup purge sweep ([DanceRepository.purgeDeleted]) hard-deletes
/// soft-deleted dances once they are older than a retention window. This file
/// exposes that window as a user-configurable preference persisted via
/// `SettingsRepository`.
///
/// It lives here (rather than in `settings_screen.dart` alongside the theme /
/// dialect keys) so `main.dart` can read the key and resolve the window at
/// startup without importing the settings screen, and so the resolver can be
/// unit-tested without pulling in Flutter — mirroring `display_defaults.dart`.
library;

/// Key used to persist the soft-delete purge retention window (ROADMAP G.4).
///
/// Stored as a stable scalar: an `int` number of days. A value of
/// [kSoftDeleteRetentionNever] (`0`) is the sentinel for "never auto-purge".
/// Absent/unset or an unrecognized value ⇒ the historical default of 30 days.
const String kSoftDeleteRetentionKey = 'soft_delete_retention_days';

/// Sentinel stored value meaning "never auto-purge" — the startup sweep is
/// skipped entirely so soft-deleted dances are kept until purged manually.
const int kSoftDeleteRetentionNever = 0;

/// The historical (and default) retention window: 30 days.
const int kSoftDeleteRetentionDefaultDays = 30;

/// The day-count options offered in the settings UI (excluding the "never"
/// sentinel, which the UI presents separately). Kept here so the UI and the
/// resolver agree on the supported values.
const List<int> kSoftDeleteRetentionDayOptions = <int>[30, 90];

/// Resolves a persisted settings value into the retention [Duration] to hand to
/// [DanceRepository.purgeDeleted], or `null` when the user has chosen to never
/// auto-purge (in which case the caller should SKIP the purge entirely).
///
/// Rules:
/// - a supported day-count option ([kSoftDeleteRetentionDayOptions]) ⇒
///   `Duration(days: stored)`;
/// - the [kSoftDeleteRetentionNever] sentinel (`0`) ⇒ `null` (never);
/// - `null`, or any other value (an unsupported/out-of-range int, non-int, or
///   garbage) ⇒ the historical default of [kSoftDeleteRetentionDefaultDays]
///   (30 days).
///
/// Defensive by design: only the values the UI can produce are honored, so a
/// corrupted or out-of-range stored value can never silently shorten, widen, or
/// disable auto-purge — it falls back to the safe 30-day default.
Duration? softDeleteRetentionFromStored(Object? stored) {
  if (stored == kSoftDeleteRetentionNever) return null;
  if (stored is int && kSoftDeleteRetentionDayOptions.contains(stored)) {
    return Duration(days: stored);
  }
  return const Duration(days: kSoftDeleteRetentionDefaultDays);
}
