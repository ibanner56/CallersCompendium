import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

/// A trivial, in-memory [SourceAdapter] used **only** to unit-test the import
/// framework end-to-end (it is not a real source and is never exported from
/// the package barrel). It parses a deliberately simple source-native JSON
/// shape into a [StructuredDraft], exercising every framework seam: verbatim
/// payload preservation, structured-vs-custom figure parsing, parse-quality
/// scoring, and the parse-never-fails invariant.
///
/// Source-native payload shape (one object per record):
/// ```json
/// {
///   "id": "fake-1",
///   "title": "Rory O'More",
///   "version": "2026-07-15",
///   "permission": "full",
///   "license": "CC-BY",
///   "authorIds": ["c1"],
///   "figures": [
///     {"beats": 16, "text": "balance and swing", "move": "swing"},
///     {"beats": 8,  "text": "give and take"}
///   ]
/// }
/// ```
/// A figure with a non-empty `move` becomes a structured [Figure]; otherwise it
/// falls back to a [customFigure] carrying its beats + text. A record whose
/// payload is not a JSON object throws a parse [ImportError].
class FakeSourceAdapter implements SourceAdapter {
  FakeSourceAdapter(
    this.records, {
    this.source = ProvenanceSource.json,
    this.failFetchExternalIds = const {},
    this.discoverThrows = false,
  });

  /// The source-native records, each a decoded JSON object.
  final List<Map<String, Object?>> records;

  @override
  final ProvenanceSource source;

  /// External ids whose [fetch] should raise a structured fetch error (to
  /// exercise partial-batch tolerance).
  final Set<String> failFetchExternalIds;

  /// When true, [discover] throws (to exercise whole-batch discovery failure).
  final bool discoverThrows;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    if (discoverThrows) throw StateError('discover boom');
    return [
      for (var i = 0; i < records.length; i++)
        DiscoveredRecord(
          source: source,
          externalId: records[i]['id'] as String?,
          label: records[i]['title'] as String?,
          locator: {'index': i},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final index = record.locator['index'] as int;
    final obj = records[index];
    final externalId = obj['id'] as String?;
    if (externalId != null && failFetchExternalIds.contains(externalId)) {
      throw fetchError(
        source,
        'Simulated fetch failure',
        externalId: externalId,
      );
    }
    return RawRecord(
      source: source,
      externalId: externalId,
      sourceVersion: obj['version'] as String?,
      payload: jsonEncode(obj),
      contentType: 'application/json',
      permission: obj['permission'] as String?,
      license: obj['license'] as String?,
    );
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.payload);
    } catch (e) {
      throw parseError(
        source,
        'Payload is not valid JSON',
        externalId: raw.externalId,
        cause: e,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw parseError(
        source,
        'Payload is not a JSON object',
        externalId: raw.externalId,
      );
    }
    final title = (decoded['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw parseError(
        source,
        'Record has no title',
        externalId: raw.externalId,
      );
    }

    final issues = <ImportIssue>[];
    final figures = <Figure>[];
    final rawFigures = (decoded['figures'] as List?) ?? const [];
    for (var i = 0; i < rawFigures.length; i++) {
      final f = rawFigures[i] as Map<String, Object?>;
      final beats = (f['beats'] as int?) ?? 0;
      final text = (f['text'] as String?) ?? '';
      final move = (f['move'] as String?)?.trim();
      if (move != null && move.isNotEmpty && move != customMove) {
        figures.add(
          Figure(
            move: move,
            params: beats > 0 ? {'beats': beats} : const {},
            note: text.isEmpty ? null : text,
          ),
        );
      } else {
        // Parse-never-fails: unstructured line → custom figure.
        figures.add(customFigure(text, beats: beats));
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'custom_figure_fallback',
            message: 'Figure ${i + 1} kept as custom text.',
            figureIndex: i,
          ),
        );
      }
    }

    final authorIds = [
      for (final a in (decoded['authorIds'] as List?) ?? const []) a as String,
    ];

    final now = DateTime.utc(2026, 1, 1);
    final dance = Dance(
      id: 'draft-${raw.externalId ?? 'anon'}',
      title: title,
      authorIds: authorIds,
      figures: figures,
      createdAt: now,
      updatedAt: now,
    );
    return StructuredDraft(dance: dance, raw: raw, issues: issues);
  }
}
