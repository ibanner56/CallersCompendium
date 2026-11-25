import 'package:drift/drift.dart';

import '../../model/event_rule.dart';
import '../../util/uuid.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import 'saved_search_repository.dart' show SavedSearchUse;

/// The [SavedSearchUse.kind] of an event rule (#2340), so a refused delete of
/// a saved search can name each rule that uses it.
const String eventRuleUseKind = 'eventRule';

/// Most live event rules [EventRuleRepository.create] lets a device hold.
const int maxEventRules = 500;

/// Thrown when a rule cannot be stored: an empty id or saved-search id, a
/// count or nickname over its bound, or a quantifier or scope this build does not
/// know (the editor writes only known ones).
class EventRuleInvalid implements Exception {
  const EventRuleInvalid(this.field);

  /// `id`, `savedSearchId`, `quantifier`, `scope`, `count`, `nickname` or
  /// `limit`.
  final String field;

  @override
  String toString() => 'EventRuleInvalid($field)';
}

/// The caller's event rules (#2340), one row each in `event_rules`.
///
/// A rule names a saved search by id; it never copies the search. Deleting a
/// rule tombstones it, so the deletion syncs and Undo ([restore]) brings it
/// back; a rule in that state does not count as using its saved search
/// ([usesOfSavedSearch]). A program's applied rules are its own field
/// (`Program.eventRuleIds`), which deleting a rule leaves alone: an id whose
/// rule is gone is ignored, and an Undo applies it again.
class EventRuleRepository {
  EventRuleRepository(this._db);

  final CompendiumDatabase _db;

  /// Every live rule in the caller's order ([EventRule.position], then id);
  /// with [includeDeleted], tombstones too.
  Future<List<EventRule>> listAll({bool includeDeleted = false}) async {
    final query = includeDeleted ? _db.select(_db.eventRules) : _live();
    final rows = await (query..orderBy(_order)).get();
    return [for (final row in rows) fromRow(row)];
  }

  /// [listAll] as a stream that re-emits on every change.
  Stream<List<EventRule>> watchAll() => (_live()..orderBy(_order)).watch().map(
    (rows) => [for (final row in rows) fromRow(row)],
  );

  static final _order = <OrderingTerm Function($EventRulesTable)>[
    (t) => OrderingTerm.asc(t.position),
    (t) => OrderingTerm.asc(t.id),
  ];

