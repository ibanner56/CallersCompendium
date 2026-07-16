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
/// to the [AppBootstrap] error screen with [message].
class DatabaseDowngradeError implements Exception {
  const DatabaseDowngradeError({
    required this.fileVersion,
    required this.appVersion,
  });

  /// The `user_version` persisted in the database file.
  final int fileVersion;

  /// The running app's [kCompendiumSchemaVersion].
  final int appVersion;

  /// User-facing explanation rendered on the startup error screen.
  String get message =>
      'This data was created by a newer version of Caller\u2019s Compendium '
      '\u2014 please update the app.';

  @override
  String toString() =>
      'DatabaseDowngradeError(file user_version $fileVersion > app schema '
      'version $appVersion)';
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
///    *fail-open*: if the snapshot cannot be written, it is logged and the
///    migration proceeds (a safety net must never block startup).
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
    // Asymmetric by design: the downgrade guard above is fail-CLOSED (it must
    // refuse to open), but the pre-migration snapshot is fail-OPEN. The
    // snapshot is a safety net; if it can't be written (disk full, unwritable
    // db_backups, checkpoint failure) we log and proceed so drift still
    // migrates. A failing backup must never be more harmful than the pre-PR
    // behavior, which ran upgrades with no snapshot at all.
    try {
      await snapshotBeforeMigrate(
        dbFile: dbFile,
        snapshotDir: snapshotDir,
        fromVersion: fileVersion,
        retain: retain,
        timestamp: now(),
      );
    } on Object catch (error) {
      debugPrint(
        'Migration preflight: pre-migration snapshot failed, proceeding '
        'with migration anyway: $error',
      );
    }
  }
}

/// App-facing entry point: resolves the real database file + snapshot directory
/// (via `path_provider`) and runs [runMigrationPreflight]. Wired into
/// `main.dart`'s startup sequence.
Future<void> runMigrationPreflightForApp({
  required int runningSchemaVersion,
}) async {
  final dbFile = await resolveDatabaseFile();
  final snapshotDir = Directory(
    p.join(dbFile.parent.path, kDatabaseBackupsDirName),
  );
  await runMigrationPreflight(
    dbFile: dbFile,
    snapshotDir: snapshotDir,
    runningSchemaVersion: runningSchemaVersion,
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
