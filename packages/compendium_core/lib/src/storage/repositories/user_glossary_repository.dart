import 'dart:convert';

import 'package:drift/drift.dart';

import '../../model/user_glossary.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';
import 'sync_local_repository.dart';
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

/// The most the user's glossary (entries and figure notes together) may hold
/// when written through the editor, counted as [glossaryRowBytes]: the UTF-8
/// bytes of every stored text column (an entry's id and kind and a note's
/// figure id included) plus [kGlossaryRowOverheadBytes] a row. A write that
/// would take the total past it is refused as [UserGlossaryEntryInvalid] or
/// [FigureNoteInvalid]; rows already there are never touched. Two paths are
/// deliberately exempt: a row that arrives by sync
/// ([UserGlossaryRepository.writeFromSync]) and a restore from a backup
/// ([UserGlossaryRepository.upsertFromRestore]). Both bring in data the user
/// already had, and refusing it would either stop devices converging or lose
/// the newest entries on the operation meant to bring data back; the backup
/// being restored already fit the file cap. A glossary they leave over the
/// budget can be edited down and pruned, not grown.
///
/// Why a total, and why 4 MiB. Each field has its own bound, but 5000 entries
/// at those bounds come to gigabytes, while a backup is one file that restore
/// reads into memory, capped at 50 MiB (`kMaxBackupFileBytes`, in the app
/// package), and export refuses to write past it. A glossary that outgrew the
/// cap left the user unable to back up at all, so the bound has to hold when
/// the data is written.
///
/// The arithmetic, worst case. The backup container is double-encoded (its
/// payload is the document JSON as a string), so a `"` or `\` stored as 1 byte
/// is written as 4 (`\\\"` for a quote); a newline, tab or return as 3; text
/// outside ASCII as itself, since `jsonEncode` does not escape it; the control
/// characters that would cost 7 are stripped on write. Keywords and payload are
/// stored as JSON already, so they cost at most 2 a byte. Four times the
/// counted bytes therefore bounds what the glossary adds to the file: 4 MiB x 4
/// = 16 MiB, under a third of the 50 MiB cap, which leaves 34 MiB for
/// everything else (the app's own estimate is about 30 MiB for a lean
/// 20,000-dance library). The bound limits what the glossary can add: a
/// collection already near the cap by itself can still reach it, and the exempt
/// paths above can take a glossary past it (a restore or sync merge unions this
/// glossary with another, and nothing bounds that sum).
///
/// How much fits. An entry at every per-field maximum counts for around a MiB
/// (its text bounds allow about 0.2 MiB of UTF-8, and its payload up to
/// [maxUserGlossaryPayloadLength] code units), so only a handful of those fit;
/// the payload of a compound at its own bounds is far below that length, and an
/// entry with a sentence each of definition and description counts for about
/// 1 KB, so a few thousand fit.
///
/// Rejected: a budget at export. The user would still be unable to back up,
/// and the only way out would be deleting entries blind.
const int maxUserGlossaryBytes = 4 * 1024 * 1024;

/// Counted against [maxUserGlossaryBytes] for each entry and each figure note
/// on top of its text: the keys and timestamp the backup writes around it
/// (about 150 bytes before the container escapes it again; the id, kind and
/// figure id are counted as text), rounded up. A test measures the real
/// envelope of tiny rows against it.
const int kGlossaryRowOverheadBytes = 512;

/// What a glossary entry or figure note holding these stored text values counts
/// for against [maxUserGlossaryBytes]; a null counts as empty.
///
/// The repositories total the same quantity in SQL over the stored columns
/// (`LENGTH(CAST(col AS BLOB))` is a column's UTF-8 byte length), so this is
/// what a row weighs once written.
int glossaryRowBytes(Iterable<String?> storedTexts) {
  var total = kGlossaryRowOverheadBytes;
  for (final text in storedTexts) {
    if (text != null) total += utf8.encode(text).length;
  }
  return total;
}

/// Thrown when an entry's required text is empty, a field is over its bound,
/// its id or kind is not an identifier sync can carry, or storing it would take
/// the glossary past [maxUserGlossaryBytes].
class UserGlossaryEntryInvalid implements Exception {
  const UserGlossaryEntryInvalid(this.field);

  /// The write would take the glossary past [maxUserGlossaryBytes]. Nothing is
  /// wrong with the entry itself: the rest of the glossary has no room for it.
  const UserGlossaryEntryInvalid.overBudget() : field = budgetField;

  /// The [field] of [UserGlossaryEntryInvalid.overBudget].
  static const String budgetField = 'budget';

  /// `id`, `kind`, `name`, `definition`, `description`, `keywords`, `notes`,
  /// `payload` or [budgetField].
  final String field;

  /// Whether this is [UserGlossaryEntryInvalid.overBudget], not a field bound.
  bool get isOverBudget => field == budgetField;

  @override
  String toString() => 'UserGlossaryEntryInvalid($field)';
}

/// Thrown when a note on a shipped figure is over its bound, or its figure id
/// is not an identifier sync can carry, or, with [overBudget], when the
/// glossary has no room for it ([maxUserGlossaryBytes]).
class FigureNoteInvalid implements Exception {
  const FigureNoteInvalid({this.overBudget = false});

