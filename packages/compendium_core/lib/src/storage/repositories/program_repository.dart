import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../analysis/half_calling_stats.dart';
import '../../model/enums.dart';
import '../../model/program.dart';
import '../../model/provenance.dart' as model;
import '../../model/stored_timestamp.dart';
import '../../search/filter.dart';
import '../../sync/sync_record_kind.dart';
import '../database.dart';
import '../existence.dart';
import '../permanent_deletion.dart';
import '../shareable_text.dart';
import '../utc_datetime.dart';
import '../calling_history_scope.dart';
import 'venue_repository.dart';
import 'sync_local_repository.dart';

/// One entry in a dance's calling history: a program that includes the dance
/// (a slot referencing it), produced by
/// [ProgramRepository.callingHistoryForDance].
///
/// Calling history is a **derived query** over [ProgramSlot]s, never stored on
/// the dance (see `docs/design/domain-model.md`). By default a program appears
/// as soon as it *contains* the dance in a primary slot — [performedAt] may be
/// null (the "mark performed" write path is a separate feature; see ROADMAP
/// G.2); an alternate slot appears only once it is marked performed. There is
/// one record per matching slot, so a dance appearing more than once in the
/// same program yields multiple records.
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
  /// final ordering/display fallback when neither [eventDate] nor [performedAt]
  /// is set.
  final DateTime programUpdatedAt;

  /// When the slot was marked performed, if it has been — otherwise null. UTC.
  /// It says the dance was called; its time dates the call only when the
  /// program has no [eventDate] (see [effectiveDate]).
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

  /// The date used for ordering and display: the program's event date when it
  /// has one, else when the slot was marked performed, else the program's
  /// last-updated time (GIG-2, maintainer decision 2026-10-29). Marking a slot
  /// on the Monday after Saturday's dance still dates the call Saturday, and
  /// re-dating the program moves it. Always non-null so ordering never depends
  /// on [performedAt] being present.
  ///
  /// `_callingHistoryRows` orders by the same date, and
  /// `DanceRepository._sortByLastCalled` sorts by it, both through
  /// `callingHistoryDateSql`.
  DateTime get effectiveDate => eventDate ?? performedAt ?? programUpdatedAt;

  /// The date a recency window gives this record: [effectiveDate] without its
  /// last fallback, so null when the program has no event date and the slot
  /// was never marked performed. A program's last edit is not a call (N1-3,
  /// maintainer decision 2026-10-30).
  ///
  /// A `CalledFilter.since` scope compares the same date, through
  /// `callingHistoryRecencyDateSql`; the two must agree.
  DateTime? get recencyDate => eventDate ?? performedAt;

  /// The venue this record's program was at, as the repeated-venues summary
  /// groups it, or null when the program has neither a linked record nor a
  /// typed venue.
  VenueKey? get venueKey => VenueKey.forProgram(venueId: venueId, venue: venue);

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

/// The number of matching calling-history records at one venue identity.
///
/// Linked venues remain keyed by [venueId], while free-text venues are keyed by
/// normalized [venue] ([key] is the [VenueKey] either way, the same key a
/// `CalledFilter.venue` scope matches). The app resolves linked labels before
/// displaying or ordering these values because the venue catalogue is app-side
/// state.
@immutable
class VenueCallCount {
  const VenueCallCount({
    required this.venueId,
    required this.venue,
    required this.count,
  });

  final String? venueId;
  final String? venue;
  final int count;

  /// The venue these records share. The summary only builds a count for a
  /// record with a key, so this throws only for a hand-built count with
  /// neither [venueId] nor [venue]. Folding [venue] again gives the key the
  /// summary grouped by: it stores [venue] trimmed and whitespace-collapsed,
  /// and the fold is idempotent.
  VenueKey get key => VenueKey.forProgram(venueId: venueId, venue: venue)!;

  @override
  bool operator ==(Object other) =>
      other is VenueCallCount &&
      other.venueId == venueId &&
      other.venue == venue &&
      other.count == count;

  @override
  int get hashCode => Object.hash(venueId, venue, count);
}

/// One venue with at least one counted call, and how many programs at it
/// count, produced by [ProgramRepository.calledVenues].
///
/// The app labels a record [key] from its venue catalogue, and a typed one from
/// [latestVenueText]. A record key whose record is missing (a dangling
/// `programs.venue_id` from a peer) falls back to [latestVenueText] too.
@immutable
class CalledVenue {
  const CalledVenue({
    required this.key,
    required this.programCount,
    this.latestVenueText,
  });

  /// The venue, as a `CalledFilter.venue` scope and the repeated-venues
  /// summary key it.
  final VenueKey key;

  /// How many distinct programs at this venue have a counted call.
  final int programCount;

  /// The typed venue of the most recent such program that has one, trimmed
  /// and whitespace-collapsed but not lower-cased. Null when none has typed
  /// text, which only a record key can be.
  final String? latestVenueText;

  @override
  bool operator ==(Object other) =>
      other is CalledVenue &&
      other.key == key &&
      other.programCount == programCount &&
      other.latestVenueText == latestVenueText;

  @override
  int get hashCode => Object.hash(key, programCount, latestVenueText);

  @override
  String toString() =>
      'CalledVenue(${key.storageKey}, programs: $programCount, '
      'latest: $latestVenueText)';
}

/// How many times a dance has been called, aggregated across every non-deleted
/// program, produced by [ProgramRepository.countByDance].
///
/// Four tallies are surfaced so a caller can honor the "Require mark-performed
/// for calling history" setting (ROADMAP G.2) and the "Require an event date"
/// setting the same way the dance-detail calling history does — WITHOUT a
/// second query, so either toggle takes effect live:
/// * [all] counts every counted occurrence (one per primary slot referencing
///   the dance, plus each alternate slot marked performed; a dance appearing
///   twice in one program counts twice), mirroring the detail history's
///   DEFAULT (a program appears as soon as it contains the dance).
/// * [performed] counts only occurrences whose slot was marked performed
///   (`performed_at IS NOT NULL`), mirroring the history's `performedOnly` mode.
/// * [dated] and [performedDated] are the same two tallies restricted to
///   programs that have an event date, mirroring `requireEventDate`.
///
/// Always `performed <= all`, `dated <= all` and
/// `performedDated <= min(performed, dated)`. A dance that has never been
/// called is simply absent from [countByDance]'s map rather than mapped to a
/// zero record.
@immutable
class DanceCallCounts {
  /// [dated] and [performedDated] default to [all] and [performed]: a record
  /// built without them describes occurrences that all have an event date.
  const DanceCallCounts({
    required this.all,
    required this.performed,
    int? dated,
    int? performedDated,
  }) : dated = dated ?? all,
       performedDated = performedDated ?? performed;

