import 'package:compendium_core/compendium_core.dart';

import '../search/dance_detail_data.dart';

/// The safe, deliberately narrow update used by the detail-screen re-import.
///
/// Normal imports use their dedupe decision and can replace an entire record.
/// This path is different: it keeps the collection entry's user-maintained
/// metadata and refreshes only the choreography supplied by the source.
enum DanceReimportResult { replaced, targetMissing }

Future<DanceReimportResult> replaceDanceChoreography(
  CompendiumRepositories repos, {
  required String targetDanceId,
  required Dance incoming,
  DateTime? now,
}) async {
  final existing = await repos.dances.getById(targetDanceId);
  if (existing == null) return DanceReimportResult.targetMissing;
  await repos.dances.update(
    existing.copyWith(
      figures: incoming.figures,
      formation: incoming.formation,
      progression: incoming.progression,
      updatedAt: now ?? DateTime.now().toUtc(),
    ),
  );
  return DanceReimportResult.replaced;
}

/// Plans exactly one dance from a generic JSON payload without ever committing
/// its archive-level entities. Program-bearing archives are intentionally not a
/// valid detail re-import source.
Future<ImportRecordPlan> planSingleDanceJson(
  CompendiumRepositories repos,
  String payload,
) async {
  final decoded = decodeArchive(payload);
  if (decoded.errors.any(
    (error) =>
        error.entityType == 'archive' && error.kind == ArchiveErrorKind.read,
  )) {
    throw const DanceReimportJsonException.cardinality(0);
  }
  if (decoded.archive.programs.isNotEmpty) {
    throw const DanceReimportJsonException.programArchive();
  }
  final batch = await ImportPipeline(
    repos.dances,
    repos.choreographers,
  ).plan(GenericJsonAdapter(), ImportRequest(payload: payload));
  if (batch.records.length != 1) {
    throw DanceReimportJsonException.cardinality(batch.records.length);
  }
  return batch.records.single;
}

/// Typed, presentation-safe failure for the JSON-only re-import contract.
class DanceReimportJsonException implements Exception {
  const DanceReimportJsonException.cardinality(this.count)
    : programBearing = false;
  const DanceReimportJsonException.programArchive()
    : count = 0,
      programBearing = true;

  final int count;
  final bool programBearing;
}

/// Builds a deliberately sparse preview for a parsed JSON dance. Its local-only
/// fields are not committed, so showing them would imply they will be replaced.
DanceDetailData reimportPreviewData(Dance dance) => DanceDetailData(
  dance: dance,
  authorNames: const [],
  tagNames: const [],
  customFields: const [],
  relatedDanceTitles: const {},
  sourcesById: const {},
  crossRefLinker: DanceTitleLinker.build(const [], excludeId: dance.id),
);
