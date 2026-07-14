import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'enums.dart';

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
    this.isAlt = false,
    this.guestCaller,
    this.plannedMinutes,
    this.performedAt,
  }) {
    if (danceId == null && text == null) {
      throw ArgumentError(
        'a slot requires a danceId, text, or both',
        'danceId/text',
      );
    }
    if (position < 0) {
      throw ArgumentError.value(position, 'position', 'must be >= 0');
    }
    if (plannedMinutes != null && plannedMinutes! < 0) {
      throw ArgumentError.value(
        plannedMinutes,
        'plannedMinutes',
        'must be >= 0',
      );
    }
  }

  final String id;
  final int position;
  final String? danceId;
  final String? text;

  /// Alternate dance, decided at event time.
  final bool isAlt;

  /// Guest caller for this slot, when someone other than the program's host
  /// caller leads it. Structured (not folded into [text]).
  final String? guestCaller;

  /// Planned length of the slot in minutes (CC `SetItem.Time`). Structured,
  /// distinct from any free-text timing note in [text]; `>= 0` when present.
  final int? plannedMinutes;

  /// Set when the slot was actually called; feeds dance calling history
  /// (which is derived by query, never stored on the dance).
  final DateTime? performedAt;

  /// See [Program.copyWith] for the `clear*`-flag precedent used for the
  /// nullable fields (a set clear flag wins over any value passed for the
  /// same field).
  ProgramSlot copyWith({
    int? position,
    String? danceId,
    String? text,
    bool? isAlt,
    String? guestCaller,
    int? plannedMinutes,
    DateTime? performedAt,
    bool clearGuestCaller = false,
    bool clearPlannedMinutes = false,
  }) => ProgramSlot(
    id: id,
    position: position ?? this.position,
    danceId: danceId ?? this.danceId,
    text: text ?? this.text,
    isAlt: isAlt ?? this.isAlt,
    guestCaller: clearGuestCaller ? null : (guestCaller ?? this.guestCaller),
    plannedMinutes: clearPlannedMinutes
        ? null
        : (plannedMinutes ?? this.plannedMinutes),
    performedAt: performedAt ?? this.performedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ProgramSlot &&
      other.id == id &&
      other.position == position &&
      other.danceId == danceId &&
      other.text == text &&
      other.isAlt == isAlt &&
      other.guestCaller == guestCaller &&
      other.plannedMinutes == plannedMinutes &&
      other.performedAt == performedAt;

  @override
  int get hashCode => Object.hash(
    id,
    position,
    danceId,
    text,
    isAlt,
    guestCaller,
    plannedMinutes,
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

/// A program (set list) for an event.
@immutable
class Program {
  Program({
    required this.id,
    required this.title,
    this.eventDate,
    this.venue,
    this.band,
    this.caller,
    this.dancerLevel,
    this.notes = '',
    this.status = ProgramStatus.draft,
    List<ProgramSlot> slots = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : slots = List.unmodifiable(
         [...slots]..sort((a, b) => a.position.compareTo(b.position)),
       ) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be non-empty');
    }
  }

  final String id;
  final String title;
  final DateTime? eventDate;
  final String? venue;

  /// The band playing the event.
  final String? band;

  /// The primary/host caller for the event.
  final String? caller;

  /// The event's overall dancer level, kept as nullable free-text for now.
  /// A first-class dance-level enum is a separate concern (ROADMAP 4b.1).
  final String? dancerLevel;

  final String notes;
  final ProgramStatus status;

  /// Slots, always ordered by position.
  final List<ProgramSlot> slots;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

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
          issues.add(
            ValidationIssue(
              severity: ValidationSeverity.warning,
              code: 'orphaned_alt',
              message:
                  'alternate slot "${slot.id}" has no preceding primary slot',
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
    String? band,
    String? caller,
    String? dancerLevel,
    String? notes,
    ProgramStatus? status,
    List<ProgramSlot>? slots,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearEventDate = false,
    bool clearVenue = false,
    bool clearBand = false,
    bool clearCaller = false,
    bool clearDancerLevel = false,
    bool clearDeletedAt = false,
  }) => Program(
    id: id,
    title: title ?? this.title,
    eventDate: clearEventDate ? null : (eventDate ?? this.eventDate),
    venue: clearVenue ? null : (venue ?? this.venue),
    band: clearBand ? null : (band ?? this.band),
    caller: clearCaller ? null : (caller ?? this.caller),
    dancerLevel: clearDancerLevel ? null : (dancerLevel ?? this.dancerLevel),
    notes: notes ?? this.notes,
    status: status ?? this.status,
    slots: slots ?? this.slots,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  /// Deep copy for "duplicate program": fresh ids everywhere, draft status,
  /// performance history cleared. [newSlotId] mints an id per copied slot.
  Program duplicate({
    required String newId,
    required String Function() newSlotId,
    required DateTime now,
    String? newTitle,
  }) => Program(
    id: newId,
    title: newTitle ?? title,
    eventDate: eventDate,
    venue: venue,
    band: band,
    caller: caller,
    dancerLevel: dancerLevel,
    notes: notes,
    status: ProgramStatus.draft,
    slots: [
      for (final s in slots)
        ProgramSlot(
          id: newSlotId(),
          position: s.position,
          danceId: s.danceId,
          text: s.text,
          isAlt: s.isAlt,
          guestCaller: s.guestCaller,
          plannedMinutes: s.plannedMinutes,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  @override
  bool operator ==(Object other) =>
      other is Program &&
      other.id == id &&
      other.title == title &&
      other.eventDate == eventDate &&
      other.venue == venue &&
      other.band == band &&
      other.caller == caller &&
      other.dancerLevel == dancerLevel &&
      other.notes == notes &&
      other.status == status &&
      _listEq.equals(other.slots, slots) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);
}
