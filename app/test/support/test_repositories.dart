import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

/// An in-memory [CompendiumRepositories] for widget tests. Each call opens a
/// fresh, isolated database (no shared state between tests), mirroring
/// `packages/compendium_core/test/storage/test_database.dart`.
CompendiumRepositories openTestRepositories() => CompendiumRepositories(
  CompendiumDatabase(NativeDatabase.memory()),
  contraTaxonomy,
);
