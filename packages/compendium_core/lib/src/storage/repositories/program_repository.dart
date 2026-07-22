import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../analysis/half_calling_stats.dart';
import '../../model/enums.dart';
import '../../model/program.dart';
import '../../model/provenance.dart' as model;
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

/// How many times a dance has been called, aggregated across every non-deleted
/// program, produced by [ProgramRepository.countByDance].
///
/// Two tallies are surfaced so a caller can honor the "Require mark-performed
/// for calling history" setting (ROADMAP G.2) the same way the dance-detail
/// calling history does — WITHOUT a second query:
/// * [all] counts every occurrence (one per slot referencing the dance; a dance
///   appearing twice in one program counts twice), mirroring the detail
///   history's DEFAULT (a program appears as soon as it contains the dance).
/// * [performed] counts only occurrences whose slot was marked performed
///   (`performed_at IS NOT NULL`), mirroring the history's `performedOnly` mode.
///
/// Always `performed <= all`. A dance that has never been called is simply
/// absent from [countByDance]'s map rather than mapped to a zero record.
@immutable
class DanceCallCounts {
  const DanceCallCounts({required this.all, required this.performed});

  /// Every occurrence of the dance (one per matching slot), regardless of
  /// whether the slot was marked performed.
  final int all;

  /// Occurrences whose slot was marked performed (`performed_at` set).
  final int performed;

  /// The tally that matches the active calling-history setting: [performed]
  /// when mark-performed is required, otherwise [all]. Mirrors
  /// `ProgramRepository.callingHistoryForDance`'s `performedOnly` flag so the
  /// card's count and the detail history never disagree.
  int countFor(bool performedOnly) => performedOnly ? performed : all;

  @override
  bool operator ==(Object other) =>
      other is DanceCallCounts &&
      other.all == all &&
      other.performed == performed;

  @override
  int get hashCode => Object.hash(all, performed);

  @override
  String toString() => 'DanceCallCounts(all: $all, performed: $performed)';
}

/// CRUD for [Program]s and their [ProgramSlot]s.
///
/// Slots are always replaced wholesale on write (delete-then-reinsert inside
/// a transaction) rather than diffed — programs are small (a night's worth
/// of dances), so this stays simple and avoids partial-update bugs.
class ProgramRepository {
  ProgramRepository(this._db);

  final CompendiumDatabase _db;

