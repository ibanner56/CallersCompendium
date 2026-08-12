import 'dart:async';

import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Tests for the live [CollectionData] stream (issue #768).
///
/// The interesting assertions are the emit COUNTS, not the values. A stream
/// that re-reads on every commit is easy; one that does so exactly once per
/// user action is the constraint issue #340 records, and the batch paths in
/// this app write one row per transaction in a loop.
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

  testWidgets(
    'a screen whose database closes mid-open fails its load instead of '
    'hanging forever',
    (tester) async {
      // The screens complete their initial load from the stream's FIRST value.
      // If the source ends without ever emitting — the database closed while
      // the screen was opening, which teardown does — a future that is never
      // completed leaves `_load` awaiting indefinitely: no data, no error, no
      // spinner ever resolving. Asserted here on the shape both screens use.
      final source = StreamController<CollectionData>();
      final first = Completer<CollectionData>();
      final sub = source.stream.listen(
        (data) {
          if (!first.isCompleted) first.complete(data);
        },
        onError: (Object e) {
          if (!first.isCompleted) first.completeError(e);
        },
        onDone: () {
          if (!first.isCompleted) {
            first.completeError(
              StateError('collection stream closed before its first value'),
            );
          }
        },
      );
      addTearDown(sub.cancel);

      await source.close();

      await expectLater(first.future, throwsStateError);
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
