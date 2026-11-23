import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// One of a program's four times of day (#2350), in the order the editor and
/// summary show them.
enum ProgramTimeField { start, end, lesson, arrival }

/// A program's four optional times of day, each in minutes after midnight
/// (`0`–`1439`): [Program.startMinute], [Program.endMinute],
/// [Program.lessonMinute] and [Program.arrivalMinute], as one value the
/// program editor can hold, compare and merge.
@immutable
class ProgramTimes {
  const ProgramTimes({this.start, this.end, this.lesson, this.arrival});

  /// [program]'s four times.
  ProgramTimes.of(Program program)
    : start = program.startMinute,
      end = program.endMinute,
      lesson = program.lessonMinute,
      arrival = program.arrivalMinute;

  final int? start;
  final int? end;
  final int? lesson;
  final int? arrival;

  /// The time for [field], or `null` when it is not set.
  int? operator [](ProgramTimeField field) => switch (field) {
    ProgramTimeField.start => start,
    ProgramTimeField.end => end,
    ProgramTimeField.lesson => lesson,
    ProgramTimeField.arrival => arrival,
  };

  /// A copy with [field] set to [minute], or cleared when [minute] is `null`.
  ProgramTimes withField(ProgramTimeField field, int? minute) => ProgramTimes(
    start: field == ProgramTimeField.start ? minute : start,
    end: field == ProgramTimeField.end ? minute : end,
    lesson: field == ProgramTimeField.lesson ? minute : lesson,
    arrival: field == ProgramTimeField.arrival ? minute : arrival,
  );

  /// [program] carrying exactly these times, clearing any that are `null`.
  Program applyTo(Program program) => program.copyWith(
    startMinute: start,
    clearStartMinute: start == null,
    endMinute: end,
    clearEndMinute: end == null,
    lessonMinute: lesson,
    clearLessonMinute: lesson == null,
    arrivalMinute: arrival,
    clearArrivalMinute: arrival == null,
  );

  /// The three-way merge the program editor saves with, one field at a time:
  /// a field the person changed since [baseline] (what the editor last took
  /// from storage) takes their value from [local]; any other takes [stored],
  /// so a time another device synced while the editor was open is not
  /// overwritten by the editor's stale copy. The same rule as the editor's
  /// venue link.
  static ProgramTimes merge({
    required ProgramTimes baseline,
    required ProgramTimes local,
    required ProgramTimes stored,
  }) {
    var merged = stored;
    for (final field in ProgramTimeField.values) {
      if (local[field] != baseline[field]) {
        merged = merged.withField(field, local[field]);
      }
    }
    return merged;
  }

  @override
  bool operator ==(Object other) =>
      other is ProgramTimes &&
      other.start == start &&
      other.end == end &&
      other.lesson == lesson &&
      other.arrival == arrival;

  @override
  int get hashCode => Object.hash(start, end, lesson, arrival);
}
