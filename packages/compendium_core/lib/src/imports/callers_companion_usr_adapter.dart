import 'dart:convert';
import 'dart:typed_data';

import '../model/enums.dart';
import 'callers_companion_mapping.dart';
import 'callers_companion_usr_archive.dart';
import 'fmp/fmp_reader.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that migrates Caller's Companion (CC) dances from the
/// **binary FileMaker Pro 12 `.USR`** file — the *headline* Phase 6.5
/// migration path (`docs/design/imports.md` §2, `docs/ROADMAP.md` 6.5). It
/// pairs the pure-Dart [readFmp12] container reader (validated byte-for-byte
/// against real FileMaker files) with the CC-schema [readCcUsrArchive] layer,
/// then feeds each CC `Dance` row through the shared
/// [mapCallersCompanionDance] mapping — the exact same mapping the CC *text*
/// adapter uses, so both paths interpret CC identically.
///
/// ## Input
///
/// The framework never does I/O, so the caller supplies the `.USR` bytes on the
/// [ImportRequest] in one of two ways (checked in this order):
/// - `options['bytes']` as a `List<int>`/`Uint8List` (preferred — no copy), or
/// - [ImportRequest.payload] as a **base64** string of the file's bytes.
///
/// ## Identity, dedupe & provenance
///
/// Unlike the text adapter (no stable id → fuzzy dedupe), CC gives every dance a
/// stable relational key in its `zk_Dance_ID` field, so each [RawRecord] carries
/// `externalId` = that CC dance id. That gives exact `(source, externalId)`
/// dedupe/re-import and is the key that links `SetItem` rows to their dance
/// (CC's `SetItem.zk_Dance_ID` references `Dance.zk_Dance_ID`, **not** the
/// FileMaker record id). The `fetch` payload is a JSON object of that dance's
/// **verbatim** CC column map (all columns, including ones this PR does not map)
/// plus its id, so the in-memory record losslessly carries the whole source row
/// through to `parse` and the follow-up phases (author resolution,
/// custom-field defs, etc.). It is not persisted: that payload fed
/// `provenance.raw_payload` until schema v21 dropped the column (#781).
///
/// ## Scope
///
/// This adapter covers the **dance** path end-to-end through the existing
/// pipeline. Programs (`Set`/`SetItem` → `Program`) are produced separately by
/// [buildCcPrograms] from a [CcUsrArchive]; wiring their persistence/undo is an
/// app-layer follow-up because [ImportPipeline] is dance-only (see the PR
/// notes). Authors stay unresolved (names → notes + info issue), matching the
/// other adapters and the queued author-resolution PR.
class CallersCompanionUsrAdapter implements SourceAdapter {
  CallersCompanionUsrAdapter({this.limits = const FmpReadLimits()});

  /// Structural bounds handed to [readCcUsrArchive]; exceeding one fails closed
  /// with a friendly "too large" [ImportError] (see [discover]). Defaults to the
  /// production ceilings; tests inject tiny values to exercise the guard.
  final FmpReadLimits limits;

  /// Version tag stamped onto each [RawRecord.sourceVersion].
  static const String sourceVersion = ccUsrSourceVersion;

