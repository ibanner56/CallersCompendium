import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/online_search.dart';
import '../data/online_search_labels.dart';
import '../data/program_import_rollback.dart';
import '../diagnostics/error_log.dart';
import '../utils/undo_snack_bar.dart';

/// Reports a finished single-dance online import [result] on [messenger], with
/// **Undo** whenever the import wrote something (INTAKE-5).
///
/// Every surface that imports one online dance and confirms it with a snackbar
/// calls this, so the wording and the Undo cannot drift between them: the
/// online preview in the Collection list ([DanceListScreen]) and the split
/// view ([CollectionShell]), and a dance link opened from outside the app
/// (`main.dart`). The collection picker reports through its program slot
/// instead, and has no snackbar.
///
/// Undo reverts [OnlineImportResult.session] through [ProgramImportRollback],
/// which runs the same exact [ImportPipeline.undo] the import review screen
/// offers: a new dance is removed, a dance the user chose to replace ("Same
/// dance") gets its previous version back, and an author the import created is
/// removed again. The ledger is used, rather than the pipeline directly, for
/// its one extra guard: a new dance that a program now links is kept. The Undo
/// stays on screen for as long as assistive navigation needs, long enough to
/// add the dance to a program, and removing it then would empty that slot. A
/// result that wrote nothing ([OnlineImportKind.alreadyInCollection]) gets the
/// plain message with no Undo.
///
/// The dance can be edited while the Undo is on offer: the import lands the
/// user on its page, and under assistive navigation the prompt stays until it
/// is dismissed. Undo then leaves it alone and says so, since removing it, or
/// restoring the replaced version, would throw those edits away. An edit is
/// any change to the dance's `updatedAt` since the import.
///
/// [onDanceRemoved] runs after an Undo that removed the dance the import
/// created, so the caller can stop showing it. It is not called when the Undo
/// restored a replaced dance, or kept a new one, since the dance still exists.
///
/// [accessibleNavigation] is captured by the caller before any async gap, as
/// [showUndoSnackBar] asks.
void showOnlineImportSnackBar(
  ScaffoldMessengerState messenger, {
  required AppLocalizations l10n,
  required OnlineImportResult result,
  required CompendiumRepositories repos,
  required bool accessibleNavigation,
  VoidCallback? onDanceRemoved,
}) {
  final message = onlineImportMessage(l10n, result);
  final session = result.session;
  if (result.kind != OnlineImportKind.created || session == null) {
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('online-import-snackbar'),
        content: Text(message),
      ),
    );
    return;
  }
  final danceId = result.danceId;
  final removesDance =
      danceId != null && session.insertedDanceIds.contains(danceId);
  // The dance as the import left it, read now, before the user can reach its
  // Edit button: Undo compares against it.
  final asImported = danceId == null
      ? null
      // A failed read only loses the guard, and Undo then runs as it would
      // have without it. The error is logged here, not left to escape
      // unawaited in the meantime.
      : repos.dances
            .getById(danceId)
            .then<Dance?>(
              (dance) => dance,
              onError: (Object error, StackTrace stackTrace) {
                logCaughtErrorTypeOnly(
                  error,
                  stackTrace,
                  source: 'showOnlineImportSnackBar.asImported',
                );
                return null;
              },
            );
  showUndoSnackBar(
    messenger,
    key: const ValueKey('online-import-snackbar'),
    actionKey: const ValueKey('online-import-undo'),
    message: message,
    undoLabel: l10n.commonUndo,
    undoFailedMessage: l10n.commonUndoFailed,
    accessibleNavigation: accessibleNavigation,
    onUndo: () async {
      final before = await asImported;
      final now = danceId == null ? null : await repos.dances.getById(danceId);
      if (before != null && now != null && now.updatedAt != before.updatedAt) {
        // Edited since the import: Undo would delete those edits along with
        // the dance, or write the pre-import version over them. Keep it, and
        // say so rather than appear to have undone it.
        if (!messenger.mounted) return;
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              key: const ValueKey('online-import-undo-kept'),
              content: Text(l10n.onlineImportUndoKeptChanged(now.title)),
            ),
          );
        return;
      }
      final rollback = ProgramImportRollback(repos);
      await rollback.record(session);
      await rollback.rollBack();
      if (removesDance && await repos.dances.getById(danceId) == null) {
        onDanceRemoved?.call();
      }
    },
  );
}
