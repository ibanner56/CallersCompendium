// The short, fixed codes a Device Sync problem can be copied as, for a user to
// paste into a message asking for help ("Copy details"), and the same codes
// the diagnostic export lists.
//
// Deliberately not localized: a code is quoted to someone else, so it must
// read the same whatever language either side uses. It names a condition and
// carries only counts, a step name and an HTTP status — never a title, the
// sync phrase, a device or record identifier, or a report's message, which can
// carry wire paths. Nothing here sends anything anywhere; the user copies it.
import 'package:compendium_core/compendium_core.dart' show SyncReport;

import '../../sync/sync_coordinator.dart'
    show SyncPassResult, SyncPassStatus, SyncStoreQuota;
import '../../sync/sync_failure.dart';
import 'sync_notice_labels.dart';

/// The code for [cause], without the `SYNC-` prefix.
///
/// Exhaustive with no `_` arm so a new cause must be given a code.
String syncFailureCauseCode(SyncFailureCause cause) => switch (cause) {
  SyncFailureCause.unreachable => 'UNREACHABLE',
  SyncFailureCause.timedOut => 'TIMED-OUT',
  SyncFailureCause.serverError => 'SERVER-ERROR',
  SyncFailureCause.rateLimited => 'RATE-LIMITED',
  SyncFailureCause.storeFull => 'STORE-FULL',
  SyncFailureCause.tooLarge => 'TOO-LARGE',
  SyncFailureCause.rejected => 'REFUSED',
  SyncFailureCause.accessDenied => 'ACCESS-DENIED',
  SyncFailureCause.unexpectedResponse => 'BAD-RESPONSE',
  SyncFailureCause.peerUnavailable => 'PEER-UNAVAILABLE',
  SyncFailureCause.internal => 'INTERNAL',
};

/// The code for a failed pass: its cause, then the step and HTTP status when
/// known — `SYNC-REFUSED upload 422`.
String syncFailureSupportCode(SyncFailure failure) => [
  'SYNC-${syncFailureCauseCode(failure.cause)}',
  ?failure.step?.name,
  ?failure.statusCode?.toString(),
].join(' ');

/// The code for the pass [result], or null for a status that is not a
/// problem.
String? syncPassSupportCode(SyncPassResult result) => switch (result.status) {
  SyncPassStatus.failed => switch (result.failure) {
    final failure? => syncFailureSupportCode(failure),
    null => 'SYNC-FAILED',
  },
  SyncPassStatus.staleEpoch => 'SYNC-STALE-STORE',
  SyncPassStatus.replacementRequired => 'SYNC-STORE-UNAVAILABLE',
  SyncPassStatus.firstTimeStoreRequired => 'SYNC-STORE-NOT-FOUND',
  SyncPassStatus.paused => 'SYNC-PAUSED',
  SyncPassStatus.completed ||
  SyncPassStatus.skippedUnconfigured ||
  SyncPassStatus.freshAttachRequired => null,
};

/// The code for the notice [group] raises from [reports]: its group name and
/// how many records it names, when it names any — `SYNC-NEWER-VERSION ×4`.
String syncNoticeSupportCode(
  SyncNoticeGroup group,
  Iterable<SyncReport> reports,
) {
  final code = 'SYNC-${_kebab(group.name)}';
  final records = syncNoticeRecords(group, reports).length;
  return records == 0 ? code : '$code ×$records';
}

/// The code for a nearly full store: the larger share used, rounded down so
/// it never claims more than is used — `SYNC-QUOTA 85%`.
String syncQuotaSupportCode(SyncStoreQuota quota) =>
    'SYNC-QUOTA ${(quota.usedFraction * 100).floor()}%';

/// `newerVersion` → `NEWER-VERSION`.
String _kebab(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]}').toUpperCase();
