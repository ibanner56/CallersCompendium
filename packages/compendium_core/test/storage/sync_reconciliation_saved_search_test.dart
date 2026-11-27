import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Sync's own natural-key reconciliation (sync-spec §6.6, "The remap") moves a
/// saved search off a merged-away tag, author, level or custom field, as a
/// user's merge does (`tags-and-people.md`, Merge step 8): on this device's
/// stored searches, and on a search that arrives in a batch while the alias
/// stands. Otherwise the search names the loser until the alias is retired,
/// and then reports as deleted a record nobody deleted (pre-release audit
/// finding D3-05).
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  final stamp = DateTime.utc(2025, 1, 2, 12);
  final remoteStamp = stamp.add(const Duration(minutes: 1));
  final today = DateTime.utc(2026, 11, 23);

  // This device's records lose (the larger ids); the inbound ones survive.
  final localAuthor = Choreographer(id: 'z-author', name: 'Shared author');
  final localTag = Tag(id: 'z-tag', name: 'Shared tag');
  final localField = CustomFieldDef(
    id: 'z-field',
    key: 'shared_field',
    label: 'Shared field',
    type: CustomFieldType.text,
  );
  final localLevel = DifficultyLevel(
    id: 'z-level',
    label: 'Shared level',
    position: 0,
  );
  final inboundAuthor = Choreographer(id: 'a-author', name: localAuthor.name);
  final inboundTag = Tag(id: 'a-tag', name: localTag.name);
  final inboundField = CustomFieldDef(
    id: 'a-field',
    key: localField.key,
    label: localField.label,
    type: localField.type,
  );
  final inboundLevel = DifficultyLevel(
    id: 'a-level',
    label: localLevel.label,
    position: localLevel.position,
  );

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  Future<void> seedLocal() async {
    // ignore: unused_result
    await repositories.choreographers.upsert(localAuthor, at: stamp);
    // ignore: unused_result
    await repositories.tags.upsert(localTag, at: stamp);
    // ignore: unused_result
    await repositories.customFieldDefs.upsert(localField, at: stamp);
    await repositories.difficultyLevels.upsert(localLevel, at: stamp);
  }

  /// A search on all four of this device's records: the Tags, Authors and
  /// Level filters, a custom-field filter and an Advanced tag row.
  SavedSearchSpec specNaming({
    required String tag,
    required String author,
    required String level,
    required String field,
  }) {
    final state = CollectionPanelState();
    state.facets.setTag(tag, selected: true);
    state.facets.authorIds.add(author);
    state.facets.levels.add(level);
    state.facets.textValues[field] = const TextFacetState(
      op: CustomFieldOp.contains,
      value: 'reel',
    );
    state.advanced.children.add(BuilderTag(tagId: tag));
    return SavedSearchSpec.fromPanelState(state, today: today).value!;
  }

  SavedSearchSpec localSpec() => specNaming(
    tag: localTag.id,
    author: localAuthor.id,
    level: localLevel.id,
    field: localField.id,
  );

  SavedSearchSpec survivorSpec() => specNaming(
    tag: inboundTag.id,
    author: inboundAuthor.id,
    level: inboundLevel.id,
    field: inboundField.id,
  );

  SyncMergeCandidate candidate(SyncRecordKind kind, String id, Object entity) =>
      SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: kind,
          id: id,
          updatedAt: remoteStamp,
          deletedAt: null,
          existenceAt: remoteStamp,
          body: syncBodyForEntity(kind, entity),
        ),
      );

  List<SyncMergeCandidate> inboundSurvivors() => [
    candidate(SyncRecordKind.choreographer, inboundAuthor.id, inboundAuthor),
    candidate(SyncRecordKind.tag, inboundTag.id, inboundTag),
    candidate(SyncRecordKind.customFieldDef, inboundField.id, inboundField),
    candidate(SyncRecordKind.difficultyLevel, inboundLevel.id, inboundLevel),
  ];

  Future<DateTime?> storedStamp(String id) async =>
      (await (db.select(db.settings)
                ..where((t) => t.key.equals('$savedSearchKeyPrefix$id')))
              .getSingle())
          .updatedAt
          ?.toUtc();

  Future<ResolvedSavedSearch> resolveStored(String id) async {
    final stored = (await repositories.savedSearches.get(id))!;
    return resolveSavedSearch(
      stored.spec,
      SavedSearchContext(
        today: today,
        taxonomy: contraTaxonomy,
        tagIds: {for (final t in await repositories.tags.listAll()) t.id},
        authorIds: {
          for (final a in await repositories.choreographers.listAll()) a.id,
        },
        levelIds: {
          for (final l in await repositories.difficultyLevels.listAll()) l.id,
        },
        customFieldDefs: await repositories.customFieldDefs.listAll(),
        aliases: await repositories.syncLocal.aliasMaps(),
      ),
    );
  }

  test('a reconciliation rewrites this device\'s saved search from each '
      'loser to its survivor, and it still resolves once the aliases are '
      'retired', () async {
    await seedLocal();
    await repositories.savedSearches.save(
      SavedSearch(id: 's1', name: 'Workshop dances', spec: localSpec()),
      at: stamp,
    );

    final result = await const SyncApplyEngine().apply(
      candidates: inboundSurvivors(),
      storage: storage,
    );
    expect(result.reports, isEmpty);
    // The reconciliation did merge all four (the setup is what it claims).
    expect(await repositories.tags.getById(localTag.id), isNull);
    expect(await repositories.choreographers.getById(localAuthor.id), isNull);
    expect(await repositories.difficultyLevels.getById(localLevel.id), isNull);
    expect(await repositories.customFieldDefs.getById(localField.id), isNull);

    final stored = (await repositories.savedSearches.get('s1'))!;
    expect(stored.name, 'Workshop dances');
    expect(stored.spec.toJson(), survivorSpec().toJson());
    // An edit of its own, so it is published (§6.6, I1).
    expect((await storedStamp('s1'))!.isAfter(stamp), isTrue);

    await repositories.syncLocal.retireAliases(
      peerAddresses: {for (final c in inboundSurvivors()) c.address},
    );
    expect(await repositories.syncLocal.aliasMaps(), isEmpty);
    expect(await resolveStored('s1'), isA<ResolvedFilter>());
  });

  test('the rewrite is published: the local snapshot carries the survivor\'s '
      'ids, and a peer that already rewrote it to the same content takes it '
      'without a review row', () async {
    await seedLocal();
    await repositories.savedSearches.save(
      SavedSearch(id: 's1', name: 'Workshop dances', spec: localSpec()),
      at: stamp,
    );
    const address = (
      kind: SyncRecordKind.setting,
      recordId: '${savedSearchKeyPrefix}s1',
    );
    final before = (await storage.snapshot()).local[address]!;

    await const SyncApplyEngine().apply(
      candidates: inboundSurvivors(),
      storage: storage,
    );
    final after = (await storage.snapshot()).local[address]!;
    expect(after.wireHash, isNot(before.wireHash));
    expect(after.blob.updatedAt.isAfter(before.blob.updatedAt), isTrue);
    expect(
      after.blob.body['value'],
      SavedSearch(
        id: 's1',
        name: 'Workshop dances',
        spec: survivorSpec(),
      ).toJson(),
    );

    // A peer that ran the same reconciliation holds the same content under
    // its own stamp. This device's copy reaches it as an ordinary newer
    // edit, with nothing to choose between.
    final peerDb = openTestDatabase();
    addTearDown(peerDb.close);
    final peer = CompendiumRepositories(peerDb, contraTaxonomy);
    final peerStorage = CompendiumSyncStorage(peer);
    await peer.savedSearches.save(
      SavedSearch(id: 's1', name: 'Workshop dances', spec: survivorSpec()),
      at: stamp.add(const Duration(seconds: 30)),
    );
    final peerCopy = (await peerStorage.snapshot()).local[address]!;
    expect(
      syncUserVisibleContentHash(
        SyncRecordKind.setting,
        peerCopy.blob.body,
        settingsKey: address.recordId,
      ),
      syncUserVisibleContentHash(
        SyncRecordKind.setting,
        after.blob.body,
        settingsKey: address.recordId,
      ),
    );
    final applied = await const SyncApplyEngine().apply(
      candidates: [SyncMergeCandidate(blob: after.blob)],
      storage: peerStorage,
    );
    expect(applied.reports, isEmpty);
    expect(applied.applied, [address]);
    expect(await peer.syncLocal.listReviewQueue(), isEmpty);
    expect(
      (await peerStorage.snapshot()).local[address]!.wireHash,
      after.wireHash,
    );
  });

  test('an inbound saved search naming a loser, in the batch that merges it, '
      'is stored under the survivor\'s ids', () async {
    await seedLocal();
    final inboundSearch = SavedSearch(
      id: 's2',
      name: 'From the other device',
      spec: localSpec(),
    );
    final result = await const SyncApplyEngine().apply(
      candidates: [
        ...inboundSurvivors(),
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.setting,
            id: inboundSearch.settingsKey,
            updatedAt: remoteStamp,
            deletedAt: null,
            existenceAt: remoteStamp,
            body: {'value': inboundSearch.toJson()},
          ),
        ),
      ],
      storage: storage,
    );
    expect(result.reports, isEmpty);
    final stored = (await repositories.savedSearches.get('s2'))!;
    expect(stored.spec.toJson(), survivorSpec().toJson());
    // Rewritten here, so stamped past the copy it came from and published.
    expect((await storedStamp('s2'))!.isAfter(remoteStamp), isTrue);
  });

  test('a saved search stamped ahead of this device\'s clock is rewritten '
      'one tick past its own stamp, so it still supersedes on peers', () async {
    await seedLocal();
    final ahead = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final aheadSecond = DateTime.utc(
      ahead.year,
      ahead.month,
      ahead.day,
      ahead.hour,
      ahead.minute,
      ahead.second,
    );
    await repositories.savedSearches.save(
      SavedSearch(id: 's1', name: 'Workshop dances', spec: localSpec()),
      at: aheadSecond,
    );
    // One merge, so one rewrite (each merge is an edit of its own).
    await const SyncApplyEngine().apply(
      candidates: [candidate(SyncRecordKind.tag, inboundTag.id, inboundTag)],
      storage: storage,
    );
    final facets =
        (await repositories.savedSearches.get('s1'))!.spec.toJson()['facets']!
            as Map;
    expect(facets['tagIds'], [inboundTag.id]);
    expect(await storedStamp('s1'), aheadSecond.add(existenceStampTick));
  });

  test('a saved search that names no loser is not written', () async {
    await seedLocal();
    final state = CollectionPanelState(text: 'petronella');
    await repositories.savedSearches.save(
      SavedSearch(
        id: 's3',
        name: 'Petronellas',
        spec: SavedSearchSpec.fromPanelState(state, today: today).value!,
      ),
      at: stamp,
    );
    await const SyncApplyEngine().apply(
      candidates: inboundSurvivors(),
      storage: storage,
    );
    expect(await storedStamp('s3'), stamp);
  });
}
