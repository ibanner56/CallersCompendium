import 'package:compendium_app/src/search/dance_detail_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Tests for the live [DanceDetailData] stream (issue #768).
///
/// The screen behaviour is asserted in `refresh_scopes_test.dart`; what is
/// tested here is the stream's own contract — what wakes it, what does not, and
/// how many times it re-reads for a burst.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 1, 1);

  Dance dance({required String id, required String title}) => Dance(
    id: id,
    title: title,
    authorIds: const [],
    tagIds: const [],
    form: DanceForm.contra,
    formation: const Formation(FormationShape.dupleImproper),
    status: DanceStatus.active,
    figures: const [],
    customFields: const [],
    hook: '',
    createdAt: now,
    updatedAt: now,
  );

  test('emits an initial record without waiting for a write', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));

    final seen = <DanceDetailData?>[];
    final sub = DanceDetailData.watch(repos, 'd1').listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    expect(seen, hasLength(1));
    expect(seen.single?.dance.title, 'Alpha');
  });

  test('emits null for a dance that does not exist', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);

    final seen = <DanceDetailData?>[];
    final sub = DanceDetailData.watch(repos, 'missing').listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    expect(seen, hasLength(1));
    expect(seen.single, isNull);
  });

  test('re-emits when the dance is edited elsewhere', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));

    final seen = <DanceDetailData?>[];
    final sub = DanceDetailData.watch(repos, 'd1').listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    final stored = await repos.dances.getById('d1');
    await repos.dances.update(stored!.copyWith(title: 'Renamed'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last?.dance.title, 'Renamed');
  });

  test('re-emits when a TAG this dance carries is renamed', () async {
    // The join tables (`dance_tags` here) are deliberately absent from the
    // watched set, on the invariant that every writer of one also writes a
    // watched table in the same transaction. A tag rename is the case that
    // exercises the other half of it: nothing about `dance_tags` changes, and
    // the chip's text comes from `tags`.
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Gentle'));
    await repos.dances.create(
      dance(id: 'd1', title: 'Alpha').copyWith(tagIds: const ['t1']),
    );

    final seen = <DanceDetailData?>[];
    final sub = DanceDetailData.watch(repos, 'd1').listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen.single?.tagNames, ['Gentle']);

    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'Easy'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last?.tagNames, ['Easy']);
  });

  test('a program-side write does NOT wake this stream', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));

    final seen = <DanceDetailData?>[];
    final sub = DanceDetailData.watch(repos, 'd1').listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, hasLength(1), reason: 'the initial record');

    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Autumn Ball',
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(
      seen,
      hasLength(1),
      reason:
          'a dance record carries nothing program-derived, so a program write '
          'must not re-run its fan-out',
    );

    // The negative above is "it did not emit again", which a dead stream
    // satisfies for free. Show the same stream still wakes for the writes it
    // is supposed to, so the assertion is about the read set and not about a
    // subscription that quietly stopped.
    final stored = await repos.dances.getById('d1');
    await repos.dances.update(stored!.copyWith(title: 'Renamed'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(
      seen.length,
      greaterThan(1),
      reason: 'without this the negative above passes against a dead stream',
    );
  });

  test('a burst of writes to OTHER dances does not re-read once per write', () {
    // The bound this asserts is what issue #340 records: a batch operation must
    // not re-run this fan-out per row it touches. Batch tagging writes one
    // dance per transaction in a loop, so a 10-dance batch is 10 commits on
    // `dances` while the record on screen changed at most once.
    return _burst(repos: openTestRepositories(), writes: 10).then((emits) {
      expect(
        emits,
        lessThan(10),
        reason: 'a 10-write burst must not produce one re-read per write',
      );
    });
  });

  test('the coalescing window reduces re-reads for a sequentially-written '
      'burst', () async {
    // The obvious red-run for a coalescing window — "delete it and watch the
    // batch leak" — does NOT go red here, and that is the finding this test
    // exists to pin. A subscriber that maps each wake to an async load pauses
    // the source while the load runs, and drift collapses the updates arriving
    // during that pause into one re-run on resume. Backpressure therefore
    // supplies a bound before the window does anything, and a test that only
    // checked "the batch did not leak" would credit the window with it.
    //
    // So what is asserted is the DIFFERENCE, on the shape the app actually
    // produces: batch tagging awaits each dance's write in turn.
    final windowed = await _burst(
      repos: openTestRepositories(),
      writes: 10,
      coalesce: DanceDetailData.coalesceWindow,
    );
    final unwindowed = await _burst(
      repos: openTestRepositories(),
      writes: 10,
      coalesce: Duration.zero,
    );

    // Measured repeatedly at 1 vs 2 on in-memory sqlite in a debug build — so
    // the window's contribution is one re-read against two, not one against
    // ten. `DanceDetailData.coalesceWindow` records both figures.
    //
    // Strict, so removing the transformer fails this test rather than leaving
    // a constant nothing checks. If it ever becomes flaky the honest fix is to
    // widen the burst, not to relax this to `<=` — which would pass for a
    // window that does nothing at all.
    expect(
      windowed,
      lessThan(unwindowed),
      reason:
          'the coalescing window must reduce re-reads for a burst written '
          'one transaction at a time. Saw windowed=$windowed '
          'unwindowed=$unwindowed',
    );
  });

  test(
    'a burst the database already merged leaves the window nothing to do',
    () async {
      // The other half of the same finding, and the reason the assertion above
      // is not stated more strongly. Writes issued together commit close enough
      // that drift dispatches them as a single update, so there is no burst left
      // for a window to collapse — it cannot beat a merge the database already
      // performed.
      //
      // Asserted rather than skipped, because the tempting generalisation from
      // the test above is "a tighter burst needs the window more", and that is
      // backwards.
      final windowed = await _tightBurst(
        repos: openTestRepositories(),
        coalesce: DanceDetailData.coalesceWindow,
      );
      final unwindowed = await _tightBurst(
        repos: openTestRepositories(),
        coalesce: Duration.zero,
      );

      expect(
        windowed,
        unwindowed,
        reason:
            'concurrent writes arrive as one update either way. Saw '
            'windowed=$windowed unwindowed=$unwindowed',
      );
    },
  );
}

