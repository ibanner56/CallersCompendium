import 'package:flutter/material.dart'
    show MaterialLocalizations, TargetPlatform;

import '../../l10n/app_localizations.dart';
import 'migration_guard.dart';
import 'regional_formats.dart';

/// Localized presentation of the startup migration-guard diagnostics
/// (`migration_guard.dart`): [DatabaseDowngradeError], [DatabaseBelowFloorError],
/// [MigrationSnapshotAborted], [DatabaseRelocationBlocked], and the
/// [SnapshotFailureCause] discriminator.
///
/// The guard never bakes English prose into these types; it exposes typed
/// discriminators (the exception type itself, plus [SnapshotFailure.cause]).
/// This mapper turns them into localized strings at the presentation boundary,
/// mirroring `import_error_labels.dart`.
///
/// Security: every returned string is generic, user-safe prose. None contains a
/// filesystem path or raw lower-layer error text — [SnapshotFailure.error] is
/// diagnostic-only and never surfaced here (CWE-209).

/// Terminal-screen message for a [DatabaseDowngradeError].
String databaseDowngradeMessage(AppLocalizations l10n) =>
    l10n.migrationDowngradeMessage;

/// Terminal-screen headline for a [DatabaseBelowFloorError].
String databaseBelowFloorHeadline(AppLocalizations l10n) =>
    l10n.migrationBelowFloorHeadline;

/// Where the below-floor recovery screen sends the caller, which depends on
/// how the app is installed on that platform (pre-release audit finding F-01).
enum BelowFloorRoute {
  /// Windows, macOS and Linux: install the bridge release from its release
  /// page, open it once, then install this version again.
  desktop,

  /// Android refuses to install an older release over a newer one, and
  /// uninstalling to make room deletes the library, so the desktop route would
  /// lose the data: the screen says not to uninstall, and shares a scrubbed
  /// copy to update on a computer instead (`recovery_copy.dart`).
  android,

  /// iPhone and iPad: the app comes only from TestFlight, and the release page
  /// has no iOS download, so the screen points to TestFlight's earlier builds,
  /// and offers the same copy as Android for when the bridge is not listed.
  ios,
}

/// The [BelowFloorRoute] for [platform]. Anything that is not Android or iOS
/// (including Fuchsia) takes the desktop route, as it did before the split.
BelowFloorRoute belowFloorRouteFor(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android => BelowFloorRoute.android,
      TargetPlatform.iOS => BelowFloorRoute.ios,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => BelowFloorRoute.desktop,
    };

/// The version number TestFlight shows for the release tagged [bridgeTag]: its
/// major.minor.patch core without the leading `v` or a `-beta` suffix (the iOS build's
/// version is the pubspec's, which carries neither). A tag that does not start
/// with a version core is returned unchanged.
String bridgeVersionForTestFlight(String bridgeTag) =>
    RegExp(r'^v?(\d+\.\d+\.\d+)').firstMatch(bridgeTag)?.group(1) ?? bridgeTag;

/// Terminal-screen body for a [DatabaseBelowFloorError] on [route].
/// [bridgeTag] is the release tag of the migration-bridge release to recommend.
String databaseBelowFloorBody(
  AppLocalizations l10n,
  String bridgeTag, {
  BelowFloorRoute route = BelowFloorRoute.desktop,
}) => switch (route) {
  BelowFloorRoute.desktop => l10n.migrationBelowFloorBody(bridgeTag),
  BelowFloorRoute.android => l10n.migrationBelowFloorBodyAndroid(bridgeTag),
  BelowFloorRoute.ios => l10n.migrationBelowFloorBodyIos(
    bridgeVersionForTestFlight(bridgeTag),
  ),
};

/// Terminal-screen label for the primary button that opens the release page
/// of [bridgeTag], the version that can update the old data.
String databaseBelowFloorGetBridge(AppLocalizations l10n, String bridgeTag) =>
    l10n.migrationBelowFloorGetBridge(bridgeTag);

/// Terminal-screen label above the two reset buttons.
String databaseBelowFloorStartFresh(AppLocalizations l10n) =>
    l10n.migrationBelowFloorStartFresh;

/// Terminal-screen label for the "Back up + reset" button on the below-floor
/// recovery screen.
String databaseBelowFloorBackUpAndReset(AppLocalizations l10n) =>
    l10n.migrationBelowFloorBackUpAndReset;

