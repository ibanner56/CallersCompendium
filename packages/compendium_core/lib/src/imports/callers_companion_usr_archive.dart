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
    this.insertCalls = const [],
    this.relatedDancePairs = const [],
    required this.warnings,
  });

  /// One entry per CC `Dance` row, in file order.
  final List<CcDanceEntry> dances;

  /// One entry per CC `Set` row, each carrying its ordered [CcSetItem]s.
  final List<CcSet> sets;

  /// One entry per CC `InsertCall` row (a shipped default "call button": a short
  /// label → full call text + beats, with an optional ALT form), in file order.
  /// The seed source for user shorthands (issue #562); empty when the file has
  /// no `InsertCall` table.
  final List<CcInsertCall> insertCalls;

  /// One entry per CC `Dance_Related` row, still keyed by CC `zk_Dance_ID`
  /// values (not yet resolved to Compendium dance ids — the importer resolves
  /// both endpoints once dances are committed; issue #688). Empty when the
  /// file has no `Dance_Related` table.
  final List<CcRelatedDancePair> relatedDancePairs;

  /// Non-fatal notes (missing tables, guessed column names, reader warnings).
  final List<String> warnings;
}

/// One CC `Dance_Related` row: a directed pair of CC `zk_Dance_ID` values
/// (still source-record ids — see [CcUsrArchive.relatedDancePairs]).
class CcRelatedDancePair {
  CcRelatedDancePair({
    required this.sourceRecordId,
    required this.targetRecordId,
  });

  /// The CC `zk_Dance1_ID` value — the dance the link is attached to.
  final String sourceRecordId;

  /// The CC `zk_Dance2_ID` value — the related dance it points at.
  final String targetRecordId;
}

/// A single CC `InsertCall` row (a shipped default "call button"), reshaped into
/// a source-agnostic value object the shorthand-seeding step consumes (issue
/// #562).
///
/// CC's buttons carry a short [label] (`InsertButtonLabel`, e.g. `"B&S-N"`), the
/// full call [text] (`InsertButtonText`, e.g. `"Neighbor balance and swing"`)
/// with its [beats] (`InsertButtonBeats`), and a SECOND, usually *different*
/// call in the ALT slot ([altText]/`InsertButtonTextAlt` + [altBeats]) toggled
/// by the same button (e.g. `"Robins Chain"` / `"Larks Chain"`). All text is
/// sanitized at this ingestion boundary; the primary vs. alt distinction is
/// preserved so the seeding step can offer the alt as an alternative expansion
/// for the same shorthand token.
class CcInsertCall {
  CcInsertCall({
    required this.label,
    required this.text,
    this.beats = 0,
    this.altText,
    this.altBeats = 0,
  });

  /// The button's short label — the proposed shorthand token. Sanitized,
  /// original casing preserved for display.
  final String label;

  /// The full primary call text the button inserts. Sanitized.
  final String text;

  /// The primary call's beat count (`InsertButtonBeats`), or 0 when absent /
  /// unparseable.
  final int beats;

  /// The ALT call text (`InsertButtonTextAlt`), sanitized, or `null` when the
  /// button has no distinct alt. May differ entirely from [text].
  final String? altText;

  /// The ALT call's beat count (`InsertButtonBeatsAlt`), or 0 when absent /
  /// unparseable.
  final int altBeats;
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
  final dances = _extractDances(db, warnings, phraseBodies, limits);
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
  final insertCalls = _extractInsertCalls(db, warnings, limits);
  final relatedDancePairs = _extractRelatedDancePairs(db, warnings, limits);
  return CcUsrArchive(
    dances: dances,
    sets: sets,
    insertCalls: insertCalls,
    relatedDancePairs: relatedDancePairs,
    warnings: warnings,
  );
}

// --- Dance extraction ------------------------------------------------------

const List<String> _danceTableNames = ['Dance', 'Dances'];
const List<String> _bodyLabels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

