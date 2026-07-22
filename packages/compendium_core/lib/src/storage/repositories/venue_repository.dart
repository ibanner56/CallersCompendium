import 'package:drift/drift.dart';

import '../../model/venue.dart';
import '../database.dart';

/// CRUD for [Venue] rows — the reusable venue entity many programs are held at.
/// Mirrors `PublishedSourceRepository`: editing a venue's address/contacts/
/// schedule happens in one place and a delete is guarded while the venue is
/// still referenced by any program's `venue_id`.
class VenueRepository {
  VenueRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> upsert(Venue v) => _db
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
        ),
      );

  Future<Venue?> getById(String id) async {
    final row = await (_db.select(
      _db.venues,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<Venue>> listAll() async {
    final rows =
        await (_db.select(_db.venues)..orderBy([
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
  Future<Set<String>> listAllIds() async {
    final query = _db.selectOnly(_db.venues)..addColumns([_db.venues.id]);
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
  Future<void> delete(String id) => _db.transaction(() async {
    // A venue is explicitly reusable across many programs, so read only a
    // scalar `COUNT(id)` for the guard rather than materializing every
    // referencing `ProgramRow` (all columns) just to count it — the cost stays
    // flat regardless of how large a popular venue's referencing history grows.
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
    await (_db.delete(_db.venues)..where((t) => t.id.equals(id))).go();
  });

  /// Unconditionally removes the venues [ids] in a single transaction, skipping
  /// the reference guard. Intended solely for reverting a just-committed import
  /// batch (see `CompendiumArchiveImporter.undo`), where the caller has already
  /// removed the programs that referenced these venues; an empty [ids] is a
  /// no-op. Ordinary deletes must go through [delete].
  Future<void> hardDelete(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(
      () => (_db.delete(_db.venues)..where((t) => t.id.isIn(list))).go(),
    );
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
