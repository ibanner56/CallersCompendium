import 'dart:typed_data';

import '../util/text_sanitizer.dart';
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
/// A non-FileMaker/unsupported container throws ([FmpFormatException]), and an
/// over-structured container throws ([FmpResourceLimitException], a fail-closed
/// DoS guard bounded by [limits]); everything else degrades to partial results +
/// [CcUsrArchive.warnings].
CcUsrArchive readCcUsrArchive(
  Uint8List bytes, {
  FmpReadLimits limits = const FmpReadLimits(),
}) {
  final db = readFmp12(bytes, limits: limits);
  return extractCcUsrArchive(db, limits: limits);
}

/// Extracts the CC tables from an already-parsed [FmpDatabase]. Split out from
/// [readCcUsrArchive] so the CC-schema extraction can be unit-tested against a
/// hand-built [FmpDatabase] without crafting raw FileMaker bytes (the raw
/// container reader is validated separately against real files).
///
/// [limits] bounds the CC `Phrase`-table join (row count, per-dance figure
/// count, per-line length). A hand-built [FmpDatabase] bypasses [readFmp12]'s
/// byte-level guards, so these CC-semantic caps are enforced here — over-limit
/// input **fails closed** with a [FmpResourceLimitException] (the adapter maps it
/// to a friendly "too large" message), never OOM/throw-through.
CcUsrArchive extractCcUsrArchive(
  FmpDatabase db, {
  FmpReadLimits limits = const FmpReadLimits(),
}) {
  final warnings = <String>[...db.warnings];
  final phraseBodies = _extractPhraseBodies(db, warnings, limits);
  final dances = _extractDances(db, warnings, phraseBodies);
  // Phrase rows whose `zk_Dance_ID` matches no `Dance` row are orphans: their
  // choreography can't be attached to any dance. Degrade gracefully — drop them
  // with a warning, never a throw (parse-never-fails; mirrors missingIdCount).
  final danceIds = {for (final d in dances) d.recordId};
  final orphanIds = phraseBodies.keys
      .where((id) => !danceIds.contains(id))
      .toList();
  if (orphanIds.isNotEmpty) {
    warnings.add(
      '${orphanIds.length} Caller\'s Companion "Phrase" group(s) referenced a '
      '"zk_Dance_ID" with no matching dance; their figures were skipped.',
    );
  }
  final sets = _extractSets(db, warnings);
  return CcUsrArchive(dances: dances, sets: sets, warnings: warnings);
}

// --- Dance extraction ------------------------------------------------------

const List<String> _danceTableNames = ['Dance', 'Dances'];
const List<String> _bodyLabels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

