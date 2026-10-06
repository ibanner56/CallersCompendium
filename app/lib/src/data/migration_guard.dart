import 'dart:io';

import 'package:compendium_core/compendium_core.dart'
    show kMinSupportedSchemaVersion;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../diagnostics/error_log.dart';
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
  // Floor raised to 20 once every tester was confirmed on beta.6+. beta.7
  // (schema v25) is the newest release that predates this raise, so it is
  // still the newest release that can open a v11–v19 database and migrate it
  // through the now-retired steps, landing at v25 — comfortably above v20.
  (floor: 20, bridgeTag: 'v0.1.0-beta.7'),
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

/// Why [relocateLegacyDatabase] refused to move (or could not finish moving) a
/// database, as a typed discriminator the presentation layer localizes.
enum DatabaseRelocationFailure {
  /// Data files already exist at the new location (the database or a stray
  /// `-wal`/`-shm`) *and* a database exists at a legacy location. Which is
  /// current is not for the app to guess, so every file is left exactly as
  /// found.
  bothExist,

  /// The new location is empty but more than one legacy location holds a
  /// database (on Windows: Documents and the Roaming fallback directory). Left
  /// exactly as found for the user to choose.
  multipleLegacy,

  /// The WAL could not be checkpointed (another connection holds the database),
  /// or copying, verifying or removing the legacy files failed (disk full,
  /// unwritable directory, a file locked by another process). Anything the
  /// attempt wrote at the new location is removed and any legacy file it had
  /// already deleted is restored from the verified copy, so the next launch
  /// starts again from the original state.
  moveFailed,

  /// No database exists at the new location yet, and the Documents folder
  /// earlier builds used does not exist (for example a redirected folder on a
  /// disconnected network share or drive letter), or on Windows could not be
  /// resolved at all. Whether a library is waiting there cannot be known, so
  /// nothing is created that would start an empty library beside it. Only a
  /// missing path is detected: an unmounted volume whose empty mount-point
  /// folder is still there looks like an empty Documents.
  legacyUnreachable,
}

/// Which folder a [DatabaseCopy] is in, as a typed discriminator the
/// presentation layer localizes (the screen never shows a path).
enum DatabaseCopyLocation {
  /// The current database directory.
  newLocation,

  /// The Documents folder earlier builds used.
  documents,

  /// Another folder an earlier build used (on Windows, the Roaming app data
  /// fallback directory).
  earlierAppFolder,
}

/// Size and age of one database copy found by [relocateLegacyDatabase], shown
/// on the terminal screen so the user can tell which copy is their library.
@immutable
class DatabaseCopy {
  const DatabaseCopy({
    required this.location,
    required this.bytes,
    required this.modified,
  });

  final DatabaseCopyLocation location;

  /// Combined size of the database file and its `-wal`/`-shm` sidecars.
  final int bytes;

  /// The most recent modification time among those files.
  final DateTime modified;
}

/// Thrown by [relocateLegacyDatabase] when it cannot safely complete the move.
///
/// Fail-closed like [MigrationSnapshotAborted] (issue #442): startup stops with
/// a terminal screen and no database is opened, so no second, empty database is
/// created beside the real one. Nothing is deleted on the way out.
class DatabaseRelocationBlocked implements Exception {
  const DatabaseRelocationBlocked(
    this.reason, {
    this.error,
    this.copies = const [],
  });

  final DatabaseRelocationFailure reason;

  /// For [DatabaseRelocationFailure.bothExist] and
  /// [DatabaseRelocationFailure.multipleLegacy]: each conflicting copy's
  /// location, size and modification time. Empty when they could not be read.
  final List<DatabaseCopy> copies;

  /// The underlying error for [DatabaseRelocationFailure.moveFailed], for
  /// diagnostics only: it can embed absolute paths and is never rendered.
  final Object? error;

  @override
  String toString() => 'DatabaseRelocationBlocked($reason, error: $error)';
}

const String _relocatingSuffix = '.relocating';

/// Name of the note [relocateLegacyDatabase] leaves inside the breadcrumb
/// folder at each earlier location after a successful move.
const String kRelocationBreadcrumbNoteName = 'README.txt';
const List<String> _sidecarSuffixes = ['-wal', '-shm'];

