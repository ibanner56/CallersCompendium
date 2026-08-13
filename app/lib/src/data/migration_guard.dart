import 'dart:io';

import 'package:compendium_core/compendium_core.dart'
    show kMinSupportedSchemaVersion;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import 'app_database.dart';

/// Directory name (under the database's own directory) holding automatic
/// pre-migration snapshots.
const String kDatabaseBackupsDirName = 'db_backups';

/// How many pre-migration snapshots to retain by default (oldest are pruned).
const int kDefaultSnapshotRetention = 5;

const String _snapshotPrefix = 'compendium.pre-v';
const String _snapshotSuffix = '.sqlite.bak';

/// Thrown by [runMigrationPreflight] when the on-disk database was written by a
/// build *older* than the minimum supported schema version floor
/// ([kMinSupportedSchemaVersion]), meaning the migration steps for its version
/// have been retired and cannot be applied.
///
/// Like [DatabaseDowngradeError] this is terminal with *no* Retry: the only
/// forward path is a one-time migration bridge (open the database with the
/// newest release that predates the floor, let it migrate to a supported
/// version, then update again). The AppBootstrap error screen localizes the
/// explanation and provides that guidance.
///
/// [bridgeTag] is the release tag of the newest release that can still open
/// and migrate a database at [fileVersion] to a version at or above the floor —
/// i.e., the tag whose schema version is the last one *before* [fileVersion]
/// was retired. The app layer derives this from [kBelowFloorBridgeTags].
class DatabaseBelowFloorError implements Exception {
  const DatabaseBelowFloorError({
    required this.fileVersion,
    required this.minSupportedVersion,
    required this.bridgeTag,
  });

  /// The `user_version` persisted in the database file (below the floor).
  final int fileVersion;

  /// The running app's [kMinSupportedSchemaVersion].
  final int minSupportedVersion;

  /// The release tag of the bridge release that can migrate [fileVersion] up
  /// to a supported schema version.
  final String bridgeTag;

  @override
  String toString() =>
      'DatabaseBelowFloorError(file user_version $fileVersion < floor '
      '$minSupportedVersion, bridge: $bridgeTag)';
}

/// Append-only list of `(floor, bridgeTag)` pairs, one entry per floor raise.
///
/// **[floor]** — the value of [kMinSupportedSchemaVersion] introduced by that
/// raise.
/// **[bridgeTag]** — the release tag of the newest release that predates the
/// raise and can therefore still open *and* migrate any database below the new
/// floor up to a supported version. Specifically, it is the tag whose schema
/// version is the highest version still below [floor] after the raise.
///
/// When [kMinSupportedSchemaVersion] is next raised, add one entry here:
/// the new floor value and the tag of the release whose schema is the last one
/// below it. That is part of the floor-raise checklist.
///
/// Uses [int] floors and [String] tags so the list is encodable without
/// importing the database package.
const List<({int floor, String bridgeTag})> kBelowFloorBridgeTags = [
  // Floor raised to 11 by #837 (d9546a15). beta.6 shipped schema v20, which
  // is comfortably above v11, so it migrates any v1–v10 database through the
  // now-retired steps and lands at a supported version.
  (floor: 11, bridgeTag: 'v0.1.0-beta.6'),
];

/// Returns the [bridgeTag] for a database at [fileVersion] — the release tag
/// of the release that can open that file and migrate it to a version the
/// current floor permits. This may require a second hop if the floor has been
/// raised more than once since that release shipped: the user installs the
/// returned tag, opens the app to migrate, then sees a second recovery screen
/// naming the next bridge if one is needed.
///
/// Iterates [kBelowFloorBridgeTags] in order and returns the first entry whose
/// [floor] exceeds [fileVersion]. If no entry matches (which should not occur
/// for any file version the preflight accepts), returns the last entry's tag as
/// a safe fallback.
String bridgeTagFor(int fileVersion) {
  for (final entry in kBelowFloorBridgeTags) {
    if (entry.floor > fileVersion) return entry.bridgeTag;
  }
  // Fallback: use the most recent entry. Should not be reachable for any
  // below-floor version the preflight is called with.
  return kBelowFloorBridgeTags.last.bridgeTag;
}

