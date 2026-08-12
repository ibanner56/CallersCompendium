import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';

/// An in-memory [CompendiumDatabase] for widget tests.
///
/// Always use this rather than constructing one inline: it sets
/// [CompendiumDatabase.closeStreamsSynchronously], without which any test that
/// unmounts a screen holding a reactive read (issue #768) fails with "Pending
/// timers" — `flutter_test` runs under `fake_async` and drift schedules a
/// zero-duration timer to hold a query stream's cache for one event loop after
/// its last listener detaches. That failure surfaces in tests which never
/// mention streams themselves, because they merely mount a shell containing a
/// converted screen, so the fix belongs here once rather than in each of them.
///
/// Pass [executor] to wrap a non-default one (e.g. `NativeDatabase.memory()`
/// with an interceptor).
CompendiumDatabase openWidgetTestDatabase([QueryExecutor? executor]) =>
    CompendiumDatabase(
      executor ?? NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    );

/// An in-memory [CompendiumRepositories] for widget tests. Each call opens a
/// fresh, isolated database (no shared state between tests), mirroring
/// `packages/compendium_core/test/storage/test_database.dart`.
CompendiumRepositories openTestRepositories() =>
    CompendiumRepositories(openWidgetTestDatabase(), contraTaxonomy);

/// A [SettingsRepository] that can be forced to fail its writes, used to
/// simulate the settings store throwing / being unavailable during a backup
/// restore's settings-apply step (issue #608). Reads and removes still delegate
/// to the real repository so tests can inspect state and a retry can succeed
/// once [failWrites] is cleared.
class FailingSettingsRepository extends SettingsRepository {
  FailingSettingsRepository(super.db);

  /// When true, every [set] throws instead of writing.
  bool failWrites = true;

  @override
  Future<void> set(String key, Object? value, {DateTime? at}) {
    if (failWrites) throw const InjectedSettingsFailure();
    return super.set(key, value, at: at);
  }
}

/// The exception thrown by [FailingSettingsRepository] while
/// [FailingSettingsRepository.failWrites] is set. An [Exception] (not an
/// [Error]) so it models a real settings-store I/O failure that the service is
/// expected to catch and report as a retryable settings failure.
class InjectedSettingsFailure implements Exception {
  const InjectedSettingsFailure();
  @override
  String toString() => 'Injected settings-store failure';
}

/// Opens in-memory repositories whose settings store fails its writes until
/// [FailingSettingsRepository.failWrites] is cleared. The core repositories
/// share the same database, so a core restore commits normally while the
/// settings-apply step fails.
({CompendiumRepositories repos, FailingSettingsRepository settings})
openTestRepositoriesWithFailingSettings() {
  final db = openWidgetTestDatabase();
  final settings = FailingSettingsRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  return (repos: repos, settings: settings);
}

/// A [SettingsRepository] whose [set] can be held open indefinitely, used to
/// deterministically reproduce the "autosave-in-flight while a draft cleanup
/// runs" race (issue #616): a test calls [holdNextWrite], triggers an
/// autosave, waits for [writeStarted] to confirm the write is in flight, runs
/// the cleanup concurrently, then completes [releaseWrite] to let the write
/// finish and asserts the cleanup — not the stale write — won.
class DelayedSettingsRepository extends SettingsRepository {
  DelayedSettingsRepository(super.db);

  Completer<void>? _armedGate;
  Completer<void>? _activeGate;
  Completer<void>? _writeStarted;

  /// Total number of [set] calls that have begun executing (gated or not),
  /// so a test can assert a later write hasn't started yet — e.g. because
  /// it's queued behind an earlier one that's still suspended.
  int writesStarted = 0;

  /// `true` once a second [set] call has begun executing. Handy shorthand
  /// for asserting an overlapping write hasn't started yet.
  bool get secondWriteStarted => writesStarted >= 2;

  /// Arms the gate: the next [set] call will complete [writeStarted] and then
  /// suspend until [releaseWrite] is called.
  void holdNextWrite() {
    _armedGate = Completer<void>();
    _writeStarted = Completer<void>();
  }

  /// Resolves once a gated [set] call has started (and is suspended awaiting
  /// [releaseWrite]).
  Future<void> get writeStarted =>
      _writeStarted?.future ?? Future<void>.value();

  /// Lets a write suspended by [holdNextWrite] proceed. Targets the gate for
  /// the write that is *currently* suspended (kept separate from
  /// [_armedGate] so calling this after the write has already started, but
  /// before it's released, still works). Idempotent — safe to call more than
  /// once for the same gated write (a bare `Completer.complete()` would throw
  /// on the second call).
  void releaseWrite() {
    final gate = _activeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> set(String key, Object? value, {DateTime? at}) async {
    writesStarted++;
    final gate = _armedGate;
    if (gate != null) {
      _armedGate = null;
      _activeGate = gate;
      _writeStarted?.complete();
      _writeStarted = null;
      await gate.future;
      _activeGate = null;
    }
    await super.set(key, value, at: at);
  }
}

/// Opens in-memory repositories backed by a [DelayedSettingsRepository], so
/// tests can hold an autosave write open while exercising a concurrent draft
/// cleanup.
({CompendiumRepositories repos, DelayedSettingsRepository settings})
openTestRepositoriesWithDelayedSettings() {
  final db = openWidgetTestDatabase();
  final settings = DelayedSettingsRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  return (repos: repos, settings: settings);
}