/// Moves a database left in a legacy location (Documents, or an earlier
/// fallback directory) to [target], once, before anything opens either file.
///
/// Returns `true` when a database was moved and `false` when there was nothing
/// to do (no legacy database exists, which is every launch after the first).
///
/// Moves `compendium.sqlite`, its `-wal`/`-shm` sidecars and the pre-migration
/// snapshots from the legacy directory's [kDatabaseBackupsDirName] folder. Only
/// files matching the snapshot naming are moved from that folder (Documents is
/// the user's own folder), and the folder is removed only if that leaves it
/// empty.
///
/// Rules, in the order they bite:
/// - **No library is not the same as an unreachable Documents.** When
///   no database exists at [target] yet and either [documentsDirectory] is
///   given but does not exist, or [documentsUnresolvable] is set (Windows could
///   not resolve Documents), throw
///   [DatabaseRelocationFailure.legacyUnreachable] and create nothing: a
///   missing Documents path (a redirected folder on a disconnected share or
///   drive letter) would otherwise look like "no legacy database", and drift
///   would start an empty library beside the real one. Only a missing path is
///   detected; an unmounted volume that leaves an empty mount-point folder
///   behind is not. Once [target] holds a database this check is skipped (an
///   empty library can no longer be started by mistake). A `null`
///   [documentsDirectory] without [documentsUnresolvable] means Linux without
///   `xdg-user-dirs`, where no earlier build could have kept a database.
/// - **Never overwrite.** If the target database (or a sidecar) exists, or more
///   than one legacy database exists, throw [DatabaseRelocationBlocked]
///   ([DatabaseRelocationFailure.bothExist] or
///   [DatabaseRelocationFailure.multipleLegacy]) and touch nothing; the error
///   carries each copy's location, size and age
///   ([DatabaseRelocationBlocked.copies]) so the user can choose.
/// - **Checkpoint first** (`wal_checkpoint(TRUNCATE)`, as the pre-migration
///   snapshot does), and require it to report not busy: a busy result means
///   another connection holds the WAL, so the main file is not yet a complete
///   database and nothing is copied ([DatabaseRelocationFailure.moveFailed]).
/// - **Copy, fsync, verify size, then rename into place**: every file is copied
///   to `<name>.relocating` beside its destination, flushed to disk and its
///   length compared with the source; only when all of them verify are they
///   renamed to their final names. A crash before that leaves only `.relocating`
///   files, which the next launch discards and redoes.
/// - **Delete the source last.** Sidecars and snapshots first, the main database
///   file last. Any failure before or during this step is rolled back: legacy
///   files already deleted are restored from the verified copy and what this
///   attempt wrote at the target is removed, so the legacy files are exactly as
///   found. Only if that restore itself fails is the target copy kept (data is
///   never left in fewer places than before).
///
/// The **breadcrumb** at the source path is made inside the delete step, right
/// after the main file is deleted; if it cannot be made the move rolls back
/// like any other delete failure. (A crash in the instant between that delete
/// and the breadcrumb leaves the path free, and nothing repairs it later.)
/// Breadcrumbs at the other legacy paths whose folder exists are best-effort.
/// A breadcrumb is a *folder* named
/// `compendium.sqlite` holding a [kRelocationBreadcrumbNoteName] that says
/// where the library went. Every earlier build (v0.1.0 to v0.5.4) skips its
/// preflight because `File.exists()` is false for a folder, then asks SQLite to
/// open the path, which cannot open a folder; it shows its startup error
/// screen instead of creating a new, empty library there. This function, for
/// the same reason, never sees a breadcrumb as a legacy database.
///
/// A *crash* (not a reported failure) between the rename and the last delete
/// leaves both copies; the next launch reports
/// [DatabaseRelocationFailure.bothExist] rather than overwriting either: a user
/// (not the app) decides which to delete, see `docs/user/faq.md`.
///
/// [deleter] is injectable so tests can fail the source cleanup part-way; the
/// production default deletes via [File]. A legacy file in
/// [documentsDirectory] is reported as [DatabaseCopyLocation.documents], any
/// other as [DatabaseCopyLocation.earlierAppFolder].
Future<bool> relocateLegacyDatabase({
  required File target,
  required List<File> legacy,
  Future<void> Function(File file)? deleter,
  Directory? documentsDirectory,
  bool documentsUnresolvable = false,
}) async {
  final delete = deleter ?? (file) => file.delete();
  final sources = <File>[
    for (final file in legacy)
      if (p.canonicalize(file.path) != p.canonicalize(target.path) &&
          file.existsSync())
        file,
  ];
  if (!target.existsSync() &&
      (documentsUnresolvable ||
          (documentsDirectory != null && !documentsDirectory.existsSync()))) {
    throw const DatabaseRelocationBlocked(
      DatabaseRelocationFailure.legacyUnreachable,
    );
  }
  if (sources.isEmpty) return false;

  DatabaseCopyLocation locationOf(File file) =>
      documentsDirectory != null &&
          p.canonicalize(file.parent.path) ==
              p.canonicalize(documentsDirectory.path)
      ? DatabaseCopyLocation.documents
      : DatabaseCopyLocation.earlierAppFolder;
  final targetOccupied = [
    target,
    for (final suffix in _sidecarSuffixes) File('${target.path}$suffix'),
  ].any((file) => file.existsSync());
  if (targetOccupied) {
    throw DatabaseRelocationBlocked(
      DatabaseRelocationFailure.bothExist,
      copies: _describeCopies([
        // Only a database file is a copy to choose; stray sidecars are not.
        if (target.existsSync()) (target, DatabaseCopyLocation.newLocation),
        for (final source in sources) (source, locationOf(source)),
      ]),
    );
  }
  if (sources.length > 1) {
    throw DatabaseRelocationBlocked(
      DatabaseRelocationFailure.multipleLegacy,
      copies: _describeCopies([
        for (final source in sources) (source, locationOf(source)),
      ]),
    );
  }
  final source = sources.single;

  final moves = <(File, File)>[];
  final temps = <File>[];
  final finals = <File>[];
  try {
    _checkpointOrThrowIfBusy(source.path);
    moves.add((source, target));
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('${source.path}$suffix');
      if (sidecar.existsSync()) {
        moves.add((sidecar, File('${target.path}$suffix')));
      }
    }
    final legacyBackups = Directory(
      p.join(source.parent.path, kDatabaseBackupsDirName),
    );
    final targetBackups = Directory(
      p.join(target.parent.path, kDatabaseBackupsDirName),
    );
    if (legacyBackups.existsSync()) {
      for (final entry in legacyBackups.listSync(followLinks: false)) {
        if (entry is File && _isSnapshot(p.basename(entry.path))) {
          moves.add((
            entry,
            File(p.join(targetBackups.path, p.basename(entry.path))),
          ));
        }
      }
    }
    if (moves.any((move) => move.$2.existsSync())) {
      throw const DatabaseRelocationBlocked(
        DatabaseRelocationFailure.bothExist,
      );
    }

    await target.parent.create(recursive: true);
    if (moves.any(
      (move) => p.basename(move.$2.parent.path) == kDatabaseBackupsDirName,
    )) {
      await targetBackups.create(recursive: true);
    }
    for (final (from, to) in moves) {
      final temp = File('${to.path}$_relocatingSuffix');
      temps.add(temp);
      await from.copy(temp.path);
      final handle = await temp.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (await temp.length() != await from.length()) {
        throw FileSystemException('relocated copy has the wrong size', to.path);
      }
    }
    for (final (index, (_, to)) in moves.indexed) {
      await temps[index].rename(to.path);
      finals.add(to);
    }
  } on DatabaseRelocationBlocked {
    // diagnostics: silent — typed fail-closed outcome, thrown before anything
    // was written; the caller routes it to the terminal screen.
    rethrow;
  } on Object catch (error) {
    // diagnostics: silent — fail-closed; the typed error carries the cause.
    await _discard([...temps, ...finals]);
    throw DatabaseRelocationBlocked(
      DatabaseRelocationFailure.moveFailed,
      error: error,
    );
  }

  final deleted = <(File, File)>[];
  try {
    // Main database file last: until it is gone the legacy library is intact.
    for (final move in moves.reversed) {
      await delete(move.$1);
      deleted.add(move);
    }
    // The breadcrumb at the old path is part of the move: if it cannot be
    // made (something took the freed path), the move rolls back below rather
    // than leave the path for an older build to start an empty library in.
    await Directory(source.path).create();
    if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('breadcrumb could not be made', source.path);
    }
  } on Object catch (error) {
    // diagnostics: silent — rolled back below; the typed error carries the cause.
    var restored = true;
    for (final (from, to) in deleted) {
      try {
        await to.copy(from.path);
      } on Object {
        // diagnostics: silent — the target copy is kept below.
        restored = false;
      }
    }
    // Only a fully restored legacy library lets the target copy go: otherwise
    // keep it, so the data is never left in fewer places than before.
    if (restored) await _discard(finals);
    throw DatabaseRelocationBlocked(
      DatabaseRelocationFailure.moveFailed,
      error: error,
    );
  }
  // Best-effort: an emptied legacy folder is cosmetic.
  try {
    final legacyBackups = Directory(
      p.join(source.parent.path, kDatabaseBackupsDirName),
    );
    if (legacyBackups.existsSync() && legacyBackups.listSync().isEmpty) {
      await legacyBackups.delete();
    }
  } on FileSystemException {
    // diagnostics: silent — cosmetic cleanup of an empty folder.
  }
  for (final file in legacy) {
    await _leaveBreadcrumb(file, target);
  }
  return true;
}

