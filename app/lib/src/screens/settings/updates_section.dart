// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';

import '../../app_metadata.dart';
import '../../theme/app_spacing.dart';
import '../../update/update_controller.dart';
import '../../update/update_scope.dart';
import '../../widgets/section_header.dart';

/// The Updates settings section (ADR-002 §4/§5): a manual "Check for updates"
/// action (always available), a beta-channel opt-in (default off → stable), and
/// an automatic background-check opt-in (default off).
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
            'ever sent. Nothing is downloaded or installed automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
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
