// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../app_metadata.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../update/update_controller.dart';
import '../../update/update_scope.dart';
import '../../widgets/section_header.dart';

/// The Updates settings section (ADR-002 §4/§5, "Stage 1.5"): a manual "Check
/// for updates" action (always available), a beta-channel opt-in (default off →
/// stable), and an automatic background-check opt-in (default off). On
/// **desktop**, once a newer version with a downloadable artifact is found, it
/// also offers an assisted "Download & install" flow (download → sha256 verify →
/// OS-handoff) with progress, cancel, and a clear error; **mobile** never shows
/// it (the banner's "View release" link is mobile's only path).
///
/// Reads the [UpdateController] via [UpdateScope.of] so it rebuilds live as a
/// check progresses or a pref flips; mutations go through the controller, which
/// persists to the shared settings store. The check is a plain HTTPS GET of a
/// static manifest and sends no data about the user or device (§5).
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final controller = UpdateScope.of(context);
    final status = controller.status;
    final checking = status == UpdateCheckStatus.checking;

    return ListView(
      children: [
        SectionHeader(title: l10n.settingsUpdatesHeader),
        ListTile(
          key: const ValueKey('updates-check-now'),
          leading: const Icon(Icons.system_update_alt),
          title: Text(l10n.settingsUpdatesCheckNowTitle),
          subtitle: Text(_statusText(l10n, controller)),
          trailing: checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onTap: checking ? null : controller.checkNow,
        ),
        if (controller.canAssistDownload)
          _downloadTile(context, controller, theme),
        SectionHeader(title: l10n.settingsUpdatesChannelHeader),
        SwitchListTile(
          key: const ValueKey('updates-beta-toggle'),
          secondary: const Icon(Icons.science_outlined),
          title: Text(l10n.settingsUpdatesBetaTitle),
          subtitle: Text(l10n.settingsUpdatesBetaSubtitle),
          value: controller.betaChannel,
          onChanged: controller.setBetaChannel,
        ),
        SectionHeader(title: l10n.settingsUpdatesAutoHeader),
        SwitchListTile(
          key: const ValueKey('updates-auto-toggle'),
          secondary: const Icon(Icons.schedule_outlined),
          title: Text(l10n.settingsUpdatesAutoTitle),
          subtitle: Text(l10n.settingsUpdatesAutoSubtitle),
          value: controller.autoCheck,
          onChanged: controller.setAutoCheck,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Text(
            l10n.settingsUpdatesPrivacyNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// The desktop assisted-download tile (ADR-002 "Stage 1.5"), shown only when
  /// [UpdateController.canAssistDownload]. Reflects each phase of the flow and
  /// surfaces a clear, non-silent error on failure — the download/verify gate is
  /// deliberately loud, unlike the silent check.
  Widget _downloadTile(
    BuildContext context,
    UpdateController controller,
    ThemeData theme,
  ) {
    final l10n = AppLocalizations.of(context);
    final version = controller.foundUpdate?.version.toString() ?? '';
    const spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    switch (controller.downloadStatus) {
      case AssistedDownloadStatus.downloading:
        final fraction = controller.downloadProgress?.fraction;
        final pct = fraction == null ? null : (fraction * 100).round();
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: const Icon(Icons.download_outlined),
          title: Text(l10n.settingsUpdatesDownloadingTitle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(
                key: const ValueKey('updates-download-progress'),
                value: fraction,
              ),
              const SizedBox(height: 4),
              Text(
                pct == null
                    ? l10n.settingsUpdatesDownloadingIndeterminate
                    : l10n.settingsUpdatesDownloadingPercent(pct),
              ),
            ],
          ),
          trailing: TextButton(
            key: const ValueKey('updates-download-cancel'),
            onPressed: controller.cancelDownload,
            child: Text(l10n.commonCancel),
          ),
        );
      case AssistedDownloadStatus.verifying:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: const Icon(Icons.verified_outlined),
          title: Text(l10n.settingsUpdatesVerifyingTitle),
          subtitle: Text(l10n.settingsUpdatesVerifyingSubtitle),
          trailing: spinner,
        );
      case AssistedDownloadStatus.handingOff:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: const Icon(Icons.open_in_new),
          title: Text(l10n.settingsUpdatesHandoffTitle),
          subtitle: Text(l10n.settingsUpdatesHandoffSubtitle),
          trailing: spinner,
        );
      case AssistedDownloadStatus.completed:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: Icon(
            Icons.check_circle_outline,
            color: theme.colorScheme.primary,
          ),
          title: Text(l10n.settingsUpdatesCompletedTitle),
          subtitle: Text(l10n.settingsUpdatesCompletedSubtitle),
        );
      case AssistedDownloadStatus.failed:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: Text(l10n.settingsUpdatesDownloadTitle),
          subtitle: Text(
            controller.downloadError ?? l10n.settingsUpdatesDownloadError,
            key: const ValueKey('updates-download-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
          trailing: const Icon(Icons.refresh),
          onTap: controller.startAssistedDownload,
        );
      case AssistedDownloadStatus.idle:
      case AssistedDownloadStatus.cancelled:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: const Icon(Icons.download_outlined),
          title: Text(l10n.settingsUpdatesDownloadTitle),
          subtitle: Text(l10n.settingsUpdatesDownloadSubtitle(version)),
          trailing: const Icon(Icons.download),
          onTap: controller.startAssistedDownload,
        );
    }
  }

  /// The inline status line under "Check for updates". Never an error — a
  /// silent failure reads the same as "no update found" by design (§5).
  String _statusText(AppLocalizations l10n, UpdateController controller) {
    switch (controller.status) {
      case UpdateCheckStatus.idle:
        return l10n.settingsUpdatesStatusIdle(kAppVersion);
      case UpdateCheckStatus.checking:
        return l10n.settingsUpdatesStatusChecking;
      case UpdateCheckStatus.noUpdate:
        return l10n.settingsUpdatesStatusNoUpdate(kAppVersion);
      case UpdateCheckStatus.updateAvailable:
        final found = controller.foundUpdate;
        final version = found?.version.toString() ?? '';
        return l10n.settingsUpdatesStatusAvailable(version);
    }
  }
}
