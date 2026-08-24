import 'dart:typed_data';

import '../model/dance.dart';
import '../model/dance_link.dart';
import '../model/enums.dart';
import '../model/program.dart';
import '../model/venue.dart';
import '../storage/repositories/dance_repository.dart';
import '../storage/repositories/program_repository.dart';
import '../storage/repositories/venue_repository.dart';
import '../util/uuid.dart';
import 'callers_companion_programs.dart';
import 'callers_companion_related_dances.dart';
import 'callers_companion_usr_adapter.dart';
import 'callers_companion_usr_archive.dart';
import 'dedupe.dart';
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
  }) : programs = List.unmodifiable(programs),
       programIssues = List.unmodifiable(programIssues),
       insertedProgramIds = List.unmodifiable(insertedProgramIds),
       updatedProgramPriorStates = List.unmodifiable(updatedProgramPriorStates),
       restoredProgramIds = List.unmodifiable(restoredProgramIds),
       insertedVenueIds = List.unmodifiable(insertedVenueIds),
       relatedDanceLinkIssues = List.unmodifiable(relatedDanceLinkIssues);

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
  CallersCompanionUsrImporter(this._pipeline, this._programs, this._venues);

  final ImportPipeline _pipeline;
  final ProgramRepository _programs;
  final VenueRepository _venues;

  /// The [DanceRepository] the related-dance-link step (issue #688) reads
  /// and updates the just-committed dances through. Reused from [_pipeline]
  /// itself — rather than taken as a separate constructor dependency — so
  /// this importer can never be wired with a [DanceRepository] instance
  /// different from the one [_pipeline] actually committed dances through
  /// (which would risk updating a different DB/transaction than the commit
  /// happened in).
  DanceRepository get _dances => _pipeline.dances;

  final CallersCompanionUsrAdapter _adapter = CallersCompanionUsrAdapter();

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
  /// archive `Dance_Related` pair is resolved via [_danceIdByCcRowId] and
  /// turned into a directed `relatedDance` [DanceLink] on the source dance
  /// (see [buildCcRelatedDanceLinks]'s doc for the full directionality,
  /// dedupe and OWASP-hardening rationale). A pair with an unresolved
  /// endpoint is skipped with a warning [ImportIssue] on
  /// [CcUsrImportResult.relatedDanceLinkIssues] — never a dangling
  /// `targetDanceId`.
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
  }) async {
    final mintId = newId ?? uuidV4;
    final danceSession = await _pipeline.commit(
      batch,
      now: now,
      newId: mintId,
      resolutions: resolutions,
    );

    final danceIdByCcRowId = _danceIdByCcRowId(danceSession);
    final built = buildCcPrograms(
      archive,
      danceIdByCcRowId: danceIdByCcRowId,
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
      // No new undo bookkeeping is needed for the links themselves: every
      // candidate source dance here is, by construction, a dance
      // [_danceIdByCcRowId] resolved from `danceSession.records` — and EVERY
      // such dance is already tracked by [ImportPipeline.undo], either via
      // `insertedDanceIds` (create/duplicate — hard-deleted wholesale) or via
      // `updatedDancePriorStates` (reimport/link — the pipeline captures a
      // full pre-commit snapshot of `_dances.getById(id)` **before any field
      // is touched**, for BOTH actions). [DanceRepository]'s upsert fully
      // replaces a dance's `dance_links` rows on every `update`, so restoring
      // that prior snapshot on undo already reverts any related-dance link
      // appended here, with zero additional tracking. See
      // `callers_companion_related_dances.dart` and this method's `undo` doc
      // for the full argument.
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
        final linkResult = buildCcRelatedDanceLinks(
          archive,
          danceIdByCcRowId: danceIdByCcRowId,
          existingLinksByDanceId: existingLinksByDanceId,
          newId: mintId,
        );
        relatedDanceLinkIssues.addAll(linkResult.issues);
        for (final entry in linkResult.newLinksByDanceId.entries) {
          final dance = dancesById[entry.key];
          if (dance == null) continue; // fetched dance vanished; skip safely
          await _dances.update(
            dance.copyWith(links: [...dance.links, ...entry.value]),
          );
        }
      }
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
    );
  }

  /// Convenience end-to-end import of a `.USR` [bytes] payload: reads the
  /// archive for the program build, then [plan]s and [commit]s in one call
  /// using default dedupe handling (ambiguous records are skipped, never
  /// guessed — the pipeline default). The dance side re-parses [bytes] through
  /// the adapter during [plan], so the file is decoded twice; that keeps the
  /// dances on the exact shared pipeline path and the cost is negligible next
  /// to the DB writes. The app's review flow can instead call [plan]/[commit]
  /// separately to let the user resolve ambiguous dances.
  Future<CcUsrImportResult> import(
    Uint8List bytes, {
    required DateTime now,
    required bool venueEntityMode,
    String Function()? newId,
    String Function()? newSlotId,
  }) async {
    final archive = readCcUsrArchive(bytes);
    final batch = await plan(bytes);
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
  /// Venue removal is **guarded**, mirroring
  /// `CompendiumArchiveImporter.undo`: after a successful import a surviving
  /// user program may have linked to a venue this import minted (e.g. by
  /// deduping onto its normalized-location key), so an unconditional delete
  /// would orphan that program's `venueId`. Each inserted venue is deleted only
  /// when no program still references it; a still-referenced venue is
  /// retained.
  ///
  /// **Related-dance links (issue #688) need no dedicated revert step here** —
  /// [ImportPipeline.undo] already fully reverts them as a side effect of its
  /// own dance rollback. Every dance [commit] could have attached a
  /// `relatedDance` link to is, by construction, a dance resolved through
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
  /// zero additional bookkeeping.
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
    for (final id in result.insertedVenueIds) {
      try {
        // `permanent` for the same reason the dances/programs above are
        // hard-deleted: a rollback must leave nothing behind to publish.
        await _venues.delete(id, permanent: true);
      } on StateError {
        // Still referenced by a surviving program — leave it in place rather
        // than orphan that program's venueId.
      }
    }
    await _pipeline.undo(result.danceSession);
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
