// The Device Sync device list and the two server-side removals beside it
// (spec §3.3 `DELETE /v1/manifests/{deviceId}`, glossary *wipe* / §5.3
// `DELETE /v1/store`).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_coordinator.dart' show SyncPeerSummary;
import '../../sync/sync_failure.dart';
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';
import 'sync_device_labels.dart';
import 'sync_failure_labels.dart';

/// Pushes the list of the *other* devices attached to this store.
///
/// A click-through rather than a section on the status surface: it makes a
/// network request on open, and the settings pane must stay silent while the
/// user is only looking at it.
Future<void> showSyncDevicesScreen(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SyncDevicesScreen()));
}

/// Confirms a wipe and, if the user goes ahead, performs it.
///
/// The whole flow lives here rather than on the status surface because it is
/// part of the device-management contract, and because the status surface is
/// shared with other work in flight.
///
/// The controller detaches this device only on success; a failure leaves it
/// attached, and this says so rather than letting a destructive action appear
/// to have been ignored.
Future<void> confirmAndWipeStore(
  BuildContext context,
  SyncController controller,
) async {
  if (!await _confirmSyncWipe(context) || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  switch (await controller.wipeStore()) {
    case SyncAdminOutcome.done:
      break;
    // The store is irreversibly gone and this device is still attached to it.
    // Reported as its own thing, never as a failure: telling the user nothing
    // happened would invite them to retry a destructive action that already
    // succeeded, and would leave them unaware that this device still holds the
    // phrase for a store that no longer exists.
    case SyncAdminOutcome.wipedButStillAttached:
      messenger?.showSnackBar(
        SnackBar(
          key: const ValueKey('sync-wipe-detach-failed'),
          content: Text(l10n.settingsSyncWipeDetachFailed),
          duration: const Duration(seconds: 10),
        ),
      );
    case _:
      messenger?.showSnackBar(
        SnackBar(
          key: const ValueKey('sync-wipe-failed'),
          content: Text(
            _withReason(
              l10n,
              l10n.settingsSyncWipeFailed,
              controller.lastAdminFailure,
            ),
          ),
        ),
      );
  }
}

/// [message] followed by why the action failed, when that is known.
///
/// The reason only, not the advice: these snackbars already say what state
/// the device was left in and what to do next, and the generic advice would
/// contradict them (a wipe's "check your other devices before trying again").
String _withReason(
  AppLocalizations l10n,
  String message,
  SyncFailure? failure,
) => failure == null
    ? message
    : l10n.settingsSyncAdminFailedBecause(
        message,
        syncFailureReason(l10n, failure.cause),
      );

/// The strongest confirmation in the app. Returns true only on an explicit
/// confirm. The destructive styling is not decoration: this is the one Device
/// Sync action that destroys data for somebody else's device as well as this
/// one.
Future<bool> _confirmSyncWipe(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        key: const ValueKey('sync-wipe-dialog'),
        title: Text(l10n.settingsSyncWipeConfirmTitle),
        content: SingleChildScrollView(
          child: Text(l10n.settingsSyncWipeConfirmBody),
        ),
        actions: [
          TextButton(
            key: const ValueKey('sync-wipe-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const ValueKey('sync-wipe-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsSyncWipeConfirmAction),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

class SyncDevicesScreen extends StatefulWidget {
  const SyncDevicesScreen({super.key, this.now});

  /// The clock "last shared changes" is measured against; the wall clock when
  /// null. A parameter so a test can pin the day.
  final DateTime Function()? now;

  @override
  State<SyncDevicesScreen> createState() => _SyncDevicesScreenState();
}

class _SyncDevicesScreenState extends State<SyncDevicesScreen> {
  /// The last listing, or null while the first one is still in flight.
  ///
  /// Re-fetched on every visit and after every removal rather than cached:
  /// the store is shared, so a peer removed from another device must not keep
  /// appearing here, and a removal must be seen to have happened.
  SyncDeviceListResult? _result;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the request is not issued during
    // build, and so the screen paints its progress indicator first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // The first call arrives from a post-frame callback, which still runs when
    // the screen was popped inside that same frame; reading the scope off a
    // defunct element would throw rather than simply do nothing.
    if (!mounted) return;
    final controller = SyncScope.of(context);
    if (!_loading) setState(() => _loading = true);
    final result = await controller.listStoreDevices();
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _confirmRemove(String deviceId) async {
    final l10n = AppLocalizations.of(context);
    final controller = SyncScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('sync-device-remove-dialog'),
        title: Text(l10n.settingsSyncDeviceRemoveTitle),
        content: Text(l10n.settingsSyncDeviceRemoveBody),
        actions: [
          TextButton(
            key: const ValueKey('sync-device-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const ValueKey('sync-device-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsSyncDeviceRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    final outcome = await controller.removeDevice(deviceId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome != SyncAdminOutcome.done) {
      messenger?.showSnackBar(
        SnackBar(
          key: const ValueKey('sync-device-remove-failed'),
          content: Text(
            _withReason(
              l10n,
              l10n.settingsSyncDeviceRemoveFailed,
              controller.lastAdminFailure,
            ),
          ),
        ),
      );
    }
    // Re-read either way: a removal that reported a failure may still have
    // reached the server, and a listing is the only thing that can say.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSyncDevicesScreenTitle)),
      body: SafeArea(child: _body(context, l10n)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        key: ValueKey('sync-devices-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final result = _result;
    if (result == null || result.outcome != SyncAdminOutcome.done) {
      return _failure(context, l10n, result);
    }
    final summaries = SyncScope.of(context).peerSummaries;
    final self = result.selfDeviceId;
    // Computed over every identifier on the screen, this device's included,
    // so no two tags shown together are equal.
    final tags = syncDeviceTags([...result.devices, ?self]);
    final now = (widget.now ?? DateTime.now)();
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.settingsSyncDevicesCaution,
            key: const ValueKey('sync-devices-caution'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (self != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              l10n.settingsSyncDevicesThisDevice(tags[self]!),
              key: const ValueKey('sync-devices-self'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (result.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              l10n.settingsSyncDevicesEmpty,
              key: const ValueKey('sync-devices-empty'),
            ),
          ),
        for (final deviceId in result.devices)
          _deviceTile(
            l10n,
            deviceId,
            tags[deviceId]!,
            summaries[deviceId],
            now,
          ),
      ],
    );
  }

  /// One other device: its tag, and — when the last completed pass read its
  /// manifest — when it last shared changes and how many of this device's are
  /// waiting for it. A device that pass did not see gets the tag alone rather
  /// than a guess.
  Widget _deviceTile(
    AppLocalizations l10n,
    String deviceId,
    String tag,
    SyncPeerSummary? summary,
    DateTime now,
  ) {
    final lines = [
      if (summary != null)
        Text(
          syncLastSharedText(l10n, summary.writtenAt, now),
          key: ValueKey('sync-device-last-shared-$deviceId'),
        ),
      if (summary != null && summary.waitingCount > 0)
        Text(
          l10n.settingsSyncDeviceWaiting(summary.waitingCount),
          key: ValueKey('sync-device-waiting-$deviceId'),
        ),
    ];
    return ListTile(
      key: ValueKey('sync-device-$deviceId'),
      leading: const Icon(Icons.devices_other_outlined),
      // A short tag rather than the whole identifier: the identifier is all
      // the server knows about a device, but 24 random characters are not
      // something a person can compare across two screens, and the tag is
      // what this device's own line and the notices name it by. It is
      // lengthened wherever two would otherwise read the same, so shortening
      // cannot make two devices look like one.
      title: Text(l10n.settingsSyncDeviceTag(tag)),
      subtitle: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
      trailing: IconButton(
        key: ValueKey('sync-device-remove-$deviceId'),
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.settingsSyncDeviceRemoveTooltip,
        onPressed: _busy ? null : () => _confirmRemove(deviceId),
      ),
    );
  }

  Widget _failure(
    BuildContext context,
    AppLocalizations l10n,
    SyncDeviceListResult? result,
  ) {
    // A store that has gone is a different fact from a request that failed,
    // and only one of them is worth retrying.
    final storeMissing = result?.outcome == SyncAdminOutcome.storeMissing;
    final failure = result?.failure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              storeMissing
                  ? l10n.settingsSyncDevicesStoreMissing
                  : failure == null
                  ? l10n.settingsSyncDevicesFailed
                  : l10n.settingsSyncDevicesFailedBecause(
                      syncFailureExplanation(l10n, failure),
                    ),
              key: const ValueKey('sync-devices-failed'),
              textAlign: TextAlign.center,
            ),
            if (!storeMissing && failure != null)
              if (syncFailureDetails(l10n, failure) case final details?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    details,
                    key: const ValueKey('sync-devices-failed-details'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            if (!storeMissing)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: FilledButton(
                  key: const ValueKey('sync-devices-retry'),
                  onPressed: _load,
                  child: Text(l10n.settingsSyncDevicesRetry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