/// Size and age of each `(database file, location)` pair, counting its
/// `-wal`/`-shm` sidecars. Empty if any of them cannot be read: the details
/// help the user choose, and their absence must not hide the blocking message.
List<DatabaseCopy> _describeCopies(List<(File, DatabaseCopyLocation)> found) {
  try {
    return [
      for (final (file, location) in found)
        () {
          final present = [
            file,
            for (final suffix in _sidecarSuffixes) File('${file.path}$suffix'),
          ].where((f) => f.existsSync()).toList();
          return DatabaseCopy(
            location: location,
            bytes: present.fold(0, (sum, f) => sum + f.lengthSync()),
            modified: present
                .map((f) => f.lastModifiedSync())
                .reduce((a, b) => a.isAfter(b) ? a : b),
          );
        }(),
    ];
  } on Object catch (error, stackTrace) {
    logCaughtErrorTypeOnly(
      error,
      stackTrace,
      source: 'migration_guard.describeCopies',
    );
    return const [];
  }
}

/// Leaves a folder named like the database at [legacyFile]'s path, with a note
/// inside, so an earlier build fails to open it rather than creating an empty
/// library there (see [relocateLegacyDatabase]). Only where the path is free
/// and its folder exists; best-effort, since the move itself has succeeded.
Future<void> _leaveBreadcrumb(File legacyFile, File target) async {
  if (p.canonicalize(legacyFile.path) == p.canonicalize(target.path)) return;
  try {
    if (!legacyFile.parent.existsSync()) return;
    final type = FileSystemEntity.typeSync(legacyFile.path, followLinks: false);
    // A file or link there is someone else's; a folder is already a crumb
    // (the moved database's own, made as part of the move).
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      return;
    }
    final crumb = await Directory(legacyFile.path).create();
    final note = File(p.join(crumb.path, kRelocationBreadcrumbNoteName));
    if (note.existsSync()) return;
    await note.writeAsString(
      "Caller's Compendium moved your library out of this folder, to:\n"
      '\n'
      '    ${target.parent.path}\n'
      '\n'
      'This folder stays here so that an older version of the app, if you\n'
      'open one, shows an error instead of starting a new, empty library.\n'
      'Current versions ignore it. You can delete it if you will not open an\n'
      'older version again.\n',
      flush: true,
    );
  } on Object catch (error, stackTrace) {
    logCaughtErrorTypeOnly(
      error,
      stackTrace,
      source: 'migration_guard.leaveBreadcrumb',
    );
  }
}

