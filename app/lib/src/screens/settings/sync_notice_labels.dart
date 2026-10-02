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
/// conditions renders deterministically. The one needs-you group comes first.
enum SyncNoticeGroup {
  /// Another device shared records in an envelope version this build cannot
  /// read. Needs you: updating the app on this device is the only remedy, and
  /// nothing about the records themselves is wrong.
  newerVersion,

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
  SyncReportCode.newerWireVersion => SyncNoticeGroup.newerVersion,
};

/// The groups [reports] raise, deduplicated, in [SyncNoticeGroup] order.
List<SyncNoticeGroup> syncNoticeGroups(Iterable<SyncReport> reports) {
  final raised = reports.map(syncNoticeGroupFor).toSet();
  return [
    for (final group in SyncNoticeGroup.values)
      if (raised.contains(group)) group,
  ];
}

/// Whether [group] needs the user to act, and so is shown with the warning
/// styling, a text label and a copyable support code; every other group is an
/// informational heads-up.
///
/// Exhaustive with no `_` arm so a new group must be placed in a tier.
bool syncNoticeNeedsYou(SyncNoticeGroup group) => switch (group) {
  SyncNoticeGroup.newerVersion => true,
  SyncNoticeGroup.divergence ||
  SyncNoticeGroup.keptLocalCreation ||
  SyncNoticeGroup.quarantinedLocal ||
  SyncNoticeGroup.withheldUnreadableLocal ||
  SyncNoticeGroup.skippedRecord ||
  SyncNoticeGroup.clock ||
  SyncNoticeGroup.deferredInbound ||
  SyncNoticeGroup.unreflectedPublication => false,
};

