import 'package:compendium_core/compendium_core.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens the on-device [CompendiumDatabase] via drift_flutter's platform
/// helper, which picks the right storage location/native library loading
/// strategy per platform (desktop/mobile/web). `compendium_core` stays
/// Flutter-free (ADR-001), so this bit of platform wiring lives in the app.
CompendiumDatabase openAppDatabase() =>
    CompendiumDatabase(driftDatabase(name: 'compendium'));

/// Bundles the open [CompendiumDatabase] with its [CompendiumRepositories]
/// facade, so callers dispose of exactly one thing.
class AppData {
  AppData(this.db) : repositories = CompendiumRepositories(db, contraTaxonomy);

  final CompendiumDatabase db;
  final CompendiumRepositories repositories;

  Future<void> close() => db.close();
}
