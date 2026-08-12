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

  Dance dance(String id, String title) =>
      Dance(id: id, title: title, createdAt: now, updatedAt: now);

  test('emits an initial snapshot without waiting for a write', () async {
    final repos = openTestRepositories();
    await repos.dances.create(dance('d1', 'Petronella'));

    final first = await CollectionData.watch(repos).first;

    expect(first.dancesById.keys, ['d1']);
  });

  test('re-emits when a dance is written elsewhere', () async {
    final repos = openTestRepositories();
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
    final repos = openTestRepositories();
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

    // One leading emit for the burst, plus at most one trailing emit that
    // carries the final state. Ten reloads would be the #340 regression.
    expect(
      seen.length - 1,
      lessThanOrEqualTo(2),
      reason: 'a 10-dance batch must not produce 10 reloads; saw $seen',
    );
  });

  test('the last emit of a burst carries the final state', () async {
    final repos = openTestRepositories();
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

  test('a program-side write refreshes the per-dance call tallies', () async {
    final repos = openTestRepositories();
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
