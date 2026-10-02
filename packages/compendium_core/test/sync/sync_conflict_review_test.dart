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
    final plan = engine.plan(
      local: {address: local},
      baseline: const {},
      peers: [
        for (final peer in peers) {address: peer},
      ],
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

      expect(kinds, {SyncRecordKind.setting});
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

      expect(kinds, {SyncRecordKind.tag});
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
}