List<CcDanceEntry> _extractDances(
  FmpDatabase db,
  List<String> warnings,
  Map<String, List<CcBodySection>> phraseBodies,
) {
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
  final danceIdCol = _resolveColumn(
    table,
    ['zk_Dance_ID'],
    [
      ['dance', 'id'],
      ['danceid'],
    ],
  );
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
        record: ccDanceRecordFromColumns(
          columns,
          bodyOverride: phraseBodies[recordId],
        ),
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
///
/// [bodyOverride] supplies the figure body from an out-of-row source — the CC
/// **`Phrase` table** (`extractCcUsrArchive` joins it per dance; see
/// [_extractPhraseBodies]) or the adapter's threaded JSON payload. When it is
/// non-null **and non-empty** it is used verbatim as [CcDanceRecord.body],
/// because the real `.USR` keeps its transcription in `Phrase`, not the
/// `Dance`-row `A1..C2` columns. When it is null/empty the record falls back to
/// deriving the body from the bare `A1..C2` columns on the `Dance` row (the CC
/// text adapter and any export that carries them still work).
CcDanceRecord ccDanceRecordFromColumns(
  Map<String, String> columns, {
  List<CcBodySection>? bodyOverride,
}) {
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

  // Prefer the joined Phrase body (the real figure source); fall back to the
  // Dance-row A1..C2 columns only when no Phrase body was supplied.
  final List<CcBodySection> body;
  if (bodyOverride != null && bodyOverride.isNotEmpty) {
    body = bodyOverride;
  } else {
    final fallback = <CcBodySection>[];
    for (final label in _bodyLabels) {
      final raw = lookup.get(label);
      if (raw == null || raw.trim().isEmpty) continue;
      final lines = _splitBodyLines(raw);
      if (lines.isNotEmpty) {
        fallback.add(CcBodySection(label: label, lines: lines));
      }
    }
    body = fallback;
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

// --- Phrase extraction -----------------------------------------------------

const List<String> _phraseTableNames = ['Phrase', 'Phrases'];

/// The canonical CC section order (`PhraseNumber`): A1→A2→B1→B2→C1→C2. Any
/// other/unknown label sorts *after* these, keeping its first-seen order.
const List<String> _phraseOrder = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// Reads the CC **`Phrase`** table — the real home of the figure transcription
/// in a `.USR` — and returns each dance's ordered figure body keyed by the CC
/// `zk_Dance_ID` value (the same join identity [_extractDances] exposes as
/// [CcDanceEntry.recordId]).
///
/// Grouped by `zk_Dance_ID`, ordered by `PhraseNumber` (A1→A2→B1→B2→C1→C2, then
/// any others in first-seen order), each `PhraseText` split on newlines becomes
/// one [CcBodySection] (label = its `PhraseNumber`). A missing table/columns
/// degrades to an empty map (the Dance-row `A1..C2` fallback still applies),
/// never a throw — parse-never-fails.
///
/// Column names are resolved exact-first (confirmed against the real
/// `CallersCompanion2.USR` schema) so the gender-swapped variants the same table
/// carries (`PhraseText_GenderSwap_LR/RL/Switch`) are never mistaken for the
/// primary `PhraseText`.
///
/// ## OWASP hardening (#561)
/// The `Phrase` table is untrusted external free text. This layer:
/// - **Sanitizes** every body line at the ingestion boundary (via
///   [_splitBodyLines] → [sanitizeImportedText]) so control/bidi/format
///   spoofing characters can never reach the [CcBodySection], the adapter's
///   persisted JSON payload, or storage.
/// - **Bounds** the join fail-closed against a pathological file: at most
///   [FmpReadLimits.maxPhraseRows] rows, [FmpReadLimits.maxFiguresPerDance] body
///   lines per dance, and [FmpReadLimits.maxBodyLineLength] characters per line —
///   each throws a [FmpResourceLimitException] (never OOM/throw-through).
/// - **Degrades** malformed joins gracefully: a row with a missing/empty
///   `zk_Dance_ID` is skipped with a warning (orphan ids — present but matching
///   no dance — are warned about by [extractCcUsrArchive]); duplicate keys are
///   grouped, never throwing.
Map<String, List<CcBodySection>> _extractPhraseBodies(
  FmpDatabase db,
  List<String> warnings,
  FmpReadLimits limits,
) {
  final table = _findTable(db, _phraseTableNames);
  // A missing Phrase table is normal for text-shaped exports; the Dance-row
  // A1..C2 fallback covers them, so this is silent (no warning).
  if (table == null) return const {};

  final danceIdCol = _resolveColumn(
    table,
    ['zk_Dance_ID'],
    [
      ['dance', 'id'],
      ['danceid'],
    ],
  );
  final phraseNumCol = _resolveColumn(
    table,
    ['PhraseNumber'],
    [
      ['phrase', 'number'],
      ['phrase', 'num'],
    ],
  );
  final phraseTextCol = _resolvePhraseTextColumn(table);
  if (danceIdCol == null || phraseTextCol == null) {
    warnings.add(
      'The Caller\'s Companion "Phrase" table was found but its '
      'dance-id/text columns could not be resolved; figures were read from the '
      'Dance rows instead (they are usually empty).',
    );
    return const {};
  }

  // Group rows by CC dance id, preserving each row's PhraseNumber + text.
  final byDance = <String, List<_PhraseRow>>{};
  var missingIdCount = 0;
  var processedRows = 0;
  for (final rec in table.records) {
    // Bound the rows the CC layer will process — fail closed before a
    // pathological Phrase table can exhaust memory (a hand-built FmpDatabase
    // bypasses the byte-level maxRecords guard, so this must be enforced here).
    if (processedRows >= limits.maxPhraseRows) {
      throw FmpResourceLimitException(
        'The Caller\'s Companion "Phrase" table has too many rows to import '
        'safely (> ${limits.maxPhraseRows}).',
      );
    }
    processedRows++;
    final cols = _CiColumns(_rowColumns(table, rec));
    final danceId = cols.get(danceIdCol)?.trim();
    // A missing/empty join key can't be attached to any dance; skip it but
    // count so the user is told rather than silently losing choreography.
    if (danceId == null || danceId.isEmpty) {
      missingIdCount++;
      continue;
    }
    final text = cols.get(phraseTextCol);
    if (text == null || text.trim().isEmpty) continue;
    final number = phraseNumCol == null ? null : cols.get(phraseNumCol)?.trim();
    byDance
        .putIfAbsent(danceId, () => [])
        .add(_PhraseRow(number: number, text: text));
  }
  if (missingIdCount > 0) {
    warnings.add(
      '$missingIdCount Caller\'s Companion "Phrase" row(s) had no '
      '"zk_Dance_ID"; their figures could not be linked to a dance and were '
      'skipped.',
    );
  }

  final result = <String, List<CcBodySection>>{};
  for (final entry in byDance.entries) {
    final rows = entry.value;
    // Stable sort by canonical PhraseNumber order, unknown/blank labels last.
    final ordered = [for (var i = 0; i < rows.length; i++) MapEntry(i, rows[i])]
      ..sort((a, b) {
        final rank = _phraseRank(
          a.value.number,
        ).compareTo(_phraseRank(b.value.number));
        return rank != 0 ? rank : a.key.compareTo(b.key); // stable on ties
      });
    final sections = <CcBodySection>[];
    var lineCount = 0;
    for (final e in ordered) {
      final lines = _splitBodyLines(e.value.text);
      if (lines.isEmpty) continue;
      // Bound a single pathological PhraseText line (e.g. multi-megabyte, no
      // newlines) — fail closed rather than carry it into storage/the parser.
      for (final line in lines) {
        if (line.length > limits.maxBodyLineLength) {
          throw FmpResourceLimitException(
            'A Caller\'s Companion figure line is too long to import safely '
            '(> ${limits.maxBodyLineLength} characters).',
          );
        }
      }
      // Bound the total figure lines a single dance can accumulate, so a file
      // that aims many Phrase rows at one zk_Dance_ID can't force an unbounded
      // figure list downstream.
      lineCount += lines.length;
      if (lineCount > limits.maxFiguresPerDance) {
        throw FmpResourceLimitException(
          'A Caller\'s Companion dance has too many figure lines to import '
          'safely (> ${limits.maxFiguresPerDance}).',
        );
      }
      final label = (e.value.number == null || e.value.number!.isEmpty)
          ? null
          : e.value.number;
      sections.add(CcBodySection(label: label, lines: lines));
    }
    if (sections.isNotEmpty) result[entry.key] = sections;
  }
  return result;
}

/// Rank of a `PhraseNumber` for ordering: its index in [_phraseOrder]
/// (case-insensitive), or a large value (unknown/blank sorts last).
int _phraseRank(String? number) {
  if (number == null) return _phraseOrder.length;
  final i = _phraseOrder.indexWhere(
    (l) => l.toLowerCase() == number.trim().toLowerCase(),
  );
  return i < 0 ? _phraseOrder.length : i;
}

/// Resolves the primary `PhraseText` column, preferring the exact name so the
/// gender-swapped variants (`PhraseText_GenderSwap_*`) are never selected. The
/// token fallback additionally rejects any candidate whose normalised name
/// contains `swap`/`genderswap`, so a differently-cased build still avoids them.
String? _resolvePhraseTextColumn(FmpTable table) {
  final exact = table.columns.firstWhereOrNull(
    (c) => c.name.toLowerCase() == 'phrasetext',
  );
  if (exact != null) return exact.name;
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final col in table.columns) {
    final n = norm(col.name);
    if (n.contains('phrase') && n.contains('text') && !n.contains('swap')) {
      return col.name;
    }
  }
  return null;
}

/// Splits a raw body value on newlines, dropping blank lines (shared by the
/// Phrase join and the Dance-row `A1..C2` fallback so both parse identically).
///
/// Each line is **sanitized at this ingestion boundary** (#561) via
/// [sanitizeImportedText] (single-line mode) so control, bidi-override and
/// invisible/format spoofing characters are stripped before the line can reach
/// a [CcBodySection], the adapter's persisted JSON payload, or storage —
/// defense in depth ahead of the parser's own `scrubFigureText` chokepoint
/// (the transform is idempotent, so this never double-mangles legitimate text).
/// A line that is empty after sanitizing is dropped.
List<String> _splitBodyLines(String raw) => raw
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((l) => sanitizeImportedText(l, allowLineBreaks: false).trim())
    .where((l) => l.isNotEmpty)
    .toList();

/// One CC `Phrase` row's ordering label + verbatim text (internal to
/// [_extractPhraseBodies]).
class _PhraseRow {
  _PhraseRow({this.number, required this.text});

  final String? number;
  final String text;
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
  final setIdCol = _resolveColumn(
    setTable,
    ['zk_Set_ID'],
    [
      ['set', 'id'],
      ['setid'],
    ],
  );
  // CC Sets have no title/name column; the program title is derived downstream
  // from Location/Date.

  final items = <String, List<CcSetItem>>{};
  if (itemTable != null) {
    final setFk = _resolveColumn(
      itemTable,
      ['zk_Set_ID'],
      [
        ['set', 'id'],
        ['setid'],
        ['set'],
      ],
    );
    final danceFk = _resolveColumn(
      itemTable,
      ['zk_Dance_ID'],
      [
        ['dance', 'id'],
        ['danceid'],
        ['dance'],
      ],
    );
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

/// Resolves a column by its **known exact CC name** first (confirmed against the
/// real `CallersCompanion2.USR` schema), falling back to tolerant token-matching
/// only if a differently-named build omits it. Preferring the exact name avoids
/// substring ambiguity — e.g. both `zk_Set_ID` and `zk_SetItem_ID` contain the
/// `set`+`id` tokens, but the FK we want is exactly `zk_Set_ID`.
String? _resolveColumn(
  FmpTable table,
  List<String> exactNames,
  List<List<String>> tokenSets,
) {
  for (final name in exactNames) {
    final col = table.columns.firstWhereOrNull(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
    );
    if (col != null) return col.name;
  }
  return _findColumnByTokens(table, tokenSets);
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
