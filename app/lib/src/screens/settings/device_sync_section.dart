// Part of the Settings screen: the Device Sync group of the Experimental pane.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart'
    show SyncReport, syncIdWordCount;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/backup_io.dart';
import '../../data/repositories_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_coordinator.dart'
    show SyncFailureCauseTier, SyncPassResult, SyncPassStatus;
import '../../sync/sync_http_client.dart' show isDefaultSyncEndpoint;
import '../../sync/sync_scope.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/section_header.dart';
import '../sync_conflict_sheet.dart';
import '../sync_review_screen.dart';
import 'sync_device_labels.dart';
import 'sync_devices_screen.dart';
import 'sync_failure_labels.dart';
import 'sync_notice_labels.dart';
import 'sync_pairing_screen.dart';
import 'sync_support_codes.dart';

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

  /// The conflict count, re-read when a pass ends or the choice closes.
  Future<int>? _conflictCount;
  Object? _conflictCountFor;
  int _conflictGeneration = 0;

  Future<int> _conflictsFor(SyncController controller) {
    final key = (
      controller.running,
      controller.lastResult,
      _conflictGeneration,
    );
    if (_conflictCount == null || key != _conflictCountFor) {
      _conflictCountFor = key;
      _conflictCount = syncConflictCount(RepositoriesScope.of(context));
    }
    return _conflictCount!;
  }

  Future<void> _openConflicts() async {
    await showSyncConflictSheet(context);
    if (mounted) setState(() => _conflictGeneration++);
  }

  bool _replacementDialogShowing = false;

  /// Whether a confirmation that actually reached the coordinator is the most
  /// recent thing this surface did.
  ///
  /// Armed before the call rather than after it, because the controller
  /// notifies from its own `finally` and re-shows the dialog before an awaited
  /// result comes back — a flag written afterwards would arrive too late for
  /// the dialog it is meant to explain. Disarmed again when the §6.12 gate
  /// deferred the attempt: a deferral runs no pass, so leaving it armed would
  /// let [SyncController.lastResult] — still the pass that raised the dialog —
  /// be read as this confirmation's outcome.
  ///
  /// It only ever *qualifies* that result, so a failure from some earlier,
  /// unrelated pass can never be reported as this dialog's.
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
            // Every attempted confirmation that did not *complete* leaves the
            // decision pending and brings this dialog back, and they are
            // indistinguishable to the user — a tap that did nothing. A plain
            // `failed` is only one of them: the fresh attach's continuation
            // can have its manifest `PUT` answered `409` and end at
            // `staleEpoch`, and the store this device just created or adopted
            // can disappear again before the continuation reads it, ending at
            // `replacementRequired`. Testing for `failed` alone left exactly
            // those races unexplained — the same defect this line exists to
            // fix, one layer in.
            //
            // `running` excludes the notification the controller sends when it
            // *takes* the pass in flight: `lastResult` is still the pass that
            // raised this dialog at that point, and reporting it would call
            // the attempt failed while it is still running.
            final result = controller.lastResult;
            final lastAttemptFailed =
                _replacementConfirmAttempted &&
                !controller.running &&
                result != null &&
                result.status != SyncPassStatus.completed;
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
    // Armed before the call and disarmed again if the gate stopped it. The
    // controller notifies from inside the attempt, so a flag set afterwards
    // would arrive too late; but a suppressed attempt ran no pass, so leaving
    // it armed would let a later notification report the *previous* pass's
    // outcome as this confirmation's. A deferral is explained by the routing
    // message below, never by the failure line.
    _replacementConfirmAttempted = true;
    final outcome = await controller.confirmReplacement();
    if (!mounted) return;
    if (outcome != SyncGateOutcome.ran) _replacementConfirmAttempted = false;
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
  /// the copy is the moment the store's address leaves this app.
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

  /// Copies a Device Sync problem's support code ([syncPassSupportCode] and
  /// its siblings) for the user to paste into a request for help. Only the
  /// code: it carries no phrase, title or identifier, and nothing is sent.
  Future<void> _copySupportCode(String code) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger?.showSnackBar(
      SnackBar(
        key: const ValueKey('sync-details-copied'),
        content: Text(l10n.settingsSyncDetailsCopied),
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
    final repositories = RepositoriesScope.of(context);
    final before = await syncConflictCount(repositories);
    final outcome = await controller.syncNow();
    final message = _gateMessage(l10n, outcome);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    // A manual pass that found new conflicts opens the choice, as the
    // toolbar button does, unless the user has left this page meanwhile.
    if (outcome != SyncGateOutcome.ran || !mounted) return;
    final after = await syncConflictCount(repositories);
    if (!mounted || after <= before) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) await _openConflicts();
  }

  /// Detach forgets the phrase, and is reversible only by re-entering it, so
  /// it is confirmed first and says what it does and does not touch —
  /// including the one thing it may send: removing this device's own entry
  /// from the store when the other devices already have everything from it
  /// (`SyncController.detach`).
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
                final problem = _problem(controller);
                final failureText = problem == null
                    ? null
                    : syncPassProblemText(l10n, problem.status);
                // A transient failure clears by itself and is retried by
                // itself (spec §6.12), so it is a calm status rather than a
                // problem: no error colour, no reason or advice, and nothing
                // to copy. Its Details line stays, small, for anyone who
                // wants it.
                final transient = problem?.failure?.cause.isTransient ?? false;
                final needsYou = failureText != null && !transient;
                final lastSuccess = controller.lastSuccessAt;
                // Only a `failed` pass has a structured cause; the other
                // failure lines are already explanations in their own right.
                final failure = problem?.failure;
                final details = failure == null
                    ? null
                    : syncFailureDetails(l10n, failure);
                final subtitleLines = [
                  if (failure != null && !transient)
                    Text(
                      syncFailureExplanation(
                        l10n,
                        failure,
                        customServer: syncUsesCustomServer(controller.endpoint),
                      ),
                      key: const ValueKey('sync-status-failure-explanation'),
                    ),
                  if (failureText != null && lastSuccess != null)
                    Text(
                      l10n.settingsSyncStatusLastSynced(
                        _formatWhen(tileContext, lastSuccess),
                      ),
                      key: const ValueKey('sync-status-last-success'),
                    ),
                  if (details != null)
                    Text(
                      details,
                      key: const ValueKey('sync-status-failure-details'),
                      style: theme.textTheme.bodySmall,
                    ),
                ];
                final supportCode = needsYou
                    ? syncPassSupportCode(problem!)
                    : null;
                return ListTile(
                  key: const ValueKey('sync-status'),
                  leading: Icon(
                    needsYou ? Icons.error_outline : Icons.info_outline,
                    key: ValueKey(
                      needsYou ? 'sync-status-needs-you' : 'sync-status-calm',
                    ),
                    color: needsYou ? theme.colorScheme.error : null,
                  ),
                  title: Text(
                    transient
                        ? l10n.settingsSyncStatusWaiting
                        : failureText ?? _statusText(tileContext, controller),
                  ),
                  subtitle: subtitleLines.isEmpty
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (i, line) in subtitleLines.indexed)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: i == 0 ? 0 : AppSpacing.xxs,
                                ),
                                child: line,
                              ),
                          ],
                        ),
                  trailing: !controller.paired
                      ? FilledButton(
                          key: const ValueKey('sync-connect'),
                          onPressed: () => showSyncPairingScreen(
                            tileContext,
                            backupSaver: widget.backupSaver,
                          ),
                          child: Text(l10n.settingsSyncConnectTitle),
                        )
                      : supportCode == null
                      ? null
                      : _CopyDetailsButton(
                          key: const ValueKey('sync-status-copy-details'),
                          onPressed: () => _copySupportCode(supportCode),
                        ),
                );
              },
            ),
            // Spec §5.2 echoes the store's limits "so a client can warn before
            // hitting them rather than discovering a `507`". Needs you, so it
            // offers the one thing this device can do about it — stop
            // uploading imported dances nothing uses — only while that is
            // still off; never a wipe (spec §5.3).
            if (controller.quotaNearlyFull)
              ListTile(
                key: const ValueKey('sync-quota-warning'),
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(l10n.settingsSyncQuotaNearlyFull),
                subtitle: controller.excludeImports
                    ? null
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey('sync-quota-exclude-imports'),
                          onPressed: () => controller.setExcludeImports(true),
                          child: Text(l10n.settingsSyncQuotaExcludeImports),
                        ),
                      ),
                trailing: _CopyDetailsButton(
                  key: const ValueKey('sync-quota-copy-details'),
                  onPressed: () => _copySupportCode(
                    syncQuotaSupportCode(controller.storeQuota!),
                  ),
                ),
              ),
            // The conditions the last pass to raise any had to report (spec
            // §2 *report*): non-blocking and with no dismissal. They sit
            // beside the status rather than in it because a pass can complete
            // successfully and still have something to say. A per-device
            // group is one tile per device, each naming it by the tag the
            // *Other devices* list shows it under. A needs-you group adds
            // Copy details, which copies a code and clears nothing.
            for (final group in syncNoticeGroups(controller.notices))
              if (syncNoticeIsPerDevice(group))
                for (final peerId in syncNoticePeerIds(
                  group,
                  controller.notices,
                ))
                  _SyncNoticeTile(
                    key: ValueKey((group, peerId)),
                    group: group,
                    reports: [
                      for (final report in controller.notices)
                        if (report.peerId == peerId) report,
                    ],
                    peerTag: syncDeviceTags({
                      ...controller.peerSummaries.keys,
                      ...syncNoticePeerIds(group, controller.notices),
                    })[peerId],
                    onCopyDetails: syncNoticeNeedsYou(group)
                        ? () => _copySupportCode(
                            syncNoticeSupportCode(group, [
                              for (final report in controller.notices)
                                if (report.peerId == peerId) report,
                            ]),
                          )
                        : null,
                  )
              else
                _SyncNoticeTile(
                  key: ValueKey(group),
                  group: group,
                  reports: controller.notices,
                  onCopyDetails: syncNoticeNeedsYou(group)
                      ? () => _copySupportCode(
                          syncNoticeSupportCode(group, controller.notices),
                        )
                      : null,
                ),
            // What this device merged when it last fresh-attached, for the rest
            // of this app session — the latch is in memory, so it does not
            // outlive a restart. ADR-004 makes the count the mitigation
            // for a merge the user is never shown, and three of the four
            // fresh-attach paths — a confirmed replacement, a stale-epoch
            // auto-join, and a pairing pass the §6.12 gate deferred — have no
            // dialog of their own to report it in. This tile is the surface
            // they share.
            if (controller.mergedDuplicates > 0)
              ListTile(
                key: const ValueKey('sync-merged-duplicates'),
                leading: Icon(
                  Icons.merge_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                title: Text(
                  l10n.settingsSyncMergedDuplicates(
                    controller.mergedDuplicates,
                  ),
                ),
              ),
            // ADR-004 requires the endpoint shown un-abstracted as a URL in
            // Settings, so pointing at your own server is a visible
            // first-class option rather than a hidden one. Shown whichever
            // server it is: a user on the default one previously saw no
            // address anywhere on this section, which is the abstraction that
            // clause forbids. A non-default endpoint keeps its own prominent
            // treatment (spec §8).
            if (controller.paired && controller.endpoint != null)
              isDefaultSyncEndpoint(controller.endpoint!)
                  ? ListTile(
                      key: const ValueKey('sync-endpoint'),
                      leading: Icon(
                        Icons.dns_outlined,
                        color: theme.colorScheme.secondary,
                      ),
                      title: Text(
                        l10n.settingsSyncEndpointStatus(
                          controller.endpoint!.toString(),
                        ),
                      ),
                    )
                  : ListTile(
                      key: const ValueKey('sync-custom-endpoint'),
                      leading: Icon(
                        Icons.dns_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        l10n.settingsSyncCustomEndpointStatus(
                          controller.endpoint!.toString(),
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
              FutureBuilder<int>(
                future: _conflictsFor(controller),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return ListTile(
                    key: const ValueKey('sync-conflicts'),
                    leading: Icon(
                      Icons.call_split,
                      color: theme.colorScheme.tertiary,
                    ),
                    title: Text(l10n.syncConflictTitle),
                    subtitle: Text(l10n.settingsSyncConflictsSubtitle(count)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openConflicts,
                  );
                },
              ),
            if (controller.paired)
              ListTile(
                key: const ValueKey('sync-review-button'),
                leading: const Icon(Icons.rule),
                title: Text(l10n.syncReviewSettingsTitle),
                subtitle: Text(l10n.syncReviewSettingsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SyncReviewScreen(),
                  ),
                ),
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
            if (controller.paired)
              ListTile(
                key: const ValueKey('sync-devices'),
                leading: const Icon(Icons.devices_other_outlined),
                title: Text(l10n.settingsSyncDevicesTitle),
                subtitle: Text(l10n.settingsSyncDevicesSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !controller.running,
                onTap: controller.running
                    ? null
                    : () => showSyncDevicesScreen(context),
              ),
            if (controller.paired)
              ListTile(
                key: const ValueKey('sync-wipe'),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(l10n.settingsSyncWipeTitle),
                subtitle: Text(l10n.settingsSyncWipeSubtitle),
                enabled: !controller.running,
                onTap: controller.running
                    ? null
                    : () => confirmAndWipeStore(context, controller),
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

  /// The last completed trigger attempt when it was not a success, or null
  /// when the last attempt succeeded, nothing has run yet in this session, or
  /// a pass is currently running (the syncing status on [_statusText] takes
  /// priority over a stale failure from an earlier pass). Which line each
  /// status gets is [syncPassProblemText]'s decision.
  SyncPassResult? _problem(SyncController controller) {
    if (controller.running || !controller.paired) return null;
    final result = controller.lastResult;
    if (result == null) return null;
    return syncPassProblemText(AppLocalizations.of(context), result.status) ==
            null
        ? null
        : result;
  }
}

/// One notice group, with the records it is about.
///
/// A notice that says "some records" and asks the user to edit "one of them"
/// gives them nothing to look for, so the tile lists the records, looked up
/// here because a report carries only a kind and an id. Only the kinds
/// [lookupSyncNoticeRecordName] looks up are named, and only those can be said
/// to be absent from this device; every other kind is listed by kind alone.
/// Nothing is left out, so the count stays honest.
class _SyncNoticeTile extends StatefulWidget {
  const _SyncNoticeTile({
    super.key,
    required this.group,
    required this.reports,
    this.peerTag,
    this.onCopyDetails,
  });

  final SyncNoticeGroup group;
  final List<SyncReport> reports;

  /// The tag of the one device a per-device notice is about; null otherwise.
  final String? peerTag;

  /// Copies the notice's support code; set for a needs-you group only.
  final VoidCallback? onCopyDetails;

  @override
  State<_SyncNoticeTile> createState() => _SyncNoticeTileState();
}

class _SyncNoticeTileState extends State<_SyncNoticeTile> {
  List<SyncNoticeRecord> _records = const [];
  Future<List<(SyncNoticeRecord, SyncNoticeRecordName)>>? _names;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_SyncNoticeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reports, widget.reports) ||
        oldWidget.group != widget.group) {
      _resolve();
    }
  }

  void _resolve() {
    final records = syncNoticeRecords(widget.group, widget.reports);
    // The controller notifies at the start and end of every pass, and each
    // notification rebuilds this tile; looking the names up again when the
    // records have not changed would flash the line away and back.
    if (_names != null && listEquals(records, _records)) return;
    _records = records;
    // Optional rather than required: a host without a repository scope still
    // gets the notice and its record kinds, just not their names.
    final repositories = context
        .getInheritedWidgetOfExactType<RepositoriesScope>()
        ?.repositories;
    final shown = records.take(kSyncNoticeNamedLimit).toList();
    _names = Future(() async {
      final named = <(SyncNoticeRecord, SyncNoticeRecordName)>[];
      for (final record in shown) {
        SyncNoticeRecordName name = const SyncNoticeRecordUnnamed();
        if (repositories != null) {
          try {
            name = await lookupSyncNoticeRecordName(repositories, record);
          } on Object catch (e, st) {
            // The notice itself is what matters; a lookup that fails degrades
            // this record to its kind rather than hiding the whole line.
            logCaughtErrorTypeOnly(e, st, source: 'sync_notice_tile.lookup');
          }
        }
        named.add((record, name));
      }
      return named;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final perDevice = syncNoticeIsPerDevice(widget.group);
    // A per-device notice already names its one device in its text.
    final peers = perDevice
        ? 0
        : syncNoticePeerCount(widget.group, widget.reports);
    final total = _records.length;
    final needsYou = syncNoticeNeedsYou(widget.group);
    final peerTag = widget.peerTag;
    final keyName = perDevice && peerTag != null
        ? '${widget.group.name}-$peerTag'
        : widget.group.name;
    final text = Text(
      syncNoticeText(
        l10n,
        widget.group,
        recordCount: syncNoticeCountedRecords(widget.group, widget.reports),
        device: perDevice ? (tag: peerTag ?? '', count: total) : null,
      ),
    );
    return ListTile(
      key: ValueKey('sync-notice-$keyName'),
      // Needs-you is carried by the icon *and* a text label, never by colour
      // alone.
      leading: needsYou
          ? Icon(Icons.warning_amber_outlined, color: theme.colorScheme.error)
          : Icon(Icons.info_outline, color: theme.colorScheme.tertiary),
      title: needsYou
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsSyncNoticeNeedsYou,
                  key: ValueKey('sync-notice-$keyName-needs-you'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                text,
              ],
            )
          : text,
      trailing: switch (widget.onCopyDetails) {
        final onCopy? => _CopyDetailsButton(
          key: ValueKey('sync-notice-$keyName-copy-details'),
          onPressed: onCopy,
        ),
        null => null,
      },
      subtitle: total == 0 && peers == 0 && !(needsYou && perDevice)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (total > 0)
                  FutureBuilder(
                    future: _names,
                    builder: (context, snapshot) {
                      final named = snapshot.data;
                      // Until the names arrive, the kinds alone still say
                      // what to look for.
                      final shown =
                          named ??
                          [
                            for (final record in _records.take(
                              kSyncNoticeNamedLimit,
                            ))
                              (record, const SyncNoticeRecordUnnamed()),
                          ];
                      return Text(
                        syncNoticeAffectedText(l10n, shown, total),
                        key: ValueKey(
                          'sync-notice-${widget.group.name}-records',
                        ),
                      );
                    },
                  ),
                if (peers > 0)
                  Text(
                    l10n.settingsSyncNoticeFromDevices(peers),
                    key: ValueKey('sync-notice-${widget.group.name}-peers'),
                  ),
                // A per-device notice's one action: the list where that
                // device is shown by the same tag, with what is waiting for
                // it. A newer-version notice's remedy is updating this app,
                // which nothing on this screen does, so it has none here.
                if (needsYou && perDevice)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: ValueKey('sync-notice-$keyName-action'),
                      onPressed: () => showSyncDevicesScreen(context),
                      child: Text(l10n.settingsSyncNoticeSeeDevices),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The "Copy details" action on a needs-you Device Sync item.
class _CopyDetailsButton extends StatelessWidget {
  const _CopyDetailsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.content_copy_outlined),
    tooltip: AppLocalizations.of(context).settingsSyncCopyDetails,
    onPressed: onPressed,
  );
}

/// The sync phrase this device is attached to, on the status surface so the
/// user can enter it on another device without having written it down at
/// pairing (spec §6.14 item 2: it cannot be recovered from the server).
///
/// Masked until the user asks for it. Knowing the address is all it takes to
/// reach the store, and there is no revoking it afterwards, so a settings pane
/// that displays the phrase unprompted shares the store with everyone who can
/// see the screen — a screenshot sent to support, a shared display, someone
/// standing behind the caller at a dance. Copying works while it is masked,
/// because the common case is moving it to another device and that never needs
/// it on screen. The reveal is per-visit state and is deliberately not
/// persisted.
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
