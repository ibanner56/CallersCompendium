import 'dart:convert';

import 'package:drift/drift.dart';

import '../../model/user_glossary.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';

/// Longest name a user glossary entry may have, in UTF-16 code units.
const int maxUserGlossaryNameLength = 200;

/// Longest definition, description or notes text, in UTF-16 code units.
const int maxUserGlossaryTextLength = 20000;

/// Most search keywords an entry may carry.
const int maxUserGlossaryKeywords = 32;

/// Thrown when an entry's required text is empty or a field is over its bound.
class UserGlossaryEntryInvalid implements Exception {
  const UserGlossaryEntryInvalid(this.field);

  /// `name`, `definition`, `description`, `keywords` or `notes`.
  final String field;

  @override
  String toString() => 'UserGlossaryEntryInvalid($field)';
}

/// The user's own glossary entries (#709).
///
/// Reads hand back every live entry, including one of a kind this build does
/// not know or whose payload no longer decodes: the caller decides how to show
/// it, and nothing here drops or rewrites it. Text is sanitised and
/// normalised on write (sync-spec §4.1, §4.6), as every shareable text column
/// is; canonicalizing role words is the caller's job, before it gets here.
class UserGlossaryRepository {
  UserGlossaryRepository(this._db);

  final CompendiumDatabase _db;

  /// Every live entry, oldest first; with [includeDeleted], tombstones too.
  Future<List<UserGlossaryEntry>> listAll({bool includeDeleted = false}) async {
    final query = includeDeleted
        ? _db.select(_db.userGlossaryEntries)
        : _live();
    final rows = await (query..orderBy([_order])).get();
    return [for (final row in rows) _toModel(row)];
  }

  /// [listAll] as a stream that re-emits on every change.
  Stream<List<UserGlossaryEntry>> watchAll() => (_live()..orderBy([_order]))
      .watch()
      .map((rows) => [for (final row in rows) _toModel(row)]);

  /// The live entry [id], or null.
  Future<UserGlossaryEntry?> getById(String id) async {
    final row = await (_live()..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// Creates or replaces [entry]. A new entry keeps [UserGlossaryEntry.
  /// createdAt]; an existing one keeps the creation time it already has, so
  /// an edit never moves it. Reviving a deleted entry by writing it again
  /// stamps the transition causally, as every synced kind does.
  Future<void> upsert(UserGlossaryEntry entry, {DateTime? at}) async {
    final now = resolveStamp(at);
    final name = _requiredText(entry.name, 'name', maxUserGlossaryNameLength);
    final definition = _requiredText(
      entry.definition,
      'definition',
      maxUserGlossaryTextLength,
    );
    final description = _requiredText(
      entry.description,
      'description',
      maxUserGlossaryTextLength,
    );
    final keywords = [
      for (final keyword in entry.keywords)
        if (_text(keyword) case final k when k.isNotEmpty) k,
    ];
    if (keywords.length > maxUserGlossaryKeywords ||
        keywords.any((k) => k.length > maxUserGlossaryNameLength)) {
      throw const UserGlossaryEntryInvalid('keywords');
    }
    final notes = entry.notes == null ? null : _text(entry.notes!);
    if (notes != null && notes.length > maxUserGlossaryTextLength) {
      throw const UserGlossaryEntryInvalid('notes');
    }
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.userGlossaryEntries,
      )..where((t) => t.id.equals(entry.id))).getSingleOrNull();
      await _db
          .into(_db.userGlossaryEntries)
          .insertOnConflictUpdate(
            UserGlossaryEntriesCompanion.insert(
              id: entry.id,
              kind: entry.kindName,
              name: name,
              definition: definition,
              description: description,
              keywordsJson: Value(jsonEncode(keywords)),
              notes: Value(notes == null || notes.isEmpty ? null : notes),
              payloadJson: Value(
                entry.payload == null ? null : jsonEncode(entry.payload),
              ),
              createdAt: existing?.createdAt ?? asUtc(entry.createdAt),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: _db.userGlossaryEntries,
        keyColumn: 'id',
        key: entry.id,
        at: now,
      );
    });
  }

  /// Deletes entry [id] softly, leaving a tombstone that sync carries.
  Future<void> delete(String id, {DateTime? at}) => stampExistenceTransition(
    _db,
    table: _db.userGlossaryEntries,
    keyColumn: 'id',
    key: id,
    at: resolveStamp(at),
    deleted: true,
  );

  SimpleSelectStatement<$UserGlossaryEntriesTable, UserGlossaryEntryRow>
  _live() =>
      _db.select(_db.userGlossaryEntries)..where((t) => t.deletedAt.isNull());

  static OrderingTerm _order($UserGlossaryEntriesTable t) =>
      OrderingTerm.asc(t.createdAt);

  static UserGlossaryEntry _toModel(UserGlossaryEntryRow row) =>
      UserGlossaryEntry(
        id: row.id,
        kindName: row.kind,
        name: row.name,
        definition: row.definition,
        description: row.description,
        keywords: _decodeKeywords(row.keywordsJson),
        notes: row.notes,
        payload: _decodeJson(row.payloadJson),
        createdAt: asUtc(row.createdAt),
      );

  static List<String> _decodeKeywords(String raw) {
    final decoded = _decodeJson(raw);
    if (decoded is! List) return const [];
    return [
      for (final k in decoded)
        if (k is String) k,
    ];
  }

  /// Stored JSON, or null when it does not decode. The row is kept either
  /// way; a payload that does not decode reads as a broken entry.
  static Object? _decodeJson(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  static String _text(String raw) =>
      normalizeShareableText(sanitizeShareableText(raw).trim());

  static String _requiredText(String raw, String field, int max) {
    final text = _text(raw);
    if (text.isEmpty || text.length > max) {
      throw UserGlossaryEntryInvalid(field);
    }
    return text;
  }
}

