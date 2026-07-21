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

  /// Throws if [id] is still referenced by any `programs.venue_id` — callers
  /// must unlink (or delete) the referencing programs first, since deleting a
  /// venue out from under a linked program would orphan its reference. Mirrors
  /// the `PublishedSourceRepository` delete guard (adapted from the
  /// `dance_sources` join to the `programs.venue_id` column).
  Future<void> delete(String id) async {
    final stillUsed = await (_db.select(
      _db.programs,
    )..where((t) => t.venueId.equals(id))).get();
    if (stillUsed.isNotEmpty) {
      throw StateError(
        'cannot delete venue "$id": still referenced by '
        '${stillUsed.length} program(s)',
      );
    }
    await (_db.delete(_db.venues)..where((t) => t.id.equals(id))).go();
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
