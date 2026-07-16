import 'dart:typed_data';

import 'callers_companion_mapping.dart';
import 'fmp/fmp_reader.dart';

/// The Caller's Companion (CC) tables recovered from a `.USR` FileMaker file,
/// reshaped into source-agnostic value objects the import layer can act on.
///
/// This is the CC-schema-aware layer that sits on top of the generic
/// [readFmp12] container reader: it knows which CC tables/columns exist and how
/// they map to a [CcDanceRecord] (reused verbatim by
/// [mapCallersCompanionDance]) and to program-shaped [CcSet]/[CcSetItem]s. It
/// is **pure Dart** and **parse-never-fails**: a missing table/column yields an
/// empty result + a [warnings] note, never a throw.
///
/// ## Schema provenance
///
/// The CC table/column names are **confirmed against a real `CallersCompanion2`
/// `.USR` (FileMaker Pro 12)**: `Dance`, `Author`, `Set`, `SetItem` and their
/// columns were read directly from the file's catalog. Relational links use CC's
/// own key *fields* — `Dance.zk_Dance_ID`, `Set.zk_Set_ID`, and the matching
/// `SetItem.zk_Set_ID` / `SetItem.zk_Dance_ID` foreign keys — **not** FileMaker's
/// internal record ids (in the real file e.g. Dance record 5430 carries
/// `zk_Dance_ID=4`, and that `4` is what a `SetItem` references). Names are still
/// matched tolerantly (case-insensitive, token-based) so a slightly different CC
/// build degrades gracefully rather than failing.
class CcUsrArchive {
  CcUsrArchive({
    required this.dances,
    required this.sets,
    required this.warnings,
  });

  /// One entry per CC `Dance` row, in file order.
  final List<CcDanceEntry> dances;

  /// One entry per CC `Set` row, each carrying its ordered [CcSetItem]s.
  final List<CcSet> sets;

  /// Non-fatal notes (missing tables, guessed column names, reader warnings).
  final List<String> warnings;
}

/// A single CC `Dance` row: its CC relational id, the mapped [CcDanceRecord],
/// and the verbatim source column map (all CC `Dance` columns, including ones
/// this PR does not map — preserved so nothing is lost and follow-up phases
/// have the real values).
class CcDanceEntry {
  CcDanceEntry({
    required this.recordId,
    required this.record,
    required this.rawColumns,
  });

  /// The CC dance identity used as the dedupe key **and** the join key that
  /// `SetItem` rows reference: the value of CC's own `zk_Dance_ID` field (e.g.
  /// `"4"`), *not* FileMaker's internal record id. Falls back to the FileMaker
  /// record id only when `zk_Dance_ID` is missing/empty (flagged in warnings).
  final String recordId;
  final CcDanceRecord record;
  final Map<String, String> rawColumns;
}

/// A CC `Set` row reshaped toward the `Program` model.
class CcSet {
  CcSet({
    required this.recordId,
    this.title,
    this.eventDate,
    this.location,
    this.band,
    this.caller,
    this.dancerLevel,
    this.notes,
    required this.items,
  });

  final String recordId;
  final String? title;
  final String? eventDate;
  final String? location;
  final String? band;
  final String? caller;
  final String? dancerLevel;
  final String? notes;
  final List<CcSetItem> items;
}

/// A CC `SetItem` row reshaped toward the `ProgramSlot` model.
class CcSetItem {
  CcSetItem({
    required this.order,
    this.danceRecordId,
    this.breakText,
    this.isAlt = false,
    this.guestCaller,
    this.minutes,
  });

  /// The CC `Order` value (as stored — CC is 1-based), used only to **sequence**
  /// a set's items; falls back to insertion order when `Order` is missing or
  /// unparseable. It is a sort key, not a final slot position: `buildCcPrograms`
  /// sorts by it and then assigns each surviving slot its own 0-based
  /// [ProgramSlot.position].
  final int order;

  /// The CC `Dance` record id this slot plays, if it references a dance.
  final String? danceRecordId;

  /// Free-text slot content (a break/waltz/announcement) when the slot is not
  /// a dance reference.
  final String? breakText;
  final bool isAlt;
  final String? guestCaller;

  /// Planned minutes (CC `SetItem.Time`), best-effort; `null` when unparseable.
  final int? minutes;
}

/// The `sourceVersion` tag stamped by the `.USR` reader (distinct from the CC
/// text adapter's `cc-text-1`).
const String ccUsrSourceVersion = 'cc-usr-1';

/// Reads a Caller's Companion `.USR` file's bytes into a [CcUsrArchive].
///
/// Only a non-FileMaker/unsupported container throws ([FmpFormatException]);
/// everything else degrades to partial results + [CcUsrArchive.warnings].
CcUsrArchive readCcUsrArchive(Uint8List bytes) {
  final db = readFmp12(bytes);
  return extractCcUsrArchive(db);
}

