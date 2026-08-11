import 'package:drift/drift.dart';

import '../../model/venue.dart';
import '../database.dart';
import '../existence.dart';

/// CRUD for [Venue] rows — the reusable venue entity many programs are held at.
/// Mirrors `PublishedSourceRepository`: editing a venue's address/contacts/
/// schedule happens in one place and a delete is guarded while the venue is
/// still referenced by any program's `venue_id`.
///
/// Venues are **soft-deleted** as of schema v25 (issue #898). They carry no
/// UNIQUE natural key (two halls may share a name), so an upsert can only ever
/// land on the row sharing its id.
class VenueRepository {
  VenueRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(Venue v, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      await _db
          .into(_db.venues)
          .insertOnConflictUpdate(
            VenuesCompanion.insert(
              id: v.id,
              name: v.name,
              address1: Value(v.address1),
              address2: Value(v.address2),
              city: Value(v.city),
              stateProv: Value(v.stateProv),
              country: Value(v.country),
              postalCode: Value(v.postalCode),
              plus4: Value(v.plus4),
              website: Value(v.website),
              sponsor: Value(v.sponsor),
              eventName: Value(v.eventName),
              time: Value(v.time),
              genericSchedule: Value(v.genericSchedule),
              price: Value(v.price),
              notes: Value(v.notes),
              contact1Name: Value(v.contact1Name),
              contact1Phone: Value(v.contact1Phone),
              contact1Email: Value(v.contact1Email),
              contact2Name: Value(v.contact2Name),
              contact2Phone: Value(v.contact2Phone),
              contact2Email: Value(v.contact2Email),
              updatedAt: Value(now),
            ),
          );
      await applyUpsertExistence(
        _db,
        table: 'venues',
        keyColumn: 'id',
        key: v.id,
        at: now,
      );
    });
  }

  Future<Venue?> getById(String id) async {
    final row = await (_db.select(
      _db.venues,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Venue>> listAll() async {
    final rows =
        await (_db.select(_db.venues)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.name.collate(Collate.noCase)),
              ]))
            .get();
    return rows.map(_toModel).toList();
  }

  /// Loads just the set of existing venue ids in a **single** query (only the
  /// `id` column is read — no full-model mapping). This is the batch-safe input
  /// for bulk writers (archive restore/import) that must validate many
  /// programs' `venueId` against existing venues without an N+1 of per-program
  /// existence SELECTs — see [ProgramRepository.create]'s `knownVenueIds`.
  ///
  /// Tombstoned venues are excluded: a soft-deleted venue is not one a program
  /// may newly link to, and letting one through here would re-admit exactly the
  /// dangling reference the write-time check exists to prevent.
  Future<Set<String>> listAllIds() async {
    final query = _db.selectOnly(_db.venues)
      ..addColumns([_db.venues.id])
      ..where(_db.venues.deletedAt.isNull());
    final rows = await query.get();
    return {for (final r in rows) r.read(_db.venues.id)!};
  }

  /// Deletes the venue [id], guarding — **atomically** — against deleting a
  /// venue any program still links to. The "is any program referencing this
  /// venue?" check and the delete run inside a single transaction so no program
  /// can acquire a reference between the check and the delete (no check-then-act
  /// race). Throws a [StateError] if still referenced: callers must unlink (or
  /// delete) the referencing programs first, since deleting a venue out from
  /// under a linked program would orphan its reference. Mirrors the
  /// `PublishedSourceRepository` delete guard (adapted from the `dance_sources`
  /// join to the `programs.venue_id` column), tightened to be transactional
  /// because `venueId` is an app-layer-enforced soft reference, not a DB FK.
  ///
  /// Tombstones by default (schema v25, issue #898); the guard is kept. See
  /// `ChoreographerRepository.delete` for [permanent], which the archive and
  /// `.USR` import rollbacks pass.
  ///
  /// The reference count deliberately does **not** filter
  /// `programs.deleted_at`: a soft-deleted program can still be restored, and
  /// restoring one whose venue had been removed in the meantime would orphan
  /// its `venueId`. That predates this change and is unaffected by it.
  Future<void> delete(String id, {DateTime? at, bool permanent = false}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      // A venue is explicitly reusable across many programs, so read only a
      // scalar `COUNT(id)` for the guard rather than materializing every
      // referencing `ProgramRow` (all columns) just to count it. The
      // `programs_venue_id` index (see `venueLookupIndexSql`) backs this WHERE
      // so the count restricts to matching references instead of scanning every
      // program row, keeping the guard cheap as a popular venue's history grows.
      final referencingCount = _db.programs.id.count();
      final count =
          await (_db.selectOnly(_db.programs)
                ..addColumns([referencingCount])
                ..where(_db.programs.venueId.equals(id)))
              .map((row) => row.read(referencingCount) ?? 0)
              .getSingle();
      if (count > 0) {
        throw StateError(
          'cannot delete venue "$id": still referenced by $count program(s)',
        );
      }
      if (permanent) {
        await (_db.delete(_db.venues)..where((t) => t.id.equals(id))).go();
        return;
      }
      await stampExistenceTransition(
        _db,
        table: 'venues',
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  /// Unconditionally removes the venues [ids] in a single transaction, skipping
  /// the reference guard. Intended solely for reverting a just-committed import
  /// batch (see `CompendiumArchiveImporter.undo`), where the caller has already
  /// removed the programs that referenced these venues; an empty [ids] is a
  /// no-op. Ordinary deletes must go through [delete].
  ///
  /// Stays a **hard** delete after the schema-v25 soft-delete conversion
  /// (issue #898), exactly as `DanceRepository.hardDelete` and
  /// `ProgramRepository.hardDelete` do on kinds that have been soft-deletable
  /// for far longer. A rollback erases an import that is being treated as never
  /// having happened, so a tombstone would advertise the deletion of an entity
  /// no other device ever saw.
  Future<void> hardDelete(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(() async {
      for (final chunk in _chunkIds(list)) {
        await (_db.delete(_db.venues)..where((t) => t.id.isIn(chunk))).go();
      }
    });
  }

  /// Max ids per `IN (…)` clause. Kept well under SQLite's default
  /// `SQLITE_MAX_VARIABLE_NUMBER` (999 on older builds) so a full-collection
  /// delete stays correct no matter how large the library grows. Mirrors
  /// `DanceRepository`'s `_idChunkSize`.
  static const int _idChunkSize = 500;

  Iterable<List<String>> _chunkIds(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final end = i + _idChunkSize;
      yield ids.sublist(i, end > ids.length ? ids.length : end);
    }
  }

  Venue _toModel(VenueRow row) => Venue(
    id: row.id,
    name: row.name,
    address1: row.address1,
    address2: row.address2,
    city: row.city,
    stateProv: row.stateProv,
    country: row.country,
    postalCode: row.postalCode,
    plus4: row.plus4,
    website: row.website,
    sponsor: row.sponsor,
    eventName: row.eventName,
    time: row.time,
    genericSchedule: row.genericSchedule,
    price: row.price,
    notes: row.notes,
    contact1Name: row.contact1Name,
    contact1Phone: row.contact1Phone,
    contact1Email: row.contact1Email,
    contact2Name: row.contact2Name,
    contact2Phone: row.contact2Phone,
    contact2Email: row.contact2Email,
  );
}
