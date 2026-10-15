import 'dart:convert';

import 'package:drift/drift.dart';

import '../../model/user_glossary.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';
import '../../util/json_depth.dart';

/// Longest name a user glossary entry may have, in UTF-16 code units.
const int maxUserGlossaryNameLength = 200;

/// Longest definition, description or notes text, in UTF-16 code units.
const int maxUserGlossaryTextLength = 20000;

/// Most search keywords an entry may carry.
const int maxUserGlossaryKeywords = 32;

/// Longest payload an entry may carry, as encoded JSON in UTF-16 code units.
/// A compound at its own bounds (64 figures, 16 parameters) is far below it.
const int maxUserGlossaryPayloadLength = 256 * 1024;

/// Deepest nesting of lists and maps a payload may have. A compound needs
/// about five levels; the bound is checked before anything recursive (JSON
/// encoding, normalisation) touches the payload, so a hand-edited backup
/// nested deep enough to overflow the stack is refused, not crashed on.
const int maxUserGlossaryPayloadDepth = 32;

/// Whether [value] can be an entry's id or kind, or a note's figure id: not
/// empty, within [maxUserGlossaryNameLength], and already in normalised form.
/// The sync decoder and inbound admission refuse anything else, so a row
/// stored with one would be published and refused by every peer, every pass
/// (#709). Stored as given rather than normalised, since the id is identity.
bool _isSyncableIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= maxUserGlossaryNameLength &&
    normalizeShareableText(value) == value;

/// Whether the payload [text] parses as JSON. A stored payload need not: one
/// that does not is kept as text and read as a broken entry (#709).
bool userGlossaryPayloadIsJson(String text) {
  try {
    jsonDecode(text);
    return true;
  } on FormatException {
    return false;
  }
}

/// Thrown when an entry's required text is empty, a field is over its bound,
/// or its id or kind is not an identifier sync can carry.
class UserGlossaryEntryInvalid implements Exception {
  const UserGlossaryEntryInvalid(this.field);

  /// `id`, `kind`, `name`, `definition`, `description`, `keywords`, `notes`
  /// or `payload`.
  final String field;

  @override
  String toString() => 'UserGlossaryEntryInvalid($field)';
}

/// Thrown when a note on a shipped figure is over its bound, or its figure id
/// is not an identifier sync can carry.
class FigureNoteInvalid implements Exception {
  const FigureNoteInvalid();

  @override
  String toString() => 'FigureNoteInvalid';
}

/// The user's own glossary entries (#709).
///
/// Reads hand back every live entry, including one of a kind this build does
/// not know or whose payload no longer decodes as a definition: the caller
/// decides how to show it, and reading never drops or rewrites it. (A payload
/// whose text is not JSON at all reads as none, and so does not survive a
/// backup, which carries the decoded payload; sync carries the text.) Text is
/// sanitised and normalised on write (sync-spec §4.1, §4.6), as every
/// shareable text column is; canonicalizing role words is the caller's job,
/// before it gets here.
class UserGlossaryRepository {
  UserGlossaryRepository(this._db, {this.onUserFigureChanged});

  final CompendiumDatabase _db;

  /// Called, inside the write's transaction, after [upsert] or [delete]
  /// writes an entry that is or was a figure of your own (#1023): the dance
  /// index renders their uses from it, so the dances using it are reindexed.
  /// An inbound sync apply reindexes once its timestamps have landed instead
  /// (`CompendiumSyncStorage`).
  final Future<void> Function(String id)? onUserFigureChanged;

  Future<void> _userFigureChanged(String id, {required bool wasOrIs}) async {
    if (wasOrIs) await onUserFigureChanged?.call(id);
  }

  /// Every live entry, oldest first; with [includeDeleted], tombstones too.
  Future<List<UserGlossaryEntry>> listAll({bool includeDeleted = false}) async {
    final query = includeDeleted
        ? _db.select(_db.userGlossaryEntries)
        : _live();
    final rows = await (query..orderBy(_order)).get();
    return [for (final row in rows) _toModel(row)];
  }