  /// Every occurrence of the dance (one per matching slot), regardless of
  /// whether the slot was marked performed.
  final int all;

  /// Occurrences whose slot was marked performed (`performed_at` set).
  final int performed;

  /// Occurrences in a program with an event date.
  final int dated;

  /// Occurrences marked performed in a program with an event date.
  final int performedDated;

  /// The tally that matches the active calling-history settings: performed
  /// occurrences when mark-performed is required, otherwise every occurrence,
  /// and in either case only dated programs when [requireEventDate] is set.
  /// Mirrors `ProgramRepository.callingHistoryForDance`'s `performedOnly` and
  /// `requireEventDate` flags so the card's count and the detail history never
  /// disagree.
  int countFor(bool performedOnly, {bool requireEventDate = false}) =>
      switch ((performedOnly, requireEventDate)) {
        (false, false) => all,
        (true, false) => performed,
        (false, true) => dated,
        (true, true) => performedDated,
      };

  @override
  bool operator ==(Object other) =>
      other is DanceCallCounts &&
      other.all == all &&
      other.performed == performed &&
      other.dated == dated &&
      other.performedDated == performedDated;

  @override
  int get hashCode => Object.hash(all, performed, dated, performedDated);

  @override
  String toString() =>
      'DanceCallCounts(all: $all, performed: $performed, dated: $dated, '
      'performedDated: $performedDated)';
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
  const DanceCallingHistory({
    required this.records,
    required this.halfStats,
    required this.venueCounts,
  });

  /// Empty history with empty stats — what a dance that has never been called
  /// resolves to.
  static const empty = DanceCallingHistory(
    records: [],
    halfStats: HalfCallingStats.empty,
    venueCounts: [],
  );

  /// Programs including the dance, most-recent first. Same value and ordering
  /// as [ProgramRepository.callingHistoryForDance].
  final List<DanceCallingRecord> records;

  /// Same value as [ProgramRepository.halfCallingStatsForDance] for the same
  /// arguments.
  final HalfCallingStats halfStats;

  /// Counts grouped by stable linked-venue identity or normalized free text.
  /// Counts include every matching record, including duplicate slots in a
  /// single program. The app filters, labels, orders, and limits this list.
  final List<VenueCallCount> venueCounts;
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

  /// Same value as [ProgramRepository.lastCalledByDance] with its default
  /// `requireEventDate: false`. No rendered surface reads this date; the
  /// Last-called sort runs its own query (see [ProgramRepository.lastCalledByDance]).
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

  /// The alternate rule every derived calling-history query applies: an
  /// alternate slot counts only once it is marked performed. See
  /// [callingHistoryAlternateClause] and
  /// [ProgramSlot.countsTowardCallingHistory].
  static final String _alternateClause = callingHistoryAlternateClause(
    slotTable: 'program_slots',
  );

  /// The event-date rule every derived calling-history query applies when
  /// "Require an event date" is on. See [callingHistoryEventDateClause].
  static String _eventDateClause(bool requireEventDate) =>
      callingHistoryEventDateClause(
        requireEventDate: requireEventDate,
        programTable: 'programs',
      );

  /// Persists a new program. Pass [knownVenueIds] on the bulk restore/import
  /// paths to validate a non-null `venueId` against a preloaded live snapshot
  /// instead of a per-row SELECT (keeps persisting N programs O(1) in venue
  /// queries); see [_upsert].
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  /// Updates an existing program. See [create] for [knownVenueIds].
  Future<void> update(Program program, {LiveVenueIds? knownVenueIds}) =>
      _upsert(program, knownVenueIds: knownVenueIds);

  /// Updates [program] like [update] and returns it as stored, read back in
  /// the same transaction (text normalized, performed stamps applied,
  /// timestamps at the store's precision).
  ///
  /// The result is the exact token [replaceIfUnchanged] compares against: no
  /// other write can land between this write and its read-back.
  Future<Program> updateAndReadBack(Program program) =>
      _db.transaction(() async {
        await _upsert(program);
        final stored = await getById(program.id);
        if (stored == null) {
          throw StateError('program "${program.id}" vanished inside its write');
        }
        return stored;
      });

  /// Atomically replaces the program [expected] describes with [replacement],
  /// but only if the stored program still equals [expected] (a value returned
  /// by [updateAndReadBack] or [getById]); returns whether it wrote.
  ///
  /// The comparison and the write share one transaction, so no write can land
  /// between them. It compares the whole stored program, not its `updatedAt`
  /// alone: the store keeps whole seconds, so a later edit within the same
  /// second as [expected] would carry an equal stamp but different content.
  /// [replacement] is written with a stamp after the current one (at or after
  /// [updatedAt]), so restoring an older snapshot still advances `updatedAt`.
  /// A missing or soft-deleted program is never replaced.
  Future<bool> replaceIfUnchanged({
    required Program expected,
    required Program replacement,
    required DateTime updatedAt,
  }) async =>
      await _replaceIfUnchanged(
        expected: expected,
        replacement: replacement,
        updatedAt: updatedAt,
        readBack: false,
      ) !=
      null;

  /// [replaceIfUnchanged], returning the program as stored by the write, read
  /// back in the same transaction, or `null` when it did not write. Like
  /// [updateAndReadBack], the result is the exact token the next
  /// [replaceIfUnchanged] compares against, so a chain of compare-and-replace
  /// writes never needs a separate read that another write could land before.
  Future<Program?> replaceIfUnchangedAndReadBack({
    required Program expected,
    required Program replacement,
    required DateTime updatedAt,
  }) => _replaceIfUnchanged(
    expected: expected,
    replacement: replacement,
    updatedAt: updatedAt,
    readBack: true,
  );

  /// Returns the stored program after the write when [readBack], [expected]
  /// otherwise, and `null` when it did not write.
  Future<Program?> _replaceIfUnchanged({
    required Program expected,
    required Program replacement,
    required DateTime updatedAt,
    required bool readBack,
  }) {
    assertUtc(updatedAt, 'updatedAt');
    if (replacement.id != expected.id) {
      throw ArgumentError.value(
        replacement.id,
        'replacement.id',
        'must match expected.id "${expected.id}"',
      );
    }
    return _db.transaction(() async {
      final current = await getById(expected.id);
      if (current == null || current != expected) return null;
      await _upsert(
        replacement.copyWith(
          updatedAt: nextStoredTimestamp(
            now: updatedAt.isAfter(current.updatedAt)
                ? updatedAt
                : current.updatedAt.add(storedTimestampTick),
            current: [current.updatedAt],
          ),
        ),
      );
      if (!readBack) return current;
      final stored = await getById(expected.id);
      if (stored == null) {
        throw StateError('program "${expected.id}" vanished inside its write');
      }
      return stored;
    });
  }

