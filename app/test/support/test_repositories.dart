import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' show addTearDown;

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
///
/// Databases close automatically when the current test tears down. Set
/// [closeOnTearDown] to false when the caller owns an explicit or early close.
CompendiumDatabase openWidgetTestDatabase({
  QueryExecutor? executor,
  bool closeOnTearDown = true,
}) {
  final db = CompendiumDatabase(
    executor ?? NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  );
  if (closeOnTearDown) addTearDown(db.close);
  return db;
}

/// An in-memory [CompendiumRepositories] for widget tests. Each call opens a
/// fresh, isolated database (no shared state between tests), mirroring
/// `packages/compendium_core/test/storage/test_database.dart`.
CompendiumRepositories openTestRepositories({bool closeOnTearDown = true}) =>
    CompendiumRepositories(
      openWidgetTestDatabase(closeOnTearDown: closeOnTearDown),
      contraTaxonomy,
    );

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
openTestRepositoriesWithFailingSettings({bool closeOnTearDown = true}) {
  final db = openWidgetTestDatabase(closeOnTearDown: closeOnTearDown);
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
  Completer<void>? _armedRemoveGate;
  Completer<void>? _activeRemoveGate;
  Completer<void>? _removeStarted;

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

  /// Arms the gate: the next [remove] call will complete [removeStarted] and
  /// then suspend until [releaseRemove] is called.
  void holdNextRemove() {
    _armedRemoveGate = Completer<void>();
    _removeStarted = Completer<void>();
  }

  /// Resolves once a gated [remove] call has started and is suspended.
  Future<void> get removeStarted =>
      _removeStarted?.future ?? Future<void>.value();

  /// Lets a remove suspended by [holdNextRemove] proceed.
  void releaseRemove() {
    final gate = _activeRemoveGate;
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

  @override
  Future<void> remove(
    String key, {
    DateTime? at,
    bool permanent = false,
  }) async {
    final gate = _armedRemoveGate;
    if (gate != null) {
      _armedRemoveGate = null;
      _activeRemoveGate = gate;
      _removeStarted?.complete();
      _removeStarted = null;
      await gate.future;
      _activeRemoveGate = null;
    }
    await super.remove(key, at: at, permanent: permanent);
  }
}

/// A [ProgramRepository] whose next create/update can be held open, used to
/// prove editor auto-commit generations preserve a newer edit while an older
/// repository write is in flight.
class DelayedProgramRepository extends ProgramRepository {
  DelayedProgramRepository(super.db);

  Completer<void>? _armedGate;
  Completer<void>? _activeGate;
  Completer<void>? _writeStarted;

  int writesStarted = 0;

  void holdNextWrite() {
    _armedGate = Completer<void>();
    _writeStarted = Completer<void>();
  }

  Future<void> get writeStarted =>
      _writeStarted?.future ?? Future<void>.value();

  void releaseWrite() {
    final gate = _activeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _beforeWrite() async {
    writesStarted++;
    final gate = _armedGate;
    if (gate == null) return;
    _armedGate = null;
    _activeGate = gate;
    _writeStarted?.complete();
    _writeStarted = null;
    await gate.future;
    _activeGate = null;
  }

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async {
    await _beforeWrite();
    await super.create(program, knownVenueIds: knownVenueIds);
  }

  @override
  Future<void> update(Program program, {LiveVenueIds? knownVenueIds}) async {
    await _beforeWrite();
    await super.update(program, knownVenueIds: knownVenueIds);
  }
}

class FailingProgramRepository extends ProgramRepository {
  FailingProgramRepository(super.db);

  bool failWrites = true;
  int attempts = 0;

  void _checkWrite() {
    attempts++;
    if (failWrites) throw const InjectedProgramFailure();
  }

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async {
    _checkWrite();
    await super.create(program, knownVenueIds: knownVenueIds);
  }

  @override
  Future<void> update(Program program, {LiveVenueIds? knownVenueIds}) async {
    _checkWrite();
    await super.update(program, knownVenueIds: knownVenueIds);
  }
}

class InjectedProgramFailure implements Exception {
  const InjectedProgramFailure();

  @override
  String toString() => 'Injected program-repository failure';
}

({CompendiumRepositories repos, FailingProgramRepository programs})
openTestRepositoriesWithFailingPrograms({bool closeOnTearDown = true}) {
  final db = openWidgetTestDatabase(closeOnTearDown: closeOnTearDown);
  final programs = FailingProgramRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, programs: programs);
  return (repos: repos, programs: programs);
}

({CompendiumRepositories repos, DelayedProgramRepository programs})
openTestRepositoriesWithDelayedPrograms({bool closeOnTearDown = true}) {
  final db = openWidgetTestDatabase(closeOnTearDown: closeOnTearDown);
  final programs = DelayedProgramRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, programs: programs);
  return (repos: repos, programs: programs);
}

