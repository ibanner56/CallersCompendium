import 'package:meta/meta.dart';

import '../model/program.dart';
import '../model/provenance.dart';
import '../model/enums.dart';
import '../model/venue.dart';
import '../serialization/compendium_archive.dart';
import '../storage/repositories/program_repository.dart';
import '../storage/repositories/venue_repository.dart';
import '../util/uuid.dart';
import 'dedupe.dart';
import 'generic_json_adapter.dart';
import 'import_pipeline.dart';
import 'program_slot_note.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';
import 'venue_dedupe.dart';

/// The result of building [Program]s from a [CompendiumArchive]: the rebuilt
/// programs plus the non-fatal [ImportIssue]s raised while building them.
@immutable
class ArchiveProgramsResult {
  ArchiveProgramsResult({
    List<Program> programs = const [],
    List<ImportIssue> issues = const [],
  }) : programs = List.unmodifiable(programs),
       issues = List.unmodifiable(issues);

  final List<Program> programs;
  final List<ImportIssue> issues;
}

/// Rebuilds the [archive]'s [Program]s for insertion into the live collection,
/// resolving each slot's *original* `danceId` to the **newly-committed**
/// Compendium dance id via [danceIdByOriginalId].
///
/// This is a **pure builder** — no repository, no I/O — mirroring
/// [buildCcPrograms]'s philosophy so it is trivially unit-testable and stays
/// Flutter-free. The importer calls it *after* the archive's dances commit
/// (so [danceIdByOriginalId] maps each archive dance id → the dance id the
/// pipeline just minted/matched), then persists the returned programs.
///
/// Fidelity: every program is imported **verbatim** — title, event metadata,
/// slot order, note-only slots ([ProgramSlot.text] with no dance), alternates,
/// guest callers, planned minutes and performed timestamps are preserved as
/// authored. Nothing is fabricated.
///
/// **Parse-never-fails:** a slot whose referenced dance was not committed (it
/// deduped away, was skipped, or the archive omitted it) degrades to a
/// text/note placeholder slot with an [ImportIssue] — never a throw, never a
/// dropped slot.
ArchiveProgramsResult buildArchivePrograms(
  CompendiumArchive archive, {
  required Map<String, String> danceIdByOriginalId,
  Map<String, String> venueIdByOriginalId = const {},
  String Function()? newId,
  String Function()? newSlotId,
  DateTime? now,
}) {
  final mintId = newId ?? uuidV4;
  final mintSlotId = newSlotId ?? uuidV4;
  final timestamp = now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final issues = <ImportIssue>[];
  final programs = <Program>[];

  for (final program in archive.programs) {
    final slots = <ProgramSlot>[];
    // Re-number positions densely from the program's existing (already
    // position-ordered) slots so the imported order is preserved exactly, even
    // if a source slot carried a sparse or duplicated position.
    var position = 0;
    for (final slot in program.slots) {
      String? danceId;
      String? text = slot.text;

      if (slot.danceId != null) {
        danceId = danceIdByOriginalId[slot.danceId];
        if (danceId == null) {
          // The referenced dance is not present in the committed collection;
          // keep the slot as a placeholder note rather than dropping it, and
          // always surface which reference failed — appended to any existing
          // note so the missing id is never silently lost.
          final marker = '$kUnresolvedDanceMarkerPrefix${slot.danceId})';
          text = (text == null || text.trim().isEmpty)
              ? marker
              : '$text\n\n$marker';
          issues.add(
            ImportIssue(
              severity: ImportIssueSeverity.warning,
              code: 'archive_program_unresolved_dance',
              message:
                  'Program "${program.title}" references a dance that was not '
                  'imported; kept the slot as a text placeholder.',
            ),
          );
        }
      }

      // A slot must carry a danceId or text (the model enforces this). If both
      // are absent after resolution, skip defensively rather than throw.
      if (danceId == null && (text == null || text.trim().isEmpty)) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'archive_program_empty_slot',
            message: 'Skipped an empty slot in program "${program.title}".',
          ),
        );
        continue;
      }

      slots.add(
        ProgramSlot(
          id: mintSlotId(),
          position: position++,
          danceId: danceId,
          text: text,
          isAlt: slot.isAlt,
          guestCaller: slot.guestCaller,
          plannedMinutes: slot.plannedMinutes,
          performedAt: slot.performedAt,
        ),
      );
    }

    programs.add(
      Program(
        id: mintId(),
        title: program.title,
        eventDate: program.eventDate,
        venue: program.venue,
        venueId: _resolveVenueId(program, venueIdByOriginalId, issues),
        band: program.band,
        caller: program.caller,
        dancerLevel: program.dancerLevel,
        notes: program.notes,
        status: program.status,
        hideAlternates: program.hideAlternates,
        slots: slots,
        createdAt: timestamp,
        updatedAt: timestamp,
        // Provenance keyed on the *original* program id, so re-receiving the
        // same bundle dedupes onto this program instead of creating a
        // duplicate. Mirrors the dance provenance the pipeline stamps
        // (`source: json`).
        provenance: Provenance(
          source: ProvenanceSource.json,
          externalId: program.id,
          importedAt: timestamp,
          sourceVersion: '${archive.schemaVersion}',
        ),
      ),
    );
  }

  return ArchiveProgramsResult(programs: programs, issues: issues);
}

