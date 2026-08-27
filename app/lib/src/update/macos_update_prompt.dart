import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'update_controller.dart';

/// Asks whether a verified macOS update should be mounted and the app closed.
///
/// The caller invokes this only after [UpdateController] has reached
/// [AssistedDownloadStatus.awaitingMacosInstall], so declining preserves the
/// verified disk image for its later "Update and restart" action.
Future<void> promptForMacosUpdate(
  BuildContext context,
  UpdateController controller,
) async {
  if (!controller.isAwaitingMacosInstall) return;
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        key: const ValueKey('update-macos-ready-dialog'),
        title: Text(l10n.updateMacosReadyTitle),
        content: Text(l10n.updateMacosReadyBody),
        actions: [
          TextButton(
            key: const ValueKey('update-macos-not-now'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.updateMacosNotNow),
          ),
          FilledButton(
            key: const ValueKey('update-macos-update-now'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.updateMacosUpdateNow),
          ),
        ],
      );
    },
  );
  if (approved == true && context.mounted) {
    await controller.installPendingMacosUpdate();
  }
}
