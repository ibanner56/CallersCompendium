import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_sync_server.dart';
import '../support/test_repositories.dart';

/// Two devices that each created a tag of the same name before they synced:
/// sync's own reconciliation merges them (sync-spec §6.6), and a saved search
/// on the losing tag follows the survivor on every device, so it still
/// resolves once the alias is retired (pre-release audit finding D3-05).
/// Real databases and real coordinators over an in-memory store.
void main() {
  // Several databases in one isolate is the point of these tests.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  // The smaller id survives the reconciliation.
  const s = '00000000-0000-4000-8000-000000000001';
  const l = '00000000-0000-4000-8000-000000000002';
  const searchId = 'workshop-search';
  final today = DateTime.utc(2026, 11, 23);

  late InMemorySyncServer server;
  // Every user write is stamped a minute after the last, starting at the real
  // clock, so it never ties with another device's write or with a stamp sync
  // takes from the real clock (see sync_user_merge_two_device_test.dart).
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
  });

  InMemorySyncDevice device(String id) {
    final created = InMemorySyncDevice(
      server,
      deviceId: id,
      repositories: openTestRepositories(),
    );
    addTearDown(created.dispose);
    return created;
  }

  Future<void> tag(InMemorySyncDevice device, String id) async {
    // ignore: unused_result
    await device.repositories.tags.upsert(
      Tag(id: id, name: 'Workshop'),
      at: tick(),
      localUserEdit: true,
    );
  }

  Future<void> saveSearchOn(InMemorySyncDevice device, String tagId) {
    final state = CollectionPanelState();
    state.facets.setTag(tagId, selected: true);
    return device.repositories.savedSearches.save(
      SavedSearch(
        id: searchId,
        name: 'Workshop dances',
        spec: SavedSearchSpec.fromPanelState(state, today: today).value!,
      ),
      at: tick(),
    );
  }

  Future<List<Object?>> searchTags(InMemorySyncDevice device) async {
    final stored = await device.repositories.savedSearches.get(searchId);
    expect(stored, isNotNull, reason: device.deviceId);
    return ((stored!.spec.toJson()['facets']! as Map)['tagIds']! as List)
        .toList();
  }

  Future<ResolvedSavedSearch> resolveOn(InMemorySyncDevice device) async {
    final repositories = device.repositories;
    return resolveSavedSearch(
      (await repositories.savedSearches.get(searchId))!.spec,
      SavedSearchContext(
        today: today,
        taxonomy: contraTaxonomy,
        tagIds: {for (final t in await repositories.tags.listAll()) t.id},
        aliases: await repositories.syncLocal.aliasMaps(),
      ),
    );
  }

  Future<List<String>> reviews(InMemorySyncDevice device) async => [
    for (final row in await device.repositories.syncLocal.listReviewQueue())
      '${row.reason}: ${row.recordId} / ${row.counterpartId}',
  ];

  /// Runs passes in turn until nothing any device publishes changes, failing
  /// if a review row is raised on the way or the devices never settle.
  Future<void> settle(List<InMemorySyncDevice> devices) async {
    String? previous;
    for (var round = 0; round < 8; round++) {
      for (final d in devices) {
        await d.sync();
      }
      for (final d in devices) {
        expect(await reviews(d), isEmpty, reason: '${d.deviceId}, $round');
      }
      final state = [
        for (final d in devices) server.manifestOf(d.deviceId)!.records,
      ].join(' ');
      if (state == previous) return;
      previous = state;
    }
    fail('the devices did not settle: $previous');
  }

  test('a saved search on the tag that lost follows the survivor on both '
      'devices, and still resolves once the alias is retired', () async {
    final a = device('device-a');
    final b = device('device-b');
    await a.sync();
    await b.sync();
    // Before they meet: each device creates "Workshop"; A saves a search on
    // its own copy, which loses.
    await tag(a, l);
    await saveSearchOn(a, l);
    await tag(b, s);

    await settle([a, b]);
    for (final d in [a, b]) {
      expect(
        [for (final t in await d.repositories.tags.listAll()) t.id],
        [s],
        reason: d.deviceId,
      );
      expect(await searchTags(d), [s], reason: d.deviceId);
      expect(
        await d.repositories.syncLocal.aliasMaps(),
        isEmpty,
        reason: '${d.deviceId}: the alias is retired once no peer lists $l',
      );
      expect(await resolveOn(d), isA<ResolvedFilter>(), reason: d.deviceId);
    }
  });

  test('two devices that each rewrite the search agree on it without a '
      'review row', () async {
    final a = device('device-a');
    final b = device('device-b');
    final c = device('device-c');
    await a.sync();
    await b.sync();
    await c.sync();
    // A and B share L and the search on it; C, before it hears of either,
    // creates its own "Workshop", which wins.
    await tag(a, l);
    await saveSearchOn(a, l);
    await a.sync();
    await b.sync();
    expect(await searchTags(b), [l]);
    await tag(c, s);

    // C publishes S. A and B each reconcile on their own pass, and each
    // rewrites the search it holds before it sees the other's rewrite.
    await c.sync();
    await a.sync();
    await b.sync();
    expect(await reviews(a), isEmpty);
    expect(await reviews(b), isEmpty);

    await settle([a, b, c]);
    final hashes = <String>{};
    for (final d in [a, b, c]) {
      expect(await searchTags(d), [s], reason: d.deviceId);
      expect(await resolveOn(d), isA<ResolvedFilter>(), reason: d.deviceId);
      hashes.add(
        server.manifestOf(d.deviceId)!.records[SyncRecordKind
            .setting]!['$savedSearchKeyPrefix$searchId']!,
      );
    }
    expect(hashes, hasLength(1), reason: 'every device holds the same copy');
  });
}