/// Resolves [program]'s *original* archive `venueId` to the **newly-inserted**
/// venue id via [venueIdByOriginalId], mirroring the dance-slot resolution.
///
/// **OWASP dangling-reference handling:** a `venueId` that resolves to no
/// venue in the bundle (the referenced venue record was omitted, malformed and
/// skipped on decode, or the id is simply spurious in an untrusted bundle) is
/// **nulled** — never persisted as a dangling soft reference and never a throw
/// — and the drop is surfaced as a non-fatal [ImportIssue]. A `null` (or
/// already-resolved) `venueId` passes through unchanged. This is the same
/// resolve-or-null contract [ArchiveRestorer] applies on the backup/restore
/// path, and it runs *before* the program reaches [ProgramRepository], whose
/// write-time check would otherwise reject a non-existent `venueId`.
String? _resolveVenueId(
  Program program,
  Map<String, String> venueIdByOriginalId,
  List<ImportIssue> issues,
) {
  final originalVenueId = program.venueId;
  if (originalVenueId == null) return null;
  final resolved = venueIdByOriginalId[originalVenueId];
  if (resolved == null) {
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.warning,
        code: 'archive_program_unresolved_venue',
        message:
            'Program "${program.title}" references a venue that was not '
            'imported; kept the program without a venue link.',
      ),
    );
  }
  return resolved;
}

/// The outcome of committing a [CompendiumArchive] import: the dance
/// [ImportSession] (dances + author choreographers) produced by the shared
/// [ImportPipeline], plus the [Program]s rebuilt from the archive and persisted
/// alongside them.
///
/// This is the single handle passed to [CompendiumArchiveImporter.undo] so a
/// whole archive import — dances **and** programs — reverts symmetrically.
/// Keeping the program bookkeeping here (rather than on the source-agnostic,
/// dance-only [ImportSession]) keeps [ImportPipeline] free of any `Program`
/// knowledge, exactly as [CcUsrImportResult] does for the `.USR` path.
class CompendiumArchiveImportResult {
  CompendiumArchiveImportResult({
    required this.danceSession,
    required List<Program> programs,
    required List<ImportIssue> programIssues,
    List<String> insertedProgramIds = const [],
    List<Program> updatedProgramPriorStates = const [],
    List<String> insertedVenueIds = const [],
  }) : programs = List.unmodifiable(programs),
       programIssues = List.unmodifiable(programIssues),
       insertedProgramIds = List.unmodifiable(insertedProgramIds),
       updatedProgramPriorStates = List.unmodifiable(updatedProgramPriorStates),
       insertedVenueIds = List.unmodifiable(insertedVenueIds);

