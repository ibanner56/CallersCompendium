import 'dart:async';

import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Tests for the live [CollectionData] stream (issue #768).
///
/// The interesting assertions are the emit COUNTS, not the values. A stream
/// that re-reads on every commit is easy; one that does so exactly once per
/// user action is the constraint issue #340 records, and the batch paths in
/// this app write one row per transaction in a loop.
/// Holds the watched-collection query open, so the stream can be closed before
/// it ever emits.
///
/// `QueryInterceptor.runSelect` returns a `Future`, so an interceptor may await
/// before delegating — the seam that makes "the source ended without emitting"
/// reproducible without racing a database that is too fast to lose.
class _ParkFirstWatchQuery extends drift.QueryInterceptor {
  final _gate = Completer<void>();
  bool _armed = false;
  bool didPark = false;

  void arm() => _armed = true;
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    // `watchCollectionSources`'s sentinel; parking it stops the snapshot being
    // assembled at all.
    if (_armed && !didPark && statement.trim() == 'SELECT 1') {
      didPark = true;
      await _gate.future;
    }
    return executor.runSelect(statement, args);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026);

  /// Opens in-memory repositories and closes them at teardown.
  ///
  /// Every test here opens a database; without the close they accumulate for
  /// the life of the suite. `dontWarnAboutMultipleDatabases` is set above (the
  /// tests deliberately open several), which silences the very warning that
  /// would otherwise surface a leak — so the teardown has to be systematic
  /// rather than remembered per test.
  CompendiumRepositories openRepos() {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    return repos;
  }

  Dance dance(String id, String title) =>
      Dance(id: id, title: title, createdAt: now, updatedAt: now);

  test('emits an initial snapshot without waiting for a write', () async {
    final repos = openRepos();
    await repos.dances.create(dance('d1', 'Petronella'));

    final first = await CollectionData.watch(repos).first;

    expect(first.dancesById.keys, ['d1']);
  });

  test('re-emits when a dance is written elsewhere', () async {
    final repos = openRepos();
    await repos.dances.create(dance('d1', 'Petronella'));
    final seen = <int>[];
    final sub = CollectionData.watch(
      repos,
    ).listen((d) => seen.add(d.dancesById.length));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, [1]);

    await repos.dances.create(dance('d2', 'Chase the Squirrel'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last, 2);
  });

  test('issue #340: a batch of N writes reloads ONCE, not N times', () async {
    final repos = openRepos();
    for (var i = 0; i < 10; i++) {
      await repos.dances.create(dance('d$i', 'Dance $i'));
    }
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Gentle'));
    final seen = <int>[];
    final sub = CollectionData.watch(repos).listen((_) => seen.add(1));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, hasLength(1), reason: 'the initial snapshot');

    // Exactly the shape of `_applyBatchTags`: one dance per transaction, in
    // a loop, with an await between each.
    for (var i = 0; i < 10; i++) {
      final d = (await repos.dances.getById('d$i'))!;
      await repos.dances.update(
        d.copyWith(tagIds: const ['t1'], updatedAt: DateTime.utc(2026, 2)),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The regression signal is "one reload per write", so that is what this
    // asserts — strictly fewer than the ten writes made. A tighter bound
    // (<= 2) would encode the *current* timing rather than the property:
    // the coalescer is rate-based, so a slower machine can legitimately
    // fit more than one window into the same burst without any
    // regression. The exact collapsing is pinned deterministically in the
    // transformer test below, where no database timing is involved.
    expect(
      seen.length - 1,
      lessThan(10),
      reason:
          'a 10-dance batch must not produce one reload per write; '
          'saw \$seen',
    );
  });

  test('the last emit of a burst carries the final state', () async {
    final repos = openRepos();
    for (var i = 0; i < 5; i++) {
      await repos.dances.create(dance('d$i', 'Dance $i'));
    }
    CollectionData? latest;
    final sub = CollectionData.watch(repos).listen((d) => latest = d);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    for (var i = 5; i < 10; i++) {
      await repos.dances.create(dance('d$i', 'Dance $i'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      latest!.dancesById,
      hasLength(10),
      reason: 'coalescing must not drop the final state of a burst',
    );
  });

  test('a synchronous burst collapses to exactly two emits', () async {
    // Deterministic counterpart to the end-to-end ceiling above: events are
    // delivered in one synchronous block, so no database or machine timing can
    // stretch the burst across two windows. Exactly one leading emit plus one
    // trailing emit carrying the final value.
    final source = StreamController<int>();
    final seen = <int>[];
    final sub = source.stream
        .transform(debugCoalesceTrailing<int>(const Duration(milliseconds: 24)))
        .listen(seen.add);
    addTearDown(sub.cancel);

    for (var i = 1; i <= 10; i++) {
      source.add(i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen, [1, 10], reason: 'leading edge, then the final value');
  });

  test(
    'a burst still delivers its final state when the source ends mid-window',
    () async {
      // The coalescer holds a trailing value for up to one window. If the
      // source ends inside that window — a database closed at teardown, a
      // screen disposed while a batch is still committing — the held value
      // must still be emitted, or the last state of the burst is silently
      // lost while every intermediate one was delivered.
      final source = StreamController<void>();
      final seen = <int>[];
      var n = 0;
      final sub = source.stream
          .transform(debugCoalesceTrailing<void>(const Duration(seconds: 5)))
          .listen((_) => seen.add(++n));
      addTearDown(sub.cancel);

      source.add(null); // leading edge, emitted immediately
      await pumpEventQueue();
      expect(seen, [1]);

      source.add(null); // held as the trailing value
      await source.close(); // ...and the source ends before the window elapses
      await pumpEventQueue();

      expect(seen, [
        1,
        2,
      ], reason: 'the held trailing value must be flushed before closing');
    },
  );

  test(
    'the stream ends with onDone and NO value when its query never returns '
    '(the precondition each screen guards; does not exercise any screen)',
    () async {
      // The screens complete their initial load from the stream's FIRST value,
      // so "the source ended without emitting" is the input their `onDone`
      // guards handle. This proves that input is real and reachable.
      //
      // It does NOT race a database — in-memory sqlite delivers a snapshot
      // inside a single frame, which defeated three earlier attempts. It PARKS
      // the watched query on a future that is never completed, then closes the
      // database underneath. Deterministic, no timing assumption.
      //
      // The name says what it does not do, because the test it replaces was a
      // hand-rolled REPLICA of the listen/onDone shape and passed whether or
      // not any screen implemented it — which is how `dance_list_screen` stayed
      // exposed through nine review rounds while this file was green.
      // Extending this to drive a real screen was attempted and not achieved:
      // with `runAsync` the stream does terminate, but the widget still renders
      // its skeleton, and that gap is unexplained rather than understood.
      final parker = _ParkFirstWatchQuery();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(NativeDatabase.memory().interceptWith(parker)),
        contraTaxonomy,
      );
      addTearDown(() async {
        parker.release();
      });
      parker.arm();

      var emitted = 0;
      var done = 0;
      var errored = 0;
      final sub = CollectionData.watch(repos).listen(
        (_) => emitted++,
        onError: (Object _) => errored++,
        onDone: () => done++,
      );
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(parker.didPark, isTrue, reason: 'the watched query was parked');
      expect(emitted, 0, reason: 'nothing can have been delivered');

      unawaited(repos.db.close());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(done, 1, reason: 'the source ended');
      expect(emitted, 0, reason: 'and it ended having emitted nothing');
      expect(errored, 0, reason: 'via onDone, not onError — different guards');
    },
  );

  test(
    'a first-value future is settled when its subscription is REPLACED — the '
    'exit no listener callback can see',
    () async {
      // Round 11's finding, reduced to the mechanism. `_load` awaits the
      // stream's first value; if a re-entrant `_load` cancels that
      // subscription before it emits, none of onData/onError/onDone runs —
      // cancelling a StreamSubscription invokes no callbacks — so the first
      // await never returns.
      //
      // This asserts the property the screens now rely on: the abandoning
      // party settles the future. It is the shape both screens implement in
      // `_replaceSubscription`, and it is deliberately tested here rather than
      // through a screen, because it is a Dart-level fact about cancellation
      // rather than anything about widgets.
      final parker = _ParkFirstWatchQuery();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(NativeDatabase.memory().interceptWith(parker)),
        contraTaxonomy,
      );
      addTearDown(repos.db.close);
      parker.arm();

      final first = Completer<CollectionData>();
      final sub = CollectionData.watch(repos).listen(
        (d) {
          if (!first.isCompleted) first.complete(d);
        },
        onError: (Object e) {
          if (!first.isCompleted) first.completeError(e);
        },
        onDone: () {
          if (!first.isCompleted) {
            first.completeError(StateError('closed before first value'));
          }
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(parker.didPark, isTrue);
      expect(first.isCompleted, isFalse, reason: 'no value has arrived');

      // The abandonment: cancel without settling, as the old code did.
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        first.isCompleted,
        isFalse,
        reason:
            'cancelling fires NO callback, so nothing completed the future — '
            'this is why the abandoning party must settle it itself',
      );

      // What the screens now do at the point of abandonment.
      if (!first.isCompleted) {
        first.completeError(StateError('subscription replaced'));
      }
      await expectLater(first.future, throwsStateError);
      parker.release();
    },
  );

  test('a program-side write refreshes the per-dance call tallies', () async {
    final repos = openRepos();
    await repos.dances.create(dance('d1', 'Petronella'));
    CollectionData? latest;
    final sub = CollectionData.watch(repos).listen((d) => latest = d);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(latest!.callCounts, isEmpty);

    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Friday',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(latest!.callCounts['d1']?.all, 1);
  });
}
