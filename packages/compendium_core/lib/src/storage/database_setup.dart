import 'package:sqlite3/common.dart';

/// Milliseconds a connection waits for a competing writer before failing.
///
/// Device Sync runs its pass — including the post-apply derived-index rebuild —
/// in a worker isolate holding its own connection, so an ordinary app write can
/// legitimately arrive while that transaction is open. sqlite3's default is
/// `0`: the loser fails immediately with `SQLITE_BUSY` ("database is locked")
/// rather than waiting. Waiting is strictly better than losing the user's edit,
/// so the budget is deliberately generous; WAL keeps readers unblocked
/// throughout, so this only ever delays a competing *write*.
const int compendiumSqliteBusyTimeoutMs = 30000;

/// Applies the connection settings every `CompendiumDatabase` connection needs.
///
/// **Both** the app's connection and the Device Sync worker's connection must
/// run this. They are separate connections to the same file, and the settings
/// below are what make that safe:
///
/// - `journal_mode = WAL` — a file-level property, so whichever connection
///   opens first sets it for both. Under the default rollback journal a writer
///   blocks readers, which would stall the UI for the length of an inbound
///   apply; under WAL, readers never block.
/// - `busy_timeout` — a *per-connection* property, which is why this cannot be
///   left to whichever connection happens to open first. WAL still permits one
///   writer at a time, so without a timeout a concurrent write fails instead of
///   waiting. See [compendiumSqliteBusyTimeoutMs].
///
/// Pass this as `DatabaseSetup` to `NativeDatabase`/`DriftNativeOptions`. It is
/// a top-level function because drift sends the setup callback to the isolate
/// that owns the connection; a closure over caller state would not survive that
/// hop.
///
/// In-memory databases (tests) cannot use WAL — sqlite reports `memory` and
/// leaves the mode unchanged — so the journal-mode result is deliberately not
/// asserted. The busy timeout applies either way.
void applyCompendiumSqliteSetup(CommonDatabase database) {
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA busy_timeout = $compendiumSqliteBusyTimeoutMs');
}