  @override
  ProvenanceSource get source => ProvenanceSource.callersCompanion;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    final bytes = _bytesOf(request);
    final CcUsrArchive archive;
    try {
      archive = readCcUsrArchive(bytes, limits: limits);
    } on FmpResourceLimitException {
      // Untrusted input that is too large / over-structured: fail closed with a
      // friendly message aligned with the archive intake path. The internal
      // detail is never surfaced (no information leak).
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'That file is too large to import.',
      );
    } on FmpFormatException catch (e) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'The file is not a readable Caller\'s Companion .USR '
            '(FileMaker 12) database: ${e.message}',
      );
    }
    return [
      for (final entry in archive.dances)
        DiscoveredRecord(
          source: source,
          externalId: entry.recordId,
          label: (entry.record.name ?? '').trim().isEmpty
              ? null
              : entry.record.name!.trim(),
          locator: {
            'rowId': entry.recordId,
            'columns': entry.rawColumns,
            // The figure body is joined from the separate `Phrase` table (or the
            // Dance-row A1..C2 fallback) and is NOT in the per-dance column map,
            // so thread it through discover→fetch→parse explicitly — otherwise
            // `parse` would re-derive an empty body from the payload columns.
            'body': _encodeBody(entry.record.body),
          },
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final rowId = record.locator['rowId'];
    final columns = record.locator['columns'];
    if (rowId is! String || columns is! Map) {
      throw fetchError(
        source,
        'Record locator is missing its dance columns; re-run discover.',
      );
    }
    final body = record.locator['body'];
    final payload = jsonEncode({
      'rowId': rowId,
      'columns': columns.map((k, v) => MapEntry('$k', '$v')),
      // Preserve the joined figure body verbatim so `parse` rebuilds it rather
      // than deriving an empty body from the columns. Absent on a legacy
      // locator — omitted so the payload stays backward compatible.
      if (body is List) 'body': body,
    });
    return RawRecord(
      source: source,
      externalId: rowId,
      sourceVersion: sourceVersion,
      payload: payload,
      contentType: 'application/json',
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final Map<String, String> columns;
    List<CcBodySection>? bodyOverride;
    try {
      final decoded = jsonDecode(raw.payload);
      if (decoded is! Map || decoded['columns'] is! Map) {
        throw parseError(
          source,
          'Payload is not a Caller\'s Companion .USR dance record.',
        );
      }
      columns = (decoded['columns'] as Map).map((k, v) => MapEntry('$k', '$v'));
      // The threaded figure body (Phrase-join or Dance-row fallback). Legacy
      // payloads have no `body` key, so `ccDanceRecordFromColumns` re-derives it
      // from the A1..C2 columns instead (backward compatible).
      final rawBody = decoded['body'];
      if (rawBody is List) bodyOverride = _decodeBody(rawBody);
    } on FormatException {
      throw parseError(
        source,
        'Payload is not valid Caller\'s Companion .USR dance JSON.',
      );
    }

    final CcDanceRecord record;
    try {
      record = ccDanceRecordFromColumns(
        columns,
        bodyOverride: bodyOverride,
        limits: limits,
      );
    } on FmpResourceLimitException {
      // A legacy payload (no threaded body) re-derives its figure body from the
      // A1..C2 columns, which is bounded by the same fail-closed CC caps; an
      // over-structured value throws here. Map it to the same friendly message
      // `discover` uses rather than letting a raw exception escape `parse`.
      throw ImportError(
        stage: ImportStage.parse,
        source: source,
        message: 'That file is too large to import.',
      );
    }
    // Figure text is scrubbed + structured by the shared parser (the mapping's
    // default scrub is the core `scrubFigureText` chokepoint).
    final mapping = mapCallersCompanionDance(record);
    return StructuredDraft(
      dance: mapping.dance,
      raw: raw,
      issues: mapping.issues,
      authorNames: mapping.authorNames,
    );
  }

  Uint8List _bytesOf(ImportRequest request) {
    final optionBytes = request.options['bytes'];
    if (optionBytes is Uint8List) return optionBytes;
    if (optionBytes is List<int>) return Uint8List.fromList(optionBytes);

    final payload = request.payload;
    if (payload != null && payload.trim().isNotEmpty) {
      try {
        return base64.decode(payload.trim());
      } on FormatException {
        throw ImportError(
          stage: ImportStage.discover,
          source: source,
          message:
              'The Caller\'s Companion .USR payload was not valid base64; '
              'pass raw bytes via options["bytes"] or a base64 payload.',
        );
      }
    }
    throw ImportError(
      stage: ImportStage.discover,
      source: source,
      message:
          'No Caller\'s Companion .USR file was provided (expected bytes in '
          'options["bytes"] or a base64 payload).',
    );
  }
}

/// Serialises a joined figure [body] to a JSON-safe list for the discover
/// locator / fetch payload: `[{label, lines:[...]}]`. Preserves section order,
/// the (nullable) label, and every verbatim line.
List<Map<String, Object?>> _encodeBody(List<CcBodySection> body) => [
  for (final section in body) {'label': section.label, 'lines': section.lines},
];

/// Rebuilds the figure body from a decoded JSON payload, defensively. The
/// payload is untrusted (it is persisted provenance that can be re-imported), so
/// every element is type-checked and malformed entries are skipped rather than
/// throwing — mirroring the parse-never-fails posture of the rest of the import
/// path. Downstream, each surviving line still flows through the mapping's
/// `scrubFigureText` chokepoint. Any structural bound belongs to #561.
List<CcBodySection> _decodeBody(List<Object?> raw) {
  final sections = <CcBodySection>[];
  for (final element in raw) {
    if (element is! Map) continue;
    final rawLabel = element['label'];
    final label = rawLabel is String && rawLabel.trim().isNotEmpty
        ? rawLabel
        : null;
    final rawLines = element['lines'];
    if (rawLines is! List) continue;
    final lines = [
      for (final line in rawLines)
        if (line is String && line.trim().isNotEmpty) line,
    ];
    if (lines.isEmpty) continue;
    sections.add(CcBodySection(label: label, lines: lines));
  }
  return sections;
}
