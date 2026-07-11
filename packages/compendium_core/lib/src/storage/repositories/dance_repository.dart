import 'dart:convert';

import 'package:drift/drift.dart';

import '../../dialect/renderer.dart';
import '../../model/dance.dart';
import '../../model/dance_link.dart';
import '../../model/formation.dart';
import '../../model/provenance.dart' as model;
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
    await _db.customStatement(
      'INSERT INTO dance_fts'
      '(dance_id, title, authors, hook, notes, figures_text, custom_values) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        dance.id,
        dance.title,
        authorNames.join(' '),
        dance.hook,
        dance.callingNotes,
        canonicalTexts.join(' '),
        customValueText,
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
          variables: [Variable.withString(query)],
        )
        .get();
    return [for (final r in rows) r.read<String>('dance_id')];
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
