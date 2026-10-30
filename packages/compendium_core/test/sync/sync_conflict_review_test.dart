import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Conflict choices: sync-spec §6.3 (equal `updatedAt`) and the
/// whole-collection settings rule, queued by [CompendiumSyncStorage
/// .refreshConflictReviews] and decided by [CompendiumSyncStorage
/// .resolveConflicts].
void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;
  const engine = SyncMergeEngine();
  final tie = DateTime.utc(2026, 9, 30, 12);
  const themeAddress = (kind: SyncRecordKind.setting, recordId: 'theme_mode');

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  Future<SyncMergeCandidate> localCandidate(SyncRecordAddress address) async =>
      (await storage.snapshot()).local[address]!;

  SyncMergeCandidate peerVersion(
    SyncMergeCandidate local,
    Map<String, Object?> body, {
    DateTime? updatedAt,
  }) => SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      kind: local.blob.kind,
      id: local.blob.id,
      updatedAt: updatedAt ?? local.updatedAt,
      deletedAt: null,
      existenceAt: local.existenceAt,
      body: body,
    ),
    peerId: 'peer',
  );

  /// Runs the merge the coordinator runs and queues what it raises.
  Future<SyncMergePlan> mergeAndQueue(
    SyncRecordAddress address,
    List<SyncMergeCandidate> peers,
  ) async {
    final local = await localCandidate(address);
    final aliases = <SyncRecordKind, Map<String, String>>{};
    for (final row in await repositories.syncLocal.listAliases()) {
      aliases.putIfAbsent(row.kind, () => {})[row.losingId] = row.survivingId;
    }
    final plan = engine.plan(
      local: {address: local},
      baseline: const {},
      peers: [
        for (final peer in peers) {address: peer},
      ],
      aliases: aliases,
    );
    await storage.refreshConflictReviews(plan.reviews);
    return plan;
  }

  Future<List<ReviewQueueRow>> queued() async => [
    for (final row in await repositories.syncLocal.listReviewQueue())
      if (row.reason == syncConflictChoiceReason) row,
  ];

  Future<void> seedTie() async {
    await repositories.settings.set('theme_mode', 'dark', at: tie);
    final local = await localCandidate(themeAddress);
    await mergeAndQueue(themeAddress, [
      peerVersion(local, {'value': 'light'}),
    ]);
  }

  group('refreshConflictReviews', () {
    test('queues one row per offered version, filed under its wire hash, '
        'with this device\'s hash beside it', () async {
      await seedTie();
      final local = await localCandidate(themeAddress);

      final rows = await queued();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.kind, SyncRecordKind.setting);
      expect(row.recordId, 'theme_mode');
      expect(row.counterpartId, row.candidateHash);
      expect(row.localHash, local.wireHash);
      final item = SyncReviewQueueItem.fromRow(row);
      expect(item.isConflictChoice, isTrue);
      expect(item.isActionable, isTrue);
      expect(item.candidate!.body['value'], 'light');
    });

    test(
      're-raising the same conflict keeps the row and its queued time',
      () async {
        await seedTie();
        final before = (await queued()).single;
        final local = await localCandidate(themeAddress);

        final added = await storage.refreshConflictReviews(
          engine
              .plan(
                local: {themeAddress: local},
                baseline: const {},
                peers: [
                  {
                    themeAddress: peerVersion(local, {'value': 'light'}),
                  },
                ],
              )
              .reviews,
        );

        expect(added, 0);
        expect((await queued()).single.queuedAt, before.queuedAt);
      },
    );

    test('drops a queued choice once the merge stops raising it', () async {
      await seedTie();

      await storage.refreshConflictReviews(const []);

      expect(await queued(), isEmpty);
    });

    test(
      'keeps a queued choice whose record the merge skipped this pass',
      () async {
        await seedTie();

        await storage.refreshConflictReviews(
          const [],
          unevaluated: {themeAddress},
        );

        expect(await queued(), hasLength(1));
      },
    );

    test('drops a queued choice for a withdrawn setting, even one the merge '
        'skipped, and keeps an ordinary setting\'s', () async {
      await seedTie();
      // As an older build left it: a tie queued for a key that build synced.
      final withdrawn = syncWithdrawnSettingKeys.first;
      await repositories.syncLocal.enqueueReview(
        kind: SyncRecordKind.setting,
        recordId: withdrawn,
        counterpartId: 'peer-hash',
        reason: syncConflictChoiceReason,
        candidateBlob: '{}',
        candidateHash: 'peer-hash',
        localHash: 'local-hash',
        queuedAt: tie,
      );
      await storage.refreshConflictReviews(
        const [],
        unevaluated: {
          themeAddress,
          (kind: SyncRecordKind.setting, recordId: withdrawn),
        },
      );

      expect((await queued()).map((row) => row.recordId), ['theme_mode']);
    });

    test('queues nothing for a withdrawn setting the merge raises', () async {
      for (final key in syncWithdrawnSettingKeys) {
        final address = (kind: SyncRecordKind.setting, recordId: key);
        await repositories.settings.set(key, 'a', at: tie);
        final local = await localCandidate(address);
        await mergeAndQueue(address, [
          peerVersion(local, {'value': 'b'}),
        ]);
      }

      expect(await queued(), isEmpty);
    });

    test('leaves rows of every other reason alone', () async {
      await seedTie();
      await repositories.syncLocal.enqueueReview(
        kind: SyncRecordKind.dance,
        recordId: 'a',
        counterpartId: 'b',
        reason: syncDanceChoreographyAmbiguityReason,
        candidateBlob: '{}',
        candidateHash: 'h',
        queuedAt: tie,
      );

      await storage.refreshConflictReviews(const []);

      final rows = await repositories.syncLocal.listReviewQueue();
      expect(rows.map((row) => row.reason), [
        syncDanceChoreographyAmbiguityReason,
      ]);
    });
  });

  group('SyncReviewQueueResolver.listConflicts', () {
    test("gives this device's copy only the fields that travel, with when it "
        "was last changed", () async {
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Local name', email: 'private@x.test'),
        at: tie,
      );
      const address = (kind: SyncRecordKind.choreographer, recordId: 'c1');
      final local = await localCandidate(address);
      await mergeAndQueue(address, [
        peerVersion(local, {...local.blob.body, 'name': 'Remote name'}),
      ]);

      final group = (await SyncReviewQueueResolver(
        storage,
      ).listConflicts()).single;

      expect(group.localBody!['name'], 'Local name');
      expect(
        group.localBody!.containsKey('email'),
        isFalse,
        reason:
            'a field that never syncs is not part of the choice and must not '
            'read as a difference',
      );
      expect(group.localUpdatedAt!.toUtc(), tie);
      expect(
        syncDifferingFields(
          group.localBody,
          group.candidates.single.candidate!.body,
        ),
        ['name'],
      );
    });
  });

  group('SyncReviewQueueResolver.listConflicts with this device\'s copy '
      'deleted', () {
    test('offers every version, none of them as this device\'s', () async {
      const address = (kind: SyncRecordKind.choreographer, recordId: 'c1');
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Seth Tepfer'),
        at: tie,
      );
      final before = await localCandidate(address);
      await repositories.choreographers.delete('c1', at: tie);
      // Two devices revived it and tied; one of them looks exactly like the
      // copy deleted here. The merge queued both, against no live copy.
      SyncMergeCandidate revived(Map<String, Object?> body) =>
          SyncMergeCandidate.fromBlob(
            SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: 'c1',
              updatedAt: tie.add(const Duration(seconds: 1)),
              deletedAt: null,
              existenceAt: tie.add(const Duration(seconds: 1)),
              body: body,
            ),
          );
      for (final peer in [
        revived(before.blob.body),
        revived({...before.blob.body, 'notes': 'there'}),
      ]) {
        await repositories.syncLocal.enqueueReview(
          kind: SyncRecordKind.choreographer,
          recordId: 'c1',
          counterpartId: peer.wireHash,
          reason: syncConflictChoiceReason,
          candidateBlob: encodeSyncRecordBlob(peer.blob),
          candidateHash: peer.wireHash,
          queuedAt: tie,
        );
      }

      final group = (await SyncReviewQueueResolver(
        storage,
      ).listConflicts()).single;

      expect(group.localBody, isNull);
      expect(group.localUpdatedAt, isNull);
      expect(group.candidates, hasLength(2));
    });
  });

  group('SyncReviewQueueResolver.listConflicts and what a version keeps for '
      'a newer build (spec §6.7)', () {
    const address = (kind: SyncRecordKind.publishedSource, recordId: 's1');

    Future<void> seedSource({Map<String, Object?>? kept}) async {
      await repositories.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Mine'),
        at: tie,
      );
      if (kept != null) {
        await repositories.syncLocal.setRetainedSyncFields(
          kind: address.kind,
          recordId: address.recordId,
          payload: canonicalJson(kept),
        );
      }
    }

    Future<void> queue(SyncMergeCandidate peer, {String? localHash}) =>
        repositories.syncLocal.enqueueReview(
          kind: address.kind,
          recordId: address.recordId,
          counterpartId: peer.wireHash,
          reason: syncConflictChoiceReason,
          candidateBlob: encodeSyncRecordBlob(peer.blob),
          candidateHash: peer.wireHash,
          localHash: localHash,
          queuedAt: tie,
        );

    test('versions that differ only in a kept part are not separate '
        'choices', () async {
      await seedSource();
      final local = await localCandidate(address);
      // The copy here is deleted; two devices revived it and tied. They show
      // the same title and differ only in what a newer build adds.
      await repositories.publishedSources.delete('s1', at: tie);
      for (final extra in ['one', 'two']) {
        await queue(
          peerVersion(local, {
            ...local.blob.body,
            'title': 'Theirs',
            'addedLater': extra,
          }, updatedAt: tie.add(const Duration(seconds: 1))),
        );
      }

      expect(await SyncReviewQueueResolver(storage).listConflicts(), isEmpty);
    });

    test('this device\'s own kept part is not a difference from a version '
        'that lacks it', () async {
      await seedSource(
        kept: {
          'addedLater': {'v': 'kept'},
        },
      );
      final local = await localCandidate(address);
      expect(local.blob.body['addedLater'], 'kept');
      // Queued against an earlier title; this device has since taken theirs.
      final peer = peerVersion(
        local,
        {...local.blob.body, 'title': 'Mine'}..remove('addedLater'),
      );
      await queue(peer, localHash: local.wireHash);

      expect(await SyncReviewQueueResolver(storage).listConflicts(), isEmpty);
    });
  });

  group('SyncReviewQueueResolver.listConflicts and a kept part of a dance or '
      'a setting (spec §6.7)', () {
    test('a kept key nested in a field the comparison shows whole is not a '
        'difference', () async {
      const address = (kind: SyncRecordKind.dance, recordId: 'd1');
      await repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Hey Day',
          formation: const Formation(FormationShape.reverseProgressionImproper),
          createdAt: tie,
          updatedAt: tie,
        ),
      );
      await repositories.syncLocal.setRetainedSyncFields(
        kind: address.kind,
        recordId: address.recordId,
        payload: canonicalJson({
          'formation': {
            'm': {
              'addedLater': {'v': 'kept'},
            },
          },
        }),
      );
      final local = await localCandidate(address);
      final formation = local.blob.body['formation']! as Map<String, Object?>;
      expect(formation['addedLater'], 'kept');
      // Queued before this device kept the nested key, or against a copy
      // that never had it: it shows the same dance.
      final peer = peerVersion(local, {
        ...local.blob.body,
        'formation': {...formation}..remove('addedLater'),
      });
      await repositories.syncLocal.enqueueReview(
        kind: address.kind,
        recordId: address.recordId,
        counterpartId: peer.wireHash,
        reason: syncConflictChoiceReason,
        candidateBlob: encodeSyncRecordBlob(peer.blob),
        candidateHash: peer.wireHash,
        localHash: local.wireHash,
        queuedAt: tie,
      );

      expect(await SyncReviewQueueResolver(storage).listConflicts(), isEmpty);
    });

    test('a setting with a kept part is compared without it', () async {
      await repositories.settings.set('theme_mode', 'dark', at: tie);
      await repositories.syncLocal.setRetainedSyncFields(
        kind: SyncRecordKind.setting,
        recordId: 'theme_mode',
        payload: canonicalJson({
          'addedLater': {'v': 'kept'},
        }),
      );
      final local = await localCandidate(themeAddress);
      expect(local.blob.body['addedLater'], 'kept');
      final peer = peerVersion(local, {'value': 'dark'});
      await repositories.syncLocal.enqueueReview(
        kind: themeAddress.kind,
        recordId: themeAddress.recordId,
        counterpartId: peer.wireHash,
        reason: syncConflictChoiceReason,
        candidateBlob: encodeSyncRecordBlob(peer.blob),
        candidateHash: peer.wireHash,
        localHash: local.wireHash,
        queuedAt: tie,
      );

      expect(await SyncReviewQueueResolver(storage).listConflicts(), isEmpty);
    });
  });

  group('resolveConflicts', () {
    Future<({Object? value, DateTime updatedAt})> themeRow() async {
      final row = await (db.select(
        db.settings,
      )..where((t) => t.key.equals('theme_mode'))).getSingle();
      return (
        value: await repositories.settings.get('theme_mode'),
        updatedAt: row.updatedAt!.toUtc(),
      );
    }

    test('keeping the other device\'s version writes it one tick past the '
        'tie and clears the choice', () async {
      await seedTie();
      final row = (await queued()).single;

      final kinds = await storage.resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
          keepCandidateHash: row.candidateHash,
        ),
      ], now: () => tie);

      expect(kinds.kinds, {SyncRecordKind.setting});
      final theme = await themeRow();
      expect(theme.value, 'light');
      expect(
        theme.updatedAt,
        tie.add(const Duration(seconds: 1)),
        reason:
            'equal to the tie would tie again on every other device; one '
            'tick past it is the smallest stamp that wins there',
      );
      expect(await queued(), isEmpty);
    });

    test('keeping this device\'s version re-stamps the unchanged value so it '
        'wins elsewhere', () async {
      await seedTie();

      await storage.resolveConflicts([
        const SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
        ),
      ], now: () => tie);

      final theme = await themeRow();
      expect(theme.value, 'dark');
      expect(theme.updatedAt, tie.add(const Duration(seconds: 1)));
      expect(await queued(), isEmpty);
    });

    test(
      'a decision stamps the clock when that is later than the tie',
      () async {
        await seedTie();
        final later = tie.add(const Duration(hours: 3, milliseconds: 600));

        await storage.resolveConflicts([
          const SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'theme_mode',
          ),
        ], now: () => later);

        expect(
          (await themeRow()).updatedAt,
          tie.add(const Duration(hours: 3)),
          reason: 'stored timestamps are whole seconds',
        );
      },
    );

    test('is refused, writing nothing, when this device\'s copy changed '
        'after the choice was queued', () async {
      await seedTie();
      final row = (await queued()).single;
      await repositories.settings.set(
        'theme_mode',
        'system',
        at: tie.add(const Duration(minutes: 5)),
      );

      await expectLater(
        storage.resolveConflicts([
          SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'theme_mode',
            keepCandidateHash: row.candidateHash,
          ),
        ], now: () => tie.add(const Duration(minutes: 6))),
        throwsA(
          isA<SyncReviewException>().having(
            (e) => e.code,
            'code',
            SyncReviewFailureCode.candidateChanged,
          ),
        ),
      );
      expect((await themeRow()).value, 'system');
      expect(await queued(), hasLength(1));
    });

    test('is refused when the decision could only be stamped outside the '
        'clock window', () async {
      await seedTie();

      await expectLater(
        storage.resolveConflicts([
          const SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'theme_mode',
          ),
        ], now: () => tie.subtract(const Duration(days: 2))),
        throwsA(
          isA<SyncReviewException>().having(
            (e) => e.code,
            'code',
            SyncReviewFailureCode.clockOutOfRange,
          ),
        ),
      );
      expect((await themeRow()).updatedAt, tie);
      expect(await queued(), hasLength(1));
    });

    test('a batch is all or nothing', () async {
      await repositories.settings.set('theme_mode', 'dark', at: tie);
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 'tag-1', name: 'Local'),
        at: tie,
      );
      const tagAddress = (kind: SyncRecordKind.tag, recordId: 'tag-1');
      final localTheme = await localCandidate(themeAddress);
      final localTag = await localCandidate(tagAddress);
      // One pass raises both, as the coordinator would.
      await storage.refreshConflictReviews(
        engine
            .plan(
              local: {themeAddress: localTheme, tagAddress: localTag},
              baseline: const {},
              peers: [
                {
                  themeAddress: peerVersion(localTheme, {'value': 'light'}),
                  tagAddress: peerVersion(localTag, {
                    ...localTag.blob.body,
                    'name': 'Remote',
                  }),
                },
              ],
            )
            .reviews,
      );
      final themeRowHash = (await queued())
          .firstWhere((row) => row.kind == SyncRecordKind.setting)
          .candidateHash;

      await expectLater(
        storage.resolveConflicts([
          SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'theme_mode',
            keepCandidateHash: themeRowHash,
          ),
          const SyncConflictDecision(
            kind: SyncRecordKind.tag,
            recordId: 'tag-1',
            keepCandidateHash: 'not-on-offer',
          ),
        ], now: () => tie),
        throwsA(isA<SyncReviewException>()),
      );

      expect((await themeRow()).value, 'dark');
      expect(await queued(), hasLength(2));
    });

    test('keeping another device\'s version of an entity applies it through '
        'the inbound path', () async {
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 'tag-1', name: 'Local'),
        at: tie,
      );
      const tagAddress = (kind: SyncRecordKind.tag, recordId: 'tag-1');
      final localTag = await localCandidate(tagAddress);
      await mergeAndQueue(tagAddress, [
        peerVersion(localTag, {...localTag.blob.body, 'name': 'Remote'}),
      ]);
      final row = (await queued()).single;

      final kinds = await storage.resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.tag,
          recordId: 'tag-1',
          keepCandidateHash: row.candidateHash,
        ),
      ], now: () => tie);

      expect(kinds.kinds, {SyncRecordKind.tag});
      final after = await localCandidate(tagAddress);
      expect(after.blob.body['name'], 'Remote');
      expect(after.updatedAt, tie.add(const Duration(seconds: 1)));
      expect(
        after.existenceAt,
        localTag.existenceAt,
        reason: 'a content choice decides nothing about existence',
      );
    });
  });

  group('combine both (whole-collection settings)', () {
    Future<void> seedDialects(
      List<Map<String, Object?>> mine,
      List<Map<String, Object?>> theirs,
    ) async {
      await repositories.settings.set('custom_dialects', mine, at: tie);
      const address = (
        kind: SyncRecordKind.setting,
        recordId: 'custom_dialects',
      );
      final local = await localCandidate(address);
      await mergeAndQueue(address, [
        peerVersion(local, {'value': theirs}),
      ]);
    }

    test("keeps every entry from both, taking the other device's version "
        "only where asked", () async {
      await seedDialects(
        [
          {'name': 'Shared', 'v': 'mine'},
          {'name': 'Mine only'},
        ],
        [
          {'name': 'Shared', 'v': 'theirs'},
          {'name': 'Theirs only'},
        ],
      );

      await storage.resolveConflicts([
        const SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
          combineTakingOther: {'Shared'},
        ),
      ], now: () => tie);

      expect(await repositories.settings.get('custom_dialects'), [
        {'name': 'Shared', 'v': 'theirs'},
        {'name': 'Mine only'},
        {'name': 'Theirs only'},
      ]);
      expect(await queued(), isEmpty);
    });

    test('records every version chosen against, and lists none of them as '
        'a review', () async {
      await seedDialects(
        [
          {'name': 'Mine'},
        ],
        [
          {'name': 'Theirs'},
        ],
      );
      const address = (
        kind: SyncRecordKind.setting,
        recordId: 'custom_dialects',
      );
      final before = await localCandidate(address);
      final offered = (await queued()).single.candidateHash;

      await storage.resolveConflicts([
        const SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
          combineTakingOther: {},
        ),
      ], now: () => tie);

      expect(await storage.decidedAgainstHashes(), {
        address: {before.wireHash, offered},
      });
      expect(await SyncReviewQueueResolver(storage).list(), isEmpty);
      expect(await SyncReviewQueueResolver(storage).conflictCount(), 0);
    });

    test('is refused for a setting that is not a collection', () async {
      await seedTie();

      await expectLater(
        storage.resolveConflicts([
          const SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'theme_mode',
            combineTakingOther: {},
          ),
        ], now: () => tie),
        throwsA(
          isA<SyncReviewException>().having(
            (e) => e.code,
            'code',
            SyncReviewFailureCode.combineUnavailable,
          ),
        ),
      );
      expect(await queued(), hasLength(1));
    });

    test('is refused, writing nothing, when the combination would be more '
        'than the library keeps', () async {
      await seedDialects(
        [
          for (var i = 0; i < syncMaxCustomDialects; i++) {'name': 'mine $i'},
        ],
        [
          {'name': 'theirs'},
        ],
      );

      await expectLater(
        storage.resolveConflicts([
          const SyncConflictDecision(
            kind: SyncRecordKind.setting,
            recordId: 'custom_dialects',
            combineTakingOther: {},
          ),
        ], now: () => tie),
        throwsA(
          isA<SyncReviewException>().having(
            (e) => e.code,
            'code',
            SyncReviewFailureCode.combineOverLimit,
          ),
        ),
      );
      expect(
        (await repositories.settings.get('custom_dialects') as List).length,
        syncMaxCustomDialects,
      );
    });
  });

  group('reconsiderConflicts (undo)', () {
    test('offers the earlier versions again and writes the new choice past '
        'the first', () async {
      await seedTie();
      final row = (await queued()).single;
      final first = await storage.resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
          keepCandidateHash: row.candidateHash,
        ),
      ], now: () => tie);
      expect(await repositories.settings.get('theme_mode'), 'light');
      final earlier = first.reconsiderations.single;
      expect(earlier.before!.body['value'], 'dark');
      expect(earlier.offered.single.body['value'], 'light');

      final second = await storage.reconsiderConflicts([
        SyncConflictRechoice(reconsideration: earlier),
      ], now: () => tie);

      final themeRow = await (db.select(
        db.settings,
      )..where((t) => t.key.equals('theme_mode'))).getSingle();
      expect(await repositories.settings.get('theme_mode'), 'dark');
      expect(
        themeRow.updatedAt!.toUtc(),
        earlier.writtenAt.add(const Duration(seconds: 1)),
        reason: 'the new choice must supersede the first on every device',
      );
      expect(second.reconsiderations.single.before, earlier.before);
    });

    test('changes nothing when no new choice is made', () async {
      await seedTie();
      final row = (await queued()).single;
      await storage.resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
          keepCandidateHash: row.candidateHash,
        ),
      ], now: () => tie);

      await storage.reconsiderConflicts(const [], now: () => tie);

      expect(await repositories.settings.get('theme_mode'), 'light');
    });

    test('is refused, writing nothing, when something newer arrived after '
        'the first choice', () async {
      await seedTie();
      final row = (await queued()).single;
      final first = await storage.resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
          keepCandidateHash: row.candidateHash,
        ),
      ], now: () => tie);
      await repositories.settings.set(
        'theme_mode',
        'system',
        at: tie.add(const Duration(minutes: 5)),
      );

      await expectLater(
        storage.reconsiderConflicts([
          SyncConflictRechoice(reconsideration: first.reconsiderations.single),
        ], now: () => tie.add(const Duration(minutes: 6))),
        throwsA(
          isA<SyncReviewException>().having(
            (e) => e.code,
            'code',
            SyncReviewFailureCode.candidateChanged,
          ),
        ),
      );
      expect(await repositories.settings.get('theme_mode'), 'system');
    });
  });

  group('a copy still filed under an id merged away', () {
    // Two devices each created the same choreographer, and natural-key
    // reconciliation kept this device's id: the other device still publishes
    // its copy under its own id, which the coordinator files under the
    // surviving one. Reconciliation stamps the survivor with that copy's
    // `updatedAt`, so the two tie.
    const address = (kind: SyncRecordKind.choreographer, recordId: 'c1');

    Future<SyncMergeCandidate> mergedAwayCopy(
      Map<String, Object?> Function(Map<String, Object?> body) edit,
    ) async {
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Seth Tepfer'),
        at: tie,
      );
      await repositories.syncLocal.upsertAlias(
        kind: SyncRecordKind.choreographer,
        losingId: 'c2',
        survivingId: 'c1',
      );
      final local = await localCandidate(address);
      return SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'c2',
          updatedAt: local.updatedAt,
          deletedAt: null,
          existenceAt: local.existenceAt,
          body: edit({...local.blob.body, 'id': 'c2'}),
        ),
        peerId: 'peer',
      );
    }

    test('is not a conflict when only the id differs', () async {
      final peer = await mergedAwayCopy((body) => body);

      final plan = await mergeAndQueue(address, [peer]);

      expect(plan.reviews, isEmpty);
      expect(await queued(), isEmpty);
    });

    test('kept in a tie in nothing the user is shown is stored under the '
        'surviving id, not re-stamped, and the tie does not return', () async {
      const dance = (kind: SyncRecordKind.dance, recordId: 'd1');
      await repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Hey Day',
          createdAt: tie,
          updatedAt: tie,
          provenance: Provenance(
            source: ProvenanceSource.contradb,
            importedAt: tie,
          ),
        ),
      );
      await repositories.syncLocal.upsertAlias(
        kind: SyncRecordKind.dance,
        losingId: 'd2',
        survivingId: 'd1',
      );
      const aliases = {
        SyncRecordKind.dance: {'d2': 'd1'},
      };
      final local = await localCandidate(dance);
      String contentOf(Map<String, Object?> body) =>
          contentHash(Map<String, Object?>.from(body)..remove('id'));
      // The other device's copy, under the merged-away id, differing only in
      // when it was imported — picked so that it is the one kept.
      late SyncMergeCandidate peer;
      for (var day = 1; ; day++) {
        final provenance = Map<String, Object?>.from(
          local.blob.body['provenance']! as Map,
        );
        provenance['importedAt'] = (provenance['importedAt']! as String)
            .replaceFirst('2026-09-30', '2026-08-${'$day'.padLeft(2, '0')}');
        final body = {...local.blob.body, 'id': 'd2', 'provenance': provenance};
        if (contentOf(body).compareTo(contentOf(local.blob.body)) < 0) {
          peer = SyncMergeCandidate.fromBlob(
            SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: 'd2',
              updatedAt: local.updatedAt,
              deletedAt: null,
              existenceAt: local.existenceAt,
              body: body,
            ),
            peerId: 'peer',
          );
          break;
        }
      }
      SyncMergeDecision decide(SyncMergeCandidate mine) => engine
          .plan(
            local: {dance: mine},
            baseline: const {},
            peers: [
              {dance: peer},
            ],
            aliases: aliases,
          )
          .decisions
          .single;

      final decision = decide(local);
      expect(decision.action, SyncMergeAction.download);
      expect(decision.winner!.blob.id, 'd1');
      expect(decision.winner!.blob.body['id'], 'd1');

      final result = await SyncApplyEngine(now: () => tie).apply(
        candidates: [decision.winner!],
        storage: storage,
        expectedWireHashes: {dance: local.wireHash},
      );

      expect(result.applied, [dance]);
      final stored = await localCandidate(dance);
      expect(
        stored.updatedAt,
        local.updatedAt,
        reason: 'settling a tie is not a new edit',
      );
      expect(
        (stored.blob.body['provenance']! as Map)['importedAt'],
        (peer.blob.body['provenance']! as Map)['importedAt'],
      );
      expect(await repositories.dances.getById('d2'), isNull);
      expect(decide(stored).action, isNot(SyncMergeAction.download));
      expect(decide(stored).action, isNot(SyncMergeAction.review));
    });

    test('queued before the merge stopped raising it, is not offered or '
        'counted', () async {
      // What an earlier version of the merge queued for exactly this case.
      final peer = await mergedAwayCopy((body) => body);
      await repositories.syncLocal.enqueueReview(
        kind: SyncRecordKind.choreographer,
        recordId: 'c1',
        counterpartId: peer.wireHash,
        reason: syncConflictChoiceReason,
        candidateBlob: encodeSyncRecordBlob(peer.blob),
        candidateHash: peer.wireHash,
        localHash: (await localCandidate(address)).wireHash,
        queuedAt: tie,
      );
      final resolver = SyncReviewQueueResolver(storage);

      expect(await resolver.listConflicts(), isEmpty);
      expect(await resolver.conflictCount(), 0);

      // The next pass, which no longer raises it, drops the row.
      await mergeAndQueue(address, [peer]);
      expect(await queued(), isEmpty);
    });

    for (final keepOther in [false, true]) {
      test('can be decided either way when its content differs '
          '(keeping ${keepOther ? 'the other' : 'this'} device\'s)', () async {
        final peer = await mergedAwayCopy(
          (body) => {...body, 'notes': 'from the other device'},
        );
        await mergeAndQueue(address, [peer]);
        final row = (await queued()).single;

        await storage.resolveConflicts([
          SyncConflictDecision(
            kind: SyncRecordKind.choreographer,
            recordId: 'c1',
            keepCandidateHash: keepOther ? row.candidateHash : null,
          ),
        ]);

        expect(await queued(), isEmpty);
        final kept = await repositories.choreographers.getById('c1');
        expect(kept?.notes, keepOther ? 'from the other device' : isNull);
        expect(await repositories.choreographers.getById('c2'), isNull);
      });
    }
  });
}