/// The notice text for [group]. [recordCount] is [syncNoticeCountedRecords];
/// only [SyncNoticeGroup.newerVersion] says it, and falls back to an
/// uncounted sentence at 0 — a newer manifest does not say what it lists.
///
/// Never the report's own `message`: those are internal diagnostics written
/// for a maintainer reading a log — they name wire paths, status codes and
/// hashes, and they are English by design.
String syncNoticeText(
  AppLocalizations l10n,
  SyncNoticeGroup group, {
  required int recordCount,
}) => switch (group) {
  SyncNoticeGroup.newerVersion =>
    recordCount > 0
        ? l10n.settingsSyncNoticeNewerVersion(recordCount)
        : l10n.settingsSyncNoticeNewerVersionUncounted,
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

/// How many records a notice names before summarising the rest as a count.
const int kSyncNoticeNamedLimit = 5;

/// One record a notice is about, as the reports identify it.
typedef SyncNoticeRecord = ({SyncRecordKind kind, String recordId});

/// The records [group]'s reports in [reports] are about, deduplicated, in
/// report order. Reports that name no record — a pass-wide clock suspicion, a
/// blob the store asked for by hash — contribute nothing.
List<SyncNoticeRecord> syncNoticeRecords(
  SyncNoticeGroup group,
  Iterable<SyncReport> reports,
) {
  final seen = <SyncNoticeRecord>{};
  return [
    for (final report in reports)
      if (syncNoticeGroupFor(report) == group)
        if ((report.kind, report.recordId) case (final kind?, final id?))
          if (seen.add((kind: kind, recordId: id))) (kind: kind, recordId: id),
  ];
}

/// How many records [group]'s notice may claim it is about: the records
/// [syncNoticeRecords] names, or 0 when any of the group's reports names no
/// record. A newer manifest names none, yet stands for everything its peer
/// shares, so a count beside it would understate what is waiting.
int syncNoticeCountedRecords(
  SyncNoticeGroup group,
  Iterable<SyncReport> reports,
) {
  final grouped = [
    for (final report in reports)
      if (syncNoticeGroupFor(report) == group) report,
  ];
  if (grouped.any((r) => r.kind == null || r.recordId == null)) return 0;
  return syncNoticeRecords(group, grouped).length;
}

/// How many distinct other devices [group]'s reports in [reports] came from.
int syncNoticePeerCount(SyncNoticeGroup group, Iterable<SyncReport> reports) =>
    {
      for (final report in reports)
        if (syncNoticeGroupFor(report) == group) ?report.peerId,
    }.length;

/// The user-facing label for a record kind ("Dance", "Program", …).
String syncRecordKindLabel(AppLocalizations l10n, SyncRecordKind kind) =>
    switch (kind) {
      SyncRecordKind.choreographer => l10n.syncReviewKindChoreographer,
      SyncRecordKind.tag => l10n.syncReviewKindTag,
      SyncRecordKind.customFieldDef => l10n.syncReviewKindCustomField,
      SyncRecordKind.difficultyLevel => l10n.syncReviewKindDifficulty,
      SyncRecordKind.dance => l10n.syncReviewKindDance,
      SyncRecordKind.program => l10n.syncReviewKindProgram,
      SyncRecordKind.publishedSource => l10n.syncReviewKindPublishedSource,
      SyncRecordKind.venue => l10n.syncReviewKindVenue,
      SyncRecordKind.setting => l10n.syncReviewKindSetting,
    };

/// What this device knows a notice's record by.
sealed class SyncNoticeRecordName {
  const SyncNoticeRecordName();
}

/// The record is here, under [name].
final class SyncNoticeRecordNamed extends SyncNoticeRecordName {
  const SyncNoticeRecordNamed(this.name);
  final String name;
}

/// The record's kind has names, and this device has no live record with that
/// id: typically a skipped record from another device.
final class SyncNoticeRecordNotHere extends SyncNoticeRecordName {
  const SyncNoticeRecordNotHere();
}

/// The kind has no single display name to look up (a setting, a custom
/// field), or no repositories were available; only the kind is shown.
final class SyncNoticeRecordUnnamed extends SyncNoticeRecordName {
  const SyncNoticeRecordUnnamed();
}

/// Looks up what the user calls [record] on this device.
///
/// Only the kinds a user browses by name are looked up. Everything else is
/// [SyncNoticeRecordUnnamed] rather than [SyncNoticeRecordNotHere]: not
/// looking is not evidence of absence.
Future<SyncNoticeRecordName> lookupSyncNoticeRecordName(
  CompendiumRepositories repositories,
  SyncNoticeRecord record,
) async {
  final id = record.recordId;
  final String? name = switch (record.kind) {
    SyncRecordKind.dance => (await repositories.dances.getById(id))?.title,
    SyncRecordKind.program => (await repositories.programs.getById(id))?.title,
    SyncRecordKind.choreographer => (await repositories.choreographers.getById(
      id,
    ))?.name,
    SyncRecordKind.tag => (await repositories.tags.getById(id))?.name,
    SyncRecordKind.venue => (await repositories.venues.getById(id))?.name,
    SyncRecordKind.customFieldDef ||
    SyncRecordKind.difficultyLevel ||
    SyncRecordKind.publishedSource ||
    SyncRecordKind.setting => null,
  };
  if (name != null && name.trim().isNotEmpty) {
    return SyncNoticeRecordNamed(name);
  }
  return switch (record.kind) {
    SyncRecordKind.dance ||
    SyncRecordKind.program ||
    SyncRecordKind.choreographer ||
    SyncRecordKind.tag ||
    SyncRecordKind.venue when name == null => const SyncNoticeRecordNotHere(),
    _ => const SyncNoticeRecordUnnamed(),
  };
}

/// The "Affects: …" line for [named] — the first [kSyncNoticeNamedLimit]
/// records with what they resolved to — out of [total] records in all.
String syncNoticeAffectedText(
  AppLocalizations l10n,
  List<(SyncNoticeRecord, SyncNoticeRecordName)> named,
  int total,
) {
  final items = [
    for (final (record, name) in named)
      switch (name) {
        SyncNoticeRecordNamed(:final name) =>
          l10n.settingsSyncNoticeRecordNamed(
            syncRecordKindLabel(l10n, record.kind),
            name,
          ),
        SyncNoticeRecordNotHere() => l10n.settingsSyncNoticeRecordNotHere(
          syncRecordKindLabel(l10n, record.kind),
        ),
        SyncNoticeRecordUnnamed() => syncRecordKindLabel(l10n, record.kind),
      },
    if (total > named.length)
      l10n.settingsSyncNoticeAffectedMore(total - named.length),
  ];
  return l10n.settingsSyncNoticeAffected(
    items.join(l10n.settingsSyncNoticeListSeparator),
  );
}
