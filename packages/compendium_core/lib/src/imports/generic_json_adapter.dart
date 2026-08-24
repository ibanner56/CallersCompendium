import '../model/choreographer.dart';
import '../model/dance.dart';
import '../model/enums.dart';
import '../serialization/archive_codec.dart';
import '../serialization/compendium_archive.dart';
import 'import_error.dart';
import 'raw_record.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// A [SourceAdapter] that imports dances from our own canonical
/// [CompendiumArchive] JSON — the generic-JSON format written by
/// `encodeArchive`/`archiveToJson` (`docs/design/imports.md` §"Generic JSON
/// (6.6)"). This is the **inter-user-sharing** import path.
///
/// **Sharing unit: dances.** The import pipeline is per-record (one
/// [DiscoveredRecord] per dance), so this adapter enumerates the archive's
/// dances and imports them one at a time through the standard
/// `discover → fetch → parse → dedupe → commit` flow. Whole-collection and
/// program sharing (plus the app-local layers) are the responsibility of the
/// G.5 backup/restore/merge path (`ArchiveRestorer`) and are deliberately NOT
/// duplicated here.
///
/// Contract notes:
/// - [discover] reads the archive JSON from [ImportRequest.payload] (inline
///   text). It decodes once via [decodeArchive] and emits one record per dance.
///   Enumeration is cheap and tolerant: the codec skips a malformed dance and
///   records it in the read result, so one bad dance never fails the batch.
///   **A payload that is not a decodable archive at all** (invalid JSON, a
///   non-object root, or a missing/empty payload) throws a discover
///   [ImportError] — surfaced as a structured error by the pipeline — because
///   there is no usable import source. A *valid* archive with zero dances is
///   not an error: it yields an empty record list.
/// - [fetch] re-serializes the single dance into a minimal, self-contained
///   single-dance archive so [parse] can work from the [RawRecord] alone,
///   independent of any adapter state [discover] built.
/// - [parse] decodes that minimal archive and returns the single dance as a
///   [StructuredDraft]. Because the generic-JSON format already carries
///   structured figures, parsing never fails on figure content
///   (parse-never-fails); it throws only when the payload is not a valid record
///   of this source (undecodable / zero dances). Codec errors and warnings are
///   surfaced as non-fatal [ImportIssue]s on the draft.
class GenericJsonAdapter implements SourceAdapter {
  GenericJsonAdapter();

  @override
  ProvenanceSource get source => ProvenanceSource.json;

  /// Dances discovered from the most recent [discover] call, keyed by their
  /// archive id, so [fetch] can re-serialize a single dance. [parse] never
  /// consults this — it works from the [RawRecord] alone.
  final Map<String, Dance> _dancesById = {};

  /// Choreographers seen during [discover], keyed by their archive id, so
  /// [fetch] can embed the ones a dance references into its self-contained
  /// single-dance payload. A received bundle credits its dances by author id,
  /// but the receiver cannot resolve the sender's ids — so [parse] turns these
  /// into author *names* on the draft, which the [ImportPipeline] resolves to
  /// (or creates) real [Choreographer] rows at commit. Without this the dance's
  /// `authorIds` would reference choreographer rows that never get created,
  /// failing the `dance_authors` foreign key and dropping the dance (#412).
  final Map<String, Choreographer> _choreographersById = {};

  /// The archive schema version seen during [discover], echoed onto each
  /// [RawRecord.sourceVersion] and used to re-serialize single-dance archives.
  int _schemaVersion = archiveSchemaVersion;

