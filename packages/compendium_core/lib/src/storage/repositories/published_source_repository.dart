import 'package:drift/drift.dart';

import '../../model/published_source.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';

/// CRUD for [PublishedSource] rows — the reusable bibliographic entity many
/// dances cite. Mirrors `ChoreographerRepository`: editing a source's metadata
/// happens in one place and a delete is guarded while the source is still
/// referenced by any dance citation.
///
/// Published sources are **soft-deleted** as of schema v25 (issue #898). They
/// carry no UNIQUE natural key, so an upsert can only ever land on the row
/// sharing its id.
class PublishedSourceRepository {
  PublishedSourceRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(PublishedSource s, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      await _db
          .into(_db.publishedSources)
          .insertOnConflictUpdate(
            PublishedSourcesCompanion.insert(
              id: s.id,
              title: normalizeShareableText(s.title),
              author: Value(
                s.author == null ? null : normalizeShareableText(s.author!),
              ),
              year: Value(s.year),
              url: Value(s.url == null ? null : normalizeShareableText(s.url!)),
              notes: Value(
                s.notes == null ? null : normalizeShareableText(s.notes!),
              ),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: _db.publishedSources,
        keyColumn: 'id',
        key: s.id,
        at: now,
      );
    });
  }

  Future<PublishedSource?> getById(String id) async {
    final row = await (_db.select(
      _db.publishedSources,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<PublishedSource>> listAll() async {
    final rows =
        await (_db.select(_db.publishedSources)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) =>
                    OrderingTerm(expression: t.title.collate(Collate.noCase)),
              ]))
            .get();
    return rows.map(_toModel).toList();
  }

  Future<List<({PublishedSource source, bool deleted})>>
  listAllWithDeleted() async {
    final rows =
        await (_db.select(_db.publishedSources)..orderBy([
              (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
            ]))
            .get();
    return [
      for (final row in rows)
        (source: _toModel(row), deleted: row.deletedAt != null),
    ];
  }

  /// Throws if [id] is still referenced by any `dance_sources` row — callers
  /// must remove the citing dances' citations first (deleting a source out
  /// from under citing dances would be a silent data-loss bug). The "still
  /// cited?" check and the delete run inside a single transaction so no
  /// dance can acquire a citation between the check and the delete (no
  /// check-then-act race). Mirrors `VenueRepository.delete` /
  /// `ChoreographerRepository.delete`.
  ///
  /// Tombstones by default (schema v25, issue #898); the guard is kept. See
  /// `ChoreographerRepository.delete` for [permanent].
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      final stillUsed = await (_db.select(
        _db.danceSources,
      )..where((t) => t.sourceId.equals(id))).get();
      if (stillUsed.isNotEmpty) {
        throw StateError(
          'cannot delete published source "$id": still cited by '
          '${stillUsed.length} dance(s)',
        );
      }

      if (permanent) {
        await (_db.delete(
          _db.publishedSources,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: _db.publishedSources,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  Future<void> restore(String id, {required DateTime at}) =>
      stampExistenceTransition(
        _db,
        table: _db.publishedSources,
        keyColumn: 'id',
        key: id,
        at: at,
        deleted: false,
      );

  Future<void> hardDelete(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id, permanent: true);
    }
  }

  PublishedSource _toModel(PublishedSourceRow row) => PublishedSource(
    id: row.id,
    title: row.title,
    author: row.author,
    year: row.year,
    url: row.url,
    notes: row.notes,
  );
}
