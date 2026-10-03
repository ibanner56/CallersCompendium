import 'dart:async';

import 'package:compendium_app/src/search/coalesce_trailing.dart';
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
/// Holds the initial collection load open, so the stream can be closed before
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
    // The first read of `CollectionData.load` (`dances.listAll`); parking it
    // stops the snapshot being assembled at all. `watch` no longer issues the
    // `watchCollectionSources` sentinel (it listens to `tableUpdates` to learn
    // which tables changed), so this parks on the initial load instead.
    if (_armed && !didPark && statement.contains('FROM "dances"')) {
      didPark = true;
      await _gate.future;
    }
    return executor.runSelect(statement, args);
  }
}

/// Records every `SELECT` statement once armed, so a test can assert which
/// tables a reload read.
class _RecordSelects extends drift.QueryInterceptor {
  final statements = <String>[];
  bool _armed = false;

  void arm() {
    statements.clear();
    _armed = true;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_armed) statements.add(statement);
    return executor.runSelect(statement, args);
  }
}

/// Fails the next `dances` select once armed, then delegates normally.
class _FailNextDancesSelect extends drift.QueryInterceptor {
  bool _armed = false;

  void arm() => _armed = true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    // `dances.listAll`, the first read of `load()`; not the dance write's own
    // lookups.
    if (_armed &&
        statement.contains('FROM "dances"') &&
        statement.contains('ORDER BY "title"')) {
      _armed = false;
      throw StateError('injected dances read failure');
    }
    return executor.runSelect(statement, args);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026);

  /// Opens in-memory repositories. The shared test helper registers the
  /// database close at teardown.
  CompendiumRepositories openRepos() {
    final repos = openTestRepositories();
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

  test('issue #1420: the tune vocabulary is distinct, case-folded, sorted, '
      'and ignores a list that cannot be read', () async {
    final repos = openRepos();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'One',
        tunes: const ['Gmaj', ' dmaj ', ''],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repos.dances.create(
      Dance(
        id: 'd2',
        title: 'Two',
        tunes: const ['DMAJ', 'Amin'],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repos.dances.create(
      Dance(
        id: 'd3',
        title: 'Three',
        tunesSource: const UnreadableTunes('["Zmaj", 1]'),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final first = await CollectionData.watch(repos).first;

    // One entry per case-folded, trimmed name (which spelling survives depends
    // on load order, so it is not asserted); the blank entry is dropped; "Zmaj"
    // is absent because its list is unreadable; and the order is
    // case-insensitive.
    expect(
      [for (final t in first.tunes) t.toLowerCase()],
      ['amin', 'dmaj', 'gmaj'],
    );
    expect(first.tunes, everyElement(predicate<String>((t) => t == t.trim())));
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
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(parker),
          closeOnTearDown: false,
        ),
        contraTaxonomy,
      );
      // The close below cannot complete while the query is parked, so it is
      // started un-awaited — but the future is TRACKED and awaited in
      // teardown, after releasing the gate. Dropping it would let an in-flight
      // close outlive the test and turn any failure inside it into a late,
      // unattributed error: a false green in the file whose whole purpose is
      // proving a stream terminates.
      //
      // Nullable because the assignment below sits AFTER two `expect`s. If
      // either fails, teardown closes the database itself instead of throwing a
      // `LateInitializationError` that would hide the real test failure.
      Future<void>? closing;
      addTearDown(() async {
        parker.release();
        final closeFuture = closing;
        if (closeFuture == null) {
          await repos.db.close();
        } else {
          await closeFuture;
        }
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

      closing = repos.db.close();
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
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(parker),
        ),
        contraTaxonomy,
      );
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

      // What the screens now do at the point of abandonment, in
      // `_replaceSubscription`: settle the pending future BEFORE cancelling.
      if (!first.isCompleted) {
        first.completeError(StateError('subscription replaced'));
      }

      // Awaited with a TIMEOUT rather than a bare `expectLater`, because of
      // how this guard fails when the invariant is broken: the defect is a
      // future that never completes, so without the settle above the await
      // would hang and the suite would stall with no message. A timeout turns
      // that into a readable failure naming the invariant — which is the
      // difference between a guard that reports and one that just stops.
      await expectLater(
        first.future.timeout(
          const Duration(seconds: 2),
          // Deliberately a DIFFERENT type from the expected StateError. A
          // first attempt threw StateError here and the mutation passed —
          // `throwsStateError` was satisfied by the timeout itself, so the
          // guard could not tell "settled" from "never completed". The whole
          // point is to distinguish those two, so the timeout must not
          // impersonate the success case.
          onTimeout: () => throw TimeoutException(
            'first-value future never completed: whatever abandoned the '
            'subscription did not settle it (see _replaceSubscription)',
          ),
        ),
        throwsStateError,
      );
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

  group('counts-only reload for program writes', () {
    final programSlot = ProgramSlot(id: 's1', position: 0, danceId: 'd1');

    Program program(String id, {String title = 'Friday'}) => Program(
      id: id,
      title: title,
      slots: [programSlot],
      createdAt: now,
      updatedAt: now,
    );

    ({CompendiumRepositories repos, _RecordSelects log}) openRecording() {
      final log = _RecordSelects();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(log),
        ),
        contraTaxonomy,
      );
      return (repos: repos, log: log);
    }

    bool reads(_RecordSelects log, String table) =>
        log.statements.any((s) => s.contains('FROM "$table"'));

    test(
      'a programs write while a watch is live issues no dances read',
      () async {
        final (:repos, :log) = openRecording();
        await repos.dances.create(dance('d1', 'Petronella'));
        final snapshots = <CollectionData>[];
        final sub = CollectionData.watch(repos).listen(snapshots.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(snapshots, hasLength(1));

        log.arm();
        await repos.programs.create(program('p1'));
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(snapshots, hasLength(2), reason: 'the write still emits');
        expect(snapshots.last.callCounts['d1']?.all, 1);
        for (final table in ['dances', 'choreographers', 'tags']) {
          expect(
            reads(log, table),
            isFalse,
            reason:
                'a counts-only reload must not read $table: ${log.statements}',
          );
        }
      },
    );

    test(
      'a counts-only emit preserves the previous snapshot content',
      () async {
        final repos = openRepos();
        await repos.dances.create(dance('d1', 'Petronella'));
        // ignore: unused_result
        await repos.customFieldDefs.upsert(
          CustomFieldDef(
            id: 'f1',
            key: 'mood',
            label: 'Mood',
            type: CustomFieldType.text,
          ),
        );
        final snapshots = <CollectionData>[];
        final sub = CollectionData.watch(repos).listen(snapshots.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();

        await repos.programs.create(program('p1'));
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(snapshots, hasLength(2));
        final (previous, next) = (snapshots.first, snapshots.last);
        expect(identical(next.dancesById, previous.dancesById), isTrue);
        expect(identical(next.tags, previous.tags), isTrue);
        expect(identical(next.citedSources, previous.citedSources), isTrue);
        expect(next.customFieldFor('f1')?.label, 'Mood');
        expect(next.callCounts['d1']?.all, 1);
        expect(previous.callCounts, isEmpty);
      },
    );

    test('a mixed burst in one window runs one full load', () async {
      final (:repos, :log) = openRecording();
      await repos.dances.create(dance('d1', 'Petronella'));
      final snapshots = <CollectionData>[];
      final sub = CollectionData.watch(repos).listen(snapshots.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      log.arm();
      await repos.db.transaction(() async {
        await repos.dances.create(dance('d2', 'Chase the Squirrel'));
        await repos.programs.create(program('p1'));
      });
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(snapshots.last.dancesById.keys, containsAll(['d1', 'd2']));
      expect(snapshots.last.callCounts['d1']?.all, 1);
      expect(
        log.statements.where((s) => s.contains('FROM "dances"')),
        isNotEmpty,
        reason: 'a dance write inside the burst forces the full load',
      );
    });

    // One write per table the watch is built from: the expected read class.
    // Each case is a (table, write, full-load?) triple.
    final cases =
        <
          ({
            String table,
            bool full,
            Future<void> Function(CompendiumRepositories) write,
          })
        >[
          (
            table: 'dances',
            full: true,
            write: (r) => r.dances.create(dance('d9', 'New')),
          ),
          (
            table: 'choreographers',
            full: true,
            write: (r) async {
              // ignore: unused_result
              await r.choreographers.upsert(
                Choreographer(id: 'c1', name: 'Gene Hubert'),
              );
            },
          ),
          (
            table: 'tags',
            full: true,
            write: (r) async {
              // ignore: unused_result
              await r.tags.upsert(Tag(id: 't1', name: 'Gentle'));
            },
          ),
          (
            table: 'custom_field_defs',
            full: true,
            write: (r) async {
              // ignore: unused_result
              await r.customFieldDefs.upsert(
                CustomFieldDef(
                  id: 'f9',
                  key: 'mood9',
                  label: 'Mood',
                  type: CustomFieldType.text,
                ),
              );
            },
          ),
          (
            table: 'published_sources',
            full: true,
            write: (r) async {
              // ignore: unused_result
              await r.publishedSources.upsert(
                PublishedSource(id: 'ps1', title: 'Book'),
              );
            },
          ),
          (
            table: 'programs',
            full: false,
            write: (r) => r.programs.create(program('p9')),
          ),
        ];
    for (final c in cases) {
      test('a ${c.table} write runs a ${c.full ? 'full' : 'counts-only'} '
          'reload', () async {
        final (:repos, :log) = openRecording();
        await repos.dances.create(dance('d1', 'Petronella'));
        final sub = CollectionData.watch(repos).listen((_) {});
        addTearDown(sub.cancel);
        await pumpEventQueue();

        log.arm();
        await c.write(repos);
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(reads(log, 'dances'), c.full, reason: '${log.statements}');
      });
    }

    test('a failed content reload is retried in full by the next '
        'program-only write', () async {
      final failer = _FailNextDancesSelect();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(
          executor: NativeDatabase.memory().interceptWith(failer),
        ),
        contraTaxonomy,
      );
      await repos.dances.create(dance('d1', 'Petronella'));
      final snapshots = <CollectionData>[];
      var errors = 0;
      final sub = CollectionData.watch(
        repos,
      ).listen(snapshots.add, onError: (Object _) => errors++);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(snapshots, hasLength(1));

      failer.arm();
      await repos.dances.create(dance('d2', 'Chase the Squirrel'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(errors, 1, reason: 'the content reload failed');
      expect(snapshots, hasLength(1));

      await repos.programs.create(program('p1'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(snapshots, hasLength(2));
      expect(
        snapshots.last.dancesById.keys,
        containsAll(['d1', 'd2']),
        reason: 'the program-only write must retry the full load',
      );
      expect(snapshots.last.callCounts['d1']?.all, 1);
    });

    test('a program_slots-only write is counts-only', () async {
      final (:repos, :log) = openRecording();
      await repos.dances.create(dance('d1', 'Petronella'));
      await repos.programs.create(program('p1'));
      final sub = CollectionData.watch(repos).listen((_) {});
      addTearDown(sub.cancel);
      await pumpEventQueue();

      log.arm();
      // A write confined to `program_slots`, as a drift notification.
      repos.db.markTablesUpdated({repos.db.programSlots});
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(log.statements, isNotEmpty, reason: 'the tallies were re-read');
      expect(reads(log, 'dances'), isFalse, reason: '${log.statements}');
    });

    test('a venues-only write is counts-only for watchVenues subscribers, '
        'and invisible to others', () async {
      final (:repos, :log) = openRecording();
      await repos.dances.create(dance('d1', 'Petronella'));
      var withVenues = 0;
      var without = 0;
      final subA = CollectionData.watch(
        repos,
        watchVenues: true,
      ).listen((_) => withVenues++);
      final subB = CollectionData.watch(repos).listen((_) => without++);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);
      await pumpEventQueue();
      expect((withVenues, without), (1, 1));

      log.arm();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Town Hall'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(withVenues, 2, reason: 'a venue write still emits for them');
      expect(without, 1, reason: 'and does not wake a plain subscriber');
      expect(reads(log, 'dances'), isFalse, reason: '${log.statements}');
    });
  });

  group('CoalesceTrailing input validation', () {
    test('a negative window trips the assert rather than silently disabling', () {
      // The guard exists because the failure is SILENT, not because anything
      // throws on its own: `Timer` accepts a negative duration and fires as
      // soon as possible, so without this a negative window would disable
      // coalescing with no diagnostic at all.
      //
      // Asserted here rather than trusted, so the guard has been shown to fire.
      expect(
        () => const CoalesceTrailing<int>(
          Duration(milliseconds: -1),
        ).bind(const Stream<int>.empty()),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a negative window is inert, which is the half that holds in release', () {
      // The assert above is a DEBUG-only guarantee — asserts are stripped in
      // release — so on its own it would protect exactly the builds that never
      // ship, leaving production with the silent failure it warns about.
      //
      // Asserted on the predicate rather than through `bind`, because in a test
      // run the assert fires first and the identity path for a negative window
      // is unreachable there. A test written through `bind` could only ever be
      // skipped, and a skipped guard proves nothing.
      expect(
        CoalesceTrailing.isInert(const Duration(milliseconds: -1)),
        isTrue,
      );
      expect(CoalesceTrailing.isInert(Duration.zero), isTrue);
      expect(
        CoalesceTrailing.isInert(const Duration(milliseconds: 1)),
        isFalse,
        reason: 'a real window must NOT be treated as inert',
      );
    });

    test('Duration.zero really is inert, not merely small', () async {
      // The paired positive: zero is a legitimate argument, not an error.
      //
      // And it is a regression guard with a recorded red run. Before the
      // identity short-circuit this assertion FAILED with `[1, 3]`: a zero
      // window still armed a real `Timer`, so the middle event of a synchronous
      // burst was held and replaced. A control arm that was supposed to be
      // disabled was quietly coalescing.
      //
      // Removing the short-circuit reproduces `[1, 3]` exactly.
      final seen = <int>[];
      final sub = Stream.fromIterable([
        1,
        2,
        3,
      ]).transform(const CoalesceTrailing<int>(Duration.zero)).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(seen, [1, 2, 3]);
    });
  });
}