  /// The note is within its own bound; the glossary has no room for it.
  final bool overBudget;

  @override
  String toString() =>
      overBudget ? 'FigureNoteInvalid(budget)' : 'FigureNoteInvalid';
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
///
/// The whole glossary, entries and [FigureNoteRepository] notes together, is
/// held to [maxBytes] ([maxUserGlossaryBytes]) when written: see [upsert].
class UserGlossaryRepository {
  UserGlossaryRepository(
    this._db, {
    this.onUserFigureChanged,
    this.maxBytes = maxUserGlossaryBytes,
  });

  final CompendiumDatabase _db;

  /// The glossary's byte budget; only a test passes anything but the default.
  final int maxBytes;

  /// Called, inside the write's transaction, after [upsert] or [delete]
  /// writes an entry that is or was a figure of your own (#1023): the dance
  /// index renders their uses from it, so the dances using it are reindexed.
  /// An inbound sync apply needs nothing of its own: after each batch it
  /// reindexes the dances using every glossary entry it wrote, from the live
  /// figures (#1920, `CompendiumSyncStorage.reindexDerivedAfterApply`).
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
  ///
  /// Refused as [UserGlossaryEntryInvalid.overBudget] when the write would take
  /// the glossary past [maxBytes] *and* make this entry larger than it was, as
  /// stored. A write that does not grow its entry always goes through, so a
  /// glossary already over the budget (one from before there was a budget, a
  /// restored backup, or one that sync filled) can still be edited down and
  /// pruned; it just cannot grow.
  Future<void> upsert(UserGlossaryEntry entry, {DateTime? at}) =>
      _upsert(entry, at: at, enforceBudget: true);

  /// [upsert] for restoring a backup, which is not held to [maxBytes]: the
  /// file already fit the backup size cap and was exportable, so refusing its
  /// tail would lose the newest entries on the one operation meant to bring
  /// data back, where the budget exists to stop the glossary growing past what
  /// can be exported. A glossary a restore leaves over the budget can be
  /// edited down and pruned, not grown. Every per-field bound still applies.
  /// Only the restore calls this; the editor goes through [upsert].
  Future<void> upsertFromRestore(UserGlossaryEntry entry) =>
      _upsert(entry, enforceBudget: false);

