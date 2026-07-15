import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/provenance.dart';
import '../storage/repositories/choreographer_repository.dart';
import '../storage/repositories/dance_repository.dart';
import 'dedupe.dart';
import 'import_error.dart';
import 'source_adapter.dart';
import 'structured_draft.dart';

/// The commit action chosen (or defaulted) for one record of a batch.
enum CommitAction {
  /// Insert a brand-new dance.
  create,

  /// Update an existing dance matched by exact `(source, externalId)`.
  reimport,

  /// Update an existing dance the caller chose to link a fuzzy match to.
  link,

  /// Import as a new dance despite a fuzzy near-match (caller chose duplicate).
  duplicate,

  /// Do not import (explicit skip, or an unresolved ambiguous record).
  skip,
}

/// One record's place in a planned batch: the parsed [draft] and the dedupe
/// [verdict]. Ambiguous verdicts wait for a caller [DedupeResolution] at commit
/// time; nothing here has touched the database yet (the plan stage is
/// non-destructive).
@immutable
class ImportRecordPlan {
  const ImportRecordPlan({required this.draft, required this.verdict});

  final StructuredDraft draft;
  final DedupeVerdict verdict;
}

/// The result of planning a batch: the per-record [records] (in discovery
/// order) plus any [errors] collected from records that failed to fetch/parse.
/// A failed record never aborts the batch — the rest are still planned and
/// committable (partial-batch tolerance, `docs/design/imports.md`).
@immutable
class ImportBatchResult {
  ImportBatchResult({
    required this.records,
    List<ImportError> errors = const [],
  }) : errors = List.unmodifiable(errors);

  final List<ImportRecordPlan> records;
  final List<ImportError> errors;

  bool get hasErrors => errors.isNotEmpty;
  int get plannedCount => records.length;
}

/// The outcome for one record after [ImportPipeline.commit].
@immutable
class CommittedRecord {
  const CommittedRecord({required this.action, this.danceId, this.error});

  final CommitAction action;

  /// The dance id written (for create/reimport/link/duplicate), else `null`.
  final String? danceId;

  /// A commit error for this record, if it failed (the rest still commit).
  final ImportError? error;

  bool get succeeded => error == null;
}

/// The in-memory log of a committed import batch, kept session-scoped to
/// support undo (`docs/design/imports.md`, "commit"). Deliberately NOT a
/// persisted table: the immediate need is reverting a just-committed batch,
/// and a durable cross-session undo log's shape depends on the review-queue UX
/// (roadmap 6.3). Restore is exact — inserts are removed, updates are rolled
/// back to their captured prior state.
class ImportSession {
  ImportSession({
    required List<CommittedRecord> records,
    required List<String> insertedDanceIds,
    required List<Dance> priorStates,
  }) : records = List.unmodifiable(records),
       _insertedDanceIds = List.unmodifiable(insertedDanceIds),
       _priorStates = List.unmodifiable(priorStates);

  final List<CommittedRecord> records;
  final List<String> _insertedDanceIds;
  final List<Dance> _priorStates;

  /// Ids of dances newly inserted by this batch.
  List<String> get insertedDanceIds => _insertedDanceIds;

  /// Prior snapshots of dances this batch updated (for rollback).
  List<Dance> get updatedDancePriorStates => _priorStates;

  int get committedCount =>
      records.where((r) => r.succeeded && r.action != CommitAction.skip).length;

  /// True once [ImportPipeline.undo] has reverted this batch.
  bool get isUndone => _undone;
  bool _undone = false;
}

/// Drives a [SourceAdapter] through the full pipeline: `discover → fetch →
/// parse → dedupe` (planning, non-destructive) and then `commit` (transactional
/// write of dances + provenance) with session-scoped undo.
///
/// Pure framework: it performs no source I/O itself (adapters own that) and
/// holds no source-specific knowledge. The [ImportPipeline] is safe to reuse
/// across batches.
class ImportPipeline {
  ImportPipeline(this._dances, this._choreographers);

  final DanceRepository _dances;
  final ChoreographerRepository _choreographers;

