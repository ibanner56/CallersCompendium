import 'package:drift/drift.dart';

import '../../model/published_source.dart';
import '../database.dart';

/// CRUD for [PublishedSource] rows — the reusable bibliographic entity many
/// dances cite. Mirrors `ChoreographerRepository`: editing a source's metadata
/// happens in one place and a delete is guarded while the source is still
/// referenced by any dance citation.
class PublishedSourceRepository {
  PublishedSourceRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(PublishedSource s) => _db
      .into(_db.publishedSources)
      .insertOnConflictUpdate(
        PublishedSourcesCompanion.insert(
          id: s.id,
          title: s.title,
          author: Value(s.author),
          year: Value(s.year),
          url: Value(s.url),
          notes: Value(s.notes),
        ),
      );

  Future<PublishedSource?> getById(String id) async {
    final row = await (_db.select(
      _db.publishedSources,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<PublishedSource>> listAll() async {
    final rows =
        await (_db.select(_db.publishedSources)..orderBy([
              (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
            ]))
            .get();
    return rows.map(_toModel).toList();
  }

  /// Throws if [id] is still referenced by any `dance_sources` row — callers
  /// must remove the citing dances' citations first (deleting a source out
  /// from under credited dances would be a silent data-loss bug). The "still
  /// cited?" check and the delete run inside a single transaction so no
  /// dance can acquire a citation between the check and the delete (no
  /// check-then-act race). Mirrors `VenueRepository.delete` /
  /// `ChoreographerRepository.delete`.
  Future<void> delete(String id) => _db.transaction(() async {
    final stillUsed = await (_db.select(
      _db.danceSources,
    )..where((t) => t.sourceId.equals(id))).get();
    if (stillUsed.isNotEmpty) {
      throw StateError(
        'cannot delete published source "$id": still cited by '
        '${stillUsed.length} dance(s)',
      );
    }
    await (_db.delete(
      _db.publishedSources,
    )..where((t) => t.id.equals(id))).go();
  });

  PublishedSource _toModel(PublishedSourceRow row) => PublishedSource(
    id: row.id,
    title: row.title,
    author: row.author,
    year: row.year,
    url: row.url,
    notes: row.notes,
  );
}