  /// The dance-side session (inserted dance ids, updated-dance prior states,
  /// created choreographer ids) — reverted via [ImportPipeline.undo].
  final ImportSession danceSession;

  /// Every program this import persisted — both newly inserted and updated
  /// (re-imported) — carrying its final id. Ordered as the archive listed them.
  final List<Program> programs;

  /// Ids of the programs **inserted** by this import (no prior existed); these
  /// are hard-deleted on [undo].
  final List<String> insertedProgramIds;

  /// Prior snapshots of the programs this import **updated in place** because a
  /// re-import matched their `(json, externalId)` provenance key. Restored
  /// verbatim on [undo].
  final List<Program> updatedProgramPriorStates;

  /// Ids of the venues this import **inserted** (one freshly-minted id per
  /// bundled venue). Hard-deleted on [undo] once the referencing programs have
  /// been reverted, so an undone import leaves no orphaned venue behind.
  final List<String> insertedVenueIds;

  /// Non-fatal issues raised while rebuilding the programs (unresolved dance
  /// references, skipped empty slots) — never fatal.
  final List<ImportIssue> programIssues;

  /// The program a caller should auto-open after a successful import: the first
  /// persisted program, or `null` when the archive carried no program.
  String? get primaryProgramId => programs.isEmpty ? null : programs.first.id;

  /// Every persisted program id (inserted or updated), in archive order.
  List<String> get importedProgramIds => [for (final p in programs) p.id];

  int get insertedProgramCount => insertedProgramIds.length;
  int get updatedProgramCount => updatedProgramPriorStates.length;
  int get insertedVenueCount => insertedVenueIds.length;

  /// True once [CompendiumArchiveImporter.undo] has reverted this import.
  bool get isUndone => _undone;
  bool _undone = false;
}

/// Drives a full [CompendiumArchive] import through the **existing shared import
/// commit path**: dances commit via the shared [ImportPipeline] and
/// [GenericJsonAdapter] (dedupe, provenance, author resolution, undo — the same
/// path every other import uses), and the archive's programs are then rebuilt
/// with [buildArchivePrograms] (resolving each slot's dance reference to the
/// dance id the commit just minted/matched) and persisted via
/// [ProgramRepository].
///
/// This is the receive-side counterpart to the send-side share bundle
/// (issue #298): the manual Import UI imports only the archive's dances, so
/// this importer is what restores the **program** too. It deliberately reuses
/// the one dance-commit function rather than forking a parallel flow, mirroring
/// [CallersCompanionUsrImporter]. It stays **Flutter-free** (pure Dart +
/// repositories) so it lives in the core and is trivially unit-testable; the
/// app supplies the archive JSON.
class CompendiumArchiveImporter {
  CompendiumArchiveImporter(this._pipeline, this._programs, this._venues);

  final ImportPipeline _pipeline;
  final ProgramRepository _programs;
  final VenueRepository _venues;

  final GenericJsonAdapter _adapter = GenericJsonAdapter();

  /// Plans the dance side of the [archiveJson] non-destructively — the archive
  /// dances run through the same `discover → fetch → parse → dedupe` pipeline as
  /// every other source. The returned batch is committed with [commit].
  Future<ImportBatchResult> plan(String archiveJson) =>
      _pipeline.plan(_adapter, ImportRequest(payload: archiveJson));

