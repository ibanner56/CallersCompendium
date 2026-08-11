import 'dart:convert';

import 'package:drift/drift.dart';

import '../database.dart';
import '../existence.dart';

/// Free-form key/value app settings (dialect choice, prefs, source URLs).
/// Values are stored as JSON so callers can persist any JSON-encodable type.
///
/// Settings are **soft-deleted** as of schema v25 (issue #898): without a
/// tombstone a removed setting cannot be expressed on the wire, so a peer that
/// had not synced recently would resurrect a preference the user cleared
/// elsewhere. Every read here filters `deleted_at IS NULL`, so a removed key
/// still reads as absent from [get], [contains] and [all].
///
/// **The internal control markers are a separate matter.** This table also
/// holds migration bookkeeping — [derivedRebuildRequiredKey],
/// [purgeCorruptionRepairDoneKey], [sectionRuleVersionKey],
/// [inversePairNormalisationDoneKey] — which `CompendiumRepositories` reads and
/// clears with raw SQL rather than through this class. Those stay hard deletes,
/// and the raw reads filter tombstones, so a marker can neither be resurrected
/// nor read back as still-set after it is cleared.
class SettingsRepository {
  SettingsRepository(this._db);

  final CompendiumDatabase _db;

  /// Writes [key], reviving it if it was previously removed.
  ///
  /// `key` is the primary key, so re-setting a removed setting lands on its
  /// tombstone; clearing `deleted_at` here is what makes the value visible
  /// again. Drift's untargeted `ON CONFLICT DO UPDATE` only writes the columns
  /// the companion names, so without this the value would be stored and then
  /// filtered straight back out of every read.
  Future<void> set(String key, Object? value, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: key,
              valueJson: jsonEncode(value),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: 'settings',
        keyColumn: 'key',
        key: key,
        at: now,
      );
    });
  }

  /// Returns the decoded value for [key], or `null` if unset. Note this
  /// cannot distinguish "unset" from "explicitly set to JSON `null`" — use
  /// [contains] when that distinction matters.
  Future<Object?> get(String key) async {
    final row =
        await (_db.select(_db.settings)
              ..where((t) => t.key.equals(key) & t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson);
  }

  Future<bool> contains(String key) async {
    final row =
        await (_db.select(_db.settings)
              ..where((t) => t.key.equals(key) & t.deletedAt.isNull()))
            .getSingleOrNull();
    return row != null;
  }

  /// Tombstones [key]. The row and its JSON value stay on disk until a purge:
  /// that is the point, since a peer must be able to learn that the setting was
  /// removed rather than merely fail to see it. Every read here filters
  /// tombstones, so callers cannot tell the difference.
  Future<void> remove(String key, {DateTime? at}) => stampExistenceTransition(
    _db,
    table: 'settings',
    keyColumn: 'key',
    key: key,
    at: resolveStamp(at),
    deleted: true,
  );

  Future<Map<String, Object?>> all() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((t) => t.deletedAt.isNull())).get();
    return {for (final r in rows) r.key: jsonDecode(r.valueJson)};
  }
}
