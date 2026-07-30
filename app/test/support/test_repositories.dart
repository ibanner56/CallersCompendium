import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

/// An in-memory [CompendiumRepositories] for widget tests. Each call opens a
/// fresh, isolated database (no shared state between tests), mirroring
/// `packages/compendium_core/test/storage/test_database.dart`.
CompendiumRepositories openTestRepositories() => CompendiumRepositories(
  CompendiumDatabase(NativeDatabase.memory()),
  contraTaxonomy,
);

/// A [SettingsRepository] that can be forced to fail its writes, used to
/// simulate the settings store throwing / being unavailable during a backup
/// restore's settings-apply step (issue #608). Reads and removes still delegate
/// to the real repository so tests can inspect state and a retry can succeed
/// once [failWrites] is cleared.
class FailingSettingsRepository extends SettingsRepository {
  FailingSettingsRepository(super.db);

  /// When true, every [set] throws instead of writing.
  bool failWrites = true;

  @override
  Future<void> set(String key, Object? value) {
    if (failWrites) throw const InjectedSettingsFailure();
    return super.set(key, value);
  }
}

/// The exception thrown by [FailingSettingsRepository] while
/// [FailingSettingsRepository.failWrites] is set. An [Exception] (not an
/// [Error]) so it models a real settings-store I/O failure that the service is
/// expected to catch and report as a retryable settings failure.
class InjectedSettingsFailure implements Exception {
  const InjectedSettingsFailure();
  @override
  String toString() => 'Injected settings-store failure';
}

/// Opens in-memory repositories whose settings store fails its writes until
/// [FailingSettingsRepository.failWrites] is cleared. The core repositories
/// share the same database, so a core restore commits normally while the
/// settings-apply step fails.
({CompendiumRepositories repos, FailingSettingsRepository settings})
openTestRepositoriesWithFailingSettings() {
  final db = CompendiumDatabase(NativeDatabase.memory());
  final settings = FailingSettingsRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  return (repos: repos, settings: settings);
}
