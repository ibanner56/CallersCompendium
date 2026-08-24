import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Base file name (without extension) of the on-device database. drift_flutter
/// stores the file as `$kDatabaseName.sqlite`; the migration preflight reuses
/// this so both agree on the exact file.
const String kDatabaseName = 'compendium';

/// Resolves the on-device [CompendiumDatabase] file, mirroring drift_flutter's
/// default location (`<applicationDocumentsDirectory>/compendium.sqlite`).
///
/// Resolving the path in the app — rather than letting drift_flutter compute it
/// opaquely — lets the migration preflight (downgrade guard + pre-migration
/// snapshot, see `migration_guard.dart`) read and copy the *same* file drift
/// will open. `compendium_core` stays Flutter-free (ADR-001), so this bit of
/// platform wiring lives in the app.
Future<File> resolveDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, '$kDatabaseName.sqlite'));
}

/// Opens the on-device [CompendiumDatabase] via drift_flutter's platform helper.
///
/// The explicit [DriftNativeOptions.databasePath] pins the file to
/// [resolveDatabaseFile] so drift opens exactly the file the migration preflight
/// inspected. Without it, drift_flutter would recompute the default path
/// internally; keeping a single source of truth avoids any drift between the
/// preflight's target and the opened database.
CompendiumDatabase openAppDatabase() => CompendiumDatabase(
  driftDatabase(
    name: kDatabaseName,
    native: DriftNativeOptions(
      databasePath: () async => (await resolveDatabaseFile()).path,
    ),
  ),
);

/// Bundles the open [CompendiumDatabase] with its [CompendiumRepositories]
/// facade, so callers dispose of exactly one thing.
class AppData {
  AppData(this.db) : repositories = CompendiumRepositories(db, contraTaxonomy);

  final CompendiumDatabase db;
  final CompendiumRepositories repositories;

  Future<void>? _closeFuture;

  /// Closes the database once, sharing the result with concurrent callers.
  ///
  /// Desktop shutdown can reach both the window-close handler and the widget
  /// tree's disposal. Sharing one close operation prevents the background Drift
  /// isolate from receiving overlapping shutdown requests.
  Future<void> close() => _closeFuture ??= db.close();
}
