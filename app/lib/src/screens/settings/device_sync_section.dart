// Part of the Settings screen: the Device Sync group of the Experimental pane.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/section_header.dart';
import 'sync_pairing_screen.dart';

/// Device Sync settings and status (spec §6.1, §6.12, §6.14).
///
/// Sync is off until the user turns it on; nothing here makes a network call
/// while it is off. The not-a-backup disclosure and the expiry warning live on
/// the status surface itself, not only at pairing, because a "last synced" line
/// is exactly what a user reads as "my data is safe" (spec §6.14 item 3).
class DeviceSyncSection extends StatefulWidget {
  const DeviceSyncSection({super.key, this.backupSaver});

  /// Test seam forwarded to the pairing screen's backup offer; defaults to
  /// [saveBackupToFile].
  final BackupSaver? backupSaver;

  @override
  State<DeviceSyncSection> createState() => _DeviceSyncSectionState();
}

class _DeviceSyncSectionState extends State<DeviceSyncSection> {
  final _wifiTileKey = GlobalKey();
  SyncController? _controller;

  bool _replacementDialogShowing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SyncScope.of(context);
    if (!identical(controller, _controller)) {
      _controller?.wifiSettingRequests.removeListener(_routeToWifiSetting);
      _controller?.removeListener(_maybeShowReplacementDialog);
      _controller = controller
        ..wifiSettingRequests.addListener(_routeToWifiSetting)
        ..addListener(_maybeShowReplacementDialog);
      // Deferred to after this frame: replacementPending can already be true
      // here (e.g. a startup sync found the missing store before the user
      // opened Experimental), and showDialog pushing a route during build
      // trips Flutter's "markNeedsBuild called during build" assertion.
      // A later, listener-driven call runs outside build and stays immediate.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowReplacementDialog(),
      );
    }
  }

  @override
  void dispose() {
    _controller?.wifiSettingRequests.removeListener(_routeToWifiSetting);
    _controller?.removeListener(_maybeShowReplacementDialog);
    super.dispose();
  }

  /// Shown at the moment §6.3 step 1 finds a previously used store missing
  /// (spec §6.14 item 6): explains it may have expired or been removed, and
  /// requires confirmation before replacing it. Cancel makes no network call.
  void _maybeShowReplacementDialog() {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !controller.replacementPending ||
        _replacementDialogShowing) {
      return;
    }
    _replacementDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('sync-replacement-dialog'),
        title: Text(l10n.settingsSyncReplacementTitle),
        content: Text(l10n.settingsSyncReplacementBody),
        actions: [
          TextButton(
            key: const ValueKey('sync-replacement-cancel'),
            onPressed: () {
              controller.declineReplacement();
              Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.settingsSyncReplacementCancel),
          ),
          FilledButton(
            key: const ValueKey('sync-replacement-confirm'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(controller.confirmReplacement());
            },
            child: Text(l10n.settingsSyncReplacementConfirm),
          ),
        ],
      ),
    ).whenComplete(() => _replacementDialogShowing = false);
  }

  /// A manual attempt on a metered connection is routed to the setting rather
  /// than failing (spec §6.12).
  void _routeToWifiSetting() {
    final tile = _wifiTileKey.currentContext;
    if (tile != null) Scrollable.ensureVisible(tile);
  }

  Future<void> _syncNow(SyncController controller) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final outcome = await controller.syncNow();
    final message = switch (outcome) {
      SyncGateOutcome.suppressedMetered => l10n.settingsSyncMeteredRouted,
      SyncGateOutcome.suppressedOffline => l10n.settingsSyncOffline,
      SyncGateOutcome.notPaired => l10n.settingsSyncNotPairedNow,
      _ => null,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = SyncScope.of(context);
    const gutter = EdgeInsets.symmetric(horizontal: AppSpacing.md);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.settingsSyncHeader),
        Padding(padding: gutter, child: Text(l10n.settingsSyncIntro)),
        SwitchListTile(
          key: const ValueKey('sync-enabled-toggle'),
          secondary: const Icon(Icons.sync_outlined),
          title: Text(l10n.settingsSyncEnableTitle),
          subtitle: Text(l10n.settingsSyncEnableSubtitle),
          value: controller.enabled,
          onChanged: controller.setEnabled,
        ),
        if (controller.enabled) ...[
          SwitchListTile(
            key: _wifiTileKey,
            secondary: const Icon(Icons.wifi),
            title: Text(l10n.settingsSyncWifiOnlyTitle),
            subtitle: Text(l10n.settingsSyncWifiOnlySubtitle),
            value: controller.wifiOnly,
            onChanged: controller.setWifiOnly,
          ),
          SwitchListTile(
            key: const ValueKey('sync-exclude-imports-toggle'),
            secondary: const Icon(Icons.filter_alt_outlined),
            title: Text(l10n.settingsSyncExcludeImportsTitle),
            subtitle: Text(l10n.settingsSyncExcludeImportsSubtitle),
            value: controller.excludeImports,
            onChanged: controller.setExcludeImports,
          ),
          SectionHeader(title: l10n.settingsSyncStatusHeader),
          ListTile(
            key: const ValueKey('sync-status'),
            leading: const Icon(Icons.info_outline),
            title: Text(_statusText(context, controller)),
            trailing: controller.paired
                ? null
                : FilledButton(
                    key: const ValueKey('sync-connect'),
                    onPressed: () => showSyncPairingScreen(
                      context,
                      backupSaver: widget.backupSaver,
                    ),
                    child: Text(l10n.settingsSyncConnectTitle),
                  ),
          ),
          Padding(
            padding: gutter,
            child: Text(
              l10n.settingsSyncNotBackup,
              key: const ValueKey('sync-not-a-backup'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (controller.expiryApproaching)
            Padding(
              padding: gutter.copyWith(top: AppSpacing.sm),
              child: Text(
                l10n.settingsSyncExpiryWarning,
                key: const ValueKey('sync-expiry-warning'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (controller.paired)
            ListTile(
              key: const ValueKey('sync-now'),
              leading: const Icon(Icons.sync),
              title: Text(l10n.settingsSyncNowTitle),
              enabled: !controller.running,
              onTap: controller.running ? null : () => _syncNow(controller),
            ),
        ],
      ],
    );
  }

  String _statusText(BuildContext context, SyncController controller) {
    final l10n = AppLocalizations.of(context);
    if (controller.running) return l10n.settingsSyncStatusSyncing;
    if (!controller.paired) return l10n.settingsSyncStatusNotPaired;
    final last = controller.lastSuccessAt;
    if (last == null) return l10n.settingsSyncStatusNeverSynced;
    final when = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm().format(last.toLocal());
    return l10n.settingsSyncStatusLastSynced(when);
  }
}
