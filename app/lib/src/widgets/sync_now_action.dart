import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_scope.dart';

/// A toolbar button that starts a manual Device Sync pass from the Collection
/// and Programs pages: a second entry point to the one path Settings ▸ Sync
/// now already uses ([SyncController.syncNow]), with no sync logic of its own.
///
/// Renders nothing unless Device Sync is on **and** a store is paired — the
/// same condition as the Settings row (`sync-now` in `DeviceSyncSection`). An
/// enabled-but-unpaired device would only ever answer "Connect a store", so
/// the glyph stays out of the way until there is something to sync.
///
/// While a pass runs the glyph becomes a spinner and ignores taps;
/// [SyncController.trigger] and the coordinator's single-flight handling
/// coalesce anything that still arrives, so this widget never queues passes.
///
/// It depends on [SyncScope] itself (rather than its host screen doing so)
/// because that scope notifies at the start and end of every pass, and a host
/// list screen should not rebuild wholesale for a spinner.
class SyncNowAction extends StatelessWidget {
  const SyncNowAction({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SyncScope.maybeOf(context);
    if (controller == null || !controller.enabled || !controller.paired) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final running = controller.running;
    return IconButton(
      key: const ValueKey('sync-now-action'),
      tooltip: l10n.commonSyncNowTooltip,
      onPressed: running ? null : () => _syncNow(context, controller),
      icon: running
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
    );
  }

  /// Runs the manual pass and explains a §6.12 gate that stopped it. A pass
  /// that ran says nothing here, as in Settings: its result is the status line
  /// there. The metered wording differs from Settings' on purpose — that one
  /// points at a tile "below", and nothing is below a toolbar button.
  Future<void> _syncNow(BuildContext context, SyncController controller) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final message = switch (await controller.syncNow()) {
      SyncGateOutcome.suppressedMetered => l10n.commonSyncMeteredBlocked,
      SyncGateOutcome.suppressedOffline => l10n.settingsSyncOffline,
      SyncGateOutcome.notPaired => l10n.settingsSyncNotPairedNow,
      SyncGateOutcome.ran || SyncGateOutcome.disabled => null,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