  /// Persists a new program. Pass [knownVenueIds] on the bulk restore/import
  /// paths to validate a non-null `venueId` against a preloaded set instead of
  /// a per-row SELECT (keeps persisting N programs O(1) in venue queries); see
  /// [_upsert].
  Future<void> create(Program program, {Set<String>? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  /// Updates an existing program. See [create] for [knownVenueIds].
  Future<void> update(Program program, {Set<String>? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  Future<void> _upsert(
    Program program, {
    Set<String>? knownVenueIds,
  }) => _db.transaction(() async {
    assertUtc(program.createdAt, 'program.createdAt');
    assertUtc(program.updatedAt, 'program.updatedAt');
    assertUtcOrNull(program.deletedAt, 'program.deletedAt');
    assertUtcOrNull(program.eventDate, 'program.eventDate');
    for (final slot in program.slots) {
      assertUtcOrNull(slot.performedAt, 'slot.performedAt');
    }
    // `venueId` is a soft reference (no DB foreign key — see [Programs.venueId]),
    // so referential integrity is enforced here at the app layer instead: a
    // non-null `venueId` must point at an existing venue. For a single write
    // (the [knownVenueIds] set is null) this is checked with a SELECT *inside*
    // this transaction, so the reference cannot become dangling between the
    // check and the write. Bulk callers (ArchiveRestorer, CompendiumArchive
    // importer) instead pass a set of venue ids preloaded once and always
    // resolve-or-null a dangling `venueId` *before* calling the repo — so a
    // bundle referencing an absent venue never reaches the throw below, and
    // persisting N programs stays O(1) in venue queries. Either way the
    // integrity guarantee is identical: an unknown `venueId` throws.
    final venueId = program.venueId;
    if (venueId != null) {
      final venueExists = knownVenueIds != null
          ? knownVenueIds.contains(venueId)
          : await (_db.select(_db.venues)
                      ..where((t) => t.id.equals(venueId))
                      ..limit(1))
                    .getSingleOrNull() !=
                null;
      if (!venueExists) {
        throw StateError(
          'cannot save program "${program.id}": venueId "$venueId" '
          'references a venue that does not exist',
        );
      }
    }
    // Auto-stamp performed slots on a status transition to `performed`
    // (issue #356): a program's *status* being performed and its per-slot
    // calling history should agree. We only stamp on the transition — reading
    // the previously-stored status — so a slot the user manually cleared while
    // the program is already performed is NOT re-stamped, and reverting away
    // from performed never un-stamps (history is preserved). Idempotent and
    // dance-linked-only logic lives in [Program.stampDanceSlotsPerformed]. The
    // stamp uses the program's eventDate when set, else its updatedAt (the
    // save's "now"), keeping the timestamp deterministic and validated.
    if (program.status == ProgramStatus.performed) {
      final priorRow = await (_db.select(
        _db.programs,
      )..where((t) => t.id.equals(program.id))).getSingleOrNull();
      if (priorRow?.status != ProgramStatus.performed) {
        program = program.stampDanceSlotsPerformed(fallback: program.updatedAt);
      }
    }
    await _db
        .into(_db.programs)
        .insertOnConflictUpdate(
          ProgramsCompanion.insert(
            id: program.id,
            title: program.title,
            eventDate: Value(program.eventDate),
            venue: Value(program.venue),
            venueId: Value(program.venueId),
            band: Value(program.band),
            caller: Value(program.caller),
            dancerLevel: Value(program.dancerLevel),
            notes: Value(program.notes),
            status: program.status,
            hideAlternates: Value(program.hideAlternates),
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
    // Provenance is a single dependent row keyed on the program id: delete then
    // (re)insert so an update refreshes it and a program that lost its
    // provenance drops the row. Mirrors DanceRepository's provenance handling.
    await (_db.delete(
      _db.programProvenance,
    )..where((t) => t.programId.equals(program.id))).go();
    final prov = program.provenance;
    if (prov != null) {
      assertUtc(prov.importedAt, 'program.provenance.importedAt');
      await _db
          .into(_db.programProvenance)
          .insert(
            ProgramProvenanceCompanion.insert(
              programId: program.id,
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
    final slots = _slotsFor(id);
    final provenance = _provenanceFor(id);
    return _toModel(row, await slots, await provenance);
  }

  Future<List<Program>> listAll({bool includeDeleted = false}) async {
    final query = _db.select(_db.programs)
      ..orderBy([(t) => OrderingTerm(expression: t.title)]);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    final rows = await query.get();
    final ids = [for (final r in rows) r.id];
    final slotsByProgram = await _slotsForMany(ids);
    final provByProgram = await _provenanceForMany(ids);
    return [
      for (final row in rows)
        _toModel(
          row,
          slotsByProgram[row.id] ?? const [],
          provByProgram[row.id],
        ),
    ];
  }

  /// Lightweight `(id, title)` listing that reads only the two columns it needs
  /// — avoiding the per-row [_slotsFor] child-query fan-out that [listAll]
  /// performs. Ordered by title then id; soft-deleted programs are excluded
  /// unless [includeDeleted] is set. Used by callers that only need to resolve
  /// or scan program titles (e.g. the command palette). Mirrors
  /// `DanceRepository.listIdsAndTitles`.
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) async {
    final query = _db.selectOnly(_db.programs)
      ..addColumns([_db.programs.id, _db.programs.title])
      ..orderBy([
        OrderingTerm(expression: _db.programs.title),
        OrderingTerm(expression: _db.programs.id),
      ]);
    if (!includeDeleted) {
      query.where(_db.programs.deletedAt.isNull());
    }
    final rows = await query.get();
    return [
      for (final row in rows)
        (id: row.read(_db.programs.id)!, title: row.read(_db.programs.title)!),
    ];
  }

  Future<List<ProgramSlot>> _slotsFor(String programId) async {
    final rows =
        await (_db.select(_db.programSlots)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.position)]))
            .get();
    return rows.map(_slotFromRow).toList();
  }

  /// Batched sibling of [_slotsFor]: loads the slots for many programs in a
  /// SINGLE `program_slots` query keyed by `programId IN (...)`, returning a
  /// `programId → slots` map with each program's slots in position order.
  /// Programs without slots are simply absent from the map. Used by [listAll]
  /// to avoid the per-row `_slotsFor` N+1 fan-out. Mirrors [_provenanceForMany].
  Future<Map<String, List<ProgramSlot>>> _slotsForMany(
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    // Order by programId then position so the in-memory grouping preserves
    // each program's position order (rows for a program arrive contiguously
    // and already sorted).
    final rows =
        await (_db.select(_db.programSlots)
              ..where((t) => t.programId.isIn(idList))
              ..orderBy([
                (t) => OrderingTerm(expression: t.programId),
                (t) => OrderingTerm(expression: t.position),
              ]))
            .get();
    final byProgram = <String, List<ProgramSlot>>{};
    for (final row in rows) {
      (byProgram[row.programId] ??= <ProgramSlot>[]).add(_slotFromRow(row));
    }
    return byProgram;
  }

  ProgramSlot _slotFromRow(ProgramSlotRow r) => ProgramSlot(
    id: r.id,
    position: r.position,
    danceId: r.danceId,
    text: r.text_,
    isAlt: r.isAlt,
    guestCaller: r.guestCaller,
    plannedMinutes: r.plannedMinutes,
    performedAt: asUtcOrNull(r.performedAt),
  );

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

  /// Maps dance id → its [DanceCallCounts] across every slot of every
  /// non-deleted program, for dances that have been called at least once
  /// (dances absent from the map have zero calls). One grouped query — the
  /// bulk sibling of [lastCalledByDance] — so the Collection list can render a
  /// per-dance "called ×N" count without an N+1 per-row fan-out.
  ///
  /// Surfaces BOTH the all-occurrences tally (`COUNT(*)`, one per matching
  /// slot) and the performed-only tally (`COUNT(performed_at)`, which counts
  /// only rows where `performed_at` is non-null) so a caller can honor the
  /// "Require mark-performed for calling history" setting (ROADMAP G.2) exactly
  /// as [callingHistoryForDance] does — see [DanceCallCounts.countFor]. The
  /// `deleted_at IS NULL` join filter matches both [lastCalledByDance] and
  /// [callingHistoryForDance].
  Future<Map<String, DanceCallCounts>> countByDance() async {
    final rows = await _db
        .customSelect(
          'SELECT program_slots.dance_id AS dance_id, '
          'COUNT(*) AS all_count, '
          'COUNT(program_slots.performed_at) AS performed_count '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id IS NOT NULL '
          'AND programs.deleted_at IS NULL '
          'GROUP BY program_slots.dance_id',
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('dance_id'): DanceCallCounts(
          all: row.read<int>('all_count'),
          performed: row.read<int>('performed_count'),
        ),
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

  /// First/second-half positional calling stats for the dance identified by
  /// [danceId] (issue #378), aggregated across every non-deleted program that
  /// includes it. A sibling of [callingHistoryForDance] — that method is left
  /// untouched — computed via the pure, Flutter-free [computeHalfCallingStats],
  /// which reuses the derived-half helper [Program.halvesForSlots].
  ///
  /// Bounded read: it loads full slot lists ONLY for the programs that actually
  /// contain the dance (found via one parameterized `dance_id = ?` query), not
  /// an all-programs scan; each program is a night's worth of slots.
  ///
  /// [performedOnly] mirrors [callingHistoryForDance]: when true only
  /// occurrences whose slot was marked performed are counted (ROADMAP G.2, off
  /// by default). Program structure — and therefore the derived halves and the
  /// first/last-in-half positions — is always taken from the full slot list,
  /// independent of [performedOnly].
  Future<HalfCallingStats> halfCallingStatsForDance(
    String danceId, {
    bool performedOnly = false,
  }) async {
    final idRows = await _db
        .customSelect(
          'SELECT DISTINCT program_slots.program_id AS program_id '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id = ? '
          'AND programs.deleted_at IS NULL',
          variables: [Variable<String>(danceId)],
        )
        .get();
    final programIds = [for (final r in idRows) r.read<String>('program_id')];
    if (programIds.isEmpty) return HalfCallingStats.empty;

    final byProgram = await _slotsForMany(programIds);
    return computeHalfCallingStats(
      danceId: danceId,
      programs: byProgram.values,
      performedOnly: performedOnly,
    );
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

  /// Hard-deletes the programs identified by [ids] outright (ignoring their
  /// soft-delete state), removing each program's slots via the
  /// `program_slots.program_id` cascade. Unknown ids are ignored; an empty
  /// [ids] is a no-op. Runs in a single transaction.
  ///
  /// Intended for reverting a just-committed import batch (import-session undo,
  /// e.g. [CallersCompanionUsrImporter.undo]); ordinary user deletes should go
  /// through [softDelete].
  Future<void> hardDelete(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(
      () => (_db.delete(_db.programs)..where((t) => t.id.isIn(list))).go(),
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

  Program _toModel(
    ProgramRow row,
    List<ProgramSlot> slots,
    model.Provenance? provenance,
  ) => Program(
    id: row.id,
    title: row.title,
    eventDate: asUtcOrNull(row.eventDate),
    venue: row.venue,
    venueId: row.venueId,
    band: row.band,
    caller: row.caller,
    dancerLevel: row.dancerLevel,
    notes: row.notes,
    status: row.status,
    hideAlternates: row.hideAlternates,
    slots: slots,
    createdAt: asUtc(row.createdAt),
    updatedAt: asUtc(row.updatedAt),
    deletedAt: asUtcOrNull(row.deletedAt),
    provenance: provenance,
  );

  Future<model.Provenance?> _provenanceFor(String programId) async {
    final row = await (_db.select(
      _db.programProvenance,
    )..where((t) => t.programId.equals(programId))).getSingleOrNull();
    if (row == null) return null;
    return _provenanceFromRow(row);
  }

  /// Batched sibling of [_provenanceFor]: resolves provenance for many programs
  /// in a SINGLE `program_provenance` query keyed by `programId IN (...)`,
  /// returning a `programId → Provenance` map. Programs without a provenance
  /// row are simply absent from the map. Used by [listAll] to avoid the per-row
  /// `_provenanceFor` N+1 fan-out. Mirrors the batched `IN (...)` lookup used by
  /// the dance derived-index rebuild.
  Future<Map<String, model.Provenance>> _provenanceForMany(
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final rows = await (_db.select(
      _db.programProvenance,
    )..where((t) => t.programId.isIn(idList))).get();
    return {for (final row in rows) row.programId: _provenanceFromRow(row)};
  }

  model.Provenance _provenanceFromRow(ProgramProvenanceRow row) {
    return model.Provenance(
      source: row.source,
      externalId: row.externalId,
      importedAt: asUtc(row.importedAt),
      permission: row.permission,
      license: row.license,
      rawPayload: row.rawPayload,
      sourceVersion: row.sourceVersion,
    );
  }

  /// Maps each existing program's provenance external id → its program id, for
  /// a single [source]. Only rows whose `externalId` is non-null are included
  /// (null-provenance programs never dedupe). Used by
  /// [CallersCompanionUsrImporter] to detect a re-import: a built CC program
  /// whose `(source, externalId)` key is already present updates that program
  /// in place instead of inserting a duplicate. Includes soft-deleted programs
  /// so a re-import re-targets (and can resurrect) a program the user deleted,
  /// rather than silently creating a second copy. Mirrors the dance
  /// deduplicator's exact `(source, externalId)` matching in `dedupe.dart`.
  Future<Map<String, String>> externalIdToProgramId(
    ProvenanceSource source,
  ) async {
    final rows = await (_db.select(
      _db.programProvenance,
    )..where((t) => t.source.equalsValue(source))).get();
    final map = <String, String>{};
    for (final row in rows) {
      final ext = row.externalId;
      if (ext != null && ext.isNotEmpty) map[ext] = row.programId;
    }
    return map;
  }
}
