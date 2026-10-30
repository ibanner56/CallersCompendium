import 'dart:typed_data';

import '../model/custom_field.dart';
import '../model/dance.dart';
import '../model/dance_link.dart';
import '../model/difficulty_level.dart';
import '../model/enums.dart';
import '../model/program.dart';
import '../model/published_source.dart';
import '../model/source_citation.dart';
import '../model/venue.dart';
import '../storage/repositories/custom_field_repository.dart';
import '../storage/repositories/dance_repository.dart';
import '../storage/repositories/difficulty_level_errors.dart';
import '../storage/repositories/difficulty_level_repository.dart';
import '../storage/repositories/program_repository.dart';
import '../storage/repositories/published_source_repository.dart';
import '../storage/repositories/venue_repository.dart';
import '../storage/shareable_text.dart';
import '../util/uuid.dart';
import 'callers_companion_mapping.dart';
import 'callers_companion_programs.dart';
import 'callers_companion_related_dances.dart';
import 'callers_companion_usr_adapter.dart';
import 'callers_companion_user_fields.dart';
import 'callers_companion_usr_archive.dart';
import 'dedupe.dart';
import 'import_error.dart';
import 'import_pipeline.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';
import 'venue_dedupe.dart';

/// The outcome of committing a Caller's Companion `.USR` import: the dance
/// [ImportSession] (dances + author choreographers) produced by the shared
/// [ImportPipeline], plus the [Program]s built from the archive's `Set`/
/// `SetItem` rows and persisted alongside them.
///
/// This is the single handle passed to [CallersCompanionUsrImporter.undo] so a
/// whole CC import — dances **and** programs — reverts symmetrically (the
/// programs are removed, then the dances). Keeping the program bookkeeping here
/// (rather than on the source-agnostic, dance-only [ImportSession]) keeps
/// [ImportPipeline] free of any `Program`/CC knowledge.
class CcUsrImportResult {
  CcUsrImportResult({
    required this.danceSession,
    required List<Program> programs,
    required List<ImportIssue> programIssues,
    List<String> insertedProgramIds = const [],
    List<Program> updatedProgramPriorStates = const [],
    List<String> restoredProgramIds = const [],
    this.programRestoreAt,
    List<String> insertedVenueIds = const [],
    List<ImportIssue> relatedDanceLinkIssues = const [],
    List<String> insertedCustomFieldIds = const [],
    List<String> restoredCustomFieldIds = const [],
    List<ImportIssue> customFieldIssues = const [],
    Map<String, List<String>> linksAddedToEarlierDances = const {},
    List<String> insertedPublishedSourceIds = const [],
    List<String> restoredPublishedSourceIds = const [],
    List<String> insertedDifficultyLevelIds = const [],
    List<String> restoredDifficultyLevelIds = const [],
  }) : insertedDifficultyLevelIds = List.unmodifiable(
         insertedDifficultyLevelIds,
       ),
       restoredDifficultyLevelIds = List.unmodifiable(
         restoredDifficultyLevelIds,
       ),
       insertedPublishedSourceIds = List.unmodifiable(
         insertedPublishedSourceIds,
       ),
       restoredPublishedSourceIds = List.unmodifiable(
         restoredPublishedSourceIds,
       ),
       programs = List.unmodifiable(programs),
       programIssues = List.unmodifiable(programIssues),
       insertedProgramIds = List.unmodifiable(insertedProgramIds),
       updatedProgramPriorStates = List.unmodifiable(updatedProgramPriorStates),
       restoredProgramIds = List.unmodifiable(restoredProgramIds),
       insertedVenueIds = List.unmodifiable(insertedVenueIds),
       relatedDanceLinkIssues = List.unmodifiable(relatedDanceLinkIssues),
       insertedCustomFieldIds = List.unmodifiable(insertedCustomFieldIds),
       restoredCustomFieldIds = List.unmodifiable(restoredCustomFieldIds),
       customFieldIssues = List.unmodifiable(customFieldIssues),
       linksAddedToEarlierDances = Map.unmodifiable({
         for (final e in linksAddedToEarlierDances.entries)
           e.key: List<String>.unmodifiable(e.value),
       });

  /// The dance-side session (inserted dance ids, updated-dance prior states,
  /// created choreographer ids) — reverted via [ImportPipeline.undo].
  final ImportSession danceSession;

  /// Every program this import persisted — both newly inserted and updated
  /// (re-imported) — carrying its final id (an updated program keeps the id of
  /// the program it deduped onto). Ordered as the archive's `Set`s were built.
  final List<Program> programs;

  /// Ids of the programs **inserted** by this import (no prior existed); these
  /// are hard-deleted on [undo]. Programs that deduped onto an existing one are
  /// not here — they are in [updatedProgramPriorStates] instead.
  final List<String> insertedProgramIds;

  /// Prior snapshots of the programs this import **updated in place** because a
  /// re-import matched their `(source, externalId)` provenance key. Restored
  /// verbatim on [undo] so a re-import reverts losslessly (mirrors the dance
  /// pipeline's `updatedDancePriorStates`).
  final List<Program> updatedProgramPriorStates;

  /// Ids of tombstoned programs restored by an exact provenance match. Soft-deleted
  /// again on [undo] so the rollback records a later existence transition.
  final List<String> restoredProgramIds;

  /// Import timestamp used for causal restore and failed-commit compensation.
  /// [undo] takes a fresh timestamp instead.
  final DateTime? programRestoreAt;

  /// Ids of the venues this import **inserted** while resolving each set's
  /// `location` text to a venue entity (issue #687) — one freshly-minted id
  /// per newly-seen location, folded to a single entry when two sets in this
  /// same archive share the exact same (normalized) location text. Empty when
  /// venue-entity mode was off, or when every set either had no usable
  /// location or matched an existing venue. Hard-deleted on [undo] (guarded —
  /// a venue a surviving program still links to is left in place).
  final List<String> insertedVenueIds;

  /// Non-fatal issues raised while building the programs (unresolved dance
  /// references, unparseable dates, skipped empty slots) — never fatal.
  final List<ImportIssue> programIssues;

  /// Non-fatal issues raised while resolving `Dance_Related` pairs into
  /// `relatedDance` [DanceLink]s (issue #688) — e.g. a pair whose target dance
  /// id was not committed in this import. **Not** the links themselves: the
  /// created links live directly on the dances in [danceSession] (there is
  /// nothing to revert independently on [undo] — see [undo]'s doc).
  final List<ImportIssue> relatedDanceLinkIssues;

  /// Ids of the custom-field definitions this import **created** for the CC
  /// `UserDefined_*` columns. On [undo] each is hard-deleted unless a surviving
  /// dance holds a value for it (the repository's own in-transaction guard).
  final List<String> insertedCustomFieldIds;

  /// Ids of tombstoned definitions this import revived because a CC column's
  /// key matched them exactly. Tombstoned again on [undo] (same guard).
  final List<String> restoredCustomFieldIds;

  /// Non-fatal notes from matching CC user fields to definitions at commit
  /// (a column whose key was taken by a field of another type). The
  /// per-dance key notes (shared keys, unusable labels) are on the drafts.
  final List<ImportIssue> customFieldIssues;

  /// Dance id → ids of the `relatedDance` links this import added to a dance
  /// it did not commit itself: one an earlier per-row Edit wrote
  /// (`earlierDanceIds` on [CallersCompanionUsrImporter.commit]). [undo]
  /// removes just these links; the dances stay.
  final Map<String, List<String>> linksAddedToEarlierDances;

  /// Ids of the published sources this import created for CC `Reference`
  /// citations (#1974). Removed on [CallersCompanionUsrImporter.undo] unless a
  /// surviving dance cites one.
  final List<String> insertedPublishedSourceIds;

  /// Ids of tombstoned published sources this import restored for a citation.
  /// Tombstoned again on undo (same guard).
  final List<String> restoredPublishedSourceIds;

  /// Ids of the difficulty levels this import created for CC combined levels
  /// such as "Easy/Intermediate" (#1973). Removed on
  /// [CallersCompanionUsrImporter.undo] unless a surviving dance uses one.
  final List<String> insertedDifficultyLevelIds;

