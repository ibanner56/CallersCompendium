import 'package:flutter/material.dart';

import '../data/confirm_before_delete_scope.dart';

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
}) async {
  if (!ConfirmBeforeDeleteScope.of(context)) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('confirm-delete-dialog'),
      title: const Text('Delete?'),
      content: Text('“$itemLabel” will be deleted. You can undo this.'),
      actions: [
        TextButton(
          key: const ValueKey('confirm-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
