import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/settings_keys.dart'
    show kConfirmPerformExitDefault, kConfirmPerformExitKey;

/// Shared pieces of leaving Perform, used by both [PerformDanceScreen] and
/// [PerformProgramScreen] so the two exits stay identical (issues #434, #612).

/// Asks "Exit Perform?" and resolves to whether the caller confirmed.
///
/// [stageContext] must be a context *below* the screen's [PerformStageTheme]
/// (the screens pass their Scaffold's context): [showDialog] captures the
/// themes of the context it is given, so a context above the stage theme drew
/// the dialog in the app theme — a near-white panel over the dark stage in
/// light mode. [body] is the screen's own explanation of what leaving keeps.
Future<bool> showPerformExitDialog(
  BuildContext stageContext, {
  required String body,
}) async {
  final l10n = AppLocalizations.of(stageContext);
  final confirmed = await showDialog<bool>(
    context: stageContext,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('perform-exit-dialog'),
      title: Text(l10n.performExitTitle),
      content: Text(body),
      actions: [
        TextButton(
          key: const ValueKey('perform-exit-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.performExitCancel),
        ),
        FilledButton(
          key: const ValueKey('perform-exit-confirm'),
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.performExitConfirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Reads the "Confirm before leaving Perform" setting for a Perform screen.
/// Resolves to [kConfirmPerformExitDefault] (ask) when the
/// value is unset, not a bool, or unreadable, so a failed read never removes
/// the guard.
Future<bool> loadConfirmPerformExit(BuildContext context) async {
  try {
    final value = await RepositoriesScope.of(
      context,
    ).settings.get(kConfirmPerformExitKey);
    return value is bool ? value : kConfirmPerformExitDefault;
  } catch (_) {
    // diagnostics: silent — exit-confirm pref read failed; keep asking.
    return kConfirmPerformExitDefault;
  }
}
