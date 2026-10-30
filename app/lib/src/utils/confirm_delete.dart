import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/confirm_before_delete_scope.dart';
import '../theme/destructive_button_style.dart';

/// Shared gate for destructive delete actions (ROADMAP G.7 "Confirm before
/// delete").
///
/// When the [ConfirmBeforeDeleteScope] setting is OFF (the default) this returns
/// `true` immediately, so callers proceed straight to the existing soft-delete +
/// Undo-snackbar flow — exactly today's behavior. When the setting is ON it
/// shows an [AlertDialog] (Cancel / Delete) and returns whether the user
/// confirmed. Soft-delete + Undo remain intact either way; this dialog only
/// layers an explicit confirmation in front, per the accessibility baseline
/// (which prefers undo/soft-delete but allows opt-in confirmation).
///
/// [itemLabel] is a short human name of the thing being deleted (e.g. a dance or
/// program title) used in the dialog body.
Future<bool> confirmDeleteIfEnabled(
  BuildContext context, {
  required String itemLabel,
}) => _confirmDeleteIfEnabled(
  context,
  (l10n) => l10n.confirmDeleteBody(itemLabel),
);

/// [confirmDeleteIfEnabled] for [count] dances deleted at once from
/// Collection's selection mode: the same setting, dialog and keys, with a body
/// that names the count instead of a title. One rule for every delete (N4-4 =
/// a), so a bulk delete with the setting off asks nothing either.
Future<bool> confirmDeleteDancesIfEnabled(
  BuildContext context, {
  required int count,
}) => _confirmDeleteIfEnabled(
  context,
  (l10n) => l10n.confirmDeleteDancesBody(count),
);

Future<bool> _confirmDeleteIfEnabled(
  BuildContext context,
  String Function(AppLocalizations l10n) body,
) async {
  if (!ConfirmBeforeDeleteScope.of(context)) return true;

  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('confirm-delete-dialog'),
      title: Text(l10n.confirmDeleteTitle),
      content: Text(body(l10n)),
      actions: [
        TextButton(
          key: const ValueKey('confirm-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: destructiveFilledButtonStyle(Theme.of(ctx).colorScheme),
          key: const ValueKey('confirm-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
