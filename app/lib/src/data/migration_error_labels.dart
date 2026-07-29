import '../../l10n/app_localizations.dart';
import 'migration_guard.dart';

/// Localized presentation of the startup migration-guard diagnostics
/// (`migration_guard.dart`): [DatabaseDowngradeError], [MigrationSnapshotAborted],
/// and the [SnapshotFailureCause] discriminator.
///
/// The guard never bakes English prose into these types; it exposes typed
/// discriminators (the exception type itself, plus [SnapshotFailure.cause]).
/// This mapper turns them into localized strings at the presentation boundary,
/// mirroring `import_error_labels.dart`.
///
/// Security: every returned string is generic, user-safe prose. None contains a
/// filesystem path or raw lower-layer error text — [SnapshotFailure.error] is
/// diagnostic-only and never surfaced here (CWE-209).

/// Terminal-screen message for a [DatabaseDowngradeError].
String databaseDowngradeMessage(AppLocalizations l10n) =>
    l10n.migrationDowngradeMessage;

/// A short, plain-language sentence naming the probable cause of a failed
/// pre-migration backup, or the empty string when the cause is [unknown].
String snapshotCauseSentence(
  AppLocalizations l10n,
  SnapshotFailureCause cause,
) => switch (cause) {
  SnapshotFailureCause.diskFull => l10n.migrationSnapshotCauseDiskFull,
  SnapshotFailureCause.unwritableBackupsDir =>
    l10n.migrationSnapshotCauseUnwritableBackupsDir,
  SnapshotFailureCause.unknown => '',
};

/// Terminal-screen message for a [MigrationSnapshotAborted], weaving in the
/// likely-cause sentence when one is known.
String migrationSnapshotAbortedMessage(
  AppLocalizations l10n,
  SnapshotFailure failure,
) {
  final sentence = snapshotCauseSentence(l10n, failure.cause);
  final cause = sentence.isEmpty ? '' : '$sentence ';
  return l10n.migrationSnapshotAbortedMessage(cause);
}
