// The Device Sync device list and the two server-side removals beside it
// (spec §3.3 `DELETE /v1/manifests/{deviceId}`, glossary *wipe* / §5.3
// `DELETE /v1/store`).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';

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

/// Confirms a wipe: the strongest confirmation in the app.
///
/// Lives here rather than on the status surface because it belongs with the
/// device-management contract, and because the surface it is invoked from is
/// shared with other work in flight.
///
/// Returns true only on an explicit confirm. The destructive styling is not
/// decoration: this is the one Device Sync action that destroys data for
/// somebody else's device as well as this one.
Future<bool> confirmSyncWipe(BuildContext context) async {
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
  const SyncDevicesScreen({super.key});

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
          content: Text(l10n.settingsSyncDeviceRemoveFailed),
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
      return _failure(context, l10n, result?.outcome);
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.settingsSyncDevicesCaution,
            key: const ValueKey('sync-devices-caution'),
            style: Theme.of(context).textTheme.bodyMedium,
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
          ListTile(
            key: ValueKey('sync-device-$deviceId'),
            leading: const Icon(Icons.devices_other_outlined),
            // The identifier is the only thing the server knows about a
            // device, so it is shown verbatim rather than abbreviated into
            // something that could collide with another device's prefix.
            title: Text(deviceId),
            trailing: IconButton(
              key: ValueKey('sync-device-remove-$deviceId'),
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsSyncDeviceRemoveTooltip,
              onPressed: _busy ? null : () => _confirmRemove(deviceId),
            ),
          ),
      ],
    );
  }

  Widget _failure(
    BuildContext context,
    AppLocalizations l10n,
    SyncAdminOutcome? outcome,
  ) {
    // A store that has gone is a different fact from a request that failed,
    // and only one of them is worth retrying.
    final storeMissing = outcome == SyncAdminOutcome.storeMissing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              storeMissing
                  ? l10n.settingsSyncDevicesStoreMissing
                  : l10n.settingsSyncDevicesFailed,
              key: const ValueKey('sync-devices-failed'),
              textAlign: TextAlign.center,
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
