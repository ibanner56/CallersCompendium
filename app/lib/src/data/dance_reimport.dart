import 'package:compendium_core/compendium_core.dart';

import '../search/dance_detail_data.dart';

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
    difficultyLevels: repos.difficultyLevels,
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

/// What re-importing [incoming]'s choreography over [existing] changes that
/// its preview, which shows [incoming], cannot show: the dance [form] it ends
/// as, and whether the Barnes reference and the Starts improper mark the
/// English dance holds are dropped (only an English dance carries either).
/// Null when the form stays.
///
/// Read off [withReimportedChoreography] itself, so it says exactly what the
/// commit will do. A re-import from a contra-only source onto an English dance
/// makes it contra (#2284); the maintainer chose to say so in the preview and
/// drop the two fields, not keep them (pre-release audit finding GAPC-02).
typedef ReimportFormChange = ({
  DanceForm form,
  bool dropsBarnesReference,
  bool dropsImproper,
});

ReimportFormChange? reimportFormChange(Dance existing, Dance incoming) {
  final after = withReimportedChoreography(
    existing,
    incoming,
    updatedAt: existing.updatedAt,
  );
  if (after.form == existing.form) return null;
  return (
    form: after.form,
    dropsBarnesReference:
        existing.barnesReference.isNotEmpty && after.barnesReference.isEmpty,
    dropsImproper: existing.formation.improper && !after.formation.improper,
  );
}

/// Whether [draft] decoded to an empty figure list.
///
/// Linking such a draft onto an existing dance (an import's "same dance"
/// link) would erase its transcription, so every surface that offers a link
/// asks this first. A re-import ([withReimportedChoreography]) keeps the saved
/// figures for an empty or unreadable incoming list, so for it this only
/// decides whether to tell the user the source sent no figures. An
/// *unreadable* incoming list is not figureless; an import link writes it
/// through as is (`ImportPipeline` copies the draft's `figuresSource` whole).
bool draftHasNoFigures(StructuredDraft draft) =>
    switch (draft.dance.figuresSource) {
      DecodedFigures(:final figures) => figures.isEmpty,
      UnreadableFigures() => false,
    };

/// Refuses an online [plan] that brought no figures.
///
/// [replaceDanceChoreography] keeps the saved figures for such a plan, so it
/// would refresh only the formation and progression and say the dance was
/// re-imported; this tells the user the source sent no figures instead, and
/// changes nothing. The common cause is The Caller's Box serving only
/// metadata for a dance without the `full` permission tier (the
/// `callersbox_search_tier` issue); a ContraDB page without a figures table
/// parses the same way. The title search hides the first case
/// (`OnlineSearchQuery.requireFigures`), but a link or id reaches any dance,
/// so every online re-import checks here. The same refusal stops an online
/// import from linking such a record onto a dance
/// (`commitPreviewedOnlinePlan`).
void rejectFigurelessReimport(ImportRecordPlan plan) {
  if (draftHasNoFigures(plan.draft)) {
    throw const DanceReimportFiguresUnavailableException();
  }
}

/// Typed, presentation-safe refusal raised by [rejectFigurelessReimport].
class DanceReimportFiguresUnavailableException implements Exception {
  const DanceReimportFiguresUnavailableException();
}

/// Builds a deliberately sparse preview for a parsed JSON dance. Its local-only
/// fields are not committed, so showing them would imply they will be replaced.
/// A re-import never changes the composed or interpreted dates
/// (`withReimportedChoreography`), so the preview leaves them out too.
DanceDetailData reimportPreviewData(Dance dance) => DanceDetailData(
  dance: dance.copyWith(clearComposedOn: true, clearInterpretedOn: true),
  authorNames: const [],
  tagNames: const [],
  customFields: const [],
  relatedDanceTitles: const {},
  sourcesById: const {},
  crossRefLinker: DanceTitleLinker.build(const [], excludeId: dance.id),
);