/// The user's notes on shipped figures (#709).
class FigureNoteRepository {
  FigureNoteRepository(this._db);

  final CompendiumDatabase _db;

  /// Every live note; with [includeDeleted], tombstones too.
  Future<List<FigureNote>> listAll({bool includeDeleted = false}) async {
    final rows = await (includeDeleted ? _db.select(_db.figureNotes) : _live())
        .get();
    return [for (final row in rows) _toModel(row)];
  }

  /// [listAll] as a stream that re-emits on every change.
  Stream<List<FigureNote>> watchAll() =>
      _live().watch().map((rows) => [for (final row in rows) _toModel(row)]);

  /// The live note on [figureId], or null.
  Future<FigureNote?> get(String figureId) async {
    final row = await (_live()..where((t) => t.figureId.equals(figureId)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// Sets the note on [figureId]. Empty text deletes it.
  Future<void> set(String figureId, String notes, {DateTime? at}) async {
    final now = resolveStamp(at);
    final text = normalizeShareableText(sanitizeShareableText(notes).trim());
    if (text.length > maxUserGlossaryTextLength) {
      throw const UserGlossaryEntryInvalid('notes');
    }
    if (text.isEmpty) return delete(figureId, at: now);
    await _db.transaction(() async {
      await _db
          .into(_db.figureNotes)
          .insertOnConflictUpdate(
            FigureNotesCompanion.insert(
              figureId: figureId,
              notes: text,
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: _db.figureNotes,
        keyColumn: 'figure_id',
        key: figureId,
        at: now,
      );
    });
  }

  /// Deletes the note on [figureId] softly. A no-op when there is none.
  Future<void> delete(String figureId, {DateTime? at}) =>
      stampExistenceTransition(
        _db,
        table: _db.figureNotes,
        keyColumn: 'figure_id',
        key: figureId,
        at: resolveStamp(at),
        deleted: true,
      );

  SimpleSelectStatement<$FigureNotesTable, FigureNoteRow> _live() =>
      _db.select(_db.figureNotes)..where((t) => t.deletedAt.isNull());

  static FigureNote _toModel(FigureNoteRow row) =>
      FigureNote(figureId: row.figureId, notes: row.notes);
}
