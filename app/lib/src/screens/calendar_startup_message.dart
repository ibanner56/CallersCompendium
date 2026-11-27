import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/calendar_startup.dart';
import '../utils/l10n_joins.dart';
import '../utils/undo_snack_bar.dart';

/// Runs the startup calendar import at most once per launch (#2353), however
/// many times the bootstrap tail is reached (a failed reset re-runs it).
class CalendarStartupGate {
  bool _ran = false;

  /// Calls [run] the first time only.
  Future<void> runOnce(Future<void> Function() run) async {
    if (_ran) return;
    _ran = true;
    await run();
  }
}

/// Shows what a startup run found (#2353), or nothing: a run that was off,
/// found nothing to say, or failed shows no message, no banner and no dialog.
/// A failure is recorded for Settings ▸ Program ▸ Calendar only.
void presentCalendarStartupOutcome({
  required CalendarStartupOutcome outcome,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required bool accessibleNavigation,
  required CompendiumRepositories repositories,
  required VoidCallback openReview,
  required void Function(String programId) openProgram,
}) {
  if (outcome is! CalendarStartupFound) return;
  showCalendarStartupMessage(
    messenger: messenger,
    l10n: l10n,
    outcome: outcome,
    accessibleNavigation: accessibleNavigation,
    repositories: repositories,
    openReview: openReview,
    openProgram: openProgram,
  );
}

/// The dismissible message a startup calendar run shows (#2353).
///
/// * **Report new events:** "3 new events in your calendar", with **Review**,
///   which opens the import preview with the fetched feed. Nothing is created
///   until the caller presses Import there.
/// * **Add them as drafts:** "3 draft programs added from your calendar",
///   shown as the app's Undo prompt ([showUndoSnackBar]: its timeout, its
///   accessibility handling) with **Undo**, and **Show** beside the message.
///   Undo moves only the drafts nobody has touched since to Recently
///   deleted: one the caller has already started filling in is kept. Not a
///   hard delete, because the import skips events whose programs are in
///   Recently deleted, so the next start does not add them back (the
///   maintainer's choice).
///
/// Either way, upstream changes and cancellations (#2354) are only counted
/// ("1 change needs you") with **Review**; the startup run never applies
/// them.
void showCalendarStartupMessage({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required CalendarStartupFound outcome,
  required bool accessibleNavigation,
  required CompendiumRepositories repositories,
  required VoidCallback openReview,
  required void Function(String programId) openProgram,
}) {
  final added = outcome.addedIds;
  final parts = [
    if (added.isNotEmpty)
      l10n.calendarImportCommitted(added.length)
    else if (outcome.newEvents > 0)
      l10n.calendarStartupNewEvents(outcome.newEvents),
    if (outcome.changes > 0) l10n.calendarStartupChanges(outcome.changes),
  ];
  final message = joinSentences(l10n, parts);
  if (added.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('calendar-startup-message'),
        content: Text(message),
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          key: const ValueKey('calendar-startup-review-action'),
          label: l10n.calendarStartupReview,
          onPressed: openReview,
        ),
      ),
    );
    return;
  }
  showUndoSnackBar(
    messenger,
    key: const ValueKey('calendar-startup-message'),
    actionKey: const ValueKey('calendar-startup-undo'),
    message: message,
    undoLabel: l10n.commonUndo,
    undoFailedMessage: l10n.commonUndoFailed,
    accessibleNavigation: accessibleNavigation,
    onUndo: () async {
      final untouched = [
        for (final id in added)
          if (await repositories.programs.getById(id) case final p?
              when p.isUntouchedCalendarDraft)
            id,
      ];
      final at = clock.now().toUtc();
      // One transaction: Undo moves all of them or none.
      await repositories.transaction(() async {
        for (final id in untouched) {
          await repositories.programs.softDelete(id, at: at);
        }
      });
    },
    extraActions: [
      TextButton(
        key: const ValueKey('calendar-startup-show'),
        onPressed: () {
          messenger.hideCurrentSnackBar();
          openProgram(added.first);
        },
        child: Text(l10n.calendarStartupShow),
      ),
      if (outcome.changes > 0)
        TextButton(
          key: const ValueKey('calendar-startup-review'),
          onPressed: () {
            messenger.hideCurrentSnackBar();
            openReview();
          },
          child: Text(l10n.calendarStartupReview),
        ),
    ],
  );
}
