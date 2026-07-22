import 'dart:typed_data';

import '../model/enums.dart';
import '../model/program.dart';
import '../storage/repositories/program_repository.dart';
import '../util/uuid.dart';
import 'callers_companion_programs.dart';
import 'callers_companion_usr_adapter.dart';
import 'callers_companion_usr_archive.dart';
import 'dedupe.dart';
import 'import_pipeline.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

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
  }) : programs = List.unmodifiable(programs),
       programIssues = List.unmodifiable(programIssues),
       insertedProgramIds = List.unmodifiable(insertedProgramIds),
       updatedProgramPriorStates = List.unmodifiable(updatedProgramPriorStates);

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

  /// Non-fatal issues raised while building the programs (unresolved dance
  /// references, unparseable dates, skipped empty slots) — never fatal.
  final List<ImportIssue> programIssues;

  /// Ids of the programs updated in place (re-imported) by this import.
  List<String> get updatedProgramIds => [
    for (final p in updatedProgramPriorStates) p.id,
  ];

  /// Count of programs newly inserted by this import.
  int get insertedProgramCount => insertedProgramIds.length;

  /// Count of programs updated in place (deduped/re-imported) by this import.
  int get updatedProgramCount => updatedProgramPriorStates.length;

  /// True once [CallersCompanionUsrImporter.undo] has reverted this import.
  bool get isUndone => _undone;
  bool _undone = false;
}

/// Drives a full Caller's Companion `.USR` migration through the **real import
/// commit path**: it commits dances via the shared [ImportPipeline] (dedupe,
/// provenance, author resolution, undo) and then builds the CC `Set`/`SetItem`
/// programs with [buildCcPrograms] — resolving each slot's CC dance reference
/// to the *new* Compendium dance id the commit just minted — and persists them
/// via [ProgramRepository].
///
/// This is the app-layer follow-up promised in [buildCcPrograms]'s doc: it is
/// what actually calls that builder in production. It stays **Flutter-free**
/// (pure Dart + repositories) so it lives in the core and is trivially
/// unit-testable; the app supplies the `.USR` bytes.
class CallersCompanionUsrImporter {
  CallersCompanionUsrImporter(this._pipeline, this._programs);

  final ImportPipeline _pipeline;
  final ProgramRepository _programs;

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
  /// Everything is recorded on the returned [CcUsrImportResult] so [undo]
  /// reverts dances **and** programs.
  Future<CcUsrImportResult> commit(
    ImportBatchResult batch,
    CcUsrArchive archive, {
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

    final danceIdByCcRowId = _danceIdByCcRowId(danceSession);
    final built = buildCcPrograms(
      archive,
      danceIdByCcRowId: danceIdByCcRowId,
      newId: mintId,
      newSlotId: newSlotId ?? uuidV4,
      now: now,
    );

    // Persist the programs, deduping on provenance. A built program whose
    // `(callersCompanion, zk_Set_ID)` key already exists is a re-import: update
    // that program in place (preserving its id + createdAt, capturing its prior
    // state for undo) rather than inserting a duplicate. Others are inserted.
    //
    // If any write fails the dances are already committed, so compensate before
    // rethrowing — remove the inserted programs, restore the updated ones, and
    // revert the dance commit — keeping the import all-or-nothing from the
    // caller's perspective (they never get a partial DB with no undo handle).
    final existingByExternalId = await _programs.externalIdToProgramId(
      ProvenanceSource.callersCompanion,
    );
    final insertedIds = <String>[];
    final priorStates = <Program>[];
    final persisted = <Program>[];
    try {
      for (final program in built.programs) {
        final externalId = program.provenance?.externalId;
        final existingId = (externalId == null || externalId.isEmpty)
            ? null
            : existingByExternalId[externalId];
        final prior = existingId == null
            ? null
            : await _programs.getById(existingId, includeDeleted: true);
        if (existingId == null || prior == null) {
          // New program (no match, or a stale index entry whose program row is
          // gone) — insert under its freshly minted id.
          await _programs.create(program);
          insertedIds.add(program.id);
          persisted.add(program);
        } else {
          // Re-import: overwrite the matched program in place.
          final target = _rebuildProgramWithId(
            program,
            id: existingId,
            createdAt: prior.createdAt,
            priorVenueId: prior.venueId,
          );
          priorStates.add(prior);
          await _programs.update(target);
          persisted.add(target);
        }
      }
    } catch (_) {
      await _programs.hardDelete(insertedIds);
      for (final prior in priorStates) {
        await _programs.update(prior);
      }
      await _pipeline.undo(danceSession);
      rethrow;
    }

    return CcUsrImportResult(
      danceSession: danceSession,
      programs: persisted,
      programIssues: built.issues,
      insertedProgramIds: insertedIds,
      updatedProgramPriorStates: priorStates,
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
    String Function()? newId,
    String Function()? newSlotId,
  }) async {
    final archive = readCcUsrArchive(bytes);
    final batch = await plan(bytes);
    return commit(batch, archive, now: now, newId: newId, newSlotId: newSlotId);
  }

  /// Reverts a committed [result]: hard-deletes the **inserted** programs (slots
  /// cascade) and restores every **updated** (re-imported) program to its
  /// captured prior state, **before** delegating to [ImportPipeline.undo] for
  /// the dances, authors and updated-dance rollbacks. Idempotent — a second
  /// call is a no-op.
  ///
  /// Programs are handled first so the revert is clean regardless of the
  /// `program_slots.dance_id → dances` foreign key (which is `SET NULL`, so the
  /// order is not strictly required for integrity, but removing programs first
  /// keeps the intent obvious).
  Future<void> undo(CcUsrImportResult result) async {
    if (result.isUndone) return;
    await _programs.hardDelete(result.insertedProgramIds);
    for (final prior in result.updatedProgramPriorStates) {
      await _programs.update(prior);
    }
    await _pipeline.undo(result.danceSession);
    result._undone = true;
  }

  /// Rebuilds [src] under an existing program [id] and [createdAt] (preserving
  /// the matched program's identity/creation stamp on a re-import) while keeping
  /// every other field — title, slots, event metadata, provenance, updatedAt —
  /// from the freshly built program.
  ///
  /// [priorVenueId] carries the matched program's existing `venueId` forward.
  /// A `.USR` archive has no concept of this app-local venue entity link, so a
  /// freshly built program never supplies one; overwriting with null would
  /// silently drop a link the user established after the original import.
  /// Preserving it (like [id]/[createdAt]) keeps the re-import from destroying
  /// app-local state the source cannot reconstruct.
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
    venueId: priorVenueId,
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
