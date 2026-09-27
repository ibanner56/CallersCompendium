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
/// While a pass runs the glyph becomes a spinner and ignores taps. That is not
/// enough on its own: [SyncController.trigger] consults the connection *before*
/// it marks a pass in flight, so [SyncController.running] is still false for
/// that first await, and a second tap inside it would reach the coordinator,
/// which queues exactly one follow-up pass rather than dropping the request.
/// So the state's `_attempting` flag is set synchronously and held until
/// `_syncNow` finishes, closing that window.
///
/// It depends on [SyncScope] itself (rather than its host screen doing so)
/// because that scope notifies at the start and end of every pass, and a host
/// list screen should not rebuild wholesale for a spinner.
class SyncNowAction extends StatefulWidget {
  const SyncNowAction({super.key});

  @override
  State<SyncNowAction> createState() => _SyncNowActionState();
}

class _SyncNowActionState extends State<SyncNowAction> {
  /// Whether a tap of this button is still being answered, from the moment it
  /// lands until [SyncController.syncNow] returns. Read synchronously by
  /// [_syncNow] so it also stops a second tap that arrives before the frame
  /// that would disable the button.
  bool _attempting = false;

  @override
  Widget build(BuildContext context) {
    final controller = SyncScope.maybeOf(context);
    if (controller == null || !controller.enabled || !controller.paired) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final busy = controller.running || _attempting;
    return IconButton(
      key: const ValueKey('sync-now-action'),
      tooltip: l10n.commonSyncNowTooltip,
      onPressed: busy ? null : () => _syncNow(controller),
      icon: controller.running
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
  ///
  /// The messenger and localizations are resolved only after the await, and
  /// only if this button is still mounted: the outcome can arrive after the
  /// page is gone, and a [ScaffoldMessenger] with no Scaffold left asserts on
  /// `showSnackBar`.
  Future<void> _syncNow(SyncController controller) async {
    if (_attempting) return;
    setState(() => _attempting = true);
    final SyncGateOutcome outcome;
    try {
      outcome = await controller.syncNow();
    } finally {
      if (mounted) setState(() => _attempting = false);
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = switch (outcome) {
      SyncGateOutcome.suppressedMetered => l10n.commonSyncMeteredBlocked,
      SyncGateOutcome.suppressedOffline => l10n.settingsSyncOffline,
      SyncGateOutcome.notPaired => l10n.settingsSyncNotPairedNow,
      SyncGateOutcome.ran || SyncGateOutcome.disabled => null,
    };
    if (message != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
