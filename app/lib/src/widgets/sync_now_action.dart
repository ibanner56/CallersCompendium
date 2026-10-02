import 'dart:async';

import 'package:flutter/material.dart';

import 'package:compendium_core/compendium_core.dart'
    show CompendiumRepositories;

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../screens/settings/sync_failure_labels.dart';
import '../screens/sync_conflict_sheet.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_coordinator.dart' show SyncPassStatus;
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
///
/// A badge counts the records waiting for the user's conflict choice
/// (sync-spec §6.3), re-read whenever a pass ends. When a manual pass finds
/// conflicts the badge did not already count, the choice opens — but only if
/// this button's page is still the one showing, so it never lands on top of
/// wherever the user went while the pass ran.
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

  /// Records awaiting a conflict choice, as of the last pass to end.
  int _conflicts = 0;
  bool? _lastRunning;

  CompendiumRepositories? get _repositories => context
      .dependOnInheritedWidgetOfExactType<RepositoriesScope>()
      ?.repositories;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SyncScope.maybeOf(context);
    final running = controller?.running ?? false;
    if (_lastRunning != running) {
      _lastRunning = running;
      if (!running) unawaited(_refreshConflicts());
    }
  }

  Future<int> _refreshConflicts() async {
    final repositories = _repositories;
    final controller = SyncScope.maybeOf(context);
    if (repositories == null || controller == null || !controller.paired) {
      return _conflicts;
    }
    try {
      final count = await syncConflictCount(repositories);
      if (mounted && count != _conflicts) setState(() => _conflicts = count);
      return count;
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_now_action.conflicts');
      return _conflicts;
    }
  }

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
      tooltip: _conflicts > 0
          ? l10n.commonSyncNowConflictsTooltip(_conflicts)
          : l10n.commonSyncNowTooltip,
      onPressed: busy ? null : () => _syncNow(controller),
      icon: controller.running
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Badge(
              key: const ValueKey('sync-now-conflict-badge'),
              isLabelVisible: _conflicts > 0,
              label: Text('$_conflicts'),
              child: const Icon(Icons.sync),
            ),
    );
  }

  /// Runs the manual pass and explains a §6.12 gate that stopped it, or a pass
  /// that ran and did not succeed. A successful pass says nothing.
  ///
  /// A failure is reported here, and not left to the Settings status line
  /// alone, because that line is several screens away: a tap that spins and
  /// then shows nothing reads as success to someone who never opens Settings.
  /// The metered wording differs from Settings' on purpose — that one points
  /// at a tile "below", and nothing is below a toolbar button.
  ///
  /// The messenger and localizations are resolved only after the await, and
  /// only if this button is still mounted: the outcome can arrive after the
  /// page is gone, and a [ScaffoldMessenger] with no Scaffold left asserts on
  /// `showSnackBar`.
  Future<void> _syncNow(SyncController controller) async {
    if (_attempting) return;
    setState(() => _attempting = true);
    // Read now, not from the cached badge: that refresh may still be in
    // flight, and a stale zero would make a conflict already waiting look new.
    final conflictsBefore = await _refreshConflicts();
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
      // `ran` means this tap's pass is the one `lastResult` holds.
      SyncGateOutcome.ran => switch (controller.lastResult) {
        final result? => switch (syncPassResultExplanation(l10n, result)) {
          final explanation? => l10n.commonSyncFailed(explanation),
          null when result.status == SyncPassStatus.failed =>
            l10n.settingsSyncStatusFailed,
          null => null,
        },
        null => null,
      },
      SyncGateOutcome.disabled => null,
    };
    if (outcome == SyncGateOutcome.ran) {
      final conflicts = await _refreshConflicts();
      if (!mounted) return;
      if (conflicts > conflictsBefore &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        await showSyncConflictSheet(context);
        if (mounted) await _refreshConflicts();
        return;
      }
    }
    if (message != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          key: const ValueKey('sync-now-action-message'),
          content: Text(message),
          // Long enough to read a reason and its advice.
          duration: const Duration(seconds: 10),
          showCloseIcon: true,
        ),
      );
    }
  }
}
