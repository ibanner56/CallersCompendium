import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';

/// Applies the slot edits that turned [before] into [after] to [onto], and
/// returns the result. Positions are left for the caller to renumber.
///
/// Perform edits a copy of the program it was opened with, which can differ
/// from the stored program: the builder may hold unsaved edits, and a commit
/// may have stamped slots since (GIG-3, GIG-4). Writing Perform's whole slot
/// list would commit the first and erase the second, so only what Perform
/// changed is carried over, matched by slot id:
///
/// - a field Perform changed on a slot takes Perform's value; every other
///   field keeps the value in [onto];
/// - a slot Perform removed is removed;
/// - a slot Perform added, or moved relative to the slots it left in place, is
///   placed after its nearest predecessor in [after] that [onto] holds, or
///   first when there is none, and a slot that is not an alternate is placed
///   after that predecessor's alternates the edit never saw, so they stay in
///   its group;
/// - a slot [onto] does not hold (an unsaved builder slot) is not added, even
///   when Perform changed or moved it.
List<ProgramSlot> rebaseSlotEdits({
  required List<ProgramSlot> before,
  required List<ProgramSlot> after,
  required List<ProgramSlot> onto,
}) {
  final beforeById = {for (final slot in before) slot.id: slot};
  final afterById = {for (final slot in after) slot.id: slot};

  final unmoved = _unmovedIds(
    [
      for (final slot in before)
        if (afterById.containsKey(slot.id)) slot.id,
    ],
    [
      for (final slot in after)
        if (beforeById.containsKey(slot.id)) slot.id,
    ],
  );
  final placed = {
    for (final slot in after)
      if (!unmoved.contains(slot.id)) slot.id,
  };

  final result = <ProgramSlot>[];
  for (final slot in onto) {
    final was = beforeById[slot.id];
    if (was == null) {
      result.add(slot);
      continue;
    }
    final now = afterById[slot.id];
    if (now == null || placed.contains(slot.id)) continue;
    result.add(_mergeFields(was, now, slot));
  }

  final ontoById = {for (final slot in onto) slot.id: slot};
  for (var i = 0; i < after.length; i++) {
    final slot = after[i];
    if (!placed.contains(slot.id)) continue;
    final ProgramSlot merged;
    final was = beforeById[slot.id];
    if (was == null) {
      merged = slot;
    } else {
      final current = ontoById[slot.id];
      if (current == null) continue;
      merged = _mergeFields(was, slot, current);
    }
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final index = result.indexWhere((s) => s.id == after[j].id);
      if (index >= 0) {
        at = index + 1;
        break;
      }
    }
    if (!merged.isAlt) {
      while (at < result.length &&
          result[at].isAlt &&
          !beforeById.containsKey(result[at].id)) {
        at++;
      }
    }
    result.insert(at, merged);
  }
  return result;
}

/// The ids in a longest common subsequence of [before] and [after]: the slots
/// whose order relative to each other Perform left alone. Programs hold a
/// night's worth of slots, so the quadratic table is small.
Set<String> _unmovedIds(List<String> before, List<String> after) {
  final n = before.length;
  final m = after.length;
  final lengths = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lengths[i][j] = before[i] == after[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  final ids = <String>{};
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (before[i] == after[j]) {
      ids.add(before[i]);
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return ids;
}

/// [onto] with every field [was] → [now] changed set to its value in [now].
/// The position is [onto]'s; the caller renumbers.
ProgramSlot _mergeFields(ProgramSlot was, ProgramSlot now, ProgramSlot onto) {
  T pick<T>(T Function(ProgramSlot slot) field) =>
      field(was) == field(now) ? field(onto) : field(now);
  try {
    return ProgramSlot(
      id: onto.id,
      position: onto.position,
      danceId: pick((s) => s.danceId),
      text: pick((s) => s.text),
      isPurgedDance: pick((s) => s.isPurgedDance),
      isAlt: pick((s) => s.isAlt),
      guestCaller: pick((s) => s.guestCaller),
      walkthroughMinutes: pick((s) => s.walkthroughMinutes),
      danceMinutes: pick((s) => s.danceMinutes),
      performedAt: pick((s) => s.performedAt),
    );
  } on ArgumentError catch (error, stackTrace) {
    // The field-by-field mix broke a slot invariant (say, Perform cleared the
    // text of a slot whose dance [onto] no longer has): take Perform's slot.
    logCaughtError(
      error,
      stackTrace,
      source: 'program_slot_rebase._mergeFields',
    );
    return ProgramSlot(
      id: now.id,
      position: onto.position,
      danceId: now.danceId,
      text: now.text,
      isPurgedDance: now.isPurgedDance,
      isAlt: now.isAlt,
      guestCaller: now.guestCaller,
      walkthroughMinutes: now.walkthroughMinutes,
      danceMinutes: now.danceMinutes,
      performedAt: now.performedAt,
    );
  }
}

/// [slots] with positions renumbered contiguously (0..n-1) in list order, as
/// [rebaseSlotEdits] leaves them for its caller to do.
List<ProgramSlot> renumberSlots(List<ProgramSlot> slots) => [
  for (var i = 0; i < slots.length; i++)
    slots[i].position == i ? slots[i] : slots[i].copyWith(position: i),
];
