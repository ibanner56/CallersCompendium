import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/error_log.dart';

/// Base file name (without extension) of the on-device database. drift_flutter
/// stores the file as `$kDatabaseName.sqlite`; the migration preflight reuses
/// this so both agree on the exact file.
const String kDatabaseName = 'compendium';

/// Where the on-device database lives, and where earlier builds left it.
@immutable
class DatabaseLocations {
  const DatabaseLocations({required this.primary, required this.legacy});

  /// The directory holding `compendium.sqlite` (and its `db_backups/`).
  final Directory primary;

  /// Directories earlier builds may have left a database in, never including
  /// [primary]. [relocateLegacyDatabase] moves such a database into [primary]
  /// during the migration preflight, before anything opens it.
  final List<Directory> legacy;
}

/// Resolves the directory the database lives in on [operatingSystem] (the
/// running platform by default; injectable so tests can cover every platform).
///
/// - **Windows**: the per-app folder under `%LOCALAPPDATA%`. `path_provider`
///   exposes LocalAppData only as the application *cache* directory
///   (`getApplicationCacheDirectory`, which is
///   `%LOCALAPPDATA%\<company>\<product>`; nothing evicts it). The application
///   *support* directory is Roaming AppData, which roaming profiles copy: a poor
///   home for a live WAL database. Roaming is used only if LocalAppData cannot
///   be resolved. Earlier builds used Documents (which OneDrive's folder backup
///   syncs) and, in a rare fallback, Roaming.
/// - **Linux**: the application support directory (`$XDG_DATA_HOME/<app id>`).
///   Earlier builds used Documents, which is `$HOME` itself when
///   `XDG_DOCUMENTS_DIR` is unset, so the files landed loose in the home
///   directory; and, when Documents could not be resolved at all
///   (`MissingPlatformDirectoryException`), this same support directory.
/// - **Everything else** (macOS is sandboxed; Android and iOS Documents are
///   app-private): the application documents directory, unchanged.
Future<DatabaseLocations> resolveDatabaseLocations({
  String? operatingSystem,
}) async {
  switch (operatingSystem ?? Platform.operatingSystem) {
    case 'windows':
      final support = await getApplicationSupportDirectory();
      Directory primary;
      try {
        primary = await getApplicationCacheDirectory();
      } on MissingPlatformDirectoryException catch (e, st) {
        logCaughtErrorTypeOnly(
          e,
          st,
          source: 'app_database.resolveDatabaseLocations',
        );
        primary = support;
      }
      return DatabaseLocations(
        primary: primary,
        legacy: [
          ?await _tryDocumentsDirectory(),
          if (p.canonicalize(support.path) != p.canonicalize(primary.path))
            support,
        ],
      );
    case 'linux':
      return DatabaseLocations(
        primary: await getApplicationSupportDirectory(),
        legacy: [?await _tryDocumentsDirectory()],
      );
    default:
      return DatabaseLocations(
        primary: await getApplicationDocumentsDirectory(),
        legacy: const [],
      );
  }
}

Future<Directory?> _tryDocumentsDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } on MissingPlatformDirectoryException catch (e, st) {
    // Linux without xdg-user-dirs: no Documents folder, so no legacy database.
    logCaughtErrorTypeOnly(e, st, source: 'app_database.documentsDirectory');
    return null;
  }
}

/// Resolves the on-device [CompendiumDatabase] file: `compendium.sqlite` in the
/// [DatabaseLocations.primary] directory (see [resolveDatabaseLocations]).
///
/// Resolving the path in the app, rather than letting drift_flutter compute it
/// opaquely, lets the migration preflight (relocation, downgrade guard and
/// pre-migration snapshot, see `migration_guard.dart`) read and copy the *same*
/// file drift will open. The preflight runs before drift opens anything, so a
/// database found in a legacy location is already in the primary directory by
/// the time this is used to open it. `compendium_core` stays Flutter-free
/// (ADR-001), so this bit of platform wiring lives in the app.
Future<File> resolveDatabaseFile({String? operatingSystem}) async {
  final locations = await resolveDatabaseLocations(
    operatingSystem: operatingSystem,
  );
  return File(p.join(locations.primary.path, '$kDatabaseName.sqlite'));
}

/// Opens the on-device [CompendiumDatabase] via drift_flutter's platform helper.
///
/// The explicit [DriftNativeOptions.databasePath] pins the file to
/// [resolveDatabaseFile] so drift opens exactly the file the migration preflight
/// inspected. Without it, drift_flutter would recompute the default path
/// internally; keeping a single source of truth avoids any drift between the
/// preflight's target and the opened database.
/// The [DriftNativeOptions.setup] enables WAL and a busy timeout. Device Sync
/// runs its pass in a worker isolate that opens this same file on its own
/// connection (`sync_isolate.dart`), so both connections have to agree: without
/// WAL a sync write would stall every app read, and without a busy timeout an
/// app write that lands during an inbound apply fails outright with "database
/// is locked". See [applyCompendiumSqliteSetup].
CompendiumDatabase openAppDatabase() => CompendiumDatabase(
  driftDatabase(
    name: kDatabaseName,
    native: DriftNativeOptions(
      databasePath: () async => (await resolveDatabaseFile()).path,
      setup: applyCompendiumSqliteSetup,
    ),
  ),
);

/// Bundles the open [CompendiumDatabase] with its [CompendiumRepositories]
/// facade, so callers dispose of exactly one thing.
class AppData {
  AppData(this.db) : repositories = CompendiumRepositories(db, contraTaxonomy);

  final CompendiumDatabase db;
  final CompendiumRepositories repositories;

  Future<void> close() => db.close();
}