/// Thrown by [runMigrationPreflight] when the on-disk database was created by a
/// *newer* build than the one running (its persisted `user_version` exceeds the
/// running [kCompendiumSchemaVersion]).
///
/// drift is forward-only with no `onDowngrade`, so migrating such a file would
/// either silently stamp its version down (leaving newer tables/columns under
/// an older code path) or corrupt data. Instead we refuse to open it and route
/// to the AppBootstrap error screen, which localizes the explanation.
class DatabaseDowngradeError implements Exception {
  const DatabaseDowngradeError({
    required this.fileVersion,
    required this.appVersion,
  });

  /// The `user_version` persisted in the database file.
  final int fileVersion;

  /// The running app's [kCompendiumSchemaVersion].
  final int appVersion;

  @override
  String toString() =>
      'DatabaseDowngradeError(file user_version $fileVersion > app schema '
      'version $appVersion)';
}

/// The most likely reason a pre-migration snapshot could not be written, so the
/// consent surface can name the probable cause in plain language. Classified by
/// [classifySnapshotFailure] (invoked from [runMigrationPreflight]) from the
/// underlying [FileSystemException]'s OS error code; never trusts raw exception
/// text for control flow.
enum SnapshotFailureCause {
  /// The volume holding the database has no room for the snapshot copy
  /// (`ENOSPC` / Windows disk-full codes).
  diskFull,

  /// The `db_backups` directory (or a parent) cannot be created or written
  /// (`EACCES`/`EPERM`/`EROFS`/`ENOTDIR` / Windows access-denied).
  unwritableBackupsDir,

  /// Anything else (a WAL checkpoint failure, an unexpected I/O error, …).
  unknown,
}

/// Describes a failed pre-migration snapshot attempt, handed to the injected
/// [SnapshotFailureDecision] so the app can ask the user whether to migrate
/// without a recoverable backup. Carries only classified, non-sensitive data;
/// [error] is retained for diagnostics/logging and must not be rendered raw
/// (it can embed absolute filesystem paths).
@immutable
class SnapshotFailure {
  const SnapshotFailure({
    required this.fromVersion,
    required this.toVersion,
    required this.cause,
    required this.error,
  });

  /// The `user_version` currently persisted in the database file (the version
  /// the pending migration is upgrading *from*).
  final int fromVersion;

  /// The running app's schema version (the version being upgraded *to*).
  final int toVersion;

  /// The classified likely cause, used to phrase the consent copy.
  final SnapshotFailureCause cause;

  /// The underlying error, for logging/diagnostics only — never surfaced raw.
  final Object error;

  @override
  String toString() =>
      'SnapshotFailure(from $fromVersion -> $toVersion, cause: $cause, '
      'error: $error)';
}

/// Decision seam invoked by [runMigrationPreflight] when the pre-migration
/// snapshot fails. Returns `true` to proceed with the migration anyway (with no
/// recoverable backup) or `false` to abort startup. Kept UI-free so the guard
/// stays testable; the app supplies an implementation that surfaces a blocking
/// consent dialog and returns the user's explicit choice.
typedef SnapshotFailureDecision =
    Future<bool> Function(SnapshotFailure failure);

/// Thrown by [runMigrationPreflight] when the pre-migration snapshot fails and
/// the [SnapshotFailureDecision] declines to proceed (or none was supplied).
///
/// Fail-closed, mirroring [DatabaseDowngradeError]: the migration must NOT run,
/// so no schema change happens and the file is left intact for the user to back
/// up manually / free disk / fix permissions before reopening the app.
class MigrationSnapshotAborted implements Exception {
  const MigrationSnapshotAborted(this.failure);

  /// The classified failure that prompted the aborted migration.
  final SnapshotFailure failure;

  @override
  String toString() => 'MigrationSnapshotAborted($failure)';
}