  /// Builds a [DedupeIndex] snapshot of the current collection (title + author
  /// names + provenance key per dance). Call once before [plan]; reuse it for
  /// the batch.
  Future<DedupeIndex> buildDedupeIndex() async {
    final authors = await _choreographers.listAll();
    final nameById = {for (final a in authors) a.id: a.name};
    final dances = await _dances.listAll();
    return DedupeIndex([
      for (final d in dances)
        DedupeEntry(
          danceId: d.id,
          title: d.title,
          authorNames: [
            for (final id in d.authorIds)
              if (nameById[id] != null) nameById[id]!,
          ],
          source: d.provenance?.source,
          externalId: d.provenance?.externalId,
        ),
    ]);
  }

  /// Runs discover → fetch → parse → dedupe over [request], producing a
  /// non-destructive [ImportBatchResult]. Per-record fetch/parse failures are
  /// collected as structured [ImportError]s; the rest of the batch proceeds.
  ///
  /// [index] should be a fresh [buildDedupeIndex] snapshot; if omitted, one is
  /// built automatically.
  Future<ImportBatchResult> plan(
    SourceAdapter adapter,
    ImportRequest request, {
    DedupeIndex? index,
    double threshold = DedupeIndex.defaultThreshold,
  }) async {
    final dedupe = index ?? await buildDedupeIndex();
    final List<DiscoveredRecord> discovered;
    try {
      discovered = await adapter.discover(request);
    } catch (e) {
      return ImportBatchResult(
        records: const [],
        errors: [
          ImportError(
            stage: ImportStage.discover,
            source: adapter.source,
            message: 'Discovery failed: $e',
            cause: e,
          ),
        ],
      );
    }

    final records = <ImportRecordPlan>[];
    final errors = <ImportError>[];
    for (final record in discovered) {
      try {
        final raw = await adapter.fetch(record);
        final draft = adapter.parse(raw);
        final verdict = dedupe.verdictFor(
          source: raw.source,
          externalId: raw.externalId,
          title: draft.dance.title,
          authorNames: await _authorNamesFor(draft.dance),
          threshold: threshold,
        );
        records.add(ImportRecordPlan(draft: draft, verdict: verdict));
      } on ImportError catch (e) {
        errors.add(e);
      } catch (e) {
        errors.add(
          parseError(
            adapter.source,
            'Failed to import record: $e',
            externalId: record.externalId,
            cause: e,
          ),
        );
      }
    }
    return ImportBatchResult(records: records, errors: errors);
  }

  /// Commits a planned [batch] transactionally, writing each dance and its
  /// provenance row. [resolutions] resolves ambiguous records, keyed by their
  /// index into `batch.records`; an ambiguous record with no resolution is
  /// skipped (never guessed). New/duplicate inserts get a fresh id from
  /// [newId]; re-imports/links update the matched dance, preserving its
  /// `createdAt`.
  ///
  /// Returns an [ImportSession] recording what was written so the batch can be
  /// [undo]ne.
  Future<ImportSession> commit(
    ImportBatchResult batch, {
    required DateTime now,
    required String Function() newId,
    Map<int, DedupeResolution> resolutions = const {},
  }) async {
    final committed = <CommittedRecord>[];
    final insertedIds = <String>[];
    final priorStates = <Dance>[];

    for (var i = 0; i < batch.records.length; i++) {
      final plan = batch.records[i];
      final resolution = resolutions[i];
      final (action, targetId) = _resolveAction(plan.verdict, resolution);

      if (action == CommitAction.skip) {
        committed.add(const CommittedRecord(action: CommitAction.skip));
        continue;
      }

      try {
        final prov = _provenanceFrom(plan.draft, now);
        if (action == CommitAction.create || action == CommitAction.duplicate) {
          final id = newId();
          final dance = _rebuildWithIdentity(
            plan.draft.dance,
            id: id,
            createdAt: now,
            updatedAt: now,
            provenance: prov,
          );
          await _dances.create(dance);
          insertedIds.add(id);
          committed.add(CommittedRecord(action: action, danceId: id));
        } else {
          // reimport / link: update the matched dance in place.
          final id = targetId!;
          final prior = await _dances.getById(id, includeDeleted: true);
          if (prior == null) {
            committed.add(
              CommittedRecord(
                action: action,
                error: commitError(
                  plan.draft.raw.source,
                  'Target dance "$id" no longer exists',
                  externalId: plan.draft.raw.externalId,
                ),
              ),
            );
            continue;
          }
          priorStates.add(prior);
          final dance = _rebuildWithIdentity(
            plan.draft.dance,
            id: id,
            createdAt: prior.createdAt,
            updatedAt: now,
            provenance: prov,
          );
          await _dances.update(dance);
          committed.add(CommittedRecord(action: action, danceId: id));
        }
      } catch (e) {
        committed.add(
          CommittedRecord(
            action: action,
            error: commitError(
              plan.draft.raw.source,
              'Commit failed: $e',
              externalId: plan.draft.raw.externalId,
              cause: e,
            ),
          ),
        );
      }
    }

    return ImportSession(
      records: committed,
      insertedDanceIds: insertedIds,
      priorStates: priorStates,
    );
  }