/// Best-effort removal of files this relocation attempt itself created.
Future<void> _discard(List<File> files) async {
  for (final file in files) {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // diagnostics: silent — a leftover `.relocating` file is discarded by the
      // next attempt; a leftover final file is reported as bothExist.
    }
  }
}

/// App-facing entry point: resolves the real database file + snapshot directory
/// (via `path_provider`), moves a database an earlier build left in a legacy
/// location into place ([relocateLegacyDatabase]), and runs
/// [runMigrationPreflight]. Wired into
/// `main.dart`'s startup sequence. [onSnapshotFailure] is the consent seam
/// invoked only when the pre-migration snapshot fails (see
/// [runMigrationPreflight]); `main.dart` supplies an implementation that
/// surfaces a blocking dialog. Left `null` only by callers that intentionally
/// opt out, in which case a snapshot failure fails closed.
///
/// [operatingSystem] overrides the running platform, as in
/// [resolveDatabaseLocations], so tests can drive each platform's relocation.
Future<void> runMigrationPreflightForApp({
  required int runningSchemaVersion,
  SnapshotFailureDecision? onSnapshotFailure,
  String? operatingSystem,
}) async {
  final locations = await resolveDatabaseLocations(
    operatingSystem: operatingSystem,
  );
  const fileName = '$kDatabaseName.sqlite';
  final dbFile = File(p.join(locations.primary.path, fileName));
  // Before any open: drift would otherwise create a new, empty database beside
  // the library an earlier build left in Documents.
  await relocateLegacyDatabase(
    target: dbFile,
    legacy: [
      for (final dir in locations.legacy) File(p.join(dir.path, fileName)),
    ],
    documentsDirectory: locations.documents,
    documentsUnresolvable: locations.documentsUnresolvable,
  );
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

/// Like [_checkpoint], but also reads the result row: `wal_checkpoint(TRUNCATE)`
/// reports a blocked checkpoint (another connection holds the WAL) as `busy = 1`
/// rather than by throwing, and a copy taken then would miss committed data.
void _checkpointOrThrowIfBusy(String path) {
  final db = sql.sqlite3.open(path);
  try {
    final row = db.select('PRAGMA wal_checkpoint(TRUNCATE)').first;
    if (row.values.first != 0) {
      throw FileSystemException(
        'WAL checkpoint is blocked (database busy)',
        path,
      );
    }
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