  /// Commits a planned dance [batch] and then the [archive]'s programs.
  ///
  /// The dances commit first (real pipeline path), yielding the
  /// original-dance-id → committed-dance-id map used to FK-resolve each program
  /// slot. Programs whose slots reference a dance that was not committed degrade
  /// to text placeholders + issues (never a throw — see [buildArchivePrograms]).
  ///
  /// Everything is recorded on the returned [CompendiumArchiveImportResult] so
  /// [undo] reverts dances **and** programs. If any program write fails the
  /// dances are already committed, so the import compensates (removing inserted
  /// programs, restoring updated ones, and undoing the dance commit) before
  /// rethrowing, keeping the import all-or-nothing from the caller's view.
  Future<CompendiumArchiveImportResult> commit(
    ImportBatchResult batch,
    CompendiumArchive archive, {
    required DateTime now,
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

    final danceIdByOriginalId = _danceIdByOriginalId(danceSession, archive);

    final existingByExternalId = await _programs.externalIdToProgramId(
      ProvenanceSource.json,
    );
    // Working copy that also absorbs ids inserted during *this* commit, so a
    // duplicate externalId appearing twice in a single (untrusted) archive
    // updates the row in place instead of inserting it twice.
    final resolvedByExternalId = Map<String, String>.from(existingByExternalId);
    final insertedIds = <String>[];
    final insertedIdSet = <String>{};
    final priorCapturedFor = <String>{};
    final priorStates = <Program>[];
    final insertedVenueIds = <String>[];
    // Keyed by final program id so repeated externalIds collapse to one entry
    // carrying the final persisted state, preserving first-seen archive order.
    final persisted = <String, Program>{};
    try {
      // Venues first — a program's `venueId` soft-references a venue, so the
      // record must exist before the program is written (the repository rejects
      // a non-existent `venueId`). Each *new* bundled venue is inserted under a
      // **freshly-minted** id, never the untrusted bundle id, so an import can
      // never overwrite an existing venue; the original→new remap is what the
      // rebuilt programs resolve their `venueId` against (a reference to a venue
      // absent from the bundle is nulled — see [buildArchivePrograms]).
      //
      // Cross-import dedupe (issue #456): before minting, an incoming venue is
      // matched against the venues the receiver already holds by a **content
      // fingerprint** ([venueFingerprint]). On a unique match the incoming venue
      // is *dropped* and the program is repointed to the existing venue, so
      // re-importing the same bundle no longer duplicates venues. This is
      // strictly a **repoint, never an overwrite**: the matched venue's fields
      // are left untouched, so the fresh-mint guarantee (an untrusted bundle
      // cannot mutate a local venue by claiming its identity) is preserved — a
      // deliberate departure from the program/dance `(source, externalId)`
      // update-in-place dedupe. A weakly-described venue (see the strong-key
      // threshold in [venueFingerprint]) or an ambiguous match (>1 existing
      // venue shares the fingerprint) always fresh-mints — never a wrong guess.
      //
      // *Within* a single (untrusted) bundle, a repeated original id must NOT
      // leave an orphaned extra row: the id's *first* occurrence decides its
      // target (mint or dedupe) and later occurrences collapse onto it. Only an
      // id that actually **minted** a fresh row on first sight refreshes it to
      // the last-seen content (mirroring the duplicate-program-id handling
      // below); a repeat of an id that *deduped* is a no-op, so one original
      // id's later occurrence can never mutate a venue that other ids were
      // repointed to (a non-deterministic clobber for a malformed bundle). Two
      // *distinct* ids that fingerprint-equal within one bundle likewise
      // collapse to one inserted venue, because each mint is folded into the
      // fingerprint index.
      final venueIdByOriginalId = <String, String>{};
      // Original ids whose first occurrence minted a fresh venue this commit —
      // the only ids permitted to "last-seen wins" refresh their row.
      final mintingOriginalIds = <String>{};
      // Seed the fingerprint index once from the current collection (a single
      // load — venue counts are small — never an N+1 of per-venue queries), then
      // fold in each venue this commit mints. The preload is skipped unless at
      // least one bundled venue has a strong-enough key to *possibly* match (a
      // non-null [venueFingerprint]): a bundle with no venues, or only weakly-
      // described ones, can never dedupe cross-import, so the SELECT would be
      // pure waste — such an import issues zero venue reads.
      final canDedupe = archive.venues.any(
        (venue) => venueFingerprint(venue) != null,
      );
      final venueIndex = canDedupe
          ? VenueFingerprintIndex(await _venues.listAll())
          : VenueFingerprintIndex();
      for (final venue in archive.venues) {
        final existingMapped = venueIdByOriginalId[venue.id];
        if (existingMapped != null) {
          // A repeated original id within this bundle. Refresh the row to the
          // last-seen content ONLY when *this* id minted it on first sight; a
          // repeat of an id that deduped (to a pre-existing venue OR to another
          // id's minted venue) is a no-op — it must never overwrite a record
          // other ids already resolved to.
          if (mintingOriginalIds.contains(venue.id)) {
            await _venues.upsert(_venueWithId(venue, existingMapped));
            venueIndex.add(existingMapped, venue);
          }
          continue;
        }
        final matchedVenueId = venueIndex.matchFor(venue);
        if (matchedVenueId != null) {
          // Dedupe: repoint the program to the existing venue. No insert, no
          // upsert, no mutation of the matched record, and — critically — not
          // added to [insertedVenueIds], so undo never deletes a venue the user
          // already had.
          venueIdByOriginalId[venue.id] = matchedVenueId;
          continue;
        }
        final mintedVenueId = mintId();
        await _venues.upsert(_venueWithId(venue, mintedVenueId));
        venueIdByOriginalId[venue.id] = mintedVenueId;
        mintingOriginalIds.add(venue.id);
        insertedVenueIds.add(mintedVenueId);
        venueIndex.add(mintedVenueId, venue);
      }

      final built = buildArchivePrograms(
        archive,
        danceIdByOriginalId: danceIdByOriginalId,
        venueIdByOriginalId: venueIdByOriginalId,
        newId: mintId,
        newSlotId: newSlotId ?? uuidV4,
        now: now,
      );

      // Every non-null `venueId` on a built program resolves (via
      // `venueIdByOriginalId`) to either a venue this commit just minted or a
      // pre-existing venue it deduped to — both are present in the DB — so this
      // set lets the repository validate each write against memory instead of an
      // N+1 of per-program venue SELECTs. Safe: this commit only inserts/reads
      // venues, never deletes one, so a referenced venue can't vanish mid-write.
      final knownVenueIds = venueIdByOriginalId.values.toSet();

      // A pre-venue archive cannot express `venueId` at all, so on a
      // provenance-matched re-import its programs carry a null one; honoring that
      // would silently drop a link the user established after the original
      // import. Only a venue-aware archive has *explicit* venue semantics whose
      // (remapped-or-nulled) value should overwrite the matched program — see
      // [_rebuildProgramWithId]. Keyed on [requiredSchemaVersion] (the archive's
      // actual venue content, exactly what the encoder stamps the wire version
      // from) rather than the passed object's `schemaVersion`, so the decision is
      // correct regardless of how that field was set.
      final archiveCarriesVenueLinks =
          requiredSchemaVersion(archive) >= archiveSchemaVersionVenues;

      for (final program in built.programs) {
        final externalId = program.provenance?.externalId;
        final hasExternalId = externalId != null && externalId.isNotEmpty;
        final mappedId = hasExternalId
            ? resolvedByExternalId[externalId]
            : null;
        final existing = mappedId == null
            ? null
            : await _programs.getById(mappedId, includeDeleted: true);
        if (mappedId == null || existing == null) {
          await _programs.create(program, knownVenueIds: knownVenueIds);
          insertedIds.add(program.id);
          insertedIdSet.add(program.id);
          if (hasExternalId) resolvedByExternalId[externalId] = program.id;
          persisted[program.id] = program;
        } else {
          final target = _rebuildProgramWithId(
            program,
            id: mappedId,
            createdAt: existing.createdAt,
            priorVenueId: existing.venueId,
            archiveCarriesVenueLinks: archiveCarriesVenueLinks,
          );
          // Capture the true pre-import state exactly once per existing id, and
          // never for a row this commit inserted (its prior state is "absent",
          // handled by hardDelete on undo) — so undo restores the real
          // pre-import state, not an intermediate one.
          if (!insertedIdSet.contains(mappedId) &&
              priorCapturedFor.add(mappedId)) {
            priorStates.add(existing);
          }
          // A preserved prior `venueId` (pre-venue re-import) references a venue
          // already in the DB, not one this import inserted, so it is absent from
          // [knownVenueIds]. Admit it for this write: the venue delete-guard keeps
          // a referenced venue alive and this commit only inserts venues, so the
          // reference is sound and needs no extra per-write SELECT.
          final venueId = target.venueId;
          final knownForWrite =
              venueId != null && !knownVenueIds.contains(venueId)
              ? {...knownVenueIds, venueId}
              : knownVenueIds;
          await _programs.update(target, knownVenueIds: knownForWrite);
          persisted[mappedId] = target;
        }
      }

      return CompendiumArchiveImportResult(
        danceSession: danceSession,
        programs: persisted.values.toList(growable: false),
        programIssues: built.issues,
        insertedProgramIds: insertedIds,
        updatedProgramPriorStates: priorStates,
        insertedVenueIds: insertedVenueIds,
      );
    } catch (_) {
      // Compensate in reverse-dependency order: remove inserted programs and
      // restore updated ones first so no program still references a venue, then
      // remove the venues this import inserted, then undo the dances.
      await _programs.hardDelete(insertedIds);
      for (final prior in priorStates) {
        await _programs.update(prior);
      }
      await _venues.hardDelete(insertedVenueIds);
      await _pipeline.undo(danceSession);
      rethrow;
    }
  }

  /// Convenience end-to-end import of an [archiveJson] payload: [plan]s the
  /// dances, then automatically resolves any **ambiguous** dedupe verdicts for
  /// this frictionless, non-interactive receive path and [commit]s.
  ///
  /// Unlike the manual review flow (which calls [plan]/[commit] separately and
  /// lets the user adjudicate), a received bundle has no user present, so an
  /// ambiguous incoming dance must never be silently skipped — that is exactly
  /// what left every referencing program slot as a `Dance not imported (…)`
  /// placeholder. Instead, [ImportPipeline.autoResolveAmbiguous] **links** each
  /// ambiguous dance to an existing one on a *confident* match (reusing the
  /// dance the receiver already has) or **duplicates** it as a new dance
  /// otherwise, so the program slot always resolves. Exact `(source,
  /// externalId)` re-imports and brand-new dances are unaffected.
  ///
  /// The receiver cannot resolve the sender's author ids, so incoming author
  /// names are read from the bundle's own [CompendiumArchive.choreographers].
  Future<CompendiumArchiveImportResult> import(
    String archiveJson,
    CompendiumArchive archive, {
    required DateTime now,
    String Function()? newId,
    String Function()? newSlotId,
  }) async {
    final batch = await plan(archiveJson);
    final authorNameById = <String, String>{
      for (final c in archive.choreographers) c.id: c.name,
    };
    final resolutions = await _pipeline.autoResolveAmbiguous(
      batch,
      authorNamesOf: (dance) => [
        for (final id in dance.authorIds)
          if (authorNameById[id] != null) authorNameById[id]!,
      ],
    );
    return commit(
      batch,
      archive,
      now: now,
      newId: newId,
      newSlotId: newSlotId,
      resolutions: resolutions,
    );
  }

  /// Reverts a committed [result]: hard-deletes the **inserted** programs (slots
  /// cascade) and restores every **updated** (re-imported) program to its
  /// captured prior state, then removes the **inserted** venues, **before**
  /// delegating to [ImportPipeline.undo] for the dances, authors and
  /// updated-dance rollbacks. Idempotent — a second call is a no-op.
  ///
  /// Venue removal is **guarded**, mirroring [ImportPipeline.undo]'s
  /// created-choreographer handling: after a successful import a surviving user
  /// program may have linked to an imported venue, so an unconditional delete
  /// would orphan that program's `venueId`. Each imported venue is deleted only
  /// when no program still references it (the repository guard throws
  /// otherwise); a still-referenced venue is retained. Inserted programs are
  /// removed first, so a venue referenced solely by this import is reclaimed.
  Future<void> undo(CompendiumArchiveImportResult result) async {
    if (result.isUndone) return;
    await _programs.hardDelete(result.insertedProgramIds);
    for (final prior in result.updatedProgramPriorStates) {
      await _programs.update(prior);
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

  /// Builds the *original*-archive-dance-id → new-Compendium-dance-id map.
  ///
  /// [GenericJsonAdapter] keys each committed record's `externalId` as
  /// `dance.provenance?.externalId ?? dance.id`, so this correlates the
  /// archive's dances (by that same key) with the committed records to recover
  /// the association from the archive's *original* dance id to the id the commit
  /// minted (or matched, on dedupe). Records that were skipped or failed
  /// contribute nothing, so a slot referencing them degrades gracefully.
  Map<String, String> _danceIdByOriginalId(
    ImportSession session,
    CompendiumArchive archive,
  ) {
    final committedByExternalId = <String, String>{};
    for (final record in session.records) {
      final danceId = record.danceId;
      final externalId = record.externalId;
      if (!record.succeeded || danceId == null) continue;
      if (externalId == null || externalId.isEmpty) continue;
      committedByExternalId[externalId] = danceId; // last-wins on rare dupes
    }

    final byOriginalId = <String, String>{};
    for (final dance in archive.dances) {
      final key = dance.provenance?.externalId ?? dance.id;
      final committed = committedByExternalId[key];
      if (committed != null) byOriginalId[dance.id] = committed;
    }
    return byOriginalId;
  }

  /// Rebuilds [src] under an existing program [id] and [createdAt] (preserving
  /// the matched program's identity/creation stamp on a re-import) while keeping
  /// every other field from the freshly built program.
  ///
  /// [priorVenueId] is the matched program's current `venueId`, and
  /// [archiveCarriesVenueLinks] is whether the incoming archive is venue-aware
  /// (its [requiredSchemaVersion] reaches [archiveSchemaVersionVenues]). A
  /// venue-aware archive has *explicit* venue semantics, so [src]'s
  /// already-remapped-or-nulled `venueId` overwrites the match (an explicit null
  /// clears the link). A pre-venue archive cannot express `venueId` at all, so
  /// [src]'s is necessarily null; overwriting with it would silently drop a link
  /// the user established after the original import, so [priorVenueId] is
  /// preserved instead (like [id]/[createdAt]) — mirroring the `.USR` re-import's
  /// venue-link preservation for a source that likewise cannot reconstruct it.
  Program _rebuildProgramWithId(
    Program src, {
    required String id,
    required DateTime createdAt,
    required String? priorVenueId,
    required bool archiveCarriesVenueLinks,
  }) => Program(
    id: id,
    title: src.title,
    eventDate: src.eventDate,
    venue: src.venue,
    venueId: archiveCarriesVenueLinks ? src.venueId : priorVenueId,
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

  /// Rebuilds [src] under a freshly-minted [id] so an imported venue is a new
  /// record that never overwrites one the receiver already holds. [Venue.copyWith]
  /// intentionally cannot change the identity, so every field is copied here —
  /// mirroring [_rebuildProgramWithId]. Keep in sync with the [Venue] fields.
  Venue _venueWithId(Venue src, String id) => Venue(
    id: id,
    name: src.name,
    address1: src.address1,
    address2: src.address2,
    city: src.city,
    stateProv: src.stateProv,
    country: src.country,
    postalCode: src.postalCode,
    plus4: src.plus4,
    website: src.website,
    sponsor: src.sponsor,
    eventName: src.eventName,
    time: src.time,
    genericSchedule: src.genericSchedule,
    price: src.price,
    notes: src.notes,
    contact1Name: src.contact1Name,
    contact1Phone: src.contact1Phone,
    contact1Email: src.contact1Email,
    contact2Name: src.contact2Name,
    contact2Phone: src.contact2Phone,
    contact2Email: src.contact2Email,
  );
}