  /// Reverts a committed [session]: hard-deletes every inserted dance and
  /// restores every updated dance to its captured prior state. Idempotent —
  /// a second call is a no-op.
  Future<void> undo(ImportSession session) async {
    if (session.isUndone) return;
    await _dances.hardDelete(session.insertedDanceIds);
    for (final prior in session.updatedDancePriorStates) {
      await _dances.update(prior);
    }
    session._undone = true;
  }

  (CommitAction, String?) _resolveAction(
    DedupeVerdict verdict,
    DedupeResolution? resolution,
  ) {
    switch (verdict.kind) {
      case DedupeKind.isNew:
        return (CommitAction.create, null);
      case DedupeKind.reimport:
        return (CommitAction.reimport, verdict.targetDanceId);
      case DedupeKind.ambiguous:
        if (resolution == null) return (CommitAction.skip, null);
        switch (resolution.kind) {
          case DedupeResolutionKind.link:
            return (CommitAction.link, resolution.targetDanceId);
          case DedupeResolutionKind.duplicate:
            return (CommitAction.duplicate, null);
          case DedupeResolutionKind.skip:
            return (CommitAction.skip, null);
        }
    }
  }

  Provenance _provenanceFrom(StructuredDraft draft, DateTime now) {
    final raw = draft.raw;
    return Provenance(
      source: raw.source,
      externalId: raw.externalId,
      importedAt: now,
      permission: raw.permission,
      license: raw.license,
      rawPayload: raw.payload,
      sourceVersion: raw.sourceVersion,
    );
  }

  Future<List<String>> _authorNamesFor(Dance dance) async {
    final names = <String>[];
    for (final id in dance.authorIds) {
      final c = await _choreographers.getById(id);
      if (c != null) names.add(c.name);
    }
    return names;
  }

  /// Rebuilds [src] under a different identity/timestamps/provenance. Used to
  /// reassign an import's id (fresh insert) or re-target it onto an existing
  /// dance (re-import/link) without the caller having to reconstruct every
  /// field. All content fields are carried over verbatim.
  Dance _rebuildWithIdentity(
    Dance src, {
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    Provenance? provenance,
  }) => Dance(
    id: id,
    title: src.title,
    authorIds: src.authorIds,
    form: src.form,
    formation: src.formation,
    progression: src.progression,
    phraseStructure: src.phraseStructure.raw,
    figures: src.figures,
    hook: src.hook,
    callingNotes: src.callingNotes,
    status: src.status,
    level: src.level,
    mixedLevel: src.mixedLevel,
    rating: src.rating,
    tunes: src.tunes,
    customFields: src.customFields,
    tagIds: src.tagIds,
    links: src.links,
    sourceCitations: src.sourceCitations,
    provenance: provenance,
    composedOn: src.composedOn,
    revisedOn: src.revisedOn,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
