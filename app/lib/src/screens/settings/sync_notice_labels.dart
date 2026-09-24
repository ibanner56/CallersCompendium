// Maps the engine's structured sync reports onto the localized copy the
// Device Sync status surface shows. Lives beside the section rather than
// inside it so that adding a report code is a one-file change and the status
// widget stays about layout.
import 'package:compendium_core/compendium_core.dart';

import '../../../l10n/app_localizations.dart';

/// The user-facing groupings of [SyncReportCode].
///
/// A report names a *condition*, and the user can act on far fewer distinct
/// conditions than the engine can distinguish: seven separate ways for a peer
/// record to be unusable leave the user with the same thing to do. The spec's
/// sizing note is explicit that the report "must not be a per-record prompt"
/// (docs/design/sync-implementation.md), so the surface groups and the engine
/// stays precise. Cited without a line number, because the one that was here
/// pointed at :614 and the sentence had since moved to :652.
///
/// Declaration order is the order notices appear, so a pass raising several
/// conditions renders deterministically.
enum SyncNoticeGroup {
  /// Two devices hold different bodies with the same `updatedAt`. Neither
  /// wins and neither is applied (spec §6.3); only a human edit settles it.
  divergence,

  /// A record created here would have been resolved out of existence before
  /// any peer had seen it, so it was kept instead (spec §6.4).
  keptLocalCreation,

  /// A record on *this* device carries a timestamp the engine will not trust:
  /// peer-only repair left it quarantined, and it is withheld from publication
  /// along with its database dependents. Nothing was received and nothing was
  /// skipped, so the remedy is this device's clock, not another device's app
  /// version.
  quarantinedLocal,

  /// A record on *this* device could not be decoded, so it is withheld from
  /// publication rather than sent as an empty body over a peer's good copy
  /// (spec §6.9, #1347).
  ///
  /// Distinct from [skippedRecord] for the same reason [quarantinedLocal] is:
  /// that notice sends the user to their *other* device's app version, which
  /// is the wrong device and the wrong remedy for a row stored here. Distinct
  /// from [quarantinedLocal] too — no clock is involved and no later pass
  /// clears it, so "check this device's date and time" would be false advice.
  withheldUnreadableLocal,

  /// A record from a peer could not be used and was left alone: malformed,
  /// non-canonical, non-shareable, a missing or mismatched blob, an
  /// unresolved reference, or quarantined for an implausible clock.
  skippedRecord,

  /// Every peer timestamp observed in the pass sat outside this device's
  /// clock window, which points at a wrong clock rather than a bad record.
  clock,

  /// An inbound update was not applied because the local row changed while
  /// the pass was preparing it. It is retried, not lost.
  deferredInbound,

  /// Records this device published have not appeared in any peer's manifest
  /// for three consecutive passes.
  unreflectedPublication,
}

/// The group [report] belongs to.
///
/// Takes the whole report, not just its code, because one code covers two
/// different conditions: `quarantinedRecord` is raised both for an inbound
/// peer record held back (`peerId` set) and for a local row peer-only repair
/// could not rescue (`peerId` null, from the coordinator's `quarantinedLocal`
/// sweep). `peerId` is what tells them apart, and they call for opposite
/// things from the user — one is another device's problem, the other is this
/// device's clock.
///
/// The switch is deliberately exhaustive with no `_` arm: a new
/// [SyncReportCode] must fail the build here rather than be dropped on the
/// floor. Dropping codes silently is precisely the defect this mapping exists
/// to fix — the original twelve were produced and none were ever displayed.
/// Stated without a count on purpose: the count was written when there were
/// twelve, `withheldUnreadableRecord` made it thirteen, and a number in a
/// comment goes stale exactly when the rule it guards is next exercised.
SyncNoticeGroup syncNoticeGroupFor(SyncReport report) => switch (report.code) {
  SyncReportCode.equalUpdatedAt => SyncNoticeGroup.divergence,
  SyncReportCode.unseenLocalCreation => SyncNoticeGroup.keptLocalCreation,
  SyncReportCode.malformedRecord => SyncNoticeGroup.skippedRecord,
  SyncReportCode.nonCanonicalWireBody => SyncNoticeGroup.skippedRecord,
  SyncReportCode.invalidClassification => SyncNoticeGroup.skippedRecord,
  SyncReportCode.unresolvedBlob => SyncNoticeGroup.skippedRecord,
  SyncReportCode.blobIdentityMismatch => SyncNoticeGroup.skippedRecord,
  SyncReportCode.unresolvedReference => SyncNoticeGroup.skippedRecord,
  SyncReportCode.quarantinedRecord =>
    report.peerId == null
        ? SyncNoticeGroup.quarantinedLocal
        : SyncNoticeGroup.skippedRecord,
  SyncReportCode.clockSuspect => SyncNoticeGroup.clock,
  SyncReportCode.concurrentLocalChange => SyncNoticeGroup.deferredInbound,
  SyncReportCode.unreflectedPublication =>
    SyncNoticeGroup.unreflectedPublication,
  SyncReportCode.withheldUnreadableRecord =>
    SyncNoticeGroup.withheldUnreadableLocal,
};

/// The groups [reports] raise, deduplicated, in [SyncNoticeGroup] order.
List<SyncNoticeGroup> syncNoticeGroups(Iterable<SyncReport> reports) {
  final raised = reports.map(syncNoticeGroupFor).toSet();
  return [
    for (final group in SyncNoticeGroup.values)
      if (raised.contains(group)) group,
  ];
}

/// The notice text for [group].
///
/// Never the report's own `message`: those are internal diagnostics written
/// for a maintainer reading a log — they name wire paths, status codes and
/// hashes, and they are English by design.
String syncNoticeText(
  AppLocalizations l10n,
  SyncNoticeGroup group,
) => switch (group) {
  SyncNoticeGroup.divergence => l10n.settingsSyncNoticeDivergence,
  SyncNoticeGroup.keptLocalCreation => l10n.settingsSyncNoticeKeptLocalCreation,
  SyncNoticeGroup.quarantinedLocal => l10n.settingsSyncNoticeQuarantinedLocal,
  SyncNoticeGroup.withheldUnreadableLocal =>
    l10n.settingsSyncNoticeWithheldUnreadable,
  SyncNoticeGroup.skippedRecord => l10n.settingsSyncNoticeSkippedRecord,
  SyncNoticeGroup.clock => l10n.settingsSyncNoticeClock,
  SyncNoticeGroup.deferredInbound => l10n.settingsSyncNoticeDeferredInbound,
  SyncNoticeGroup.unreflectedPublication =>
    l10n.settingsSyncNoticeUnreflectedPublication,
};
