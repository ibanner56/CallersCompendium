import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_metadata.dart';
import '../utils/launch_external_url.dart';
import 'artifact_handoff.dart';
import 'update_controller.dart';
import 'update_scope.dart';
import 'update_service.dart';

/// App-wide update banner (ADR-002 §4/§5, "Stage 1.5"). Hosted once at the app
/// shell (above the shell content) so it can appear on any tab, it is
/// **dismissible and non-modal** — never a modal interrupt during a gig.
///
/// Renders nothing unless the [UpdateController] has a newer version to show
/// (after the dismissed-version gate). On **desktop** with a downloadable
/// artifact it offers an assisted "Download & install" flow (download → sha256
/// verify → OS-handoff) with progress, cancel, and a clear, non-silent error;
/// on **mobile** it keeps only the "View release" link. "View release" (via the
/// existing [launchExternalUrl] seam) is always available, and "Dismiss" records
/// the version so it is not shown again until a strictly-newer one appears.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UpdateScope.of(context);
    final update = controller.bannerUpdate;
    if (update == null) return const SizedBox.shrink();

    return MaterialBanner(
      key: const ValueKey('update-banner'),
      leading: const Icon(Icons.system_update_alt),
      content: _content(context, controller, update),
      actions: _actions(context, controller, update),
    );
  }

  Widget _content(
    BuildContext context,
    UpdateController controller,
    UpdateAvailable update,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final version = update.version.toString();
    switch (controller.downloadStatus) {
      case AssistedDownloadStatus.downloading:
        final fraction = controller.downloadProgress?.fraction;
        final pct = fraction == null ? null : (fraction * 100).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pct == null
                  ? l10n.updateBannerDownloading(kAppName, version)
                  : l10n.updateBannerDownloadingPct(kAppName, version, pct),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const ValueKey('update-banner-progress'),
              value: fraction,
            ),
          ],
        );
      case AssistedDownloadStatus.verifying:
        return Text(l10n.updateBannerVerifying(kAppName, version));
      case AssistedDownloadStatus.handingOff:
        return Text(l10n.updateBannerPreparingInstaller);
      case AssistedDownloadStatus.completed:
        final revealed = controller.handoffResult == HandoffResult.revealed;
        return Text(
          revealed
              ? l10n.updateBannerCompletedRevealed(kAppName, version)
              : l10n.updateBannerCompletedManual(kAppName, version),
        );
      case AssistedDownloadStatus.failed:
        return Text(
          controller.downloadError ?? l10n.updateBannerDownloadFailed,
          key: const ValueKey('update-banner-error'),
          style: TextStyle(color: theme.colorScheme.error),
        );
      case AssistedDownloadStatus.idle:
      case AssistedDownloadStatus.cancelled:
        return Text(l10n.updateBannerAvailable(kAppName, version));
    }
  }

  List<Widget> _actions(
    BuildContext context,
    UpdateController controller,
    UpdateAvailable update,
  ) {
    final l10n = AppLocalizations.of(context);
    final viewButton = TextButton(
      key: const ValueKey('update-banner-view'),
      onPressed: () => launchExternalUrl(context, update.releaseNotesUrl),
      child: Text(l10n.updateBannerViewRelease),
    );

    if (controller.isDownloadInFlight) {
      final canCancel =
          controller.downloadStatus == AssistedDownloadStatus.downloading ||
          controller.downloadStatus == AssistedDownloadStatus.verifying;
      return [
        if (canCancel)
          TextButton(
            key: const ValueKey('update-banner-cancel'),
            onPressed: () => UpdateScope.controllerOf(context).cancelDownload(),
            child: Text(l10n.commonCancel),
          ),
        viewButton,
      ];
    }

    final dismissButton = TextButton(
      key: const ValueKey('update-banner-dismiss'),
      onPressed: () =>
          UpdateScope.controllerOf(context).dismiss(update.version),
      child: Text(l10n.updateBannerDismiss),
    );

    if (controller.canAssistDownload &&
        controller.downloadStatus != AssistedDownloadStatus.completed) {
      final retry = controller.downloadStatus == AssistedDownloadStatus.failed;
      return [
        dismissButton,
        TextButton(
          key: const ValueKey('update-banner-download'),
          onPressed: () =>
              UpdateScope.controllerOf(context).startAssistedDownload(),
          child: Text(
            retry ? l10n.commonTryAgain : l10n.updateBannerDownloadInstall,
          ),
        ),
        viewButton,
      ];
    }

    return [dismissButton, viewButton];
  }
}
