import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/calling_history_caller_filter.dart';
import '../data/confirm_before_delete_scope.dart';
import '../data/default_program_caller_scope.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../theme/app_motion.dart';
import '../theme/destructive_button_style.dart';

/// The app's two delete confirmations, one rule between them:
///
/// - **A delete Undo can reverse** goes through [confirmDeleteIfEnabled] (or
///   one of its variants below) and then offers Undo. It asks only when the
///   user has turned on "Confirm before delete" ([ConfirmBeforeDeleteScope],
///   off by default; ROADMAP G.7): the accessibility baseline prefers Undo to
///   a dialog, and allows an opt-in confirmation in front of it.
/// - **A delete nothing can reverse** goes through [confirmPermanentDelete],
///   which always asks, whatever that setting says, and says "This can't be
///   undone."
///
/// Swipe-to-delete is the one exception to the first rule: a swipe reveals a
/// Delete button that takes a second tap, and that second tap is the
/// confirmation, so swipes do not ask again.
///
/// [confirmDeleteIfEnabled] returns `true` immediately when the setting is
/// off, so the caller proceeds straight to its delete and Undo. When it is on,
/// it shows an [AlertDialog] (Cancel / Delete) and returns whether the user
/// confirmed.
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
/// that names the count instead of a title, and how many of them ([notShown])
/// the current search hides. One rule for every delete (N4-4 = a), so a bulk
/// delete with the setting off asks nothing either.
Future<bool> confirmDeleteDancesIfEnabled(
  BuildContext context, {
  required int count,
  required int notShown,
}) => _confirmDeleteIfEnabled(
  context,
  (l10n) => notShown == 0
      ? l10n.confirmDeleteDancesBody(count)
      : l10n.confirmDeleteDancesNotShownBody(count, notShown),
);

/// [confirmDeleteIfEnabled] for a program, whose body also says how many
/// dances lose it from their calling history (LIFE-6 = a, maintainer decision
/// 2026-10-30). Deleting a program takes its slots out of the derived calling
/// history (`programs.deleted_at IS NULL` in every history query), and the
/// plain "will be deleted" body never said so.
///
/// The count is [ProgramRepository.danceCountLosingHistory] under the history
/// settings in force right now (performed-only, event date, caller), so it is
/// the number of dances whose history lists this program. It is read only when
/// the dialog will actually show — with the setting off this returns `true`
/// without a query — and a body with no dances to name (zero, or a failed
/// read) falls back to the plain one.
///
/// Limitation: the dialog is opt-in, and the programs-list swipe skips it, so
/// the warning reaches only callers who turned "Confirm before delete" on.
Future<bool> confirmDeleteProgramIfEnabled(
  BuildContext context, {
  required String itemLabel,
  required String programId,
  required CompendiumRepositories repositories,
}) async {
  if (!ConfirmBeforeDeleteScope.of(context)) return true;

  // Scopes are read before the first await, as the history screens do.
  final performedOnly = RequirePerformedForHistoryScope.of(context);
  final requireEventDate = RequireEventDateForHistoryScope.of(context);
  final trackAllCallers = TrackHistoryForAllCallersScope.of(context);
  final defaultCaller = DefaultProgramCallerScope.maybeOf(context);

  var losing = 0;
  try {
    final callerFilter = await resolveCallingHistoryCallerFilter(
      repositories.settings,
      trackAllCallers: trackAllCallers,
      defaultCaller: defaultCaller,
    );
    losing = await repositories.programs.danceCountLosingHistory(
      programId,
      performedOnly: performedOnly,
      requireEventDate: requireEventDate,
      callerFilter: callerFilter,
    );
  } catch (_) {
    // diagnostics: silent — the count only enriches the confirm; a failed read
    // shows the plain body rather than blocking a delete the user asked for.
  }
  if (!context.mounted) return false;
  return _confirmDeleteIfEnabled(
    context,
    (l10n) => losing > 0
        ? l10n.confirmDeleteProgramHistoryBody(itemLabel, losing)
        : l10n.confirmDeleteBody(itemLabel),
  );
}

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
    animationStyle: AppMotion.styleFor(context),
  );
  return confirmed ?? false;
}

/// Asks before a delete that cannot be undone: there is no Undo, and nothing
/// in Recently deleted to bring it back. Always shown, whatever "Confirm
/// before delete" says: that setting adds a question in front of an Undo, and
/// here there is no Undo to fall back on.
///
/// [body] says what will be deleted (and what else changes with it); the
/// dialog adds "This can't be undone." after it, so every irreversible delete
/// says so in the same words. The confirm button is a destructive
/// [FilledButton] labelled [confirmLabel], "Delete" unless given. Returns
/// whether the user confirmed.
Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
  Key confirmKey = const ValueKey('confirm-permanent-delete'),
  Key? bodyKey,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('confirm-permanent-delete-dialog'),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, key: bodyKey),
            const SizedBox(height: 12),
            Text(
              l10n.commonCantBeUndone,
              key: const ValueKey('confirm-permanent-delete-irreversible'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('confirm-permanent-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: destructiveFilledButtonStyle(Theme.of(ctx).colorScheme),
          key: confirmKey,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? l10n.commonDelete),
        ),
      ],
    ),
    animationStyle: AppMotion.styleFor(context),
  );
  return confirmed ?? false;
}