/// Terminal-screen label for the "Reset only" button on the below-floor
/// recovery screen.
String databaseBelowFloorResetOnly(AppLocalizations l10n) =>
    l10n.migrationBelowFloorResetOnly;

/// A short, plain-language sentence naming the probable cause of a failed
/// pre-migration backup, or the empty string when the cause is [unknown].
/// The [SnapshotFailureCause.databaseInUse] sentence also names its remedy, as
/// the generic copy's "free up space" advice does not apply to it.
String snapshotCauseSentence(
  AppLocalizations l10n,
  SnapshotFailureCause cause,
) => switch (cause) {
  SnapshotFailureCause.diskFull => l10n.migrationSnapshotCauseDiskFull,
  SnapshotFailureCause.unwritableBackupsDir =>
    l10n.migrationSnapshotCauseUnwritableBackupsDir,
  SnapshotFailureCause.databaseInUse =>
    l10n.migrationSnapshotCauseDatabaseInUse,
  SnapshotFailureCause.unknown => '',
};

/// Body of the blocking dialog that asks whether to change saved data without
/// a backup. A database another app holds open gets its own copy: the
/// generic one tells the user to free up space or fix the backups folder,
/// which would not help.
String migrationSnapshotConsentBody(
  AppLocalizations l10n,
  SnapshotFailure failure,
) {
  if (failure.cause == SnapshotFailureCause.databaseInUse) {
    return l10n.migrationSnapshotInUseConsentBody;
  }
  final sentence = snapshotCauseSentence(l10n, failure.cause);
  return l10n.migrationSnapshotConsentBody(
    sentence.isEmpty ? '' : '\n\n$sentence',
  );
}

/// Terminal-screen message for a [MigrationSnapshotAborted], weaving in the
/// likely-cause sentence when one is known. A database another app holds
/// open gets its own message, for the reason given at
/// [migrationSnapshotConsentBody].
String migrationSnapshotAbortedMessage(
  AppLocalizations l10n,
  SnapshotFailure failure,
) {
  if (failure.cause == SnapshotFailureCause.databaseInUse) {
    return l10n.migrationSnapshotInUseAbortedMessage;
  }
  final sentence = snapshotCauseSentence(l10n, failure.cause);
  final cause = sentence.isEmpty ? '' : '$sentence ';
  return l10n.migrationSnapshotAbortedMessage(cause);
}

/// Terminal-screen message for a [DatabaseRelocationBlocked]. Generic and
/// path-free; the FAQ names the per-OS locations.
String databaseRelocationMessage(
  AppLocalizations l10n,
  DatabaseRelocationFailure reason,
) => switch (reason) {
  DatabaseRelocationFailure.bothExist => l10n.migrationRelocationBothExist,
  DatabaseRelocationFailure.multipleLegacy =>
    l10n.migrationRelocationMultipleLegacy,
  DatabaseRelocationFailure.moveFailed => l10n.migrationRelocationFailed,
  DatabaseRelocationFailure.legacyUnreachable =>
    l10n.migrationRelocationLegacyUnreachable,
};

/// Folder name for a [DatabaseCopy] on the relocation terminal screen.
String databaseCopyLocationLabel(
  AppLocalizations l10n,
  DatabaseCopyLocation location,
) => switch (location) {
  DatabaseCopyLocation.newLocation => l10n.migrationRelocationCopyNewLocation,
  DatabaseCopyLocation.documents => l10n.migrationRelocationCopyDocuments,
  DatabaseCopyLocation.earlierAppFolder =>
    l10n.migrationRelocationCopyEarlierAppFolder,
};

/// One line describing a conflicting [DatabaseCopy]: its folder name, its size
/// in kilobytes (rounded up, so a non-empty file never reads as 0 KB) and its
/// last-changed date and time (the date in the device's region, as
/// [formatEventDateTime] shows it). Path-free, like the rest of
/// this file.
String databaseCopyDetails(
  AppLocalizations l10n,
  MaterialLocalizations material,
  DatabaseCopy copy,
) => l10n.migrationRelocationCopyDetails(
  databaseCopyLocationLabel(l10n, copy.location),
  (copy.bytes / 1024).ceil(),
  // The Regional setting is stored in the database that failed to open, so
  // this is the system default: the device's region.
  formatEventDateTime(copy.modified, DateFormatSetting.system, material, l10n),
);