/// Extracts the CC tables from an already-parsed [FmpDatabase]. Split out from
/// [readCcUsrArchive] so the CC-schema extraction can be unit-tested against a
/// hand-built [FmpDatabase] without crafting raw FileMaker bytes (the raw
/// container reader is validated separately against real files).
CcUsrArchive extractCcUsrArchive(FmpDatabase db) {
  final warnings = <String>[...db.warnings];
  final dances = _extractDances(db, warnings);
  final sets = _extractSets(db, warnings);
  return CcUsrArchive(dances: dances, sets: sets, warnings: warnings);
}

// --- Dance extraction ------------------------------------------------------

const List<String> _danceTableNames = ['Dance', 'Dances'];
const List<String> _bodyLabels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

List<CcDanceEntry> _extractDances(FmpDatabase db, List<String> warnings) {
  final table = _findTable(db, _danceTableNames);
  if (table == null) {
    warnings.add(
      'No Caller\'s Companion "Dance" table was found in the file; '
      'no dances were imported.',
    );
    return const [];
  }
  // CC references dances by its own `zk_Dance_ID` field value, not the FileMaker
  // record id, so that is the join/dedupe identity we expose.
  final danceIdCol = _findColumnByTokens(table, [
    ['dance', 'id'],
    ['danceid'],
  ]);
  final entries = <CcDanceEntry>[];
  var missingIdCount = 0;
  for (final rec in table.records) {
    final columns = _rowColumns(table, rec);
    final ccId = danceIdCol == null
        ? null
        : _CiColumns(columns).get(danceIdCol)?.trim();
    final recordId = (ccId == null || ccId.isEmpty) ? rec.id.toString() : ccId;
    if (ccId == null || ccId.isEmpty) missingIdCount++;
    entries.add(
      CcDanceEntry(
        recordId: recordId,
        record: ccDanceRecordFromColumns(columns),
        rawColumns: columns,
      ),
    );
  }
  if (missingIdCount > 0) {
    warnings.add(
      '$missingIdCount Caller\'s Companion dance row(s) had no "zk_Dance_ID"; '
      'used the FileMaker record id as a fallback identity (their program '
      'slots may not link).',
    );
  }
  return entries;
}

/// Builds a [CcDanceRecord] from a case-insensitive CC `Dance` column map.
/// Shared by the `.USR` reader (columns from the binary) and the adapter's
/// `parse` step (columns from the fetched JSON), so both interpret CC the same.
CcDanceRecord ccDanceRecordFromColumns(Map<String, String> columns) {
  final lookup = _CiColumns(columns);

  final authors = [
    lookup.get('Author1'),
    lookup.get('Author2'),
  ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

  final formation = lookup.firstNonEmpty([
    'ContraForm',
    'Formation',
    'FormationOther',
  ]);
  final progression = lookup.firstNonEmpty(['Progression', 'ProgressionOther']);

  var level = lookup.get('Level');
  if ((level == null || level.trim().isEmpty) &&
      _isTruthy(lookup.get('Mixed Level'))) {
    level = 'Mixed';
  }

  final body = <CcBodySection>[];
  for (final label in _bodyLabels) {
    final raw = lookup.get(label);
    if (raw == null || raw.trim().isEmpty) continue;
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isNotEmpty) body.add(CcBodySection(label: label, lines: lines));
  }

  final userFields = <CcUserField>[];
  for (var i = 1; i <= 3; i++) {
    final value = lookup.get('UserDefined_$i');
    if (value == null || value.trim().isEmpty) continue;
    final label = lookup.get('UserDefined_${i}_Name');
    userFields.add(
      CcUserField(
        label: (label == null || label.trim().isEmpty)
            ? 'User field $i'
            : label.trim(),
        value: value,
      ),
    );
  }

  return CcDanceRecord(
    name: lookup.get('Name'),
    authors: authors,
    type: lookup.firstNonEmpty(['Type', 'SubType']),
    formation: formation,
    level: level,
    progression: progression,
    music: lookup.get('Music'),
    notes: lookup.get('Credits'),
    composed: lookup.get('DateComposed'),
    revised: lookup.get('DateRevised'),
    rating: lookup.get('Rating'),
    userFields: userFields,
    body: body,
  );
}

// --- Set / SetItem extraction ---------------------------------------------

const List<String> _setTableNames = ['Set', 'Sets', 'Program', 'Programs'];
const List<String> _setItemTableNames = ['SetItem', 'SetItems', 'Set_Item'];