  /// Ids of tombstoned difficulty levels this import restored for a combined
  /// level. Tombstoned again on undo (same guard).
  final List<String> restoredDifficultyLevelIds;

  /// Ids of the programs updated in place (re-imported) by this import.
  List<String> get updatedProgramIds => [
    for (final p in updatedProgramPriorStates) p.id,
  ];

  /// Count of programs newly inserted by this import.
  int get insertedProgramCount => insertedProgramIds.length;

  /// Count of programs updated in place (deduped/re-imported) by this import.
  int get updatedProgramCount => updatedProgramPriorStates.length;

  /// Count of venues newly inserted by this import.
  int get insertedVenueCount => insertedVenueIds.length;

  /// True once [CallersCompanionUsrImporter.undo] has reverted this import.
  bool get isUndone => _undone;
  bool _undone = false;
}

/// Drives a full Caller's Companion `.USR` migration through the **real import
/// commit path**: it commits dances via the shared [ImportPipeline] (dedupe,
/// provenance, author resolution, undo), builds the CC `Set`/`SetItem`
/// programs with [buildCcPrograms] — resolving each slot's CC dance reference
/// to the *new* Compendium dance id the commit just minted — and persists them
/// via [ProgramRepository], then wires the CC `Dance_Related` table into
/// `relatedDance` [DanceLink]s on the just-committed dances (issue #688) via
/// [buildCcRelatedDanceLinks].
///
/// This is the app-layer follow-up promised in [buildCcPrograms]'s doc: it is
/// what actually calls that builder in production. It stays **Flutter-free**
/// (pure Dart + repositories) so it lives in the core and is trivially
/// unit-testable; the app supplies the `.USR` bytes.
class CallersCompanionUsrImporter {
  CallersCompanionUsrImporter(
    this._pipeline,
    this._programs,
    this._venues,
    this._customFields, {
    required PublishedSourceRepository publishedSources,
    required DifficultyLevelRepository difficultyLevels,
    CallersCompanionUsrAdapter? adapter,
  }) : _sources = publishedSources,
       _levels = difficultyLevels,
       _adapter = adapter ?? CallersCompanionUsrAdapter();

  /// Where the published sources behind CC `Reference` citations are matched
  /// and created (#1974), alongside the user-field definitions.
  final PublishedSourceRepository _sources;

  /// Where the difficulty levels behind CC combined levels ("Easy/
  /// Intermediate") are matched and created (#1973), like the sources.
  final DifficultyLevelRepository _levels;

  final ImportPipeline _pipeline;
  final ProgramRepository _programs;
  final VenueRepository _venues;

  /// Where the definitions behind the CC `UserDefined_*` columns are matched
  /// and created. Takes part in [commit]'s all-or-nothing compensation and in
  /// [undo].
  final CustomFieldDefRepository _customFields;

  /// The [DanceRepository] the related-dance-link step (issue #688) reads
  /// and updates the just-committed dances through. Reused from [_pipeline]
  /// itself — rather than taken as a separate constructor dependency — so
  /// this importer can never be wired with a [DanceRepository] instance
  /// different from the one [_pipeline] actually committed dances through
  /// (which would risk updating a different DB/transaction than the commit
  /// happened in).
  DanceRepository get _dances => _pipeline.dances;

  final CallersCompanionUsrAdapter _adapter;

  /// Plans the dance side of a `.USR` [bytes] payload non-destructively (the CC
  /// dances run through the same `discover → fetch → parse → dedupe` pipeline as
  /// every other source). The returned batch is committed with [commit]. The
  /// programs are built from the archive at commit time, so planning is
  /// dance-only — mirroring the pipeline.
  Future<ImportBatchResult> plan(Uint8List bytes) =>
      _pipeline.plan(_adapter, ImportRequest(options: {'bytes': bytes}));

