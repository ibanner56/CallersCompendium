import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'enums.dart';
import 'provenance.dart';
import 'stored_timestamp.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// One slot in a program.
///
/// Invariant: at least one of [danceId] or [text] is non-null. Both may be
/// set simultaneously — [text] is then a per-slot caller note on a dance
/// slot; alone it is the full slot content (break, waltz, announcement).
@immutable
class ProgramSlot {
  ProgramSlot({
    required this.id,
    required this.position,
    this.danceId,
    this.text,
    this.isPurgedDance = false,
    this.isAlt = false,
    this.guestCaller,
    this.walkthroughMinutes,
    this.danceMinutes,
    this.performedAt,
  }) {
    if (danceId == null && text == null) {
      throw ArgumentError(
        'a slot requires a danceId, text, or both',
        'danceId/text',
      );
    }
    if (isPurgedDance == true && (danceId != null || text == null)) {
      throw ArgumentError(
        'a purged dance tombstone requires text without a danceId',
        'isPurgedDance',
      );
    }
    if (position < 0) {
      throw ArgumentError.value(position, 'position', 'must be >= 0');
    }
    if (walkthroughMinutes != null && walkthroughMinutes! < 0) {
      throw ArgumentError.value(
        walkthroughMinutes,
        'walkthroughMinutes',
        'must be >= 0',
      );
    }
    if (danceMinutes != null && danceMinutes! < 0) {
      throw ArgumentError.value(danceMinutes, 'danceMinutes', 'must be >= 0');
    }
  }

  final String id;
  final int position;
  final String? danceId;
  final String? text;

  /// Whether this text-only slot preserves the title of a purged dance.
  ///
  /// This marker distinguishes a lossless purge caption from an ordinary
  /// free-text slot such as a break, waltz, or announcement.
  /// `null` preserves the ambiguous text-only shape from pre-v33 storage and
  /// older archives; those values remain literal until explicitly edited.
  final bool? isPurgedDance;

  /// Alternate dance, decided at event time.
  final bool isAlt;

  /// Guest caller for this slot, when someone other than the program's host
  /// caller leads it. Structured (not folded into [text]).
  final String? guestCaller;

  /// Planned walkthrough length in minutes; `>= 0` when present.
  final int? walkthroughMinutes;

  /// Planned dance length in minutes (CC `SetItem.Time`). Structured, distinct
  /// from any free-text timing note in [text]; `>= 0` when present.
  final int? danceMinutes;

  /// Combined planned slot length, when either split duration is present.
  int? get plannedTotalMinutes {
    if (walkthroughMinutes == null && danceMinutes == null) return null;
    return (walkthroughMinutes ?? 0) + (danceMinutes ?? 0);
  }

  /// Set when the slot was actually called; feeds dance calling history
  /// (which is derived by query, never stored on the dance).
  final DateTime? performedAt;

  /// Whether this slot counts toward its dance's calling history ("called
  /// ×N", the Called filter, history rows, last-called, venue repeats and half
  /// stats), before the "Require mark performed" setting is applied.
  ///
  /// A primary dance slot counts as soon as its program contains it (#583's
  /// documented default). An alternate counts only once that slot is marked
  /// performed: listing a dance as a fallback is not calling it (maintainer
  /// ruling, 2026-10-28). The SQL side of the same rule is
  /// `callingHistoryAlternateClause`; the two must agree.
  bool get countsTowardCallingHistory =>
      danceId != null && (!isAlt || performedAt != null);

  /// Whether a bulk mark — **Mark all performed**, or the stamp when a program's
  /// status becomes performed ([Program.stampDanceSlotsPerformed]) — stamps
  /// this slot: an unperformed primary dance slot.
  ///
  /// Alternates are skipped because a bulk stamp would make every unused
  /// alternate count as called (see [countsTowardCallingHistory]); a caller
  /// marks the alternate they actually used by hand.
  bool get isBulkMarkPerformedTarget =>
      danceId != null && !isAlt && performedAt == null;

  /// Whether this slot is one of the dances a program is planned for: every
  /// slot except an alternate and the break. The one definition behind
  /// [Program.plannedDanceCount] and the set-list numbering
  /// ([Program.danceNumbersForSlots]), so a count and the highest number never
  /// disagree (GIG-10).
  bool get isPlannedDance => !isAlt && !isBreak;

  /// Whether this slot is a **break** — the divider the program's first/second
  /// section is derived from ([Program.sectionAtIndex]).
  ///
  /// A break is modelled as a free-text slot (no [danceId]) whose [text],
  /// trimmed and lowercased, equals the canonical [Program.breakSlotText]
  /// token. This is deliberately an exact match on the token so a note like
  /// "breakdown" or "take a break at the pub after" is *not* treated as the
  /// structural break; the one-tap "insert break" affordance writes exactly
  /// this token so callers never have to hand-type it (a hand-typed "Break"
  /// still matches). There is no persisted break slot-kind — recognition is
  /// derived, so introducing it needs no schema migration.
  bool get isBreak {
    final t = text;
    if (danceId != null || isPurgedDance == true || t == null) return false;
    return t.trim().toLowerCase() == Program.breakSlotText.toLowerCase();
  }