  /// The live rule [id], or null.
  Future<EventRule?> get(String id) async {
    final row = await (_live()..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : fromRow(row);
  }

  /// The live rules [ids] names, in [ids]' order; an id with no live rule is
  /// left out.
  Future<List<EventRule>> getMany(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_live()..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final row in rows) row.id: fromRow(row)};
    return [for (final id in ids) ?byId[id]];
  }

  /// The live rules that use the saved search [savedSearchId], for the
  /// saved-search delete guard. A rule in the trash does not count.
  Future<List<SavedSearchUse>> usesOfSavedSearch(String savedSearchId) async {
    final rows =
        await (_live()
              ..where((t) => t.savedSearchId.equals(savedSearchId))
              ..orderBy(_order))
            .get();
    return [
      for (final row in rows)
        SavedSearchUse(
          kind: eventRuleUseKind,
          label: row.nickname ?? '',
          id: row.id,
        ),
    ];
  }

  /// Adds a new rule under a fresh id, after every other rule. Throws
  /// [EventRuleInvalid] for a rule it cannot store, and with field `limit`
  /// when this device already holds [maxEventRules].
  Future<EventRule> create({
    required String savedSearchId,
    required EventRuleQuantifier quantifier,
    int count = 0,
    required EventRuleScope scope,
    String? nickname,
    DateTime? at,
  }) => _db.transaction(() async {
    final live = await _live().get();
    if (live.length >= maxEventRules) throw const EventRuleInvalid('limit');
    final last = live.fold<int>(
      -1,
      (max, row) => row.position > max ? row.position : max,
    );
    final rule = EventRule.of(
      id: uuidV4(),
      savedSearchId: savedSearchId,
      quantifier: quantifier,
      count: count,
      scope: scope,
      nickname: nickname,
      position: last + 1,
    );
    await save(rule, at: at);
    return (await get(rule.id))!;
  });

  /// Writes [rule] under its own id: an edit, or a new rule. Throws
  /// [EventRuleInvalid] for one it cannot store.
  Future<void> save(EventRule rule, {DateTime? at}) async {
    _check(rule);
    final now = resolveStamp(at);
    await _db.transaction(() async {
      await _db
          .into(_db.eventRules)
          .insertOnConflictUpdate(_companion(rule, now));
      await applyUpsertExistence(
        _db,
        table: _db.eventRules,
        keyColumn: 'id',
        key: rule.id,
        at: now,
      );
    });
  }

  /// Puts the live rules in [ids]' order (the manager's reorder). A rule not
  /// named keeps its place after them.
  Future<void> reorder(List<String> ids, {DateTime? at}) async {
    final now = resolveStamp(at);
    await _db.transaction(() async {
      final rules = await listAll();
      final order = [
        ...ids.where((id) => rules.any((r) => r.id == id)),
        for (final r in rules)
          if (!ids.contains(r.id)) r.id,
      ];
      for (var i = 0; i < order.length; i++) {
        final rule = rules.firstWhere((r) => r.id == order[i]);
        if (rule.position == i) continue;
        await save(rule.copyWith(position: i), at: now);
      }
    });
  }

  /// Deletes the rule [id] softly (a tombstone that syncs). A no-op when there
  /// is none.
  Future<void> delete(String id, {DateTime? at}) => stampExistenceTransition(
    _db,
    table: _db.eventRules,
    keyColumn: 'id',
    key: id,
    at: resolveStamp(at),
    deleted: true,
  );

  /// Brings back the rule [id] that [delete] tombstoned (Undo).
  Future<void> restore(String id, {DateTime? at}) => stampExistenceTransition(
    _db,
    table: _db.eventRules,
    keyColumn: 'id',
    key: id,
    at: resolveStamp(at),
    deleted: false,
  );

  /// Applies a validated inbound sync record, written as the peer sent it;
  /// the sync engine restores its timestamps after (sync-spec §6.7). A rule
  /// of a kind this build does not know is stored as it came.
  Future<void> writeFromSync(EventRule rule, {DateTime? at}) async {
    final now = resolveStamp(at);
    await _db
        .into(_db.eventRules)
        .insertOnConflictUpdate(_companion(rule, now));
  }

  /// Writes [rule] from a backup restore, stamped at the backup's creation
  /// time [backupCreatedAt] (SYNC-1) rather than causally.
  Future<void> upsertFromRestore(
    EventRule rule, {
    required DateTime backupCreatedAt,
  }) async {
    _checkStored(rule);
    final at = resolveStamp(backupCreatedAt);
    await _db.transaction(() async {
      await _db
          .into(_db.eventRules)
          .insertOnConflictUpdate(_companion(rule, at));
      await applyRestoredExistence(
        _db,
        table: _db.eventRules,
        keyColumn: 'id',
        key: rule.id,
        at: at,
        deleted: false,
      );
    });
  }

  /// Deletes the rule [id] softly for a backup restore that does not hold it,
  /// stamped at the backup's creation time [at].
  Future<void> deleteFromRestore(String id, {required DateTime at}) =>
      applyRestoredExistence(
        _db,
        table: _db.eventRules,
        keyColumn: 'id',
        key: id,
        at: resolveStamp(at),
        deleted: true,
      );

  /// [row] as the model, the stored quantifier and scope kept as text.
  static EventRule fromRow(EventRuleRow row) => EventRule(
    id: row.id,
    savedSearchId: row.savedSearchId,
    quantifierName: row.quantifier,
    count: row.count,
    scopeName: row.scope,
    nickname: row.nickname,
    position: row.position,
  );

  EventRulesCompanion _companion(EventRule rule, DateTime now) {
    final nickname = _nickname(rule.nickname);
    return EventRulesCompanion.insert(
      id: rule.id,
      savedSearchId: normalizeShareableText(rule.savedSearchId),
      quantifier: normalizeShareableText(rule.quantifierName),
      count: Value(rule.count),
      scope: normalizeShareableText(rule.scopeName),
      nickname: Value(
        nickname == null ? null : normalizeShareableText(nickname),
      ),
      position: Value(rule.position),
      updatedAt: Value(now),
    );
  }

  /// A nickname with invisible characters and edge spaces removed, or null
  /// when nothing is left.
  static String? _nickname(String? nickname) {
    if (nickname == null) return null;
    final text = sanitizeShareableText(nickname).trim();
    return text.isEmpty ? null : text;
  }

  /// What any stored rule must be: what a backup may hold.
  static void _checkStored(EventRule rule) {
    if (rule.id.trim().isEmpty) throw const EventRuleInvalid('id');
    if (rule.savedSearchId.trim().isEmpty) {
      throw const EventRuleInvalid('savedSearchId');
    }
    if (rule.quantifierName.isEmpty || rule.quantifierName.length > 64) {
      throw const EventRuleInvalid('quantifier');
    }
    if (rule.scopeName.isEmpty || rule.scopeName.length > 64) {
      throw const EventRuleInvalid('scope');
    }
    if (rule.count < 0 || rule.count > maxEventRuleCount) {
      throw const EventRuleInvalid('count');
    }
    if ((rule.nickname?.length ?? 0) > maxEventRuleNicknameLength) {
      throw const EventRuleInvalid('nickname');
    }
  }

  /// What the editor may write: a stored rule this build can check.
  static void _check(EventRule rule) {
    _checkStored(rule);
    if (rule.quantifier == null) throw const EventRuleInvalid('quantifier');
    if (rule.scope == null) throw const EventRuleInvalid('scope');
    if (!rule.isReadable) throw const EventRuleInvalid('count');
  }

  SimpleSelectStatement<$EventRulesTable, EventRuleRow> _live() =>
      _db.select(_db.eventRules)..where((t) => t.deletedAt.isNull());
}
