import '../../l10n/app_localizations.dart';
import 'backup_io.dart';

/// The snackbar text for a backup export that failed with [error]: the size
/// limit ([BackupExportTooLargeException]), no room to replace an existing
/// backup in place ([BackupDiskFullException]), or the generic failure.
///
/// Shared by every flow that exports a backup, so each says the same thing
/// about the same failure. Never includes a path or the raw error text.
String backupExportFailureMessage(AppLocalizations l10n, Object error) =>
    switch (error) {
      BackupExportTooLargeException(:final sizeBytes, :final maxBytes) =>
        l10n.backupExportTooLarge(
          backupMegabytes(sizeBytes),
          backupMegabytes(maxBytes),
        ),
      BackupDiskFullException(:final requiredBytes, :final availableBytes) =>
        l10n.backupExportDiskFull(
          backupMegabytes(requiredBytes),
          backupMegabytes(availableBytes),
        ),
      _ => l10n.backupExportFailed,
    };