/// Runs the data-safety preflight against the database file *before* drift opens
/// it. Three guards, in order:
///
/// 1. **Downgrade protection** — if the file's `user_version` exceeds
///    [runningSchemaVersion], throw [DatabaseDowngradeError] and do NOT open /
///    migrate.
/// 2. **Below-floor protection** — if the file's `user_version` is below
///    [kMinSupportedSchemaVersion], throw [DatabaseBelowFloorError] and do NOT
///    open / migrate. The migration steps for those versions are retired; the
///    recovery path is a one-time bridge release, not a downgrade or a wipe.
/// 3. **Backup-before-migrate** — if an upgrade is pending (file version <
///    running), snapshot the file into [snapshotDir] first (retaining the
///    newest [retain]), so a botched migration is recoverable. This step is
///    **fail-CLOSED**: if the snapshot cannot be written, the migration is
///    *not* allowed to silently proceed. Instead the failure is classified into
///    a [SnapshotFailure] and handed to [onSnapshotFailure], which returns the
///    user's explicit choice — `true` to proceed without a backup, `false` to
///    abort. If the callback declines (or none is supplied — the safest
///    default), a [MigrationSnapshotAborted] is thrown and no schema change
///    happens (issue #442).
///
/// A missing file (fresh install) or an uninitialized file (`user_version == 0`,
/// which drift will populate via `onCreate`) is a no-op.
///
/// This reads the file with a short-lived `package:sqlite3` connection (which
/// is WAL-aware, unlike reading the header bytes directly) and never opens the
/// drift database, so no migration is triggered here.
Future<void> runMigrationPreflight({
  required File dbFile,
  required Directory snapshotDir,
  required int runningSchemaVersion,
  int retain = kDefaultSnapshotRetention,
  DateTime Function() now = _utcNow,
  SnapshotFailureDecision? onSnapshotFailure,
}) async {
  if (!await dbFile.exists()) return;

  final fileVersion = readUserVersion(dbFile.path);
  // 0 == brand-new/empty file; drift's onCreate will stamp the current version.
  if (fileVersion == 0) return;

  if (fileVersion > runningSchemaVersion) {
    throw DatabaseDowngradeError(
      fileVersion: fileVersion,
      appVersion: runningSchemaVersion,
    );
  }

  if (fileVersion < runningSchemaVersion) {
    // Below-floor check: if the file version is retired (below the supported
    // floor), migration steps no longer exist for it. Throw
    // [DatabaseBelowFloorError] so the app can show a recovery screen with
    // the bridge-release guidance rather than a dead-end Retry (issue #841).
    if (fileVersion < kMinSupportedSchemaVersion) {
      throw DatabaseBelowFloorError(
        fileVersion: fileVersion,
        minSupportedVersion: kMinSupportedSchemaVersion,
        bridgeTag: bridgeTagFor(fileVersion),
      );
    }
    // Symmetric with the downgrade guard above: both are fail-CLOSED. The
    // pre-migration snapshot is a recoverability safety net; if it can't be
    // written (disk full, unwritable db_backups, checkpoint failure) we must
    // NOT silently migrate, because a botched upgrade would then be
    // unrecoverable. We gate the migration on an explicit user decision
    // ([onSnapshotFailure]); absent a decision — or a decision to decline — we
    // abort (issue #442).
    try {
      await snapshotBeforeMigrate(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        fromVersion: fileVersion,
        retain: retain,
        timestamp: now(),
      );
    } on Object catch (error) {
      // diagnostics: silent — pre-migration snapshot failed; returns SnapshotFailure to caller (bootstrap infrastructure, not UI).
      final failure = SnapshotFailure(
        fromVersion: fileVersion,
        toVersion: runningSchemaVersion,
        cause: classifySnapshotFailure(error),
        error: error,
      );
      // No seam to ask the user (e.g. a headless/test caller that opted out) is
      // treated as a decline: fail closed rather than assume consent.
      final proceed = onSnapshotFailure == null
          ? false
          : await onSnapshotFailure(failure);
      if (!proceed) {
        throw MigrationSnapshotAborted(failure);
      }
      if (kDebugMode) {
        debugPrint(
          'Migration preflight: pre-migration snapshot failed; user chose to '
          'proceed without a backup: $error',
        );
      }
    }
  }
}