  /// Commits a planned dance [batch] and then the programs from [archive].
  ///
  /// The dances commit first (real pipeline path), yielding the CC-dance-id →
  /// new-Compendium-dance-id map used to FK-resolve each program slot. Programs
  /// whose slots reference a dance that was not committed degrade to text
  /// placeholders + issues (never a throw — see [buildCcPrograms]).
  ///
  /// [venueEntityMode] gates issue #687's venue-entity linking. It is read by
  /// the app from `VenueEntityModeScope` — a Flutter `InheritedNotifier` the
  /// (Flutter-free) core cannot see — and passed in explicitly, exactly like
  /// [now]/[newId]. When `false`, this method touches [VenueRepository] not at
  /// all (no read, no write) and every program keeps `venueId: null`, `venue`
  /// text only — byte-for-byte today's pre-#687 behavior. When `true`, each
  /// set's cleaned `location` (already sanitized by [buildCcPrograms] via its
  /// `_cleanLine`, so no separate/weaker sanitizer is introduced here) is
  /// resolved to a venue entity, mirroring the native archive importer's
  /// fingerprint rule (`compendium_archive_import.dart`): a unique
  /// [VenueFingerprintIndex] match links to the existing venue; no match (the
  /// overwhelmingly common case — see below) or an ambiguous match (>1
  /// existing venue sharing the fingerprint) fresh-mints rather than guessing.
  ///
  /// **Why matches are rare for `.USR`:** [venueFingerprint] only scores a
  /// venue when it has a `name` *and* a `city`/`address1` — a bare `.USR`
  /// `Location` string has neither, so a location-derived candidate's
  /// fingerprint is always weak/`null`. Cross-import (or re-import) reuse of
  /// an existing venue purely from that bare text is therefore intentionally
  /// rare/absent: two distinct real-world halls that merely share a common
  /// name (e.g. two different towns each with a "Grange Hall") must never
  /// silently merge just because the text matches — fresh-mint-over-guess,
  /// the same philosophy the strong-key threshold already enforces for
  /// richer records. Do not "fix" this by relaxing the match to a bare name.
  /// [VenueFingerprintIndex] stays wired exactly as the issue asks so the path
  /// is live if `.USR` location parsing is ever enriched with structured
  /// city/state.
  ///
  /// **Same-import collapse:** to still satisfy "two sets with the same
  /// location link to one venue" *within a single archive*, this method also
  /// keeps a this-commit-only map from normalized location text (mirroring
  /// [venueFingerprint]'s own field normalization) to the venue id it
  /// resolved for that text, folded in as each set is processed — deliberately
  /// separate from, and narrower than, the cross-import fingerprint match.
  ///
  /// **Re-import skip:** a program matched by provenance to one that already
  /// carries a `venueId` never has a fresh candidate resolved for it at all —
  /// [_rebuildProgramWithId] always carries the existing link forward (a
  /// `.USR` archive has no venue-link concept of its own to overwrite it
  /// with), so resolving one here would go unused and simply mint an orphan
  /// venue on every re-import.
  ///
  /// **Related dances (issue #688):** after the programs are persisted, each
  /// archive `Dance_Related` pair is resolved via [_danceIdByCcRowId] (and
  /// `earlierDanceIds`, below) and turned into a directed `relatedDance` [DanceLink] on the source dance
  /// (see [buildCcRelatedDanceLinks]'s doc for the full directionality,
  /// dedupe and OWASP-hardening rationale). A pair with an unresolved
  /// endpoint is skipped with a warning [ImportIssue] on
  /// [CcUsrImportResult.relatedDanceLinkIssues] — never a dangling
  /// `targetDanceId`. A dance [batch] re-imports gets no links: a re-import
  /// replaces only the choreography (INTAKE-7).
  ///
  /// **Dances committed earlier (the review's per-row Edit):**
  /// [earlierDanceIds] maps the CC `zk_Dance_ID` of each dance an earlier
  /// [commitDances] in the same review wrote to the dance id it wrote. A set
  /// slot or `Dance_Related` pair naming one of them resolves to that dance,
  /// as it would had the dance been in [batch]; without the map its slots
  /// became "not imported" placeholders. An entry whose dance no longer exists
  /// is ignored, and [batch]'s own dance wins for a CC id it also commits.
  /// Those dances are not this import's to revert: a related-dance link added
  /// to one is recorded in [CcUsrImportResult.linksAddedToEarlierDances] and
  /// [undo] removes just that link.
  ///
  /// **Skipped re-import rows (INTAKE-1):** [existingDanceIdByExternalId] maps
  /// a CC `zk_Dance_ID` to the local dance a re-import row the review left at
  /// Skip already matches (its verdict's target). Program slots for that dance
  /// link to it instead of becoming "not imported" placeholders. The map is
  /// used for slots only: the dances it names are not written, so
  /// `Dance_Related` links are never added to a dance the user chose to leave
  /// as it is (and [undo] has no prior state to restore one from). An entry
  /// whose dance no longer exists is ignored, and [batch]'s own dance and an
  /// [earlierDanceIds] entry both win over it for the same CC id.
  ///
  /// Everything is recorded on the returned [CcUsrImportResult] so [undo]
  /// reverts dances, programs **and** venues.
  Future<CcUsrImportResult> commit(
    ImportBatchResult batch,
    CcUsrArchive archive, {
    required DateTime now,
    required bool venueEntityMode,
    String Function()? newId,
    String Function()? newSlotId,
    Map<int, DedupeResolution> resolutions = const {},
    Map<String, String> existingDanceIdByExternalId = const {},
    List<String> defaultTagIds = const [],
    void Function(int done, int total)? onProgress,
    Map<String, String> earlierDanceIds = const {},
  }) async {
    final mintId = newId ?? uuidV4;
    final (
      session: danceSession,
      insertedFieldIds: keptInserted,
      restoredFieldIds: keptRestored,
      fieldIssues: fieldIssues,
      insertedSourceIds: keptSourcesInserted,
      restoredSourceIds: keptSourcesRestored,
      insertedLevelIds: keptLevelsInserted,
      restoredLevelIds: keptLevelsRestored,
    ) = await _commitDancesWithFields(
      batch,
      now: now,
      newId: mintId,
      resolutions: resolutions,
      defaultTagIds: defaultTagIds,
      onProgress: onProgress,
    );

    // This batch's own dances win over an earlier commit's for the same CC
    // row. An earlier dance that no longer exists (deleted from the editor
    // since) resolves to nothing, so its slots fall back to placeholders
    // rather than naming a missing dance.
    final committedEarlier = <String, String>{};
    final Map<String, String> danceIdByCcRowId;
    // Slots also link to a skipped re-import row's existing dance (see the doc
    // above); `Dance_Related` resolution below does not.
    final Map<String, String> slotDanceIdByCcRowId;
    try {
      for (final entry in earlierDanceIds.entries) {
        if (await _dances.getById(entry.value) != null) {
          committedEarlier[entry.key] = entry.value;
        }
      }
      danceIdByCcRowId = {
        ...committedEarlier,
        ..._danceIdByCcRowId(danceSession),
      };
      slotDanceIdByCcRowId = await _pipeline.withLiveExistingDances(
        danceIdByCcRowId,
        existingDanceIdByExternalId,
      );
    } catch (_) {
      await _pipeline.undo(danceSession);
      await _revertUserFieldDefinitions(keptInserted, keptRestored);
      await _revertPublishedSources(keptSourcesInserted, keptSourcesRestored);
      await _revertDifficultyLevels(keptLevelsInserted, keptLevelsRestored);
      rethrow;
    }

    final built = buildCcPrograms(
      archive,
      danceIdByCcRowId: slotDanceIdByCcRowId,
      newId: mintId,
      newSlotId: newSlotId ?? uuidV4,
      now: now,
    );
    final issues = List<ImportIssue>.of(built.issues);

    // Persist the programs, deduping on provenance. A built program whose
    // `(callersCompanion, zk_Set_ID)` key already exists is a re-import: update
    // that program in place (preserving its id + createdAt, capturing its prior
    // state for undo) rather than inserting a duplicate. Others are inserted.
    //
    // If any write fails the dances are already committed, so compensate before
    // rethrowing — remove the inserted programs, restore the updated ones,
    // remove any minted venues, and revert the dance commit — keeping the
    // import all-or-nothing from the caller's perspective (they never get a
    // partial DB with no undo handle).
    final existingByExternalId = await _programs.externalIdToProgramId(
      ProvenanceSource.callersCompanion,
    );
    final insertedIds = <String>[];
    final priorCapturedFor = <String>{};
    final priorStates = <Program>[];
    final restoredProgramIds = <String>[];
    final restoredProgramIdSet = <String>{};
    final persisted = <Program>[];
    final insertedVenueIds = <String>[];
    final relatedDanceLinkIssues = <ImportIssue>[];
    // Dance id → ids of the links appended to a dance an earlier commit wrote
    // (see the related-dance step below); removed again on failure and undo.
    final linksAddedToEarlier = <String, List<String>>{};
    // Lazily-seeded fingerprint index over the receiver's existing venues
    // (issue #687), built at most once per commit (memoized here) and only
    // when a candidate actually produces a non-null [venueFingerprint] — a
    // bare `.USR` location (name only) never does, so the ordinary all-
    // location .USR import touches `_venues.listAll()` zero times; a mode-
    // off import, or one whose sets are all location-less or already-linked
    // re-imports, likewise issues zero venue reads.
    VenueFingerprintIndex? venueIndex;
    // This-commit-only collapse of *this archive's* locations — see the
    // "Same-import collapse" doc above.
    final venueIdByLocationKey = <String, String>{};
    try {
      for (final program in built.programs) {
        final externalId = program.provenance?.externalId;
        final existingId = (externalId == null || externalId.isEmpty)
            ? null
            : existingByExternalId[externalId];
        final prior = existingId == null
            ? null
            : await _programs.getById(existingId, includeDeleted: true);

        String? venueId;
        if (venueEntityMode && !(prior != null && prior.venueId != null)) {
          final cleanedLocation = program.venue;
          if (cleanedLocation != null && cleanedLocation.isNotEmpty) {
            final locationKey = _normalizeLocationKey(cleanedLocation);
            final reused = venueIdByLocationKey[locationKey];
            if (reused != null) {
              venueId = reused;
            } else {
              final candidateVenue = Venue(
                id: '_venue_dedupe_candidate',
                name: cleanedLocation,
              );
              // Compute the fingerprint BEFORE touching the venue repository.
              // A bare `.USR` location (name only, no city/address1) always
              // yields a null/weak fingerprint — see the doc above — so
              // `matchFor` structurally can never succeed for it. Skip the
              // `_venues.listAll()` read and index build entirely in that
              // (overwhelmingly common) case and go straight to mint; only a
              // candidate with a genuine (non-null) fingerprint needs the
              // index consulted, and even then it's built at most once per
              // commit (memoized in [venueIndex]), not once per set.
              final fingerprint = venueFingerprint(candidateVenue);
              if (fingerprint == null) {
                final mintedId = mintId();
                final mintedVenue = Venue(id: mintedId, name: cleanedLocation);
                await _venues.upsert(mintedVenue);
                insertedVenueIds.add(mintedId);
                // Keep an already-built index in sync so a later strong-
                // fingerprint candidate this commit can't collide with it.
                venueIndex?.add(mintedId, mintedVenue);
                venueId = mintedId;
              } else {
                final index = venueIndex ??= VenueFingerprintIndex(
                  await _venues.listAll(),
                );
                final matchedId = index.matchFor(candidateVenue);
                if (matchedId != null) {
                  venueId = matchedId;
                } else {
                  if (index.isAmbiguous(candidateVenue)) {
                    issues.add(
                      ImportIssue(
                        severity: ImportIssueSeverity.info,
                        code: 'cc_program_ambiguous_venue',
                        message:
                            'Set location "$cleanedLocation" matches more '
                            'than one existing venue; minted a new venue '
                            'rather than guessing which to link.',
                      ),
                    );
                  }
                  final mintedId = mintId();
                  final mintedVenue = Venue(
                    id: mintedId,
                    name: cleanedLocation,
                  );
                  await _venues.upsert(mintedVenue);
                  insertedVenueIds.add(mintedId);
                  index.add(mintedId, mintedVenue);
                  venueId = mintedId;
                }
              }
              venueIdByLocationKey[locationKey] = venueId;
            }
          }
        }
        final candidate = venueId == null
            ? program
            : program.copyWith(venueId: venueId);

        if (existingId == null || prior == null) {
          // New program (no match, or a stale index entry whose program row is
          // gone) — insert under its freshly minted id.
          await _programs.create(candidate);
          insertedIds.add(candidate.id);
          persisted.add(candidate);
        } else {
          // Re-import: overwrite the matched program in place.
          final target = _rebuildProgramWithId(
            candidate,
            id: existingId,
            createdAt: prior.createdAt,
            priorVenueId: prior.venueId,
          );
          if (priorCapturedFor.add(existingId)) {
            priorStates.add(prior);
          }
          if (prior.deletedAt != null) {
            await _programs.restore(existingId, at: now);
            if (restoredProgramIdSet.add(existingId)) {
              restoredProgramIds.add(existingId);
            }
          }
          await _programs.update(target);
          persisted.add(target);
        }
      }

      // Wire the CC `Dance_Related` table into `relatedDance` links on the
      // just-committed dances (issue #688), inside this SAME try block so a
      // failure here is compensated identically to a program-write failure
      // (see the catch below).
      //
      // No undo bookkeeping is needed for a link on a dance this batch
      // committed: every such dance is already tracked by
      // [ImportPipeline.undo], either via
      // `insertedDanceIds` (create/duplicate — hard-deleted wholesale) or via
      // `updatedDancePriorStates` (reimport/link — the pipeline captures a
      // full pre-commit snapshot of `_dances.getById(id)` **before any field
      // is touched**, for BOTH actions). [DanceRepository]'s upsert fully
      // replaces a dance's `dance_links` rows on every `update`, so restoring
      // that prior snapshot on undo already reverts any related-dance link
      // appended here, with zero additional tracking. See
      // `callers_companion_related_dances.dart` and this method's `undo` doc
      // for the full argument. A dance from [earlierDanceIds] is the exception:
      // this batch's undo does not restore it, so the ids of the links appended
      // to it are recorded and removed one by one instead.
      if (archive.relatedDancePairs.isNotEmpty) {
        final candidateDanceIds = <String>{
          for (final pair in archive.relatedDancePairs)
            if (danceIdByCcRowId[pair.sourceRecordId] != null)
              danceIdByCcRowId[pair.sourceRecordId]!,
        };
        final dancesById = <String, Dance>{};
        for (final id in candidateDanceIds) {
          final dance = await _dances.getById(id);
          if (dance != null) dancesById[id] = dance;
        }
        final existingLinksByDanceId = <String, List<DanceLink>>{
          for (final entry in dancesById.entries) entry.key: entry.value.links,
        };
        final sessionDanceIds = {
          for (final r in danceSession.records)
            if (r.succeeded && r.danceId != null) r.danceId!,
        };
        // A re-import replaces only a dance's choreography (INTAKE-7), so a
        // dance this batch re-imported gets none of the file's links.
        final reimportedDanceIds = {
          for (final r in danceSession.records)
            if (r.succeeded && r.action == CommitAction.reimport) r.danceId!,
        };
        final linkResult = buildCcRelatedDanceLinks(
          archive,
          danceIdByCcRowId: danceIdByCcRowId,
          existingLinksByDanceId: existingLinksByDanceId,
          newId: mintId,
        );
        relatedDanceLinkIssues.addAll(linkResult.issues);
        for (final entry in linkResult.newLinksByDanceId.entries) {
          if (reimportedDanceIds.contains(entry.key)) continue;
          final dance = dancesById[entry.key];
          if (dance == null) continue; // fetched dance vanished; skip safely
          if (!sessionDanceIds.contains(entry.key)) {
            // Recorded before the write, so a failure part-way is compensated.
            linksAddedToEarlier[entry.key] = [
              for (final link in entry.value) link.id,
            ];
          }
          await _dances.update(
            dance.copyWith(links: [...dance.links, ...entry.value]),
          );
        }
      }
      // Last: only an import that otherwise succeeded moves any level.
      await _placeLevels([...keptLevelsInserted, ...keptLevelsRestored]);
    } catch (_) {
      await _programs.hardDelete(insertedIds);
      for (final prior in priorStates) {
        await _programs.update(prior);
      }
      for (final id in restoredProgramIds) {
        await _programs.softDelete(id, at: now);
      }
      await _venues.hardDelete(insertedVenueIds);
      await _pipeline.undo(danceSession);
      await _revertUserFieldDefinitions(keptInserted, keptRestored);
      await _revertPublishedSources(keptSourcesInserted, keptSourcesRestored);
      await _revertDifficultyLevels(keptLevelsInserted, keptLevelsRestored);
      // Last, so the older steps above run even if this one throws.
      await _removeLinks(linksAddedToEarlier);
      rethrow;
    }

    return CcUsrImportResult(
      danceSession: danceSession,
      programs: persisted,
      programIssues: issues,
      insertedProgramIds: insertedIds,
      updatedProgramPriorStates: priorStates,
      restoredProgramIds: restoredProgramIds,
      programRestoreAt: restoredProgramIds.isEmpty ? null : now,
      insertedVenueIds: insertedVenueIds,
      relatedDanceLinkIssues: relatedDanceLinkIssues,
      insertedCustomFieldIds: keptInserted,
      restoredCustomFieldIds: keptRestored,
      insertedPublishedSourceIds: keptSourcesInserted,
      restoredPublishedSourceIds: keptSourcesRestored,
      insertedDifficultyLevelIds: keptLevelsInserted,
      restoredDifficultyLevelIds: keptLevelsRestored,
      customFieldIssues: fieldIssues,
      linksAddedToEarlierDances: linksAddedToEarlier,
    );
  }

