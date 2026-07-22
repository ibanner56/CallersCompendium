import 'dart:convert';

import 'package:drift/drift.dart';

import '../../dialect/dialect.dart';
import '../../dialect/renderer.dart';
import '../../model/custom_field.dart';
import '../../model/dance.dart';
import '../../model/dance_link.dart';
import '../../model/enums.dart';
import '../../model/formation.dart';
import '../../imports/reparse_custom_figures.dart';
import '../../model/partial_date.dart';
import '../../model/provenance.dart' as model;
import '../../model/source_citation.dart';
import '../../search/search_sort.dart';
import '../../search/title_sort_key.dart';
import '../../search/filter.dart';
import '../../search/filter_compiler.dart';
import '../../search/search_enrichment.dart';
import '../../search/fts_query.dart';
import '../../serialization/figure_codec.dart';
import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import '../tables.dart';
import '../utc_datetime.dart';
import 'custom_field_repository.dart';

/// Progress of a [DanceRepository.rebuildAllDerived] pass: [completed] of
/// [total] dances have had their derived `dance_figures`/`dance_fts` rows
/// rewritten.
///
/// Emitted once with `completed == 0` before any work starts and again after
/// every committed chunk, so a UI can render determinate progress and the
/// post-migration rebuild never appears hung on a large collection (#440).
/// [completed] is monotonically non-decreasing and ends at [total].
class DerivedRebuildProgress {
  const DerivedRebuildProgress({required this.completed, required this.total});

  /// Number of dances whose derived rows have been rewritten and committed.
  final int completed;

  /// Total number of dances the rebuild will process (including soft-deleted,
  /// which stay in `dance_fts` and are filtered at query time — see #439).
  final int total;

  /// Fraction in `[0, 1]`; `1` when there is nothing to rebuild ([total] == 0).
  double get fraction => total == 0 ? 1 : completed / total;

  @override
  bool operator ==(Object other) =>
      other is DerivedRebuildProgress &&
      other.completed == completed &&
      other.total == total;

  @override
  int get hashCode => Object.hash(completed, total);

  @override
  String toString() => 'DerivedRebuildProgress($completed/$total)';
}

/// Callback invoked with monotonically non-decreasing [DerivedRebuildProgress]
/// while [DanceRepository.rebuildAllDerived] runs.
typedef DerivedRebuildProgressCallback =
    void Function(DerivedRebuildProgress progress);

/// CRUD + search for [Dance]s.
///
/// Every write rebuilds the two derived indexes ([DanceFigures] rows and the
/// `dance_fts` row) from `figures_json` inside the same transaction, per
/// `docs/design/storage.md` — the derived tables are never the source of
/// truth and are always safe to drop and recompute (see [rebuildAllDerived]).
class DanceRepository {
  DanceRepository(this._db, this._taxonomy);

  final CompendiumDatabase _db;
  final Taxonomy _taxonomy;

  FigureRenderer get _renderer => FigureRenderer(_taxonomy);

  Future<void> create(Dance dance) => _upsert(dance);

  Future<void> update(Dance dance) => _upsert(dance);

  Future<void> _upsert(Dance dance) => _db.transaction(() async {
    assertUtc(dance.createdAt, 'dance.createdAt');
    assertUtc(dance.updatedAt, 'dance.updatedAt');
    assertUtcOrNull(dance.deletedAt, 'dance.deletedAt');
    assertUtcOrNull(
      dance.provenance?.importedAt,
      'dance.provenance.importedAt',
    );
    await _db
        .into(_db.dances)
        .insertOnConflictUpdate(
          DancesCompanion.insert(
            id: dance.id,
            title: dance.title,
            form: dance.form,
            formationShape: dance.formation.shape,
            formationDetail: Value(dance.formation.detail),
            progression: dance.progression,
            phraseStructure: Value(dance.phraseStructure.raw),
            figuresJson: Value(encodeFigures(dance.figures)),
            hook: Value(dance.hook),
            callingNotes: Value(dance.callingNotes),
            status: dance.status,
            level: Value(dance.level),
            mixedLevel: Value(dance.mixedLevel),
            rating: Value(dance.rating),
            composedOn: Value(dance.composedOn?.serialize()),
            revisedOn: Value(dance.revisedOn?.serialize()),
            tunesJson: Value(jsonEncode(dance.tunes)),
            createdAt: dance.createdAt,
            updatedAt: dance.updatedAt,
            deletedAt: Value(dance.deletedAt),
          ),
        );

    await (_db.delete(
      _db.danceAuthors,
    )..where((t) => t.danceId.equals(dance.id))).go();
    for (var i = 0; i < dance.authorIds.length; i++) {
      await _db
          .into(_db.danceAuthors)
          .insert(
            DanceAuthorsCompanion.insert(
              danceId: dance.id,
              choreographerId: dance.authorIds[i],
              position: i,
            ),
          );
    }

    await (_db.delete(
      _db.danceTags,
    )..where((t) => t.danceId.equals(dance.id))).go();
    for (final tagId in dance.tagIds) {
      await _db
          .into(_db.danceTags)
          .insert(DanceTagsCompanion.insert(danceId: dance.id, tagId: tagId));
    }

    await (_db.delete(
      _db.danceLinks,
    )..where((t) => t.danceId.equals(dance.id))).go();
    for (final link in dance.links) {
      await _db
          .into(_db.danceLinks)
          .insert(
            DanceLinksCompanion.insert(
              id: link.id,
              danceId: dance.id,
              kind: link.kind,
              url: Value(link.url),
              targetDanceId: Value(link.targetDanceId),
              label: Value(link.label),
            ),
          );
    }

    await (_db.delete(
      _db.danceSources,
    )..where((t) => t.danceId.equals(dance.id))).go();
    for (var i = 0; i < dance.sourceCitations.length; i++) {
      final citation = dance.sourceCitations[i];
      await _db
          .into(_db.danceSources)
          .insert(
            DanceSourcesCompanion.insert(
              danceId: dance.id,
              sourceId: citation.sourceId,
              page: Value(citation.page),
              number: Value(citation.number),
              position: i,
            ),
          );
    }

    await (_db.delete(
      _db.customFieldValues,
    )..where((t) => t.danceId.equals(dance.id))).go();
    for (final value in dance.customFields) {
      final def = await (_db.select(
        _db.customFieldDefs,
      )..where((t) => t.id.equals(value.fieldId))).getSingleOrNull();
      if (def == null) {
        throw StateError(
          'dance "${dance.id}" has a value for unknown custom field '
          '"${value.fieldId}"',
        );
      }
      final (text, num) = encodeCustomFieldValue(
        value,
        CustomFieldDefRepository.toModel(def),
      );
      await _db
          .into(_db.customFieldValues)
          .insert(
            CustomFieldValuesCompanion.insert(
              danceId: dance.id,
              fieldId: value.fieldId,
              valueText: Value(text),
              valueNum: Value(num),
            ),
          );
    }

    await (_db.delete(
      _db.provenance,
    )..where((t) => t.danceId.equals(dance.id))).go();
    final prov = dance.provenance;
    if (prov != null) {
      await _db
          .into(_db.provenance)
          .insert(
            ProvenanceCompanion.insert(
              danceId: dance.id,
              source: prov.source,
              externalId: Value(prov.externalId),
              importedAt: prov.importedAt,
              permission: Value(prov.permission),
              license: Value(prov.license),
              rawPayload: Value(prov.rawPayload),
              sourceVersion: Value(prov.sourceVersion),
            ),
          );
    }

    await _rebuildDerived(dance);
  });