/// Classifies a snapshot [error] into a [SnapshotFailureCause] using the
/// platform error code first (locale-independent) and the OS message only as a
/// fallback. Never trusts message text for anything but a coarse hint.
///
/// Exposed so the below-floor backup-before-reset flow (AppBootstrap's
/// Back Up + Reset action) can classify its own snapshot failures with the same
/// logic, rather than duplicating the OS-code table.
SnapshotFailureCause classifySnapshotFailure(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // Disk full: POSIX ENOSPC (28); Windows ERROR_DISK_FULL (112) /
    // ERROR_HANDLE_DISK_FULL (39).
    if (code == 28 || code == 112 || code == 39) {
      return SnapshotFailureCause.diskFull;
    }
    // Unwritable path: POSIX EPERM (1), EACCES (13), ENOTDIR (20), EROFS (30);
    // Windows ERROR_ACCESS_DENIED (5).
    if (code == 1 || code == 13 || code == 20 || code == 30 || code == 5) {
      return SnapshotFailureCause.unwritableBackupsDir;
    }
    final message = error.osError?.message.toLowerCase() ?? '';
    if (message.contains('no space') || message.contains('disk full')) {
      return SnapshotFailureCause.diskFull;
    }
    if (message.contains('permission') ||
        message.contains('denied') ||
        message.contains('read-only') ||
        message.contains('not a directory')) {
      return SnapshotFailureCause.unwritableBackupsDir;
    }
  }
  return SnapshotFailureCause.unknown;
}

/// App-facing entry point: resolves the real database file + snapshot directory
/// (via `path_provider`) and runs [runMigrationPreflight]. Wired into
/// `main.dart`'s startup sequence. [onSnapshotFailure] is the consent seam
/// invoked only when the pre-migration snapshot fails (see
/// [runMigrationPreflight]); `main.dart` supplies an implementation that
/// surfaces a blocking dialog. Left `null` only by callers that intentionally
/// opt out, in which case a snapshot failure fails closed.
Future<void> runMigrationPreflightForApp({
  required int runningSchemaVersion,
  SnapshotFailureDecision? onSnapshotFailure,
}) async {
  final dbFile = await resolveDatabaseFile();
  final snapshotDir = Directory(
    p.join(dbFile.parent.path, kDatabaseBackupsDirName),
  );
  await runMigrationPreflight(
    dbFile: dbFile,
    snapshotDir: snapshotDir,
    runningSchemaVersion: runningSchemaVersion,
    onSnapshotFailure: onSnapshotFailure,
  );
}

/// Reads the persisted `PRAGMA user_version` of the SQLite file at [path]
/// without going through drift. Returns 0 for a brand-new/empty file.
int readUserVersion(String path) {
  final db = sql.sqlite3.open(path);
  try {
    final result = db.select('PRAGMA user_version');
    final value = result.first.values.first;
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  } finally {
    db.close();
  }
}

/// Copies [dbFile] to a timestamped snapshot in [snapshotDir] and prunes the
/// directory to the newest [retain] snapshots. Returns the snapshot file.
///
/// The WAL is folded into the main file first (`wal_checkpoint(TRUNCATE)`) so
/// the byte copy is a complete, self-contained database.
Future<File> snapshotBeforeMigrate({
  required File dbFile,
  required Directory snapshotDir,
  required int fromVersion,
  required DateTime timestamp,
  int retain = kDefaultSnapshotRetention,
}) async {
  await snapshotDir.create(recursive: true);
  _checkpoint(dbFile.path);

  // Disambiguate collisions: microsecond timestamps make same-name snapshots
  // vanishingly unlikely, but a retry loop *could* still land in the same
  // microsecond, so fall back to an incrementing suffix rather than silently
  // overwriting a previous backup.
  final base = '$_snapshotPrefix$fromVersion-${_formatTimestamp(timestamp)}';
  var dest = File(p.join(snapshotDir.path, '$base$_snapshotSuffix'));
  var collision = 1;
  while (await dest.exists()) {
    dest = File(p.join(snapshotDir.path, '$base-$collision$_snapshotSuffix'));
    collision++;
  }
  await dbFile.copy(dest.path);

  await _pruneSnapshots(snapshotDir, retain);
  return dest;
}

DateTime _utcNow() => DateTime.now().toUtc();

/// Checkpoints (and truncates) the WAL so all committed data lives in the main
/// database file, making a plain file copy a complete snapshot.
void _checkpoint(String path) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    db.close();
  }
}

/// Filename-safe, lexicographically-sortable UTC timestamp with microsecond
/// resolution (`YYYYMMDDTHHMMSSmmmuuuZ`).
String _formatTimestamp(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  final year = u.year.toString().padLeft(4, '0');
  return '$year${two(u.month)}${two(u.day)}T'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}'
      '${three(u.millisecond)}${three(u.microsecond)}Z';
}