  Future<void> _upsert(
    UserGlossaryEntry entry, {
    DateTime? at,
    required bool enforceBudget,
  }) async {
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
    // The description is optional (stored empty when there is none).
    final description = _text(entry.description);
    if (description.length > maxUserGlossaryTextLength) {
      throw const UserGlossaryEntryInvalid('description');
    }
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
      final before = enforceBudget
          ? await _rowBytes(_db, entryId: entry.id)
          : 0;
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
      // Measured on what is stored, after the write, so what is counted is
      // what the backup will carry (not a second computation of it); throwing
      // rolls the whole write back. Before the user-figure hook, so a refused
      // write does not first re-index every dance that uses the figure.
      if (enforceBudget) {
        final after = await _glossaryBytes(_db, entryId: entry.id);
        if (after.total > maxBytes && after.row > before) {
          throw const UserGlossaryEntryInvalid.overBudget();
        }
      }
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
  /// change what an inbound apply does. It is not held to [maxBytes]: a peer's
  /// row is applied or the two devices never converge, and the peer's own
  /// glossary usually was within the budget when it was written (an older build
  /// had none, and a peer's can itself have been filled by sync or restore). A glossary that sync
  /// fills past the budget can still be exported (up to the backup file cap)
  /// and edited down, but not grown. The entry is written as the peer sent
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
  ///
  /// [permanent] erases the row instead, leaving nothing behind to publish:
  /// for undoing a write this device just made, such as an import's (#1023),
  /// so the entry is as if it had never been added and a later import of the
  /// same id finds no deletion in its way. An entry a publication has already
  /// named is tombstoned all the same, so peers keep the deletion.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) =>
      _db.transaction(() async {
        if (permanent &&
            !await isPublishedSyncRecord(
              _db,
              kind: SyncRecordKind.glossaryEntry,
              recordId: id,
            )) {
          final row = await (_db.select(
            _db.userGlossaryEntries,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          await (_db.delete(
            _db.userGlossaryEntries,
          )..where((t) => t.id.equals(id))).go();
          await _userFigureChanged(
            id,
            wasOrIs: row?.kind == UserGlossaryEntryKind.customFigure.name,
          );
          return;
        }
        await _softDelete(id, at: at);
      });

  Future<void> _softDelete(String id, {DateTime? at}) async {
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
  }

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

// SQL for what a live row counts for against [maxUserGlossaryBytes]: the same
// quantity as [glossaryRowBytes], over the stored columns. `LENGTH` of a BLOB
// is its byte length, and a text column cast to one is its UTF-8 encoding.
const String _entryBytesSql =
    '$kGlossaryRowOverheadBytes'
    ' + LENGTH(CAST(id AS BLOB)) + LENGTH(CAST(kind AS BLOB))'
    ' + LENGTH(CAST(name AS BLOB)) + LENGTH(CAST(definition AS BLOB))'
    ' + LENGTH(CAST(description AS BLOB)) + LENGTH(CAST(keywords_json AS BLOB))'
    ' + COALESCE(LENGTH(CAST(notes AS BLOB)), 0)'
    ' + COALESCE(LENGTH(CAST(payload_json AS BLOB)), 0)';
const String _noteBytesSql =
    '$kGlossaryRowOverheadBytes'
    ' + LENGTH(CAST(figure_id AS BLOB)) + LENGTH(CAST(notes AS BLOB))';

/// What the one live row named by [entryId] or [figureId] counts for; 0 when
/// there is none, or it is deleted.
Future<int> _rowBytes(
  CompendiumDatabase db, {
  String? entryId,
  String? figureId,
}) async {
  final result = await db
      .customSelect(
        'SELECT'
        ' (SELECT COALESCE(SUM($_entryBytesSql), 0) FROM user_glossary_entries'
        '   WHERE deleted_at IS NULL AND id = ?)'
        ' + (SELECT COALESCE(SUM($_noteBytesSql), 0) FROM figure_notes'
        '   WHERE deleted_at IS NULL AND figure_id = ?) AS own',
        variables: [Variable<String>(entryId), Variable<String>(figureId)],
      )
      .getSingle();
  return result.read<int>('own');
}

/// The bytes every live glossary entry and figure note counts for together
/// ([total]), and what the one row named by [entryId] or [figureId] counts for
/// ([row], as [_rowBytes]). Deleted rows are not in the backup, so they count
/// for nothing.
Future<({int total, int row})> _glossaryBytes(
  CompendiumDatabase db, {
  String? entryId,
  String? figureId,
}) async {
  final result = await db
      .customSelect(
        'SELECT'
        ' (SELECT COALESCE(SUM($_entryBytesSql), 0) FROM user_glossary_entries'
        '   WHERE deleted_at IS NULL)'
        ' + (SELECT COALESCE(SUM($_noteBytesSql), 0) FROM figure_notes'
        '   WHERE deleted_at IS NULL) AS total,'
        ' (SELECT COALESCE(SUM($_entryBytesSql), 0) FROM user_glossary_entries'
        '   WHERE deleted_at IS NULL AND id = ?)'
        ' + (SELECT COALESCE(SUM($_noteBytesSql), 0) FROM figure_notes'
        '   WHERE deleted_at IS NULL AND figure_id = ?) AS own',
        variables: [Variable<String>(entryId), Variable<String>(figureId)],
      )
      .getSingle();
  return (total: result.read<int>('total'), row: result.read<int>('own'));
}

/// The user's notes on shipped figures (#709). They count against the same
/// [maxUserGlossaryBytes] as the glossary entries.
class FigureNoteRepository {
  FigureNoteRepository(this._db, {this.maxBytes = maxUserGlossaryBytes});

  final CompendiumDatabase _db;

  /// The glossary's byte budget; only a test passes anything but the default.
  final int maxBytes;

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
  /// [FigureNoteInvalid]. So is a note that would take the glossary past
  /// [maxBytes] and is larger than the one it replaces
  /// ([FigureNoteInvalid.overBudget]); a note that does not grow always goes
  /// through, as [UserGlossaryRepository.upsert] does.
  Future<void> set(String figureId, String notes, {DateTime? at}) =>
      _set(figureId, notes, at: at, enforceBudget: true);

  /// [set] for restoring a backup, which is not held to [maxBytes], for the
  /// reason [UserGlossaryRepository.upsertFromRestore] gives. The length bound
  /// still applies. Only the restore calls this.
  Future<void> setFromRestore(String figureId, String notes) =>
      _set(figureId, notes, enforceBudget: false);

  Future<void> _set(
    String figureId,
    String notes, {
    DateTime? at,
    required bool enforceBudget,
  }) async {
    final now = resolveStamp(at);
    if (!_isSyncableIdentifier(figureId)) throw const FigureNoteInvalid();
    final text = normalizeShareableText(sanitizeShareableText(notes).trim());
    if (text.length > maxUserGlossaryTextLength) {
      throw const FigureNoteInvalid();
    }
    if (text.isEmpty) return delete(figureId, at: now);
    await _db.transaction(() async {
      final before = enforceBudget
          ? await _rowBytes(_db, figureId: figureId)
          : 0;
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
      // Measured after the write, on what is stored; throwing rolls it back.
      if (!enforceBudget) return;
      final after = await _glossaryBytes(_db, figureId: figureId);
      if (after.total > maxBytes && after.row > before) {
        throw const FigureNoteInvalid(overBudget: true);
      }
    });
  }

  /// Applies a validated inbound sync record (#709). Separate from [set] per
  /// sync-spec §6.7: the note is written as the peer sent it, never deleted
  /// for being empty, and the sync engine restores its timestamps after. Not
  /// held to [maxBytes], for the reason [UserGlossaryRepository.writeFromSync]
  /// gives.
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
