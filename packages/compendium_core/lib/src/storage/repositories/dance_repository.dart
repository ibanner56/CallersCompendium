import 'dart:convert';

import 'package:drift/drift.dart';

import '../../dialect/dialect.dart';
import '../../dialect/renderer.dart';
import '../../model/dance.dart';
import '../../model/dance_link.dart';
import '../../model/enums.dart';
import '../../model/formation.dart';
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

  Future<void> _rebuildDerived(Dance dance) async {
    await (_db.delete(
      _db.danceFigures,
    )..where((t) => t.danceId.equals(dance.id))).go();
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

    await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
      dance.id,
    ]);
    final authorNames = <String>[];
    for (final authorId in dance.authorIds) {
      final row = await (_db.select(
        _db.choreographers,
      )..where((t) => t.id.equals(authorId))).getSingleOrNull();
      if (row != null) authorNames.add(row.name);
    }
    final customValueText = dance.customFields
        .map((v) => v.value.toString())
        .join(' ');
    final sourceTexts = <String>[];
    if (dance.sourceCitations.isNotEmpty) {
      final sourceIds = dance.sourceCitations.map((c) => c.sourceId).toList();
      final rows = await (_db.select(
        _db.publishedSources,
      )..where((t) => t.id.isIn(sourceIds))).get();
      final byId = {for (final r in rows) r.id: r};
      for (final citation in dance.sourceCitations) {
        final row = byId[citation.sourceId];
        if (row == null) continue;
        sourceTexts.add(row.title);
        if (row.author != null) sourceTexts.add(row.author!);
      }
    }
    await _db.customStatement(
      'INSERT INTO dance_fts'
      '(dance_id, title, authors, hook, notes, figures_text, custom_values, '
      'sources) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        dance.id,
        dance.title,
        authorNames.join(' '),
        dance.hook,
        dance.callingNotes,
        canonicalTexts.join(' '),
        customValueText,
        sourceTexts.join(' '),
      ],
    );
  }

  /// Recomputes `dance_figures` and `dance_fts` for every non-deleted dance
  /// from `figures_json`. Intended as an integrity repair after a migration
  /// that changes derived-table shape, or if corruption is detected by
  /// `PRAGMA quick_check`.
  Future<void> rebuildAllDerived() => _db.transaction(() async {
    final dances = await listAll(includeDeleted: true);
    for (final dance in dances) {
      await _rebuildDerived(dance);
    }
  });

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
    return [for (final row in rows) await _toModel(row)];
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
  /// (the slot's `text`, if any, survives as a tombstone caption).
  Future<int> purgeDeleted({
    required DateTime now,
    Duration retention = const Duration(days: 30),
  }) async {
    assertUtc(now, 'now');
    final cutoff = now.subtract(retention);
    final toPurge = await (_db.select(
      _db.dances,
    )..where((t) => t.deletedAt.isSmallerOrEqualValue(cutoff))).get();
    return _db.transaction(() async {
      for (final row in toPurge) {
        await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
          row.id,
        ]);
      }
      return (_db.delete(
        _db.dances,
      )..where((t) => t.deletedAt.isSmallerOrEqualValue(cutoff))).go();
    });
  }

  /// Immediately and permanently removes the dances identified by [ids]
  /// (bypassing the soft-delete/retention path). Cascades to child rows
  /// (authors, tags, links, custom values, provenance, derived figures) via
  /// FK, and clears each dance's `dance_fts` row (that virtual table is not
  /// FK-linked). Any `program_slots.dance_id` pointing at a removed dance is
  /// set to `NULL` (the slot's `text`, if any, survives as a tombstone
  /// caption). Unknown ids are ignored. Runs in a single transaction.
  ///
  /// Intended for reverting a just-committed import batch (import-session
  /// undo); ordinary user deletes should go through [softDelete].
  Future<void> hardDelete(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(() async {
      for (final id in list) {
        await _db.customStatement('DELETE FROM dance_fts WHERE dance_id = ?', [
          id,
        ]);
      }
      await (_db.delete(_db.dances)..where((t) => t.id.isIn(list))).go();
    });
  }

  /// Duplicates the dance identified by [id] under [newId] via
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
  Future<List<String>> searchText(String query) async {
    final rows = await _db
        .customSelect(
          'SELECT dance_id FROM dance_fts WHERE dance_fts MATCH ? '
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
  Future<List<String>> search(
    DanceFilter filter, {
    SearchSort sort = SearchSort.title,
    Dialect? dialect,
    SearchEnrichment? enrichment,
    bool ignoreLeadingArticles = false,
  }) async {
    final compiled = FilterCompiler(
      dialect,
      enrichment,
    ).compile(filter, sort: sort);
    final rows = await _db
        .customSelect(
          compiled.sql,
          variables: [for (final b in compiled.binds) Variable(b)],
        )
        .get();
    final ids = [for (final r in rows) r.read<String>(r.data.keys.first)];
    switch (sort) {
      case SearchSort.author:
        return _sortByAuthor(ids);
      case SearchSort.lastCalled:
        return _sortByLastCalled(ids);
      case SearchSort.title:
        return ignoreLeadingArticles ? _sortByTitleIgnoringArticles(ids) : ids;
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
    Dialect? dialect,
    SearchEnrichment? enrichment,
    bool ignoreLeadingArticles = false,
  }) async {
    final ids = await search(
      filter,
      sort: sort,
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
  Future<List<String>> _sortByTitleIgnoringArticles(List<String> ids) async {
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
        final cmp = (keys[a] ?? '').compareTo(keys[b] ?? '');
        return cmp != 0 ? cmp : baseOrder[a]!.compareTo(baseOrder[b]!);
      });
    return sorted;
  }

  Future<List<String>> _sortByAuthor(List<String> ids) async {
    if (ids.isEmpty) return ids;
    // First author (position 0) name per dance; dances with no author sort
    // first (empty name), matching Phase 3.1's Collection author sort.
    final rows = await _db
        .customSelect(
          'SELECT dance_authors.dance_id AS dance_id, '
          'choreographers.name AS name FROM dance_authors '
          'JOIN choreographers '
          'ON choreographers.id = dance_authors.choreographer_id '
          'WHERE dance_authors.position = 0',
        )
        .get();
    final names = {
      for (final r in rows)
        r.read<String>('dance_id'): r.read<String>('name').toLowerCase(),
    };
    // `ids` arrives in title (base) order; keep it as a stable tiebreak since
    // Dart's List.sort is not guaranteed stable.
    final baseOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final sorted = [...ids]
      ..sort((a, b) {
        final cmp = (names[a] ?? '').compareTo(names[b] ?? '');
        return cmp != 0 ? cmp : baseOrder[a]!.compareTo(baseOrder[b]!);
      });
    return sorted;
  }

  Future<List<String>> _sortByLastCalled(List<String> ids) async {
    if (ids.isEmpty) return ids;
    // Mirrors ProgramRepository.lastCalledByDance(): most-recent performed_at
    // per dance across non-deleted programs. Never-called dances sort last.
    final rows = await _db
        .customSelect(
          'SELECT program_slots.dance_id AS dance_id, '
          'MAX(program_slots.performed_at) AS last_called '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id IS NOT NULL '
          'AND program_slots.performed_at IS NOT NULL '
          'AND programs.deleted_at IS NULL '
          'GROUP BY program_slots.dance_id',
        )
        .get();
    final lastCalled = {
      for (final r in rows)
        r.read<String>('dance_id'): r.read<DateTime>('last_called'),
    };
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
        final cmp = cb.compareTo(ca);
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
    final authorRows =
        await (_db.select(_db.danceAuthors)
              ..where((t) => t.danceId.equals(row.id))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    final tagRows = await (_db.select(
      _db.danceTags,
    )..where((t) => t.danceId.equals(row.id))).get();
    final linkRows = await (_db.select(
      _db.danceLinks,
    )..where((t) => t.danceId.equals(row.id))).get();
    final sourceRows =
        await (_db.select(_db.danceSources)
              ..where((t) => t.danceId.equals(row.id))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    final customRows =
        await (_db.select(
          _db.customFieldValues,
        )..where((t) => t.danceId.equals(row.id))).join([
          innerJoin(
            _db.customFieldDefs,
            _db.customFieldDefs.id.equalsExp(_db.customFieldValues.fieldId),
          ),
        ]).get();
    final provRow = await (_db.select(
      _db.provenance,
    )..where((t) => t.danceId.equals(row.id))).getSingleOrNull();

    return Dance(
      id: row.id,
      title: row.title,
      authorIds: [for (final a in authorRows) a.choreographerId],
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
      customFields: [
        for (final r in customRows)
          decodeCustomFieldValue(
            fieldId: r.readTable(_db.customFieldValues).fieldId,
            type: r.readTable(_db.customFieldDefs).type,
            valueText: r.readTable(_db.customFieldValues).valueText,
            valueNum: r.readTable(_db.customFieldValues).valueNum,
          ),
      ],
      tagIds: [for (final t in tagRows) t.tagId],
      links: [
        for (final l in linkRows)
          DanceLink(
            id: l.id,
            kind: l.kind,
            url: l.url,
            targetDanceId: l.targetDanceId,
            label: l.label,
          ),
      ],
      sourceCitations: [
        for (final s in sourceRows)
          SourceCitation(sourceId: s.sourceId, page: s.page, number: s.number),
      ],
      provenance: provRow == null
          ? null
          : model.Provenance(
              source: provRow.source,
              externalId: provRow.externalId,
              importedAt: asUtc(provRow.importedAt),
              permission: provRow.permission,
              license: provRow.license,
              rawPayload: provRow.rawPayload,
              sourceVersion: provRow.sourceVersion,
            ),
      createdAt: asUtc(row.createdAt),
      updatedAt: asUtc(row.updatedAt),
      deletedAt: asUtcOrNull(row.deletedAt),
    );
  }
}
