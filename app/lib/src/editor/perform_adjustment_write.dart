import 'package:compendium_core/compendium_core.dart';

import 'program_slot_rebase.dart';

/// What [writePerformAdjustment] stored.
class PerformAdjustmentWrite {
  const PerformAdjustmentWrite({
    required this.stored,
    required this.changedUnderneath,
  });

  /// The program as the write stored it: the token the next adjustment, and
  /// the Undo offered after Perform closes, compare the stored program
  /// against.
  final Program stored;

  /// Whether the stored program was no longer the one Perform's copy was
  /// based on, so another write (Device Sync, the summary, another screen)
  /// landed while Perform was open. The adjustment was applied on top of that
  /// write instead of replacing it.
  final bool changedUnderneath;
}

/// How often [writePerformAdjustment] re-reads and retries before giving up,
/// when other writes keep landing between its read and its write.
const int _kPerformWriteAttempts = 5;

/// Writes a Perform adjustment to the stored program (GIG-6): only the change
/// that turned [before] into [after] (see [rebaseSlotEdits]), applied to the
/// program as stored, as a compare-and-replace
/// ([ProgramRepository.replaceIfUnchangedAndReadBack]), so no write that
/// lands meanwhile is overwritten by Perform's copy.
///
/// [expected] is the stored program Perform's copy was based on: the program
/// Perform opened with, then each earlier adjustment's [PerformAdjustmentWrite]
/// `stored`. When the stored program no longer equals it, the result says
/// so, for Perform to show the newer program and tell the caller. Pass `null`
/// when that cannot be told; the write is still a compare-and-replace.
///
/// Throws a [StateError] when the program is missing or deleted, or keeps
/// changing between the read and the write.
Future<PerformAdjustmentWrite> writePerformAdjustment(
  ProgramRepository programs, {
  required String programId,
  required Program? expected,
  required List<ProgramSlot> before,
  required List<ProgramSlot> after,
}) async {
  var changed = false;
  for (var attempt = 0; attempt < _kPerformWriteAttempts; attempt++) {
    final current = await programs.getById(programId);
    if (current == null) {
      throw StateError('program "$programId" is gone');
    }
    if (expected != null && current != expected) changed = true;
    final stored = await programs.replaceIfUnchangedAndReadBack(
      expected: current,
      replacement: current.copyWith(
        slots: renumberSlots(
          rebaseSlotEdits(before: before, after: after, onto: current.slots),
        ),
      ),
      updatedAt: DateTime.now().toUtc(),
    );
    if (stored != null) {
      return PerformAdjustmentWrite(stored: stored, changedUnderneath: changed);
    }
    // Another write landed between the read and the compare: it is newer than
    // Perform's copy too.
    changed = true;
  }
  throw StateError('program "$programId" kept changing during the write');
}
