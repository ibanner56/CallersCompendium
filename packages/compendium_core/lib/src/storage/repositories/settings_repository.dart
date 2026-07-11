import 'dart:convert';

import '../database.dart';

/// Free-form key/value app settings (dialect choice, prefs, source URLs).
/// Values are stored as JSON so callers can persist any JSON-encodable type.
class SettingsRepository {
  SettingsRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> set(String key, Object? value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, valueJson: jsonEncode(value)),
      );

  /// Returns the decoded value for [key], or `null` if unset. Note this
  /// cannot distinguish "unset" from "explicitly set to JSON `null`" — use
  /// [contains] when that distinction matters.
  Future<Object?> get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson);
  }

  Future<bool> contains(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row != null;
  }

  Future<void> remove(String key) =>
      (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();

  Future<Map<String, Object?>> all() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final r in rows) r.key: jsonDecode(r.valueJson)};
  }
}
