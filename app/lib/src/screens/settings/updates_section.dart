// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../app_metadata.dart';
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
    final controller = UpdateScope.of(context);
    final status = controller.status;
    final checking = status == UpdateCheckStatus.checking;

    return ListView(
      children: [
        SectionHeader(title: 'Updates'),
        ListTile(
          key: const ValueKey('updates-check-now'),
          leading: const Icon(Icons.system_update_alt),
          title: const Text('Check for updates'),
          subtitle: Text(_statusText(controller)),
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
        SectionHeader(title: 'Channel'),
        SwitchListTile(
          key: const ValueKey('updates-beta-toggle'),
          secondary: const Icon(Icons.science_outlined),
          title: const Text('Beta channel'),
          subtitle: const Text(
            'Receive pre-release beta updates. Off means stable releases only.',
          ),
          value: controller.betaChannel,
          onChanged: controller.setBetaChannel,
        ),
        SectionHeader(title: 'Automatic checks'),
        SwitchListTile(
          key: const ValueKey('updates-auto-toggle'),
          secondary: const Icon(Icons.schedule_outlined),
          title: const Text('Check automatically'),
          subtitle: const Text(
            'Check for a newer version in the background when the app starts. '
            'Off by default.',
          ),
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
            'The update check downloads a small version file over HTTPS and '
            'nothing else — no data about you, your device, or your usage is '
            'ever sent. Nothing is downloaded or installed automatically: you '
            'choose when to download an update, it is verified before it opens, '
            'and your system installer completes the install.',
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
          title: const Text('Downloading update'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(
                key: const ValueKey('updates-download-progress'),
                value: fraction,
              ),
              const SizedBox(height: 4),
              Text(pct == null ? 'Downloading…' : 'Downloading… $pct%'),
            ],
          ),
          trailing: TextButton(
            key: const ValueKey('updates-download-cancel'),
            onPressed: controller.cancelDownload,
            child: const Text('Cancel'),
          ),
        );
      case AssistedDownloadStatus.verifying:
        return const ListTile(
          key: ValueKey('updates-download'),
          leading: Icon(Icons.verified_outlined),
          title: Text('Verifying download'),
          subtitle: Text('Checking the sha256 integrity of the download…'),
          trailing: spinner,
        );
      case AssistedDownloadStatus.handingOff:
        return const ListTile(
          key: ValueKey('updates-download'),
          leading: Icon(Icons.open_in_new),
          title: Text('Opening the installer'),
          subtitle: Text('Handing the verified update to your system…'),
          trailing: spinner,
        );
      case AssistedDownloadStatus.completed:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: Icon(
            Icons.check_circle_outline,
            color: theme.colorScheme.primary,
          ),
          title: const Text('Update downloaded'),
          subtitle: const Text(
            'Follow your system installer to finish updating.',
          ),
        );
      case AssistedDownloadStatus.failed:
        return ListTile(
          key: const ValueKey('updates-download'),
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: const Text('Download & install update'),
          subtitle: Text(
            controller.downloadError ?? 'The update could not be downloaded.',
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
          title: const Text('Download & install update'),
          subtitle: Text(
            'Download version $version, verify it, then open your installer. '
            'The app never replaces itself in place.',
          ),
          trailing: const Icon(Icons.download),
          onTap: controller.startAssistedDownload,
        );
    }
  }

  /// The inline status line under "Check for updates". Never an error — a
  /// silent failure reads the same as "no update found" by design (§5).
  String _statusText(UpdateController controller) {
    switch (controller.status) {
      case UpdateCheckStatus.idle:
        return "You're on version $kAppVersion.";
      case UpdateCheckStatus.checking:
        return 'Checking…';
      case UpdateCheckStatus.noUpdate:
        return "No update found. You're on version $kAppVersion.";
      case UpdateCheckStatus.updateAvailable:
        final found = controller.foundUpdate;
        final version = found?.version.toString() ?? '';
        return 'Version $version is available. See the banner to view it.';
    }
  }
}
