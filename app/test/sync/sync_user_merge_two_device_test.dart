import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// A user's merge, rename and delete of a tag reaching another device
/// (`docs/design/tags-and-people.md`, T1; sync-spec §6.6 "The remap",
/// amended 2026-10-30). Two real databases sync through an in-memory store
/// with real coordinators.
void main() {
  // Two databases in one isolate is the point of these tests.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  // Ids sort in this order, so the smaller-UUID rule is easy to read.
  const s = '00000000-0000-4000-8000-000000000001';
  const l = '00000000-0000-4000-8000-000000000002';
  const t = '00000000-0000-4000-8000-000000000003';
  const d1 = '00000000-0000-4000-8000-0000000000d1';
  const d2 = '00000000-0000-4000-8000-0000000000d2';

  late InMemorySyncServer server;
  late InMemorySyncDevice a;
  late InMemorySyncDevice b;
  // Every user write is stamped a minute after the last, so two
  // devices' edits never tie (a tie is a conflict choice, §6.3). It starts at
  // the real clock, so each one is also later than the writes sync stamps
  // from the real clock as it applies: started any earlier, which of the two
  // is newer would depend on the second the test ran in.
  late DateTime clock;
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));

  setUp(() {
    final now = DateTime.now().toUtc();
    clock = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    server = InMemorySyncServer();
    a = InMemorySyncDevice(
      server,
      deviceId: 'device-a',
      repositories: openTestRepositories(),
    );
    b = InMemorySyncDevice(
      server,
      deviceId: 'device-b',
      repositories: openTestRepositories(),
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
  });

  Future<void> tag(InMemorySyncDevice device, String id, String name) async {
    // ignore: unused_result
    await device.repositories.tags.upsert(
      Tag(id: id, name: name),
      at: tick(),
      localUserEdit: true,
    );
  }

  Future<void> dance(InMemorySyncDevice device, String id, List<String> tags) {
    final at = tick();
    return device.repositories.dances.create(
      Dance(
        id: id,
        title: 'Dance $id',
        tagIds: tags,
        createdAt: at,
        updatedAt: at,
      ),
    );
  }

  /// Live tags by id, as each device's user sees them.
  Future<Map<String, String>> liveTags(InMemorySyncDevice device) async => {
    for (final tag in await device.repositories.tags.listAll())
      tag.id: tag.name,
  };

  /// Which live tags each dance shows.
  Future<Map<String, Set<String>>> danceTags(InMemorySyncDevice device) async {
    final db = device.repositories.db;
    final live = (await liveTags(device)).keys.toSet();
    final result = <String, Set<String>>{};
    for (final row in await db.select(db.danceTags).get()) {
      if (!live.contains(row.tagId)) continue;
      result.putIfAbsent(row.danceId, () => {}).add(row.tagId);
    }
    return result;
  }

  Future<List<String>> reviews(InMemorySyncDevice device) async => [
    for (final row in await device.repositories.syncLocal.listReviewQueue())
      '${row.reason}: ${row.recordId} / ${row.counterpartId}',
  ];

  Future<List<String>> pending(InMemorySyncDevice device) async => [
    for (final row
        in await device.repositories.syncLocal.listPendingDeletions())
      row.recordId,
  ];

  /// Runs passes alternately until neither device changes, failing if a
  /// review row is raised on the way or the devices never settle.
  Future<void> settle({int maxRounds = 6}) async {
    String? previous;
    for (var round = 0; round < maxRounds; round++) {
      await b.sync();
      await a.sync();
      expect(await reviews(a), isEmpty, reason: 'device A, round $round');
      expect(await reviews(b), isEmpty, reason: 'device B, round $round');
      // What each device publishes covers tombstones and stamps too, which
      // the live view below does not.
      final state =
          '${server.manifestOf(a.deviceId)!.records} '
          '${server.manifestOf(b.deviceId)!.records} '
          '${await liveTags(a)} ${await danceTags(a)} '
          '${await liveTags(b)} ${await danceTags(b)}';
      if (state == previous) return;
      previous = state;
    }
    fail('the devices did not settle in $maxRounds rounds: $previous');
  }

  /// Both devices hold S "Flowing" and L "Flowy", with d1 tagged L.
  Future<void> seed() async {
    await tag(a, s, 'Flowing');
    await tag(a, l, 'Flowy');
    await dance(a, d1, [l]);
    await a.sync();
    await b.sync();
    await a.sync();
    expect(await liveTags(b), {s: 'Flowing', l: 'Flowy'});
  }

  /// "Rename 'Flowing' to 'Flowy'", which collides and merges: the user
  /// merges into L, the larger id, so S survives holding L's name.
  Future<ReferenceEditUndo> mergeFlowingIntoFlowy(InMemorySyncDevice device) =>
      device.repositories.references.merge(
        ReferenceKind.tag,
        intoId: l,
        otherIds: [s],
        name: 'Flowy',
        at: tick(),
      );

  test('a peer that tagged a dance with the loser while offline holds the '
      'deletion, then converges on the survivor with no review row', () async {
    await seed();
    // B, offline, tags a new dance with "Flowy" (L).
    await dance(b, d2, [l]);
    await mergeFlowingIntoFlowy(a);
    await a.sync();

    // B now holds L's deletion: d2, which A has never seen, still cites it.
    await b.sync();
    expect(await pending(b), [l]);
    expect(await reviews(b), isEmpty);

    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowy'}, reason: device.deviceId);
      expect(await danceTags(device), {
        d1: {s},
        d2: {s},
      }, reason: device.deviceId);
    }
  });

  test('opposite merges on two offline devices keep the same id', () async {
    await seed();
    // A merges "Flowing" into "Flowy"; B, offline, the other way round.
    await mergeFlowingIntoFlowy(a);
    await b.repositories.references.merge(
      ReferenceKind.tag,
      intoId: s,
      otherIds: [l],
      at: tick(),
    );

    await settle();
    // Both kept S. B merged last, so its fields win by last-writer-wins.
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowing'}, reason: device.deviceId);
      expect(await danceTags(device), {
        d1: {s},
      }, reason: device.deviceId);
    }
  });

  test("another device's tombstone of the loser never tombstones the "
      'survivor', () async {
    await seed();
    await mergeFlowingIntoFlowy(a);
    // B, before it hears of the merge, deletes "Flowy" itself: a tombstone of
    // L stamped after A's. On A the alias names L's survivor, S.
    await b.repositories.references.deleteTag(l, at: tick());

    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowy'}, reason: device.deviceId);
    }
  });

  test('Undo of a merge reaches a peer that held the deletion', () async {
    await seed();
    await dance(b, d2, [l]);
    final undo = await mergeFlowingIntoFlowy(a);
    await a.sync();
    await b.sync();
    expect(await pending(b), [l]);

    await a.repositories.references.undo(undo, at: tick());
    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {
        s: 'Flowing',
        l: 'Flowy',
      }, reason: device.deviceId);
      expect(await danceTags(device), {
        d1: {l},
        d2: {l},
      }, reason: device.deviceId);
    }
  });

  test('a rename onto a name a tombstone holds reaches a peer still holding '
      "that tombstone's deletion", () async {
    await seed();
    // L is deleted on A; B has a dance citing it that A has not seen, so B
    // holds the deletion.
    await dance(b, d2, [l]);
    await a.repositories.references.deleteTag(l, at: tick());
    await a.sync();
    await b.sync();
    expect(await pending(b), [l]);

    // A renames S onto the name L's tombstone holds there.
    await a.repositories.references.rename(
      ReferenceKind.tag,
      s,
      'Flowy',
      at: tick(),
    );
    await settle();
    expect(await liveTags(a), {s: 'Flowy'});
    // B keeps L live while d2 cites it (§6.8). The rename waits behind it,
    // unqueued.
    expect(await liveTags(b), {s: 'Flowing', l: 'Flowy'});

    // Once B's user takes the tag off d2, the deletion lands and the rename
    // follows.
    final d2OnB = (await b.repositories.dances.getById(d2))!;
    await b.repositories.dances.update(
      d2OnB.copyWith(tagIds: const [], updatedAt: tick()),
      localUserEdit: true,
    );
    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowy'}, reason: device.deviceId);
    }
  });

  test('a merge of several matches where a loser other than the renamed '
      'entry held the exact name', () async {
    // S "Flowing" is renamed onto "Flowy", which L holds exactly and T, only
    // on A, holds as "FLOWY". Sync folds case and reconciles case variants
    // between devices (§6.6 step 2), so a peer never holds both L and T; the
    // matches only coexist on the device that merges. S, the smallest id,
    // survives holding L's bytes.
    await seed();
    await tag(a, t, 'FLOWY');
    await dance(b, d2, [l]);

    await a.repositories.references.merge(
      ReferenceKind.tag,
      intoId: l,
      otherIds: [s, t],
      name: 'Flowy',
      at: tick(),
    );
    await a.sync();
    await b.sync();
    expect(await pending(b), [l]);

    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowy'}, reason: device.deviceId);
      expect(await danceTags(device), {
        d1: {s},
        d2: {s},
      }, reason: device.deviceId);
    }
  });

  test('a rename of the loser on a peer that has not seen the merge loses to '
      "the merge's tombstone, as an edit loses to a later delete", () async {
    await seed();
    await mergeFlowingIntoFlowy(a);
    await b.repositories.references.rename(
      ReferenceKind.tag,
      l,
      'Flowier',
      at: tick(),
    );

    await settle();
    for (final device in [a, b]) {
      expect(await liveTags(device), {s: 'Flowy'}, reason: device.deviceId);
      expect(await danceTags(device), {
        d1: {s},
      }, reason: device.deviceId);
    }
  });

  test('a held deletion that did not give up its name still asks, rather '
      'than holding a rename back without a word', () async {
    // Not a merge: on A, "Foo" is renamed "Old" and deleted, then "Bar" is
    // renamed "Foo". B holds Foo's deletion for a dance only B has, which
    // nothing on A will ever rewrite, so the hold may never end.
    await tag(a, s, 'Foo');
    await tag(a, l, 'Bar');
    await a.sync();
    await b.sync();
    await a.sync();
    await dance(b, d2, [s]);
    await a.repositories.references.rename(
      ReferenceKind.tag,
      s,
      'Old',
      at: tick(),
    );
    await a.repositories.references.deleteTag(s, at: tick());
    await a.repositories.references.rename(
      ReferenceKind.tag,
      l,
      'Foo',
      at: tick(),
    );
    await a.sync();
    await b.sync();
    await b.sync();

    expect(await pending(b), [s]);
    expect(await reviews(b), [
      'known UUID natural-key rename collides with another local row: '
          '$l / $s',
    ]);
  });
}