List<CcSet> _extractSets(FmpDatabase db, List<String> warnings) {
  final setTable = _findTable(db, _setTableNames);
  if (setTable == null) {
    warnings.add(
      'No Caller\'s Companion "Set" table was found; no programs were '
      'imported (the dance import is unaffected).',
    );
    return const [];
  }
  final itemTable = _findTable(db, _setItemTableNames);
  if (itemTable == null) {
    warnings.add(
      'No "SetItem" table was found; sets were imported without their items.',
    );
  }

  // CC joins SetItem→Set on the `zk_Set_ID` *field* value (not the FileMaker
  // record id), so we key each set by its own `zk_Set_ID` and group items by
  // the matching SetItem foreign key.
  final setIdCol = _findColumnByTokens(setTable, [
    ['set', 'id'],
    ['setid'],
  ]);
  // CC Sets have no title/name column; the program title is derived downstream
  // from Location/Date.

  final items = <String, List<CcSetItem>>{};
  if (itemTable != null) {
    final setFk = _findColumnByTokens(itemTable, [
      ['set', 'id'],
      ['setid'],
      ['set'],
    ]);
    final danceFk = _findColumnByTokens(itemTable, [
      ['dance', 'id'],
      ['danceid'],
      ['dance'],
    ]);
    for (final rec in itemTable.records) {
      final cols = _CiColumns(_rowColumns(itemTable, rec));
      final setId = setFk == null ? null : cols.get(setFk)?.trim();
      if (setId == null || setId.isEmpty) continue;
      final danceId = danceFk == null ? null : cols.get(danceFk)?.trim();
      final breakText = cols.firstNonEmpty(['Break', 'BreakText', 'Note']);
      final hasDance = danceId != null && danceId.isNotEmpty;
      items
          .putIfAbsent(setId, () => [])
          .add(
            CcSetItem(
              order: _parseInt(cols.get('Order')) ?? items[setId]?.length ?? 0,
              danceRecordId: hasDance ? danceId : null,
              breakText: hasDance ? null : breakText,
              isAlt: _isTruthy(cols.get('AlternateDance')),
              guestCaller: cols.get('Caller'),
              minutes: _parseInt(cols.get('Time')),
            ),
          );
    }
  }

  final sets = <CcSet>[];
  for (final rec in setTable.records) {
    final cols = _CiColumns(_rowColumns(setTable, rec));
    final ccId = setIdCol == null ? null : cols.get(setIdCol)?.trim();
    final id = (ccId == null || ccId.isEmpty) ? rec.id.toString() : ccId;
    final setItems = (items[id] ?? [])
      ..sort((a, b) => a.order.compareTo(b.order));
    sets.add(
      CcSet(
        recordId: id,
        title: null,
        eventDate: cols.get('Date'),
        location: cols.get('Location'),
        band: cols.get('Band'),
        caller: cols.get('Caller'),
        dancerLevel: cols.firstNonEmpty(['DancerLevel', 'Level']),
        notes: cols.get('Notes'),
        items: setItems,
      ),
    );
  }
  return sets;
}

// --- Helpers ---------------------------------------------------------------

FmpTable? _findTable(FmpDatabase db, List<String> candidateNames) {
  for (final name in candidateNames) {
    final t = db.tables.firstWhereOrNull(
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    );
    if (t != null) return t;
  }
  return null;
}

/// Finds a column whose normalised (lowercased, non-alphanumeric-stripped) name
/// contains ALL tokens of any one candidate token-set, trying sets in order.
String? _findColumnByTokens(FmpTable table, List<List<String>> tokenSets) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final tokens in tokenSets) {
    for (final col in table.columns) {
      final n = norm(col.name);
      if (tokens.every(n.contains)) return col.name;
    }
  }
  return null;
}

Map<String, String> _rowColumns(FmpTable table, FmpRecord record) {
  final map = <String, String>{};
  for (final col in table.columns) {
    final v = record.valuesByColumnIndex[col.index];
    if (v != null) map[col.name] = v;
  }
  return map;
}

bool _isTruthy(String? raw) {
  final v = raw?.trim().toLowerCase() ?? '';
  return v == '1' || v == 'true' || v == 'yes' || v == 'y';
}

int? _parseInt(String? raw) {
  final v = raw?.trim() ?? '';
  if (v.isEmpty) return null;
  final m = RegExp(r'-?\d+').firstMatch(v);
  return m == null ? null : int.tryParse(m.group(0)!);
}

/// A case-insensitive view over a CC column map.
class _CiColumns {
  _CiColumns(Map<String, String> columns)
    : _byLower = {
        for (final e in columns.entries) e.key.toLowerCase().trim(): e.value,
      };

  final Map<String, String> _byLower;

  String? get(String name) => _byLower[name.toLowerCase().trim()];

  String? firstNonEmpty(List<String> names) {
    for (final name in names) {
      final v = get(name);
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
