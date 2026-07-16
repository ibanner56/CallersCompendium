import 'package:meta/meta.dart';

import '../model/choreographer.dart';
import '../model/dance.dart';
import '../model/provenance.dart';
import '../storage/repositories/choreographer_repository.dart';
import '../storage/repositories/dance_repository.dart';
import 'dedupe.dart';
import 'import_error.dart';
import 'raw_record.dart';
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

/// How one imported author name was resolved to a [Choreographer] during
/// [ImportPipeline.commit]: either matched to an existing row or created fresh.
@immutable
class AuthorResolution {
  const AuthorResolution({
    required this.name,
    required this.choreographerId,
    required this.created,
  });

  /// The raw source name (trimmed) that was resolved.
  final String name;

  /// The id of the matched-or-created [Choreographer].
  final String choreographerId;

  /// True when a new [Choreographer] row was created for this name; false when
  /// an existing row was matched (exact, normalized).
  final bool created;

  @override
  String toString() =>
      'AuthorResolution($name → $choreographerId, '
      '${created ? 'created' : 'matched'})';
}

/// The outcome for one record after [ImportPipeline.commit].
@immutable
class CommittedRecord {
  const CommittedRecord({
    required this.action,
    this.danceId,
    this.error,
    this.authorResolutions = const [],
  });

  final CommitAction action;

  /// The dance id written (for create/reimport/link/duplicate), else `null`.
  final String? danceId;

  /// A commit error for this record, if it failed (the rest still commit).
  final ImportError? error;