  /// Commits the dances of [batch] alone — no programs, no related-dance links
  /// — for the review's per-row Edit, which writes one dance before the rest of
  /// the file is imported. Unlike a bare [ImportPipeline.commit], it first
  /// matches or creates the definitions behind the CC `UserDefined_*` values
  /// (as [commit] does), since [DanceRepository] refuses a value for a field
  /// that does not exist: without this, every dance with a user-field value
  /// failed to commit. It resolves the published sources behind CC `Reference`
  /// citations the same way (#1974).
  ///
  /// A definition or source no committed dance uses is dropped again, and a
  /// commit that throws removes the ones it created. Those a committed dance
  /// holds stay, as the dance does; the per-row Edit has no undo, and a later
  /// batch [commit] reuses them rather than recording them for its own undo.
  /// Pass
  /// the CC ids of the dances written here to a later [commit] as its
  /// `earlierDanceIds` so its sets and related dances can name them.
  Future<ImportSession> commitDances(
    ImportBatchResult batch, {
    required DateTime now,
    String Function()? newId,
    Map<int, DedupeResolution> resolutions = const {},
    List<String> defaultTagIds = const [],
  }) async {
    final committed = await _commitDancesWithFields(
      batch,
      now: now,
      newId: newId ?? uuidV4,
      resolutions: resolutions,
      defaultTagIds: defaultTagIds,
    );
    try {
      await _placeLevels([
        ...committed.insertedLevelIds,
        ...committed.restoredLevelIds,
      ]);
    } catch (_) {
      await _pipeline.undo(committed.session);
      await _revertUserFieldDefinitions(
        committed.insertedFieldIds,
        committed.restoredFieldIds,
      );
      await _revertPublishedSources(
        committed.insertedSourceIds,
        committed.restoredSourceIds,
      );
      await _revertDifficultyLevels(
        committed.insertedLevelIds,
        committed.restoredLevelIds,
      );
      rethrow;
    }
    return committed.session;
  }