List<CcDanceEntry> _extractDances(
  FmpDatabase db,
  List<String> warnings,
  Map<String, List<CcBodySection>> phraseBodies,
  FmpReadLimits limits,
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
          limits: limits,
          warnings: warnings,
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
  FmpReadLimits limits = const FmpReadLimits(),
  List<String>? warnings,
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
  // Dance-row A1..C2 columns only when no Phrase body was supplied. The fallback
  // is untrusted free text too, so it is bounded by the SAME incremental caps as
  // the Phrase join — otherwise a hostile `.USR` could bypass the Phrase-join
  // guards by omitting the `Phrase` table and stuffing extreme values into
  // `A1..C2`. The Phrase [bodyOverride] path is already capped upstream, so the
  // caps here apply only to this fallback (no double-enforcement).
  final List<CcBodySection> body;
  if (bodyOverride != null && bodyOverride.isNotEmpty) {
    body = bodyOverride;
  } else {
    final fallback = <CcBodySection>[];
    var lineCount = 0;
    var overLongCount = 0;
    for (final label in _bodyLabels) {
      final raw = lookup.get(label);
      if (raw == null || raw.trim().isEmpty) continue;
      final lines = <String>[];
      overLongCount += _appendCappedBodyLines(
        raw,
        lines,
        maxLineLength: limits.maxBodyLineLength,
        remaining: limits.maxFiguresPerDance - lineCount,
        absoluteCap: limits.maxFiguresPerDance,
      );
      if (lines.isNotEmpty) {
        lineCount += lines.length;
        fallback.add(CcBodySection(label: label, lines: lines));
      }
    }
    if (overLongCount > 0) {
      warnings?.add(
        '$overLongCount Caller\'s Companion figure line(s) exceeded the safe '
        'length (> ${limits.maxBodyLineLength} characters) and were dropped; '
        'the rest was imported.',
      );
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
///   [_appendCappedBodyLines] → [sanitizeImportedText]) so control/bidi/format
///   spoofing characters can never reach the [CcBodySection], the adapter's
///   persisted JSON payload, or storage.
/// - **Bounds** the join fail-closed against a pathological file: at most
///   [FmpReadLimits.maxPhraseRows] rows and [FmpReadLimits.maxFiguresPerDance]
///   body lines per dance — each throws a [FmpResourceLimitException] (never
///   OOM/throw-through). A single line longer than
///   [FmpReadLimits.maxBodyLineLength] is instead **dropped with a warning**
///   (not fatal), mirroring the local free-text-entry path so one over-long line
///   can't abort the whole import.
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
  var overLongCount = 0;
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
      // Split + sanitize INCREMENTALLY, enforcing the caps as each line is
      // produced, so a pathological PhraseText (e.g. millions of short lines)
      // trips the fail-closed guard *before* the full list is materialized —
      // the OOM/DoS bound this change adds must precede the allocation it
      // guards, not follow it. Behavior is identical for well-formed input.
      final lines = <String>[];
      overLongCount += _appendCappedBodyLines(
        e.value.text,
        lines,
        maxLineLength: limits.maxBodyLineLength,
        remaining: limits.maxFiguresPerDance - lineCount,
        absoluteCap: limits.maxFiguresPerDance,
      );
      if (lines.isEmpty) continue;
      lineCount += lines.length;
      final label = (e.value.number == null || e.value.number!.isEmpty)
          ? null
          : e.value.number;
      sections.add(CcBodySection(label: label, lines: lines));
    }
    if (sections.isNotEmpty) result[entry.key] = sections;
  }
  if (overLongCount > 0) {
    warnings.add(
      '$overLongCount Caller\'s Companion figure line(s) exceeded the safe '
      'length (> ${limits.maxBodyLineLength} characters) and were dropped; the '
      'rest was imported.',
    );
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

/// Walks [raw] one newline-delimited line at a time, invoking [emit] with each
/// raw (pre-sanitize) line, **without materializing the full split list**.
///
/// Handles `\n`, `\r` and `\r\n` line endings (a `\r\n` pair is one separator).
/// Emitting incrementally lets the untrusted `Phrase` join enforce its per-dance
/// caps as lines are produced (#561), so a pathological value with a huge number
/// of short lines fails closed *before* the whole list is allocated — the guard
/// precedes the allocation it bounds. At most one line substring is live per
/// callback.
void _forEachBodyLine(String raw, void Function(String line) emit) {
  final len = raw.length;
  var start = 0;
  var i = 0;
  while (i < len) {
    final c = raw.codeUnitAt(i);
    if (c == 0x0A || c == 0x0D) {
      emit(raw.substring(start, i));
      // Treat a CR immediately followed by LF as a single line break.
      if (c == 0x0D && i + 1 < len && raw.codeUnitAt(i + 1) == 0x0A) i++;
      i++;
      start = i;
    } else {
      i++;
    }
  }
  // Trailing segment (raw not ending in a line break). A trailing break leaves
  // start == len, contributing nothing — matching the old blank-line filter.
  if (start < len) emit(raw.substring(start, len));
}

/// Sanitizes + appends the body lines of [raw] to [out], enforcing the CC
/// ingestion caps INCREMENTALLY so allocation is bounded, and returns the number
/// of over-long lines it dropped.
///
/// Walks [raw] one newline-delimited fragment at a time via [_forEachBodyLine]
/// (no full split list is ever built), and for each fragment:
///  - sanitizes it at this ingestion boundary (#444) via [sanitizeImportedText]
///    so control/bidi-override/invisible format spoofing characters are stripped
///    before the line can reach a [CcBodySection], the persisted JSON payload, or
///    storage — and drops it if empty afterwards;
///  - drops a line longer than [maxLineLength] (counted in the return value) —
///    never fatal, mirroring the local free-text-entry path (which drops a line
///    past `maxFreeTextEntryLength` rather than throwing) so a lone over-long
///    line can't abort a whole import. The per-line cost is O(line length); the
///    line is dropped before it can enlarge the retained set or the per-dance
///    total;
///  - throws [FmpResourceLimitException] (naming [absoluteCap]) the moment [out]
///    would grow past [remaining] kept lines — the fail-closed aggregate guard,
///    checked BEFORE the line is retained, so [out] never grows past the budget
///    regardless of how many fragments remain in [raw].
///
/// Shared by BOTH untrusted body sources — the `Phrase` join and the Dance-row
/// `A1..C2` fallback — so neither can bypass the caps.
int _appendCappedBodyLines(
  String raw,
  List<String> out, {
  required int maxLineLength,
  required int remaining,
  required int absoluteCap,
}) {
  var dropped = 0;
  _forEachBodyLine(raw, (rawLine) {
    final line = sanitizeImportedText(rawLine, allowLineBreaks: false).trim();
    if (line.isEmpty) return;
    if (line.length > maxLineLength) {
      dropped++;
      return;
    }
    if (out.length >= remaining) {
      throw FmpResourceLimitException(
        'A Caller\'s Companion dance has too many figure lines to import '
        'safely (> $absoluteCap).',
      );
    }
    out.add(line);
  });
  return dropped;
}

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

// --- InsertCall extraction (shorthand seeding, #562) -----------------------

const List<String> _insertCallTableNames = ['InsertCall', 'InsertCalls'];

/// Reads the CC **`InsertCall`** table — the shipped default "call buttons" — as
/// source-agnostic [CcInsertCall]s for the shorthand-seeding step (issue #562).
///
/// A missing table yields an empty list (silent — a text-shaped export has no
/// buttons), never a throw (parse-never-fails). Column names are resolved
/// exact-first (confirmed against the real `CallersCompanion2.USR` schema) with a
/// tolerant token fallback, mirroring the Dance/Phrase/Set resolvers.
///
/// ## OWASP hardening
/// The `InsertCall` table is untrusted external free text. This layer:
/// - **Sanitizes** every label + button text at the ingestion boundary via
///   [sanitizeImportedText] so control/bidi/format spoofing characters can never
///   reach a [CcInsertCall], the candidate builder, or storage.
/// - **Bounds** the scan fail-closed: at most [FmpReadLimits.maxInsertCallRows]
///   rows (a hand-built [FmpDatabase] bypasses the byte-level guard, so the cap
///   is enforced here) — exceeding it throws a [FmpResourceLimitException].
/// - **Degrades** gracefully: a row with a missing/empty label OR empty primary
///   text is skipped (nothing to seed), never a throw.
List<CcInsertCall> _extractInsertCalls(
  FmpDatabase db,
  List<String> warnings,
  FmpReadLimits limits,
) {
  final table = _findTable(db, _insertCallTableNames);
  if (table == null) return const [];

  final labelCol = _resolveColumn(
    table,
    ['InsertButtonLabel'],
    [
      ['button', 'label'],
      ['insertlabel'],
      ['label'],
    ],
  );
  final textCol = _resolveColumn(
    table,
    ['InsertButtonText'],
    [
      ['button', 'text'],
      ['inserttext'],
    ],
  );
  if (labelCol == null || textCol == null) {
    warnings.add(
      'The Caller\'s Companion "InsertCall" table was found but its '
      'label/text columns could not be resolved; no shorthands were seeded.',
    );
    return const [];
  }
  // Beats/alt columns are optional — a differently-named build simply loses the
  // beats/alt refinement, never the whole button.
  final beatsCol = _resolveColumn(
    table,
    ['InsertButtonBeats'],
    [
      ['button', 'beats'],
    ],
  );
  final altTextCol = _resolveColumn(
    table,
    ['InsertButtonTextAlt'],
    [
      ['button', 'text', 'alt'],
    ],
  );
  final altBeatsCol = _resolveColumn(
    table,
    ['InsertButtonBeatsAlt'],
    [
      ['button', 'beats', 'alt'],
    ],
  );

  final result = <CcInsertCall>[];
  var processedRows = 0;
  for (final rec in table.records) {
    // Bound the rows the CC layer will process — fail closed before a
    // pathological InsertCall table can exhaust memory (a hand-built
    // FmpDatabase bypasses the byte-level maxRecords guard).
    if (processedRows >= limits.maxInsertCallRows) {
      throw FmpResourceLimitException(
        'The Caller\'s Companion "InsertCall" table has too many rows to import '
        'safely (> ${limits.maxInsertCallRows}).',
      );
    }
    processedRows++;
    final cols = _CiColumns(_rowColumns(table, rec));
    final label = _sanitizeButtonLabel(cols.get(labelCol));
    if (label.isEmpty) continue;
    final text = _sanitizeButtonText(cols.get(textCol));
    if (text.isEmpty) continue;
    final altRaw = altTextCol == null ? null : cols.get(altTextCol);
    final altText = _sanitizeButtonText(altRaw);
    result.add(
      CcInsertCall(
        label: label,
        text: text,
        beats: beatsCol == null ? 0 : _parseBeats(cols.get(beatsCol)),
        altText: altText.isEmpty ? null : altText,
        altBeats: altBeatsCol == null ? 0 : _parseBeats(cols.get(altBeatsCol)),
      ),
    );
  }
  return result;
}

/// Sanitizes a button label at the ingestion boundary — single-line (labels
/// never span lines), control/bidi/format spoofing stripped.
String _sanitizeButtonLabel(String? raw) =>
    raw == null ? '' : sanitizeImportedText(raw, allowLineBreaks: false).trim();

/// Sanitizes button call text at the ingestion boundary. Line breaks are
/// preserved (a few default buttons carry a two-line call the fan-out reads) but
/// control/bidi/format spoofing characters are stripped.
String _sanitizeButtonText(String? raw) =>
    raw == null ? '' : sanitizeImportedText(raw).trim();

/// Parses a CC beats value (`InsertButtonBeats`), tolerating stray non-digit
/// characters; 0 when absent/unparseable. Negative values clamp to 0.
int _parseBeats(String? raw) {
  final n = _parseInt(raw);
  return (n == null || n < 0) ? 0 : n;
}

// --- Dance_Related extraction (related-dance links, #688) -----------------

const List<String> _relatedDanceTableNames = ['Dance_Related', 'DanceRelated'];

/// Reads the CC **`Dance_Related`** table into directed
/// [CcRelatedDancePair]s, still keyed by CC `zk_Dance_ID` values (the importer
/// resolves both endpoints to committed Compendium dance ids after the dance
/// import commits — mirrors how `SetItem.zk_Dance_ID` isn't resolved until
/// `buildCcPrograms`).
///
/// ## Schema provenance
/// The table **name** and its four columns — `zk_Dance1_ID` (source),
/// `zk_Dance2_ID` (target), `zk_DanceRelatedID`, `zk_DanceRelatedID_PairID` —
/// were read directly from a real `CallersCompanion2.USR` catalog, the same
/// rigor as `Dance`/`Set`/`SetItem`/`Phrase`. **Unlike those tables, the real
/// sample had zero populated `Dance_Related` rows**, so only the *schema*
/// (table/column names) is confirmed — the *row shape* (e.g. whether CC always
/// double-writes a mirrored pair via `zk_DanceRelatedID_PairID`) is not. This
/// extractor deliberately makes **no assumption** about that shape: it reads
/// each row as one directed `(zk_Dance1_ID → zk_Dance2_ID)` pair and nothing
/// more. If CC does mirror pairs in real data, two rows naturally yield two
/// directed pairs (one per direction) with no special-casing here — the
/// importer never synthesizes a reverse link on its own (issue #688 decision:
/// `RelatedDancesEditor`/`DanceLink` are directional per-dance app-side, with
/// no auto-mirroring anywhere).
///
/// Because the row shape is unvalidated, this layer stays maximally
/// defensive: a missing/renamed table, unresolvable columns, or a malformed
/// row degrade to a non-fatal warning and zero/fewer pairs — **never** a
/// crash, and never a pair with a missing/self-referential id.
///
/// ## OWASP hardening
/// The `Dance_Related` table is untrusted external data. This layer:
/// - **Bounds** the scan fail-closed: at most [FmpReadLimits.maxDanceRelatedRows]
///   rows total, and at most [FmpReadLimits.maxRelatedDancesPerDance] pairs per
///   source dance (a hand-built [FmpDatabase] bypasses the byte-level
///   `maxRecords` guard, so both caps are enforced here) — exceeding either
///   throws a [FmpResourceLimitException].
/// - **Dedupes** identical `(source, target)` rows within the table itself
///   before returning (defends against a malformed archive with literal
///   duplicate rows; distinct from the importer's separate cross-import
///   dedupe against already-persisted links).
/// - Never resolves ids against `Dance` rows itself — the importer validates
///   both endpoints resolve to dances **actually committed in this session**
///   before ever constructing a link, so an unresolved/invalid id can never
///   reach storage as a dangling `targetDanceId`.
List<CcRelatedDancePair> _extractRelatedDancePairs(
  FmpDatabase db,
  List<String> warnings,
  FmpReadLimits limits,
) {
  final table = _findTable(db, _relatedDanceTableNames);
  if (table == null) {
    // Not fatal — parse-never-fails — but still worth a warning: a real CC
    // export is expected to carry this table, so its absence usually means a
    // renamed/unrecognized schema variant silently dropped related-dance
    // links, which is worth surfacing (unlike `InsertCall`, which many real
    // exports legitimately lack).
    warnings.add(
      'No Caller\'s Companion "Dance_Related" table was found; no '
      'related-dance links were imported.',
    );
    return const [];
  }

  final sourceCol = _resolveColumn(
    table,
    ['zk_Dance1_ID'],
    [
      ['dance1', 'id'],
      ['related', 'dance1'],
    ],
  );
  final targetCol = _resolveColumn(
    table,
    ['zk_Dance2_ID'],
    [
      ['dance2', 'id'],
      ['related', 'dance2'],
    ],
  );
  if (sourceCol == null || targetCol == null) {
    warnings.add(
      'The Caller\'s Companion "Dance_Related" table was found but its '
      'zk_Dance1_ID/zk_Dance2_ID columns could not be resolved; no '
      'related-dance links were imported.',
    );
    return const [];
  }

  final pairs = <CcRelatedDancePair>[];
  final seenPairs = <String>{};
  final perSourceCounts = <String, int>{};
  var processedRows = 0;
  var skippedCount = 0;
  for (final rec in table.records) {
    // Bound the rows this layer will process — fail closed before a
    // pathological Dance_Related table can exhaust memory (a hand-built
    // FmpDatabase bypasses the byte-level maxRecords guard).
    if (processedRows >= limits.maxDanceRelatedRows) {
      throw FmpResourceLimitException(
        'The Caller\'s Companion "Dance_Related" table has too many rows to '
        'import safely (> ${limits.maxDanceRelatedRows}).',
      );
    }
    processedRows++;
    final cols = _CiColumns(_rowColumns(table, rec));
    final source = cols.get(sourceCol)?.trim();
    final target = cols.get(targetCol)?.trim();
    if (source == null ||
        source.isEmpty ||
        target == null ||
        target.isEmpty ||
        source == target) {
      // Missing id or a self-referential row — never a valid link.
      skippedCount++;
      continue;
    }
    final pairKey = '$source\u0000$target';
    if (!seenPairs.add(pairKey)) continue; // duplicate row in the table itself

    final count = (perSourceCounts[source] ?? 0) + 1;
    if (count > limits.maxRelatedDancesPerDance) {
      throw FmpResourceLimitException(
        'A Caller\'s Companion dance has too many related-dance links to '
        'import safely (> ${limits.maxRelatedDancesPerDance}).',
      );
    }
    perSourceCounts[source] = count;
    pairs.add(
      CcRelatedDancePair(sourceRecordId: source, targetRecordId: target),
    );
  }
  if (skippedCount > 0) {
    warnings.add(
      '$skippedCount Caller\'s Companion "Dance_Related" row(s) had a '
      'missing or self-referential dance id and were skipped.',
    );
  }
  return pairs;
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
