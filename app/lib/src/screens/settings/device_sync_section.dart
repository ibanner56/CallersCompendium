// Part of the Settings screen: the Device Sync group of the Experimental pane.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart' show syncIdWordCount;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../diagnostics/error_log.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_coordinator.dart' show SyncPassStatus;
import '../../sync/sync_http_client.dart' show isDefaultSyncEndpoint;
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/section_header.dart';
import 'sync_notice_labels.dart';
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

  /// Whether the user has already confirmed a replacement on this surface.
  /// Set before the call, not after it: the controller notifies from its
  /// `finally` and re-shows the dialog before an awaited result comes back, so
  /// a flag written afterwards would arrive too late for the dialog it is
  /// meant to explain. It only qualifies [SyncController.lastResult], so a
  /// failure from some earlier, unrelated pass cannot be reported as this
  /// dialog's.
  bool _replacementConfirmAttempted = false;

  /// The sync phrase currently shown in the clear, or null while it is
  /// masked. Holding the phrase rather than a bool means a reveal cannot
  /// survive the phrase changing underneath it — detaching and pairing with a
  /// different store re-masks on its own. Never persisted: see [_SyncIdTile].
  String? _revealedSyncId;

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
        // A confirmation that failed leaves the decision pending, so this
        // dialog is still — or straight back — on screen, and without a word
        // about the last attempt that reads as the tap having been ignored.
        // The status line that would explain it sits behind a
        // barrier-dismissible-false barrier, so it has to be said here.
        //
        // Built against the live controller rather than a value read when the
        // dialog opened: the controller notifies when it takes the pass in
        // flight, which can re-show this dialog *before* the attempt has a
        // result, so a snapshot taken at open time would always predate the
        // failure it is meant to report.
        content: ListenableBuilder(
          listenable: controller,
          builder: (builderContext, _) {
            final lastAttemptFailed =
                _replacementConfirmAttempted &&
                controller.lastResult?.status == SyncPassStatus.failed;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsSyncReplacementBody),
                if (lastAttemptFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      l10n.settingsSyncReplacementFailed,
                      key: const ValueKey('sync-replacement-failed'),
                      style: TextStyle(
                        color: Theme.of(builderContext).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
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
              unawaited(_confirmReplacement(controller));
            },
            child: Text(l10n.settingsSyncReplacementConfirm),
          ),
        ],
      ),
    ).whenComplete(() => _replacementDialogShowing = false);
  }

  /// Confirms replacement and reports what the §6.12 gate did with it.
  ///
  /// A suppressed confirmation sends nothing and leaves the decision pending,
  /// and the controller deliberately does not notify — so this dialog stays
  /// closed and the routing message and the *Sync only on WiFi* tile are
  /// actually reachable behind it.
  Future<void> _confirmReplacement(SyncController controller) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    _replacementConfirmAttempted = true;
    final outcome = await controller.confirmReplacement();
    if (!mounted) return;
    final message = _gateMessage(l10n, outcome);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// What to tell the user about a manual attempt the §6.12 gate stopped, or
  /// null when it ran.
  String? _gateMessage(AppLocalizations l10n, SyncGateOutcome outcome) =>
      switch (outcome) {
        SyncGateOutcome.suppressedMetered => l10n.settingsSyncMeteredRouted,
        SyncGateOutcome.suppressedOffline => l10n.settingsSyncOffline,
        SyncGateOutcome.notPaired => l10n.settingsSyncNotPairedNow,
        _ => null,
      };

  /// Copies the sync phrase for entry on another device. The confirmation
  /// restates what the phrase is, because a clipboard is a shared surface and
  /// the copy is the moment the credential leaves this app.
  Future<void> _copySyncId(String syncId) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: syncId));
    messenger?.showSnackBar(
      SnackBar(
        key: const ValueKey('sync-id-copied'),
        content: Text(l10n.settingsSyncIdCopied),
      ),
    );
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
    final message = _gateMessage(l10n, await controller.syncNow());
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Detach is purely local and reversible only by re-entering the phrase, so
  /// it is confirmed first and says what it does and does not touch.
  Future<void> _confirmDisconnect(SyncController controller) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('sync-disconnect-dialog'),
        title: Text(l10n.settingsSyncDisconnectConfirmTitle),
        content: Text(l10n.settingsSyncDisconnectConfirmBody),
        actions: [
          TextButton(
            key: const ValueKey('sync-disconnect-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const ValueKey('sync-disconnect-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsSyncDisconnectConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controller.detach();
    } on Object catch (e, st) {
      logCaughtErrorTypeOnly(e, st, source: 'device_sync_section.disconnect');
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.settingsSyncDisconnectFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = SyncScope.of(context);
    const gutter = EdgeInsets.symmetric(horizontal: AppSpacing.md);

    // Starts open while sync is on, so its status and any failure stay in
    // view; folds away otherwise to keep the Experimental pane uncluttered.
    return CollapsibleSection(
      sectionKey: const ValueKey('sync-section'),
      title: l10n.settingsSyncHeader,
      expanded: controller.enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            if (controller.syncId case final syncId?)
              _SyncIdTile(
                syncId: syncId,
                revealed: _revealedSyncId == syncId,
                onToggleReveal: () => setState(
                  () => _revealedSyncId = _revealedSyncId == syncId
                      ? null
                      : syncId,
                ),
                onCopy: () => _copySyncId(syncId),
              ),
            Builder(
              builder: (tileContext) {
                final failureText = _failureText(l10n, controller);
                final lastSuccess = controller.lastSuccessAt;
                return ListTile(
                  key: const ValueKey('sync-status'),
                  leading: Icon(
                    failureText != null
                        ? Icons.error_outline
                        : Icons.info_outline,
                    color: failureText != null ? theme.colorScheme.error : null,
                  ),
                  title: Text(
                    failureText ?? _statusText(tileContext, controller),
                  ),
                  subtitle: failureText != null && lastSuccess != null
                      ? Text(
                          l10n.settingsSyncStatusLastSynced(
                            _formatWhen(tileContext, lastSuccess),
                          ),
                          key: const ValueKey('sync-status-last-success'),
                        )
                      : null,
                  trailing: controller.paired
                      ? null
                      : FilledButton(
                          key: const ValueKey('sync-connect'),
                          onPressed: () => showSyncPairingScreen(
                            tileContext,
                            backupSaver: widget.backupSaver,
                          ),
                          child: Text(l10n.settingsSyncConnectTitle),
                        ),
                );
              },
            ),
            // The conditions the last pass to raise any had to report (spec
            // §2 *report*): non-blocking, no dismissal, nothing to tap. They
            // sit beside the status rather than in it because a pass can
            // complete successfully and still have something to say.
            for (final group in syncNoticeGroups(controller.notices))
              ListTile(
                key: ValueKey('sync-notice-${group.name}'),
                leading: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.tertiary,
                ),
                title: Text(syncNoticeText(l10n, group)),
              ),
            if (controller.paired &&
                controller.endpoint != null &&
                !isDefaultSyncEndpoint(controller.endpoint!))
              ListTile(
                key: const ValueKey('sync-custom-endpoint'),
                leading: Icon(
                  Icons.dns_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.settingsSyncCustomEndpointStatus(
                    controller.endpoint!.host,
                  ),
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
            if (controller.paired)
              ListTile(
                key: const ValueKey('sync-disconnect'),
                leading: const Icon(Icons.link_off),
                title: Text(l10n.settingsSyncDisconnectTitle),
                subtitle: Text(l10n.settingsSyncDisconnectSubtitle),
                enabled: !controller.running,
                onTap: controller.running
                    ? null
                    : () => _confirmDisconnect(controller),
              ),
          ],
        ],
      ),
    );
  }

  String _statusText(BuildContext context, SyncController controller) {
    final l10n = AppLocalizations.of(context);
    if (controller.running) return l10n.settingsSyncStatusSyncing;
    if (!controller.paired) return l10n.settingsSyncStatusNotPaired;
    final last = controller.lastSuccessAt;
    if (last == null) return l10n.settingsSyncStatusNeverSynced;
    return l10n.settingsSyncStatusLastSynced(_formatWhen(context, last));
  }

  String _formatWhen(BuildContext context, DateTime when) => DateFormat.yMMMd(
    Localizations.localeOf(context).toString(),
  ).add_jm().format(when.toLocal());

  /// The line for the last completed trigger attempt when it was not a
  /// success, or null when the last attempt succeeded, nothing has run yet in
  /// this session, or a pass is currently running (the syncing status on
  /// [_statusText] takes priority over a stale failure from an earlier pass).
  ///
  /// The two missing-store outcomes are deliberately kept apart, as spec §6.2
  /// and the pairing flow keep them apart: `replacementRequired` is a store
  /// this device *had* used and that has since gone, so it may have expired
  /// or been removed — never claimed as either, per §6.14 item 6 — and the
  /// replacement dialog owns the decision; `firstTimeStoreRequired` is a
  /// stored phrase no store has ever answered to, which is the mistyped or
  /// never-created case, and saying "expired" there would explain a store
  /// that never existed. A stale epoch needs no action: the next pass
  /// fresh-attaches to the replaced store on its own.
  String? _failureText(AppLocalizations l10n, SyncController controller) {
    if (controller.running || !controller.paired) return null;
    return switch (controller.lastResult?.status) {
      SyncPassStatus.failed => l10n.settingsSyncStatusFailed,
      SyncPassStatus.staleEpoch => l10n.settingsSyncStatusStaleStore,
      SyncPassStatus.replacementRequired =>
        l10n.settingsSyncStatusStoreUnavailable,
      SyncPassStatus.firstTimeStoreRequired =>
        l10n.settingsSyncStatusStoreNotFound,
      // Declining a replacement leaves sync configured but paused so a later
      // action can reconsider (spec §6.3 step 1, §6.14 item 6). Every
      // automatic trigger then answers `paused` without running a pass, so
      // without this arm the surface fell back to the last success — a date
      // belonging to a store that no longer exists. `declineReplacement` is
      // the only thing that pauses the coordinator, so naming the missing
      // store here claims nothing the pause does not already mean.
      SyncPassStatus.paused => l10n.settingsSyncStatusPaused,
      _ => null,
    };
  }
}