  /// Persists an inbound sync body without stamping performed slots as a local
  /// status-transition side effect.
  ///
  /// Does not run the live-venue guard (see [_upsert]'s `enforceVenueExists`):
  /// a peer's `venueId` is persisted exactly as received, dangling or not.
  /// Device Sync's I1 forbids changing a peer's serialised content without
  /// advancing its `updatedAt` (sync-spec.md §6.5), and nulling a dangling
  /// reference here would do exactly that; `SyncStorage` reports the missing
  /// venue separately instead (sync-spec.md §6.7).
  Future<void> writeFromSync(Program program) =>
      _upsert(program, stampPerformedSlots: false, enforceVenueExists: false);

  /// Persists only the program row for a two-phase inbound sync write. See
  /// [writeFromSync] for why the live-venue guard does not run here.
  Future<void> writeFromSyncParent(Program program) => _upsert(
    program,
    stampPerformedSlots: false,
    writeRelations: false,
    enforceVenueExists: false,
  );

  /// Persists only the program's dependent rows for a two-phase inbound write.
  /// See [writeFromSync] for why the live-venue guard does not run here.
  Future<void> writeFromSyncRelations(Program program) => _upsert(
    program,
    stampPerformedSlots: false,
    writeParent: false,
    enforceVenueExists: false,
  );

  /// Clears performed stamps created by one bulk mark action.
  ///
  /// The slot id and timestamp predicates make this an atomic compare-and-clear
  /// operation: a later edit to one of the slots, or an edit to another part of
  /// the program, is preserved instead of being overwritten by a stale
  /// [Program] snapshot.
  Future<int> clearPerformedAtIfMatches({
    required String programId,
    required Iterable<String> slotIds,
    required DateTime performedAt,
    required DateTime updatedAt,
  }) async {
    assertUtc(performedAt, 'performedAt');
    assertUtc(updatedAt, 'updatedAt');
    final ids = slotIds.toSet();
    if (ids.isEmpty) return 0;

    return _db.transaction(() async {
      var cleared = 0;
      for (final chunk in _chunkIds(ids.toList())) {
        cleared +=
            await (_db.update(_db.programSlots)..where(
                  (t) =>
                      t.programId.equals(programId) &
                      t.id.isIn(chunk) &
                      t.performedAt.equals(performedAt) &
                      existsQuery(
                        _db.select(_db.programs)..where(
                          (p) => p.id.equals(programId) & p.deletedAt.isNull(),
                        ),
                      ),
                ))
                .write(const ProgramSlotsCompanion(performedAt: Value(null)));
      }
      if (cleared == 0) return 0;
      final liveProgram =
          await (_db.select(_db.programs)
                ..where((t) => t.id.equals(programId) & t.deletedAt.isNull()))
              .getSingleOrNull();
      if (liveProgram == null) return 0;
      final rollbackUpdatedAt = nextStoredTimestamp(
        now: updatedAt.isAfter(liveProgram.updatedAt)
            ? updatedAt
            : liveProgram.updatedAt.add(storedTimestampTick),
        current: [liveProgram.updatedAt],
      );
      await (_db.update(
        _db.programs,
      )..where((t) => t.id.equals(programId) & t.deletedAt.isNull())).write(
        ProgramsCompanion(
          title: Value(normalizeShareableText(liveProgram.title)),
          updatedAt: Value(rollbackUpdatedAt),
        ),
      );
      return cleared;
    });
  }

  /// Carries a dialect rename to the programs that name it: every program whose
  /// `dialectName` is [oldName] gets [newName], and returns how many changed.
  ///
  /// Names are compared after [normalizeShareableText] on both sides, as
  /// `resolveProgramDialect` does, so a program holding the NFD spelling of a
  /// name still follows its NFC-normalized library entry. Trashed programs are
  /// included: restoring one must not bring back a name that no longer exists.
  ///
  /// Each changed program gets a stamp after its current one (at or after
  /// [updatedAt]), so the rename travels in Device Sync as an ordinary newer
  /// program record. The dialect library syncs separately, as a setting.
  Future<int> renameDialect({
    required String oldName,
    required String newName,
    required DateTime updatedAt,
  }) {
    assertUtc(updatedAt, 'updatedAt');
    final oldKey = normalizeShareableText(oldName);
    if (oldKey == normalizeShareableText(newName)) return Future.value(0);
    return _db.transaction(() async {
      final rows = await (_db.select(
        _db.programs,
      )..where((t) => t.dialectName.isNotNull())).get();
      var renamed = 0;
      for (final row in rows) {
        if (normalizeShareableText(row.dialectName!) != oldKey) continue;
        await (_db.update(
          _db.programs,
        )..where((t) => t.id.equals(row.id))).write(
          ProgramsCompanion(
            dialectName: Value(normalizeShareableText(newName)),
            updatedAt: Value(
              nextStoredTimestamp(
                now: updatedAt.isAfter(row.updatedAt)
                    ? updatedAt
                    : row.updatedAt.add(storedTimestampTick),
                current: [row.updatedAt],
              ),
            ),
          ),
        );
        renamed++;
      }
      return renamed;
    });
  }

  // --- Linking typed venues to a venue record (GIG-7 = (b)) ---------------

