import '../../l10n/app_localizations.dart';
import 'update_controller.dart';

/// Localized presentation of an assisted-download failure.
///
/// [UpdateController] records a typed [UpdateDownloadFailure] instead of prose
/// because it has no locale; this turns it into the user-facing sentence at the
/// display boundary (the update banner and Settings ▸ Updates). Shaped like
/// `importErrorMessage` in `data/import_error_labels.dart`.
///
/// The strings are generic and user-safe: none carries a URL, a file path, or
/// raw lower-layer error text (CWE-209). Most tell the user to use "View
/// release", the manual-download button; each locale's sentence quotes that
/// locale's `updateBannerViewRelease`, which `update_failure_labels_test.dart`
/// enforces.
String updateDownloadFailureMessage(
  AppLocalizations l10n,
  UpdateDownloadFailure failure,
) {
  return switch (failure) {
    UpdateDownloadFailure.destinationUnavailable =>
      l10n.updateDownloadFailureDestination,
    UpdateDownloadFailure.incomplete => l10n.updateDownloadFailureIncomplete,
    UpdateDownloadFailure.refusedHost => l10n.updateDownloadFailureRefusedHost,
    UpdateDownloadFailure.unreachable => l10n.updateDownloadFailureUnreachable,
    UpdateDownloadFailure.checksumMismatch =>
      l10n.updateDownloadFailureChecksumMismatch,
    UpdateDownloadFailure.handoffFailed =>
      l10n.updateDownloadFailureHandoffFailed,
    UpdateDownloadFailure.installFailed =>
      l10n.updateDownloadFailureInstallFailed,
  };
}