/// The sync phrase this device is attached to, on the status surface so the
/// user can enter it on another device without having written it down at
/// pairing (spec §6.14 item 2: it cannot be recovered from the server).
///
/// Masked until the user asks for it. The phrase is a bearer credential with
/// no revocation, so a settings pane that displays it unprompted hands it to
/// anyone who is shown the screen — a screenshot sent to support, a shared
/// display, someone standing behind the caller at a dance. Copying works
/// while it is masked, because the common case is moving it to another device
/// and that never needs it on screen. The reveal is per-visit state and is
/// deliberately not persisted.
class _SyncIdTile extends StatelessWidget {
  const _SyncIdTile({
    required this.syncId,
    required this.revealed,
    required this.onToggleReveal,
    required this.onCopy,
  });

  final String syncId;
  final bool revealed;
  final VoidCallback onToggleReveal;
  final VoidCallback onCopy;

  /// The masked rendering: one bullet group per word, so the phrase's shape is
  /// still recognisable. Word *lengths* are not shown — those narrow a guess.
  static final String _mask = List.filled(syncIdWordCount, '•' * 4).join('-');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const ValueKey('sync-id'),
          leading: const Icon(Icons.key_outlined),
          title: Text(l10n.settingsSyncIdTitle),
          subtitle: Text(
            revealed ? syncId : _mask,
            key: const ValueKey('sync-id-value'),
            semanticsLabel: revealed ? syncId : l10n.settingsSyncIdMasked,
            style: theme.textTheme.titleMedium,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('sync-id-reveal'),
                icon: Icon(
                  revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: revealed
                    ? l10n.settingsSyncIdHide
                    : l10n.settingsSyncIdShow,
                onPressed: onToggleReveal,
              ),
              IconButton(
                key: const ValueKey('sync-id-copy'),
                icon: const Icon(Icons.copy_outlined),
                tooltip: l10n.settingsSyncIdCopy,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            l10n.settingsSyncIdCaution,
            key: const ValueKey('sync-id-caution'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
