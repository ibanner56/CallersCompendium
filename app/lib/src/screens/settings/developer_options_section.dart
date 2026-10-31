// Part of the Settings screen: the Developer options group of the Experimental
// pane.
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/sync_writer_lifecycle_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_scope.dart';
import '../../theme/destructive_button_style.dart';
import '../../widgets/collapsible_section.dart';

/// Tools for development and support, folded away by default.
///
/// Today it holds one action: resetting the database to a wiped, clean install.
class DeveloperOptionsSection extends StatefulWidget {
  const DeveloperOptionsSection({super.key});

  @override
  State<DeveloperOptionsSection> createState() =>
      _DeveloperOptionsSectionState();
}

class _DeveloperOptionsSectionState extends State<DeveloperOptionsSection> {
  /// Guards against a second tap while the sync store is being left or the
  /// database is being deleted; both can take a network round trip.
  bool _resetting = false;

  Future<void> _confirmReset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetDatabaseDialog(),
    );
    if (confirmed != true || !mounted || _resetting) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = SyncScope.maybeOf(context);
    final reset = SyncWriterLifecycleScope.maybeOf(
      context,
    )?.resetToCleanInstall;
    if (reset == null) return;

    setState(() => _resetting = true);
    try {
      // Leave the sync store before the wipe: once the database is gone so is
      // the sync phrase, and with it any way to remove this device's manifest,
      // which would otherwise stay listed under every other device for good.
      // A failure stops here with nothing deleted.
      if (controller != null && controller.paired) {
        final outcome = await controller.leaveStoreForReset();
        if (outcome == SyncAdminOutcome.failed) {
          messenger?.showSnackBar(
            SnackBar(content: Text(l10n.settingsDeveloperResetLeaveFailed)),
          );
          return;
        }
      }
      if (!await reset()) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.settingsDeveloperResetFailed)),
        );
      }
    } on Object catch (e, st) {
      logCaughtErrorTypeOnly(e, st, source: 'developer_options.reset');
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.settingsDeveloperResetFailed)),
      );
    } finally {
      // After a successful reset the app rebuilds around this widget, so it is
      // normally gone by now.
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return CollapsibleSection(
      sectionKey: const ValueKey('developer-options-section'),
      title: l10n.settingsDeveloperOptionsHeader,
      expanded: false,
      child: ListTile(
        key: const ValueKey('developer-reset-database'),
        enabled: !_resetting,
        leading: Icon(
          Icons.delete_forever_outlined,
          color: _resetting ? null : theme.colorScheme.error,
        ),
        title: Text(l10n.settingsDeveloperResetTitle),
        subtitle: Text(l10n.settingsDeveloperResetSubtitle),
        isThreeLine: true,
        onTap: _resetting ? null : _confirmReset,
      ),
    );
  }
}

/// The confirmation for the reset. The destructive button stays disabled until
/// the user ticks that they understand it cannot be undone and have taken a
/// backup if they want one.
class _ResetDatabaseDialog extends StatefulWidget {
  const _ResetDatabaseDialog();

  @override
  State<_ResetDatabaseDialog> createState() => _ResetDatabaseDialogState();
}

class _ResetDatabaseDialogState extends State<_ResetDatabaseDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final syncPaired = SyncScope.maybeOf(context)?.paired ?? false;
    return AlertDialog(
      key: const ValueKey('developer-reset-dialog'),
      icon: const Icon(Icons.warning_amber_outlined),
      title: Text(l10n.settingsDeveloperResetConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsDeveloperResetConfirmBody),
            if (syncPaired) ...[
              const SizedBox(height: 12),
              Text(l10n.settingsDeveloperResetConfirmSyncNote),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('developer-reset-understood'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _understood,
              onChanged: (value) =>
                  setState(() => _understood = value ?? false),
              title: Text(l10n.settingsDeveloperResetConfirmCheckbox),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('developer-reset-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('developer-reset-confirm'),
          style: destructiveFilledButtonStyle(Theme.of(context).colorScheme),
          onPressed: _understood ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.settingsDeveloperResetConfirmAction),
        ),
      ],
    );
  }
}