  /// Rewrites the derived `dance_figures`/`dance_fts` rows for a single dance:
  /// drops this dance's existing derived rows, then re-inserts them. Used by the
  /// per-write path ([_upsert]); the bulk [rebuildAllDerived] path instead
  /// clears every derived row once up front and calls [_insertDerivedRows]
  /// directly, so it never pays the per-dance `DELETE FROM dance_fts` scan.
  Future<void> _rebuildDerived(Dance dance) async {
    await (_db.delete(
      _db.danceFigures,
    )..where((t) => t.danceId.equals(dance.id))).go();
    // `dance_fts` carries `dance_id` UNINDEXED, so this delete-by-scan is O(rows
    // in the FTS index). Fine for one dance on a write; [rebuildAllDerived]
    // deliberately avoids doing it N times (see there).
    await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
      dance.id,
    ]);
    await _insertDerivedRows(dance);
  }

  /// Inserts this dance's `dance_figures` rows and its single `dance_fts` row,
  /// assuming any prior derived rows for it have already been removed by the
  /// caller. Extracted from [_rebuildDerived] so the bulk rebuild can re-insert
  /// after a one-shot clear instead of a per-dance delete+insert.
  ///
  /// [authorNames] (choreographer id → name) and [sources] (published-source id
  /// → row) let the bulk rebuild pass prefetched lookups so author/source
  /// resolution doesn't fan out into a per-dance N+1 of single-row selects;
  /// when omitted (the single-write path) they are resolved on demand.
  Future<void> _insertDerivedRows(
    Dance dance, {
    Map<String, String>? authorNames,
    Map<String, PublishedSourceRow>? sources,
  }) async {
    final canonicalTexts = <String>[];
    final sectioned = dance.sectionedFigures;
    for (var i = 0; i < dance.figures.length; i++) {
      final figure = dance.figures[i];
      final canonicalText = _renderer.renderCanonical(figure);
      canonicalTexts.add(canonicalText);
      await _db
          .into(_db.danceFigures)
          .insert(
            DanceFiguresCompanion.insert(
              danceId: dance.id,
              idx: i,
              move: figure.move,
              beats: Value(figure.beats),
              progression: Value(figure.progression),
              paramsJson: Value(jsonEncode(figure.params)),
              canonicalText: Value(canonicalText),
              section: Value(sectioned[i].label),
            ),
          );
    }

    final resolvedAuthors = await _resolveAuthorNames(dance, authorNames);
    final customValueText = dance.customFields
        .map((v) => v.value.toString())
        .join(' ');
    final sourceTexts = await _resolveSourceTexts(dance, sources);
    await _db.customStatement(
      'INSERT INTO dance_fts'
      '(dance_id, title, authors, hook, notes, figures_text, custom_values, '
      'sources) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        dance.id,
        dance.title,
        resolvedAuthors.join(' '),
        dance.hook,
        dance.callingNotes,
        canonicalTexts.join(' '),
        customValueText,
        sourceTexts.join(' '),
      ],
    );
  }

  /// Author display names for [dance]'s `authorIds`, in position order. Uses
  /// [prefetched] (choreographer id → name) when the caller supplied it,
  /// otherwise reads each choreographer row on demand.
  Future<List<String>> _resolveAuthorNames(
    Dance dance,
    Map<String, String>? prefetched,
  ) async {
    final names = <String>[];
    if (prefetched != null) {
      for (final authorId in dance.authorIds) {
        final name = prefetched[authorId];
        if (name != null) names.add(name);
      }
      return names;
    }
    for (final authorId in dance.authorIds) {
      final row = await (_db.select(
        _db.choreographers,
      )..where((t) => t.id.equals(authorId))).getSingleOrNull();
      if (row != null) names.add(row.name);
    }
    return names;
  }

  /// Searchable source text (title, then author when present) for [dance]'s
  /// citations, in citation order. Uses [prefetched] (published-source id →
  /// row) when supplied, otherwise batch-reads exactly the cited rows.
  Future<List<String>> _resolveSourceTexts(
    Dance dance,
    Map<String, PublishedSourceRow>? prefetched,
  ) async {
    if (dance.sourceCitations.isEmpty) return const [];
    final Map<String, PublishedSourceRow> byId;
    if (prefetched != null) {
      byId = prefetched;
    } else {
      final sourceIds = dance.sourceCitations.map((c) => c.sourceId).toList();
      final rows = await (_db.select(
        _db.publishedSources,
      )..where((t) => t.id.isIn(sourceIds))).get();
      byId = {for (final r in rows) r.id: r};
    }
    final texts = <String>[];
    for (final citation in dance.sourceCitations) {
      final row = byId[citation.sourceId];
      if (row == null) continue;
      texts.add(row.title);
      if (row.author != null) texts.add(row.author!);
    }
    return texts;
  }

  /// Number of dances rebuilt per transaction in [rebuildAllDerived]. Bounds
  /// each transaction's work so a large-collection rebuild commits incrementally
  /// (progress is reported per chunk and a crash loses at most one chunk) rather
  /// than holding one multi-minute transaction open.
  static const int _rebuildChunkSize = 250;

  /// Recomputes `dance_figures` and `dance_fts` for **every** dance (including
  /// soft-deleted — they stay in `dance_fts` and are filtered at query time,
  /// see [searchText] and #439) from `figures_json`. Intended as an integrity
  /// repair after a migration that changes derived-table shape, or if
  /// corruption is detected by `PRAGMA quick_check`.
  ///
  /// Runs in bounded chunks of [chunkSize] dances, each committed in its own
  /// transaction, and reports progress through [onProgress] so a post-migration
  /// rebuild on a large collection shows determinate progress instead of
  /// appearing hung (#440). [onProgress] fires once with `completed: 0` before
  /// work begins and again after each committed chunk.
  ///
  /// Wall-clock: the whole derived index is cleared once up front
  /// (`DELETE FROM dance_fts` + `DELETE FROM dance_figures`) and every dance is
  /// then re-inserted, so the rebuild never runs the per-dance
  /// `DELETE FROM dance_fts WHERE dance_id = ?` scan N times — that scan is
  /// O(N²) because `dance_fts.dance_id` is `UNINDEXED` (#440). Shared author /
  /// source lookups are prefetched once to drop the last per-dance N+1 reads.
  ///
  /// Crash-safety: this is idempotent and safe to interrupt. The migration
  /// marker that schedules it (`derivedRebuildRequiredKey`) is only cleared
  /// after a *successful* full pass, and `CompendiumRepositories.ensureMigrated`
  /// gates all reads on that pass, so a crash mid-rebuild simply re-runs the
  /// whole clear+reinsert on the next open — a partially populated index is
  /// never observed by a search.
  Future<void> rebuildAllDerived({
    int chunkSize = _rebuildChunkSize,
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    // Runtime guard (not just an assert, which is stripped in release builds):
    // a non-positive chunkSize would make the `start += chunkSize` loop never
    // advance and hang the rebuild, so fail fast in production too (#440).
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    final dances = await listAll(includeDeleted: true);
    final total = dances.length;
    onProgress?.call(DerivedRebuildProgress(completed: 0, total: total));

    // Prefetch the shared lookups once so per-dance FTS assembly is O(1) reads
    // instead of an N+1 of single-row author/source selects. These tables are
    // small relative to the dance collection.
    final authorNames = {
      for (final row in await _db.select(_db.choreographers).get())
        row.id: row.name,
    };
    final sources = {
      for (final row in await _db.select(_db.publishedSources).get())
        row.id: row,
    };

    // One-shot bulk clear instead of N per-dance delete-by-scans. `dance_fts`
    // is a regular (self-contained) FTS5 table, so an unqualified DELETE resets
    // the whole index cheaply; `dance_figures` is an ordinary table.
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM dance_fts');
      await _db.delete(_db.danceFigures).go();
    });

    var completed = 0;
    for (var start = 0; start < dances.length; start += chunkSize) {
      final end = start + chunkSize > dances.length
          ? dances.length
          : start + chunkSize;
      final chunk = dances.sublist(start, end);
      await _db.transaction(() async {
        for (final dance in chunk) {
          await _insertDerivedRows(
            dance,
            authorNames: authorNames,
            sources: sources,
          );
        }
      });
      completed = end;
      onProgress?.call(
        DerivedRebuildProgress(completed: completed, total: total),
      );
    }
  }

  Future<Dance?> getById(String id, {bool includeDeleted = false}) async {
    final row =
        await (_db.select(_db.dances)..where(
              (t) =>
                  t.id.equals(id) &
                  (includeDeleted
                      ? const Constant(true)
                      : t.deletedAt.isNull()),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toModel(row);
  }

  Future<List<Dance>> listAll({bool includeDeleted = false}) async {
    final query = _db.select(_db.dances)
      ..orderBy([(t) => OrderingTerm(expression: t.title)]);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    final rows = await query.get();
    final ids = [for (final row in rows) row.id];
    // Batch-load every child relation in a bounded number of `dance_id IN (…)`
    // queries, then hydrate in memory — instead of the per-row [_toModel]
    // fan-out (six child queries each) that made a full load O(1 + 6N) queries
    // (~120k at 20k dances). Mirrors the batched `_slotsForMany` /
    // `_provenanceForMany` approach ProgramRepository already uses. The `IN`
    // lists are chunked (see [_chunkIds]) so the collection can grow past the
    // SQLite bound-variable limit.
    final authors = await _authorsForMany(ids);
    final tags = await _tagsForMany(ids);
    final links = await _linksForMany(ids);
    final sources = await _sourcesForMany(ids);
    final customFields = await _customFieldsForMany(ids);
    final provenance = await _provenanceForMany(ids);
    return [
      for (final row in rows)
        _buildDance(
          row,
          authorIds: authors[row.id] ?? const [],
          tagIds: tags[row.id] ?? const [],
          links: links[row.id] ?? const [],
          sourceCitations: sources[row.id] ?? const [],
          customFields: customFields[row.id] ?? const [],
          provenance: provenance[row.id],
        ),
    ];
  }

  /// Whether the collection contains at least one dance, reading at most a
  /// single row (`LIMIT 1`) rather than materializing every id/title. A
  /// lightweight emptiness probe for callers — e.g. the first-run seed — that
  /// only need to know if any dance exists. Soft-deleted dances are excluded
  /// unless [includeDeleted] is set.
  Future<bool> hasAny({bool includeDeleted = false}) async {
    final query = _db.selectOnly(_db.dances)
      ..addColumns([_db.dances.id])
      ..limit(1);
    if (!includeDeleted) {
      query.where(_db.dances.deletedAt.isNull());
    }
    final rows = await query.get();
    return rows.isNotEmpty;
  }

  /// Lightweight `(id, title)` listing that reads only the two columns it
  /// needs — avoiding the per-row [_toModel] hydration (figure decoding, child
  /// queries) that [listAll] performs. Ordered by title; soft-deleted dances
  /// are excluded unless [includeDeleted] is set. Used by callers that only
  /// need to resolve or scan dance titles (e.g. auto cross-reference links).
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) async {
    final query = _db.selectOnly(_db.dances)
      ..addColumns([_db.dances.id, _db.dances.title])
      ..orderBy([
        OrderingTerm(expression: _db.dances.title),
        OrderingTerm(expression: _db.dances.id),
      ]);
    if (!includeDeleted) {
      query.where(_db.dances.deletedAt.isNull());
    }
    final rows = await query.get();
    return [
      for (final row in rows)
        (id: row.read(_db.dances.id)!, title: row.read(_db.dances.title)!),
    ];
  }

  /// Lightweight `(id, title, form)` listing that reads only the three columns
  /// it needs — avoiding the per-row [_toModel] hydration (figure decoding,
  /// child queries) that [listAll] performs. Ordered by title then id;
  /// soft-deleted dances are excluded unless [includeDeleted] is set. Used by
  /// callers that render a dance's title alongside its [DanceForm] but need
  /// nothing else — e.g. the command palette, whose per-row icon + label are
  /// derived from the form.
  Future<List<({String id, String title, DanceForm form})>>
  listIdsTitlesAndForms({bool includeDeleted = false}) async {
    final query = _db.selectOnly(_db.dances)
      ..addColumns([_db.dances.id, _db.dances.title, _db.dances.form])
      ..orderBy([
        OrderingTerm(expression: _db.dances.title),
        OrderingTerm(expression: _db.dances.id),
      ]);
    if (!includeDeleted) {
      query.where(_db.dances.deletedAt.isNull());
    }
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          id: row.read(_db.dances.id)!,
          title: row.read(_db.dances.title)!,
          form: row.readWithConverter(_db.dances.form)!,
        ),
    ];
  }

  Future<void> softDelete(String id, {required DateTime at}) {
    assertUtc(at, 'at');
    return (_db.update(_db.dances)..where((t) => t.id.equals(id))).write(
      DancesCompanion(deletedAt: Value(at), updatedAt: Value(at)),
    );
  }

  Future<void> restore(String id, {required DateTime at}) {
    assertUtc(at, 'at');
    return (_db.update(_db.dances)..where((t) => t.id.equals(id))).write(
      DancesCompanion(deletedAt: const Value(null), updatedAt: Value(at)),
    );
  }

  /// Hard-deletes soft-deleted dances whose `deletedAt` is older than
  /// [retention] (default 30 days). Cascades to child rows (authors, tags,
  /// links, custom values, provenance, derived figures) via FK; any
  /// `program_slots.dance_id` pointing at a purged dance is set to `NULL`
  /// (the slot's `text`, if any, survives as a tombstone caption). Reusable
  /// `choreographers` / `published_sources` rows left unreferenced by the purge
  /// are garbage-collected in the same transaction (#462).
  Future<int> purgeDeleted({
    required DateTime now,
    Duration retention = const Duration(days: 30),
  }) async {
    assertUtc(now, 'now');
    final cutoff = now.subtract(retention);
    return _db.transaction(() async {
      // Select eligibility INSIDE the transaction so selection, cleanup, and
      // deletion all operate on one consistent snapshot. Selecting outside the
      // txn opened a TOCTOU race: a dance restored between the SELECT and the
      // DELETE would keep its row (it no longer matches the cutoff predicate)
      // while its dance-only slots were already tombstoned and its incoming
      // relatedDance links deleted — corrupting a dance that ends up surviving.
      final toPurge = await (_db.select(
        _db.dances,
      )..where((t) => t.deletedAt.isSmallerOrEqualValue(cutoff))).get();
      if (toPurge.isEmpty) return 0;
      final ids = [for (final r in toPurge) r.id];
      // Snapshot the orphan-ref candidates from the SAME in-txn snapshot,
      // before _cleanupDanglingReferences / the DELETE cascade the purged
      // dances' dance_authors / dance_sources join rows away (#462).
      final orphanCandidates = await _referencedRefIds(ids);
      await _cleanupDanglingReferences([
        for (final r in toPurge) (id: r.id, title: r.title),
      ]);
      for (final id in ids) {
        await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
          id,
        ]);
      }
      // Delete exactly the rows we selected and cleaned up — by id, not by a
      // re-evaluated cutoff predicate — so cleanup and deletion can never
      // diverge onto different sets of dances.
      var deleted = 0;
      for (final chunk in _chunkIds(ids)) {
        deleted += await (_db.delete(
          _db.dances,
        )..where((t) => t.id.isIn(chunk))).go();
      }
      await _garbageCollectOrphanedRefs(orphanCandidates);
      return deleted;
    });
  }

  /// Neutralises the two `onDelete: SET NULL` FKs that point at [toPurge]
  /// **before** the owning dances are hard-deleted, so the SET NULL can never
  /// leave a row the domain layer rejects. Called inside the delete
  /// transaction of both [purgeDeleted] and [hardDelete].
  ///
  /// - **#429** — `program_slots.danceId`: a *dance-only* slot (its `text` is
  ///   NULL) would become `(danceId, text) = (null, null)`, which the
  ///   [ProgramSlot] constructor rejects, corrupting every Programs load. We
  ///   tombstone it in place with the purged dance's title so the caption
  ///   survives and the slot stays valid. Text-bearing slots already survive
  ///   SET NULL unharmed, so they are left untouched.
  /// - **#466** — `dance_links.targetDanceId`: a `relatedDance` link whose
  ///   *target* is purged would become `(relatedDance, targetDanceId = null)`,
  ///   which the [DanceLink] constructor rejects, corrupting the *owner*
  ///   dance's load. The link no longer refers to anything, so we delete it.
  ///   (Owner-side links are cascade-deleted with their dance separately.)
  Future<void> _cleanupDanglingReferences(
    List<({String id, String title})> toPurge,
  ) async {
    if (toPurge.isEmpty) return;
    for (final d in toPurge) {
      await _db.customStatement(
        'UPDATE program_slots SET text = ? WHERE dance_id = ? AND text IS NULL',
        [d.title, d.id],
      );
    }
    final ids = [for (final d in toPurge) d.id];
    for (final chunk in _chunkIds(ids)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await _db.customStatement(
        'DELETE FROM dance_links WHERE kind = ? AND target_dance_id IN '
        '($placeholders)',
        [LinkKind.relatedDance.name, ...chunk],
      );
    }
  }

  /// Snapshots the reusable reference rows — `choreographers` (via
  /// `dance_authors`) and `published_sources` (via `dance_sources`) — cited by
  /// [danceIds] **before** those dances are hard-deleted, so
  /// [_garbageCollectOrphanedRefs] knows exactly which rows might have just
  /// lost their last citation. Scoping to this snapshot keeps the sweep precise:
  /// pre-existing unreferenced rows (e.g. reusable "Traditional"/"Unknown"
  /// choreographers) that this purge did not touch are never candidates for
  /// removal. Called inside the delete transaction of [purgeDeleted] /
  /// [hardDelete] before the `DELETE FROM dances` cascades the join rows away.
  Future<({Set<String> choreographerIds, Set<String> sourceIds})>
  _referencedRefIds(List<String> danceIds) async {
    final choreographerIds = <String>{};
    final sourceIds = <String>{};
    if (danceIds.isEmpty) {
      return (choreographerIds: choreographerIds, sourceIds: sourceIds);
    }
    for (final chunk in _chunkIds(danceIds)) {
      final authors = await (_db.select(
        _db.danceAuthors,
      )..where((t) => t.danceId.isIn(chunk))).get();
      for (final r in authors) {
        choreographerIds.add(r.choreographerId);
      }
      final sources = await (_db.select(
        _db.danceSources,
      )..where((t) => t.danceId.isIn(chunk))).get();
      for (final r in sources) {
        sourceIds.add(r.sourceId);
      }
    }
    return (choreographerIds: choreographerIds, sourceIds: sourceIds);
  }

  /// Garbage-collects the reusable reference rows in [candidates] (gathered by
  /// [_referencedRefIds]) that, **after** the owning dances were hard-deleted
  /// and their `dance_authors` / `dance_sources` join rows cascaded away, are
  /// now referenced by ZERO remaining dances (#462). Runs inside the same
  /// delete transaction as [purgeDeleted] / [hardDelete], after the
  /// `DELETE FROM dances`.
  ///
  /// A row is kept if any surviving dance still cites it — including a
  /// soft-deleted-but-retained dance, whose join rows persist until its own
  /// purge — because the `NOT IN (SELECT …)` guard tests the live join tables.
  /// This mirrors (and never weakens) the delete-guards in
  /// `ChoreographerRepository` / `PublishedSourceRepository`, which refuse to
  /// remove a still-referenced row; here the last reference is already gone, so
  /// the removal is safe hygiene rather than silent data loss.
  Future<void> _garbageCollectOrphanedRefs(
    ({Set<String> choreographerIds, Set<String> sourceIds}) candidates,
  ) async {
    for (final chunk in _chunkIds(candidates.choreographerIds.toList())) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await _db.customStatement(
        'DELETE FROM choreographers WHERE id IN ($placeholders) AND id NOT IN '
        '(SELECT choreographer_id FROM dance_authors)',
        [...chunk],
      );
    }
    for (final chunk in _chunkIds(candidates.sourceIds.toList())) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await _db.customStatement(
        'DELETE FROM published_sources WHERE id IN ($placeholders) AND id NOT '
        'IN (SELECT source_id FROM dance_sources)',
        [...chunk],
      );
    }
  }

  /// Immediately and permanently removes the dances identified by [ids]
  /// (bypassing the soft-delete/retention path). Cascades to child rows
  /// (authors, tags, links, custom values, provenance, derived figures) via
  /// FK, and clears each dance's `dance_fts` row (that virtual table is not
  /// FK-linked). Any `program_slots.dance_id` pointing at a removed dance is
  /// set to `NULL` (the slot's `text`, if any, survives as a tombstone
  /// caption). Unknown ids are ignored. Runs in a single transaction.
  ///
  /// When [gcOrphanedRefs] is `true` (the default), reusable `choreographers` /
  /// `published_sources` rows this delete leaves referenced by ZERO remaining
  /// dances are garbage-collected in the same transaction (#462). The
  /// import-session **undo** path passes `false`: undo is a faithful rollback
  /// to the pre-import state, so it must leave pre-existing reference rows in
  /// place and do its own targeted cleanup of only the rows that import
  /// *created* (see `ImportPipeline.undo`).
  ///
  /// Intended for reverting a just-committed import batch (import-session
  /// undo); ordinary user deletes should go through [softDelete].
  Future<void> hardDelete(Iterable<String> ids, {bool gcOrphanedRefs = true}) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(() async {
      final rows = await (_db.select(
        _db.dances,
      )..where((t) => t.id.isIn(list))).get();
      final orphanCandidates = gcOrphanedRefs
          ? await _referencedRefIds([for (final r in rows) r.id])
          : null;
      await _cleanupDanglingReferences([
        for (final r in rows) (id: r.id, title: r.title),
      ]);
      for (final id in list) {
        await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
          id,
        ]);
      }
      await (_db.delete(_db.dances)..where((t) => t.id.isIn(list))).go();
      if (orphanCandidates != null) {
        await _garbageCollectOrphanedRefs(orphanCandidates);
      }
    });
  }

  /// Sets the difficulty [level] on many dances at once, in a single
  /// transaction, for the Collection multi-select "batch set level" flow.
  ///
  /// Contract: to *set* a level pass a non-null [level]; to *unset* it pass
  /// [clearLevel] `true`. These are mutually exclusive — calling with neither
  /// throws an [ArgumentError] (and trips a debug assert) to prevent the
  /// footgun of accidentally clearing every dance by omitting [level] (which
  /// would otherwise diverge from [Dance.copyWith], where a null value without
  /// a clear flag keeps the existing value). A set [clearLevel] wins over any [level] value, matching
  /// [Dance.copyWith]. Each affected dance is rewritten through the same upsert
  /// path as [update], so the derived figure/FTS indexes stay consistent.
  ///
  /// Skips unknown ids and dances already at the target level (idempotent), and
  /// stamps [now] as `updatedAt` only on dances that actually change. Returns
  /// the number of dances changed. An empty [ids] is a no-op returning `0`.
  /// Because the whole batch runs in one transaction, an error leaves the
  /// collection untouched rather than half-updated.
  Future<int> setLevelForMany(
    Iterable<String> ids, {
    DanceLevel? level,
    bool clearLevel = false,
    required DateTime now,
  }) {
    // Release-safe guard (asserts are stripped in release): a caller must pass
    // a concrete level, or opt in to clearing via clearLevel. This is checked
    // before the debug-only assert so the thrown ArgumentError is deterministic
    // across build modes. clearLevel still takes precedence when both are set.
    if (!clearLevel && level == null) {
      throw ArgumentError(
        'setLevelForMany requires a non-null level unless clearLevel is true',
      );
    }
    assert(
      clearLevel || level != null,
      'setLevelForMany: pass a non-null level, or clearLevel: true to unset',
    );
    assertUtc(now, 'now');
    final target = clearLevel ? null : level;
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        if (dance.level == target) continue;
        await _upsert(
          dance.copyWith(
            level: target,
            clearLevel: target == null,
            updatedAt: now,
          ),
        );
        changed++;
      }
      return changed;
    });
  }

  /// Sets the curatorial star [rating] on many dances at once, in a single
  /// transaction, for the Collection multi-select "batch set rating" flow
  /// (#423). Direct analogue of [setLevelForMany].
  ///
  /// Contract: to *set* a rating pass a non-null [rating] on the closed `1..5`
  /// scale; to *unset* it pass [clearRating] `true`. Calling with neither
  /// throws an [ArgumentError] (and trips a debug assert) to prevent the
  /// footgun of accidentally clearing every dance by omitting [rating] (which
  /// would otherwise diverge from [Dance.copyWith], where a null value without
  /// a clear flag keeps the existing value). A set [clearRating] wins over any
  /// [rating] value, matching [Dance.copyWith]. An out-of-range [rating] is
  /// rejected up front with an [ArgumentError] so no dance is touched.
  ///
  /// Skips unknown ids and dances already at the target rating (idempotent),
  /// and stamps [now] as `updatedAt` only on dances that actually change.
  /// Returns the number of dances changed. An empty [ids] is a no-op returning
  /// `0`. Because the whole batch runs in one transaction, an error leaves the
  /// collection untouched rather than half-updated.
  Future<int> setRatingForMany(
    Iterable<String> ids, {
    int? rating,
    bool clearRating = false,
    required DateTime now,
  }) {
    // Release-safe guard (asserts are stripped in release): a caller must pass
    // a concrete rating, or opt in to clearing via clearRating. clearRating
    // still takes precedence when both are set.
    if (!clearRating && rating == null) {
      throw ArgumentError(
        'setRatingForMany requires a non-null rating unless clearRating is true',
      );
    }
    assert(
      clearRating || rating != null,
      'setRatingForMany: pass a non-null rating, or clearRating: true to unset',
    );
    // Reject an out-of-range rating before opening the transaction so the
    // thrown error is deterministic and the collection is never half-updated.
    if (!clearRating && rating != null && (rating < 1 || rating > 5)) {
      throw ArgumentError.value(rating, 'rating', 'must be null or 1..5');
    }
    assertUtc(now, 'now');
    final target = clearRating ? null : rating;
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        if (dance.rating == target) continue;
        await _upsert(
          dance.copyWith(
            rating: target,
            clearRating: target == null,
            updatedAt: now,
          ),
        );
        changed++;
      }
      return changed;
    });
  }

  /// Merges [tunes] into the tune set of many dances at once (additive union),
  /// in a single transaction, for the Collection multi-select "batch add tunes"
  /// flow (#423). Mirrors the tag *add* model: existing tunes are preserved and
  /// the specified tunes are appended where missing — nothing is ever removed.
  /// Use [clearTunesForMany] for removal.
  ///
  /// Incoming tunes are sanitized once up front (trimmed, blanks dropped,
  /// case-sensitively de-duplicated preserving first-seen order), matching the
  /// single-dance edit path (`DanceEditorController.addTune`). Per dance, tunes
  /// are appended only where not already present; a dance whose set does not
  /// grow is skipped (idempotent). Skips unknown ids, stamps [now] as
  /// `updatedAt` only on changed dances, and returns the number changed. An
  /// empty [ids] — or an [tunes] that sanitizes to empty — is a no-op returning
  /// `0`.
  Future<int> addTunesForMany(
    Iterable<String> ids, {
    required Iterable<String> tunes,
    required DateTime now,
  }) {
    assertUtc(now, 'now');
    final additions = <String>[];
    for (final raw in tunes) {
      final tune = raw.trim();
      if (tune.isEmpty || additions.contains(tune)) continue;
      additions.add(tune);
    }
    final list = ids.toList();
    if (list.isEmpty || additions.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        final current = dance.tunes;
        final next = [
          ...current,
          for (final tune in additions)
            if (!current.contains(tune)) tune,
        ];
        // Append-only: an unchanged length means every addition was already
        // present, so there is nothing to write.
        if (next.length == current.length) continue;
        await _upsert(dance.copyWith(tunes: next, updatedAt: now));
        changed++;
      }
      return changed;
    });
  }

  /// Removes *all* tunes from many dances at once, in a single transaction, for
  /// the Collection multi-select "batch clear tunes" flow (#423) — the explicit
  /// removal counterpart to the additive [addTunesForMany].
  ///
  /// Skips unknown ids and dances that already have no tunes (idempotent),
  /// stamps [now] as `updatedAt` only on changed dances, and returns the number
  /// changed. An empty [ids] is a no-op returning `0`.
  Future<int> clearTunesForMany(Iterable<String> ids, {required DateTime now}) {
    assertUtc(now, 'now');
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        if (dance.tunes.isEmpty) continue;
        await _upsert(dance.copyWith(tunes: const [], updatedAt: now));
        changed++;
      }
      return changed;
    });
  }

  /// Upserts a single custom-field key→[value] across many dances at once, in a
  /// single transaction, for the Collection multi-select "batch edit custom
  /// field" flow (#423). For each selected dance the entry for [def] is set or
  /// overwritten while **all other custom-field keys are left untouched**; a
  /// dance lacking the key has it added.
  ///
  /// The [value] is validated against [def] via [CustomFieldValue.matchesType]
  /// (respecting `choice` options and numeric/boolean/text typing) and an
  /// invalid value is rejected up front with an [ArgumentError] so no dance is
  /// touched — the OWASP-aligned guard mirroring the single-dance edit path.
  ///
  /// Skips unknown ids and dances whose entry for [def] already equals [value]
  /// (idempotent), stamps [now] as `updatedAt` only on changed dances, and
  /// returns the number changed. An empty [ids] is a no-op returning `0`.
  Future<int> upsertCustomFieldForMany(
    Iterable<String> ids, {
    required CustomFieldDef def,
    required Object value,
    required DateTime now,
  }) {
    assertUtc(now, 'now');
    final incoming = CustomFieldValue(fieldId: def.id, value: value);
    if (!incoming.matchesType(def)) {
      throw ArgumentError.value(
        value,
        'value',
        'does not match custom field "${def.key}" of type ${def.type.name}',
      );
    }
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        final current = dance.customFields;
        final alreadySet = current.any(
          (f) => f.fieldId == def.id && f.value == value,
        );
        if (alreadySet) continue;
        final next = [
          for (final f in current)
            if (f.fieldId != def.id) f,
          incoming,
        ];
        await _upsert(dance.copyWith(customFields: next, updatedAt: now));
        changed++;
      }
      return changed;
    });
  }

  /// Clears a single custom-field key (identified by [fieldId]) across many
  /// dances at once, in a single transaction, for the Collection multi-select
  /// "batch edit custom field" flow (#423) — the removal counterpart to
  /// [upsertCustomFieldForMany]. Only the entry for [fieldId] is removed from
  /// each dance; **all other keys are left untouched**.
  ///
  /// Skips unknown ids and dances that lack the key (idempotent), stamps [now]
  /// as `updatedAt` only on changed dances, and returns the number changed. An
  /// empty [ids] is a no-op returning `0`.
  Future<int> clearCustomFieldForMany(
    Iterable<String> ids, {
    required String fieldId,
    required DateTime now,
  }) {
    assertUtc(now, 'now');
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        final current = dance.customFields;
        if (!current.any((f) => f.fieldId == fieldId)) continue;
        final next = [
          for (final f in current)
            if (f.fieldId != fieldId) f,
        ];
        await _upsert(dance.copyWith(customFields: next, updatedAt: now));
        changed++;
      }
      return changed;
    });
  }

  /// Read-only dry-run for the #417 "re-check custom figures" flow: scans every
  /// non-deleted dance and returns a [CustomReparsePreview] for each one that
  /// has at least one import-gap custom figure whose stored text now parses to
  /// a structured taxonomy move. Dances with nothing to upgrade are omitted, so
  /// an empty result means "nothing to do". Writes nothing.
  ///
  /// Reads only the three columns it needs (`id`, `title`, `figures_json`) and
  /// decodes the figures locally — deliberately avoiding [listAll]/[_toModel],
  /// whose six per-dance relationship queries (authors, tags, links, custom
  /// values, sources, provenance) are irrelevant to a figure-only check and
  /// would make this an O(1 + 6N)-query scan. Results are ordered
  /// case-insensitively by title to match the collection's `COLLATE NOCASE`
  /// display order.
  Future<List<CustomReparsePreview>> previewImportGapReparse() async {
    final rows =
        await (_db.selectOnly(_db.dances)
              ..addColumns([
                _db.dances.id,
                _db.dances.title,
                _db.dances.figuresJson,
              ])
              ..where(_db.dances.deletedAt.isNull()))
            .get();

    final previews = <CustomReparsePreview>[];
    for (final row in rows) {
      final figures = decodeFigures(row.read(_db.dances.figuresJson)!);
      final outcome = reparseImportGapFigures(figures, taxonomy: _taxonomy);
      if (outcome.upgradedCount > 0) {
        previews.add(
          CustomReparsePreview(
            danceId: row.read(_db.dances.id)!,
            title: row.read(_db.dances.title)!,
            upgradeCount: outcome.upgradedCount,
          ),
        );
      }
    }
    previews.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return previews;
  }

  /// Applies the #417 re-parse to the dances in [ids], upgrading import-gap
  /// custom figures whose stored text now maps to a structured move. Only the
  /// individual upgraded figures are rewritten (in place); every other field —
  /// tags, rating, tunes, notes, custom fields, author/program links, id,
  /// favorite/updated status, and all non-import-gap figures — is preserved
  /// exactly, because each dance is rewritten via [Dance.copyWith] through the
  /// same upsert path as [update].
  ///
  /// Stamps [now] as `updatedAt` only on dances that actually change; dances
  /// with nothing to upgrade are skipped, so the operation is idempotent
  /// (re-running changes nothing further). Skips unknown ids. Returns the
  /// number of dances changed. An empty [ids] is a no-op returning `0`. The
  /// whole batch runs in one transaction, so an error leaves the collection
  /// untouched rather than half-updated.
  Future<int> reparseImportGapFiguresForMany(
    Iterable<String> ids, {
    required DateTime now,
  }) {
    assertUtc(now, 'now');
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var changed = 0;
      for (final id in list) {
        final dance = await getById(id);
        if (dance == null) continue;
        final outcome = reparseImportGapFigures(
          dance.figures,
          taxonomy: _taxonomy,
        );
        if (outcome.upgradedCount == 0) continue;
        await _upsert(dance.copyWith(figures: outcome.figures, updatedAt: now));
        changed++;
      }
      return changed;
    });
  }

  /// [Dance.duplicate] (fresh identity, no provenance) and persists it.
  Future<Dance> duplicate({
    required String id,
    required String newId,
    required DateTime now,
  }) async {
    assertUtc(now, 'now');
    final source = await getById(id, includeDeleted: true);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'no such dance');
    }
    final copy = source.duplicate(newId: newId, now: now);
    await create(copy);
    return copy;
  }

  /// Full-text search over title/authors/hook/notes/figures/custom values.
  /// Returns dance ids ranked by FTS5's `bm25` relevance (best first).
  ///
  /// Soft-deleted (trashed) dances are excluded (#439): the `dance_fts` virtual
  /// table retains a row until the owning dance is purged/hard-deleted, so the
  /// bare `MATCH` must JOIN `dances` and filter `deleted_at IS NULL` to stay
  /// consistent with every other list/search path (mirrors the
  /// `FilterCompiler._compileRelevance` convention). Ranking/order is unchanged.
  Future<List<String>> searchText(String query) async {
    final rows = await _db
        .customSelect(
          'SELECT dance_fts.dance_id FROM dance_fts '
          'JOIN dances ON dances.id = dance_fts.dance_id '
          'WHERE dance_fts MATCH ? AND dances.deleted_at IS NULL '
          'ORDER BY bm25(dance_fts)',
          variables: [Variable.withString(toFtsMatchQuery(query))],
        )
        .get();
    return [for (final r in rows) r.read<String>('dance_id')];
  }

  /// Composable structural + metadata search (`docs/design/search.md`).
  ///
  /// Compiles [filter] to a single parameterized query over the derived
  /// indexes ([FilterCompiler]) and returns the matching non-deleted dance
  /// ids in [sort] order. [dialect] (default [Dialect.canonical]) canonicalizes
  /// move names, full-text terms and role-valued params at the compiler
  /// boundary so a dialect user's query matches the canonical stored tokens.
  /// [enrichment] optionally adds always-on reverse synonyms from the union of
  /// every saved dialect, so terms configured in any saved dialect resolve
  /// regardless of which one is active (the active dialect and legacy synonyms
  /// still win on overlap).
  ///
  /// [SearchSort.title], [SearchSort.recentlyAdded], [SearchSort.recentlyEdited]
  /// and (bare-full-text) [SearchSort.relevance] are ordered in SQL;
  /// [SearchSort.author] and [SearchSort.lastCalled] reuse the Phase 3.1
  /// orderings and are applied in Dart over the fetched id set. Those two keys
  /// are **not** columns on `dances`: the first author's name comes from
  /// `dance_authors` joined to `choreographers`, and the last-called timestamp
  /// is a `MAX(performed_at)` aggregate over `program_slots`/`programs` — so
  /// they can't be an SQL `ORDER BY` here and are computed as a post-fetch
  /// step. The post-sort is stable, preserving the SQL title base order for
  /// ties.
  ///
  /// When [ignoreLeadingArticles] is `true`, [SearchSort.title] alphabetizes
  /// with a leading article ("the"/"a"/"an") ignored (see [titleSortKey]) —
  /// e.g. "The Nice Combination" files under **N**. This is applied as a stable
  /// Dart post-sort over the SQL base order; other sorts are unaffected.
  ///
  /// [direction] flips the ordering; when omitted it resolves to the sort key's
  /// [SearchSortDirectionX.defaultDirection], preserving the historical order.
  /// For the timestamp, rating, composed-date, and last-called sorts,
  /// NULL/absent/never-called rows stay **last** in both directions. The author
  /// sort instead orders author-less dances by an empty key (so they sort first
  /// ascending, last descending), matching Phase 3.1's Collection author sort.
  Future<List<String>> search(
    DanceFilter filter, {
    SearchSort sort = SearchSort.title,
    SortDirection? direction,
    Dialect? dialect,
    SearchEnrichment? enrichment,
    bool ignoreLeadingArticles = false,
  }) async {
    final dir = direction ?? sort.defaultDirection;
    final descending = dir == SortDirection.descending;
    final compiled = FilterCompiler(
      dialect,
      enrichment,
    ).compile(filter, sort: sort, direction: dir);
    final rows = await _db
        .customSelect(
          compiled.sql,
          variables: [for (final b in compiled.binds) Variable(b)],
        )
        .get();
    final ids = [for (final r in rows) r.read<String>(r.data.keys.first)];
    switch (sort) {
      case SearchSort.author:
        return _sortByAuthor(ids, descending: descending);
      case SearchSort.lastCalled:
        return _sortByLastCalled(ids, descending: descending);
      case SearchSort.title:
        return ignoreLeadingArticles
            ? _sortByTitleIgnoringArticles(ids, descending: descending)
            : ids;
      case SearchSort.recentlyAdded:
      case SearchSort.recentlyEdited:
      case SearchSort.composedOn:
      case SearchSort.rating:
      case SearchSort.relevance:
        return ids;
    }
  }

  /// Like [search] but returns hydrated [Dance]s in the same order. Convenience
  /// for callers that immediately need the full objects; the id-returning
  /// [search] is the primary contract.
  Future<List<Dance>> searchDances(
    DanceFilter filter, {
    SearchSort sort = SearchSort.title,
    SortDirection? direction,
    Dialect? dialect,
    SearchEnrichment? enrichment,
    bool ignoreLeadingArticles = false,
  }) async {
    final ids = await search(
      filter,
      sort: sort,
      direction: direction,
      dialect: dialect,
      enrichment: enrichment,
      ignoreLeadingArticles: ignoreLeadingArticles,
    );
    final result = <Dance>[];
    for (final id in ids) {
      final dance = await getById(id);
      if (dance != null) result.add(dance);
    }
    return result;
  }

  /// Alphabetizes [ids] by title with a leading article ignored (see
  /// [titleSortKey]). [ids] arrive in SQL title (base) order, kept as a stable
  /// tiebreak for equal keys (e.g. "Rose" vs "The Rose" both key to "rose").
  ///
  /// Only the `(id, title)` of the already-filtered [ids] is fetched (via an
  /// `id IN (...)` restriction), so this scales with the result size rather
  /// than the whole library.
  Future<List<String>> _sortByTitleIgnoringArticles(
    List<String> ids, {
    bool descending = false,
  }) async {
    if (ids.isEmpty) return ids;
    final rows =
        await (_db.selectOnly(_db.dances)
              ..addColumns([_db.dances.id, _db.dances.title])
              ..where(_db.dances.id.isIn(ids)))
            .get();
    final keys = {
      for (final row in rows)
        row.read(_db.dances.id)!: titleSortKey(row.read(_db.dances.title)!),
    };
    final baseOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final sorted = [...ids]
      ..sort((a, b) {
        var cmp = (keys[a] ?? '').compareTo(keys[b] ?? '');
        if (descending) cmp = -cmp;
        return cmp != 0 ? cmp : baseOrder[a]!.compareTo(baseOrder[b]!);
      });
    return sorted;
  }

  Future<List<String>> _sortByAuthor(
    List<String> ids, {
    bool descending = false,
  }) async {
    if (ids.isEmpty) return ids;
    // First author (position 0) name per dance; dances with no author have an
    // empty key, so they sort first ascending / last descending, matching
    // Phase 3.1's Collection author sort. The aggregate is restricted to the
    // incoming result `ids` (chunked `dance_id IN (…)`, like [listAll]) so a
    // narrowed result set does not scan the whole collection. Each dance_id is
    // unique and lands in one chunk, and `position = 0` yields at most one row
    // per dance, so merging the chunk rows equals a single restricted query.
    final names = <String, String>{};
    for (final chunk in _chunkIds(ids)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db
          .customSelect(
            'SELECT dance_authors.dance_id AS dance_id, '
            'choreographers.name AS name FROM dance_authors '
            'JOIN choreographers '
            'ON choreographers.id = dance_authors.choreographer_id '
            'WHERE dance_authors.position = 0 '
            'AND dance_authors.dance_id IN ($placeholders)',
            variables: [for (final id in chunk) Variable(id)],
          )
          .get();
      for (final r in rows) {
        names[r.read<String>('dance_id')] = r
            .read<String>('name')
            .toLowerCase();
      }
    }
    // `ids` arrives in title (base) order; keep it as a stable tiebreak since
    // Dart's List.sort is not guaranteed stable.
    final baseOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final sorted = [...ids]
      ..sort((a, b) {
        var cmp = (names[a] ?? '').compareTo(names[b] ?? '');
        if (descending) cmp = -cmp;
        return cmp != 0 ? cmp : baseOrder[a]!.compareTo(baseOrder[b]!);
      });
    return sorted;
  }

  Future<List<String>> _sortByLastCalled(
    List<String> ids, {
    bool descending = true,
  }) async {
    if (ids.isEmpty) return ids;
    // Mirrors ProgramRepository.lastCalledByDance(): most-recent performed_at
    // per dance across non-deleted programs. Never-called dances sort last
    // regardless of direction. The aggregate is restricted to the incoming
    // result `ids` (chunked `dance_id IN (…)`, like [listAll]) so a narrowed
    // result set does not scan every performed slot in the library. Each
    // dance_id is unique and lands in one chunk, and `GROUP BY dance_id`
    // computes each dance's MAX fully within its chunk, so merging the chunk
    // rows equals a single restricted query.
    final lastCalled = <String, DateTime>{};
    for (final chunk in _chunkIds(ids)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db
          .customSelect(
            'SELECT program_slots.dance_id AS dance_id, '
            'MAX(program_slots.performed_at) AS last_called '
            'FROM program_slots '
            'JOIN programs ON programs.id = program_slots.program_id '
            'WHERE program_slots.dance_id IS NOT NULL '
            'AND program_slots.performed_at IS NOT NULL '
            'AND programs.deleted_at IS NULL '
            'AND program_slots.dance_id IN ($placeholders) '
            'GROUP BY program_slots.dance_id',
            variables: [for (final id in chunk) Variable(id)],
          )
          .get();
      for (final r in rows) {
        lastCalled[r.read<String>('dance_id')] = r.read<DateTime>(
          'last_called',
        );
      }
    }
    // `ids` arrives in title (base) order; keep it as a stable tiebreak.
    final baseOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final sorted = [...ids]
      ..sort((a, b) {
        final ca = lastCalled[a];
        final cb = lastCalled[b];
        final tie = baseOrder[a]!.compareTo(baseOrder[b]!);
        if (ca == null && cb == null) return tie;
        if (ca == null) return 1;
        if (cb == null) return -1;
        // Default (descending) is most-recent-first; ascending is oldest-first.
        final cmp = descending ? cb.compareTo(ca) : ca.compareTo(cb);
        return cmp != 0 ? cmp : tie;
      });
    return sorted;
  }

  /// Structural search: ids of non-deleted dances containing a figure with
  /// the given canonical [move] id (and, if given, an exact `params[key]`
  /// match — compared as JSON text, so values must be passed pre-encoded,
  /// e.g. `'"partners"'` for a string or `16` for a number). A minimal
  /// building block; the full composable filter-tree compiler is Phase 3.2.
  Future<List<String>> danceIdsWithFigure(
    String move, {
    String? paramKey,
    String? paramJsonValue,
  }) async {
    final query =
        _db.select(_db.danceFigures).join([
          innerJoin(
            _db.dances,
            _db.dances.id.equalsExp(_db.danceFigures.danceId),
          ),
        ])..where(
          _db.danceFigures.move.equals(move) & _db.dances.deletedAt.isNull(),
        );
    final rows = await query.get();
    final ids = <String>{};
    for (final row in rows) {
      if (paramKey == null) {
        ids.add(row.readTable(_db.dances).id);
        continue;
      }
      final params =
          jsonDecode(row.readTable(_db.danceFigures).paramsJson)
              as Map<String, Object?>;
      final actual = params[paramKey];
      final expected = paramJsonValue == null
          ? null
          : jsonDecode(paramJsonValue);
      if (actual == expected) {
        ids.add(row.readTable(_db.dances).id);
      }
    }
    return ids.toList();
  }

  Future<Dance> _toModel(DanceRow row) async {
    // Single-dance hydration reuses the same batched child loaders as
    // [listAll] (each becomes a one-`id` `IN (…)` query), so the two paths
    // stay byte-for-byte consistent in field ordering and decoding.
    final id = row.id;
    final authors = await _authorsForMany([id]);
    final tags = await _tagsForMany([id]);
    final links = await _linksForMany([id]);
    final sources = await _sourcesForMany([id]);
    final customFields = await _customFieldsForMany([id]);
    final provenance = await _provenanceForMany([id]);
    return _buildDance(
      row,
      authorIds: authors[id] ?? const [],
      tagIds: tags[id] ?? const [],
      links: links[id] ?? const [],
      sourceCitations: sources[id] ?? const [],
      customFields: customFields[id] ?? const [],
      provenance: provenance[id],
    );
  }

  /// Assembles a [Dance] from a fetched [DanceRow] and its already-resolved
  /// child collections. Pure (no I/O), so both the single-row [_toModel] and
  /// the batched [listAll] feed it the same way.
  Dance _buildDance(
    DanceRow row, {
    required List<String> authorIds,
    required List<String> tagIds,
    required List<DanceLink> links,
    required List<SourceCitation> sourceCitations,
    required List<CustomFieldValue> customFields,
    required model.Provenance? provenance,
  }) {
    return Dance(
      id: row.id,
      title: row.title,
      authorIds: authorIds,
      form: row.form,
      formation: Formation(row.formationShape, detail: row.formationDetail),
      progression: row.progression,
      phraseStructure: row.phraseStructure,
      figures: decodeFigures(row.figuresJson),
      hook: row.hook,
      callingNotes: row.callingNotes,
      status: row.status,
      level: row.level,
      mixedLevel: row.mixedLevel,
      rating: row.rating,
      composedOn: row.composedOn == null
          ? null
          : PartialDate.parse(row.composedOn!),
      revisedOn: row.revisedOn == null
          ? null
          : PartialDate.parse(row.revisedOn!),
      tunes: (jsonDecode(row.tunesJson) as List).cast<String>(),
      customFields: customFields,
      tagIds: tagIds,
      links: links,
      sourceCitations: sourceCitations,
      provenance: provenance,
      createdAt: asUtc(row.createdAt),
      updatedAt: asUtc(row.updatedAt),
      deletedAt: asUtcOrNull(row.deletedAt),
    );
  }

  /// Max ids per `IN (…)` clause. Kept well under SQLite's default
  /// `SQLITE_MAX_VARIABLE_NUMBER` (999 on older builds) so a full-collection
  /// load stays correct no matter how large the library grows; the batched
  /// loaders below split their id list into chunks of this size.
  static const int _idChunkSize = 500;

  Iterable<List<String>> _chunkIds(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final end = i + _idChunkSize;
      yield ids.sublist(i, end > ids.length ? ids.length : end);
    }
  }

  /// First-author-first `dance_id → [choreographerId]` in position order.
  Future<Map<String, List<String>>> _authorsForMany(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, List<String>>{};
    for (final chunk in _chunkIds(ids)) {
      final rows =
          await (_db.select(_db.danceAuthors)
                ..where((t) => t.danceId.isIn(chunk))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.danceId),
                  (t) => OrderingTerm(expression: t.position),
                ]))
              .get();
      for (final r in rows) {
        (byDance[r.danceId] ??= <String>[]).add(r.choreographerId);
      }
    }
    return byDance;
  }

  /// `dance_id → [tagId]` in insertion (row) order, matching the un-ordered
  /// per-dance query the single-row path historically used.
  Future<Map<String, List<String>>> _tagsForMany(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, List<String>>{};
    for (final chunk in _chunkIds(ids)) {
      final rows =
          await (_db.select(_db.danceTags)
                ..where((t) => t.danceId.isIn(chunk))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.danceId),
                  (t) => OrderingTerm(expression: t.rowId),
                ]))
              .get();
      for (final r in rows) {
        (byDance[r.danceId] ??= <String>[]).add(r.tagId);
      }
    }
    return byDance;
  }

  /// `dance_id → [DanceLink]` in insertion (row) order.
  Future<Map<String, List<DanceLink>>> _linksForMany(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, List<DanceLink>>{};
    for (final chunk in _chunkIds(ids)) {
      final rows =
          await (_db.select(_db.danceLinks)
                ..where((t) => t.danceId.isIn(chunk))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.danceId),
                  (t) => OrderingTerm(expression: t.rowId),
                ]))
              .get();
      for (final r in rows) {
        final link = _linkFromRow(r);
        if (link == null) continue;
        (byDance[r.danceId] ??= <DanceLink>[]).add(link);
      }
    }
    return byDance;
  }

  /// Maps a link row to a [DanceLink], returning `null` for a row the domain
  /// invariants reject rather than throwing. A pre-fix purge could leave a
  /// `relatedDance` link whose `target_dance_id` was SET NULL (#466); tolerating
  /// it here means one corrupt row can't fail the whole Collection load
  /// (`listAll`/`getById`). [purgeDeleted]/[hardDelete] and the one-time repair
  /// in `CompendiumRepositories.ensureMigrated` remove such rows for good.
  DanceLink? _linkFromRow(DanceLinkRow r) {
    try {
      return DanceLink(
        id: r.id,
        kind: r.kind,
        url: r.url,
        targetDanceId: r.targetDanceId,
        label: r.label,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// `dance_id → [SourceCitation]` in position order.
  Future<Map<String, List<SourceCitation>>> _sourcesForMany(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, List<SourceCitation>>{};
    for (final chunk in _chunkIds(ids)) {
      final rows =
          await (_db.select(_db.danceSources)
                ..where((t) => t.danceId.isIn(chunk))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.danceId),
                  (t) => OrderingTerm(expression: t.position),
                ]))
              .get();
      for (final r in rows) {
        (byDance[r.danceId] ??= <SourceCitation>[]).add(
          SourceCitation(sourceId: r.sourceId, page: r.page, number: r.number),
        );
      }
    }
    return byDance;
  }

  /// `dance_id → [CustomFieldValue]` in insertion (row) order, decoded against
  /// each value's field definition (inner-joined, so a value whose def is gone
  /// is dropped — exactly as the single-row path did).
  Future<Map<String, List<CustomFieldValue>>> _customFieldsForMany(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, List<CustomFieldValue>>{};
    for (final chunk in _chunkIds(ids)) {
      final query = _db.select(_db.customFieldValues)
        ..where((t) => t.danceId.isIn(chunk));
      final joined =
          query.join([
            innerJoin(
              _db.customFieldDefs,
              _db.customFieldDefs.id.equalsExp(_db.customFieldValues.fieldId),
            ),
          ])..orderBy([
            OrderingTerm(expression: _db.customFieldValues.danceId),
            OrderingTerm(expression: _db.customFieldValues.rowId),
          ]);
      final rows = await joined.get();
      for (final r in rows) {
        final value = r.readTable(_db.customFieldValues);
        final def = r.readTable(_db.customFieldDefs);
        (byDance[value.danceId] ??= <CustomFieldValue>[]).add(
          decodeCustomFieldValue(
            fieldId: value.fieldId,
            type: def.type,
            valueText: value.valueText,
            valueNum: value.valueNum,
          ),
        );
      }
    }
    return byDance;
  }

  /// `dance_id → Provenance` (at most one row per dance).
  Future<Map<String, model.Provenance>> _provenanceForMany(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final byDance = <String, model.Provenance>{};
    for (final chunk in _chunkIds(ids)) {
      final rows = await (_db.select(
        _db.provenance,
      )..where((t) => t.danceId.isIn(chunk))).get();
      for (final r in rows) {
        byDance[r.danceId] = model.Provenance(
          source: r.source,
          externalId: r.externalId,
          importedAt: asUtc(r.importedAt),
          permission: r.permission,
          license: r.license,
          rawPayload: r.rawPayload,
          sourceVersion: r.sourceVersion,
        );
      }
    }
    return byDance;
  }
}

/// A single dance's dry-run result for the #417 re-parse flow: how many of its
/// import-gap custom figures would be upgraded to structured moves. Produced by
/// [DanceRepository.previewImportGapReparse]; UI shows these before the user
/// confirms the (opt-in, non-destructive) apply.
class CustomReparsePreview {
  const CustomReparsePreview({
    required this.danceId,
    required this.title,
    required this.upgradeCount,
  });

  final String danceId;
  final String title;
  final int upgradeCount;
}
