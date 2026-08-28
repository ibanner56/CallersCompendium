import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/enums.dart';
import '../../model/provenance.dart';
import '../../model/venue.dart';
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';

/// CRUD for [Venue] rows — the reusable venue entity many programs are held at.
/// Mirrors `PublishedSourceRepository`: editing a venue's address/contacts/
/// schedule happens in one place and a delete is guarded while the venue is
/// still referenced by any program's `venue_id`.
///
/// Venues are **soft-deleted** as of schema v25 (issue #898). They carry no
/// UNIQUE natural key (two halls may share a name), so an upsert can only ever
/// land on the row sharing its id.
@immutable
final class LiveVenueIds {
  LiveVenueIds._(Iterable<String> ids) : _ids = Set.unmodifiable(ids);

  /// The empty live-id snapshot, used when a bulk write has no venue links.
  static final empty = LiveVenueIds._(const <String>[]);

  final Set<String> _ids;

  bool contains(String id) => _ids.contains(id);
}

class VenueRepository {
  VenueRepository(this._db);

  final CompendiumDatabase _db;

  static String? _normalize(String? value) =>
      value == null ? null : normalizeShareableText(value);

  Future<void> upsert(Venue v, {DateTime? at}) {
    final now = resolveStamp(at);
    return _db.transaction(() async {
      await _db
          .into(_db.venues)
          .insertOnConflictUpdate(
            VenuesCompanion.insert(
              id: v.id,
              name: normalizeShareableText(v.name),
              address1: Value(v.address1),
              address2: Value(v.address2),
              city: Value(v.city),
              stateProv: Value(v.stateProv),
              country: Value(v.country),
              postalCode: Value(v.postalCode),
              plus4: Value(v.plus4),
              website: Value(_normalize(v.website)),
              sponsor: Value(_normalize(v.sponsor)),
              eventName: Value(_normalize(v.eventName)),
              time: Value(_normalize(v.time)),
              genericSchedule: Value(_normalize(v.genericSchedule)),
              price: Value(_normalize(v.price)),
              notes: Value(_normalize(v.notes)),
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
        table: _db.venues,
        keyColumn: 'id',
        key: v.id,
        at: now,
      );
      // Provenance is a single dependent row keyed on the venue id: delete
      // then (re)insert so an update refreshes it and a venue that lost its
      // provenance drops the row. Mirrors ProgramRepository's provenance
      // handling.
      await (_db.delete(
        _db.venueProvenance,
      )..where((t) => t.venueId.equals(v.id))).go();
      final prov = v.provenance;
      if (prov != null) {
        assertUtc(prov.importedAt, 'venue.provenance.importedAt');
        await _db
            .into(_db.venueProvenance)
            .insert(
              VenueProvenanceCompanion.insert(
                venueId: v.id,
                source: prov.source,
                externalId: Value(
                  prov.externalId == null
                      ? null
                      : normalizeShareableText(prov.externalId!),
                ),
                importedAt: prov.importedAt,
                permission: Value(prov.permission),
                license: Value(prov.license),
                sourceVersion: Value(prov.sourceVersion),
              ),
            );
      }
    });
  }

  Future<Venue?> getById(String id) async {
    final row = await (_db.select(
      _db.venues,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    final prov = await _provenanceFor(id);
    return _toModel(row, prov);
  }

  Future<List<Venue>> listAll() async {
    final rows =
        await (_db.select(_db.venues)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(expression: t.name.collate(Collate.noCase)),
              ]))
            .get();
    final ids = [for (final r in rows) r.id];
    final provByVenue = await _provenanceForMany(ids);
    return [for (final row in rows) _toModel(row, provByVenue[row.id])];
  }

  /// [listAll] as a live stream: the current catalogue immediately, then again
  /// after every write that changes it (issue #768).
  ///
  /// ## Why the query builder here, and not a sentinel `customSelect`
  ///
  /// `ProgramRepository.watchAll` states its `readsFrom` set by hand because
  /// `ProgramRepository.listAll` is not one query — it selects, then fans out
  /// in Dart to child tables that drift never sees, so an inferred set would be
  /// silently too narrow.
  ///
  /// [listAll] above has no such fan-out: one `select(venues)`, then `map` over
  /// rows already in memory. drift therefore infers exactly `{venues}`, which
  /// is exactly right, and hand-writing it would add a second place for the
  /// same fact to live. The distinction is worth stating because the two shapes
  /// are indistinguishable at the call site — both are `listAll()`.
  ///
  /// **What would invalidate this:** giving [listAll] any per-row read — a
  /// venue's programs, say. The inferred set would not grow to match, and this
  /// stream would go stale for that data with nothing to indicate it. Add the
  /// table to an explicit `readsFrom` at that point, as the program list does.
  ///
  /// **Provenance:** this stream does not include [Venue.provenance]. Venue
  /// provenance never changes after an import (it is stamped once on mint), so
  /// staleness is not a concern in practice. Callers that need provenance use
  /// [listAll] or [getById] instead.
  Stream<List<Venue>> watchAll() =>
      (_db.select(_db.venues)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.name.collate(Collate.noCase)),
            ]))
          .watch()
          .map((rows) => rows.map((r) => _toModel(r, null)).toList());

  /// Loads just the set of existing venue ids in a **single** query (only the
  /// `id` column is read — no full-model mapping). This is the batch-safe input
  /// for bulk writers (archive restore/import) that must validate many
  /// programs' `venueId` against existing venues without an N+1 of per-program
  /// existence SELECTs — see [ProgramRepository.create]'s `knownVenueIds`.
  ///
  /// Tombstoned venues are excluded: a soft-deleted venue is not one a program
  /// may newly link to, and letting one through here would re-admit exactly the
  /// dangling reference the write-time check exists to prevent.
  Future<LiveVenueIds> listAllIds() async {
    final query = _db.selectOnly(_db.venues)
      ..addColumns([_db.venues.id])
      ..where(_db.venues.deletedAt.isNull());
    final rows = await query.get();
    return LiveVenueIds._({for (final r in rows) r.read(_db.venues.id)!});
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
        table: _db.venues,
        keyColumn: 'id',
        key: id,
        at: now,
        deleted: true,
      );
    });
  }

  /// Restores a tombstoned venue without changing its fields. Exact archive
  /// re-imports use this when the provenance row survives a prior deletion.
  Future<void> restore(String id, {DateTime? at}) {
    final now = resolveStamp(at);
    return stampExistenceTransition(
      _db,
      table: _db.venues,
      keyColumn: 'id',
      key: id,
      at: now,
      deleted: false,
    );
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

  Venue _toModel(VenueRow row, Provenance? provenance) => Venue(
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
    provenance: provenance,
  );

  Future<Provenance?> _provenanceFor(String venueId) async {
    final row = await (_db.select(
      _db.venueProvenance,
    )..where((t) => t.venueId.equals(venueId))).getSingleOrNull();
    return row == null ? null : _provenanceFromRow(row);
  }

  /// Batched sibling of [_provenanceFor]: resolves provenance for many venues
  /// via `venue_provenance` queries keyed by `venueId IN (...)`, chunking [ids]
  /// to stay within SQLite's bound-variable limit (see [_chunkIds]). Venues
  /// without a provenance row are absent from the map. Used by [listAll] to
  /// avoid the per-row [_provenanceFor] N+1 fan-out.
  Future<Map<String, Provenance>> _provenanceForMany(
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final result = <String, Provenance>{};
    for (final chunk in _chunkIds(idList)) {
      final rows = await (_db.select(
        _db.venueProvenance,
      )..where((t) => t.venueId.isIn(chunk))).get();
      for (final row in rows) {
        result[row.venueId] = _provenanceFromRow(row);
      }
    }
    return result;
  }

  Provenance _provenanceFromRow(VenueProvenanceRow row) {
    return Provenance(
      source: row.source,
      externalId: row.externalId,
      importedAt: asUtc(row.importedAt),
      permission: row.permission,
      license: row.license,
      sourceVersion: row.sourceVersion,
    );
  }

  /// Maps each live venue's provenance external id → its venue id, for a single
  /// [source]. Only rows whose `externalId` is non-null are included
  /// (null-provenance venues never dedupe). Tombstoned venues are excluded so an
  /// archive re-import cannot repoint a program at a deleted parent. Used by
  /// [CompendiumArchiveImporter] to detect a re-import: a venue whose
  /// `(source, externalId)` key is already present repoints incoming programs at
  /// the existing record instead of minting a duplicate. Mirrors
  /// [ProgramRepository.externalIdToProgramId].
  Future<Map<String, String>> externalIdToVenueId(
    ProvenanceSource source,
  ) async {
    final rows =
        await (_db.select(_db.venueProvenance).join([
              innerJoin(
                _db.venues,
                _db.venues.id.equalsExp(_db.venueProvenance.venueId),
              ),
            ])..where(
              _db.venueProvenance.source.equalsValue(source) &
                  _db.venues.deletedAt.isNull(),
            ))
            .get();
    final map = <String, String>{};
    for (final result in rows) {
      final row = result.readTable(_db.venueProvenance);
      final ext = row.externalId;
      if (ext != null && ext.isNotEmpty) map[ext] = row.venueId;
    }
    return map;
  }

  /// Maps tombstoned venues' provenance external ids → venue ids for a single
  /// [source]. This is separate from [externalIdToVenueId] so normal dedupe
  /// never treats a deleted venue as live; an exact re-import can instead
  /// restore the same row without colliding with the provenance unique key.
  Future<Map<String, String>> deletedExternalIdToVenueId(
    ProvenanceSource source,
  ) async {
    final rows =
        await (_db.select(_db.venueProvenance).join([
              innerJoin(
                _db.venues,
                _db.venues.id.equalsExp(_db.venueProvenance.venueId),
              ),
            ])..where(
              _db.venueProvenance.source.equalsValue(source) &
                  _db.venues.deletedAt.isNotNull(),
            ))
            .get();
    final map = <String, String>{};
    for (final result in rows) {
      final row = result.readTable(_db.venueProvenance);
      final ext = row.externalId;
      if (ext != null && ext.isNotEmpty) map[ext] = row.venueId;
    }
    return map;
  }
}