  /// The dance half of [commit] and [commitDances]: resolves the CC user-field
  /// definitions [batch] needs, commits its dances through the pipeline, and
  /// drops any definition no committed dance ended up using. Returns the
  /// session with the definitions kept; on a throw nothing is left behind.
  Future<
    ({
      ImportSession session,
      List<String> insertedFieldIds,
      List<String> restoredFieldIds,
      List<ImportIssue> fieldIssues,
      List<String> insertedSourceIds,
      List<String> restoredSourceIds,
      List<String> insertedLevelIds,
      List<String> restoredLevelIds,
    })
  >
  _commitDancesWithFields(
    ImportBatchResult batch, {
    required DateTime now,
    required String Function() newId,
    required Map<int, DedupeResolution> resolutions,
    required List<String> defaultTagIds,
    void Function(int done, int total)? onProgress,
  }) async {
    // Definitions first: a dance cannot commit a value for a field that does
    // not exist yet (`DanceRepository` refuses it), and they are reverted with
    // the rest of the import.
    final fields = await _resolveUserFieldDefinitions(
      batch,
      now: now,
      newId: newId,
    );
    // Published sources likewise: a citation names a source row (#1974).
    final ({
      ImportBatchResult batch,
      List<String> inserted,
      List<String> restored,
    })
    sources;
    try {
      sources = await _resolvePublishedSources(
        fields.batch,
        now: now,
        newId: newId,
      );
    } catch (_) {
      await _revertUserFieldDefinitions(fields.inserted, fields.restored);
      rethrow;
    }
    // And the difficulty levels behind CC combined levels (#1973).
    final ({
      ImportBatchResult batch,
      List<String> inserted,
      List<String> restored,
    })
    levels;
    try {
      levels = await _resolveDifficultyLevels(sources.batch, now: now);
    } catch (_) {
      await _revertUserFieldDefinitions(fields.inserted, fields.restored);
      await _revertPublishedSources(sources.inserted, sources.restored);
      rethrow;
    }
    final ImportSession danceSession;
    try {
      danceSession = await _pipeline.commit(
        levels.batch,
        now: now,
        newId: newId,
        resolutions: resolutions,
        // Dances only: programs carry no tags.
        defaultTagIds: defaultTagIds,
        onProgress: onProgress,
      );
    } catch (_) {
      await _revertUserFieldDefinitions(fields.inserted, fields.restored);
      await _revertPublishedSources(sources.inserted, sources.restored);
      await _revertDifficultyLevels(levels.inserted, levels.restored);
      rethrow;
    }
    // A definition no committed dance ended up using (every dance that carried
    // its key was skipped) is dropped now rather than left as an orphan. Inside
    // its own compensation: the dances are committed by now, so a failure here
    // must not leave them without an undo handle.
    final keptInserted = <String>[];
    final keptRestored = <String>[];
    final keptSourcesInserted = <String>[];
    final keptSourcesRestored = <String>[];
    final keptLevelsInserted = <String>[];
    final keptLevelsRestored = <String>[];
    try {
      for (final id in levels.inserted) {
        if (await _removeUnusedLevel(id, permanent: true)) continue;
        keptLevelsInserted.add(id);
      }
      for (final id in levels.restored) {
        if (await _removeUnusedLevel(id, permanent: false)) continue;
        keptLevelsRestored.add(id);
      }
      for (final id in sources.inserted) {
        if (await _removeUnusedSource(id, permanent: true)) continue;
        keptSourcesInserted.add(id);
      }
      for (final id in sources.restored) {
        if (await _removeUnusedSource(id, permanent: false)) continue;
        keptSourcesRestored.add(id);
      }
      for (final id in fields.inserted) {
        if (await _customFields.isInUse(id)) {
          keptInserted.add(id);
        } else {
          await _customFields.delete(id, permanent: true);
        }
      }
      for (final id in fields.restored) {
        if (await _customFields.isInUse(id)) {
          keptRestored.add(id);
        } else {
          await _customFields.delete(id);
        }
      }
    } catch (_) {
      await _pipeline.undo(danceSession);
      await _revertUserFieldDefinitions(fields.inserted, fields.restored);
      await _revertPublishedSources(sources.inserted, sources.restored);
      await _revertDifficultyLevels(levels.inserted, levels.restored);
      rethrow;
    }
    return (
      session: danceSession,
      insertedFieldIds: keptInserted,
      restoredFieldIds: keptRestored,
      fieldIssues: fields.issues,
      insertedSourceIds: keptSourcesInserted,
      restoredSourceIds: keptSourcesRestored,
      insertedLevelIds: keptLevelsInserted,
      restoredLevelIds: keptLevelsRestored,
    );
  }

  /// Matches or creates the published source behind each placeholder citation
  /// in [batch] (a CC `Reference`, #1974), and returns [batch] with each
  /// placeholder id rewritten to the real one.
  ///
  /// A source is matched by title (#1974), compared as [naturalKeyMatchKey]
  /// does (normalised, case-folded), so a book the user entered with its author
  /// or year is reused rather than duplicated. Among several, a live one beats a
  /// tombstone, which is restored, then an exact title beats a case variant,
  /// then the smallest id, so the pick does not depend on load order. Otherwise
  /// a source with that title is created, once for all its case variants.
  Future<
    ({ImportBatchResult batch, List<String> inserted, List<String> restored})
  >
  _resolvePublishedSources(
    ImportBatchResult batch, {
    required DateTime now,
    required String Function() newId,
  }) async {
    final titles = <String>{
      for (final record in batch.records)
        for (final citation in record.draft.dance.sourceCitations)
          ?ccPublishedSourceTitleOf(citation.sourceId),
    };
    if (titles.isEmpty) {
      return (
        batch: batch,
        inserted: const <String>[],
        restored: const <String>[],
      );
    }
    final existing = await _sources.listAllWithDeleted();
    final idByTitle = <String, String>{};
    final idByKey = <String, String>{};
    final inserted = <String>[];
    final restored = <String>[];
    try {
      for (final title in titles) {
        final key = naturalKeyMatchKey(title);
        if (idByKey[key] case final id?) {
          idByTitle[title] = id;
          continue;
        }
        final matches =
            [
              for (final item in existing)
                if (naturalKeyMatchKey(item.source.title) == key) item,
            ]..sort((a, b) {
              if (a.deleted != b.deleted) return a.deleted ? 1 : -1;
              final aExact = a.source.title == title;
              if (aExact != (b.source.title == title)) return aExact ? -1 : 1;
              return a.source.id.compareTo(b.source.id);
            });
        if (matches.isNotEmpty) {
          final match = matches.first;
          if (match.deleted) {
            await _sources.restore(match.source.id, at: now);
            restored.add(match.source.id);
          }
          idByTitle[title] = idByKey[key] = match.source.id;
          continue;
        }
        final id = newId();
        await _sources.upsert(
          PublishedSource(id: id, title: title),
          at: now,
        );
        inserted.add(id);
        idByTitle[title] = idByKey[key] = id;
      }
    } catch (_) {
      await _revertPublishedSources(inserted, restored);
      rethrow;
    }

    ImportRecordPlan rewrite(ImportRecordPlan record) {
      final citations = record.draft.dance.sourceCitations;
      if (!citations.any((c) => ccPublishedSourceTitleOf(c.sourceId) != null)) {
        return record;
      }
      return ImportRecordPlan(
        draft: record.draft.copyWith(
          dance: record.draft.dance.copyWith(
            sourceCitations: [
              for (final c in citations)
                switch (ccPublishedSourceTitleOf(c.sourceId)) {
                  final title? => SourceCitation(
                    sourceId: idByTitle[title]!,
                    page: c.page,
                    number: c.number,
                  ),
                  null => c,
                },
            ],
          ),
        ),
        verdict: record.verdict,
      );
    }

    return (
      batch: ImportBatchResult(
        records: [for (final record in batch.records) rewrite(record)],
        errors: batch.errors,
        warnings: batch.warnings,
        dedupeIndex: batch.dedupeIndex,
      ),
      inserted: inserted,
      restored: restored,
    );
  }

  /// Removes source [id] when no live dance cites it, permanently for one this
  /// import created or back to a tombstone for one it restored, and reports
  /// whether it did. The repository refuses a cited source in its own
  /// transaction.
  Future<bool> _removeUnusedSource(String id, {required bool permanent}) async {
    try {
      await _sources.delete(id, permanent: permanent);
      return true;
    } on StateError {
      return false; // Still cited by a live dance.
    }
  }

  /// Reverts the sources [inserted] (removed) and [restored] (tombstoned
  /// again), leaving any a surviving dance still cites.
  Future<void> _revertPublishedSources(
    List<String> inserted,
    List<String> restored,
  ) async {
    for (final id in inserted) {
      await _removeUnusedSource(id, permanent: true);
    }
    for (final id in restored) {
      await _removeUnusedSource(id, permanent: false);
    }
  }