  /// The live programs that carry [name] as typed venue text and no linked
  /// record, matched by [VenueKey] (the same folding the repeated-venues list
  /// and the venue filter use). Empty for a blank [name].
  ///
  /// Trashed programs are not matched: a trashed program keeps its typed
  /// venue, so restoring it brings back the text it was trashed with.
  Future<List<ProgramRow>> _typedVenueMatches(
    String name, {
    String? excludeProgramId,
  }) async {
    if (callingHistoryVenueText(name) == null) return const [];
    final key = VenueKey.typed(name);
    final rows =
        await (_db.select(_db.programs)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.venueId.isNull() &
                  t.venue.isNotNull() &
                  (excludeProgramId == null
                      ? const Constant(true)
                      : t.id.equals(excludeProgramId).not()),
            ))
            .get();
    return [
      for (final row in rows)
        if (VenueKey.forProgram(venue: row.venue) == key) row,
    ];
  }

  /// How many live programs [linkTypedVenues] would link for [name]: the
  /// programs with that typed venue and no linked record, other than
  /// [excludeProgramId].
  Future<int> countTypedVenuePrograms(
    String name, {
    String? excludeProgramId,
  }) async => (await _typedVenueMatches(
    name,
    excludeProgramId: excludeProgramId,
  )).length;

  /// Links every live program whose typed venue matches [name] (by
  /// [VenueKey]) and has no linked record to the venue record [venueId], and
  /// returns how many it linked.
  ///
  /// Lossless: the typed `venue` text is kept, so unlinking later shows what
  /// was typed. Each linked program gets a stamp after its current one (at or
  /// after [updatedAt]), so the link travels in Device Sync as an ordinary
  /// newer program record. Programs already linked to any record, trashed
  /// programs, and [excludeProgramId] (the program an open editor is about to
  /// save with its own link) are left alone. Throws [StateError] when [venueId] is not a
  /// live venue record.
  Future<int> linkTypedVenues({
    required String venueId,
    required String name,
    required DateTime updatedAt,
    String? excludeProgramId,
  }) {
    assertUtc(updatedAt, 'updatedAt');
    return _db.transaction(() async {
      final venue =
          await (_db.select(_db.venues)
                ..where((t) => t.id.equals(venueId) & t.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
      if (venue == null) {
        throw StateError(
          'cannot link programs to venue "$venueId": it does not exist or is '
          'soft-deleted',
        );
      }
      final matches = await _typedVenueMatches(
        name,
        excludeProgramId: excludeProgramId,
      );
      for (final row in matches) {
        await (_db.update(
          _db.programs,
        )..where((t) => t.id.equals(row.id))).write(
          ProgramsCompanion(
            venueId: Value(venueId),
            updatedAt: Value(
              nextStoredTimestamp(
                now: updatedAt.isAfter(row.updatedAt)
                    ? updatedAt
                    : row.updatedAt.add(storedTimestampTick),
                current: [row.updatedAt],
              ),
            ),
          ),
        );
      }
      return matches.length;
    });
  }

  Future<void> _upsert(
    Program program, {
    LiveVenueIds? knownVenueIds,
    bool stampPerformedSlots = true,
    bool writeParent = true,
    bool writeRelations = true,
    bool enforceVenueExists = true,
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
    //
    // [enforceVenueExists] disables this guard entirely for the inbound sync
    // write paths ([writeFromSync] and its two-phase siblings): I1 forbids
    // altering a peer's serialised content without advancing its `updatedAt`
    // (sync-spec.md §6.5), so a dangling `venueId` from a peer MUST be
    // persisted verbatim rather than refused or nulled — `SyncStorage` reports
    // it separately (sync-spec.md §6.7).
    //
    // For every other caller (interactive `create`/`update`) the guard still
    // runs, but tolerates a `venueId` that was already dangling on the stored
    // row when this write does not change it: an inbound sync apply can leave
    // a program pointing at a venue this device no longer has, and the user
    // must still be able to save an otherwise-unrelated edit to that program
    // (or simply re-save it) without first being forced to unlink the venue.
    // Only a *newly chosen* non-existent venue is refused.
    final venueId = program.venueId;
    if (venueId != null && enforceVenueExists) {
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
        final storedVenueId =
            await (_db.selectOnly(_db.programs)
                  ..addColumns([_db.programs.venueId])
                  ..where(_db.programs.id.equals(program.id)))
                .map((row) => row.read(_db.programs.venueId))
                .getSingleOrNull();
        if (storedVenueId != venueId) {
          throw StateError(
            'cannot save program "${program.id}": venueId "$venueId" '
            'references a venue that does not exist or is soft-deleted',
          );
        }
      }
    }
    // Auto-stamp performed slots on a status transition to `performed`
    // (issue #356): a program's *status* being performed and its per-slot
    // calling history should agree. We only stamp on the transition — reading
    // the previously-stored status — so a slot the user manually cleared while
    // the program is already performed is NOT re-stamped, and reverting away
    // from performed never un-stamps (history is preserved). Idempotent and
    // dance-linked, primaries-only logic lives in
    // [Program.stampDanceSlotsPerformed] (skipping alternates there is an
    // inference from the 2026-10-28 alternates ruling; see that method). The
    // stamp uses the program's eventDate when set, else its updatedAt (the
    // save's "now"), keeping the timestamp deterministic and validated.
    if (stampPerformedSlots && program.status == ProgramStatus.performed) {
      final priorRow = await (_db.select(
        _db.programs,
      )..where((t) => t.id.equals(program.id))).getSingleOrNull();
      if (priorRow?.status != ProgramStatus.performed) {
        program = program.stampDanceSlotsPerformed(fallback: program.updatedAt);
      }
    }
    if (writeParent) {
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
              dancerLevel: Value(
                program.dancerLevel == null
                    ? null
                    : normalizeShareableText(program.dancerLevel!),
              ),
              notes: Value(normalizeShareableText(program.notes)),
              status: program.status,
              hideAlternates: Value(program.hideAlternates),
              // Normalized like every shareable string, and it must be: the
              // dialect library's own names reach storage through
              // SettingsRepository.set, which NFC-normalizes the shareable
              // `custom_dialects` JSON, and Device Sync rejects a body that
              // differs from its normalized form (`nonCanonicalWireBody`). A
              // reference stored un-normalized would stop matching the
              // reloaded library name and get the whole program rejected.
              dialectName: Value(
                program.dialectName == null
                    ? null
                    : normalizeShareableText(program.dialectName!),
              ),
              payMinorUnits: Value(program.payMinorUnits),
              payCurrency: Value(program.payCurrency),
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
    }
    if (writeRelations) {
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
                isPurgedDance: Value(slot.isPurgedDance),
                isAlt: Value(slot.isAlt),
                guestCaller: Value(
                  slot.guestCaller == null
                      ? null
                      : normalizeShareableText(slot.guestCaller!),
                ),
                walkthroughMinutes: Value(slot.walkthroughMinutes),
                danceMinutes: Value(slot.danceMinutes),
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

  /// The programs among [ids], assembled exactly as [listAll] assembles them,
  /// in a bounded number of batched queries rather than one [getById] per
  /// program. Unordered; an id with no row is left out.
  Future<List<Program>> getByIds(
    Iterable<String> ids, {
    bool includeDeleted = false,
  }) async {
    final rows = <ProgramRow>[];
    for (final chunk in _chunkIds(ids.toSet().toList())) {
      final query = _db.select(_db.programs)..where((t) => t.id.isIn(chunk));
      if (!includeDeleted) {
        query.where((t) => t.deletedAt.isNull());
      }
      rows.addAll(await query.get());
    }
    final found = [for (final r in rows) r.id];
    final slotsByProgram = await _slotsForMany(found);
    final provByProgram = await _provenanceForMany(found);
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
        isPurgedDance: r.isPurgedDance,
        isAlt: r.isAlt,
        guestCaller: r.guestCaller,
        walkthroughMinutes: r.walkthroughMinutes,
        danceMinutes: r.danceMinutes,
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
  ///   `performed_at`), the `COUNT(*)` / `COUNT(performed_at)` tallies, and
  ///   which slots the last-called date is taken over.
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

  /// Maps dance id → the most recent date it was called across every
  /// performed slot of every non-deleted program, for dances with at least one
  /// slot marked performed; a dance absent from the map has no performed slot —
  /// or, when [callerFilter] is set, none in a program led by that host caller
  /// (see [callingHistoryForDance]; issue #583). Pass [requireEventDate] `true`
  /// to consider only programs that have an event date ("Require an event
  /// date").
  ///
  /// Each performed slot is dated as [DanceCallingRecord.effectiveDate] dates
  /// it: the program's event date, else the performed stamp (GIG-2).
  ///
  /// Only performed slots count here, whatever the history settings.
  /// Collection's Last-called sort does not read it: `DanceRepository.search`
  /// orders by each dance's latest history date under the active
  /// calling-history settings instead (FIND-2).
  Future<Map<String, DateTime>> lastCalledByDance({
    String? callerFilter,
    bool requireEventDate = false,
  }) async => _programDerivedRows(_normalizedCallerFilter(callerFilter))
      .get()
      .then(
        (rows) => _lastCalledFromRows(rows, requireEventDate: requireEventDate),
      );

  /// Maps dance id → its [DanceCallCounts] across every counted slot (every
  /// primary, plus each alternate marked performed) of every non-deleted
  /// program, for dances that have been called at least once (a
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
  /// same pair restricted to dated programs serves "Require an event date".
  /// The
  /// `deleted_at IS NULL` join filter matches both [lastCalledByDance] and
  /// [callingHistoryForDance].
  Future<Map<String, DanceCallCounts>> countByDance({
    String? callerFilter,
  }) async =>
      _programDerivedRows(_normalizedCallerFilter(callerFilter))
          .get()
          .then(_countsFromRows);

  /// The ONE query behind [lastCalledByDance], [countByDance] and
  /// [watchProgramDerivedCounts]. [caller] is already normalized.
  ///
  /// The two tallies and the last-called date are aggregated together rather
  /// than by two queries, for two reasons. Sharing the query is what stops the
  /// one-shot reads and the stream from ever disagreeing about which slots
  /// count. And computing them in one statement is what makes each emit of
  /// [watchProgramDerivedCounts] an internally consistent snapshot: taking the
  /// last-called date in a second read could observe a write that landed after
  /// the counts were read, so one emit would carry tallies from one revision
  /// and a last-called date from the next.
  ///
  /// The last-called date is `COALESCE(event_date, performed_at)` over
  /// performed slots only: [DanceCallingRecord.effectiveDate] for a slot that
  /// has a stamp, so `updated_at` is never reached. The `CASE` yields NULL for
  /// an unperformed slot and `MAX` ignores NULLs, so a dance whose slots were
  /// all unperformed aggregates to NULL and [_lastCalledFromRows] omits it.
  Selectable<QueryRow> _programDerivedRows(String? caller) => _db.customSelect(
    'SELECT program_slots.dance_id AS dance_id, '
    'COUNT(*) AS all_count, '
    'COUNT(program_slots.performed_at) AS performed_count, '
    'COUNT(programs.event_date) AS dated_count, '
    'COUNT(CASE WHEN programs.event_date IS NOT NULL '
    'THEN program_slots.performed_at END) AS performed_dated_count, '
    'MAX(CASE WHEN program_slots.performed_at IS NOT NULL '
    'THEN COALESCE(programs.event_date, program_slots.performed_at) END) '
    'AS last_called, '
    'MAX(CASE WHEN program_slots.performed_at IS NOT NULL '
    'THEN programs.event_date END) AS last_called_dated '
    'FROM program_slots '
    'JOIN programs ON programs.id = program_slots.program_id '
    'WHERE program_slots.dance_id IS NOT NULL '
    'AND programs.deleted_at IS NULL '
    '$_alternateClause'
    '${_callerClause(caller)}'
    'GROUP BY program_slots.dance_id',
    variables: _callerVariables(caller),
    readsFrom: _programDerivedTables,
  );

  /// Dances with at least one performed slot, mapped to their most recent one.
  /// A NULL `last_called` means every slot for that dance is unperformed, so
  /// the dance is absent from the map rather than present with a null value.
  ///
  /// With [requireEventDate], only slots in a program that has an event date
  /// are considered, so a dance whose performed slots are all in undated
  /// programs is absent too.
  Map<String, DateTime> _lastCalledFromRows(
    List<QueryRow> rows, {
    bool requireEventDate = false,
  }) => {
    for (final row in rows)
      if (row.read<DateTime?>(
            requireEventDate ? 'last_called_dated' : 'last_called',
          )
          case final lastCalled?)
        row.read<String>('dance_id'): asUtc(lastCalled),
  };

  Map<String, DanceCallCounts> _countsFromRows(List<QueryRow> rows) => {
    for (final row in rows)
      row.read<String>('dance_id'): DanceCallCounts(
        all: row.read<int>('all_count'),
        performed: row.read<int>('performed_count'),
        dated: row.read<int>('dated_count'),
        performedDated: row.read<int>('performed_dated_count'),
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
  /// The Collection snapshot carries both — the "called ×N" badge and the
  /// last-called stamps (the Last-called sort runs its own query in
  /// `DanceRepository.search`) — so they are emitted as one
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
  /// By DEFAULT a program appears as soon as it *contains* the dance in a
  /// primary slot — regardless of whether the slot was marked performed
  /// ([performedAt] may be null). An alternate slot appears only once it is
  /// marked performed ([ProgramSlot.countsTowardCallingHistory]), in either
  /// mode. Pass [performedOnly] `true` to restrict the history to slots that
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
  /// Pass [requireEventDate] `true` to leave out programs that have no event
  /// date ("Require an event date", off by default). It too is AND-combined
  /// with the other gates.
  ///
  /// Calling history is a derived query, never stored (see
  /// `docs/design/domain-model.md`; `docs/design/ux.md` §2 / the dance-detail
  /// wireframe "History"). One record per matching slot, ordered by each
  /// record's [DanceCallingRecord.effectiveDate] (event_date, else
  /// performed_at, else updated_at) descending — the ordering never depends on
  /// `performed_at` being present (GIG-2).
  /// Feeds the dance-detail "Calling history" section.
  Future<List<DanceCallingRecord>> callingHistoryForDance(
    String danceId, {
    bool performedOnly = false,
    bool requireEventDate = false,
    String? callerFilter,
  }) async => _callingHistoryRows(
    danceId,
    performedOnly: performedOnly,
    requireEventDate: requireEventDate,
    caller: _normalizedCallerFilter(callerFilter),
  ).get().then(_callingHistoryFromRows);

  /// The query behind [callingHistoryForDance]. Shared by the one-shot read and
  /// [watchCallingHistoryForDance] so the two can never diverge; [caller] is
  /// already normalized.
  Selectable<QueryRow> _callingHistoryRows(
    String danceId, {
    required bool performedOnly,
    required bool requireEventDate,
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
    '$_alternateClause'
    '${_eventDateClause(requireEventDate)}'
    '${_callerClause(caller)}'
    'AND programs.deleted_at IS NULL '
    'ORDER BY ${callingHistoryDateSql(slotTable: 'program_slots', programTable: 'programs')} '
    'DESC, programs.id',
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

  List<VenueCallCount> _venueCountsFromRecords(
    List<DanceCallingRecord> records,
  ) {
    final counts = <String, VenueCallCount>{};
    for (final record in records) {
      final key = record.venueKey?.storageKey;
      if (key == null) continue;
      final current = counts[key];
      counts[key] = VenueCallCount(
        venueId: record.venueId,
        venue: current?.venue ?? _displayVenueText(record.venue),
        count: (current?.count ?? 0) + 1,
      );
    }
    return counts.values.toList(growable: false);
  }

  String? _displayVenueText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Every venue with at least one counted call, for the Filters panel's venue
  /// chooser: a choice with no counted call could not change a result, so it
  /// is left out.
  ///
  /// "Counted" is what a `CalledFilter` with the same arguments counts: the
  /// alternate rule, the caller scope ([callerFilter]), [performedOnly],
  /// [requireEventDate], and non-deleted programs only. Venues are keyed as
  /// the repeated-venues summary keys them ([VenueKey]); a program with no
  /// venue is left out. Ordered by each venue's most recent call
  /// ([DanceCallingRecord.effectiveDate]'s date, newest first), then by
  /// [VenueKey.storageKey].
  Future<List<CalledVenue>> calledVenues({
    bool performedOnly = false,
    bool requireEventDate = false,
    String? callerFilter,
  }) => _calledVenueRows(
    performedOnly: performedOnly,
    requireEventDate: requireEventDate,
    caller: _normalizedCallerFilter(callerFilter),
  ).get().then(_calledVenuesFromRows);

  /// Reactive [calledVenues]: emits now, then whenever a write to programs or
  /// slots changes it. Arguments mean what they do on the one-shot method.
  Stream<List<CalledVenue>> watchCalledVenues({
    bool performedOnly = false,
    bool requireEventDate = false,
    String? callerFilter,
  }) => _calledVenueRows(
    performedOnly: performedOnly,
    requireEventDate: requireEventDate,
    caller: _normalizedCallerFilter(callerFilter),
  ).watch().map(_calledVenuesFromRows);

  /// One row per program with a venue and at least one counted slot, with its
  /// newest counted slot's history date. Shared by [calledVenues] and
  /// [watchCalledVenues] so the two cannot diverge.
  Selectable<QueryRow> _calledVenueRows({
    required bool performedOnly,
    required bool requireEventDate,
    required String? caller,
  }) => _db.customSelect(
    'SELECT programs.id AS program_id, programs.venue_id AS venue_id, '
    'programs.venue AS venue, '
    'MAX(${callingHistoryDateSql(slotTable: 'program_slots', programTable: 'programs')}) '
    'AS called_at '
    'FROM program_slots '
    'JOIN programs ON programs.id = program_slots.program_id '
    'WHERE programs.deleted_at IS NULL '
    '${performedOnly ? 'AND program_slots.performed_at IS NOT NULL ' : ''}'
    '$_alternateClause'
    '${_eventDateClause(requireEventDate)}'
    '${_callerClause(caller)}'
    'GROUP BY programs.id',
    variables: _callerVariables(caller),
    readsFrom: _programDerivedTables,
  );

  List<CalledVenue> _calledVenuesFromRows(List<QueryRow> rows) {
    final programs =
        [
          for (final row in rows)
            if (VenueKey.forProgram(
                  venueId: row.read<String?>('venue_id'),
                  venue: row.read<String?>('venue'),
                )
                case final key?)
              (
                key: key,
                venue: _displayVenueText(row.read<String?>('venue')),
                calledAt: asUtc(row.read<DateTime>('called_at')),
              ),
        ]..sort((a, b) {
          final byDate = b.calledAt.compareTo(a.calledAt);
          return byDate != 0
              ? byDate
              : a.key.storageKey.compareTo(b.key.storageKey);
        });
    final counts = <VenueKey, int>{};
    final latestText = <VenueKey, String>{};
    for (final program in programs) {
      counts.update(program.key, (n) => n + 1, ifAbsent: () => 1);
      if (program.venue case final venue?) {
        latestText.putIfAbsent(program.key, () => venue);
      }
    }
    return [
      for (final MapEntry(:key, value: count) in counts.entries)
        CalledVenue(
          key: key,
          programCount: count,
          latestVenueText: latestText[key],
        ),
    ];
  }

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
  ///    argument here changes (`performedOnly`, `requireEventDate`,
  ///    `callerFilter`).
  /// 5. **When a view's data is fully reactive, drop its refresh-scope listener
  ///    in the same change.** Leaving it attached means one write both re-emits
  ///    the stream and re-runs the imperative load — reintroducing #340 while
  ///    fixing staleness. The scopes themselves come out last, once nothing
  ///    subscribes; both app-side channels have now reached that condition, one
  ///    of them by being retired on it.
  Stream<DanceCallingHistory> watchCallingHistoryForDance(
    String danceId, {
    bool performedOnly = false,
    bool requireEventDate = false,
    String? callerFilter,
  }) {
    final caller = _normalizedCallerFilter(callerFilter);
    return _callingHistoryRows(
      danceId,
      performedOnly: performedOnly,
      requireEventDate: requireEventDate,
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
      // The two id sets agree on everything that counts. That query returns
      // every program containing the dance. The history leaves out a program
      // whose only slots for the dance are unperformed alternates, and with
      // `performedOnly` true also one where the dance was never performed —
      // and such a program contributes no counted occurrence to the stats
      // either (`computeHalfCallingStats` skips the same slots), so dropping
      // it cannot change the result. With `requireEventDate` true both sides
      // leave out an undated program by the same clause.
      // `program_repository_watch_test.dart`
      // asserts the equality against [halfCallingStatsForDance] under both
      // flags with a never-performed program present, and
      // `calling_history_alternates_test.dart` does so with an
      // alternates-only program.
      return DanceCallingHistory(
        records: records,
        halfStats: await _halfStatsForPrograms(
          danceId: danceId,
          programIds: {for (final r in records) r.programId}.toList(),
          performedOnly: performedOnly,
        ),
        venueCounts: _venueCountsFromRecords(records),
      );
    });
  }

  /// First/second-half positional calling stats for the dance identified by
  /// [danceId] (issue #378), aggregated across every non-deleted program that
  /// includes it. A sibling of [callingHistoryForDance] — that method is left
  /// untouched — computed via the pure, Flutter-free [computeHalfCallingStats],
  /// which reuses the derived-section helper [Program.sectionsForSlots].
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
  ///
  /// [requireEventDate] mirrors [callingHistoryForDance] too: when true a
  /// program with no event date contributes nothing.
  Future<HalfCallingStats> halfCallingStatsForDance(
    String danceId, {
    bool performedOnly = false,
    bool requireEventDate = false,
    String? callerFilter,
  }) async {
    final caller = _normalizedCallerFilter(callerFilter);
    final idRows = await _db
        .customSelect(
          'SELECT DISTINCT program_slots.program_id AS program_id '
          'FROM program_slots '
          'JOIN programs ON programs.id = program_slots.program_id '
          'WHERE program_slots.dance_id = ? '
          '${_eventDateClause(requireEventDate)}'
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
  Future<void> restore(
    String id, {
    required DateTime at,
    bool clearPending = true,
  }) => _db.transaction(() async {
    await _stampExistence(id, at: at, deleted: false);
    if (clearPending) {
      await clearPendingSyncDeletionForRestore(
        _db,
        kind: SyncRecordKind.program,
        recordId: id,
        table: _db.programs,
        keyColumn: 'id',
        at: at,
      );
    }
  });

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

  /// Removes the programs identified by [ids] regardless of soft-delete state:
  /// unpublished programs are hard-deleted, while published programs become
  /// tombstones so peers retain deletion evidence. Physical deletes remove
  /// each program's slots via the `program_slots.program_id` cascade. Unknown
  /// ids are ignored; an empty [ids] is a no-op. Runs in a single transaction.
  ///
  /// Intended for reverting a just-committed import batch (import-session undo,
  /// e.g. [CallersCompanionUsrImporter.undo]); ordinary user deletes should go
  /// through [softDelete].
  Future<void> hardDelete(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return _db.transaction(() async {
      final publishedIds = await publishedSyncRecordIds(
        _db,
        kind: SyncRecordKind.program,
        recordIds: list,
      );
      for (final id in publishedIds) {
        await stampExistenceTransition(
          _db,
          table: _db.programs,
          keyColumn: 'id',
          key: id,
          at: DateTime.now().toUtc(),
          deleted: true,
        );
      }
      final erasableIds = list
          .where((id) => !publishedIds.contains(id))
          .toList(growable: false);
      for (final chunk in _chunkIds(erasableIds)) {
        await (_db.delete(_db.programs)..where((t) => t.id.isIn(chunk))).go();
      }
    });
  }

  /// Hard-deletes unpublished soft-deleted programs whose `deletedAt` is older
  /// than [retention] (default 30 days per `docs/design/storage.md`). A
  /// published program cannot be erased, so an expired one is blanked instead,
  /// as "Permanently delete" blanks it; its deletion record stays so peers
  /// retain deletion evidence. See `DanceRepository._markExpiredPublished` for
  /// why that leaves `existence_at` alone. Returns how many programs it erased.
  /// Physical deletes cascade slots automatically (FK).
  ///
  /// When [onlyIds] is non-null the purge is restricted to those ids: a row
  /// outside the set is left alone even if it is past the cutoff. The manual
  /// "Permanently delete" action uses this so erasing one item cannot sweep
  /// other expired items past the user's retention setting (LIFE-1). The
  /// cutoff and the published-record exclusion still apply, so a caller wanting
  /// one specific row gone first backdates its `deletedAt` (see
  /// [softDelete]).
  Future<int> purgeDeleted({
    required DateTime now,
    Duration retention = const Duration(days: 30),
    Iterable<String>? onlyIds,
  }) {
    assertUtc(now, 'now');
    final cutoff = now.subtract(retention);
    final restrictTo = onlyIds?.toSet();
    return _db.transaction(() async {
      final rows = <ProgramRow>[];
      if (restrictTo == null) {
        rows.addAll(
          await (_db.select(
            _db.programs,
          )..where((t) => t.deletedAt.isSmallerOrEqualValue(cutoff))).get(),
        );
      } else {
        for (final chunk in _chunkIds(restrictTo.toList())) {
          rows.addAll(
            await (_db.select(_db.programs)..where(
                  (t) =>
                      t.deletedAt.isSmallerOrEqualValue(cutoff) &
                      t.id.isIn(chunk),
                ))
                .get(),
          );
        }
      }
      if (rows.isEmpty) return 0;
      final publishedIds = await publishedSyncRecordIds(
        _db,
        kind: SyncRecordKind.program,
        recordIds: rows.map((row) => row.id),
      );
      final expiredPublished = [
        for (final row in rows)
          if (publishedIds.contains(row.id) &&
              !isPermanentlyDeleted(row.deletedAt))
            row.id,
      ];
      if (expiredPublished.isNotEmpty) {
        // Leaves `existence_at` alone: see
        // `DanceRepository._markExpiredPublished`.
        // The mark changes the body, so it stamps content too; see
        // `DanceRepository._markExpiredPublished`.
        for (final chunk in _chunkIds(expiredPublished)) {
          await _db.customUpdate(
            'UPDATE ${_db.programs.actualTableName} '
            'SET deleted_at = ?, updated_at = MAX(updated_at + 1, ?) '
            'WHERE id IN (${List.filled(chunk.length, '?').join(', ')})',
            variables: [
              Variable<int>(unixSeconds(permanentlyDeletedAt)),
              Variable<int>(unixSeconds(now)),
              for (final id in chunk) Variable<String>(id),
            ],
            updates: {_db.programs},
            updateKind: UpdateKind.update,
          );
        }
        await removePermanentlyDeleted(now: now, onlyIds: expiredPublished);
      }
      final erasableIds = [
        for (final row in rows)
          if (!publishedIds.contains(row.id)) row.id,
      ];
      if (erasableIds.isEmpty) return 0;
      var deleted = 0;
      for (final chunk in _chunkIds(erasableIds)) {
        deleted += await (_db.delete(
          _db.programs,
        )..where((t) => t.id.isIn(chunk))).go();
      }
      return deleted;
    });
  }

  /// "Permanently delete" for one program in Recently deleted (LIFE-2).
  ///
  /// Erases the program when no device has published it, exactly as before. A
  /// published program cannot be erased (sync-spec.md §3.1 forfeiture), so it
  /// is blanked instead and hidden from Recently deleted; see
  /// `permanent_deletion.dart` for the design and the maintainer's decision.
  ///
  /// Mirrors `DanceRepository.permanentlyDelete`: a causal existence stamp, the
  /// [permanentlyDeletedAt] mark, then [removePermanentlyDeleted]. A program
  /// that is missing or live is left alone and reported as
  /// [PermanentDeletion.none].
  Future<PermanentDeletion> permanentlyDelete(
    String id, {
    required DateTime now,
  }) {
    assertUtc(now, 'now');
    return _db.transaction(() async {
      final trashed =
          await (_db.select(_db.programs)
                ..where((t) => t.id.equals(id) & t.deletedAt.isNotNull()))
              .getSingleOrNull();
      if (trashed == null) return PermanentDeletion.none;
      await _stampExistence(id, at: now, deleted: true);
      // The stamp above also moved `updated_at` to [now]. Put the content stamp
      // back: the blank body must outrank the content it replaces, which may
      // carry a stamp ahead of this clock.
      await (_db.update(_db.programs)..where((t) => t.id.equals(id))).write(
        ProgramsCompanion(
          updatedAt: Value(trashed.updatedAt),
          deletedAt: Value(permanentlyDeletedAt),
        ),
      );
      final published = await isPublishedSyncRecord(
        _db,
        kind: SyncRecordKind.program,
        recordId: id,
      );
      await removePermanentlyDeleted(now: now, onlyIds: [id]);
      return published ? PermanentDeletion.blanked : PermanentDeletion.erased;
    });
  }

  /// Finishes every permanently deleted program ([isPermanentlyDeleted]):
  /// erases the unpublished ones through [purgeDeleted] and blanks the
  /// published ones that still hold content. Returns how many it erased or
  /// blanked. See `DanceRepository.removePermanentlyDeleted` for why the
  /// startup sweep runs it whatever the retention setting, and why a blank
  /// program is skipped.
  ///
  /// When [onlyIds] is non-null only those programs are considered.
  Future<int> removePermanentlyDeleted({
    required DateTime now,
    Iterable<String>? onlyIds,
  }) {
    assertUtc(now, 'now');
    final restrictTo = onlyIds?.toSet();
    return _db.transaction(() async {
      final marked = <ProgramRow>[];
      if (restrictTo == null) {
        marked.addAll(
          await (_db.select(
            _db.programs,
          )..where((t) => t.deletedAt.equals(permanentlyDeletedAt))).get(),
        );
      } else {
        for (final chunk in _chunkIds(restrictTo.toList())) {
          marked.addAll(
            await (_db.select(_db.programs)..where(
                  (t) =>
                      t.deletedAt.equals(permanentlyDeletedAt) &
                      t.id.isIn(chunk),
                ))
                .get(),
          );
        }
      }
      if (marked.isEmpty) return 0;
      final publishedIds = await publishedSyncRecordIds(
        _db,
        kind: SyncRecordKind.program,
        recordIds: marked.map((row) => row.id),
      );
      var removed = await purgeDeleted(
        now: now,
        onlyIds: [
          for (final row in marked)
            if (!publishedIds.contains(row.id)) row.id,
        ],
      );
      for (final row in marked) {
        if (!publishedIds.contains(row.id) || await _isBlank(row)) continue;
        await _blank(row, now: now);
        removed++;
      }
      return removed;
    });
  }

  /// Whether [row] already holds nothing but a deletion record. Slots are
  /// checked too: a program's slots carry most of what it says.
  Future<bool> _isBlank(ProgramRow row) async =>
      row.title == blankedRecordTitle &&
      row.eventDate == null &&
      row.venue == null &&
      row.venueId == null &&
      row.band == null &&
      row.caller == null &&
      row.dancerLevel == null &&
      row.notes.isEmpty &&
      row.status == ProgramStatus.draft &&
      !row.hideAlternates &&
      row.dialectName == null &&
      row.payMinorUnits == null &&
      row.payCurrency == null &&
      await (_db.selectOnly(_db.programSlots)
                ..addColumns([_db.programSlots.id])
                ..where(_db.programSlots.programId.equals(row.id))
                ..limit(1))
              .getSingleOrNull() ==
          null;

  /// Removes everything a trashed, published program holds except its
  /// deletion record: its slots, its provenance, any kept parts a newer peer's
  /// build sent (`retained_sync_fields`), and every field of its row. The blank
  /// body is stamped after the content it replaces, so it wins last-writer-wins
  /// on every peer. Nothing else cites a program.
  Future<void> _blank(ProgramRow row, {required DateTime now}) async {
    final id = row.id;
    await (_db.delete(
      _db.programSlots,
    )..where((t) => t.programId.equals(id))).go();
    await (_db.delete(
      _db.programProvenance,
    )..where((t) => t.programId.equals(id))).go();
    await (_db.delete(_db.retainedSyncFields)..where(
          (t) =>
              t.kind.equals(SyncRecordKind.program.name) &
              t.recordId.equals(id),
        ))
        .go();
    final current = asUtc(row.updatedAt);
    await (_db.update(_db.programs)..where((t) => t.id.equals(id))).write(
      ProgramsCompanion(
        title: Value(normalizeShareableText(blankedRecordTitle)),
        eventDate: const Value(null),
        venue: Value(normalizeShareableTextOrNull(null)),
        venueId: const Value(null),
        band: Value(normalizeShareableTextOrNull(null)),
        caller: Value(normalizeShareableTextOrNull(null)),
        dancerLevel: Value(normalizeShareableTextOrNull(null)),
        notes: Value(normalizeShareableText('')),
        status: const Value(ProgramStatus.draft),
        hideAlternates: const Value(false),
        dialectName: Value(normalizeShareableTextOrNull(null)),
        payMinorUnits: const Value(null),
        payCurrency: const Value(null),
        updatedAt: Value(
          nextStoredTimestamp(
            now: now.isAfter(current) ? now : current.add(storedTimestampTick),
            current: [current],
          ),
        ),
        deletedAt: Value(permanentlyDeletedAt),
      ),
    );
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
    dialectName: row.dialectName,
    payMinorUnits: row.payMinorUnits,
    payCurrency: row.payCurrency,
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