  @override
  Future<List<DiscoveredRecord>> discover(ImportRequest request) async {
    // Reset discovery state up front so a failed attempt never leaves stale
    // records fetchable from a prior successful discover on this instance.
    _dancesById.clear();
    _choreographersById.clear();
    _schemaVersion = archiveSchemaVersion;

    final payload = request.payload;
    if (payload == null || payload.trim().isEmpty) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message: 'No archive payload provided to import.',
      );
    }

    final result = decodeArchive(payload);
    // A root-level read error means the payload is not a decodable archive at
    // all (invalid JSON or a non-object root); there is nothing to import.
    final rootError = _rootReadError(result);
    if (rootError != null) {
      throw ImportError(
        stage: ImportStage.discover,
        source: source,
        message:
            'Payload is not a decodable Compendium archive: '
            '${rootError.message}',
      );
    }

    _dancesById.addEntries(result.archive.dances.map((d) => MapEntry(d.id, d)));
    _choreographersById.addEntries(
      result.archive.choreographers.map((c) => MapEntry(c.id, c)),
    );
    _schemaVersion = result.archive.schemaVersion;

    return [
      for (final dance in result.archive.dances)
        DiscoveredRecord(
          source: source,
          externalId: dance.provenance?.externalId ?? dance.id,
          label: dance.title,
          locator: {'danceId': dance.id},
        ),
    ];
  }

  @override
  Future<RawRecord> fetch(DiscoveredRecord record) async {
    final rawDanceId = record.locator['danceId'];
    if (rawDanceId is! String) {
      throw fetchError(
        source,
        'Record locator is missing a valid "danceId"; re-run discover.',
        externalId: record.externalId,
      );
    }
    final dance = _dancesById[rawDanceId];
    if (dance == null) {
      throw fetchError(
        source,
        'Dance "$rawDanceId" is no longer available to fetch; re-run discover.',
        externalId: record.externalId,
      );
    }

    return RawRecord(
      source: source,
      externalId: record.externalId,
      sourceVersion: '$_schemaVersion',
      payload: _encodeSingleDance(
        dance,
        _referencedChoreographers(dance),
        _schemaVersion,
      ),
      contentType: 'application/json',
    );
  }

  /// The choreographers this [dance] credits — the ones whose ids appear in its
  /// `authorIds`, deduped by id, skipping ids that were not present in the
  /// discovered archive (best-effort — an unresolved author id is simply
  /// dropped, never fatal). The single-dance payload carries ONLY these, keeping
  /// it minimal and leaking no unrelated authors. ([parse] recovers names in
  /// `authorIds` order directly from the decoded dance, so the order of this
  /// list — which [encodeArchive] canonicalizes by id anyway — is irrelevant.)
  List<Choreographer> _referencedChoreographers(Dance dance) {
    final referenced = <Choreographer>[];
    final seen = <String>{};
    for (final id in dance.authorIds) {
      if (!seen.add(id)) continue;
      final choreographer = _choreographersById[id];
      if (choreographer != null) referenced.add(choreographer);
    }
    return referenced;
  }

  @override
  StructuredDraft parse(RawRecord raw) {
    final result = decodeArchive(raw.payload);
    final rootError = _rootReadError(result);
    if (rootError != null) {
      throw parseError(
        source,
        'Payload is not a decodable Compendium archive: ${rootError.message}',
        externalId: raw.externalId,
      );
    }
    final dances = result.archive.dances;
    if (dances.isEmpty) {
      throw parseError(
        source,
        'Payload does not contain a decodable dance.',
        externalId: raw.externalId,
      );
    }
    if (dances.length > 1) {
      throw parseError(
        source,
        'Payload contains ${dances.length} dances; expected exactly one.',
        externalId: raw.externalId,
      );
    }

    final issues = <ImportIssue>[
      for (final e in result.errors)
        ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'archive_read_error',
          // Full context (entityType/entityId) so a skipped entity is
          // actionable when several are dropped.
          message: e.toString(),
        ),
      for (final w in result.warnings)
        ImportIssue(
          severity: ImportIssueSeverity.info,
          code: 'archive_read_warning',
          message: w,
        ),
    ];

    // Recover author display names from the payload's own choreographers (a
    // received bundle credits by author id, but the receiver cannot resolve the
    // sender's ids). Names are emitted in the dance's `authorIds` order, deduped
    // by id, skipping ids with no choreographer and blank/whitespace-only names
    // (the archive is untrusted input; a blank name would throw in the
    // Choreographer model, and parse must never fail a dance). The pipeline
    // resolves each name to an existing row or creates one at commit.
    final dance = dances.single;
    final nameById = {
      for (final c in result.archive.choreographers) c.id: c.name,
    };
    final authorNames = <String>[];
    final seenAuthorIds = <String>{};
    for (final id in dance.authorIds) {
      if (!seenAuthorIds.add(id)) continue;
      final name = nameById[id]?.trim();
      if (name != null && name.isNotEmpty) authorNames.add(name);
    }

    // The draft carries no provenance — the pipeline attaches it at commit,
    // derived from `raw` (including the externalId that keys exact dedupe).
    return StructuredDraft(
      dance: _withoutProvenance(dance),
      raw: raw,
      issues: issues,
      authorNames: authorNames,
    );
  }

  /// The archive-level read error (the payload is not a decodable archive at
  /// all), or `null` when the root decoded to a JSON object.
  static ArchiveError? _rootReadError(ArchiveReadResult result) {
    for (final e in result.errors) {
      if (e.entityType == 'archive' && e.kind == ArchiveErrorKind.read) {
        return e;
      }
    }
    return null;
  }

  /// Encodes [dance] as a minimal, self-contained single-dance archive so the
  /// payload is fully decodable by [parse] on its own. [choreographers] are the
  /// dance's referenced authors, carried alongside so [parse] can recover their
  /// display names (the pipeline resolves names to ids at commit).
  static String _encodeSingleDance(
    Dance dance,
    List<Choreographer> choreographers,
    int schemaVersion,
  ) => encodeArchive(
    CompendiumArchive(
      schemaVersion: schemaVersion,
      exportedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      dances: [dance],
      choreographers: choreographers,
    ),
    mode: ArchiveSerializationMode.share,
  );

  /// Strips any embedded provenance from an imported dance; the pipeline owns
  /// provenance and re-derives it from the [RawRecord] at commit time.
  static Dance _withoutProvenance(Dance dance) =>
      dance.provenance == null ? dance : dance.copyWith(clearProvenance: true);
}