  /// Matches or creates the difficulty level behind each CC combined level in
  /// [batch] ("Easy/Intermediate", #1973), and returns [batch] with each such
  /// dance pointed at it and its [ccNewLevelIssueCode] issue dropped.
  ///
  /// The pipeline has already pointed a dance at a live level of that name;
  /// this resolves the rest, so it also covers levels another record in the
  /// same file created. A level is matched by name ignoring case and spacing
  /// ([ccLevelNameKey], maintainer decision): a live one is reused, a
  /// tombstoned one is restored, and otherwise one is created. A created level
  /// goes between the levels its span lies between on CC's scale
  /// ([ccLevelScaleKey], maintainer decision): after the last level below it,
  /// else before the first level above it, else last.
  Future<
    ({ImportBatchResult batch, List<String> inserted, List<String> restored})
  >
  _resolveDifficultyLevels(
    ImportBatchResult batch, {
    required DateTime now,
  }) async {
    bool unresolved(ImportRecordPlan record) =>
        record.draft.dance.difficultyLevelId == null &&
        record.draft.difficultyLevelLabel != null &&
        record.draft.issues.any((i) => i.code == ccNewLevelIssueCode);
    final labels = <String>{
      for (final record in batch.records)
        if (unresolved(record)) record.draft.difficultyLevelLabel!,
    };
    if (labels.isEmpty) {
      return (
        batch: batch,
        inserted: const <String>[],
        restored: const <String>[],
      );
    }
    final idByKey = <String, String>{};
    final inserted = <String>[];
    final restored = <String>[];
    try {
      final existing = await _levels.listAllWithDeleted();
      for (final label in labels) {
        final key = ccLevelNameKey(label);
        if (idByKey.containsKey(key)) continue;
        final matches =
            [
              for (final item in existing)
                if (ccLevelNameKey(item.level.label) == key) item,
            ]..sort((a, b) {
              if (a.deleted != b.deleted) return a.deleted ? 1 : -1;
              return a.level.id.compareTo(b.level.id);
            });
        if (matches.isNotEmpty) {
          final match = matches.first;
          if (match.deleted) {
            await _levels.restore(match.level.id, at: now);
            restored.add(match.level.id);
          }
          idByKey[key] = match.level.id;
          continue;
        }
        // Created after every level for now: [_placeLevels] moves it once
        // the import has kept it, so an import that fails or skips the dance
        // rewrites no other level.
        final created = await _levels.createCustom(
          label: label,
          position: [
            for (final level in await _levels.listAll()) level.position + 1,
          ].fold(0, (a, b) => a > b ? a : b),
        );
        inserted.add(created.id);
        idByKey[key] = created.id;
      }
    } catch (_) {
      await _revertDifficultyLevels(inserted, restored);
      rethrow;
    }

    ImportRecordPlan rewrite(ImportRecordPlan record) {
      if (!unresolved(record)) return record;
      final id = idByKey[ccLevelNameKey(record.draft.difficultyLevelLabel!)]!;
      return ImportRecordPlan(
        draft: record.draft.copyWith(
          dance: record.draft.dance.copyWith(difficultyLevelId: id),
          issues: [
            for (final issue in record.draft.issues)
              if (issue.code != ccNewLevelIssueCode) issue,
          ],
        ),
        verdict: record.verdict,
      );
    }

    return (
      batch: ImportBatchResult(
        records: [for (final record in batch.records) rewrite(record)],
        errors: batch.errors,
        warnings: batch.warnings,
        dedupeIndex: batch.dedupeIndex,
      ),
      inserted: inserted,
      restored: restored,
    );
  }

  /// Places the levels [ids] this import kept (created or restored) among
  /// the user's levels by CC's scale (maintainer decision, #1973).
  ///
  /// The other levels keep their positions, gaps included: a placed level
  /// takes the position after the level before it, and a level after it moves
  /// up only while it would collide. So only the levels that have to move are
  /// written, stamped now rather than with the import's start time.
  Future<void> _placeLevels(List<String> ids) async {
    if (ids.isEmpty) return;
    final moving = ids.toSet();
    final order = [
      for (final level in await _levels.listAll())
        if (!moving.contains(level.id)) level,
    ];
    for (final id in ids) {
      final level = await _levels.getById(id);
      if (level == null) continue;
      order.insert(_levelInsertIndex(order, level), level);
    }
    final positions = <String, int>{};
    var last = -1;
    for (final level in order) {
      final position = !moving.contains(level.id) && level.position > last
          ? level.position
          : last + 1;
      if (position != level.position) positions[level.id] = position;
      last = position;
    }
    await _levels.setPositions(positions);
  }

  /// Where [level] goes in [order] (the live levels, by position): after the
  /// last level that sits below it on CC's scale, else before the first that
  /// sits above it, else last. "Below" follows the user's own direction: a
  /// list ordered hardest first is read hardest first. Levels the scale says
  /// nothing about keep their places around it.
  static int _levelInsertIndex(
    List<DifficultyLevel> order,
    DifficultyLevel level,
  ) {
    final own = ccLevelScaleKey(level);
    if (own == null) return order.length;
    final known = [for (final other in order) ?ccLevelScaleKey(other)];
    final sign = known.length >= 2 && known.first > known.last ? -1 : 1;
    final key = own * sign;
    final keys = [
      for (final other in order)
        if (ccLevelScaleKey(other) case final k?) k * sign else null,
    ];
    final below = keys.lastIndexWhere((k) => k != null && k < key);
    if (below >= 0) return below + 1;
    final above = keys.indexWhere((k) => k != null && k > key);
    return above >= 0 ? above : order.length;
  }

  /// Removes level [id] when no dance uses it, permanently for one this
  /// import created or back to a tombstone for one it restored, and reports
  /// whether it did. A tombstoned dance still counts as a use: it can be
  /// restored.
  Future<bool> _removeUnusedLevel(String id, {required bool permanent}) async {
    if (permanent) {
      if (await _levels.isInUse(id)) return false;
      await _levels.hardDelete([id]);
      return true;
    }
    try {
      await _levels.delete(id);
      return true;
    } on DifficultyLevelInUse {
      return false;
    }
  }

  /// Reverts the levels [inserted] (removed) and [restored] (tombstoned
  /// again), leaving any a surviving dance still uses.
  Future<void> _revertDifficultyLevels(
    List<String> inserted,
    List<String> restored,
  ) async {
    for (final id in inserted) {
      await _removeUnusedLevel(id, permanent: true);
    }
    for (final id in restored) {
      await _removeUnusedLevel(id, permanent: false);
    }
  }

  /// Removes the links named in [linkIdsByDanceId] from each of those dances,
  /// leaving every other link, and any dance since deleted, alone.
  Future<void> _removeLinks(Map<String, List<String>> linkIdsByDanceId) async {
    for (final entry in linkIdsByDanceId.entries) {
      final dance = await _dances.getById(entry.key, includeDeleted: true);
      if (dance == null) continue;
      final remove = entry.value.toSet();
      if (!dance.links.any((l) => remove.contains(l.id))) continue;
      await _dances.update(
        dance.copyWith(
          links: [
            for (final l in dance.links)
              if (!remove.contains(l.id)) l,
          ],
        ),
      );
    }
  }

