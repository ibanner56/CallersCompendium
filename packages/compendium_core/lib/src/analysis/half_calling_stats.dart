import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../model/program.dart';

/// First/second-half positional calling stats for a single dance, aggregated
/// across every program that includes it (issue #378). Derived — like calling
/// history itself — never stored.
///
/// "Half" reuses the program's derived first/second half (the merged
/// [Program.halvesForSlots] / [Program.halfAtIndex]): everything before a
/// program's first break slot is the first half, everything after is the
/// second; a program with no break contributes nothing here.
///
/// Counting is **per slot occurrence**, matching calling-history semantics
/// (one record per matching slot): a dance appearing twice in the second half
/// adds 2 to [secondHalfCount], and if one of those occurrences is the last
/// dance of the second half it also adds 1 to [closedSecondHalfCount].
///
/// The "opened"/"closed" positional stats are defined over **dance slots
/// only** (a slot with a `danceId`): free-text slots (break, waltz,
/// announcement) are never the opener or closer, so a trailing "waltz" note
/// doesn't rob a dance of being the second-half closer.
@immutable
class HalfCallingStats {
  const HalfCallingStats({
    this.firstHalfCount = 0,
    this.secondHalfCount = 0,
    this.openedFirstHalfCount = 0,
    this.closedSecondHalfCount = 0,
  });

  /// The empty result — no program contributed any half-attributed occurrence.
  static const HalfCallingStats empty = HalfCallingStats();

  /// Occurrences whose derived half is [ProgramHalf.first].
  final int firstHalfCount;

  /// Occurrences whose derived half is [ProgramHalf.second].
  final int secondHalfCount;

  /// Occurrences that were the FIRST dance slot of the first half (the program
  /// opener / "first-in-1st-half").
  final int openedFirstHalfCount;

  /// Occurrences that were the LAST dance slot of the second half (the
  /// evening's closer / "last-in-2nd-half").
  final int closedSecondHalfCount;

  /// Whether any half-attributed occurrence was counted, so the UI can hide
  /// the summary entirely for dances with no half data (e.g. only ever called
  /// in break-less programs).
  bool get hasAny =>
      firstHalfCount > 0 ||
      secondHalfCount > 0 ||
      openedFirstHalfCount > 0 ||
      closedSecondHalfCount > 0;

  @override
  bool operator ==(Object other) =>
      other is HalfCallingStats &&
      other.firstHalfCount == firstHalfCount &&
      other.secondHalfCount == secondHalfCount &&
      other.openedFirstHalfCount == openedFirstHalfCount &&
      other.closedSecondHalfCount == closedSecondHalfCount;

  @override
  int get hashCode => Object.hash(
    firstHalfCount,
    secondHalfCount,
    openedFirstHalfCount,
    closedSecondHalfCount,
  );

  @override
  String toString() =>
      'HalfCallingStats(firstHalf: $firstHalfCount, '
      'secondHalf: $secondHalfCount, '
      'openedFirstHalf: $openedFirstHalfCount, '
      'closedSecondHalf: $closedSecondHalfCount)';
}

/// Aggregates [HalfCallingStats] for [danceId] across [programs], where each
/// element of [programs] is one program's slot list (order-independent — each
/// list is sorted by [ProgramSlot.position] internally before deriving halves,
/// so callers may pass rows straight from a query).
///
/// Half attribution reuses [Program.halvesForSlots] (no duplicated half
/// logic). For each program the first/last **dance slot** of each half is
/// located, then every slot referencing [danceId] contributes to the counts.
///
/// When [performedOnly] is true, only occurrences whose
/// [ProgramSlot.performedAt] is set are counted — mirroring
/// `ProgramRepository.callingHistoryForDance`'s flag (ROADMAP G.2, off by
/// default). The full slot list is always used to derive halves and the
/// first/last positions regardless of [performedOnly], since program structure
/// is independent of whether a slot was marked performed.
HalfCallingStats computeHalfCallingStats({
  required String danceId,
  required Iterable<List<ProgramSlot>> programs,
  bool performedOnly = false,
}) {
  var firstHalf = 0;
  var secondHalf = 0;
  var openedFirstHalf = 0;
  var closedSecondHalf = 0;

  for (final rawSlots in programs) {
    if (rawSlots.isEmpty) continue;
    final slots = [...rawSlots]
      ..sort((a, b) => a.position.compareTo(b.position));
    final halves = Program.halvesForSlots(slots);

    // First dance slot of the first half; last dance slot of the second half.
    // Defined over dance slots only (danceId != null) so free-text slots never
    // count as the opener/closer.
    int? firstHalfOpenerIndex;
    int? secondHalfCloserIndex;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].danceId == null) continue;
      final half = halves[i];
      if (half == ProgramHalf.first) {
        firstHalfOpenerIndex ??= i;
      } else if (half == ProgramHalf.second) {
        secondHalfCloserIndex = i;
      }
    }

    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      if (slot.danceId != danceId) continue;
      if (performedOnly && slot.performedAt == null) continue;
      final half = halves[i];
      if (half == ProgramHalf.first) {
        firstHalf++;
        if (i == firstHalfOpenerIndex) openedFirstHalf++;
      } else if (half == ProgramHalf.second) {
        secondHalf++;
        if (i == secondHalfCloserIndex) closedSecondHalf++;
      }
    }
  }

  return HalfCallingStats(
    firstHalfCount: firstHalf,
    secondHalfCount: secondHalf,
    openedFirstHalfCount: openedFirstHalf,
    closedSecondHalfCount: closedSecondHalf,
  );
}
