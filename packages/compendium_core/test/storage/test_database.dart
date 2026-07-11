import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

/// An in-memory [CompendiumDatabase] for tests. Each call returns a fresh,
/// isolated database (no shared state between tests).
CompendiumDatabase openTestDatabase() =>
    CompendiumDatabase(NativeDatabase.memory());