  /// Matches or creates one text definition per CC user-field key carried by
  /// [batch] (the label comes from the placeholder, see
  /// [kCcUserFieldIdPrefix]), and returns [batch] with each placeholder field id
  /// rewritten to the real definition id.
  ///
  /// Matching follows the native archive importer (`ShareMetadataImporter`),
  /// except that keys are compared case-folded (`naturalKeyMatchKey`), wider
  /// than the repository's byte-exact key check: a *live text* definition under the same key is reused untouched, and a
  /// tombstoned *text* one is revived. A key held by a definition of **another
  /// type** is never reused (that would store text in a number or choice field)
  /// and `upsert` would refuse to create onto it, so the field is created under
  /// `<key>_2`, `<key>_3`, … and a `cc_user_field_key_conflict` note is raised.
  /// New definitions are text, hidden from the list, searchable, and shareable —
  /// the default every new field gets.
  Future<
    ({
      ImportBatchResult batch,
      List<String> inserted,
      List<String> restored,
      List<ImportIssue> issues,
    })
  >
  _resolveUserFieldDefinitions(
    ImportBatchResult batch, {
    required DateTime now,
    required String Function() newId,
  }) async {
    // Key → label, in first-seen order; the first dance to use a key names it.
    final labelByKey = <String, String>{};
    for (final record in batch.records) {
      for (final value in record.draft.dance.customFields) {
        final field = ccUserFieldOfPlaceholder(value.fieldId);
        if (field != null) labelByKey.putIfAbsent(field.key, () => field.label);
      }
    }
    final needed = labelByKey.keys;
    if (needed.isEmpty) {
      return (
        batch: batch,
        inserted: const <String>[],
        restored: const <String>[],
        issues: const <ImportIssue>[],
      );
    }

    final existing = await _customFields.listAllWithDeleted();
    // Every existing row under a case-folded key. The repository's own key
    // check is byte-exact, so `Tempo` and `tempo` can both exist; matching is
    // deliberately wider than that, so a key typed as `Tempo` is found by the
    // CC column "Tempo", and [find] then picks among the variants.
    final byFolded = <String, List<({CustomFieldDef field, bool deleted})>>{};
    for (final item in existing) {
      byFolded
          .putIfAbsent(naturalKeyMatchKey(item.field.key), () => [])
          .add(item);
    }
    // The row [candidate] resolves to, or null when its key is free. A text
    // definition beats one of another type, a live one beats a tombstone, and
    // an exact key beats a case variant; ties go to the smallest id (the
    // precedence `ShareMetadataImporter` applies), so the choice is
    // load-order free and never passes over an exact text match.
    ({CustomFieldDef field, bool deleted})? find(String candidate) {
      final rows = byFolded[naturalKeyMatchKey(candidate)];
      if (rows == null || rows.isEmpty) return null;
      final exact = normalizeShareableText(candidate);
      int rank(({CustomFieldDef field, bool deleted}) r) =>
          (r.field.type == CustomFieldType.text ? 0 : 4) +
          (r.deleted ? 2 : 0) +
          (r.field.key == exact ? 0 : 1);
      return rows.reduce((best, r) {
        final byRank = rank(r).compareTo(rank(best));
        if (byRank != 0) return byRank < 0 ? r : best;
        return r.field.id.compareTo(best.field.id) < 0 ? r : best;
      });
    }

    final usedIds = {for (final item in existing) item.field.id};
    String freshId() {
      for (var attempt = 0; attempt < 100; attempt++) {
        final id = newId();
        if (usedIds.add(id)) return id;
      }
      throw StateError('unable to allocate a unique custom field id');
    }

    final idByKey = <String, String>{};
    final inserted = <String>[];
    final restored = <String>[];
    final issues = <ImportIssue>[];
    // Canonical key → the CC column key this import resolved onto it, so a
    // suffix candidate another column already claimed is skipped, not shared.
    final createdFor = <String, String>{};
    try {
      for (final key in needed) {
        final label = labelByKey[key]!;
        var candidate = key;
        for (var n = 2; ; n++) {
          final canonical = naturalKeyMatchKey(candidate);
          final match = find(candidate);
          if (match == null) {
            final def = CustomFieldDef(
              id: freshId(),
              key: candidate,
              label: label,
              type: CustomFieldType.text,
            );
            final actualId = await _customFields.upsert(def, at: now);
            inserted.add(actualId);
            if (actualId != def.id) {
              throw StateError(
                'custom field "$candidate" resolved to an unexpected id',
              );
            }
            byFolded[canonical] = [(field: def, deleted: false)];
            createdFor[canonical] = key;
            idByKey[key] = def.id;
            break;
          }
          final claimedByOther =
              createdFor.containsKey(canonical) && createdFor[canonical] != key;
          if (match.field.type == CustomFieldType.text && !claimedByOther) {
            if (match.deleted) {
              await _customFields.restore(match.field.id, at: now);
              restored.add(match.field.id);
              final rows = byFolded[canonical]!;
              rows[rows.indexOf(match)] = (field: match.field, deleted: false);
            }
            // Claimed even when reused untouched: two columns must never
            // resolve to one definition, or a dance would carry two values
            // for the same field.
            createdFor[canonical] = key;
            idByKey[key] = match.field.id;
            break;
          }
          candidate = '${key}_$n';
        }
        if (candidate != key) {
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.warning,
              code: 'cc_user_field_key_conflict',
              message:
                  'Caller\'s Companion field "$label" could not use the key '
                  '"$key" (a field of another type holds it); imported as '
                  '"$candidate".',
            ),
          );
        }
      }
    } catch (_) {
      await _revertUserFieldDefinitions(inserted, restored);
      rethrow;
    }

    // Only a draft that carries a placeholder is copied: a library-scale batch
    // is mostly dances with no user columns.
    ImportRecordPlan rewrite(ImportRecordPlan record) {
      final values = record.draft.dance.customFields;
      if (!values.any((v) => ccUserFieldOfPlaceholder(v.fieldId) != null)) {
        return record;
      }
      return ImportRecordPlan(
        draft: record.draft.copyWith(
          dance: record.draft.dance.copyWith(
            customFields: [
              for (final value in values)
                switch (ccUserFieldOfPlaceholder(value.fieldId)) {
                  final field? => CustomFieldValue(
                    fieldId: idByKey[field.key]!,
                    value: value.value,
                  ),
                  null => value,
                },
            ],
          ),
        ),
        verdict: record.verdict,
      );
    }

    final rewritten = ImportBatchResult(
      records: [for (final record in batch.records) rewrite(record)],
      errors: batch.errors,
      warnings: batch.warnings,
      dedupeIndex: batch.dedupeIndex,
    );
    return (
      batch: rewritten,
      inserted: inserted,
      restored: restored,
      issues: issues,
    );
  }

  /// Removes the definitions [inserted] and re-tombstones the ones [restored],
  /// each guarded in the repository's own transaction: one a surviving dance
  /// still holds a value for is left alone.
  Future<void> _revertUserFieldDefinitions(
    List<String> inserted,
    List<String> restored,
  ) async {
    for (final id in inserted) {
      try {
        await _customFields.delete(id, permanent: true);
      } on CustomFieldInUseException {
        // A surviving dance holds a value for it.
      }
    }
    for (final id in restored) {
      try {
        await _customFields.delete(id);
      } on CustomFieldInUseException {
        // A surviving dance holds a value for it.
      }
    }
  }

  /// Convenience end-to-end import of a `.USR` [bytes] payload: [plan]s and
  /// [commit]s in one call using default dedupe handling (ambiguous records are
  /// skipped, never guessed — the pipeline default). The file is decoded once:
  /// planning reads it through the adapter, and the program build reuses that
  /// same read ([CallersCompanionUsrAdapter.discoveredArchive]). A file that
  /// cannot be read throws the [ImportError] planning captured (at
  /// [ImportStage.discover]) rather than being decoded a second time. The app's
  /// review flow can instead call [plan]/[commit] separately to let the user
  /// resolve ambiguous dances.
  Future<CcUsrImportResult> import(
    Uint8List bytes, {
    required DateTime now,
    required bool venueEntityMode,
    String Function()? newId,
    String Function()? newSlotId,
  }) async {
    final batch = await plan(bytes);
    final archive = _adapter.discoveredArchive;
    if (archive == null) {
      // `discover` failed. The pipeline turns that into an error batch instead
      // of rethrowing, and decoding the file again here would only fail the same
      // way — after a second full scan of a file that may be hundreds of MiB.
      // Surface the error it already captured. The pipeline returns an
      // adapter's own ImportError as-is; the `cause` unwrap covers any other
      // failure it wrapped.
      final captured = batch.errors.firstWhere(
        (e) => e.stage == ImportStage.discover,
        orElse: () => ImportError(
          stage: ImportStage.discover,
          source: _adapter.source,
          message: 'The .USR file could not be read.',
        ),
      );
      final cause = captured.cause;
      throw cause is ImportError ? cause : captured;
    }
    return commit(
      batch,
      archive,
      now: now,
      venueEntityMode: venueEntityMode,
      newId: newId,
      newSlotId: newSlotId,
    );
  }

  /// Reverts a committed [result]: hard-deletes the **inserted** programs (slots
  /// cascade) and restores every **updated** (re-imported) program to its
  /// captured prior state, then removes the **inserted** venues (issue #687),
  /// **before** delegating to [ImportPipeline.undo] for the dances, authors and
  /// updated-dance rollbacks. Idempotent — a second call is a no-op.
  ///
  /// Programs are handled first so the revert is clean regardless of the
  /// `program_slots.dance_id → dances` foreign key (which is `SET NULL`, so the
  /// order is not strictly required for integrity, but removing programs first
  /// keeps the intent obvious) — and so no program still references a venue
  /// this import is about to remove.
  ///
  /// Venue removal goes through [VenueRepository.hardDelete], mirroring
  /// `CompendiumArchiveImporter.undo` and the commit-failure path above: after
  /// a successful import a surviving user program may have linked to a venue
  /// this import minted (e.g. by deduping onto its normalized-location key), so
  /// an unconditional erase would orphan that program's `venueId`. `hardDelete`
  /// retains a venue **any** surviving program row still names, tombstoned
  /// programs included, and tombstones an already-published one.
  /// `delete(permanent: true)` is deliberately *not* used: its guard counts
  /// live programs only (issue #1328), so it erased a venue a tombstoned
  /// program still named — issue #1357.
  ///
  /// **Related-dance links (issue #688)** on this import's own dances need no
  /// dedicated revert step here — [ImportPipeline.undo] already fully reverts
  /// them as a side effect of its own dance rollback. Apart from the dances an
  /// earlier per-row Edit wrote (below), every dance [commit] could have
  /// attached a `relatedDance` link to is a dance resolved through
  /// `_danceIdByCcRowId(result.danceSession)`, which only ever names dances
  /// appearing in `result.danceSession.records`. Every such dance is either
  /// freshly **inserted** this commit (hard-deleted wholesale by the call
  /// below — its links vanish with it) or was matched by **reimport/link**
  /// (both actions capture a full pre-commit `Dance` snapshot — *including*
  /// its pre-commit `links` — into `updatedDancePriorStates`, restored
  /// verbatim below). Restoring a dance's prior snapshot fully replaces its
  /// `dance_links` rows (a full delete-then-reinsert on every
  /// `DanceRepository.update`), so any related-dance link [commit] appended
  /// afterward is discarded along with the rest of the reverted state — with
  /// zero additional bookkeeping. A dance named by `earlierDanceIds` is not
  /// this import's to restore, so the links appended to it are removed by id
  /// ([CcUsrImportResult.linksAddedToEarlierDances]) and the dance kept.
  ///
  /// [now] is an optional clock seam for deterministic callers; production
  /// undo timestamps default to the current UTC time.
  Future<void> undo(
    CcUsrImportResult result, {
    DateTime Function()? now,
  }) async {
    if (result.isUndone) return;
    final undoAt = (now?.call() ?? DateTime.now()).toUtc();
    await _programs.hardDelete(result.insertedProgramIds);
    for (final prior in result.updatedProgramPriorStates) {
      await _programs.update(prior);
    }
    if (result.programRestoreAt != null) {
      for (final id in result.restoredProgramIds) {
        await _programs.softDelete(id, at: undoAt);
      }
    }
    // Erasing for the same reason the dances/programs above are hard-deleted:
    // a rollback must leave nothing behind to publish. `hardDelete` owns both
    // exceptions to that — a published venue is tombstoned instead, and a venue
    // any surviving program row still names (tombstoned ones included) is left
    // untouched rather than orphaning that reference.
    await _venues.hardDelete(result.insertedVenueIds);
    await _pipeline.undo(result.danceSession);
    // After the dances: the guard refuses to remove a definition a live dance
    // still holds a value for, so the definitions can only go once this
    // import's dances have.
    await _revertUserFieldDefinitions(
      result.insertedCustomFieldIds,
      result.restoredCustomFieldIds,
    );
    // After the dances too: the repository refuses a source a live dance cites.
    await _revertPublishedSources(
      result.insertedPublishedSourceIds,
      result.restoredPublishedSourceIds,
    );
    // After the dances too: a level a dance uses is not removed.
    await _revertDifficultyLevels(
      result.insertedDifficultyLevelIds,
      result.restoredDifficultyLevelIds,
    );
    // Last, so the older steps above run even if this one throws.
    await _removeLinks(result.linksAddedToEarlierDances);
    result._undone = true;
  }

  /// Rebuilds [src] under an existing program [id] and [createdAt] (preserving
  /// the matched program's identity/creation stamp on a re-import) while keeping
  /// every other field — title, slots, event metadata, provenance, updatedAt —
  /// from the freshly built program.
  ///
  /// [priorVenueId] carries the matched program's existing `venueId` forward
  /// **when set** — a `.USR` archive has no concept of this app-local venue
  /// entity link of its own, so overwriting an established link with null (or
  /// with a fresh guess) would silently drop/flip-flop app-local state the
  /// source cannot reconstruct or express (issue #687 bullet 6). When there is
  /// no prior link (`priorVenueId` is `null` — a first-time import, or a
  /// re-import of a program nobody has linked yet), [src.venueId] passes
  /// through instead, so a venue-entity-mode resolution computed for *this*
  /// commit (see [commit]'s venue resolution block) isn't discarded.
  Program _rebuildProgramWithId(
    Program src, {
    required String id,
    required DateTime createdAt,
    required String? priorVenueId,
  }) => Program(
    id: id,
    title: src.title,
    eventDate: src.eventDate,
    venue: src.venue,
    venueId: priorVenueId ?? src.venueId,
    band: src.band,
    caller: src.caller,
    dancerLevel: src.dancerLevel,
    notes: src.notes,
    status: src.status,
    hideAlternates: src.hideAlternates,
    slots: src.slots,
    createdAt: createdAt,
    updatedAt: src.updatedAt,
    provenance: src.provenance,
  );

  /// Builds the CC-dance-id → new-Compendium-dance-id map from the committed
  /// [session] alone. Each [CommittedRecord] carries its own
  /// [CommittedRecord.externalId] (the CC `zk_Dance_ID` value that `SetItem`
  /// rows reference) alongside the [CommittedRecord.danceId] the commit minted,
  /// so the map is a direct association with **no** dependence on the original
  /// batch's ordering or index alignment. Skips, errors, and records with a
  /// missing external id or dance id contribute nothing.
  ///
  /// Duplicate-externalId policy: a CC archive's `zk_Dance_ID` is expected to be
  /// unique, so normally each external id appears once. If two committed records
  /// ever share one, this is **last-wins** — records are visited in commit
  /// (discovery) order and a later assignment overwrites an earlier one, so
  /// `SetItem` FKs resolve to the most recently committed dance for that id.
  Map<String, String> _danceIdByCcRowId(ImportSession session) {
    final map = <String, String>{};
    for (final record in session.records) {
      final danceId = record.danceId;
      final externalId = record.externalId;
      if (!record.succeeded || danceId == null) continue;
      if (externalId == null || externalId.isEmpty) continue;
      map[externalId] = danceId; // last-wins on the rare duplicate id
    }
    return map;
  }
}

/// Normalizes a cleaned `.USR` `Set.location` string for the this-commit-only
/// same-location collapse (see [CallersCompanionUsrImporter.commit]'s venue
/// resolution block): trims, lowercases and collapses internal whitespace
/// runs, mirroring `venue_dedupe.dart`'s own private `_normalizeField` so two
/// sets differing only in case or spacing ("Grange Hall" / "  GRANGE  Hall ")
/// still collapse to the same minted venue. Deliberately **not** exported —
/// this local collapse only governs de-duplication *within a single import*;
/// it is never used for the cross-import [venueFingerprint]/
/// [VenueFingerprintIndex] match, which stays keyed on the full
/// (name + city/address) descriptive fields.
String _normalizeLocationKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
