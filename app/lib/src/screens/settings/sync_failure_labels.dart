// Maps a structured sync failure onto the localized copy every Device Sync
// surface shows for it: the status line, the pairing form, the device list,
// and the toolbar button. One mapping, so the same failure reads the same
// wherever the user meets it.
import '../../../l10n/app_localizations.dart';
import '../../sync/sync_coordinator.dart' show SyncPassResult, SyncPassStatus;
import '../../sync/sync_failure.dart';

/// The status line for a pass that ended at [status] without succeeding, or
/// null for a status that needs no line.
///
/// The two missing-store outcomes are deliberately kept apart, as spec §6.2
/// and the pairing flow keep them apart: `replacementRequired` is a store
/// this device *had* used and that has since gone, so it may have expired
/// or been removed — never claimed as either, per §6.14 item 6 — and the
/// replacement dialog owns the decision; `firstTimeStoreRequired` is a
/// stored phrase no store has ever answered to, which is the mistyped or
/// never-created case, and saying "expired" there would explain a store
/// that never existed. A stale epoch needs no action: the next pass
/// fresh-attaches to the replaced store on its own.
String? syncPassProblemText(
  AppLocalizations l10n,
  SyncPassStatus status,
) => switch (status) {
  SyncPassStatus.failed => l10n.settingsSyncStatusFailed,
  SyncPassStatus.staleEpoch => l10n.settingsSyncStatusStaleStore,
  SyncPassStatus.replacementRequired => l10n.settingsSyncStatusStoreUnavailable,
  SyncPassStatus.firstTimeStoreRequired => l10n.settingsSyncStatusStoreNotFound,
  // Declining a replacement leaves sync configured but paused so a later
  // action can reconsider (spec §6.3 step 1, §6.14 item 6). Every automatic
  // trigger then answers `paused` without running a pass, so without this arm
  // the surface fell back to the last success — a date belonging to a store
  // that no longer exists. `declineReplacement` is the only thing that pauses
  // the coordinator, so naming the missing store here claims nothing the
  // pause does not already mean.
  SyncPassStatus.paused => l10n.settingsSyncStatusPaused,
  SyncPassStatus.completed ||
  SyncPassStatus.skippedUnconfigured ||
  SyncPassStatus.freshAttachRequired => null,
};

/// What to add, after a surface's own "it didn't finish" sentence, about a
/// pass that did not succeed; null when it succeeded or there is nothing to
/// add.
///
/// A `failed` pass is explained by its cause. One without a cause (a path
/// that never set one) gets null rather than "Last sync failed.", which would
/// only repeat the sentence it follows.
String? syncPassResultExplanation(
  AppLocalizations l10n,
  SyncPassResult result,
) {
  if (result.status == SyncPassStatus.failed) {
    final failure = result.failure;
    return failure == null ? null : syncFailureExplanation(l10n, failure);
  }
  return syncPassProblemText(l10n, result.status);
}

/// One sentence saying what went wrong.
///
/// Exhaustive with no `_` arm: a new [SyncFailureCause] must be given copy
/// here rather than fall back to a sentence that explains nothing.
String syncFailureReason(AppLocalizations l10n, SyncFailureCause cause) =>
    switch (cause) {
      SyncFailureCause.unreachable => l10n.settingsSyncFailureUnreachable,
      SyncFailureCause.timedOut => l10n.settingsSyncFailureTimedOut,
      SyncFailureCause.serverError => l10n.settingsSyncFailureServerError,
      SyncFailureCause.rateLimited => l10n.settingsSyncFailureRateLimited,
      SyncFailureCause.storeFull => l10n.settingsSyncFailureStoreFull,
      SyncFailureCause.tooLarge => l10n.settingsSyncFailureTooLarge,
      SyncFailureCause.rejected => l10n.settingsSyncFailureRejected,
      SyncFailureCause.accessDenied => l10n.settingsSyncFailureAccessDenied,
      SyncFailureCause.unexpectedResponse =>
        l10n.settingsSyncFailureUnexpectedResponse,
      SyncFailureCause.peerUnavailable =>
        l10n.settingsSyncFailurePeerUnavailable,
      SyncFailureCause.internal => l10n.settingsSyncFailureInternal,
    };

/// What the user can do about [cause], or who to tell when they can't.
String syncFailureAdvice(AppLocalizations l10n, SyncFailureCause cause) =>
    switch (cause) {
      SyncFailureCause.unreachable => l10n.settingsSyncFailureUnreachableAdvice,
      SyncFailureCause.timedOut => l10n.settingsSyncFailureTimedOutAdvice,
      SyncFailureCause.serverError => l10n.settingsSyncFailureServerErrorAdvice,
      SyncFailureCause.rateLimited => l10n.settingsSyncFailureRateLimitedAdvice,
      SyncFailureCause.storeFull => l10n.settingsSyncFailureStoreFullAdvice,
      SyncFailureCause.tooLarge => l10n.settingsSyncFailureTooLargeAdvice,
      SyncFailureCause.rejected => l10n.settingsSyncFailureRejectedAdvice,
      SyncFailureCause.accessDenied =>
        l10n.settingsSyncFailureAccessDeniedAdvice,
      SyncFailureCause.unexpectedResponse =>
        l10n.settingsSyncFailureUnexpectedResponseAdvice,
      SyncFailureCause.peerUnavailable =>
        l10n.settingsSyncFailurePeerUnavailableAdvice,
      SyncFailureCause.internal => l10n.settingsSyncFailureInternalAdvice,
    };

/// The reason followed by the advice, for surfaces with room for one block of
/// text (a snackbar, a form error).
String syncFailureExplanation(AppLocalizations l10n, SyncFailure failure) =>
    '${syncFailureReason(l10n, failure.cause)} '
    '${syncFailureAdvice(l10n, failure.cause)}';

/// The technical line a user can quote when describing the problem: which
/// step stopped and what the server answered. Null when neither is known —
/// a thrown failure has no step, and an unreachable server answered nothing.
String? syncFailureDetails(AppLocalizations l10n, SyncFailure failure) {
  final parts = [
    if (failure.step case final step?) l10n.settingsSyncFailureStep(step.name),
    if (failure.statusCode case final code?)
      l10n.settingsSyncFailureStatusCode(code),
  ];
  if (parts.isEmpty) return null;
  return l10n.settingsSyncFailureDetails(parts.join(' '));
}
