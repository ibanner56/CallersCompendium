import 'package:meta/meta.dart';

import '../model/program.dart';
import '../model/provenance.dart';
import '../model/enums.dart';
import '../serialization/compendium_archive.dart';
import '../storage/repositories/program_repository.dart';
import '../util/uuid.dart';
import 'dedupe.dart';
import 'generic_json_adapter.dart';
import 'import_pipeline.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

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
          // keep the slot as a placeholder note rather than dropping it.
          if (text == null || text.trim().isEmpty) {
            text = 'Dance not imported (${slot.danceId})';
          }
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
  }) : programs = List.unmodifiable(programs),
       programIssues = List.unmodifiable(programIssues),
       insertedProgramIds = List.unmodifiable(insertedProgramIds),
       updatedProgramPriorStates = List.unmodifiable(updatedProgramPriorStates);

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
  CompendiumArchiveImporter(this._pipeline, this._programs);

  final ImportPipeline _pipeline;
  final ProgramRepository _programs;

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
    final built = buildArchivePrograms(
      archive,
      danceIdByOriginalId: danceIdByOriginalId,
      newId: mintId,
      newSlotId: newSlotId ?? uuidV4,
      now: now,
    );

    final existingByExternalId = await _programs.externalIdToProgramId(
      ProvenanceSource.json,
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
          await _programs.create(program);
          insertedIds.add(program.id);
          persisted.add(program);
        } else {
          final target = _rebuildProgramWithId(
            program,
            id: existingId,
            createdAt: prior.createdAt,
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

    return CompendiumArchiveImportResult(
      danceSession: danceSession,
      programs: persisted,
      programIssues: built.issues,
      insertedProgramIds: insertedIds,
      updatedProgramPriorStates: priorStates,
    );
  }

  /// Convenience end-to-end import of an [archiveJson] payload: [plan]s and
  /// [commit]s in one call using default dedupe handling (ambiguous records are
  /// skipped, never guessed — the pipeline default). The app's frictionless
  /// intake uses this; a review flow could instead call [plan]/[commit]
  /// separately to let the user resolve ambiguous dances.
  Future<CompendiumArchiveImportResult> import(
    String archiveJson,
    CompendiumArchive archive, {
    required DateTime now,
    String Function()? newId,
    String Function()? newSlotId,
  }) async {
    final batch = await plan(archiveJson);
    return commit(batch, archive, now: now, newId: newId, newSlotId: newSlotId);
  }

  /// Reverts a committed [result]: hard-deletes the **inserted** programs (slots
  /// cascade) and restores every **updated** (re-imported) program to its
  /// captured prior state, **before** delegating to [ImportPipeline.undo] for
  /// the dances, authors and updated-dance rollbacks. Idempotent — a second
  /// call is a no-op.
  Future<void> undo(CompendiumArchiveImportResult result) async {
    if (result.isUndone) return;
    await _programs.hardDelete(result.insertedProgramIds);
    for (final prior in result.updatedProgramPriorStates) {
      await _programs.update(prior);
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
  Program _rebuildProgramWithId(
    Program src, {
    required String id,
    required DateTime createdAt,
  }) => Program(
    id: id,
    title: src.title,
    eventDate: src.eventDate,
    venue: src.venue,
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
}