/// Opens in-memory repositories backed by a [DelayedSettingsRepository], so
/// tests can hold an autosave write or draft removal open while exercising a
/// concurrent draft cleanup.
({CompendiumRepositories repos, DelayedSettingsRepository settings})
openTestRepositoriesWithDelayedSettings({bool closeOnTearDown = true}) {
  final db = openWidgetTestDatabase(closeOnTearDown: closeOnTearDown);
  final settings = DelayedSettingsRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  return (repos: repos, settings: settings);
}

/// A [SettingsRepository] whose [get] can be held open indefinitely, used to
/// deterministically reproduce a "late settings read arrives after the user
/// has already sorted in-list" race for the Collection/Programs default-sort
/// seed (issue #895) — the read counterpart of [DelayedSettingsRepository],
/// which gates [set] only and so cannot hold open the read side of that race.
///
/// A test calls [holdNextRead] for a given [key], triggers the screen's boot
/// (which starts the seed read), waits for [readStarted] to confirm the read
/// is in flight, performs the in-session user action the read must not
/// clobber, then completes [releaseRead] to let the stale read resolve and
/// asserts the user's choice — not the seed — won.
class DelayedReadSettingsRepository extends SettingsRepository {
  DelayedReadSettingsRepository(super.db);

  String? _armedKey;
  Completer<void>? _armedGate;
  Completer<void>? _activeGate;
  Completer<void>? _readStarted;

  /// Arms the gate: the next [get] call for [key] will complete [readStarted]
  /// and then suspend until [releaseRead] is called. Reads for any other key
  /// pass straight through, mirroring [DelayedSettingsRepository.holdNextWrite]
  /// gating only the write it is told to.
  void holdNextRead(String key) {
    _armedKey = key;
    _armedGate = Completer<void>();
    _readStarted = Completer<void>();
  }

  /// Resolves once a gated [get] call has started (and is suspended awaiting
  /// [releaseRead]).
  Future<void> get readStarted => _readStarted?.future ?? Future<void>.value();

  /// Lets a read suspended by [holdNextRead] proceed. Idempotent, mirroring
  /// [DelayedSettingsRepository.releaseWrite].
  void releaseRead() {
    final gate = _activeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Object?> get(String key) async {
    if (key == _armedKey) {
      final gate = _armedGate!;
      _armedKey = null;
      _armedGate = null;
      _activeGate = gate;
      _readStarted?.complete();
      _readStarted = null;
      await gate.future;
      _activeGate = null;
    }
    return super.get(key);
  }
}

/// Opens in-memory repositories backed by a [DelayedReadSettingsRepository],
/// so tests can hold a default-sort seed read open while the user sorts
/// in-list, reproducing the late-read-clobber race for both the Collection
/// and Programs lists (issue #895).
({CompendiumRepositories repos, DelayedReadSettingsRepository settings})
openTestRepositoriesWithDelayedSettingsRead({bool closeOnTearDown = true}) {
  final db = openWidgetTestDatabase(closeOnTearDown: closeOnTearDown);
  final settings = DelayedReadSettingsRepository(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, settings: settings);
  return (repos: repos, settings: settings);
}
