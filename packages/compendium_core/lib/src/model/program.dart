import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

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
  }

  final String id;
  final int position;
  final String? danceId;
  final String? text;

  /// Alternate dance, decided at event time.
  final bool isAlt;

  /// Set when the slot was actually called; feeds dance calling history
  /// (which is derived by query, never stored on the dance).
  final DateTime? performedAt;

  ProgramSlot copyWith({
    int? position,
    String? danceId,
    String? text,
    bool? isAlt,
    DateTime? performedAt,
  }) => ProgramSlot(
    id: id,
    position: position ?? this.position,
    danceId: danceId ?? this.danceId,
    text: text ?? this.text,
    isAlt: isAlt ?? this.isAlt,
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
      other.performedAt == performedAt;

  @override
  int get hashCode =>
      Object.hash(id, position, danceId, text, isAlt, performedAt);
}

/// A program (set list) for an event.
@immutable
class Program {
  Program({
    required this.id,
    required this.title,
    this.eventDate,
    this.venue,
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
  final String notes;
  final ProgramStatus status;

  /// Slots, always ordered by position.
  final List<ProgramSlot> slots;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Program copyWith({
    String? title,
    DateTime? eventDate,
    String? venue,
    String? notes,
    ProgramStatus? status,
    List<ProgramSlot>? slots,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Program(
    id: id,
    title: title ?? this.title,
    eventDate: eventDate ?? this.eventDate,
    venue: venue ?? this.venue,
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
      other.notes == notes &&
      other.status == status &&
      _listEq.equals(other.slots, slots) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);
}
