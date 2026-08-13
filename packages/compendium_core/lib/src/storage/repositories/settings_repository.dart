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
///
/// ## Before making `settings` a watched source (issue #768)
///
/// Nothing streams this table today. When something does, the obvious shape —
/// one stream over `settings`, feeding a screen that re-reads its preferences —
/// **self-triggers**, and the app already contains the writer that does it: the
/// program editor autosaves its in-progress draft into this table on a **500 ms
/// debounce while the user types**. A watcher on the whole table therefore wakes
/// twice a second during editing, and every wake reloads whatever that screen
/// derives from settings — the over-firing failure of issue #340, arrived at
/// from the opposite direction to the staleness #768 is about.
///
/// Deliberately described by behaviour rather than by the symbols that
/// implement it. This package does not depend on the app, so any private
/// identifier named here is one nothing in this repository can check: it would
/// not break a build when renamed, and a stale symbol makes a warning read as
/// out of date even while the hazard it describes is still live.
///
/// The two failures share one cause: a watched set chosen by *table* rather
/// than by what the consumer actually reads. So the fix is not to debounce the
/// stream — that trades a fast wrong answer for a slow one — but to scope the
/// subscription to the keys a consumer depends on, or to keep transient
/// per-screen state out of `settings` entirely. Whichever is chosen, the draft
/// key is the case to test against, because it is the highest-frequency writer
/// here by a wide margin.
///
/// The migration-sweep writes in `CompendiumRepositories` are already visible
/// to watchers (#768), so they need no further work — but they are also, by
/// design, the only writes to this table that fire during startup, which is
/// exactly when a new watcher is most likely to be attached and least likely to
/// be observed misbehaving.
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
        table: _db.settings,
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
  ///
  /// [permanent] erases the row instead, and exists because a tombstone is only
  /// worth its storage when there is somebody to inform. **A key that can never
  /// travel has no peer to tell**, so tombstoning it is pure cost — and for the
  /// editor autosave drafts (`editor_draft:` / `program_editor_draft:`) that
  /// cost is not marginal: a draft is cleared on every save and every discard,
  /// and each tombstone retains the whole draft blob. Measured at 200 edit
  /// cycles that is 200 rows holding ~352 KB, invisible to [all] and to backup
  /// export, with no retention sweep to reclaim it — unbounded growth in
  /// proportion to how much the user works.
  ///
  /// That is the rule for anything added later, not just a carve-out for these
  /// two prefixes: pass [permanent] when the key is device-scoped scratch, and
  /// leave it alone when the removal is a state change a peer would need to
  /// learn about. A discarded draft is not a decision; clearing a preference
  /// is.
  Future<void> remove(String key, {DateTime? at, bool permanent = false}) {
    if (permanent) {
      return (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
    }
    return stampExistenceTransition(
      _db,
      table: _db.settings,
      keyColumn: 'key',
      key: key,
      at: resolveStamp(at),
      deleted: true,
    );
  }

  Future<Map<String, Object?>> all() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((t) => t.deletedAt.isNull())).get();
    return {for (final r in rows) r.key: jsonDecode(r.valueJson)};
  }
}