  /// See [Program.copyWith] for the `clear*`-flag precedent used for the
  /// nullable fields (a set clear flag wins over any value passed for the
  /// same field).
  ProgramSlot copyWith({
    int? position,
    String? danceId,
    String? text,
    bool? isPurgedDance,
    bool? isAlt,
    String? guestCaller,
    int? walkthroughMinutes,
    int? danceMinutes,
    DateTime? performedAt,
    bool clearGuestCaller = false,
    bool clearWalkthroughMinutes = false,
    bool clearDanceMinutes = false,
    bool clearPerformedAt = false,
  }) => ProgramSlot(
    id: id,
    position: position ?? this.position,
    danceId: danceId ?? this.danceId,
    text: text ?? this.text,
    isPurgedDance:
        isPurgedDance ??
        (text != null && text != this.text ? false : this.isPurgedDance),
    isAlt: isAlt ?? this.isAlt,
    guestCaller: clearGuestCaller ? null : (guestCaller ?? this.guestCaller),
    walkthroughMinutes: clearWalkthroughMinutes
        ? null
        : (walkthroughMinutes ?? this.walkthroughMinutes),
    danceMinutes: clearDanceMinutes
        ? null
        : (danceMinutes ?? this.danceMinutes),
    performedAt: clearPerformedAt ? null : (performedAt ?? this.performedAt),
  );

  @override
  bool operator ==(Object other) =>
      other is ProgramSlot &&
      other.id == id &&
      other.position == position &&
      other.danceId == danceId &&
      other.text == text &&
      other.isPurgedDance == isPurgedDance &&
      other.isAlt == isAlt &&
      other.guestCaller == guestCaller &&
      other.walkthroughMinutes == walkthroughMinutes &&
      other.danceMinutes == danceMinutes &&
      other.performedAt == performedAt;

  @override
  int get hashCode => Object.hash(
    id,
    position,
    danceId,
    text,
    isPurgedDance,
    isAlt,
    guestCaller,
    walkthroughMinutes,
    danceMinutes,
    performedAt,
  );
}

/// A primary [ProgramSlot] together with its trailing alternates, produced by
/// [Program.grouped] so builder/perform UIs render alts indented under their
/// primary consistently (`docs/design/ux.md` §4).
@immutable
class ProgramSlotGroup {
  const ProgramSlotGroup({required this.primary, this.alternates = const []});

  /// The primary (non-alt) slot, or — for a leading/orphaned alt with no
  /// preceding primary — that alt itself, kept as a degenerate primary so the
  /// grouping stays total and every slot renders.
  final ProgramSlot primary;

  /// Alternates that follow [primary] in position order.
  final List<ProgramSlot> alternates;

  @override
  bool operator ==(Object other) =>
      other is ProgramSlotGroup &&
      other.primary == primary &&
      _listEq.equals(other.alternates, alternates);

  @override
  int get hashCode => Object.hash(primary, _listEq.hash(alternates));
}

/// [Program.calendarFlag]: the event was cancelled in the calendar (#2354).
const String calendarFlagCancelled = 'cancelled';

/// [Program.calendarFlag]: the event is no longer in the calendar (#2354).
const String calendarFlagMissing = 'missing';

