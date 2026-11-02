import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/calling_history_caller_filter.dart';
import '../data/confirm_before_delete_scope.dart';
import '../data/default_program_caller_scope.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
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
  );
  return confirmed ?? false;
}