bool _isSnapshot(String basename) =>
    basename.startsWith(_snapshotPrefix) && basename.endsWith(_snapshotSuffix);

/// Deletes the oldest snapshots so at most [retain] remain. Ordering is by
/// modified time, with the (lexicographically sortable, timestamped) filename
/// as a deterministic tie-breaker so coarse-resolution filesystems that give
/// several snapshots the same mtime never prune out of order.
Future<void> _pruneSnapshots(Directory dir, int retain) async {
  if (retain < 0) return;
  final snapshots = <(File, DateTime)>[];
  await for (final entry in dir.list()) {
    if (entry is File && _isSnapshot(p.basename(entry.path))) {
      snapshots.add((entry, (await entry.stat()).modified));
    }
  }
  if (snapshots.length <= retain) return;
  // Oldest first; the copy just written has the newest mtime, so recency order
  // is correct even when snapshots span multiple `fromVersion`s.
  snapshots.sort((a, b) {
    final byMtime = a.$2.compareTo(b.$2);
    if (byMtime != 0) return byMtime;
    return p.basename(a.$1.path).compareTo(p.basename(b.$1.path));
  });
  for (final (file, _) in snapshots.take(snapshots.length - retain)) {
    try {
      await file.delete();
    } on FileSystemException {
      // diagnostics: silent — best-effort pruning; a snapshot we couldn't
      // delete is harmless.
    }
  }
}

/// Result of [performBackUpAndReset] — either the snapshot succeeded and the
/// wipe can proceed, or it failed and the database must be left untouched.
sealed class BackUpAndResetResult {
  const BackUpAndResetResult();
}

/// The pre-reset snapshot was written successfully. The caller may proceed with
/// the wipe (after any confirmation UI). [snapshotFile] is the written file.
/// [diagnosticLogFile] is the accompanying log written beside the backup; may
/// be `null` if writing the log failed (non-blocking — the snapshot is the
/// load-bearing artefact).
final class BackUpReady extends BackUpAndResetResult {
  const BackUpReady(this.snapshotFile, {this.diagnosticLogFile});
  final File snapshotFile;
  final File? diagnosticLogFile;
}

/// The pre-reset snapshot could not be written. The database must NOT be wiped.
/// [cause] is the classified failure for use in the UI.
final class BackUpFailed extends BackUpAndResetResult {
  const BackUpFailed({required this.cause, required this.error});
  final SnapshotFailureCause cause;

  /// The underlying error, for diagnostics/logging — never surfaced raw.
  final Object error;
}

/// Fail-closed pre-reset backup: attempts to snapshot [dbFile] into
/// [snapshotDir] before any wipe, then writes an accompanying diagnostic log.
///
/// Returns [BackUpReady] if the snapshot succeeded, or [BackUpFailed] if it
/// did not. The caller **must not wipe** when [BackUpFailed] is returned.
///
/// A diagnostic log (plain text, schema/version metadata only — no user
/// content, no filesystem paths) is written beside the backup when possible.
/// Log failure is non-blocking: [BackUpReady.diagnosticLogFile] is `null` when
/// writing it failed, but the reset may still proceed.
///
/// Privacy: the diagnostic log contains only non-personal technical metadata
/// (schema version, floor, app version, platform, timestamp). It is intended
/// to be shared with support alongside the backup — egress: shareable,
/// subject: none, DPV term: nonPersonal. No user-authored content, no
/// filesystem paths, no personally identifiable information.
///
/// [snapshotWriter] is injectable so tests can inject a failing writer without
/// touching the filesystem; the production default is [snapshotBeforeMigrate].
///
/// This is the testable core of `_backUpAndReset` in `main.dart`: the Flutter
/// layer handles dialogs and navigation; this function owns the fail-closed
/// invariant.
Future<BackUpAndResetResult> performBackUpAndReset({
  required File dbFile,
  required Directory snapshotDir,
  required int fileVersion,
  required String appVersion,
  required String platform,
  String? bridgeTag,
  Future<File> Function({
    required File dbFile,
    required Directory snapshotDir,
    required int fromVersion,
    required DateTime timestamp,
  })?
  snapshotWriter,
}) async {
  final writer = snapshotWriter ?? snapshotBeforeMigrate;
  final now = DateTime.now().toUtc();
  final File snapshot;
  try {
    snapshot = await writer(
      dbFile: dbFile,
      snapshotDir: snapshotDir,
      fromVersion: fileVersion,
      timestamp: now,
    );
  } on Object catch (error) {
    // diagnostics: silent — snapshot write failed; returns BackUpFailed to caller (bootstrap infrastructure, not UI).
    return BackUpFailed(cause: classifySnapshotFailure(error), error: error);
  }

  // Snapshot succeeded. Attempt to write an accompanying diagnostic log.
  // A log failure is non-blocking: the backup is the load-bearing artefact.
  File? logFile;
  try {
    logFile = await _writeDiagnosticLog(
      snapshotDir: snapshotDir,
      timestamp: now,
      fileVersion: fileVersion,
      appVersion: appVersion,
      platform: platform,
      bridgeTag: bridgeTag,
    );
  } on Object {
    // diagnostics: silent — non-fatal: proceed without a log file.
  }

  return BackUpReady(snapshot, diagnosticLogFile: logFile);
}

