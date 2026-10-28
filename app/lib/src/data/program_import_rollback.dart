import 'package:compendium_core/compendium_core.dart';

/// The dances a program import brought into the collection while it resolved
/// its slots, kept so they can be taken back out (docs/user/programs.md:
/// "the same **Undo** safety net as every other import").
///
/// Both program imports — from a title list and from ContraDB — commit dances
/// *before* the program exists: each confident online hit is imported as it is
/// found, so the program's slots have something to link. Each of those writes
/// is an [ImportSession]; this ledger holds them so that Undo, backing out of
/// the screen, or a failed program write can revert them with the same
/// [ImportPipeline.undo] the import review screen uses. That undo is exact:
/// inserted dances are removed, a variation's link-back on its original is
/// rolled back, and authors the import created are removed again.
///
/// A dance an import merely *linked* — one already in the collection — never
/// reaches the ledger, because nothing was written for it.
///
/// Once [rollBack] has run the ledger is closed: a session that arrives later
/// (a lookup that was still in flight when the user left) is reverted as soon
/// as it is recorded, so a back-out can never leave a dance behind.
class ProgramImportRollback {
  ProgramImportRollback(this._repos);

  final CompendiumRepositories _repos;
  final List<ImportSession> _sessions = [];
  bool _closed = false;

  /// Whether nothing has been recorded since the last [rollBack].
  bool get isEmpty => _sessions.isEmpty;

  /// Whether [rollBack] has run.
  bool get isClosed => _closed;

  /// Records [session] for a later [rollBack], or reverts it straight away if
  /// the ledger is already closed.
  Future<void> record(ImportSession session) async {
    if (_closed) {
      await _pipeline().undo(session);
      return;
    }
    _sessions.add(session);
  }

  /// Reverts every recorded session, newest first, and closes the ledger.
  ///
  /// Newest first because a later session can have updated a dance an earlier
  /// one created (a variation's link-back onto a dance this same import
  /// brought in), and [ImportPipeline.undo] restores the state each session
  /// found. Idempotent: a session already undone is skipped, and a second call
  /// has nothing left to revert.
  ///
  /// A dance some program still links is **kept**. Removing it would empty
  /// that program's slot behind the user's back: the user can add an imported
  /// dance to another program while the Undo is still on offer (it can persist
  /// under accessible navigation). Soft-deleted programs count too, since
  /// restoring one must not find its slot emptied. [undoneProgramId] names the
  /// program this import created, whose own slots never count: removing it may
  /// leave a tombstone that still holds them (a program sync has published is
  /// tombstoned rather than erased).
  ///
  /// Each dance is judged on its own. Most sessions hold one dance, but the
  /// review screen's commit for ambiguous titles holds one per title, so a
  /// session with some dances kept is reverted for the rest only: their
  /// dances and the authors it created go (an author a kept dance still
  /// credits stays, by [ImportPipeline.undo]'s own guard), and the dances it
  /// updated in place keep their new state, since restoring them could drop a
  /// link a kept dance relies on.
  Future<void> rollBack({String? undoneProgramId}) async {
    _closed = true;
    final sessions = _sessions.reversed.toList();
    _sessions.clear();
    if (sessions.isEmpty) return;
    final linked = await _danceIdsLinkedByPrograms(except: undoneProgramId);
    final pipeline = _pipeline();
    for (final session in sessions) {
      final kept = session.insertedDanceIds.where(linked.contains).toSet();
      if (kept.isEmpty) {
        await pipeline.undo(session);
      } else if (kept.length < session.insertedDanceIds.length) {
        await pipeline.undo(
          ImportSession(
            records: const [],
            insertedDanceIds: [
              for (final id in session.insertedDanceIds)
                if (!kept.contains(id)) id,
            ],
            priorStates: const [],
            createdChoreographerIds: session.createdChoreographerIds,
            revivedChoreographerIds: session.revivedChoreographerIds,
          ),
        );
      }
    }
  }

  Future<Set<String>> _danceIdsLinkedByPrograms({String? except}) async {
    final programs = await _repos.programs.listAll(includeDeleted: true);
    return {
      for (final program in programs)
        if (program.id != except)
          for (final slot in program.slots) ?slot.danceId,
    };
  }

  ImportPipeline _pipeline() => ImportPipeline(
    _repos.dances,
    _repos.choreographers,
    difficultyLevels: _repos.difficultyLevels,
  );
}

/// Thrown by a program import's resolve step when its `isCancelled` callback
/// reports that the user cancelled or left the screen. Whatever the import
/// had already committed is in its [ProgramImportRollback]; the caller decides
/// whether to keep or revert it.
class ProgramImportCancelled implements Exception {
  const ProgramImportCancelled();

  @override
  String toString() => 'ProgramImportCancelled';
}

/// Thrown by a program import's resolve step when an online source could not
/// be reached (see `isConnectionFailure`). The next dance would fail the same
/// way, so the import stops instead of reporting every remaining dance as
/// "not found".
class ProgramImportConnectionFailed implements Exception {
  const ProgramImportConnectionFailed();

  @override
  String toString() => 'ProgramImportConnectionFailed';
}
