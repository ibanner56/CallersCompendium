import '../../l10n/app_localizations.dart';
import 'archive_intake_service.dart';

/// Localized presentation of an [ArchiveIntakeRejectionReason].
///
/// [ArchiveIntakeService] never bakes English prose into its result; it resolves
/// a failure to a stable [ArchiveIntakeRejectionReason] discriminator. This
/// mapper — living beside the other data helpers like `import_error_labels.dart`
/// — turns that into a localized string at the presentation boundary.
///
/// Security: every returned string is generic, user-safe prose. None contains a
/// file path, raw bytes, or lower-layer/parser error text (CWE-209).
String archiveIntakeRejectionMessage(
  AppLocalizations l10n,
  ArchiveIntakeRejectionReason reason,
) => switch (reason) {
  ArchiveIntakeRejectionReason.tooLarge => l10n.archiveIntakeRejectedTooLarge,
  ArchiveIntakeRejectionReason.unreadable =>
    l10n.archiveIntakeRejectedUnreadable,
  ArchiveIntakeRejectionReason.empty => l10n.archiveIntakeRejectedEmpty,
  ArchiveIntakeRejectionReason.notArchive =>
    l10n.archiveIntakeRejectedNotArchive,
  ArchiveIntakeRejectionReason.newerVersion =>
    l10n.archiveIntakeRejectedNewerVersion,
  ArchiveIntakeRejectionReason.noContent => l10n.archiveIntakeRejectedNoContent,
};