  /// [listAll] as a stream that re-emits on every change.
  Stream<List<UserGlossaryEntry>> watchAll() => (_live()..orderBy(_order))
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
  /// stamps the transition causally, as every synced kind does. An id or kind
  /// sync could not carry (empty, over [maxUserGlossaryNameLength], or not
  /// normalised) is refused as [UserGlossaryEntryInvalid], so a restored
  /// backup cannot store a row every peer would refuse.
  Future<void> upsert(UserGlossaryEntry entry, {DateTime? at}) async {
    final now = resolveStamp(at);
    if (!_isSyncableIdentifier(entry.id)) {
      throw const UserGlossaryEntryInvalid('id');
    }
    if (!_isSyncableIdentifier(entry.kindName)) {
      throw const UserGlossaryEntryInvalid('kind');
    }
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
    final payloadJson = _payloadJson(entry.payload);
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.userGlossaryEntries,
      )..where((t) => t.id.equals(entry.id))).getSingleOrNull();
      // Every value is already normalised above; each is wrapped again here,
      // which changes nothing, so the normalisation ratchet
      // (normalisation_structure_test.dart) can see it at the write.
      await _db
          .into(_db.userGlossaryEntries)
          .insertOnConflictUpdate(
            UserGlossaryEntriesCompanion.insert(
              id: entry.id,
              kind: entry.kindName,
              name: normalizeShareableText(name),
              definition: normalizeShareableText(definition),
              description: normalizeShareableText(description),
              keywordsJson: Value(
                normalizeShareableJsonText(jsonEncode(keywords)),
              ),
              notes: Value(
                notes == null || notes.isEmpty
                    ? null
                    : normalizeShareableText(notes),
              ),
              payloadJson: Value(
                payloadJson == null
                    ? null
                    : normalizeShareableJsonText(payloadJson),
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
      await _userFigureChanged(
        entry.id,
        wasOrIs:
            entry.kindName == UserGlossaryEntryKind.customFigure.name ||
            existing?.kind == UserGlossaryEntryKind.customFigure.name,
      );
    });
  }

  /// Applies a validated inbound sync record (#709).
  ///
  /// Separate from [upsert] per sync-spec §6.7, so the editor's path cannot
  /// change what an inbound apply does. The entry is written as the peer sent
  /// it: its kind and payload text verbatim, whether or not this build can
  /// read them, and its creation time unchanged, since which of two entries
  /// sharing a name is flagged for rename is decided by it. Text is normalised
  /// as every shareable column is; admission and the sync decoder have already
  /// refused a body that normalising would change, so nothing is rewritten.
  /// The sync engine restores the record's timestamps after.
  Future<void> writeFromSync(
    StoredUserGlossaryEntry entry, {
    DateTime? at,
  }) async {
    final now = resolveStamp(at);
    final payload = entry.payloadJson;
    final notes = entry.notes;
    await _db
        .into(_db.userGlossaryEntries)
        .insertOnConflictUpdate(
          UserGlossaryEntriesCompanion.insert(
            id: entry.id,
            kind: entry.kind,
            name: normalizeShareableText(entry.name),
            definition: normalizeShareableText(entry.definition),
            description: normalizeShareableText(entry.description),
            keywordsJson: Value(
              normalizeShareableJsonText(jsonEncode(entry.keywords)),
            ),
            notes: Value(notes == null ? null : normalizeShareableText(notes)),
            // A payload that is not JSON at all is kept as text: it is an
            // entry this build reads as broken, never one it may drop.
            payloadJson: Value(
              payload == null
                  ? null
                  : userGlossaryPayloadIsJson(payload)
                  ? normalizeShareableJsonText(payload)
                  : normalizeShareableText(payload),
            ),
            createdAt: asUtc(entry.createdAt),
            updatedAt: Value(now),
          ),
        );
  }

  /// [row] as sync carries it: every stored column, the kind and payload
  /// text verbatim (#709).
  static StoredUserGlossaryEntry storedFromRow(UserGlossaryEntryRow row) =>
      StoredUserGlossaryEntry(
        id: row.id,
        kind: row.kind,
        name: row.name,
        definition: row.definition,
        description: row.description,
        keywords: _decodeKeywords(row.keywordsJson),
        notes: row.notes,
        payloadJson: row.payloadJson,
        createdAt: asUtc(row.createdAt),
      );

  /// Deletes entry [id] softly, leaving a tombstone for sync to carry.
  Future<void> delete(String id, {DateTime? at}) => _db.transaction(() async {
    await stampExistenceTransition(
      _db,
      table: _db.userGlossaryEntries,
      keyColumn: 'id',
      key: id,
      at: resolveStamp(at),
      deleted: true,
    );
    final row = await (_db.select(
      _db.userGlossaryEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await _userFigureChanged(
      id,
      wasOrIs: row?.kind == UserGlossaryEntryKind.customFigure.name,
    );
  });

  SimpleSelectStatement<$UserGlossaryEntriesTable, UserGlossaryEntryRow>
  _live() =>
      _db.select(_db.userGlossaryEntries)..where((t) => t.deletedAt.isNull());

  // created_at is stored to the second, so the id breaks a tie: entries made
  // in the same second still read back in one order on every device.
  static List<OrderingTerm Function($UserGlossaryEntriesTable)> get _order => [
    (t) => OrderingTerm.asc(t.createdAt),
    (t) => OrderingTerm.asc(t.id),
  ];

  /// The model of a stored [row], for readers outside this repository (the
  /// dance index reads the user's own figures, #1023).
  static UserGlossaryEntry modelFromRow(UserGlossaryEntryRow row) =>
      _toModel(row);

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

  /// [payload] as normalised JSON text, or null for none. Refused as
  /// [UserGlossaryEntryInvalid] when it cannot be stored: nested deeper than
  /// [maxUserGlossaryPayloadDepth], not encodable as JSON (a non-finite number
  /// from a hand-edited backup), two keys that normalise to one, or over
  /// [maxUserGlossaryPayloadLength].
  static String? _payloadJson(Object? payload) {
    if (payload == null) return null;
    if (userGlossaryPayloadDeeperThan(payload, maxUserGlossaryPayloadDepth)) {
      throw const UserGlossaryEntryInvalid('payload');
    }
    final String encoded;
    try {
      encoded = normalizeShareableJsonText(jsonEncode(payload));
    } on JsonUnsupportedObjectError {
      throw const UserGlossaryEntryInvalid('payload');
    } on ShareableJsonKeyCollision {
      throw const UserGlossaryEntryInvalid('payload');
    }
    if (encoded.length > maxUserGlossaryPayloadLength) {
      throw const UserGlossaryEntryInvalid('payload');
    }
    return encoded;
  }

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
    final query = includeDeleted ? _db.select(_db.figureNotes) : _live();
    final rows = await (query..orderBy([(t) => OrderingTerm.asc(t.figureId)]))
        .get();
    return [for (final row in rows) _toModel(row)];
  }

  /// [listAll] as a stream that re-emits on every change.
  Stream<List<FigureNote>> watchAll() =>
      (_live()..orderBy([(t) => OrderingTerm.asc(t.figureId)])).watch().map(
        (rows) => [for (final row in rows) _toModel(row)],
      );

  /// The live note on [figureId], or null.
  Future<FigureNote?> get(String figureId) async {
    final row = await (_live()..where((t) => t.figureId.equals(figureId)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// Sets the note on [figureId]. Empty text deletes it; text over
  /// [maxUserGlossaryTextLength], or a figure id sync could not carry (empty,
  /// over [maxUserGlossaryNameLength], or not normalised), is refused as
  /// [FigureNoteInvalid].
  Future<void> set(String figureId, String notes, {DateTime? at}) async {
    final now = resolveStamp(at);
    if (!_isSyncableIdentifier(figureId)) throw const FigureNoteInvalid();
    final text = normalizeShareableText(sanitizeShareableText(notes).trim());
    if (text.length > maxUserGlossaryTextLength) {
      throw const FigureNoteInvalid();
    }
    if (text.isEmpty) return delete(figureId, at: now);
    await _db.transaction(() async {
      await _db
          .into(_db.figureNotes)
          .insertOnConflictUpdate(
            FigureNotesCompanion.insert(
              figureId: figureId,
              notes: normalizeShareableText(text),
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

  /// Applies a validated inbound sync record (#709). Separate from [set] per
  /// sync-spec §6.7: the note is written as the peer sent it, never deleted
  /// for being empty, and the sync engine restores its timestamps after.
  Future<void> writeFromSync(FigureNote note, {DateTime? at}) async {
    final now = resolveStamp(at);
    await _db
        .into(_db.figureNotes)
        .insertOnConflictUpdate(
          FigureNotesCompanion.insert(
            figureId: note.figureId,
            notes: normalizeShareableText(note.notes),
            updatedAt: Value(now),
          ),
        );
  }

  /// [row] as sync carries it (#709).
  static FigureNote fromRow(FigureNoteRow row) => _toModel(row);

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

/// Whether [value] nests lists and maps more than [limit] deep, walked
/// without recursion, so a payload nested deep enough to overflow the stack
/// is refused before anything recursive touches it (#709).
bool userGlossaryPayloadDeeperThan(Object? value, int limit) =>
    jsonNestedDeeperThan(value, limit);
