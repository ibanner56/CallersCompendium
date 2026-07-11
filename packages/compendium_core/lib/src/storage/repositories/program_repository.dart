import 'package:drift/drift.dart';

import '../../model/program.dart';
import '../database.dart';
import '../utc_datetime.dart';

/// CRUD for [Program]s and their [ProgramSlot]s.
///
/// Slots are always replaced wholesale on write (delete-then-reinsert inside
/// a transaction) rather than diffed — programs are small (a night's worth
/// of dances), so this stays simple and avoids partial-update bugs.
class ProgramRepository {
  ProgramRepository(this._db);

  final CompendiumDatabase _db;

  Future<void> create(Program program) => _upsert(program);

  Future<void> update(Program program) => _upsert(program);

  Future<void> _upsert(Program program) => _db.transaction(() async {
    assertUtc(program.createdAt, 'program.createdAt');
    assertUtc(program.updatedAt, 'program.updatedAt');
    assertUtcOrNull(program.deletedAt, 'program.deletedAt');
    assertUtcOrNull(program.eventDate, 'program.eventDate');
    for (final slot in program.slots) {
      assertUtcOrNull(slot.performedAt, 'slot.performedAt');
    }
    await _db
        .into(_db.programs)
        .insertOnConflictUpdate(
          ProgramsCompanion.insert(
            id: program.id,
            title: program.title,
            eventDate: Value(program.eventDate),
            venue: Value(program.venue),
            notes: Value(program.notes),
            status: program.status,
            createdAt: program.createdAt,
            updatedAt: program.updatedAt,
            deletedAt: Value(program.deletedAt),
          ),
        );
    await (_db.delete(
      _db.programSlots,
    )..where((t) => t.programId.equals(program.id))).go();
    for (final slot in program.slots) {
      await _db
          .into(_db.programSlots)
          .insert(
            ProgramSlotsCompanion.insert(
              id: slot.id,
              programId: program.id,
              position: slot.position,
              danceId: Value(slot.danceId),
              text_: Value(slot.text),
              isAlt: Value(slot.isAlt),
              performedAt: Value(slot.performedAt),
            ),
          );
    }
  });

  Future<Program?> getById(String id, {bool includeDeleted = false}) async {
    final row =
        await (_db.select(_db.programs)..where(
              (t) =>
                  t.id.equals(id) &
                  (includeDeleted
                      ? const Constant(true)
                      : t.deletedAt.isNull()),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toModel(row, await _slotsFor(id));
  }

  Future<List<Program>> listAll({bool includeDeleted = false}) async {
    final query = _db.select(_db.programs)
      ..orderBy([(t) => OrderingTerm(expression: t.title)]);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    final rows = await query.get();
    return [for (final row in rows) _toModel(row, await _slotsFor(row.id))];
  }

  Future<List<ProgramSlot>> _slotsFor(String programId) async {
    final rows =
        await (_db.select(_db.programSlots)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    return rows
        .map(
          (r) => ProgramSlot(
            id: r.id,
            position: r.position,
            danceId: r.danceId,
            text: r.text_,
            isAlt: r.isAlt,
            performedAt: asUtcOrNull(r.performedAt),
          ),
        )
        .toList();
  }

  Future<void> softDelete(String id, {required DateTime at}) {
    assertUtc(at, 'at');
    return (_db.update(_db.programs)..where((t) => t.id.equals(id))).write(
      ProgramsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
    );
  }

  Future<void> restore(String id, {required DateTime at}) {
    assertUtc(at, 'at');
    return (_db.update(_db.programs)..where((t) => t.id.equals(id))).write(
      ProgramsCompanion(deletedAt: const Value(null), updatedAt: Value(at)),
    );
  }

  /// Hard-deletes soft-deleted programs whose `deletedAt` is older than
  /// [retention] (default 30 days per `docs/design/storage.md`). Slots
  /// cascade automatically (FK).
  Future<int> purgeDeleted({
    required DateTime now,
    Duration retention = const Duration(days: 30),
  }) {
    assertUtc(now, 'now');
    final cutoff = now.subtract(retention);
    return (_db.delete(
      _db.programs,
    )..where((t) => t.deletedAt.isSmallerOrEqualValue(cutoff))).go();
  }

  Program _toModel(ProgramRow row, List<ProgramSlot> slots) => Program(
    id: row.id,
    title: row.title,
    eventDate: asUtcOrNull(row.eventDate),
    venue: row.venue,
    notes: row.notes,
    status: row.status,
    slots: slots,
    createdAt: asUtc(row.createdAt),
    updatedAt: asUtc(row.updatedAt),
    deletedAt: asUtcOrNull(row.deletedAt),
  );
}