/// A program (set list) for an event.
@immutable
class Program {
  Program({
    required this.id,
    required this.title,
    this.eventDate,
    this.venue,
    this.venueId,
    this.band,
    this.caller,
    this.dancerLevel,
    this.notes = '',
    this.status = ProgramStatus.draft,
    this.hideAlternates = false,
    this.dialectName,
    this.payMinorUnits,
    this.payCurrency,
    this.startMinute,
    this.endMinute,
    this.lessonMinute,
    this.arrivalMinute,
    List<ProgramSlot> slots = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.archivedAt,
    this.calendarEventKey,
    this.calendarEventFingerprint,
    this.calendarWrittenAt,
    this.calendarFlag,
    this.provenance,
  }) : slots = List.unmodifiable(
         <ProgramSlot>[...slots]
           ..sort((a, b) => a.position.compareTo(b.position)),
       ) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be non-empty');
    }
    final pay = payMinorUnits;
    final currency = payCurrency;
    if ((pay == null) != (currency == null)) {
      throw ArgumentError(
        'payMinorUnits and payCurrency must be set together or not at all',
      );
    }
    if (pay != null && pay < 0) {
      throw ArgumentError.value(pay, 'payMinorUnits', 'must be >= 0');
    }
    if (currency != null && !isValidPayCurrency(currency)) {
      throw ArgumentError.value(
        currency,
        'payCurrency',
        'must be three uppercase ASCII letters (ISO 4217)',
      );
    }
    _checkMinuteOfDay(startMinute, 'startMinute');
    _checkMinuteOfDay(endMinute, 'endMinute');
    _checkMinuteOfDay(lessonMinute, 'lessonMinute');
    _checkMinuteOfDay(arrivalMinute, 'arrivalMinute');
  }

  /// The number of minutes in a day: a time of day is `0` (midnight) to
  /// `minutesPerDay - 1` (11:59 pm).
  static const int minutesPerDay = 24 * 60;

  /// Whether [minute] is a time of day this model accepts: a whole number of
  /// minutes after midnight, `0`–`1439`.
  static bool isValidMinuteOfDay(int minute) =>
      minute >= 0 && minute < minutesPerDay;

  static void _checkMinuteOfDay(int? minute, String name) {
    if (minute != null && !isValidMinuteOfDay(minute)) {
      throw ArgumentError.value(minute, name, 'must be 0-1439');
    }
  }

  /// Whether [code] has the shape of an ISO 4217 currency code: exactly three
  /// uppercase ASCII letters. Shape only — the list of assigned codes changes
  /// and is not consulted, so a code this build has never heard of is kept.
  static bool isValidPayCurrency(String code) =>
      RegExp(r'^[A-Z]{3}$').hasMatch(code);

  final String id;
  final String title;
  final DateTime? eventDate;
  final String? venue;

  /// Optional reference to a first-class venue entity (`venues.id`; see
  /// `Venue`). A soft reference — not a DB foreign key — kept independently of
  /// the free-text [venue] label so the two coexist non-destructively: the
  /// display layer prefers a resolvable [venueId], falling back to [venue]
  /// (`docs/design/domain-model.md`). `null` when the program has no linked
  /// venue entity (the default, and every program before schema v14).
  final String? venueId;

  /// The band playing the event.
  final String? band;

  /// The primary/host caller for the event.
  final String? caller;

  /// The event's overall dancer level, kept as nullable free-text for now.
  /// A first-class dance-level enum is a separate concern (ROADMAP 4b.1).
  final String? dancerLevel;

  final String notes;
  final ProgramStatus status;

  /// When true, alternate (`isAlt`) slots are omitted from the program's
  /// **output** — the plain-text set list, PDF, and on-screen summary set list
  /// (see [outputGrouped]). Per-program and persisted (CC parity:
  /// `SetList_HideALT`). The builder editor and Perform mode ignore this flag
  /// and always show every slot; the stored slots are never mutated.
  final bool hideAlternates;

  /// Name of the dialect Perform uses for this program, or `null` to follow the
  /// application dialect (the default, and every program before schema v37).
  /// Applies to that program's Perform view only — the editor preview, summary
  /// and exports keep the application dialect. A soft reference by name,
  /// resolved with `Dialect.resolveByName` when Perform opens: a name that no
  /// longer resolves silently falls back to the application dialect, so it is
  /// never validated, and not cleared when a dialect is deleted; a rename is
  /// carried to the program by `ProgramRepository.renameDialect`.
  final String? dialectName;

  /// What the caller is paid for this program, in the currency's minor units
  /// (cents for USD, whole yen for JPY), or `null` when no pay is recorded
  /// (the default, and every program before schema v38). Never negative; set
  /// together with [payCurrency] or not at all. Private to the caller's own
  /// bookkeeping but shareable across their devices and in archives; it is not
  /// part of the shared program text or PDF.
  final int? payMinorUnits;

  /// ISO 4217 code (three uppercase letters) that [payMinorUnits] is
  /// denominated in; `null` exactly when [payMinorUnits] is.
  final String? payCurrency;

  /// When the dance starts, as minutes after midnight (`0`–`1439`), or `null`
  /// when not recorded (the default, and every program before schema v42).
  ///
  /// [startMinute], [endMinute], [lessonMinute] and [arrivalMinute] are
  /// wall-clock times at the hall on [eventDate], with **no time zone**: a
  /// 7:30 pm start stays 7:30 pm wherever the device is. Each is optional on
  /// its own, and each can be set without an [eventDate]. An [endMinute]
  /// earlier than [startMinute] means the next day ([endsNextDay]).
  final int? startMinute;

  /// When the dance ends, as minutes after midnight; see [startMinute].
  final int? endMinute;

  /// When the beginner lesson before the dance starts, as minutes after
  /// midnight; see [startMinute].
  final int? lessonMinute;

  /// When the caller needs to be at the hall, as minutes after midnight; see
  /// [startMinute]. The caller's own logistics: it travels in Device Sync,
  /// backups and program share files, but the set-list text and PDF leave it
  /// out.
  final int? arrivalMinute;

  /// Whether the dance ends on the day after it starts: both [startMinute]
  /// and [endMinute] are set and the end is earlier than the start. An end
  /// equal to the start is the same day.
  bool get endsNextDay {
    final start = startMinute;
    final end = endMinute;
    return start != null && end != null && end < start;
  }

  /// Whether any of the four times is set.
  bool get hasTimes =>
      startMinute != null ||
      endMinute != null ||
      lessonMinute != null ||
      arrivalMinute != null;

  /// Slots, always ordered by position.
  final List<ProgramSlot> slots;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// When the caller archived this program, or `null` when it is not archived
  /// (the default, and every program before schema v42).
  ///
  /// Archiving only hides the program: the Programs list leaves it out unless
  /// "Show archived" is on, and the Add to program sheet never offers it. It
  /// still counts toward every dance's calling history, Last called and the
  /// venue counts, and search still finds it. Unlike [deletedAt] it never
  /// expires. It travels in Device Sync and the caller's own backups, but not in
  /// program share files (`sanitizeProgramForShare`), so a recipient always
  /// gets an unarchived program.
  final DateTime? archivedAt;

  /// The calendar event this program was imported from (#2352): a SHA-256
  /// digest of the event's `UID` and recurrence id (`calendarEventKey` in
  /// `ical_feed.dart`), never the `UID` itself. A later calendar import
  /// matches on it and does not offer the event again. It travels in Device
  /// Sync, so another device recognises the import too, and in the caller's
  /// own backups, but not in share files (`sanitizeProgramForShare`). Null
  /// for a program not imported from a calendar.
  final String? calendarEventKey;

  /// What the calendar import last wrote from the event (#2354): a
  /// per-field hash of its title, date and first location segment
  /// (`calendarEventFingerprint`). A later import compares the event's
  /// current fingerprint with it to see what changed upstream. Null for a
  /// program not imported from a calendar, or imported before #2354.
  final String? calendarEventFingerprint;

  /// The [updatedAt] the calendar import last wrote (#2354). While the
  /// program is still a Draft and [updatedAt] still equals it, the caller has
  /// not touched it ([isUntouchedCalendarDraft]), so an upstream change is
  /// offered ticked. Any edit, here or synced from another device, moves
  /// [updatedAt] on.
  final DateTime? calendarWrittenAt;

  /// Why the calendar flags this program (#2354): [calendarFlagCancelled],
  /// [calendarFlagMissing], or null. Stored as a string and read leniently,
  /// so a value a later build adds reads as a generic flag rather than
  /// refusing the program. Never deletes or edits anything: it is a label.
  final String? calendarFlag;

  /// Whether a calendar import created this program and the caller has not
  /// touched it since: still a Draft, and [updatedAt] is the stamp the import
  /// wrote. Conservative on purpose: linking a venue or adding a slot counts.
  bool get isUntouchedCalendarDraft =>
      status == ProgramStatus.draft &&
      calendarWrittenAt != null &&
      calendarWrittenAt == updatedAt;

  /// Import provenance: where this program came from, keyed on
  /// `(source, externalId)`. For a CC `.USR` import the key makes a re-import
  /// dedupe onto the same program rather than create a duplicate. A program
  /// received in a shared file (`json`) records its origin only: re-receiving
  /// it adds a new program (F6). `null` for user-created programs, which never
  /// dedupe. Mirrors [Dance.provenance]; like Dance, it is metadata *about the
  /// import* and is deliberately excluded from value equality (`==`/[hashCode]).
  final Provenance? provenance;

  bool get isDeleted => deletedAt != null;

  /// Whether the program is archived ([archivedAt] is set).
  bool get isArchived => archivedAt != null;

  /// Canonical text of a **break** slot. The one-tap "insert break" affordance
  /// writes exactly this so section derivation ([sectionAtIndex]) keys off it without
  /// the caller hand-typing "break"; [ProgramSlot.isBreak] recognises it
  /// case-insensitively (so a hand-typed "break" still counts).
  static const String breakSlotText = 'Break';

  /// Index into [slots] of the first [ProgramSlot.isBreak] slot, or `null` when
  /// the program has no break. Because [slots] is always position-ordered, this
  /// is the first divider from which numbered sections are derived.
  int? get firstBreakSlotIndex {
    final index = slots.indexWhere((s) => s.isBreak);
    return index < 0 ? null : index;
  }

  /// How many dances the program is planned for: every slot except alternates
  /// ([ProgramSlot.isAlt]) and the break ([ProgramSlot.isBreak]).
  ///
  /// Text-only slots that stand in for a dance ("bouncy", "set ender") and
  /// purged-dance captions are counted; an orphaned leading alternate is not,
  /// because it is still an alternate. [slots]`.length` is the row count, which
  /// this deliberately is not.
  int get plannedDanceCount => plannedDanceCountOf(slots);

  /// [plannedDanceCount] for a working slot list, such as the builder's
  /// unsaved edits, without constructing a [Program].
  static int plannedDanceCountOf(Iterable<ProgramSlot> slots) =>
      slots.where((s) => s.isPlannedDance).length;

  /// How many slots hold [danceId], **alternates included** (N3-6): the
  /// "will I add this twice?" count behind the add-to-program sheet's
  /// "In this program" marker and the builder picker's "in program ×N".
  ///
  /// Deliberately not the calling-history rule, under which an alternate counts
  /// only once performed. Break and free-text slots carry no dance id and never
  /// match, so a text slot that names the dance is not detected.
  int danceSlotCount(String danceId) => danceSlotCountsOf(slots)[danceId] ?? 0;

  /// [danceSlotCount] for every dance in a working slot list, such as the
  /// builder's unsaved edits, without constructing a [Program]. Dances absent
  /// from [slots] are absent from the map.
  static Map<String, int> danceSlotCountsOf(Iterable<ProgramSlot> slots) {
    final counts = <String, int>{};
    for (final slot in slots) {
      final danceId = slot.danceId;
      if (danceId == null) continue;
      counts[danceId] = (counts[danceId] ?? 0) + 1;
    }
    return counts;
  }

  /// The set-list number of each slot in a **position-ordered** [slots] list,
  /// as a parallel list (same length/order): planned dances
  /// ([ProgramSlot.isPlannedDance]) are numbered `1..n`, and alternates and
  /// the break are `null`. The highest number is therefore always
  /// [plannedDanceCountOf] the same slots (GIG-10).
  static List<int?> danceNumbersForSlots(List<ProgramSlot> slots) {
    var number = 0;
    return List<int?>.generate(
      slots.length,
      (i) => slots[i].isPlannedDance ? ++number : null,
      growable: false,
    );
  }

  /// [slots] without the slot at [index]. When that slot is the primary of an
  /// alternate group, its first alternate takes its place as the primary and
  /// any further alternates stay with it (LIFE-10); without this the group's
  /// alternates would silently join the slot above (see
  /// [alternateGroupsForSlots]). Positions are left for the caller to
  /// renumber. Shared by cutting a slot and moving one.
  static List<ProgramSlot> removeSlotPromotingAlternate(
    List<ProgramSlot> slots,
    int index,
  ) {
    final promoted = alternatePromotedByRemoving(slots, index);
    final next = [...slots];
    if (promoted != null) {
      next[promoted] = next[promoted].copyWith(isAlt: false);
    }
    next.removeAt(index);
    return next;
  }

  /// The alternate group holding the slot at [index] in a **position-ordered**
  /// [slots] list, as the half-open range `[start, end)`: the group's primary
  /// and every alternate after it, by the rule [grouped] and
  /// [alternateGroupsForSlots] use. An alternate's group is its primary's; a
  /// break, a note, or a leading/orphaned alternate with no primary above it
  /// starts its own group.
  static ({int start, int end}) alternateGroupRange(
    List<ProgramSlot> slots,
    int index,
  ) {
    RangeError.checkValidIndex(index, slots, 'index');
    var start = index;
    while (start > 0 && slots[start].isAlt) {
      start--;
    }
    var end = start + 1;
    while (end < slots.length && slots[end].isAlt) {
      end++;
    }
    return (start: start, end: end);
  }

  /// [slots] with [slot] inserted as a **primary** just before ([after]
  /// false) or just after ([after] true) the alternate group holding the slot
  /// at [index] ([alternateGroupRange]): before the group's primary, or after
  /// its last alternate. Inserting at the raw index instead could land the new
  /// dance among a group's alternates, splitting the group or making its
  /// alternates belong to the new dance (#2339). [slot] is inserted with
  /// `isAlt` cleared. Positions are left for the caller to renumber.
  ///
  /// The one group with no primary is a leading run of orphaned alternates
  /// (`orphaned_alt`, reachable by dragging an alternate to the top). Inserting
  /// before it would make the run the new dance's alternates, so the run's
  /// first slot is promoted to a planned primary instead: it loses its ALT
  /// badge, gains a dance number, and is no longer hidden by
  /// `hideAlternates`. The rest of the run stays its alternates.
  static List<ProgramSlot> insertSlotAtGroupBoundary(
    List<ProgramSlot> slots,
    int index,
    ProgramSlot slot, {
    required bool after,
  }) {
    final range = alternateGroupRange(slots, index);
    final next = [...slots];
    if (!after && next[range.start].isAlt) {
      next[range.start] = next[range.start].copyWith(isAlt: false);
    }
    return next
      ..insert(after ? range.end : range.start, slot.copyWith(isAlt: false));
  }

  /// [slots] with the slot at [oldIndex] moved to [newIndex], where
  /// [newIndex] is the insertion index after the removal (Flutter's
  /// `onReorderItem` convention). A moved primary leaves its alternates behind
  /// with the first promoted in its place, as [removeSlotPromotingAlternate]
  /// does; a drop inside that promoted group's alternates lands after them,
  /// so the group stays whole rather than its later alternates joining the
  /// moved slot. Positions are left for the caller to renumber.
  static List<ProgramSlot> moveSlotPromotingAlternate(
    List<ProgramSlot> slots,
    int oldIndex,
    int newIndex,
  ) {
    final item = slots[oldIndex];
    final promoted = alternatePromotedByRemoving(slots, oldIndex);
    final next = removeSlotPromotingAlternate(slots, oldIndex);
    var target = newIndex.clamp(0, next.length);
    if (promoted != null && target > oldIndex) {
      // The promoted slot now sits at oldIndex; its alternates follow it.
      var groupEnd = oldIndex + 1;
      while (groupEnd < next.length && next[groupEnd].isAlt) {
        groupEnd++;
      }
      if (target < groupEnd) target = groupEnd;
    }
    next.insert(target, item);
    return next;
  }

  /// Index into [slots] of the alternate that
  /// [removeSlotPromotingAlternate] would promote when removing [index], or
  /// `null` when nothing would be promoted: the slot is itself an alternate,
  /// or no alternate follows it.
  static int? alternatePromotedByRemoving(List<ProgramSlot> slots, int index) {
    if (index < 0 || index + 1 >= slots.length) return null;
    if (slots[index].isAlt || !slots[index + 1].isAlt) return null;
    return index + 1;
  }

  /// Whether the program contains a break slot (and therefore has derived
  /// sections).
  bool get hasBreak => firstBreakSlotIndex != null;

  /// The derived numbered section for the slot at [index] in [slots].
  ///
  /// Sections are numbered from 1 and increment after every break. Returns
  /// `null` when there is no break (no sections are defined), for any break
  /// slot itself, and for any out-of-range [index].
  int? sectionAtIndex(int index) {
    if (index < 0 || index >= slots.length) return null;
    if (firstBreakSlotIndex == null || slots[index].isBreak) return null;
    var section = 1;
    for (var i = 0; i < index; i++) {
      if (slots[i].isBreak) section++;
    }
    return section;
  }

  /// Derived numbered section for each slot in a **position-ordered** [slots]
  /// list, as a parallel list (same length/order). Lets callers classify a
  /// working slot list — e.g. the program editor's in-progress edits — without
  /// constructing a [Program]. Uses the same rules as [sectionAtIndex].
  static List<int?> sectionsForSlots(List<ProgramSlot> slots) {
    if (!slots.any((slot) => slot.isBreak)) {
      return List<int?>.filled(slots.length, null, growable: false);
    }
    var section = 1;
    return List<int?>.generate(slots.length, (i) {
      if (slots[i].isBreak) {
        section++;
        return null;
      }
      return section;
    }, growable: false);
  }

  /// The alternate group of each slot in a **position-ordered** [slots] list,
  /// as a parallel list (same length/order): every slot in one group is a
  /// mutually exclusive choice for the same program position. Ids are
  /// consecutive from 0. Uses exactly the rule [grouped] does — an `isAlt` slot
  /// joins the nearest preceding non-alt slot's group (which may be a text-only
  /// slot), and a leading/orphaned alt starts its own group — so the two never
  /// disagree about which slots are alternatives to each other.
  static List<int> alternateGroupsForSlots(List<ProgramSlot> slots) {
    var group = -1;
    return List<int>.generate(slots.length, (i) {
      if (!slots[i].isAlt || group < 0) group++;
      return group;
    }, growable: false);
  }

  /// Groups [slots] into primaries each carrying their trailing alternates,
  /// so builder/perform UIs render an alt indented under its primary
  /// (`docs/design/ux.md` §4). The documented invariant is that an `isAlt`
  /// slot alternates for the nearest preceding non-alt slot in position order.
  ///
  /// This is **total**: it never throws and every slot appears in exactly one
  /// group. A leading/orphaned alt (no preceding primary — a non-blocking
  /// warning surfaced by [validate], not an error) starts its own group as a
  /// degenerate primary so it still renders.
  List<ProgramSlotGroup> get grouped {
    final groups = <ProgramSlotGroup>[];
    var current = <ProgramSlot>[];
    for (final slot in slots) {
      if (!slot.isAlt || current.isEmpty) {
        if (current.isNotEmpty) {
          groups.add(
            ProgramSlotGroup(
              primary: current.first,
              alternates: List.unmodifiable(current.sublist(1)),
            ),
          );
        }
        current = [slot];
      } else {
        current.add(slot);
      }
    }
    if (current.isNotEmpty) {
      groups.add(
        ProgramSlotGroup(
          primary: current.first,
          alternates: List.unmodifiable(current.sublist(1)),
        ),
      );
    }
    return List.unmodifiable(groups);
  }

  /// The [grouped] view used for **output** (plain-text set list, PDF, summary):
  /// identical to [grouped] except that, when [hideAlternates] is set, each
  /// group's [ProgramSlotGroup.alternates] are dropped so only primaries render.
  /// The planned dances keep the same numbers either way: only a
  /// [ProgramSlot.isPlannedDance] primary is numbered, so dropping alternates
  /// changes no number. The builder/Perform UIs use
  /// [grouped] directly and are unaffected by the flag.
  List<ProgramSlotGroup> get outputGrouped {
    if (!hideAlternates) return grouped;
    return List.unmodifiable([
      for (final group in grouped)
        // Drop each group's trailing alternates, and drop the group entirely
        // when its primary is itself an alt (a leading/orphaned ALT, which
        // [grouped] keeps as a degenerate primary) so no `isAlt` slot renders.
        if (!group.primary.isAlt) ProgramSlotGroup(primary: group.primary),
    ]);
  }

  /// Runs warning-level validation. Structural invariants are enforced at
  /// construction and never appear here; softer concerns surface as warnings
  /// (mirrors [Dance.validate], per the domain-model "warnings, not hard
  /// errors" philosophy). Currently flags leading/orphaned alternates — an
  /// `isAlt` slot with no preceding non-alt primary — which the builder UI
  /// surfaces so the user can fix the ordering.
  List<ValidationIssue> validate() {
    final issues = <ValidationIssue>[];
    var sawPrimary = false;
    for (final slot in slots) {
      if (slot.isAlt) {
        if (!sawPrimary) {
          // The localized message refers to the slot by its 1-based position
          // (and text, when present) rather than the internal id, which is
          // typically an opaque UUID. The English `message` below stays for
          // diagnostics/tests; the UI renders the localized form from `data`.
          final label = slot.text == null ? '' : ' ("${slot.text}")';
          issues.add(
            ValidationIssue(
              severity: ValidationSeverity.warning,
              code: 'orphaned_alt',
              message:
                  'alternate at position ${slot.position + 1}$label has no '
                  'preceding primary slot',
              data: {'position': slot.position + 1, 'text': slot.text},
            ),
          );
        }
      } else {
        sawPrimary = true;
      }
    }
    return issues;
  }

  /// The `?? this.x` pattern cannot distinguish "leave unchanged" from "set to
  /// null" for nullable fields. To clear a nullable field, pass the matching
  /// `clear*` flag (mirrors the [clearDeletedAt] precedent); a set flag wins
  /// over any value passed for the same field.
  Program copyWith({
    String? title,
    DateTime? eventDate,
    String? venue,
    String? venueId,
    String? band,
    String? caller,
    String? dancerLevel,
    String? notes,
    ProgramStatus? status,
    bool? hideAlternates,
    String? dialectName,
    int? payMinorUnits,
    String? payCurrency,
    int? startMinute,
    int? endMinute,
    int? lessonMinute,
    int? arrivalMinute,
    List<ProgramSlot>? slots,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? archivedAt,
    String? calendarEventKey,
    String? calendarEventFingerprint,
    DateTime? calendarWrittenAt,
    String? calendarFlag,
    Provenance? provenance,
    bool clearEventDate = false,
    bool clearVenue = false,
    bool clearVenueId = false,
    bool clearBand = false,
    bool clearCaller = false,
    bool clearDancerLevel = false,
    bool clearDialectName = false,
    bool clearDeletedAt = false,
    bool clearArchivedAt = false,
    bool clearCalendarEventKey = false,
    bool clearCalendarFlag = false,
    bool clearPay = false,
    bool clearStartMinute = false,
    bool clearEndMinute = false,
    bool clearLessonMinute = false,
    bool clearArrivalMinute = false,
    bool clearProvenance = false,
  }) => Program(
    id: id,
    title: title ?? this.title,
    eventDate: clearEventDate ? null : (eventDate ?? this.eventDate),
    venue: clearVenue ? null : (venue ?? this.venue),
    venueId: clearVenueId ? null : (venueId ?? this.venueId),
    band: clearBand ? null : (band ?? this.band),
    caller: clearCaller ? null : (caller ?? this.caller),
    dancerLevel: clearDancerLevel ? null : (dancerLevel ?? this.dancerLevel),
    notes: notes ?? this.notes,
    status: status ?? this.status,
    hideAlternates: hideAlternates ?? this.hideAlternates,
    dialectName: clearDialectName ? null : (dialectName ?? this.dialectName),
    payMinorUnits: clearPay ? null : (payMinorUnits ?? this.payMinorUnits),
    payCurrency: clearPay ? null : (payCurrency ?? this.payCurrency),
    startMinute: clearStartMinute ? null : (startMinute ?? this.startMinute),
    endMinute: clearEndMinute ? null : (endMinute ?? this.endMinute),
    lessonMinute: clearLessonMinute
        ? null
        : (lessonMinute ?? this.lessonMinute),
    arrivalMinute: clearArrivalMinute
        ? null
        : (arrivalMinute ?? this.arrivalMinute),
    slots: slots ?? this.slots,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    // Clearing the key clears everything the calendar import keeps with it.
    calendarEventKey: clearCalendarEventKey
        ? null
        : (calendarEventKey ?? this.calendarEventKey),
    calendarEventFingerprint: clearCalendarEventKey
        ? null
        : (calendarEventFingerprint ?? this.calendarEventFingerprint),
    calendarWrittenAt: clearCalendarEventKey
        ? null
        : (calendarWrittenAt ?? this.calendarWrittenAt),
    calendarFlag: clearCalendarEventKey || clearCalendarFlag
        ? null
        : (calendarFlag ?? this.calendarFlag),
    provenance: clearProvenance ? null : (provenance ?? this.provenance),
  );

  /// Deep copy for "duplicate program": fresh ids everywhere, draft status,
  /// performance history, event date and pay cleared; the times are kept. [newSlotId] mints an id per
  /// copied slot.
  /// Provenance is dropped (the copy is the user's own record, not an import),
  /// mirroring [Dance.duplicate]. The copy is never archived: it is for a new
  /// event, so it belongs in the Programs list even when its source does not.
  /// Nor does it keep [calendarEventKey]: it was not imported from that event,
  /// and a calendar import must keep recognising the original alone.
  Program duplicate({
    required String newId,
    required String Function() newSlotId,
    required DateTime now,
    String? newTitle,
  }) => Program(
    id: newId,
    title: newTitle ?? title,
    // The event date is deliberately not copied, for the same reason as pay
    // below: a duplicate is for a different event. Copying it would put a
    // second calling-history entry on the original's date (LIFE-7).
    venue: venue,
    venueId: venueId,
    band: band,
    caller: caller,
    dancerLevel: dancerLevel,
    notes: notes,
    status: ProgramStatus.draft,
    hideAlternates: hideAlternates,
    dialectName: dialectName,
    // Pay is deliberately not copied: it belongs to one event, and a duplicate
    // is for a different one.
    // The times are copied: the date changes between events, but the
    // schedule usually does not (#2350).
    startMinute: startMinute,
    endMinute: endMinute,
    lessonMinute: lessonMinute,
    arrivalMinute: arrivalMinute,
    slots: [
      for (final s in slots)
        ProgramSlot(
          id: newSlotId(),
          position: s.position,
          danceId: s.danceId,
          text: s.text,
          isPurgedDance: s.isPurgedDance,
          isAlt: s.isAlt,
          guestCaller: s.guestCaller,
          walkthroughMinutes: s.walkthroughMinutes,
          danceMinutes: s.danceMinutes,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  /// Returns a copy in which every **primary dance-linked** slot (`danceId !=
  /// null`, not an alternate) that has no [ProgramSlot.performedAt] is stamped
  /// performed at the first
  /// unused stored timestamp at or after this program's [eventDate] when set,
  /// else at [fallback].
  ///
  /// This backs the "auto-stamp when a program's status becomes performed"
  /// behaviour (issue #356): a program's *status* being performed and its
  /// per-slot calling history should agree, since dance calling history is
  /// derived from per-slot `performedAt` (see [ProgramSlot.performedAt]).
  ///
  /// - **Dance-linked only:** free-text/note/break slots aren't dances and can
  ///   never contribute to calling history, so they're left untouched.
  /// - **Primaries only:** alternate slots are left unstamped, as **Mark all
  ///   performed** leaves them ([ProgramSlot.isBulkMarkPerformedTarget]). The
  ///   maintainer ruled that an alternate counts only once marked performed and
  ///   that Mark all performed skips alternates (2026-10-28); applying the same
  ///   skip here is an inference from that ruling, because this is the same bulk
  ///   stamp reached through the status, not a separately ruled behaviour.
  /// - **Idempotent:** a slot that already has a `performedAt` (e.g. a
  ///   manually-set date) is never overwritten.
  /// - **Pure:** callers choose the timestamp — typically the program's
  ///   [eventDate] when set, else the status-change time — so this stays
  ///   deterministic and Flutter-free. [fallback] must be UTC.
  ///
  /// When nothing needs stamping the same instance is returned unchanged (no
  /// spurious `updatedAt` churn is introduced here; callers manage that).
  Program stampDanceSlotsPerformed({required DateTime fallback}) {
    final stamp = nextStoredTimestamp(
      now: eventDate ?? fallback,
      current: slots.map((s) => s.performedAt),
    );
    var changed = false;
    final next = <ProgramSlot>[];
    for (final s in slots) {
      if (s.isBulkMarkPerformedTarget) {
        next.add(s.copyWith(performedAt: stamp));
        changed = true;
      } else {
        next.add(s);
      }
    }
    if (!changed) return this;
    return copyWith(slots: next);
  }

  @override
  bool operator ==(Object other) =>
      other is Program &&
      other.id == id &&
      other.title == title &&
      other.eventDate == eventDate &&
      other.venue == venue &&
      other.venueId == venueId &&
      other.band == band &&
      other.caller == caller &&
      other.dancerLevel == dancerLevel &&
      other.notes == notes &&
      other.status == status &&
      other.hideAlternates == hideAlternates &&
      other.dialectName == dialectName &&
      other.payMinorUnits == payMinorUnits &&
      other.payCurrency == payCurrency &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.lessonMinute == lessonMinute &&
      other.arrivalMinute == arrivalMinute &&
      _listEq.equals(other.slots, slots) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.archivedAt == archivedAt &&
      other.calendarEventKey == calendarEventKey &&
      other.calendarEventFingerprint == calendarEventFingerprint &&
      other.calendarWrittenAt == calendarWrittenAt &&
      other.calendarFlag == calendarFlag;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);
}
