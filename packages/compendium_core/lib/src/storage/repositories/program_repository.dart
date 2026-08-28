import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../analysis/half_calling_stats.dart';
import '../../model/enums.dart';
import '../../model/program.dart';
import '../../model/provenance.dart' as model;
import '../database.dart';
import '../existence.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';
import '../calling_history_scope.dart';
import 'venue_repository.dart';

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
    this.venueId,
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

  /// The program's venue free text, if any.
  final String? venue;

  /// The program's linked venue id (soft reference into `venues`), if any.
  /// Carried alongside the free-text [venue] so a caller can resolve the linked
  /// [Venue]'s display name against a preloaded venue map WITHOUT a per-program
  /// fetch — the app layer decides which to show per the venue-entity mode.
  final String? venueId;

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
      other.venue == venue &&
      other.venueId == venueId;

  @override
  int get hashCode => Object.hash(
    slotId,
    programId,
    programTitle,
    programUpdatedAt,
    performedAt,
    eventDate,
    venue,
    venueId,
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

/// A dance's calling history together with the half-calling stats derived from
/// the same rows, delivered as ONE value by
/// [ProgramRepository.watchCallingHistoryForDance].
///
/// The two travel together deliberately. Both are rendered by a single section
/// of the dance-detail screen, and both derive from the same two tables, so
/// emitting them separately would rebuild that section twice per write — the
/// over-firing failure issue #340 records — and could briefly render a history
/// list and a stats summary that disagree.
@immutable
class DanceCallingHistory {
  const DanceCallingHistory({required this.records, required this.halfStats});

  /// Empty history with empty stats — what a dance that has never been called
  /// resolves to.
  static const empty = DanceCallingHistory(
    records: [],
    halfStats: HalfCallingStats.empty,
  );

  /// Programs including the dance, most-recent first. Same value and ordering
  /// as [ProgramRepository.callingHistoryForDance].
  final List<DanceCallingRecord> records;

  /// Same value as [ProgramRepository.halfCallingStatsForDance] for the same
  /// arguments.
  final HalfCallingStats halfStats;
}

/// The program-derived per-dance tallies the Collection list renders, delivered
/// as ONE value by [ProgramRepository.watchProgramDerivedCounts].
///
/// [lastCalled] and [callCounts] are paired for the same reason
/// [DanceCallingHistory] pairs its two members: one write must produce one
/// rebuild of the list, not two (issue #340).
@immutable
class ProgramDerivedCounts {
  const ProgramDerivedCounts({
    required this.lastCalled,
    required this.callCounts,
  });

  /// Same value as [ProgramRepository.lastCalledByDance].
  final Map<String, DateTime> lastCalled;

  /// Same value as [ProgramRepository.countByDance].
  final Map<String, DanceCallCounts> callCounts;
}

/// CRUD for [Program]s and their [ProgramSlot]s.
///
/// Slots are always replaced wholesale on write (delete-then-reinsert inside
/// a transaction) rather than diffed — programs are small (a night's worth
/// of dances), so this stays simple and avoids partial-update bugs.
class ProgramRepository {
  ProgramRepository(this._db);

  final CompendiumDatabase _db;

  /// Normalizes an optional host-caller filter for the derived calling-history
  /// queries ([callingHistoryForDance], [countByDance], [lastCalledByDance],
  /// [halfCallingStatsForDance]). Returns the trimmed caller name, or `null`
  /// when [callerFilter] is `null` or blank — i.e. "track all callers", the
  /// historical behavior (issue #583). Empty/whitespace is treated as absent,
  /// matching how the default-caller setting itself treats empty as unset.
  static String? _normalizedCallerFilter(String? callerFilter) =>
      normalizeCallingHistoryCaller(callerFilter);

  /// SQL fragment restricting a derived history query to programs whose HOST
  /// caller matches [caller] (already normalized by [_normalizedCallerFilter]),
  /// or the empty string (no SQL appended) when [caller] is `null` — meaning no
  /// restriction. [caller] is always either `null` or a non-empty trimmed string;
  /// callers must use [_normalizedCallerFilter] to canonicalize before passing it
  /// here. Folds both sides with `LOWER(TRIM(...))` so every query site matches
  /// identically (trim + case-insensitive; issue #583) and the value is bound as
  /// a parameter (no injection). Programs with a `NULL` or blank caller are
  /// treated as the user's own and are included alongside explicitly matching
  /// programs (#850 supersedes the original #583 exclusion of unattributed
  /// programs).
  static String _callerClause(String? caller) =>
      callingHistoryCallerClause(caller, callerColumn: 'programs.caller');

  /// The bound variables for [_callerClause]: a single [Variable] when a filter
  /// is active, otherwise empty.
  static List<Variable<Object>> _callerVariables(String? caller) =>
      caller == null ? const [] : [Variable<String>(caller)];

  /// Persists a new program. Pass [knownVenueIds] on the bulk restore/import
  /// paths to validate a non-null `venueId` against a preloaded live snapshot
  /// instead of a per-row SELECT (keeps persisting N programs O(1) in venue
  /// queries); see [_upsert].
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  /// Updates an existing program. See [create] for [knownVenueIds].
  Future<void> update(Program program, {LiveVenueIds? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  Future<void> _upsert(
    Program program, {
    LiveVenueIds? knownVenueIds,
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
    // (the [knownVenueIds] snapshot is null) this is checked with a SELECT
    // *inside* this transaction, so the reference cannot become dangling
    // between the check and the write. Bulk callers instead pass a
    // liveness-aware snapshot preloaded once and always resolve-or-null a
    // dangling `venueId` before calling the repo — so a bundle referencing an
    // absent venue never reaches the throw below, and persisting N programs
    // stays O(1) in venue queries. Either way the integrity guarantee is
    // identical at the time of validation: an unknown or tombstoned `venueId`
    // throws. A preloaded snapshot is point-in-time; callers that need atomic
    // liveness must use the transactional single-write path.
    final venueId = program.venueId;
    if (venueId != null) {
      final venueExists = knownVenueIds != null
          ? knownVenueIds.contains(venueId)
          // `deleted_at IS NULL` since schema v25 (#898): a tombstoned venue
          // is not one a program may newly link to, and `venue_id` is a soft
          // reference with no FK, so nothing else would catch it.
          : await (_db.select(_db.venues)
                      ..where(
                        (t) => t.id.equals(venueId) & t.deletedAt.isNull(),
                      )
                      ..limit(1))
                    .getSingleOrNull() !=
                null;
      if (!venueExists) {
        throw StateError(
          'cannot save program "${program.id}": venueId "$venueId" '
          'references a venue that does not exist or is soft-deleted',
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
            title: normalizeShareableText(program.title),
            eventDate: Value(program.eventDate),
            venue: Value(
              program.venue == null
                  ? null
                  : normalizeShareableText(program.venue!),
            ),
            venueId: Value(program.venueId),
            band: Value(
              program.band == null
                  ? null
                  : normalizeShareableText(program.band!),
            ),
            caller: Value(
              program.caller == null
                  ? null
                  : normalizeShareableText(program.caller!),
            ),
            dancerLevel: Value(program.dancerLevel),
            notes: Value(normalizeShareableText(program.notes)),
            status: program.status,
            hideAlternates: Value(program.hideAlternates),
            createdAt: program.createdAt,
            updatedAt: program.updatedAt,
            deletedAt: Value(program.deletedAt),
          ),
        );
    await seedExistenceIfMissing(
      _db,
      table: _db.programs,
      keyColumn: 'id',
      key: program.id,
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
              text_: Value(
                slot.text == null ? null : normalizeShareableText(slot.text!),
              ),
              isAlt: Value(slot.isAlt),
              guestCaller: Value(
                slot.guestCaller == null
                    ? null
                    : normalizeShareableText(slot.guestCaller!),
              ),
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
              externalId: Value(
                prov.externalId == null
                    ? null
                    : normalizeShareableText(prov.externalId!),
              ),
              importedAt: prov.importedAt,
              permission: Value(
                prov.permission == null
                    ? null
                    : normalizeShareableText(prov.permission!),
              ),
              license: Value(
                prov.license == null
                    ? null
                    : normalizeShareableText(prov.license!),
              ),
              sourceVersion: Value(
                prov.sourceVersion == null
                    ? null
                    : normalizeShareableText(prov.sourceVersion!),
              ),
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

  /// Returns the soft-delete state for [id] without hydrating its slots or
  /// provenance. Returns `null` when no row exists.
  Future<bool?> isDeletedById(String id) async {
    final row =
        await (_db.selectOnly(_db.programs)
              ..addColumns([_db.programs.deletedAt])
              ..where(_db.programs.id.equals(id)))
            .getSingleOrNull();
    if (row == null) return null;
    return row.read(_db.programs.deletedAt) != null;
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

  /// The tables [listAll] reads, and therefore the `readsFrom` set
  /// [watchAll] declares. Justified per table:
  ///
  /// * `programs` — the row set itself: title, event date, venue text/link,
  ///   `deleted_at` for the soft-delete filter, and the title ordering.
  /// * `program_slots` — every program carries its slots
  ///   (`_slotsForMany`), so adding, removing, reordering or editing a slot
  ///   changes what [listAll] returns while touching no `programs` row.
  /// * `program_provenance` — the imported-from record folded in by
  ///   `_provenanceForMany`. Nothing in the Programs list renders it *today*,
  ///   but it is part of the [Program] value this stream hands out, so a
  ///   subscriber receiving a stale one is the same defect as a stale title.
  ///
  /// `venues` is deliberately NOT here, matching [_programDerivedTables]: the
  /// venue *label* is resolved app-side from the catalogue, so a venue rename
  /// does not re-emit and the label stays stale until something else reloads.
  /// That boundary is stated rather than fixed here because fixing it by
  /// widening this set would push a reload onto every subscriber on every
  /// venue edit, including subscribers that render no venue at all — curing
  /// staleness by causing issue #340. It needs a per-consumer read set, which
  /// is tracked separately (issue #944).
  Set<ResultSetImplementation<dynamic, dynamic>> get _programListTables => {
    _db.programs,
    _db.programSlots,
    _db.programProvenance,
  };

  /// [_programListTables] plus `venues`, for callers that render a venue label
  /// beside the list (issue #944).
  ///
  /// A separate getter rather than a mutated one: the caller states what it
  /// renders, and both sets stay readable as a list of tables with a reason
  /// each. See `CompendiumRepositories.watchCollectionSources` for the same
  /// choice made at the Collection seam, and for why widening the shared set
  /// instead would trade this staleness for issue #340's churn.
  Set<ResultSetImplementation<dynamic, dynamic>> get _programListWithVenues => {
    ..._programListTables,
    _db.venues,
  };

  /// [listAll] as a live stream: emits the current list immediately, then again
  /// after every write that could change it.
  ///
  /// ## Why a sentinel `customSelect` rather than watching the query
  ///
  /// The obvious implementation — `_db.select(_db.programs).watch()` — is
  /// wrong here, and wrong in the way this issue is about: it looks correct and
  /// fails silently.
  ///
  /// drift infers a builder query's read set from the query itself, so
  /// `select(programs).watch()` re-emits for `programs` and **nothing else**.
  /// But [listAll] is not one query: it selects programs and then fans out in
  /// Dart to `_slotsForMany` and `_provenanceForMany`. Those reads happen after
  /// drift has finished deciding what the stream depends on, so editing a slot
  /// would change the list's contents and re-emit nothing at all.
  ///
  /// That makes the inferred set more dangerous than a hand-written one, not
  /// less: a `customSelect` with no `readsFrom` is obviously unfinished,
  /// whereas the builder hands back a plausible answer to a narrower question
  /// than the caller asked. The sentinel makes the dependency explicit and puts
  /// it in one place — [_programListTables] — where each entry is justified.
  ///
  /// `program_repository_watch_test.dart` pins this: it asserts a slot-only
  /// edit re-emits, which is exactly the assertion the builder version fails.
  Stream<List<Program>> watchAll({
    bool includeDeleted = false,
    bool includeVenues = false,
  }) => _db
      .customSelect(
        // Distinct SQL per read set, deliberately: drift keys its stream cache
        // on (sql, variables) and ignores `readsFrom`, so two sentinels reading
        // `SELECT 1` with different declared tables become one stream and the
        // later subscriber inherits the earlier one's set. The full account is
        // on `CompendiumRepositories.watchCollectionSources`, whose sentinel
        // this one would otherwise collide with.
        includeVenues
            ? '/* program list +venues */ SELECT 1'
            : '/* program list */ SELECT 1',
        readsFrom: includeVenues ? _programListWithVenues : _programListTables,
      )
      .watch()
      .asyncMap((_) => listAll(includeDeleted: includeDeleted));

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
    return rows.map(_slotFromRow).whereType<ProgramSlot>().toList();
  }

  /// Batched sibling of [_slotsFor]: loads the slots for many programs via
  /// `program_slots` queries keyed by `programId IN (...)`, chunking [ids] to
  /// stay within SQLite's bound-variable limit (see [_chunkIds]) and merging
  /// the per-chunk results, returning a `programId → slots` map with each
  /// program's slots in position order. Programs without slots are simply
  /// absent from the map. Used by [listAll] to avoid the per-row `_slotsFor`
  /// N+1 fan-out. Mirrors [_provenanceForMany].
  Future<Map<String, List<ProgramSlot>>> _slotsForMany(
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final byProgram = <String, List<ProgramSlot>>{};
    // Order by programId then position so the in-memory grouping preserves
    // each program's position order (rows for a program arrive contiguously
    // and already sorted); chunking (see [_chunkIds]) doesn't disturb this
    // since each chunk's rows are grouped separately before being merged.
    for (final chunk in _chunkIds(idList)) {
      final rows =
          await (_db.select(_db.programSlots)
                ..where((t) => t.programId.isIn(chunk))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.programId),
                  (t) => OrderingTerm(expression: t.position),
                ]))
              .get();
      for (final row in rows) {
        final slot = _slotFromRow(row);
        if (slot == null) continue;
        (byProgram[row.programId] ??= <ProgramSlot>[]).add(slot);
      }
    }
    return byProgram;
  }

  /// Maps a slot row to a [ProgramSlot], returning `null` for a row the domain
  /// invariants reject rather than throwing. A pre-fix purge could leave a
  /// *dance-only* slot as `(danceId, text) = (null, null)` when the SET NULL FK
  /// fired (#429); tolerating it here means one corrupt row can't fail the whole
  /// Programs load (`listAll`/`getById`). [DanceRepository.purgeDeleted]
  /// tombstones such slots going forward, and the one-time repair in
  /// `CompendiumRepositories.ensureMigrated` clears any left by a prior build.
  ProgramSlot? _slotFromRow(ProgramSlotRow r) {
    try {
      return ProgramSlot(
        id: r.id,
        position: r.position,
        danceId: r.danceId,
        text: r.text_,
        isAlt: r.isAlt,
        guestCaller: r.guestCaller,
        plannedMinutes: r.plannedMinutes,
        performedAt: asUtcOrNull(r.performedAt),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// The tables every derived calling-history / counts query below reads, and
  /// therefore the `readsFrom` set their streams declare. Stated once so the
  /// queries cannot drift apart, and justified per table:
  ///
  /// * `program_slots` — the history rows themselves (`dance_id`,
  ///   `performed_at`), the `COUNT(*)` / `COUNT(performed_at)` tallies, and the
  ///   `MAX(performed_at)` last-called timestamp.
  /// * `programs` — joined by every one of these queries for
  ///   `deleted_at IS NULL` and the host-caller filter, and read directly by
  ///   [callingHistoryForDance] for `title` / `event_date` / `venue` /
  ///   `venue_id`. Renaming a program or soft-deleting one changes rendered
  ///   output while touching no slot row, so omitting this entry would leave a
  ///   subscribed view silently stale — see [watchCallingHistoryForDance].
  ///
  /// `venues` is deliberately NOT here: none of these queries reads it. The
  /// venue *label* shown against a history row is resolved app-side from the
  /// venue catalogue, so this set alone cannot re-emit on a venue rename —
  /// see [_programDerivedWithVenues], which callers rendering that label use
  /// instead (issue #944).
  Set<ResultSetImplementation<dynamic, dynamic>> get _programDerivedTables => {
    _db.programSlots,
    _db.programs,
  };

  /// [_programDerivedTables] plus `venues`, for callers that render a venue
  /// label beside the history (issue #944).
  ///
  /// **Watching the table is necessary and not sufficient here.** The label is
  /// resolved app-side from a cached catalogue, so the subscriber must also
  /// invalidate that cache on emit — a read set can make a consumer re-run, it
  /// cannot make the consumer re-read something it believes it already knows.
  /// `calling_history_section.dart` carries the other half.
  Set<ResultSetImplementation<dynamic, dynamic>>
  get _programDerivedWithVenues => {..._programDerivedTables, _db.venues};

  /// Maps dance id → the most recent `performedAt` timestamp across every
  /// slot of every non-deleted program, for dances that have actually been
  /// called at least once. Feeds Collection's "last-called" sort (see
  /// `docs/design/ux.md` §1); a dance absent from the map has never been
  /// called — or, when [callerFilter] is set, was never called in a program led
  /// by that host caller (see [callingHistoryForDance]; issue #583).
  Future<Map<String, DateTime>> lastCalledByDance({
    String? callerFilter,
  }) async => _programDerivedRows(
    _normalizedCallerFilter(callerFilter),
  ).get().then(_lastCalledFromRows);

  /// Maps dance id → its [DanceCallCounts] across every slot of every
  /// non-deleted program, for dances that have been called at least once (a
  /// dance absent from the map has zero calls — or, when [callerFilter] is set,
  /// zero calls in programs led by that host caller; issue #583). One grouped
  /// query — the bulk sibling of [lastCalledByDance] — so the Collection list
  /// can render a per-dance "called ×N" count without an N+1 per-row fan-out.
  ///
  /// Surfaces BOTH the all-occurrences tally (`COUNT(*)`, one per matching
  /// slot) and the performed-only tally (`COUNT(performed_at)`, which counts
  /// only rows where `performed_at` is non-null) so a caller can honor the
  /// "Require mark-performed for calling history" setting (ROADMAP G.2) exactly
  /// as [callingHistoryForDance] does — see [DanceCallCounts.countFor]. The
  /// `deleted_at IS NULL` join filter matches both [lastCalledByDance] and
  /// [callingHistoryForDance].
  Future<Map<String, DanceCallCounts>> countByDance({
    String? callerFilter,
  }) async => _programDerivedRows(
    _normalizedCallerFilter(callerFilter),
  ).get().then(_countsFromRows);

  /// The ONE query behind [lastCalledByDance], [countByDance] and
  /// [watchProgramDerivedCounts]. [caller] is already normalized.
  ///
  /// The two tallies and the last-called timestamp are aggregated together
  /// rather than by two queries, for two reasons. Sharing the query is what
  /// stops the one-shot reads and the stream from ever disagreeing about which
  /// slots count. And computing them in one statement is what makes each emit
  /// of [watchProgramDerivedCounts] an internally consistent snapshot: taking
  /// `MAX(performed_at)` in a second read could observe a write that landed
  /// after the counts were read, so one emit would carry tallies from one
  /// revision and a last-called stamp from the next.
  ///
  /// `MAX(performed_at)` ignores NULLs, so no `performed_at IS NOT NULL` filter
  /// is needed to reproduce [lastCalledByDance]'s result: a dance whose slots
  /// were all unperformed aggregates to NULL and [_lastCalledFromRows] simply
  /// omits it, which is what the narrower query did by excluding the rows.
  Selectable<QueryRow> _programDerivedRows(String? caller) => _db.customSelect(
    'SELECT program_slots.dance_id AS dance_id, '
    'COUNT(*) AS all_count, '
    'COUNT(program_slots.performed_at) AS performed_count, '
    'MAX(program_slots.performed_at) AS last_called '
    'FROM program_slots '
    'JOIN programs ON programs.id = program_slots.program_id '
    'WHERE program_slots.dance_id IS NOT NULL '
    'AND programs.deleted_at IS NULL '
    '${_callerClause(caller)}'
    'GROUP BY program_slots.dance_id',
    variables: _callerVariables(caller),
    readsFrom: _programDerivedTables,
  );

  /// Dances with at least one performed slot, mapped to their most recent one.
  /// A NULL `last_called` means every slot for that dance is unperformed, so
  /// the dance is absent from the map rather than present with a null value.
  Map<String, DateTime> _lastCalledFromRows(List<QueryRow> rows) => {
    for (final row in rows)
      if (row.read<DateTime?>('last_called') case final lastCalled?)
        row.read<String>('dance_id'): asUtc(lastCalled),
  };

  Map<String, DanceCallCounts> _countsFromRows(List<QueryRow> rows) => {
    for (final row in rows)
      row.read<String>('dance_id'): DanceCallCounts(
        all: row.read<int>('all_count'),
        performed: row.read<int>('performed_count'),
      ),
  };

  /// [countByDance] and [lastCalledByDance] in one read — the one-shot sibling
  /// of [watchProgramDerivedCounts], and what a caller that needs both should
  /// use.
  ///
  /// The two share a query (see [_programDerivedRows]), so asking for them
  /// separately runs it twice and, between the two runs, a write can land: the
  /// snapshot then pairs tallies from one revision with a last-called stamp
  /// from the next.
  Future<ProgramDerivedCounts> programDerivedCounts({
    String? callerFilter,
  }) async {
    final rows = await _programDerivedRows(
      _normalizedCallerFilter(callerFilter),
    ).get();
    return ProgramDerivedCounts(
      lastCalled: _lastCalledFromRows(rows),
      callCounts: _countsFromRows(rows),
    );
  }

  /// Reactive [countByDance] + [lastCalledByDance]: emits the current tallies
  /// immediately, then again whenever a write changes them.
  ///
  /// The Collection list renders both — the "called ×N" badge and the
  /// last-called sort/subtitle — so they are emitted as one
  /// [ProgramDerivedCounts] value, read from one query, so an emit can never
  /// pair tallies from one revision with a last-called stamp from another (see
  /// [_programDerivedRows]). [watchCallingHistoryForDance] states the pattern
  /// both streams follow.
  Stream<ProgramDerivedCounts> watchProgramDerivedCounts({
    String? callerFilter,
  }) => _programDerivedRows(_normalizedCallerFilter(callerFilter)).watch().map(
    (rows) => ProgramDerivedCounts(
      lastCalled: _lastCalledFromRows(rows),
      callCounts: _countsFromRows(rows),
    ),
  );

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
  /// Pass [callerFilter] (the default caller's name) to additionally restrict
  /// the history to programs whose HOST caller matches it — trim +
  /// case-insensitive — for the "scope calling history to my programs" setting
  /// (issue #583). `null`/blank means "track all callers" (unchanged). This
  /// gate is AND-combined with [performedOnly], never a replacement.
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
    String? callerFilter,
  }) async => _callingHistoryRows(
    danceId,
    performedOnly: performedOnly,
    caller: _normalizedCallerFilter(callerFilter),
  ).get().then(_callingHistoryFromRows);

  /// The query behind [callingHistoryForDance]. Shared by the one-shot read and
  /// [watchCallingHistoryForDance] so the two can never diverge; [caller] is
  /// already normalized.
  Selectable<QueryRow> _callingHistoryRows(
    String danceId, {
    required bool performedOnly,
    required String? caller,
    bool includeVenues = false,
  }) => _db.customSelect(
    // Marker first: this query has two read sets, and drift's stream cache
    // would otherwise treat both as one stream. See `watchCollectionSources`.
    '${includeVenues ? '/* +venues */ ' : ''}'
    'SELECT program_slots.id AS slot_id, programs.id AS program_id, '
    'programs.title AS program_title, '
    'programs.event_date AS event_date, programs.venue AS venue, '
    'programs.venue_id AS venue_id, '
    'programs.updated_at AS updated_at, '
    'program_slots.performed_at AS performed_at '
    'FROM program_slots '
    'JOIN programs ON programs.id = program_slots.program_id '
    'WHERE program_slots.dance_id = ? '
    '${performedOnly ? 'AND program_slots.performed_at IS NOT NULL ' : ''}'
    '${_callerClause(caller)}'
    'AND programs.deleted_at IS NULL '
    'ORDER BY COALESCE('
    'program_slots.performed_at, programs.event_date, programs.updated_at'
    ') DESC, programs.id',
    variables: [Variable<String>(danceId), ..._callerVariables(caller)],
    readsFrom: includeVenues
        ? _programDerivedWithVenues
        : _programDerivedTables,
  );

  List<DanceCallingRecord> _callingHistoryFromRows(List<QueryRow> rows) => [
    for (final row in rows)
      DanceCallingRecord(
        slotId: row.read<String>('slot_id'),
        programId: row.read<String>('program_id'),
        programTitle: row.read<String>('program_title'),
        programUpdatedAt: asUtc(row.read<DateTime>('updated_at')),
        performedAt: asUtcOrNull(row.read<DateTime?>('performed_at')),
        eventDate: asUtcOrNull(row.read<DateTime?>('event_date')),
        venue: row.read<String?>('venue'),
        venueId: row.read<String?>('venue_id'),
      ),
  ];

  /// Reactive [callingHistoryForDance] + [halfCallingStatsForDance]: emits the
  /// current calling history immediately, then again whenever a write changes
  /// it. Arguments mean exactly what they do on the one-shot methods.
  ///
  /// ---
  ///
  /// **This is the reference implementation for issue #768's reactive
  /// conversion.** Before it the app had no `.watch()` stream and no
  /// `StreamBuilder` at all: every view took a one-shot snapshot and relied on
  /// a mutation site remembering to broadcast a refresh, which is the defect
  /// class #768 catalogues seven instances of. The rules below are what the
  /// remaining conversions should follow; the app-side half is
  /// `app/lib/src/screens/dance_detail/calling_history_section.dart`.
  ///
  /// 1. **State `readsFrom` explicitly, and justify every table.** A
  ///    `customSelect` is opaque to drift, so a stream only re-emits for the
  ///    tables it is *told* the query reads. Omit one and the view looks wired
  ///    and silently never updates — the same bug as before, harder to spot.
  ///    This set is [_programDerivedTables], where each entry is justified;
  ///    `programs` is the load-bearing one, because a program rename or soft
  ///    delete changes what this history renders without touching a slot row.
  /// 2. **A derived value may ride an existing stream only when its own read
  ///    set is a subset of that stream's declared `readsFrom`.**
  ///    [halfCallingStatsForDance] qualifies: its program-id query reads
  ///    `{program_slots, programs}` and `_slotsForMany` reads `program_slots`,
  ///    both within the declared set, so it is folded in here via `asyncMap`
  ///    instead of being a second stream. The venue *label* rendered beside each
  ///    row does NOT qualify — it reads the `venues` catalogue, which is outside
  ///    the set — so it stays a one-shot read on the app side and a venue rename
  ///    does not refresh it. Stating that boundary is the point: an unstated one
  ///    is indistinguishable from the bug in rule 1.
  /// 3. **One stream per rendered section, not one per query.** Emitting the
  ///    history and its stats separately would rebuild the section twice per
  ///    write and could render two disagreeing halves. Over-firing is issue
  ///    #340's failure and pulls opposite to rule 1; both have to hold at once.
  ///    drift coalesces updates per transaction, and every write here goes
  ///    through one, so a write yields exactly one emit.
  /// 4. **Create the stream once, in `State`, never in `build()`.** Rebuilding
  ///    it per frame re-subscribes and re-queries; recreate it only when an
  ///    argument here changes (`performedOnly`, `callerFilter`).
  /// 5. **When a view's data is fully reactive, drop its refresh-scope listener
  ///    in the same change.** Leaving it attached means one write both re-emits
  ///    the stream and re-runs the imperative load — reintroducing #340 while
  ///    fixing staleness. The scopes themselves come out last, once nothing
  ///    subscribes; both app-side channels have now reached that condition, one
  ///    of them by being retired on it.
  Stream<DanceCallingHistory> watchCallingHistoryForDance(
    String danceId, {
    bool performedOnly = false,
    String? callerFilter,
  }) {
    final caller = _normalizedCallerFilter(callerFilter);
    return _callingHistoryRows(
      danceId,
      performedOnly: performedOnly,
      caller: caller,
      // The section renders a venue label per row, resolved app-side, so it
      // must re-emit when a venue changes (issue #944). The one-shot
      // `callingHistoryForDance` above does not opt in: it has no subscriber
      // to notify, and widening its declared set would state a dependency the
      // read does not have.
      includeVenues: true,
    ).watch().asyncMap((List<QueryRow> rows) async {
      final records = _callingHistoryFromRows(rows);
      // The programs to compute stats over are already in these rows, so the
      // `DISTINCT program_id` query [halfCallingStatsForDance] would run is
      // skipped: one fewer read per emit, and — more to the point — the stats
      // are derived from the same revision of `program_slots` the records came
      // from rather than from a re-query that a write could land in front of.
      //
      // The two id sets agree. With `performedOnly` false the history holds
      // every program containing the dance, which is exactly what that query
      // returns. With it true the history is narrowed to programs where the
      // dance was performed — and a program containing it but never performed
      // contributes no counted occurrence anyway, so dropping it cannot change
      // the result. `program_repository_watch_test.dart` asserts the equality
      // against [halfCallingStatsForDance] under both flags, with such a
      // program present.
      return DanceCallingHistory(
        records: records,
        halfStats: await _halfStatsForPrograms(
          danceId: danceId,
          programIds: {for (final r in records) r.programId}.toList(),
          performedOnly: performedOnly,
        ),
      );
    });
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
    String? callerFilter,
  }) async {
    final caller = _normalizedCallerFilter(callerFilter);
    final idRows = await _db
        .customSelect(
          'SELECT DISTINCT program_slots.program_id AS program_id '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id = ? '
          '${_callerClause(caller)}'
          'AND programs.deleted_at IS NULL',
          variables: [Variable<String>(danceId), ..._callerVariables(caller)],
        )
        .get();
    final programIds = [for (final r in idRows) r.read<String>('program_id')];
    return _halfStatsForPrograms(
      danceId: danceId,
      programIds: programIds,
      performedOnly: performedOnly,
    );
  }

  /// [halfCallingStatsForDance] once the programs containing [danceId] are
  /// known, so a caller already holding that set does not re-derive it.
  ///
  /// Program structure is read in full for each id regardless of
  /// [performedOnly] — the halves and the first/last-in-half positions come
  /// from the whole slot list, and only which *occurrences* are counted depends
  /// on the flag.
  Future<HalfCallingStats> _halfStatsForPrograms({
    required String danceId,
    required List<String> programIds,
    required bool performedOnly,
  }) async {
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

  /// Tombstones the program, stamping `existence_at` causally (schema v25,
  /// issue #898). One shared [at] goes into both `deletedAt` and `updatedAt`
  /// and `body` is untouched, which is unchanged and correct: nothing causal
  /// flows into either of those two. See `DanceRepository.softDelete`.
  Future<void> softDelete(String id, {required DateTime at}) =>
      _stampExistence(id, at: at, deleted: true);

  /// Revives the program, stamping `existence_at` causally (schema v25, issue
  /// #898). A revival is an existence transition, so it must advance
  /// `existence_at` or a peer holding the tombstone would win the comparison
  /// and delete it straight back.
  Future<void> restore(String id, {required DateTime at}) =>
      _stampExistence(id, at: at, deleted: false);

  /// Shared live<->deleted transition: one statement that writes
  /// `max(at, current + 1 tick)` while reading the pre-update
  /// `existence_at`, so the stamp cannot be computed from a value another
  /// writer has already moved. Matching no rows is a no-op, exactly as the
  /// previous unconditional UPDATE was.
  Future<void> _stampExistence(
    String id, {
    required DateTime at,
    required bool deleted,
  }) => stampExistenceTransition(
    _db,
    table: _db.programs,
    keyColumn: 'id',
    key: id,
    at: at,
    deleted: deleted,
  );

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
    return _db.transaction(() async {
      for (final chunk in _chunkIds(list)) {
        await (_db.delete(_db.programs)..where((t) => t.id.isIn(chunk))).go();
      }
    });
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
  /// via `program_provenance` queries keyed by `programId IN (...)`, chunking
  /// [ids] to stay within SQLite's bound-variable limit (see [_chunkIds]) and
  /// merging the per-chunk results into a `programId → Provenance` map.
  /// Programs without a provenance row are simply absent from the map. Used by
  /// [listAll] to avoid the per-row `_provenanceFor` N+1 fan-out. Mirrors the
  /// batched `IN (...)` lookup used by the dance derived-index rebuild.
  Future<Map<String, model.Provenance>> _provenanceForMany(
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final result = <String, model.Provenance>{};
    for (final chunk in _chunkIds(idList)) {
      final rows = await (_db.select(
        _db.programProvenance,
      )..where((t) => t.programId.isIn(chunk))).get();
      for (final row in rows) {
        result[row.programId] = _provenanceFromRow(row);
      }
    }
    return result;
  }

  model.Provenance _provenanceFromRow(ProgramProvenanceRow row) {
    return model.Provenance(
      source: row.source,
      externalId: row.externalId,
      importedAt: asUtc(row.importedAt),
      permission: row.permission,
      license: row.license,
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

  /// Max ids per `IN (…)` clause. Kept well under SQLite's default
  /// `SQLITE_MAX_VARIABLE_NUMBER` (999 on older builds) so a full-collection
  /// load/delete stays correct no matter how large the library grows; the
  /// batched queries above split their id list into chunks of this size.
  /// Mirrors `DanceRepository`'s `_idChunkSize`.
  static const int _idChunkSize = 500;

  Iterable<List<String>> _chunkIds(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final end = i + _idChunkSize;
      yield ids.sublist(i, end > ids.length ? ids.length : end);
    }
  }
}