/// Writes a plain-text diagnostic log file beside the backup. Contains only
/// non-personal technical metadata — no user content, no filesystem paths.
///
/// File name: `compendium-reset-diagnostics-<timestamp>.txt`
Future<File> _writeDiagnosticLog({
  required Directory snapshotDir,
  required DateTime timestamp,
  required int fileVersion,
  required String appVersion,
  required String platform,
  String? bridgeTag,
}) async {
  await snapshotDir.create(recursive: true);
  final ts = _formatTimestamp(timestamp);
  final file = File(
    p.join(snapshotDir.path, 'compendium-reset-diagnostics-$ts.txt'),
  );
  final buffer = StringBuffer()
    ..writeln('Caller\'s Compendium — below-floor reset diagnostics')
    ..writeln('Generated: ${timestamp.toIso8601String()}')
    ..writeln('App version: $appVersion')
    ..writeln('Platform: $platform')
    ..writeln('Database schema version: $fileVersion')
    ..writeln('Minimum supported schema version: $kMinSupportedSchemaVersion')
    ..writeln('Bridge release: ${bridgeTag ?? 'none'}');
  await file.writeAsString(buffer.toString(), flush: true);
  return file;
}

/// Result of [performReset] — either the database was deleted and the app can
/// reopen a fresh one, or deletion failed and the database file is intact.
sealed class ResetResult {
  const ResetResult();
}

/// The database file was deleted successfully. The caller should reopen a fresh
/// database and restart the bootstrap sequence.
final class ResetComplete extends ResetResult {
  const ResetComplete();
}

/// The database file could not be deleted. The file is still present; the
/// caller should reopen the original database so the app returns to a usable
/// state (it will show the recovery screen again).
final class ResetFailed extends ResetResult {
  const ResetFailed(this.error);
  final Object error;
}

/// Deletes [dbFile] and its WAL/SHM sidecar files.
///
/// Returns [ResetComplete] if [dbFile] was deleted, or [ResetFailed] if the
/// deletion threw. The database must be closed by the caller **before** this
/// is called; [dbFile] is closed by the time [performReset] is invoked.
///
/// WAL/SHM sidecar deletion is best-effort: a failure there is caught and
/// ignored because the load-bearing step is the main file.
///
/// [dbDeleter] is injectable so tests can inject a failing deleter without
/// touching the real filesystem; the production default deletes via [File].
Future<ResetResult> performReset({
  required File dbFile,
  Future<void> Function(File file)? dbDeleter,
}) async {
  final deleter = dbDeleter ?? (file) => file.delete();
  try {
    if (await dbFile.exists()) {
      await deleter(dbFile);
    }
  } on Object catch (error) {
    // diagnostics: silent — DB file deletion failed; returns ResetFailed to caller (bootstrap infrastructure, not UI).
    return ResetFailed(error);
  }
  // WAL/SHM sidecars: best-effort, non-load-bearing.
  for (final suffix in ['-wal', '-shm']) {
    final sidecar = File('${dbFile.path}$suffix');
    if (await sidecar.exists()) {
      try {
        await sidecar.delete();
      } on FileSystemException {
        // diagnostics: silent — best-effort: a stale sidecar is harmless once
        // the main file is gone.
      }
    }
  }
  return const ResetComplete();
}
