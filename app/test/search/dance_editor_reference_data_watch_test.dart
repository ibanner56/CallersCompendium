import 'package:compendium_app/src/search/dance_editor_reference_data.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// Tests for the live [DanceEditorReferenceData] stream (issue #768, PR 9).
///
/// Mirrors `dance_detail_data_watch_test.dart`'s shape and control arm, since
/// both types are built on the same [CompendiumRepositories.watchDanceSources]
/// sentinel and face the same batch-write burst shape. What is asserted here
/// is this type's own contract: what wakes it, what does not, and how many
/// times it re-reads for a burst — the screen's own behaviour (the draft
/// survival guarantee, the reference-data caches) is asserted in
/// `dance_editor_screen_test.dart`.
const _noCoalescing = Duration.zero;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 1, 1);

  Dance dance({required String id, required String title}) => Dance(
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
  );

  test('emits an initial reference set without waiting for a write', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));
    // ignore: unused_result
    await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Gene'));

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    expect(seen, hasLength(1));
    expect(seen.single.dances.map((d) => d.title), contains('Alpha'));
    expect(seen.single.choreographers.map((c) => c.name), contains('Gene'));
  });

  test('re-emits when a choreographer is added elsewhere', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    // ignore: unused_result
    await repos.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Gene Hubert'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last.choreographerNames['c1'], 'Gene Hubert');
  });

  test('re-emits when a tag is renamed elsewhere', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'flowy'));

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'flowing'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last.tagNames['t1'], 'flowing');
  });

  test('re-emits when a dance is retitled elsewhere', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    final stored = await repos.dances.getById('d1');
    await repos.dances.update(stored!.copyWith(title: 'Renamed'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen.last.danceNamesById['d1'], 'Renamed');
  });

  test('re-emits when a published source is added elsewhere', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await repos.publishedSources.upsert(
      PublishedSource(id: 's1', title: 'Zesty Contras'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(
      seen.last.publishedSources.map((s) => s.title),
      contains('Zesty Contras'),
    );
  });

  test('a program-side write does NOT wake this stream', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(dance(id: 'd1', title: 'Alpha'));

    final seen = <DanceEditorReferenceData>[];
    final sub = DanceEditorReferenceData.watch(repos).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, hasLength(1), reason: 'the initial reference set');

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
          'the editor renders nothing program-derived, so a program write '
          'must not re-run its fan-out',
    );

    // Paired positive: the same stream still wakes for a write it does care
    // about, so the negative above is evidence about the read set and not
    // about a subscription that quietly stopped.
    final stored = await repos.dances.getById('d1');
    await repos.dances.update(stored!.copyWith(title: 'Renamed'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(
      seen.length,
      greaterThan(1),
      reason: 'without this the negative above passes against a dead stream',
    );
  });

  test(
    'a burst of writes to OTHER dances does not re-read once per write',
    () {
      // Mirrors DanceDetailData's #340 guard: a batch operation (e.g. batch
      // tagging, which writes one dance per transaction in a loop) must not
      // re-run this fan-out per row it touches.
      return _burst(repos: openTestRepositories(), writes: 10).then((emits) {
        expect(
          emits,
          lessThan(10),
          reason: 'a 10-write burst must not produce one re-read per write',
        );
      });
    },
  );

  test(
    'the coalescing window reduces re-reads for a sequentially-written '
    'burst',
    () async {
      final windowed = await _burst(
        repos: openTestRepositories(),
        writes: 10,
        coalesce: DanceEditorReferenceData.coalesceWindow,
      );
      final unwindowed = await _burst(
        repos: openTestRepositories(),
        writes: 10,
        coalesce: _noCoalescing,
      );

      expect(
        windowed,
        lessThan(unwindowed),
        reason:
            'the coalescing window must reduce re-reads for a burst written '
            'one transaction at a time. Saw windowed=$windowed '
            'unwindowed=$unwindowed',
      );
    },
  );
}

/// Subscribes, writes [writes] other dances one transaction at a time, and
/// returns how many times the stream re-read after its initial emit.
Future<int> _burst({
  required CompendiumRepositories repos,
  required int writes,
  Duration coalesce = DanceEditorReferenceData.coalesceWindow,
}) async {
  addTearDown(repos.db.close);
  final now = DateTime.utc(2026, 1, 1);

  var emits = 0;
  final sub = DanceEditorReferenceData.watch(
    repos,
    coalesce: coalesce,
  ).listen((_) => emits++);
  addTearDown(sub.cancel);
  await pumpEventQueue();
  expect(emits, 1, reason: 'the initial reference set');

  for (var i = 0; i < writes; i++) {
    await repos.dances.create(
      Dance(id: 'd$i', title: 'Dance $i', createdAt: now, updatedAt: now),
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return emits - 1;
}