/// Subscribes, writes [writes] other dances one transaction at a time, and
/// returns how many times the stream re-read after its initial emit.
Future<int> _burst({
  required CompendiumRepositories repos,
  required int writes,
  Duration coalesce = DanceDetailData.coalesceWindow,
}) async {
  addTearDown(repos.db.close);
  await repos.dances.create(_plain(repos, 'd1', 'Alpha'));

  var emits = 0;
  final sub = DanceDetailData.watch(
    repos,
    'd1',
    coalesce: coalesce,
  ).listen((_) => emits++);
  addTearDown(sub.cancel);
  await pumpEventQueue();
  expect(emits, 1, reason: 'the initial record');

  for (var i = 0; i < writes; i++) {
    await repos.dances.create(_plain(repos, 'other$i', 'Other $i'));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return emits - 1;
}

/// As [_burst], but the writes are issued together rather than awaited one at a
/// time.
///
/// Deliberately does **not** claim they "land inside one coalescing window".
/// That was the intuition this helper was written on, and measuring it showed
/// the opposite: writes issued together commit close enough that drift
/// dispatches them as a single update, so the window is handed one event and
/// has nothing to collapse.
Future<int> _tightBurst({
  required CompendiumRepositories repos,
  required Duration coalesce,
}) async {
  addTearDown(repos.db.close);
  await repos.dances.create(_plain(repos, 'd1', 'Alpha'));

  var emits = 0;
  final sub = DanceDetailData.watch(
    repos,
    'd1',
    coalesce: coalesce,
  ).listen((_) => emits++);
  addTearDown(sub.cancel);
  await pumpEventQueue();

  await Future.wait([
    for (var i = 0; i < 10; i++)
      repos.dances.create(_plain(repos, 'other$i', 'Other $i')),
  ]);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return emits - 1;
}

Dance _plain(CompendiumRepositories repos, String id, String title) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