  /// How each of the record's author names resolved (matched vs created), in
  /// order. Empty for skips, errors, or records with no author names.
  final List<AuthorResolution> authorResolutions;

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
    List<String> createdChoreographerIds = const [],
  }) : records = List.unmodifiable(records),
       _insertedDanceIds = List.unmodifiable(insertedDanceIds),
       _priorStates = List.unmodifiable(priorStates),
       _createdChoreographerIds = List.unmodifiable(createdChoreographerIds);

  final List<CommittedRecord> records;
  final List<String> _insertedDanceIds;
  final List<Dance> _priorStates;
  final List<String> _createdChoreographerIds;

  /// Ids of dances newly inserted by this batch.
  List<String> get insertedDanceIds => _insertedDanceIds;

  /// Prior snapshots of dances this batch updated (for rollback).
  List<Dance> get updatedDancePriorStates => _priorStates;

  /// Ids of [Choreographer] rows newly created while resolving author names in
  /// this batch (never pre-existing rows). Reverted on [ImportPipeline.undo],
  /// but only when no surviving dance still references them.
  List<String> get createdChoreographerIds => _createdChoreographerIds;

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
      RawRecord raw;
      try {
        raw = await adapter.fetch(record);
      } on ImportError catch (e) {
        errors.add(e);
        continue;
      } catch (e) {
        errors.add(
          fetchError(
            adapter.source,
            'Failed to fetch record: $e',
            externalId: record.externalId,
            cause: e,
          ),
        );
        continue;
      }

      final StructuredDraft draft;
      try {
        draft = adapter.parse(raw);
      } on ImportError catch (e) {
        errors.add(e);
        continue;
      } catch (e) {
        errors.add(
          parseError(
            adapter.source,
            'Failed to parse record: $e',
            externalId: raw.externalId ?? record.externalId,
            cause: e,
          ),
        );
        continue;
      }

      try {
        final verdict = dedupe.verdictFor(
          source: raw.source,
          externalId: raw.externalId,
          title: draft.dance.title,
          authorNames: await _dedupeAuthorNames(draft),
          threshold: threshold,
        );
        records.add(ImportRecordPlan(draft: draft, verdict: verdict));
      } on ImportError catch (e) {
        errors.add(e);
      } catch (e) {
        errors.add(
          ImportError(
            stage: ImportStage.dedupe,
            source: adapter.source,
            message: 'Failed to dedupe record: $e',
            externalId: raw.externalId ?? record.externalId,
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

    // Batch-scoped author resolution state. The map is seeded from the current
    // choreographers (normalized name → id) so imported names match existing
    // rows; newly-created ids are added live so two dances crediting the same
    // new author in one batch resolve to ONE created row (batch de-dup).
    final nameToId = <String, String>{};
    for (final c in await _choreographers.listAll()) {
      nameToId[_normalizeName(c.name)] = c.id;
    }
    final createdChoreographerIds = <String>[];

    for (var i = 0; i < batch.records.length; i++) {
      final plan = batch.records[i];
      final resolution = resolutions[i];
      final (action, targetId) = _resolveAction(plan.verdict, resolution);

      if (action == CommitAction.skip) {
        committed.add(const CommittedRecord(action: CommitAction.skip));
        continue;
      }

      try {
        // Resolve the record's author names to Choreographer ids, creating rows
        // as needed. Done before the write so both create and reimport/link
        // paths get real authorIds. Reimport/link REPLACES authors wholesale
        // (consistent with re-import's overwrite of dance content).
        final authorResolutions = await _resolveAuthors(
          plan.draft.authorNames,
          nameToId: nameToId,
          newId: newId,
          createdChoreographerIds: createdChoreographerIds,
        );
        // Only override authorIds when the draft actually carried author NAMES
        // to resolve (the free-text adapters). Drafts that ship canonical
        // authorIds directly and no names (e.g. the generic archive/JSON
        // adapter) keep their own ids — `null` makes `_rebuildWithIdentity`
        // fall back to `src.authorIds`, avoiding data loss.
        final authorIds = plan.draft.authorNames.isEmpty
            ? null
            : [for (final r in authorResolutions) r.choreographerId];

        final prov = _provenanceFrom(plan.draft, now);
        if (action == CommitAction.create || action == CommitAction.duplicate) {
          final id = newId();
          final dance = _rebuildWithIdentity(
            plan.draft.dance,
            id: id,
            authorIds: authorIds,
            createdAt: now,
            updatedAt: now,
            provenance: prov,
          );
          await _dances.create(dance);
          insertedIds.add(id);
          committed.add(
            CommittedRecord(
              action: action,
              danceId: id,
              authorResolutions: authorResolutions,
            ),
          );
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
            authorIds: authorIds,
            createdAt: prior.createdAt,
            updatedAt: now,
            provenance: prov,
          );
          await _dances.update(dance);
          committed.add(
            CommittedRecord(
              action: action,
              danceId: id,
              authorResolutions: authorResolutions,
            ),
          );
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
      createdChoreographerIds: createdChoreographerIds,
    );
  }

  /// Reverts a committed [session]: hard-deletes every inserted dance, restores
  /// every updated dance to its captured prior state, and removes every
  /// choreographer this batch created — but only those no surviving dance still
  /// references (respecting the repository's referenced-guard). Pre-existing
  /// choreographers are never touched. Idempotent — a second call is a no-op.
  Future<void> undo(ImportSession session) async {
    if (session.isUndone) return;
    await _dances.hardDelete(session.insertedDanceIds);
    for (final prior in session.updatedDancePriorStates) {
      await _dances.update(prior);
    }
    // Deleting inserted dances cascades away their dance_authors rows, and the
    // rolled-back updates drop any references they added, so a created
    // choreographer is now typically unreferenced. Guard anyway: skip any that
    // a surviving dance still credits (the repo throws in that case).
    for (final id in session.createdChoreographerIds) {
      try {
        await _choreographers.delete(id);
      } on StateError {
        // Still referenced by a surviving dance — leave it in place.
      }
    }
    session._undone = true;
  }

  /// Normalizes an author name for matching: trims, collapses internal
  /// whitespace, and lowercases. Deliberately conservative — punctuation is
  /// preserved (never stripped) so distinct people (e.g. "O'More" vs "OMore")
  /// are not merged. A wrong merge (miscrediting a dance) is worse than a
  /// near-duplicate row.
  String _normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Resolves [names] to [Choreographer] ids: matches an existing row by
  /// normalized name, else creates a new row (name only) via [newId] + upsert.
  /// Blank/whitespace-only names are dropped. Duplicate names within one
  /// record collapse to a single authorship entry. Newly-created ids are added
  /// to [nameToId] (batch de-dup) and [createdChoreographerIds] (undo).
  Future<List<AuthorResolution>> _resolveAuthors(
    List<String> names, {
    required Map<String, String> nameToId,
    required String Function() newId,
    required List<String> createdChoreographerIds,
  }) async {
    final resolutions = <AuthorResolution>[];
    final seenNorms = <String>{};
    for (final rawName in names) {
      final name = rawName.trim();
      if (name.isEmpty) continue;
      final norm = _normalizeName(name);
      if (!seenNorms.add(norm)) continue;

      final existingId = nameToId[norm];
      if (existingId != null) {
        resolutions.add(
          AuthorResolution(
            name: name,
            choreographerId: existingId,
            created: false,
          ),
        );
        continue;
      }
      final id = newId();
      await _choreographers.upsert(Choreographer(id: id, name: name));
      nameToId[norm] = id;
      createdChoreographerIds.add(id);
      resolutions.add(
        AuthorResolution(name: name, choreographerId: id, created: true),
      );
    }
    return resolutions;
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

  /// The author-name signal for plan-time dedupe. Free-text imports carry their
  /// authors as raw [StructuredDraft.authorNames] (their `dance.authorIds` are
  /// empty until commit), so prefer those; fall back to names resolved from any
  /// pre-set ids (e.g. the generic adapter that already ships authorIds).
  Future<List<String>> _dedupeAuthorNames(StructuredDraft draft) async {
    if (draft.authorNames.isNotEmpty) return draft.authorNames;
    return _authorNamesFor(draft.dance);
  }

  /// Rebuilds [src] under a different identity/timestamps/provenance. Used to
  /// reassign an import's id (fresh insert) or re-target it onto an existing
  /// dance (re-import/link) without the caller having to reconstruct every
  /// field. All content fields are carried over verbatim, except [authorIds]
  /// which may be overridden with the pipeline's resolved ids. When
  /// [authorIds] is null the draft's own ids are kept — free-text adapters
  /// resolve names at commit and pass the resolved list, while adapters that
  /// ship canonical ids directly (e.g. the generic archive/JSON adapter) pass
  /// null to preserve them.
  Dance _rebuildWithIdentity(
    Dance src, {
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    List<String>? authorIds,
    Provenance? provenance,
  }) => Dance(
    id: id,
    title: src.title,
    authorIds: authorIds ?? src.authorIds,
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
