import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/program.dart';
import '../database.dart';
import '../utc_datetime.dart';

/// One entry in a dance's calling history: a program that includes the dance
/// (a slot referencing it), produced by
/// [ProgramRepository.callingHistoryForDance].
///
/// Calling history is a **derived query** over [ProgramSlot]s, never stored on
/// the dance (see `docs/design/domain-model.md`). By default a program appears
/// as soon as it *contains* the dance — [performedAt] may be null (the "mark
/// performed" write path is a separate feature; see ROADMAP G.2). There is one
/// record per matching slot, so a dance appearing more than once in the same
/// program yields multiple records.
@immutable
class DanceCallingRecord {
  const DanceCallingRecord({
    required this.slotId,
    required this.programId,
    required this.programTitle,
    required this.programUpdatedAt,
    this.performedAt,
    this.eventDate,
    this.venue,
  });

  /// The slot that references the dance. Unique per record — used as a stable
  /// key so two rows for the same program don't collide.
  final String slotId;

  /// The program the dance appears in.
  final String programId;
  final String programTitle;

  /// The program's last-updated timestamp (always present). UTC. Used as the
  /// final ordering/display fallback when neither [performedAt] nor [eventDate]
  /// is set.
  final DateTime programUpdatedAt;

  /// When the slot was actually called, if the "mark performed" path has
  /// stamped it — otherwise null. UTC.
  final DateTime? performedAt;

  /// The program's scheduled event date, if any. UTC.
  final DateTime? eventDate;

  /// The program's venue, if any.
  final String? venue;

  /// The date used for ordering and display: the actual performance time when
  /// set, else the program's scheduled event date, else its last-updated time.
  /// Always non-null so ordering never depends on [performedAt] being present.
  DateTime get effectiveDate => performedAt ?? eventDate ?? programUpdatedAt;

  @override
  bool operator ==(Object other) =>
      other is DanceCallingRecord &&
      other.slotId == slotId &&
      other.programId == programId &&
      other.programTitle == programTitle &&
      other.programUpdatedAt == programUpdatedAt &&
      other.performedAt == performedAt &&
      other.eventDate == eventDate &&
      other.venue == venue;

  @override
  int get hashCode => Object.hash(
    slotId,
    programId,
    programTitle,
    programUpdatedAt,
    performedAt,
    eventDate,
    venue,
  );
}

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
            band: Value(program.band),
            caller: Value(program.caller),
            dancerLevel: Value(program.dancerLevel),
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
              guestCaller: Value(slot.guestCaller),
              plannedMinutes: Value(slot.plannedMinutes),
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
            guestCaller: r.guestCaller,
            plannedMinutes: r.plannedMinutes,
            performedAt: asUtcOrNull(r.performedAt),
          ),
        )
        .toList();
  }

  /// Maps dance id → the most recent `performedAt` timestamp across every
  /// slot of every non-deleted program, for dances that have actually been
  /// called at least once. Feeds Collection's "last-called" sort (see
  /// `docs/design/ux.md` §1); dances absent from the map have never been
  /// called.
  Future<Map<String, DateTime>> lastCalledByDance() async {
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
    return {
      for (final row in rows)
        row.read<String>('dance_id'): asUtc(row.read<DateTime>('last_called')),
    };
  }

  /// The calling history for the dance identified by [danceId]: the programs
  /// that include the dance (a slot referencing it) on a non-deleted program,
  /// ordered most-recent first.
  ///
  /// By DEFAULT a program appears as soon as it *contains* the dance —
  /// regardless of whether the slot was marked performed ([performedAt] may be
  /// null). Pass [performedOnly] `true` to restrict the history to slots that
  /// were actually called (`performed_at IS NOT NULL`); this is the hook for
  /// the future "Require mark-performed for calling history" General setting
  /// (ROADMAP G.2, off by default).
  ///
  /// Calling history is a derived query, never stored (see
  /// `docs/design/domain-model.md`; `docs/design/ux.md` §2 / the dance-detail
  /// wireframe "History"). One record per matching slot, ordered by each
  /// record's effective date (performed_at, else event_date, else updated_at)
  /// descending — the ordering never depends on `performed_at` being present.
  /// Feeds the dance-detail "Calling history" section.
  Future<List<DanceCallingRecord>> callingHistoryForDance(
    String danceId, {
    bool performedOnly = false,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT program_slots.id AS slot_id, programs.id AS program_id, '
          'programs.title AS program_title, '
          'programs.event_date AS event_date, programs.venue AS venue, '
          'programs.updated_at AS updated_at, '
          'program_slots.performed_at AS performed_at '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id = ? '
          '${performedOnly ? 'AND program_slots.performed_at IS NOT NULL ' : ''}'
          'AND programs.deleted_at IS NULL '
          'ORDER BY COALESCE('
          'program_slots.performed_at, programs.event_date, programs.updated_at'
          ') DESC, programs.id',
          variables: [Variable<String>(danceId)],
        )
        .get();
    return [
      for (final row in rows)
        DanceCallingRecord(
          slotId: row.read<String>('slot_id'),
          programId: row.read<String>('program_id'),
          programTitle: row.read<String>('program_title'),
          programUpdatedAt: asUtc(row.read<DateTime>('updated_at')),
          performedAt: asUtcOrNull(row.read<DateTime?>('performed_at')),
          eventDate: asUtcOrNull(row.read<DateTime?>('event_date')),
          venue: row.read<String?>('venue'),
        ),
    ];
  }

  /// Duplicates the program identified by [id] under [newId] via
  /// [Program.duplicate] (fresh identity everywhere, draft status, performance
  /// history cleared) and persists it. [newSlotId] mints an id per copied slot.
  Future<Program> duplicate({
    required String id,
    required String newId,
    required String Function() newSlotId,
    required DateTime now,
    String? newTitle,
  }) async {
    assertUtc(now, 'now');
    final source = await getById(id, includeDeleted: true);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'no such program');
    }
    final copy = source.duplicate(
      newId: newId,
      newSlotId: newSlotId,
      now: now,
      newTitle: newTitle,
    );
    await create(copy);
    return copy;
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
    band: row.band,
    caller: row.caller,
    dancerLevel: row.dancerLevel,
    notes: row.notes,
    status: row.status,
    slots: slots,
    createdAt: asUtc(row.createdAt),
    updatedAt: asUtc(row.updatedAt),
    deletedAt: asUtcOrNull(row.deletedAt),
  );
}
