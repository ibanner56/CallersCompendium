import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/error_log.dart';

/// Base file name (without extension) of the on-device database. drift_flutter
/// stores the file as `$kDatabaseName.sqlite`; the migration preflight reuses
/// this so both agree on the exact file.
const String kDatabaseName = 'compendium';

/// Resolves the on-device [CompendiumDatabase] file.
///
/// The file lives in the application documents directory by default
/// (`<applicationDocumentsDirectory>/compendium.sqlite`). When the platform
/// cannot resolve Documents — on Linux without `xdg-user-dirs`, `path_provider`
/// throws [MissingPlatformDirectoryException] — it lives in the application
/// support directory instead (`$XDG_DATA_HOME/<app id>/compendium.sqlite` on
/// Linux). The fallback is sticky: once a database exists in the support
/// directory it is used even if Documents later becomes resolvable, so
/// installing `xdg-user-dirs` cannot strand the library behind a new, empty
/// file. If both exist, the support-directory file wins.
///
/// Resolving the path in the app — rather than letting drift_flutter compute it
/// opaquely — lets the migration preflight (downgrade guard + pre-migration
/// snapshot, see `migration_guard.dart`) read and copy the *same* file drift
/// will open. `compendium_core` stays Flutter-free (ADR-001), so this bit of
/// platform wiring lives in the app. The directory providers are injectable for
/// tests.
Future<File> resolveDatabaseFile({
  Future<Directory> Function() documentsDirectory =
      getApplicationDocumentsDirectory,
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
}) async {
  final fileName = '$kDatabaseName.sqlite';
  final supportFile = File(p.join((await supportDirectory()).path, fileName));
  if (supportFile.existsSync()) return supportFile;
  try {
    return File(p.join((await documentsDirectory()).path, fileName));
  } on MissingPlatformDirectoryException catch (e, st) {
    logCaughtErrorTypeOnly(e, st, source: 'app_database.resolveDatabaseFile');
    return supportFile;
  }
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
