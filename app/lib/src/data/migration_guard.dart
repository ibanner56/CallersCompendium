import 'dart:io';

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

/// Thrown by [runMigrationPreflight] when the on-disk database was created by a
/// *newer* build than the one running (its persisted `user_version` exceeds the
/// running [kCompendiumSchemaVersion]).
///
/// drift is forward-only with no `onDowngrade`, so migrating such a file would
/// either silently stamp its version down (leaving newer tables/columns under
/// an older code path) or corrupt data. Instead we refuse to open it and route
/// to the [AppBootstrap] error screen, which localizes the explanation.
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
/// [_classifySnapshotFailure] (invoked from [runMigrationPreflight]) from the
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
/// it. Two guards, in order:
///
/// 1. **Downgrade protection** — if the file's `user_version` exceeds
///    [runningSchemaVersion], throw [DatabaseDowngradeError] and do NOT open /
///    migrate.
/// 2. **Backup-before-migrate** — if an upgrade is pending (file version <
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
      final failure = SnapshotFailure(
        fromVersion: fileVersion,
        toVersion: runningSchemaVersion,
        cause: _classifySnapshotFailure(error),
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
SnapshotFailureCause _classifySnapshotFailure(Object error) {
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
      // Best-effort pruning: a snapshot we couldn't delete is harmless.
    }
  }
}
