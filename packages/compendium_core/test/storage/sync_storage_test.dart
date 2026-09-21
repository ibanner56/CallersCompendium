import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/serialization/archive_entity_codec.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:compendium_core/testing.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'test_database.dart';

final class _SqliteBindLimitGuard extends QueryInterceptor {
  static const maxVariables = 999;

  void _check(List<Object?> args) {
    if (args.length > maxVariables) {
      throw StateError(
        'test SQLite bind limit exceeded: ${args.length} > $maxVariables',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(args);
    return super.runDelete(executor, statement, args);
  }
}

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  test(
    'snapshots and applies through the real repository transaction seam',
    () async {
      final localStamp = DateTime.utc(2025, 1, 1, 12);
      final remoteStamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(
          id: 'c1',
          name: 'Local name',
          email: 'private@example.com',
          location: 'Private locality',
        ),
        at: localStamp,
      );

      final snapshot = await storage.snapshot();
      final local =
          snapshot.local[(kind: SyncRecordKind.choreographer, recordId: 'c1')];
      expect(local, isNotNull);
      expect(local!.blob.body, isNot(contains('email')));

      final remote = SyncRecordBlob(
        kind: SyncRecordKind.choreographer,
        id: 'c1',
        updatedAt: remoteStamp,
        deletedAt: null,
        existenceAt: localStamp,
        body: const {'id': 'c1', 'name': 'Remote name'},
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: remote)],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: 'c1'),
      ]);
      final stored = await repositories.choreographers.getById('c1');
      expect(stored!.name, 'Remote name');
      expect(stored.email, 'private@example.com');
      expect(stored.location, 'Private locality');

      final row = await (db.select(
        db.choreographers,
      )..where((table) => table.id.equals('c1'))).getSingle();
      expect(row.updatedAt!.toUtc(), remoteStamp);
      expect(row.existenceAt!.toUtc(), localStamp);
      expect(row.deletedAt, isNull);
    },
  );

  test(
    'rejects a noncanonical natural-key body before reconciliation side effects',
    () async {
      final localStamp = DateTime.utc(2025, 1, 1, 12);
      final remoteStamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 'local-tag', name: 'Café'),
        at: localStamp,
      );
      final noncanonicalTag = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.tag,
          id: 'remote-tag',
          updatedAt: remoteStamp,
          deletedAt: null,
          existenceAt: remoteStamp,
          body: {'id': 'remote-tag', 'name': 'Caf\u0065\u0301'},
        ),
        peerId: 'peer-a',
      );
      final valid = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'valid-peer',
          updatedAt: remoteStamp,
          deletedAt: null,
          existenceAt: remoteStamp,
          body: {'id': 'valid-peer', 'name': 'Valid peer'},
        ),
        peerId: 'peer-a',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [noncanonicalTag, valid],
        storage: storage,
      );

      expect(result.applied, [valid.address]);
      expect(result.reports.single.code, SyncReportCode.nonCanonicalWireBody);
      expect(result.reports.single.peerId, 'peer-a');
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.tag,
          recordId: noncanonicalTag.blob.id,
        ),
        noncanonicalTag.blob.id,
      );
      expect(await repositories.tags.getById('local-tag'), isNotNull);
      expect(await repositories.tags.getById('remote-tag'), isNull);
      expect(
        await repositories.choreographers.getById('valid-peer'),
        isNotNull,
      );
    },
  );

  test(
    'uses envelope timestamps for inbound dance and program bodies',
    () async {
      final createdAt = DateTime.utc(2020, 1, 1, 12);
      final bodyStamp = DateTime.utc(2099, 1, 1, 12);
      final liveStamp = DateTime.utc(2026, 1, 1, 12);
      final tombstoneStamp = DateTime.utc(2026, 1, 1, 12, 1);

      final liveDance = Dance(
        id: 'inbound-timestamp-live-dance',
        title: 'Inbound timestamp live dance',
        createdAt: createdAt,
        updatedAt: bodyStamp,
        deletedAt: bodyStamp,
      );
      final tombstonedDance = Dance(
        id: 'inbound-timestamp-tombstone-dance',
        title: 'Inbound timestamp tombstone dance',
        createdAt: createdAt,
        updatedAt: bodyStamp,
      );
      final liveProgram = Program(
        id: 'inbound-timestamp-live-program',
        title: 'Inbound timestamp live program',
        createdAt: createdAt,
        updatedAt: bodyStamp,
        deletedAt: bodyStamp,
      );
      final tombstonedProgram = Program(
        id: 'inbound-timestamp-tombstone-program',
        title: 'Inbound timestamp tombstone program',
        createdAt: createdAt,
        updatedAt: bodyStamp,
      );

      SyncMergeCandidate candidate(
        SyncRecordKind kind,
        Object entity,
        DateTime envelopeUpdatedAt,
        DateTime? envelopeDeletedAt,
      ) {
        final id = switch (entity) {
          Dance value => value.id,
          Program value => value.id,
          _ => throw ArgumentError('unexpected sync entity'),
        };
        return SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: kind,
            id: id,
            updatedAt: envelopeUpdatedAt,
            deletedAt: envelopeDeletedAt,
            existenceAt: envelopeUpdatedAt,
            body: syncBodyForEntity(kind, entity),
          ),
        );
      }

      final candidates = [
        candidate(SyncRecordKind.dance, liveDance, liveStamp, null),
        candidate(
          SyncRecordKind.dance,
          tombstonedDance,
          tombstoneStamp,
          tombstoneStamp,
        ),
        candidate(SyncRecordKind.program, liveProgram, liveStamp, null),
        candidate(
          SyncRecordKind.program,
          tombstonedProgram,
          tombstoneStamp,
          tombstoneStamp,
        ),
      ];

      final result = await const SyncApplyEngine().apply(
        candidates: candidates,
        storage: storage,
      );

      expect(result.applied, [
        for (final candidate in candidates) candidate.address,
      ]);

      Future<void> expectPublished({
        required SyncRecordKind kind,
        required String id,
        required DateTime expectedUpdatedAt,
        required DateTime? expectedDeletedAt,
      }) async {
        final stored = switch (kind) {
          SyncRecordKind.dance => await repositories.dances.getById(
            id,
            includeDeleted: true,
          ),
          SyncRecordKind.program => await repositories.programs.getById(
            id,
            includeDeleted: true,
          ),
          _ => throw ArgumentError('unexpected sync kind'),
        };
        switch (stored) {
          case Dance value:
            expect(value.createdAt.toUtc(), createdAt);
            expect(value.updatedAt.toUtc(), expectedUpdatedAt);
            expect(value.deletedAt?.toUtc(), expectedDeletedAt);
          case Program value:
            expect(value.createdAt.toUtc(), createdAt);
            expect(value.updatedAt.toUtc(), expectedUpdatedAt);
            expect(value.deletedAt?.toUtc(), expectedDeletedAt);
          case null:
            fail('expected $kind/$id to be persisted');
          default:
            fail('unexpected stored entity type: ${stored.runtimeType}');
        }

        final address = (kind: kind, recordId: id);
        final publication = (await storage.snapshot()).publication[address];
        expect(publication, isNotNull);
        final blob = publication!.blob;
        expect(blob.updatedAt, expectedUpdatedAt);
        expect(blob.deletedAt, expectedDeletedAt);
        expect(blob.body['createdAt'], createdAt.toIso8601String());
        expect(blob.body['updatedAt'], expectedUpdatedAt.toIso8601String());
        expect(blob.body['deletedAt'], expectedDeletedAt?.toIso8601String());
      }

      await expectPublished(
        kind: SyncRecordKind.dance,
        id: liveDance.id,
        expectedUpdatedAt: liveStamp,
        expectedDeletedAt: null,
      );
      await expectPublished(
        kind: SyncRecordKind.dance,
        id: tombstonedDance.id,
        expectedUpdatedAt: tombstoneStamp,
        expectedDeletedAt: tombstoneStamp,
      );
      await expectPublished(
        kind: SyncRecordKind.program,
        id: liveProgram.id,
        expectedUpdatedAt: liveStamp,
        expectedDeletedAt: null,
      );
      await expectPublished(
        kind: SyncRecordKind.program,
        id: tombstonedProgram.id,
        expectedUpdatedAt: tombstoneStamp,
        expectedDeletedAt: tombstoneStamp,
      );

      final publishedAddress = (
        kind: SyncRecordKind.dance,
        recordId: liveDance.id,
      );
      final published =
          (await storage.snapshot()).publication[publishedAddress]!;
      final mergePlan = const SyncMergeEngine().plan(
        local: {published.address: published},
        baseline: {
          published.address: SyncBaselineEntry(
            kind: published.address.kind,
            recordId: published.address.recordId,
            wireHash: published.wireHash,
          ),
        },
        peers: [
          {
            published.address: SyncMergeCandidate(
              blob: published.blob,
              wireHash: published.wireHash,
              peerId: 'peer-a',
            ),
          },
        ],
      );
      expect(mergePlan.reports, isEmpty);
      expect(mergePlan.decisions.single.action, SyncMergeAction.none);
    },
  );

  test(
    'preflight admits malformed embedded timestamps when the envelope is valid',
    () async {
      final createdAt = DateTime.utc(2020, 1, 1, 12);
      final bodyStamp = DateTime.utc(2099, 1, 1, 12);
      final liveStamp = DateTime.utc(2026, 2, 1, 12);
      final tombstoneStamp = DateTime.utc(2026, 2, 1, 12, 1);

      SyncMergeCandidate malformedCandidate({
        required SyncRecordKind kind,
        required String id,
        required Object entity,
        required DateTime updatedAt,
        required DateTime? deletedAt,
      }) {
        final body = Map<String, Object?>.from(syncBodyForEntity(kind, entity))
          ..['updatedAt'] = 'not-a-timestamp'
          ..['deletedAt'] = 'also-not-a-timestamp';
        return SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: kind,
            id: id,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            existenceAt: updatedAt,
            body: body,
          ),
        );
      }

      final candidates = [
        malformedCandidate(
          kind: SyncRecordKind.dance,
          id: 'inbound-timestamp-preflight-dance',
          entity: Dance(
            id: 'inbound-timestamp-preflight-dance',
            title: 'Preflight malformed dance',
            createdAt: createdAt,
            updatedAt: bodyStamp,
          ),
          updatedAt: liveStamp,
          deletedAt: null,
        ),
        malformedCandidate(
          kind: SyncRecordKind.program,
          id: 'inbound-timestamp-preflight-program',
          entity: Program(
            id: 'inbound-timestamp-preflight-program',
            title: 'Preflight malformed program',
            createdAt: createdAt,
            updatedAt: bodyStamp,
          ),
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
        ),
      ];

      final result = await const SyncApplyEngine().apply(
        candidates: candidates,
        storage: storage,
      );

      expect(result.applied, [
        for (final candidate in candidates) candidate.address,
      ]);
      expect(result.reports, isEmpty);

      final storedDance = await repositories.dances.getById(
        candidates[0].blob.id,
        includeDeleted: true,
      );
      expect(storedDance, isNotNull);
      expect(storedDance!.createdAt.toUtc(), createdAt);
      expect(storedDance.updatedAt.toUtc(), liveStamp);
      expect(storedDance.deletedAt, isNull);

      final storedProgram = await repositories.programs.getById(
        candidates[1].blob.id,
        includeDeleted: true,
      );
      expect(storedProgram, isNotNull);
      expect(storedProgram!.createdAt.toUtc(), createdAt);
      expect(storedProgram.updatedAt.toUtc(), tombstoneStamp);
      expect(storedProgram.deletedAt?.toUtc(), tombstoneStamp);

      final publication = (await storage.snapshot()).publication;
      final danceBody = publication[candidates[0].address]!.blob.body;
      expect(danceBody['updatedAt'], liveStamp.toIso8601String());
      expect(danceBody['deletedAt'], isNull);
      final programBody = publication[candidates[1].address]!.blob.body;
      expect(programBody['updatedAt'], tombstoneStamp.toIso8601String());
      expect(programBody['deletedAt'], tombstoneStamp.toIso8601String());
    },
  );

  test('normalizes pending dance tombstone publication and replay', () async {
    final createdAt = DateTime.utc(2020, 1, 1, 12);
    final bodyStamp = DateTime.utc(2099, 1, 1, 12);
    final localStamp = DateTime.utc(2025, 1, 1, 12);
    final tombstoneStamp = DateTime.utc(2026, 1, 1, 12);
    final dance = Dance(
      id: 'inbound-timestamp-pending-dance',
      title: 'Inbound timestamp pending dance',
      createdAt: createdAt,
      updatedAt: localStamp,
    );
    await repositories.dances.create(dance);
    final citingProgram = Program(
      id: 'inbound-timestamp-citing-program',
      title: 'Inbound timestamp citing program',
      slots: [
        ProgramSlot(
          id: 'inbound-timestamp-citing-slot',
          position: 0,
          danceId: dance.id,
        ),
      ],
      createdAt: createdAt,
      updatedAt: localStamp,
    );
    await repositories.programs.create(citingProgram);

    final poisonedBody =
        Map<String, Object?>.from(
            syncBodyForEntity(SyncRecordKind.dance, dance),
          )
          ..['updatedAt'] = bodyStamp.toIso8601String()
          ..['deletedAt'] = bodyStamp.toIso8601String();
    final tombstone = SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: dance.id,
        updatedAt: tombstoneStamp,
        deletedAt: tombstoneStamp,
        existenceAt: tombstoneStamp,
        body: poisonedBody,
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [tombstone],
      storage: storage,
    );

    expect(result.reports, isEmpty);
    final pending = await repositories.syncLocal.getPendingDeletion(
      kind: SyncRecordKind.dance,
      recordId: dance.id,
    );
    expect(pending, isNotNull);
    final canonicalTombstone = SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: dance.id,
      updatedAt: tombstoneStamp,
      deletedAt: tombstoneStamp,
      existenceAt: tombstoneStamp,
      body: {
        ...poisonedBody,
        'updatedAt': tombstoneStamp.toIso8601String(),
        'deletedAt': tombstoneStamp.toIso8601String(),
      },
    );
    expect(
      pending!.tombstoneHash,
      SyncMergeCandidate.fromBlob(canonicalTombstone).wireHash,
    );
    expect(pending.tombstoneHash, isNot(tombstone.wireHash));
    expect(
      decodeSyncRecordBlob(pending.tombstoneBlob).body,
      canonicalTombstone.body,
    );

    Future<void> expectPublishedTombstone() async {
      final publication =
          (await storage.snapshot()).publication[tombstone.address];
      expect(publication, isNotNull);
      final blob = publication!.blob;
      expect(blob.updatedAt, tombstoneStamp);
      expect(blob.deletedAt, tombstoneStamp);
      expect(blob.body['createdAt'], createdAt.toIso8601String());
      expect(blob.body['updatedAt'], tombstoneStamp.toIso8601String());
      expect(blob.body['deletedAt'], tombstoneStamp.toIso8601String());
    }

    await expectPublishedTombstone();

    await repositories.programs.update(citingProgram.copyWith(slots: const []));

    final replayedSnapshot = await storage.snapshot();
    expect(
      await repositories.syncLocal.getPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: dance.id,
      ),
      isNull,
    );
    final stored = await repositories.dances.getById(
      dance.id,
      includeDeleted: true,
    );
    expect(stored, isNotNull);
    expect(stored!.createdAt.toUtc(), createdAt);
    expect(stored.updatedAt.toUtc(), tombstoneStamp);
    expect(stored.deletedAt?.toUtc(), tombstoneStamp);
    final replayed = replayedSnapshot.publication[tombstone.address];
    expect(replayed, isNotNull);
    expect(replayed!.blob.body['updatedAt'], tombstoneStamp.toIso8601String());
    expect(replayed.blob.body['deletedAt'], tombstoneStamp.toIso8601String());
  });

  test(
    'fresh attach dedupe rewires aliases, slots, links, indexes, and timestamps',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final survivor = Dance(
        id: 'a-survivor',
        title: 'shared dance',
        walkthrough: 'survivor',
        rating: 1,
        createdAt: stamp,
        updatedAt: stamp,
      );
      final loser = Dance(
        id: 'z-loser',
        title: 'The Shared Dance',
        walkthrough: 'newer loser',
        rating: 5,
        links: [
          DanceLink(
            id: 'loser-owned-link',
            kind: LinkKind.relatedDance,
            targetDanceId: 'c-related',
          ),
          DanceLink(
            id: 'loser-self-link',
            kind: LinkKind.relatedDance,
            targetDanceId: survivor.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp.add(const Duration(minutes: 1)),
      );
      await repositories.dances.create(survivor);
      await repositories.dances.create(
        Dance(
          id: 'c-related',
          title: 'Related dance',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.dances.create(loser);

      final owner = Dance(
        id: 'c-owner',
        title: 'Owner',
        links: [
          DanceLink(
            id: 'owner-link',
            kind: LinkKind.relatedDance,
            targetDanceId: loser.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(owner);

      final program = Program(
        id: 'program-with-loser',
        title: 'Program',
        slots: [ProgramSlot(id: 'loser-slot', position: 0, danceId: loser.id)],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.programs.create(program);
      final beforeProgram = await (db.select(
        db.programs,
      )..where((row) => row.id.equals(program.id))).getSingle();

      final result = await storage.deduplicateFreshAttach();

      expect(result.duplicateCount, 1);
      expect(await repositories.dances.getById(loser.id), isNull);
      final merged = await repositories.dances.getById(survivor.id);
      expect(merged!.walkthrough, 'newer loser');
      expect(merged.rating, 5);
      expect(merged.links.map((link) => link.id), ['loser-owned-link']);
      expect(merged.links.single.targetDanceId, 'c-related');
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.dance,
          recordId: loser.id,
        ),
        survivor.id,
      );
      expect(
        (await repositories.programs.getById(program.id))!.slots.single.danceId,
        survivor.id,
      );
      expect(
        (await repositories.dances.getById(
          owner.id,
        ))!.links.single.targetDanceId,
        survivor.id,
      );

      final afterProgram = await (db.select(
        db.programs,
      )..where((row) => row.id.equals(program.id))).getSingle();
      expect(afterProgram.updatedAt, isNot(beforeProgram.updatedAt));

      for (final table in [
        'dance_figures',
        'dance_fts',
        'dance_substring_fts',
      ]) {
        final rows = await db
            .customSelect(
              'SELECT dance_id FROM $table WHERE dance_id = ?',
              variables: [Variable.withString(loser.id)],
            )
            .get();
        expect(rows, isEmpty, reason: table);
      }
    },
  );

  test(
    'fresh attach dedupe rebuilds FTS once across duplicate groups',
    () async {
      final counter = FtsDeleteByDanceCounter();
      await db.close();
      final countingDb = openCountingTestDatabase(counter);
      db = countingDb;
      final countingRepositories = CompendiumRepositories(
        countingDb,
        contraTaxonomy,
      );
      final countingStorage = CompendiumSyncStorage(countingRepositories);
      final stamp = DateTime.utc(2026, 7, 15, 12);
      for (var i = 0; i < 6; i++) {
        final group = i ~/ 2;
        await countingRepositories.dances.create(
          Dance(
            id: i.isEven ? 'a-survivor-$group' : 'z-loser-$i',
            title: 'Shared dance $group',
            createdAt: stamp,
            updatedAt: stamp.add(Duration(seconds: i)),
          ),
        );
      }
      counter.count = 0;

      final result = await countingStorage.deduplicateFreshAttach();

      expect(result.duplicateCount, 3);
      // All survivor writes defer derived maintenance; the complete pass uses
      // one bulk rebuild rather than one unindexed FTS delete per group.
      expect(counter.count, 0);
    },
  );

  test(
    'fresh attach preserves loser-owned private custom-field values',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final privateField = CustomFieldDef(
        id: 'private-dedupe-field',
        key: 'private_dedupe_field',
        label: 'Private dedupe field',
        type: CustomFieldType.text,
        shareable: false,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(privateField, at: stamp);
      final survivor = Dance(
        id: 'a-survivor',
        title: 'Shared dance',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final loser = Dance(
        id: 'z-loser',
        title: 'The Shared Dance',
        customFields: [
          CustomFieldValue(fieldId: privateField.id, value: 'keep locally'),
        ],
        createdAt: stamp,
        updatedAt: stamp.add(const Duration(minutes: 1)),
      );
      await repositories.dances.create(survivor);
      await repositories.dances.create(loser);

      final result = await storage.deduplicateFreshAttach();

      expect(result.duplicateCount, 1);
      expect((await repositories.dances.getById(survivor.id))!.customFields, [
        CustomFieldValue(fieldId: privateField.id, value: 'keep locally'),
      ]);
      expect(await repositories.dances.getById(loser.id), isNull);
      final wire = (await storage.snapshot())
          .local[(kind: SyncRecordKind.dance, recordId: survivor.id)]!;
      expect(wire.blob.body['customFields'], isEmpty);
    },
  );

  test(
    'fresh attach ambiguity is immutable and review-queue insertion is idempotent',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      await repositories.dances.create(
        Dance(
          id: 'a-left',
          title: 'The Shared Dance',
          figures: [
            testFigure(move: 'balance', params: const {'hand': 'left'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.dances.create(
        Dance(
          id: 'b-right',
          title: 'shared dance',
          figures: [
            testFigure(move: 'balance', params: const {'hand': 'right'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

      final first = await storage.deduplicateFreshAttach();
      final firstRow = (await repositories.syncLocal.listReviewQueue()).single;
      final second = await storage.deduplicateFreshAttach();
      final rows = await repositories.syncLocal.listReviewQueue();

      expect(first.duplicateCount, 0);
      expect(first.reports.single.code, SyncReportCode.equalUpdatedAt);
      expect(second.duplicateCount, 0);
      expect(second.reports.single.code, SyncReportCode.equalUpdatedAt);
      expect(rows, hasLength(1));
      expect(rows.single.candidateBlob, firstRow.candidateBlob);
      expect(rows.single.candidateHash, firstRow.candidateHash);
      expect(rows.single.localHash, firstRow.localHash);
      expect(rows.single.localHash, isNotNull);
      expect(rows.single.recordId, 'a-left');
      expect(rows.single.counterpartId, 'b-right');
    },
  );

  test(
    'keeps ambiguity pairs distinct when dance IDs contain colons',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      for (final entry in [
        (
          id: 'a',
          figure: testFigure(move: 'balance', params: const {'hand': 'left'}),
        ),
        (
          id: 'a:b',
          figure: testFigure(move: 'balance', params: const {'hand': 'right'}),
        ),
        (id: 'b:c', figure: testFigure(move: 'swing')),
        (id: 'c', figure: testFigure(move: 'star')),
      ]) {
        await repositories.dances.create(
          Dance(
            id: entry.id,
            title: 'Shared dance',
            figures: [entry.figure],
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
      }

      await storage.deduplicateFreshAttach();
      final expectedPairs = {
        ('a', 'a:b'),
        ('a', 'b:c'),
        ('a', 'c'),
        ('a:b', 'b:c'),
        ('a:b', 'c'),
        ('b:c', 'c'),
      };
      Future<Set<(String, String)>> queuedPairs() async =>
          (await repositories.syncLocal.listReviewQueue())
              .map((row) => (row.recordId, row.counterpartId))
              .toSet();

      expect(await queuedPairs(), expectedPairs);

      await storage.refreshDanceAmbiguityReviews();
      expect(await queuedPairs(), expectedPairs);

      final first = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.getReviewQueue(
          kind: SyncRecordKind.dance,
          recordId: 'a',
          counterpartId: 'a:b',
        ))!,
      );
      await storage.resolveReviewQueue(
        expectedRow: first.row,
        action: SyncReviewAction.merge,
      );

      expect(await queuedPairs(), {('a', 'b:c'), ('a', 'c'), ('b:c', 'c')});
    },
  );

  test(
    'resolves a live dance ambiguity by merging the chosen records',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      await repositories.dances.create(
        Dance(
          id: 'a-left',
          title: 'Shared dance',
          figures: [
            testFigure(move: 'balance', params: const {'hand': 'left'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.dances.create(
        Dance(
          id: 'b-right',
          title: 'The shared dance',
          figures: [
            testFigure(move: 'balance', params: const {'hand': 'right'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

      await storage.deduplicateFreshAttach();
      final item = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.listReviewQueue()).single,
      );
      expect(item.isActionable, isTrue);
      expect(item.isDanceAmbiguity, isTrue);

      await storage.resolveReviewQueue(
        expectedRow: item.row,
        action: SyncReviewAction.merge,
      );

      expect(await repositories.dances.getById('b-right'), isNull);
      expect(await repositories.dances.getById('a-left'), isNotNull);
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.dance,
          recordId: 'b-right',
        ),
        'a-left',
      );
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    },
  );

  test('rejects a dance ambiguity after an ordinary local edit', () async {
    final stamp = DateTime.utc(2026, 7, 15, 12);
    await repositories.dances.create(
      Dance(
        id: 'a-edited',
        title: 'Shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'left'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await repositories.dances.create(
      Dance(
        id: 'b-edited',
        title: 'The shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'right'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );

    await storage.deduplicateFreshAttach();
    final item = SyncReviewQueueItem.fromRow(
      (await repositories.syncLocal.listReviewQueue()).single,
    );
    final before = await (db.select(
      db.dances,
    )..where((row) => row.id.equals('a-edited'))).getSingle();
    final local = (await repositories.dances.getById('a-edited'))!;
    await repositories.dances.update(
      local.copyWith(
        rating: 4,
        updatedAt: stamp.add(const Duration(minutes: 3)),
      ),
    );
    final after = await (db.select(
      db.dances,
    )..where((row) => row.id.equals('a-edited'))).getSingle();
    expect(after.existenceAt, before.existenceAt);
    expect(after.updatedAt, isNot(before.updatedAt));

    await expectLater(
      storage.resolveReviewQueue(
        expectedRow: item.row,
        action: SyncReviewAction.merge,
      ),
      throwsA(
        isA<SyncReviewException>().having(
          (error) => error.code,
          'code',
          SyncReviewFailureCode.candidateChanged,
        ),
      ),
    );
    expect((await repositories.dances.getById('a-edited'))!.rating, 4);
    expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
  });

  test(
    'reconciles sibling dance ambiguities after merging one of three groups',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      for (final entry in [
        (id: 'a-left', hand: 'left'),
        (id: 'b-right', hand: 'right'),
        (id: 'c-swing', hand: 'swing'),
      ]) {
        await repositories.dances.create(
          Dance(
            id: entry.id,
            title: 'Shared dance',
            figures: [
              entry.hand == 'swing'
                  ? testFigure(move: 'swing')
                  : testFigure(move: 'balance', params: {'hand': entry.hand}),
            ],
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
      }

      await storage.deduplicateFreshAttach();
      expect(
        (await repositories.syncLocal.listReviewQueue()).map(
          (row) => (row.recordId, row.counterpartId),
        ),
        [('a-left', 'b-right'), ('a-left', 'c-swing'), ('b-right', 'c-swing')],
      );

      final first = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.getReviewQueue(
          kind: SyncRecordKind.dance,
          recordId: 'a-left',
          counterpartId: 'b-right',
        ))!,
      );
      await storage.resolveReviewQueue(
        expectedRow: first.row,
        action: SyncReviewAction.merge,
      );

      final remaining = await repositories.syncLocal.listReviewQueue();
      expect(remaining.map((row) => (row.recordId, row.counterpartId)), [
        ('a-left', 'c-swing'),
      ]);
      final current = await storage.snapshot();
      expect(
        remaining.single.localHash,
        current
            .local[(kind: SyncRecordKind.dance, recordId: 'a-left')]!
            .wireHash,
      );
      expect(
        remaining.single.candidateHash,
        current
            .local[(kind: SyncRecordKind.dance, recordId: 'c-swing')]!
            .wireHash,
      );
      expect(await repositories.dances.getById('b-right'), isNull);
      expect(
        SyncReviewQueueItem.fromRow(remaining.single).isActionable,
        isTrue,
      );

      await storage.resolveReviewQueue(
        expectedRow: remaining.single,
        action: SyncReviewAction.merge,
      );
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    },
  );

  test(
    'drops sibling dance ambiguities after keeping one of three groups',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      for (final entry in [
        (id: 'a-left', hand: 'left'),
        (id: 'b-right', hand: 'right'),
        (id: 'c-swing', hand: 'swing'),
      ]) {
        await repositories.dances.create(
          Dance(
            id: entry.id,
            title: 'Shared dance',
            figures: [
              entry.hand == 'swing'
                  ? testFigure(move: 'swing')
                  : testFigure(move: 'balance', params: {'hand': entry.hand}),
            ],
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
      }

      await storage.deduplicateFreshAttach();
      final first = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.getReviewQueue(
          kind: SyncRecordKind.dance,
          recordId: 'a-left',
          counterpartId: 'b-right',
        ))!,
      );
      await storage.resolveReviewQueue(
        expectedRow: first.row,
        action: SyncReviewAction.keepBoth,
        newNaturalKey: 'Renamed dance',
      );

      final remaining = await repositories.syncLocal.listReviewQueue();
      expect(remaining.map((row) => (row.recordId, row.counterpartId)), [
        ('b-right', 'c-swing'),
      ]);
      expect(
        (await repositories.dances.getById('a-left'))!.title,
        'Renamed dance',
      );
      expect(
        SyncReviewQueueItem.fromRow(remaining.single).isActionable,
        isTrue,
      );
    },
  );

  test('resolves a live dance ambiguity by renaming the local dance', () async {
    final stamp = DateTime.utc(2026, 7, 15, 12);
    await repositories.dances.create(
      Dance(
        id: 'a-left',
        title: 'Shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'left'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await repositories.dances.create(
      Dance(
        id: 'b-right',
        title: 'The shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'right'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );

    await storage.deduplicateFreshAttach();
    final item = SyncReviewQueueItem.fromRow(
      (await repositories.syncLocal.listReviewQueue()).single,
    );

    await storage.resolveReviewQueue(
      expectedRow: item.row,
      action: SyncReviewAction.keepBoth,
      newNaturalKey: 'A different dance',
    );

    expect(
      (await repositories.dances.getById('a-left'))!.title,
      'A different dance',
    );
    expect(await repositories.dances.getById('b-right'), isNotNull);
    expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
  });

  test(
    'fresh attach does not dedupe a dance held by a pending tombstone',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final held = Dance(
        id: 'a-held',
        title: 'Shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'left'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final independent = Dance(
        id: 'z-independent',
        title: 'The Shared Dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'right'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(held);
      await repositories.dances.create(independent);
      final program = Program(
        id: 'holding-program',
        title: 'Holding program',
        slots: [ProgramSlot(id: 'holding-slot', position: 0, danceId: held.id)],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.programs.create(program);
      await storage.deduplicateFreshAttach();
      expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));

      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final tombstone = SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: held.id,
        updatedAt: tombstoneStamp,
        deletedAt: tombstoneStamp,
        existenceAt: stamp,
        body: syncBodyForEntity(SyncRecordKind.dance, held),
      );
      await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: tombstone)],
        storage: storage,
      );

      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.dance,
          recordId: held.id,
        ),
        isNotNull,
      );
      await storage.refreshDanceAmbiguityReviews();
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      final dedupe = await storage.deduplicateFreshAttach();
      expect(dedupe.duplicateCount, 0);
      expect(await repositories.dances.getById(held.id), isNotNull);
      expect(await repositories.dances.getById(independent.id), isNotNull);

      final currentProgram = await repositories.programs.getById(program.id);
      await repositories.programs.update(
        currentProgram!.copyWith(
          slots: const [],
          updatedAt: tombstoneStamp.add(const Duration(minutes: 1)),
        ),
      );
      await storage.revalidatePendingDeletions();

      expect(await repositories.dances.getById(held.id), isNull);
      expect(await repositories.dances.getById(independent.id), isNotNull);
    },
  );

  test(
    'tracks prior use by sync identity even when the collection is empty',
    () async {
      expect(
        (await storage.snapshot(syncId: 'sync-a')).previouslyUsed,
        isFalse,
      );

      await storage.markSyncUsed('sync-a');

      expect((await storage.snapshot(syncId: 'sync-a')).previouslyUsed, isTrue);
      expect(
        (await storage.snapshot(syncId: 'sync-b')).previouslyUsed,
        isFalse,
      );

      await storage.markSyncUsed('sync-b');

      expect((await storage.snapshot(syncId: 'sync-a')).previouslyUsed, isTrue);
      expect((await storage.snapshot(syncId: 'sync-b')).previouslyUsed, isTrue);
    },
  );

  test(
    'stores salted slow verifiers and migrates legacy fast markers',
    () async {
      await repositories.settings.set(syncLastUsedFingerprintKey, [
        sha256Hex(utf8.encode('sync-a')),
      ]);
      await storage.snapshot();
      expect(
        await repositories.settings.get(syncLastUsedFingerprintKey),
        const <Object?>[],
      );

      await repositories.settings.set(syncLastUsedFingerprintKey, [
        sha256Hex(utf8.encode('sync-a')),
      ]);

      expect((await storage.snapshot(syncId: 'sync-a')).previouslyUsed, isTrue);

      final marker = await repositories.settings.get(
        syncLastUsedFingerprintKey,
      );
      final entries = (marker! as List).cast<Object?>();
      expect(entries, hasLength(1));
      final verifier = (entries.single as Map).cast<String, Object?>();
      expect(verifier['algorithm'], 'pbkdf2-sha256');
      expect(verifier['iterations'], 600000);
      expect(verifier['salt'], isA<String>());
      expect(verifier['verifier'], isA<String>());
      expect(verifier['verifier'], isNot(sha256Hex(utf8.encode('sync-a'))));

      await storage.markSyncUsed('sync-b');
      final migrated = await repositories.settings.get(
        syncLastUsedFingerprintKey,
      );
      expect((migrated! as List), hasLength(2));
      expect((await storage.snapshot(syncId: 'sync-b')).previouslyUsed, isTrue);
    },
  );

  test(
    'skips an inbound record with an unavailable reference and applies peers',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final invalidDance = Dance(
        id: 'bad-dance',
        title: 'Bad dance',
        difficultyLevelId: 'missing-level',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final validChoreographer = Choreographer(
        id: 'c2',
        name: 'Remote choreographer',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: invalidDance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, invalidDance),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: validChoreographer.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.choreographer,
                validChoreographer,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: 'c2'),
      ]);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(await repositories.choreographers.getById('c2'), isNotNull);
      expect(await repositories.dances.getById('bad-dance'), isNull);
    },
  );

  test(
    'applies an inbound tombstone citing a locally tombstoned difficulty level',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // A custom level this device has since deleted. Deleting it is permitted
      // once no live dance cites it.
      await db
          .into(db.difficultyLevels)
          .insert(
            DifficultyLevelsCompanion.insert(
              id: 'custom-level',
              label: 'Sizzling',
              position: 99,
              updatedAt: Value(stamp),
              deletedAt: Value(stamp),
              existenceAt: Value(stamp),
            ),
          );
      // A peer deletes a dance that cited that level; this device never held
      // the dance itself.
      final deletedDance = Dance(
        id: 'peer-dance',
        title: 'Peer dance',
        difficultyLevelId: 'custom-level',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final unrelated = Choreographer(
        id: 'peer-choreographer',
        name: 'Unrelated peer choreographer',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: deletedDance.id,
              updatedAt: stamp,
              deletedAt: stamp,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, deletedDance),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: unrelated.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.choreographer, unrelated),
            ),
          ),
        ],
        storage: storage,
      );

      // The tombstone applies rather than failing its write: a record that is
      // itself deleted may cite a deleted level, which is exactly what
      // `validateInboundReferences` already allows. Before this was aligned,
      // the failed write was a *named tombstone* failure, so the whole batch
      // rolled back — deterministically, on every later pass — and the
      // unrelated peer record below was lost with it.
      expect(
        result.applied,
        contains((
          kind: SyncRecordKind.choreographer,
          recordId: unrelated.id,
        )),
      );
      expect(await repositories.choreographers.getById(unrelated.id), isNotNull);
      expect(
        result.applied,
        contains((kind: SyncRecordKind.dance, recordId: deletedDance.id)),
      );
      expect(
        result.reports.where(
          (report) => report.message.contains('rolled back'),
        ),
        isEmpty,
      );
    },
  );

  test('applies an inbound update to a record held by a pending tombstone', () async {
    // A record kept live by §6.8's referential guard is moved out of
    // `snapshot().local` into `pendingLive`. The coordinator builds its
    // expected wire hashes from *both*, so a guard reading only `local` saw
    // `null` where a real hash was expected and refused the record as a
    // concurrent local change — structurally, on every pass, over a record the
    // user never touched.
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final later = DateTime.utc(2025, 1, 3, 12);
    final tag = Tag(id: 'cited-tag', name: 'Cited tag');
    // ignore: unused_result
    await repositories.tags.upsert(tag, at: stamp);
    await repositories.dances.create(
      Dance(
        id: 'citing-dance',
        title: 'Citing dance',
        tagIds: const ['cited-tag'],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );

    // A peer deletes the tag; the live citation defers it as pending.
    await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.tag,
            id: tag.id,
            updatedAt: stamp,
            deletedAt: stamp,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.tag, tag),
          ),
        ),
      ],
      storage: storage,
    );
    final pending = await repositories.syncLocal.listPendingDeletions();
    expect(pending.map((row) => row.recordId), contains(tag.id));

    // A peer now edits the same tag. Build the expected hashes exactly as the
    // coordinator does: local candidates plus the pending-live ones.
    final snapshot = await storage.snapshot();
    final expectedCandidates = {...snapshot.local, ...snapshot.pendingLive};
    final renamed = Tag(id: tag.id, name: 'Renamed by peer');
    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.tag,
            id: tag.id,
            updatedAt: later,
            deletedAt: null,
            existenceAt: later,
            body: syncBodyForEntity(SyncRecordKind.tag, renamed),
          ),
        ),
      ],
      storage: storage,
      expectedWireHashes: {
        for (final entry in expectedCandidates.entries)
          entry.key: entry.value?.wireHash,
      },
    );

    expect(
      result.reports.where(
        (report) => report.code == SyncReportCode.concurrentLocalChange,
      ),
      isEmpty,
    );
    expect(
      result.applied,
      contains((kind: SyncRecordKind.tag, recordId: tag.id)),
    );
  });

  test('rejected inbound tombstones do not suppress live citations', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final tag = Tag(id: 'retained-tag', name: 'Retained tag');
    // ignore: unused_result
    await repositories.tags.upsert(tag, at: stamp);
    await repositories.dances.create(
      Dance(
        id: 'live-dance',
        title: 'Live dance',
        tagIds: [tag.id],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );

    final tombstoneStamp = stamp.add(const Duration(minutes: 1));
    final invalidDance = Dance(
      id: 'live-dance',
      title: 'Live dance',
      authorIds: const ['missing-author'],
      tagIds: [tag.id],
      createdAt: stamp,
      updatedAt: tombstoneStamp,
    );
    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.tag,
            id: tag.id,
            updatedAt: tombstoneStamp,
            deletedAt: tombstoneStamp,
            existenceAt: tombstoneStamp,
            body: syncBodyForEntity(SyncRecordKind.tag, tag),
          ),
        ),
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.dance,
            id: invalidDance.id,
            updatedAt: tombstoneStamp,
            deletedAt: tombstoneStamp,
            existenceAt: tombstoneStamp,
            body: syncBodyForEntity(SyncRecordKind.dance, invalidDance),
          ),
        ),
      ],
      storage: storage,
    );

    expect(result.reports.single.code, SyncReportCode.unresolvedReference);
    expect(await repositories.dances.getById('live-dance'), isNotNull);
    expect(
      await repositories.syncLocal.getPendingDeletion(
        kind: SyncRecordKind.tag,
        recordId: tag.id,
      ),
      isNotNull,
    );
  });

  test(
    'refreshes a live ambiguity review after its candidate is edited',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final left = Dance(
        id: 'a-left',
        title: 'Shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'left'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final right = Dance(
        id: 'b-right',
        title: 'The shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'right'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(left);
      await repositories.dances.create(right);

      await storage.deduplicateFreshAttach();
      final firstRow = (await repositories.syncLocal.listReviewQueue()).single;
      await repositories.dances.create(
        Dance(
          id: 'c-left',
          title: 'Shared dance',
          figures: [testFigure(move: 'swing')],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.dances.create(
        Dance(
          id: 'd-right',
          title: 'The shared dance',
          figures: [
            testFigure(move: 'balance', params: const {'hand': 'left'}),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await storage.refreshDanceAmbiguityReviews();
      final targetedRows = await repositories.syncLocal.listReviewQueue();
      expect(targetedRows, hasLength(1));
      expect(targetedRows.single.recordId, 'a-left');
      expect(targetedRows.single.counterpartId, 'b-right');

      final editedRight = right.copyWith(
        figures: [testFigure(move: 'swing')],
        updatedAt: stamp.add(const Duration(minutes: 1)),
      );
      await repositories.dances.update(editedRight);

      await storage.refreshDanceAmbiguityReviews();
      final refreshedRow =
          (await repositories.syncLocal.listReviewQueue()).single;

      expect(refreshedRow.candidateHash, isNot(firstRow.candidateHash));
      expect(refreshedRow.candidateBlob, isNot(firstRow.candidateBlob));
      await storage.resolveReviewQueue(
        expectedRow: refreshedRow,
        action: SyncReviewAction.keepBoth,
        newNaturalKey: 'A distinct dance',
      );
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    },
  );

  // The sibling of the test above for the other side of the pair. Resolution
  // compares the live local record against the hash captured at enqueue, so a
  // row kept across an edit to the `recordId` side stays actionable while no
  // decision on it can ever succeed.
  test(
    'refreshes a live ambiguity review after its local record is edited',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final left = Dance(
        id: 'a-left',
        title: 'Shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'left'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final right = Dance(
        id: 'b-right',
        title: 'The shared dance',
        figures: [
          testFigure(move: 'balance', params: const {'hand': 'right'}),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(left);
      await repositories.dances.create(right);

      await storage.deduplicateFreshAttach();
      final firstRow = (await repositories.syncLocal.listReviewQueue()).single;
      expect(firstRow.recordId, 'a-left');
      expect(firstRow.localHash, isNotNull);

      // An edit that leaves the pair ambiguous and the candidate untouched:
      // only the local side moves.
      await repositories.dances.update(
        left.copyWith(
          walkthrough: 'A new walkthrough',
          updatedAt: stamp.add(const Duration(minutes: 1)),
        ),
      );

      await storage.refreshDanceAmbiguityReviews();
      final refreshedRow =
          (await repositories.syncLocal.listReviewQueue()).single;
      expect(refreshedRow.candidateHash, firstRow.candidateHash);
      expect(refreshedRow.localHash, isNot(firstRow.localHash));
      expect(SyncReviewQueueItem.fromRow(refreshedRow).isActionable, isTrue);

      await storage.resolveReviewQueue(
        expectedRow: refreshedRow,
        action: SyncReviewAction.keepBoth,
        newNaturalKey: 'A distinct dance',
      );
      expect(
        (await repositories.dances.getById('a-left'))!.title,
        'A distinct dance',
      );
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    },
  );

  test('adopts onto an aliased survivor that has no local row', () async {
    // Difficulty canonicalization picks a shipped ID without resolving it
    // through the alias table, so the adoption target can be an ID an earlier
    // collision already aliased away. When nothing occupies the end of that
    // chain the losing row has to move there; leaving it behind and rewriting
    // its references anyway points `dances.level_id` at a row that does not
    // exist and fails the foreign key, taking the whole inbound batch with it.
    final stamp = DateTime.utc(2025, 1, 2, 12);
    // The shipped row is gone and a user-defined ID holds its label, so
    // canonicalization falls through to the label match and names the shipped
    // ID as the survivor.
    await (db.delete(
      db.difficultyLevels,
    )..where((row) => row.id.equals(DifficultyLevel.beginnerId))).go();
    // ignore: unused_result
    await repositories.difficultyLevels.upsert(
      DifficultyLevel(id: 'custom-level', label: 'Beginner', position: 0),
      at: stamp,
    );
    await repositories.dances.create(
      Dance(
        id: 'levelled-dance',
        title: 'Levelled dance',
        difficultyLevelId: 'custom-level',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await repositories.syncLocal.upsertAlias(
      kind: SyncRecordKind.difficultyLevel,
      losingId: DifficultyLevel.beginnerId,
      survivingId: 'ghost-level',
    );
    expect(await repositories.difficultyLevels.getById('ghost-level'), isNull);

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.difficultyLevel,
            id: 'custom-level',
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp.add(const Duration(minutes: 1)),
            body: syncBodyForEntity(
              SyncRecordKind.difficultyLevel,
              DifficultyLevel(
                id: 'custom-level',
                label: 'Beginner',
                position: 0,
              ),
            ),
          ),
        ),
      ],
      storage: storage,
    );

    expect(
      result.reports.map((report) => '${report.code}: ${report.message}'),
      isEmpty,
    );
    // The local row moved to the end of the alias chain, and the dance still
    // resolves to it.
    expect(await repositories.difficultyLevels.getById('custom-level'), isNull);
    final survivor = await repositories.difficultyLevels.getById('ghost-level');
    expect(survivor, isNotNull);
    expect(survivor!.label, 'Beginner');
    expect(
      (await repositories.dances.getById('levelled-dance'))!.difficultyLevelId,
      'ghost-level',
    );
  });

  test(
    'reconciles same-label difficulty levels before applying dependents',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final remoteStamp = stamp.add(const Duration(minutes: 1));
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(id: 'existing-level', label: 'Same label', position: 0),
        at: stamp,
      );

      final inboundLevel = DifficultyLevel(
        id: 'inbound-level',
        label: 'Same label',
        position: 1,
      );
      final dance = Dance(
        id: 'dependent-dance',
        title: 'Dependent dance',
        difficultyLevelId: inboundLevel.id,
        createdAt: stamp,
        updatedAt: stamp,
      );
      final program = Program(
        id: 'dependent-program',
        title: 'Dependent program',
        slots: [
          ProgramSlot(id: 'dependent-slot', position: 0, danceId: dance.id),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      SyncMergeCandidate candidate({
        required SyncRecordKind kind,
        required String id,
        required Object entity,
      }) => SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: kind,
          id: id,
          updatedAt: remoteStamp,
          deletedAt: null,
          existenceAt: remoteStamp,
          body: syncBodyForEntity(kind, entity),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          candidate(
            kind: SyncRecordKind.difficultyLevel,
            id: inboundLevel.id,
            entity: inboundLevel,
          ),
          candidate(kind: SyncRecordKind.dance, id: dance.id, entity: dance),
          candidate(
            kind: SyncRecordKind.program,
            id: program.id,
            entity: program,
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        result.applied,
        containsAll([
          (kind: SyncRecordKind.difficultyLevel, recordId: 'existing-level'),
          (kind: SyncRecordKind.dance, recordId: dance.id),
          (kind: SyncRecordKind.program, recordId: program.id),
        ]),
      );
      expect(
        await repositories.difficultyLevels.getById(inboundLevel.id),
        isNull,
      );
      expect(
        (await repositories.dances.getById(dance.id))!.difficultyLevelId,
        'existing-level',
      );
      expect(await repositories.programs.getById(program.id), isNotNull);
    },
  );

  test(
    'rewrites same-label difficulty references in same-kind dependents',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final remoteStamp = stamp.add(const Duration(minutes: 1));
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(id: 'existing-level', label: 'Same label', position: 0),
        at: stamp,
      );

      final inboundLevel = DifficultyLevel(
        id: 'inbound-level',
        label: 'Same label',
        position: 1,
      );
      final blockedDance = Dance(
        id: 'blocked-dance',
        title: 'Blocked dance',
        difficultyLevelId: inboundLevel.id,
        createdAt: stamp,
        updatedAt: stamp,
      );
      final dependentDance = Dance(
        id: 'dependent-dance',
        title: 'Dependent dance',
        links: [
          DanceLink(
            id: 'dependent-link',
            kind: LinkKind.relatedDance,
            targetDanceId: blockedDance.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      SyncMergeCandidate candidate({
        required SyncRecordKind kind,
        required String id,
        required Object entity,
      }) => SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: kind,
          id: id,
          updatedAt: remoteStamp,
          deletedAt: null,
          existenceAt: remoteStamp,
          body: syncBodyForEntity(kind, entity),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          candidate(
            kind: SyncRecordKind.difficultyLevel,
            id: inboundLevel.id,
            entity: inboundLevel,
          ),
          candidate(
            kind: SyncRecordKind.dance,
            id: blockedDance.id,
            entity: blockedDance,
          ),
          candidate(
            kind: SyncRecordKind.dance,
            id: dependentDance.id,
            entity: dependentDance,
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        result.applied,
        containsAll([
          (kind: SyncRecordKind.difficultyLevel, recordId: 'existing-level'),
          (kind: SyncRecordKind.dance, recordId: blockedDance.id),
          (kind: SyncRecordKind.dance, recordId: dependentDance.id),
        ]),
      );
      expect(await repositories.dances.getById(blockedDance.id), isNotNull);
      expect(
        (await repositories.dances.getById(blockedDance.id))!.difficultyLevelId,
        'existing-level',
      );
      expect(await repositories.dances.getById(dependentDance.id), isNotNull);
    },
  );

  test('rewrites every inbound natural-key reference before commit', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final remoteStamp = stamp.add(const Duration(minutes: 1));
    final localChoreographer = Choreographer(
      id: 'z-author',
      name: 'Shared author',
    );
    final localTag = Tag(id: 'z-tag', name: 'Shared tag');
    final localField = CustomFieldDef(
      id: 'z-field',
      key: 'shared_field',
      label: 'Shared field',
      type: CustomFieldType.text,
    );
    final localDifficulty = DifficultyLevel(
      id: 'z-level',
      label: 'Shared level',
      position: 0,
    );
    // ignore: unused_result
    await repositories.choreographers.upsert(localChoreographer, at: stamp);
    // ignore: unused_result
    await repositories.tags.upsert(localTag, at: stamp);
    // ignore: unused_result
    await repositories.customFieldDefs.upsert(localField, at: stamp);
    await repositories.difficultyLevels.upsert(localDifficulty, at: stamp);

    final localDance = Dance(
      id: 'local-reference-dance',
      title: 'Local reference dance',
      authorIds: [localChoreographer.id],
      tagIds: [localTag.id],
      difficultyLevelId: localDifficulty.id,
      customFields: [
        CustomFieldValue(fieldId: localField.id, value: 'local value'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    await repositories.dances.create(localDance);

    final incomingChoreographer = Choreographer(
      id: 'a-author',
      name: localChoreographer.name,
    );
    final incomingTag = Tag(id: 'a-tag', name: localTag.name);
    final incomingField = CustomFieldDef(
      id: 'a-field',
      key: localField.key,
      label: localField.label,
      type: localField.type,
    );
    final incomingDifficulty = DifficultyLevel(
      id: 'a-level',
      label: localDifficulty.label,
      position: localDifficulty.position,
    );
    final inboundDance = Dance(
      id: 'inbound-reference-dance',
      title: 'Inbound reference dance',
      authorIds: [localChoreographer.id],
      tagIds: [localTag.id],
      difficultyLevelId: localDifficulty.id,
      customFields: [
        CustomFieldValue(fieldId: localField.id, value: 'remote value'),
      ],
      createdAt: remoteStamp,
      updatedAt: remoteStamp,
    );

    SyncMergeCandidate candidate({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
      Set<String> allowedCustomFieldIds = const {},
    }) => SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: remoteStamp,
        deletedAt: null,
        existenceAt: remoteStamp,
        body: syncBodyForEntity(
          kind,
          entity,
          allowedCustomFieldIds: allowedCustomFieldIds,
        ),
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        candidate(
          kind: SyncRecordKind.choreographer,
          id: incomingChoreographer.id,
          entity: incomingChoreographer,
        ),
        candidate(
          kind: SyncRecordKind.tag,
          id: incomingTag.id,
          entity: incomingTag,
        ),
        candidate(
          kind: SyncRecordKind.customFieldDef,
          id: incomingField.id,
          entity: incomingField,
        ),
        candidate(
          kind: SyncRecordKind.difficultyLevel,
          id: incomingDifficulty.id,
          entity: incomingDifficulty,
        ),
        candidate(
          kind: SyncRecordKind.dance,
          id: inboundDance.id,
          entity: inboundDance,
          allowedCustomFieldIds: {localField.id},
        ),
      ],
      storage: storage,
    );

    expect(result.reports, isEmpty);
    expect(
      result.applied,
      contains((kind: SyncRecordKind.dance, recordId: inboundDance.id)),
    );
    final stored = await repositories.dances.getById(inboundDance.id);
    expect(stored, isNotNull);
    expect(stored!.authorIds, ['a-author']);
    expect(stored.tagIds, ['a-tag']);
    expect(stored.difficultyLevelId, 'a-level');
    expect(stored.customFields.single.fieldId, 'a-field');
    expect(await repositories.choreographers.getById('z-author'), isNull);
    expect(await repositories.tags.getById('z-tag'), isNull);
    expect(await repositories.customFieldDefs.getById('z-field'), isNull);
    expect(await repositories.difficultyLevels.getById('z-level'), isNull);
  });

  test(
    'moves a local same-label custom difficulty onto the shipped ID',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final custom = DifficultyLevel(
        id: 'a-custom-beginner',
        label: DifficultyLevel.beginner.label,
        position: 0,
      );
      await (db.delete(
        db.difficultyLevels,
      )..where((row) => row.id.equals(DifficultyLevel.beginner.id))).go();
      await repositories.difficultyLevels.upsert(custom, at: stamp);
      final dance = Dance(
        id: 'custom-level-dance',
        title: 'Custom level dance',
        difficultyLevelId: custom.id,
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);

      final canonical = DifficultyLevel.beginner;
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: canonical.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(
                SyncRecordKind.difficultyLevel,
                canonical,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(await repositories.difficultyLevels.getById(custom.id), isNull);
      expect(
        await repositories.difficultyLevels.getById(canonical.id),
        isNotNull,
      );
      expect(
        (await repositories.dances.getById(dance.id))!.difficultyLevelId,
        canonical.id,
      );
    },
  );

  test(
    'canonical difficulty keeps newer local content over stale inbound live',
    () async {
      final localStamp = DateTime.utc(2025, 1, 2, 12);
      final inboundStamp = localStamp.subtract(const Duration(minutes: 1));
      final custom = DifficultyLevel(
        id: 'a-custom-beginner',
        label: DifficultyLevel.beginner.label,
        position: 7,
      );
      await (db.delete(
        db.difficultyLevels,
      )..where((row) => row.id.equals(DifficultyLevel.beginner.id))).go();
      await repositories.difficultyLevels.upsert(custom, at: localStamp);

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: DifficultyLevel.beginner.id,
              updatedAt: inboundStamp,
              deletedAt: null,
              existenceAt: inboundStamp,
              body: syncBodyForEntity(
                SyncRecordKind.difficultyLevel,
                DifficultyLevel.beginner,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(await repositories.difficultyLevels.getById(custom.id), isNull);
      final stored = await repositories.difficultyLevels.getById(
        DifficultyLevel.beginner.id,
      );
      expect(stored, isNotNull);
      expect(stored!.position, custom.position);
    },
  );

  test(
    'canonical difficulty aliases a noncanonical inbound ID before dependents',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final inboundDifficulty = DifficultyLevel(
        id: 'a-inbound-beginner',
        label: DifficultyLevel.beginner.label,
        position: DifficultyLevel.beginner.position,
      );
      final dance = Dance(
        id: 'canonical-dependent-dance',
        title: 'Canonical dependent dance',
        difficultyLevelId: inboundDifficulty.id,
        createdAt: stamp,
        updatedAt: stamp,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: inboundDifficulty.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(
                SyncRecordKind.difficultyLevel,
                inboundDifficulty,
              ),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.dance, dance),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        result.applied,
        contains((kind: SyncRecordKind.dance, recordId: dance.id)),
      );
      expect(
        (await repositories.dances.getById(dance.id))!.difficultyLevelId,
        DifficultyLevel.beginner.id,
      );
      final aliases = await repositories.syncLocal.listAliases();
      expect(
        aliases.any(
          (alias) =>
              alias.kind == SyncRecordKind.difficultyLevel &&
              alias.losingId == inboundDifficulty.id &&
              alias.survivingId == DifficultyLevel.beginner.id,
        ),
        isTrue,
      );
    },
  );

  test(
    'renamed shipped difficulty IDs remain canonical for same-label inbound IDs',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final renamed = DifficultyLevel(
        id: DifficultyLevel.beginnerId,
        label: 'Easy',
        position: DifficultyLevel.beginner.position,
      );
      await repositories.difficultyLevels.upsert(renamed, at: stamp);
      final inbound = DifficultyLevel(
        id: 'a-inbound-easy',
        label: renamed.label,
        position: 7,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.difficultyLevel, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(await repositories.difficultyLevels.getById(inbound.id), isNull);
      final stored = await repositories.difficultyLevels.getById(
        DifficultyLevel.beginnerId,
      );
      expect(stored, isNotNull);
      expect(stored!.label, renamed.label);
      expect(stored.position, inbound.position);
      expect(
        (await repositories.syncLocal.listAliases()).any(
          (alias) =>
              alias.kind == SyncRecordKind.difficultyLevel &&
              alias.losingId == inbound.id &&
              alias.survivingId == DifficultyLevel.beginnerId,
        ),
        isTrue,
      );
    },
  );

  test(
    'distinct shipped difficulty IDs with one natural key enter review',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      await repositories.difficultyLevels.hardDelete([
        DifficultyLevel.beginnerId,
      ]);
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(
          id: DifficultyLevel.advancedId,
          label: DifficultyLevel.advanced.label,
          position: DifficultyLevel.advanced.position,
        ),
        at: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: DifficultyLevel.beginnerId,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(
                SyncRecordKind.difficultyLevel,
                DifficultyLevel(
                  id: DifficultyLevel.beginnerId,
                  label: DifficultyLevel.advanced.label,
                  position: DifficultyLevel.beginner.position,
                ),
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(await repositories.syncLocal.listReviewQueue(), isNotEmpty);
      expect(
        await repositories.difficultyLevels.getById(DifficultyLevel.advancedId),
        isNotNull,
      );
    },
  );

  test(
    'canonical difficulty keeps newer local existence over stale inbound tombstone',
    () async {
      final localStamp = DateTime.utc(2025, 1, 2, 12);
      final inboundStamp = localStamp.subtract(const Duration(minutes: 1));
      final custom = DifficultyLevel(
        id: 'a-custom-beginner',
        label: DifficultyLevel.beginner.label,
        position: 7,
      );
      await (db.delete(
        db.difficultyLevels,
      )..where((row) => row.id.equals(DifficultyLevel.beginner.id))).go();
      await repositories.difficultyLevels.upsert(custom, at: localStamp);

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: DifficultyLevel.beginner.id,
              updatedAt: inboundStamp,
              deletedAt: inboundStamp,
              existenceAt: inboundStamp,
              body: syncBodyForEntity(
                SyncRecordKind.difficultyLevel,
                DifficultyLevel.beginner,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      // Step 2 does not resolve the survivor to non-existence here — the local
      // row's `existence_at` is newer than the inbound tombstone's — so §6.6's
      // baseline-absence guard does not apply and the collision reconciles
      // silently onto the canonical shipped ID, which is what step 2 and the
      // shipped-difficulty rule both require. The stale tombstone still loses
      // the existence comparison, so the level stays live carrying the local
      // row's content.
      //
      // This previously queued a review instead. That entry could never be
      // resolved by Merge: `resolveReviewQueue` refuses a candidate whose
      // `existence_at` is older than the local record's, so the only exit was
      // renaming a difficulty level the user never had a conflict over.
      expect(result.reports, isEmpty);
      final canonical = await repositories.difficultyLevels.getById(
        DifficultyLevel.beginner.id,
      );
      expect(canonical, isNotNull);
      expect(canonical!.position, custom.position);
      expect(await repositories.difficultyLevels.getById(custom.id), isNull);
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    },
  );

  test(
    'applies forward and cyclic dance references after parent rows',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      Dance dance({
        required String id,
        required String target,
        required String linkId,
      }) => Dance(
        id: id,
        title: id,
        links: [
          DanceLink(
            id: linkId,
            kind: LinkKind.relatedDance,
            targetDanceId: target,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final source = dance(
        id: 'a-source',
        target: 'z-target',
        linkId: 'forward-link',
      );
      final target = Dance(
        id: 'z-target',
        title: 'z-target',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final cycleA = dance(
        id: 'cycle-a',
        target: 'cycle-b',
        linkId: 'cycle-a-link',
      );
      final cycleB = dance(
        id: 'cycle-b',
        target: 'cycle-a',
        linkId: 'cycle-b-link',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          for (final dance in [source, target, cycleA, cycleB])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.dance,
                id: dance.id,
                updatedAt: stamp,
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.dance, dance),
              ),
            ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: 'a-source'),
        (kind: SyncRecordKind.dance, recordId: 'cycle-a'),
        (kind: SyncRecordKind.dance, recordId: 'cycle-b'),
        (kind: SyncRecordKind.dance, recordId: 'z-target'),
      ]);
      expect(result.reports, isEmpty);
      expect(
        (await repositories.dances.getById(
          'a-source',
        ))!.links.single.targetDanceId,
        'z-target',
      );
      expect(
        (await repositories.dances.getById(
          'cycle-a',
        ))!.links.single.targetDanceId,
        'cycle-b',
      );
      expect(
        (await repositories.dances.getById(
          'cycle-b',
        ))!.links.single.targetDanceId,
        'cycle-a',
      );
    },
  );

  test('does not resolve references to tombstoned inbound parents', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final tombstoneStamp = stamp.add(const Duration(minutes: 1));
    final tombstoneChoreographer = Choreographer(
      id: 'tomb-choreographer',
      name: 'Tombstoned choreographer',
    );
    final tombstoneTag = Tag(id: 'tomb-tag', name: 'Tombstoned tag');
    final tombstoneField = CustomFieldDef(
      id: 'tomb-field',
      key: 'tomb_field',
      label: 'Tombstoned field',
      type: CustomFieldType.text,
    );
    final tombstoneDance = Dance(
      id: 'tomb-dance',
      title: 'Tombstoned dance',
      createdAt: stamp,
      updatedAt: stamp,
    );
    final dances = [
      Dance(
        id: 'uses-choreographer',
        title: 'Uses choreographer',
        authorIds: [tombstoneChoreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-tag',
        title: 'Uses tag',
        tagIds: [tombstoneTag.id],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-field',
        title: 'Uses field',
        customFields: [
          CustomFieldValue(fieldId: tombstoneField.id, value: 'remote'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
      Dance(
        id: 'uses-dance',
        title: 'Uses dance',
        links: [
          DanceLink(
            id: 'uses-tombstone-link',
            kind: LinkKind.relatedDance,
            targetDanceId: tombstoneDance.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      ),
    ];

    SyncMergeCandidate entityCandidate({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
    }) => SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: stamp,
        deletedAt: tombstoneStamp,
        existenceAt: stamp,
        body: syncBodyForEntity(
          kind,
          entity,
          allowedCustomFieldIds: kind == SyncRecordKind.dance
              ? {tombstoneField.id}
              : const {},
        ),
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        entityCandidate(
          kind: SyncRecordKind.choreographer,
          id: tombstoneChoreographer.id,
          entity: tombstoneChoreographer,
        ),
        entityCandidate(
          kind: SyncRecordKind.tag,
          id: tombstoneTag.id,
          entity: tombstoneTag,
        ),
        entityCandidate(
          kind: SyncRecordKind.customFieldDef,
          id: tombstoneField.id,
          entity: tombstoneField,
        ),
        entityCandidate(
          kind: SyncRecordKind.dance,
          id: tombstoneDance.id,
          entity: tombstoneDance,
        ),
        for (final dance in dances)
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                dance,
                allowedCustomFieldIds: {tombstoneField.id},
              ),
            ),
          ),
      ],
      storage: storage,
    );

    expect(result.applied, [
      (kind: SyncRecordKind.choreographer, recordId: tombstoneChoreographer.id),
      (kind: SyncRecordKind.tag, recordId: tombstoneTag.id),
      (kind: SyncRecordKind.customFieldDef, recordId: tombstoneField.id),
      (kind: SyncRecordKind.dance, recordId: tombstoneDance.id),
    ]);
    expect(
      result.reports.where(
        (report) => report.code == SyncReportCode.unresolvedReference,
      ),
      hasLength(4),
    );
    for (final dance in dances) {
      expect(await repositories.dances.getById(dance.id), isNull);
    }
  });

  test('does not resolve relations to a locally tombstoned dance', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final tombstoneStamp = stamp.add(const Duration(minutes: 1));
    final tombstone = Dance(
      id: 'local-tombstone',
      title: 'Locally tombstoned',
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: tombstoneStamp,
    );
    await repositories.dances.create(tombstone);

    final linkedDance = Dance(
      id: 'linked-to-local-tombstone',
      title: 'Linked dance',
      links: [
        DanceLink(
          id: 'local-tombstone-link',
          kind: LinkKind.relatedDance,
          targetDanceId: tombstone.id,
        ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    final program = Program(
      id: 'program-with-local-tombstone',
      title: 'Program',
      slots: [
        ProgramSlot(
          id: 'local-tombstone-slot',
          position: 0,
          danceId: tombstone.id,
        ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );

    SyncMergeCandidate candidate({
      required SyncRecordKind kind,
      required String id,
      required Object entity,
    }) => SyncMergeCandidate(
      blob: SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: stamp,
        deletedAt: null,
        existenceAt: stamp,
        body: syncBodyForEntity(kind, entity),
      ),
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        candidate(
          kind: SyncRecordKind.dance,
          id: linkedDance.id,
          entity: linkedDance,
        ),
        candidate(
          kind: SyncRecordKind.program,
          id: program.id,
          entity: program,
        ),
      ],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(
      result.reports
          .where((report) => report.code == SyncReportCode.unresolvedReference)
          .length,
      2,
    );
    expect(await repositories.dances.getById(linkedDance.id), isNull);
    expect(await repositories.programs.getById(program.id), isNull);
    expect(
      await repositories.dances.getById(tombstone.id, includeDeleted: true),
      isNotNull,
    );
  });

  test(
    'does not retain a parent when an inbound tombstone invalidates its join',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final choreographer = Choreographer(
        id: 'existing-choreographer',
        name: 'Existing choreographer',
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(
        choreographer,
        at: stamp,
      ); // ignore: unused_result

      final dance = Dance(
        id: 'dance-with-tombstoned-author',
        title: 'Dance with tombstoned author',
        authorIds: [choreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final tombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: choreographer.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: tombstoneStamp,
          body: syncBodyForEntity(SyncRecordKind.choreographer, choreographer),
        ),
      );
      final inboundDance = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: dance.id,
          updatedAt: stamp,
          deletedAt: null,
          existenceAt: stamp,
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [inboundDance, tombstone],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: choreographer.id),
      ]);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(await repositories.dances.getById(dance.id), isNull);
      expect(
        await repositories.choreographers.getById(choreographer.id),
        isNull,
      );
    },
  );

  test(
    'applies tombstoned dances whose retained links target tombstones',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final target = Dance(
        id: 'z-tombstoned-target',
        title: 'Target',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final parent = Dance(
        id: 'a-tombstoned-parent',
        title: 'Parent',
        links: [
          DanceLink(
            id: 'retained-tombstone-link',
            kind: LinkKind.relatedDance,
            targetDanceId: target.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final program = Program(
        id: 'tombstoned-program',
        title: 'Program',
        slots: [
          ProgramSlot(
            id: 'retained-tombstone-slot',
            position: 0,
            danceId: target.id,
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(target);
      await repositories.dances.create(parent);
      await repositories.programs.create(program);

      SyncMergeCandidate tombstone(Dance dance) => SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: dance.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: tombstoneStamp,
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      );
      final programTombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.program,
          id: program.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: tombstoneStamp,
          body: syncBodyForEntity(SyncRecordKind.program, program),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [tombstone(parent), tombstone(target), programTombstone],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: parent.id),
        (kind: SyncRecordKind.dance, recordId: target.id),
        (kind: SyncRecordKind.program, recordId: program.id),
      ]);
      expect(result.reports, isEmpty);
      final storedParent = await repositories.dances.getById(
        parent.id,
        includeDeleted: true,
      );
      expect(storedParent!.deletedAt, tombstoneStamp);
      expect(storedParent.links.single.targetDanceId, target.id);
      expect(
        (await repositories.dances.getById(
          target.id,
          includeDeleted: true,
        ))!.deletedAt,
        tombstoneStamp,
      );
      expect(
        (await repositories.programs.getById(
          program.id,
          includeDeleted: true,
        ))!.deletedAt,
        tombstoneStamp,
      );
    },
  );

  test(
    'rejects duplicate and foreign dependent row ids before parent writes',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final duplicateLinks = Dance(
        id: 'duplicate-link-dance',
        title: 'Duplicate links',
        links: [
          DanceLink(id: 'same-link', kind: LinkKind.other, url: 'https://one'),
          DanceLink(id: 'same-link', kind: LinkKind.other, url: 'https://two'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final existingOwner = Dance(
        id: 'existing-link-owner',
        title: 'Existing owner',
        links: [
          DanceLink(
            id: 'owned-link',
            kind: LinkKind.other,
            url: 'https://owner',
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(existingOwner);
      final foreignOwner = Dance(
        id: 'foreign-link-dance',
        title: 'Foreign link',
        links: [
          DanceLink(
            id: 'owned-link',
            kind: LinkKind.other,
            url: 'https://peer',
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final duplicateSlots = Program(
        id: 'duplicate-slot-program',
        title: 'Duplicate slots',
        slots: [
          ProgramSlot(id: 'same-slot', position: 0, text: 'first'),
          ProgramSlot(id: 'same-slot', position: 1, text: 'second'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final duplicateAuthors = Dance(
        id: 'duplicate-author-dance',
        title: 'Duplicate authors',
        authorIds: const ['same-author', 'same-author'],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final duplicateTags = Dance(
        id: 'duplicate-tag-dance',
        title: 'Duplicate tags',
        tagIds: const ['same-tag', 'same-tag'],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final duplicateSources = Dance(
        id: 'duplicate-source-dance',
        title: 'Duplicate sources',
        sourceCitations: [
          SourceCitation(sourceId: 'same-source'),
          SourceCitation(sourceId: 'same-source'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final existingSlotOwner = Program(
        id: 'existing-slot-owner',
        title: 'Existing slot owner',
        slots: [ProgramSlot(id: 'owned-slot', position: 0, text: 'owner')],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.programs.create(existingSlotOwner);
      final foreignSlotOwner = Program(
        id: 'foreign-slot-program',
        title: 'Foreign slot',
        slots: [ProgramSlot(id: 'owned-slot', position: 0, text: 'peer')],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          for (final dance in [
            duplicateLinks,
            duplicateAuthors,
            duplicateTags,
            duplicateSources,
            foreignOwner,
          ])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.dance,
                id: dance.id,
                updatedAt: stamp.add(const Duration(minutes: 1)),
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.dance, dance),
              ),
            ),
          for (final program in [duplicateSlots, foreignSlotOwner])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.program,
                id: program.id,
                updatedAt: stamp.add(const Duration(minutes: 1)),
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.program, program),
              ),
            ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(
        result.reports.where(
          (report) => report.code == SyncReportCode.malformedRecord,
        ),
        hasLength(7),
      );
      expect(await repositories.dances.getById(duplicateLinks.id), isNull);
      expect(await repositories.dances.getById(duplicateAuthors.id), isNull);
      expect(await repositories.dances.getById(duplicateTags.id), isNull);
      expect(await repositories.dances.getById(duplicateSources.id), isNull);
      expect(await repositories.dances.getById(foreignOwner.id), isNull);
      expect(await repositories.programs.getById(duplicateSlots.id), isNull);
      expect(await repositories.programs.getById(foreignSlotOwner.id), isNull);
      expect(
        (await repositories.dances.getById(existingOwner.id))!.links.single.id,
        'owned-link',
      );
      expect(
        (await repositories.programs.getById(
          existingSlotOwner.id,
        ))!.slots.single.id,
        'owned-slot',
      );
    },
  );

  test(
    'batches high-cardinality inbound reference lookups and unions all rows',
    () async {
      final guardedDb = CompendiumDatabase(
        NativeDatabase.memory().interceptWith(_SqliteBindLimitGuard()),
      );
      addTearDown(guardedDb.close);
      final guardedRepositories = CompendiumRepositories(
        guardedDb,
        contraTaxonomy,
      );
      final guardedStorage = CompendiumSyncStorage(guardedRepositories);
      const total = 1001;
      final stamp = DateTime.utc(2025, 1, 2, 12);

      String id(String prefix, int index) =>
          '$prefix-${index.toString().padLeft(4, '0')}';

      final authorIds = [for (var i = 0; i < total; i++) id('author', i)];
      final tagIds = [for (var i = 0; i < total; i++) id('tag', i)];
      final sourceIds = [for (var i = 0; i < total; i++) id('source', i)];
      final customFieldIds = [for (var i = 0; i < total; i++) id('field', i)];
      final targetDanceIds = [for (var i = 0; i < total; i++) id('target', i)];

      await guardedDb.batch((batch) {
        batch.insertAll(guardedDb.choreographers, [
          for (var i = 0; i < total; i++)
            ChoreographersCompanion.insert(
              id: authorIds[i],
              name: 'Author $i',
              updatedAt: Value(stamp),
              existenceAt: Value(stamp),
            ),
        ]);
        batch.insertAll(guardedDb.tags, [
          for (var i = 0; i < total; i++)
            TagsCompanion.insert(
              id: tagIds[i],
              name: 'Tag $i',
              updatedAt: Value(stamp),
              existenceAt: Value(stamp),
            ),
        ]);
        batch.insertAll(guardedDb.publishedSources, [
          for (var i = 0; i < total; i++)
            PublishedSourcesCompanion.insert(
              id: sourceIds[i],
              title: 'Source $i',
              updatedAt: Value(stamp),
              existenceAt: Value(stamp),
            ),
        ]);
        batch.insertAll(guardedDb.customFieldDefs, [
          for (var i = 0; i < total; i++)
            CustomFieldDefsCompanion.insert(
              id: customFieldIds[i],
              key: 'field_$i',
              label: 'Field $i',
              type: CustomFieldType.text,
              updatedAt: Value(stamp),
              existenceAt: Value(stamp),
            ),
        ]);
        batch.insertAll(guardedDb.dances, [
          for (var i = 0; i < total; i++)
            DancesCompanion.insert(
              id: targetDanceIds[i],
              title: 'Target dance $i',
              form: DanceForm.contra,
              formationShape: FormationShape.dupleImproper,
              progression: Progression.single,
              status: DanceStatus.active,
              createdAt: stamp,
              updatedAt: stamp,
              existenceAt: Value(stamp),
            ),
        ]);
      });

      final inboundDance = Dance(
        id: 'high-cardinality-dance',
        title: 'High-cardinality dance',
        authorIds: authorIds,
        tagIds: tagIds,
        sourceCitations: [
          for (final sourceId in sourceIds) SourceCitation(sourceId: sourceId),
        ],
        customFields: [
          for (final fieldId in customFieldIds)
            CustomFieldValue(fieldId: fieldId, value: 'value'),
        ],
        links: [
          for (var i = 0; i < total; i++)
            DanceLink(
              id: id('link', i),
              kind: LinkKind.relatedDance,
              targetDanceId: targetDanceIds[i],
            ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final inboundProgram = Program(
        id: 'high-cardinality-program',
        title: 'High-cardinality program',
        slots: [
          for (var i = 0; i < total; i++)
            ProgramSlot(
              id: id('slot', i),
              position: i,
              danceId: targetDanceIds[i],
            ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final candidates = [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.dance,
            id: inboundDance.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.dance, inboundDance),
          ),
        ),
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.program,
            id: inboundProgram.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.program, inboundProgram),
          ),
        ),
      ];

      final result = await const SyncApplyEngine().apply(
        candidates: candidates,
        storage: guardedStorage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: inboundDance.id),
        (kind: SyncRecordKind.program, recordId: inboundProgram.id),
      ]);
      expect(result.reports, isEmpty);
      expect(
        (await guardedRepositories.dances.getById(inboundDance.id))!.authorIds,
        authorIds,
      );
      expect(
        (await guardedRepositories.dances.getById(inboundDance.id))!.links,
        inboundDance.links,
      );
      expect(
        (await guardedRepositories.programs.getById(inboundProgram.id))!.slots,
        inboundProgram.slots,
      );
    },
  );

  test('detects a dance-link owner in the second bind-limit chunk', () async {
    final guardedDb = CompendiumDatabase(
      NativeDatabase.memory().interceptWith(_SqliteBindLimitGuard()),
    );
    addTearDown(guardedDb.close);
    final guardedRepositories = CompendiumRepositories(
      guardedDb,
      contraTaxonomy,
    );
    final guardedStorage = CompendiumSyncStorage(guardedRepositories);
    const total = 1001;
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final conflictIndex = 500;
    final conflictLinkId =
        'inbound-link-${conflictIndex.toString().padLeft(4, '0')}';
    final foreignOwner = Dance(
      id: 'stored-link-owner',
      title: 'Stored link owner',
      links: [
        DanceLink(
          id: conflictLinkId,
          kind: LinkKind.other,
          url: 'https://stored.example/link',
        ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    await guardedRepositories.dances.create(foreignOwner);

    final inboundDance = Dance(
      id: 'inbound-link-conflict',
      title: 'Inbound link conflict',
      links: [
        for (var i = 0; i < total; i++)
          DanceLink(
            id: 'inbound-link-${i.toString().padLeft(4, '0')}',
            kind: LinkKind.other,
            url: 'https://inbound.example/$i',
          ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.dance,
            id: inboundDance.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.dance, inboundDance),
          ),
        ),
      ],
      storage: guardedStorage,
    );

    expect(result.applied, isEmpty);
    expect(result.reports, hasLength(1));
    expect(result.reports.single.code, SyncReportCode.malformedRecord);
    expect(
      result.reports.single.message,
      'Dance link id "$conflictLinkId" is already owned by '
      '"${foreignOwner.id}".',
    );
    expect(await guardedRepositories.dances.getById(inboundDance.id), isNull);
  });

  test('detects a program-slot owner in the second bind-limit chunk', () async {
    final guardedDb = CompendiumDatabase(
      NativeDatabase.memory().interceptWith(_SqliteBindLimitGuard()),
    );
    addTearDown(guardedDb.close);
    final guardedRepositories = CompendiumRepositories(
      guardedDb,
      contraTaxonomy,
    );
    final guardedStorage = CompendiumSyncStorage(guardedRepositories);
    const total = 1001;
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final conflictIndex = 500;
    final conflictSlotId =
        'inbound-slot-${conflictIndex.toString().padLeft(4, '0')}';
    final foreignOwner = Program(
      id: 'stored-slot-owner',
      title: 'Stored slot owner',
      slots: [
        ProgramSlot(id: conflictSlotId, position: 0, text: 'Stored slot'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    await guardedRepositories.programs.create(foreignOwner);

    final inboundProgram = Program(
      id: 'inbound-slot-conflict',
      title: 'Inbound slot conflict',
      slots: [
        for (var i = 0; i < total; i++)
          ProgramSlot(
            id: 'inbound-slot-${i.toString().padLeft(4, '0')}',
            position: i,
            text: 'Inbound slot $i',
          ),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.program,
            id: inboundProgram.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.program, inboundProgram),
          ),
        ),
      ],
      storage: guardedStorage,
    );

    expect(result.applied, isEmpty);
    expect(result.reports, hasLength(1));
    expect(result.reports.single.code, SyncReportCode.malformedRecord);
    expect(
      result.reports.single.message,
      'Program slot id "$conflictSlotId" is already owned by '
      '"${foreignOwner.id}".',
    );
    expect(
      await guardedRepositories.programs.getById(inboundProgram.id),
      isNull,
    );
  });

  test(
    'isolates dependent-id collisions to the conflicting inbound owners',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);

      SyncMergeCandidate danceCandidate(Dance dance) => SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: dance.id,
          updatedAt: stamp.add(const Duration(minutes: 1)),
          deletedAt: null,
          existenceAt: stamp,
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      );

      SyncMergeCandidate programCandidate(Program program) =>
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.program,
              id: program.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.program, program),
            ),
          );

      final conflictingDanceA = Dance(
        id: 'conflicting-dance-a',
        title: 'Conflicting dance A',
        links: [
          DanceLink(id: 'shared-link', kind: LinkKind.other, url: 'https://a'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final conflictingDanceB = Dance(
        id: 'conflicting-dance-b',
        title: 'Conflicting dance B',
        links: [
          DanceLink(id: 'shared-link', kind: LinkKind.other, url: 'https://b'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final validDance = Dance(
        id: 'unrelated-dance',
        title: 'Unrelated dance',
        links: [
          DanceLink(
            id: 'unrelated-link',
            kind: LinkKind.other,
            url: 'https://unrelated',
          ),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final conflictingProgramA = Program(
        id: 'conflicting-program-a',
        title: 'Conflicting program A',
        slots: [ProgramSlot(id: 'shared-slot', position: 0, text: 'A')],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final conflictingProgramB = Program(
        id: 'conflicting-program-b',
        title: 'Conflicting program B',
        slots: [ProgramSlot(id: 'shared-slot', position: 0, text: 'B')],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final validProgram = Program(
        id: 'unrelated-program',
        title: 'Unrelated program',
        slots: [
          ProgramSlot(id: 'unrelated-slot', position: 0, text: 'unrelated'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          danceCandidate(conflictingDanceA),
          danceCandidate(conflictingDanceB),
          danceCandidate(validDance),
          programCandidate(conflictingProgramA),
          programCandidate(conflictingProgramB),
          programCandidate(validProgram),
        ],
        storage: storage,
      );

      expect(
        result.applied,
        containsAll([
          (kind: SyncRecordKind.dance, recordId: validDance.id),
          (kind: SyncRecordKind.program, recordId: validProgram.id),
        ]),
      );
      expect(
        result.reports.where(
          (report) => report.code == SyncReportCode.malformedRecord,
        ),
        hasLength(4),
      );
      expect(await repositories.dances.getById(validDance.id), isNotNull);
      expect(await repositories.programs.getById(validProgram.id), isNotNull);
      expect(await repositories.dances.getById(conflictingDanceA.id), isNull);
      expect(await repositories.dances.getById(conflictingDanceB.id), isNull);
      expect(
        await repositories.programs.getById(conflictingProgramA.id),
        isNull,
      );
      expect(
        await repositories.programs.getById(conflictingProgramB.id),
        isNull,
      );
    },
  );

  test(
    'isolates wrong-typed inbound entity fields from valid records',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final malformed = Dance(
        id: 'wrong-typed-dance',
        title: 'Wrong typed',
        figures: [Figure(move: 'swing', note: 'valid note')],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final malformedBody = Map<String, Object?>.from(
        syncBodyForEntity(SyncRecordKind.dance, malformed),
      );
      final malformedFigures = (malformedBody['figures'] as List).map((raw) {
        final figure = Map<String, Object?>.from(raw as Map);
        figure['note'] = 42;
        return figure;
      }).toList();
      malformedBody['figures'] = malformedFigures;
      final valid = Choreographer(
        id: 'valid-after-malformed',
        name: 'Still applied',
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: malformed.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: malformedBody,
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: valid.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.choreographer, valid),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: valid.id),
      ]);
      expect(result.reports.single.code, SyncReportCode.malformedRecord);
      expect(await repositories.dances.getById(malformed.id), isNull);
      expect(await repositories.choreographers.getById(valid.id), isNotNull);

      final directReport = await storage.writeWithReport(
        SyncApplyRecord(
          address: (kind: SyncRecordKind.dance, recordId: malformed.id),
          body: malformedBody,
          updatedAt: stamp,
          deletedAt: null,
          existenceAt: stamp,
        ),
      );
      expect(directReport?.code, SyncReportCode.malformedRecord);
    },
  );

  test(
    'inbound dance writes preserve device-local custom-field values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'local-field',
          key: 'local_field',
          label: 'Local field',
          type: CustomFieldType.text,
          shareable: false,
        ),
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'shared-field',
          key: 'shared_field',
          label: 'Shared field',
          type: CustomFieldType.text,
        ),
      );
      final local = Dance(
        id: 'dance-fields',
        title: 'Local dance',
        customFields: [
          CustomFieldValue(fieldId: 'local-field', value: 'keep me'),
          CustomFieldValue(fieldId: 'shared-field', value: 'old'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(local);

      final remote = local.copyWith(
        title: 'Remote dance',
        customFields: [CustomFieldValue(fieldId: 'shared-field', value: 'new')],
        updatedAt: stamp.add(const Duration(hours: 1)),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: remote.id,
              updatedAt: remote.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                remote,
                allowedCustomFieldIds: {'shared-field'},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: remote.id),
      ]);
      final stored = await repositories.dances.getById(remote.id);
      expect(
        stored!.customFields,
        containsAll([
          CustomFieldValue(fieldId: 'local-field', value: 'keep me'),
          CustomFieldValue(fieldId: 'shared-field', value: 'new'),
        ]),
      );
    },
  );

  test(
    'inbound performed programs preserve peer slot content without stamping it',
    () async {
      final originalStamp = DateTime.utc(2025, 1, 1, 12);
      final remoteStamp = DateTime.utc(2025, 1, 2, 12);
      final original = Program(
        id: 'p1',
        title: 'Program',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: originalStamp,
        updatedAt: originalStamp,
      );
      await repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Dance',
          createdAt: originalStamp,
          updatedAt: originalStamp,
        ),
      );
      await repositories.programs.create(original);

      final remote = original.copyWith(
        status: ProgramStatus.performed,
        updatedAt: remoteStamp,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.program,
              id: remote.id,
              updatedAt: remoteStamp,
              deletedAt: null,
              existenceAt: originalStamp,
              body: syncBodyForEntity(SyncRecordKind.program, remote),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, [(kind: SyncRecordKind.program, recordId: 'p1')]);
      final stored = await repositories.programs.getById('p1');
      expect(stored!.status, ProgramStatus.performed);
      expect(stored.slots.single.performedAt, isNull);
      expect(stored.updatedAt, remoteStamp);
    },
  );

  test(
    'does not retain a parent when a stored custom-field definition is corrupt',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final preservedDef = CustomFieldDef(
        id: 'preserved-field',
        key: 'preserved_field',
        label: 'Preserved field',
        type: CustomFieldType.text,
      );
      final corruptDef = CustomFieldDef(
        id: 'corrupt-field',
        key: 'corrupt_field',
        label: 'Corrupt field',
        type: CustomFieldType.choice,
        choices: ['valid'],
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(preservedDef, at: stamp);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(corruptDef, at: stamp);
      await (db.update(
        db.customFieldDefs,
      )..where((row) => row.id.equals(corruptDef.id))).write(
        const CustomFieldDefsCompanion(choicesJson: Value('{not valid json')),
      );

      final original = Dance(
        id: 'dance-with-corrupt-field',
        title: 'Original title',
        customFields: [
          CustomFieldValue(fieldId: preservedDef.id, value: 'preserve me'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(original);

      final inbound = original.copyWith(
        title: 'Inbound title',
        customFields: [
          CustomFieldValue(fieldId: corruptDef.id, value: 'invalid definition'),
        ],
        updatedAt: stamp.add(const Duration(minutes: 1)),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: inbound.id,
              updatedAt: inbound.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                inbound,
                allowedCustomFieldIds: {corruptDef.id},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      final stored = await repositories.dances.getById(original.id);
      expect(stored!.title, original.title);
      expect(stored.customFields, original.customFields);
    },
  );

  test(
    'rejects non-shareable custom-field definitions and inbound values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final localDefinition = CustomFieldDef(
        id: 'local-private-field',
        key: 'local_private_field',
        label: 'Local private field',
        type: CustomFieldType.text,
        shareable: false,
      );
      final inboundDefinition = CustomFieldDef(
        id: 'inbound-private-field',
        key: 'inbound_private_field',
        label: 'Inbound private field',
        type: CustomFieldType.text,
        shareable: false,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(localDefinition, at: stamp);
      final inboundDance = Dance(
        id: 'dance-with-private-field',
        title: 'Inbound dance',
        customFields: [
          CustomFieldValue(fieldId: localDefinition.id, value: 'private'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final sameBatchDance = Dance(
        id: 'dance-with-inbound-private-field',
        title: 'Same-batch dance',
        customFields: [
          CustomFieldValue(fieldId: inboundDefinition.id, value: 'private'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: inboundDefinition.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: archiveCustomFieldDefToJson(
                inboundDefinition,
                includeShareable: true,
                includeOptionalFields: true,
              ),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: inboundDance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                inboundDance,
                allowedCustomFieldIds: {localDefinition.id},
              ),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: sameBatchDance.id,
              updatedAt: stamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                sameBatchDance,
                allowedCustomFieldIds: {inboundDefinition.id},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(
        result.reports
            .where(
              (report) => report.code == SyncReportCode.invalidClassification,
            )
            .map((report) => report.recordId),
        containsAll([inboundDefinition.id, inboundDance.id, sameBatchDance.id]),
      );
      expect(
        await repositories.customFieldDefs.getById(inboundDefinition.id),
        isNull,
      );
      expect(await repositories.dances.getById(inboundDance.id), isNull);
      expect(await repositories.dances.getById(sameBatchDance.id), isNull);
    },
  );

  test(
    'rejects tombstoned non-shareable custom-field definitions and values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final localDefinition = CustomFieldDef(
        id: 'local-tombstoned-private-field',
        key: 'local_tombstoned_private_field',
        label: 'Local tombstoned private field',
        type: CustomFieldType.text,
        shareable: false,
      );
      final inboundDefinition = CustomFieldDef(
        id: 'inbound-tombstoned-private-field',
        key: 'inbound_tombstoned_private_field',
        label: 'Inbound tombstoned private field',
        type: CustomFieldType.text,
        shareable: false,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(localDefinition, at: stamp);
      await (db.update(
        db.customFieldDefs,
      )..where((row) => row.id.equals(localDefinition.id))).write(
        CustomFieldDefsCompanion(
          deletedAt: Value(tombstoneStamp),
          existenceAt: Value(tombstoneStamp),
        ),
      );
      final localTombstonedDance = Dance(
        id: 'dance-with-local-tombstoned-private-field',
        title: 'Local tombstoned dance',
        customFields: [
          CustomFieldValue(fieldId: localDefinition.id, value: 'private'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      final inboundTombstonedDance = Dance(
        id: 'dance-with-inbound-tombstoned-private-field',
        title: 'Inbound tombstoned dance',
        customFields: [
          CustomFieldValue(fieldId: inboundDefinition.id, value: 'private'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: inboundDefinition.id,
              updatedAt: tombstoneStamp,
              deletedAt: tombstoneStamp,
              existenceAt: stamp,
              body: archiveCustomFieldDefToJson(
                inboundDefinition,
                includeShareable: true,
                includeOptionalFields: true,
              ),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: localTombstonedDance.id,
              updatedAt: tombstoneStamp,
              deletedAt: tombstoneStamp,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                localTombstonedDance,
                allowedCustomFieldIds: {localDefinition.id},
              ),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: inboundTombstonedDance.id,
              updatedAt: tombstoneStamp,
              deletedAt: tombstoneStamp,
              existenceAt: stamp,
              body: syncBodyForEntity(
                SyncRecordKind.dance,
                inboundTombstonedDance,
                allowedCustomFieldIds: {inboundDefinition.id},
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(
        result.reports
            .where(
              (report) => report.code == SyncReportCode.invalidClassification,
            )
            .map((report) => report.recordId),
        containsAll([
          inboundDefinition.id,
          localTombstonedDance.id,
          inboundTombstonedDance.id,
        ]),
      );
      expect(
        await repositories.customFieldDefs.getById(inboundDefinition.id),
        isNull,
      );
      expect(
        await repositories.dances.getById(localTombstonedDance.id),
        isNull,
      );
      expect(
        await repositories.dances.getById(inboundTombstonedDance.id),
        isNull,
      );
      final localRow = await (db.select(
        db.customFieldDefs,
      )..where((row) => row.id.equals(localDefinition.id))).getSingle();
      expect(localRow.shareable, isFalse);
      expect(localRow.deletedAt?.toUtc(), tombstoneStamp);
    },
  );

  test(
    'defers derived maintenance during sync relation writes to the batch rebuild',
    () async {
      final counter = FtsDeleteByDanceCounter();
      await db.close();
      final countingDb = openCountingTestDatabase(counter);
      db = countingDb;
      final countingRepositories = CompendiumRepositories(
        countingDb,
        contraTaxonomy,
      );
      final countingStorage = CompendiumSyncStorage(countingRepositories);
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final dance = Dance(
        id: 'sync-derived-batch',
        title: 'Sync dance',
        createdAt: stamp,
        updatedAt: stamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: dance.updatedAt,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, dance),
            ),
          ),
        ],
        storage: countingStorage,
      );

      expect(result.applied, [
        (kind: SyncRecordKind.dance, recordId: dance.id),
      ]);
      expect(
        counter.count,
        0,
        reason:
            'sync relation writes must defer per-dance derived maintenance '
            'until the final bulk rebuild',
      );
    },
  );

  test(
    'holds a cited tombstone out of the live view until its citation is gone',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final choreographer = Choreographer(
        id: 'cited-choreographer',
        name: 'Cited choreographer',
        email: 'local@example.com',
        location: 'Local hall',
        deceased: true,
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(choreographer, at: stamp);
      final dance = Dance(
        id: 'citing-dance',
        title: 'Citing dance',
        authorIds: [choreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);

      final tombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: choreographer.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: tombstoneStamp,
          body: syncBodyForEntity(SyncRecordKind.choreographer, choreographer),
        ),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [tombstone],
        storage: storage,
      );

      expect(result.applied, [tombstone.address]);
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: choreographer.id,
        ),
        isNotNull,
      );
      final pendingSnapshot = await storage.snapshot();
      expect(pendingSnapshot.local, isNot(contains(tombstone.address)));
      expect(
        pendingSnapshot.publication[tombstone.address]!.blob.deletedAt,
        tombstoneStamp,
      );
      expect(
        await repositories.choreographers.getById(choreographer.id),
        isNotNull,
      );

      // A body edit is not an existence transition and must not cancel the
      // pending tombstone while the dance still cites the row.
      // ignore: unused_result
      await repositories.choreographers.upsert(
        choreographer.copyWith(notes: 'edited locally'),
        at: tombstoneStamp.add(const Duration(minutes: 1)),
      );
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: choreographer.id,
        ),
        isNotNull,
      );

      await repositories.dances.update(dance.copyWith(authorIds: const []));
      final finalSnapshot = await storage.snapshot();
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: choreographer.id,
        ),
        isNull,
      );
      expect(
        finalSnapshot.local[tombstone.address]!.blob.deletedAt,
        tombstoneStamp,
      );
      expect(
        await repositories.choreographers.getById(choreographer.id),
        isNull,
      );
      final retainedTombstone = await (db.select(
        db.choreographers,
      )..where((table) => table.id.equals(choreographer.id))).getSingle();
      expect(retainedTombstone.email, choreographer.email);
      expect(retainedTombstone.location, choreographer.location);
      expect(retainedTombstone.deceased, choreographer.deceased);
    },
  );

  test(
    'soft-deleted citation owners do not keep a pending tombstone alive',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final choreographer = Choreographer(
        id: 'soft-deleted-owner-choreographer',
        name: 'Soft deleted owner choreographer',
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(choreographer, at: stamp);
      final dance = Dance(
        id: 'soft-deleted-owner-dance',
        title: 'Soft deleted owner dance',
        authorIds: [choreographer.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);
      await repositories.dances.softDelete(
        dance.id,
        at: stamp.add(const Duration(minutes: 1)),
      );

      final tombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: choreographer.id,
          updatedAt: stamp.add(const Duration(minutes: 2)),
          deletedAt: stamp.add(const Duration(minutes: 2)),
          existenceAt: stamp.add(const Duration(minutes: 2)),
          body: syncBodyForEntity(SyncRecordKind.choreographer, choreographer),
        ),
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [tombstone],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: choreographer.id,
        ),
        isNull,
      );
      expect(
        await repositories.choreographers.getById(choreographer.id),
        isNull,
      );
    },
  );

  test(
    'an explicit restore clears pending state while archive restore can retain it',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final dance = Dance(
        id: 'pending-dance',
        title: 'Pending dance',
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);
      await repositories.programs.create(
        Program(
          id: 'citing-program',
          title: 'Citing program',
          slots: [
            ProgramSlot(id: 'citing-slot', position: 0, danceId: dance.id),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final tombstone = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: dance.id,
          updatedAt: stamp.add(const Duration(minutes: 1)),
          deletedAt: stamp.add(const Duration(minutes: 1)),
          existenceAt: stamp.add(const Duration(minutes: 1)),
          body: syncBodyForEntity(SyncRecordKind.dance, dance),
        ),
      );
      await const SyncApplyEngine().apply(
        candidates: [tombstone],
        storage: storage,
      );
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.dance,
          recordId: dance.id,
        ),
        isNotNull,
      );

      await repositories.dances.restore(
        dance.id,
        at: stamp.add(const Duration(minutes: 2)),
      );
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.dance,
          recordId: dance.id,
        ),
        isNull,
      );

      // Recreate the pending state and exercise the archive-only path. The
      // archive restorer must leave the pending state for citation revalidation.
      await repositories.syncLocal.upsertPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: dance.id,
        tombstonedAt: tombstone.blob.deletedAt!,
        tombstoneHash: tombstone.wireHash,
        tombstoneBlob: encodeSyncRecordBlob(tombstone.blob),
      );
      await repositories.dances.restore(
        dance.id,
        at: stamp.add(const Duration(minutes: 3)),
        clearPending: false,
      );
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.dance,
          recordId: dance.id,
        ),
        isNotNull,
      );
    },
  );

  test(
    'natural-key reconciliation rewrites local references and advances their content stamp',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = Choreographer(id: 'z-author', name: 'Same author');
      // ignore: unused_result
      await repositories.choreographers.upsert(
        local,
        at: stamp,
      ); // ignore: unused_result
      final dance = Dance(
        id: 'referencing-dance',
        title: 'Referencing dance',
        authorIds: [local.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);
      final beforeSnapshot = await storage.snapshot();
      final before = await (db.select(
        db.dances,
      )..where((row) => row.id.equals(dance.id))).getSingle();

      final inbound = Choreographer(id: 'a-author', name: 'Same author');
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(await repositories.choreographers.getById(local.id), isNull);
      expect((await repositories.dances.getById(dance.id))!.authorIds, [
        inbound.id,
      ]);
      final after = await (db.select(
        db.dances,
      )..where((row) => row.id.equals(dance.id))).getSingle();
      expect(after.updatedAt, isNot(before.updatedAt));
      final snapshot = await storage.snapshot();
      expect(
        snapshot
            .local[(kind: SyncRecordKind.dance, recordId: dance.id)]!
            .wireHash,
        isNot(
          beforeSnapshot
              .local[(kind: SyncRecordKind.dance, recordId: dance.id)]!
              .wireHash,
        ),
      );
    },
  );

  test('natural-key reconciliation rejects a changed local survivor', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final local = Choreographer(
      id: 'z-concurrent-local-author',
      name: 'Concurrent author',
      notes: 'before',
    );
    // ignore: unused_result
    await repositories.choreographers.upsert(local, at: stamp);
    final before = (await storage.snapshot())
        .local[(kind: SyncRecordKind.choreographer, recordId: local.id)]!;

    // The coordinator's merge snapshot is now stale, but the inbound
    // address is new, so the ordinary candidate-address guard cannot catch
    // this mutation.
    // ignore: unused_result
    await repositories.choreographers.upsert(
      local.copyWith(notes: 'changed locally'),
      at: stamp.add(const Duration(minutes: 1)),
    );
    final incoming = Choreographer(
      id: 'a-concurrent-remote-author',
      name: local.name,
      notes: 'remote',
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.choreographer,
            id: incoming.id,
            updatedAt: stamp.add(const Duration(minutes: 2)),
            deletedAt: null,
            existenceAt: stamp.add(const Duration(minutes: 2)),
            body: syncBodyForEntity(SyncRecordKind.choreographer, incoming),
          ),
        ),
      ],
      storage: storage,
      expectedWireHashes: {before.address: before.wireHash},
    );

    expect(result.reports.single.code, SyncReportCode.concurrentLocalChange);
    expect(result.applied, isEmpty);
    expect(
      (await repositories.choreographers.getById(local.id))!.notes,
      'changed locally',
    );
    expect(await repositories.choreographers.getById(incoming.id), isNull);
  });

  test(
    'aliased natural-key reconciliation rejects a changed local survivor',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = Choreographer(
        id: 'a-aliased-local-author',
        name: 'Aliased concurrent author',
        notes: 'before',
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(local, at: stamp);
      final before = (await storage.snapshot())
          .local[(kind: SyncRecordKind.choreographer, recordId: local.id)]!;
      final incoming = Choreographer(
        id: 'z-aliased-remote-author',
        name: local.name,
        notes: 'remote',
      );
      await repositories.syncLocal.upsertAlias(
        kind: SyncRecordKind.choreographer,
        losingId: incoming.id,
        survivingId: local.id,
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(
        local.copyWith(notes: 'changed locally'),
        at: stamp.add(const Duration(minutes: 1)),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: incoming.id,
              updatedAt: stamp.add(const Duration(minutes: 2)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 2)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, incoming),
            ),
          ),
        ],
        storage: storage,
        expectedWireHashes: {before.address: before.wireHash},
      );

      expect(result.reports.single.code, SyncReportCode.concurrentLocalChange);
      expect(result.applied, isEmpty);
      expect(
        (await repositories.choreographers.getById(local.id))!.notes,
        'changed locally',
      );
      expect(await repositories.choreographers.getById(incoming.id), isNull);
    },
  );

  test(
    'natural-key reconciliation rewrites tag and custom-field references',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 'z-tag', name: 'Shared tag'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'z-field',
          key: 'shared_field',
          label: 'Shared field',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      final dance = Dance(
        id: 'tag-field-dance',
        title: 'Tag and field dance',
        tagIds: const ['z-tag'],
        customFields: [
          CustomFieldValue(fieldId: 'z-field', value: 'local value'),
        ],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);
      final before = await (db.select(
        db.dances,
      )..where((row) => row.id.equals(dance.id))).getSingle();

      final candidateTag = Tag(id: 'a-tag', name: 'Shared tag');
      final candidateField = CustomFieldDef(
        id: 'a-field',
        key: 'shared_field',
        label: 'Shared field',
        type: CustomFieldType.text,
      );
      final remoteStamp = stamp.add(const Duration(minutes: 1));
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.tag,
              id: candidateTag.id,
              updatedAt: remoteStamp,
              deletedAt: null,
              existenceAt: remoteStamp,
              body: syncBodyForEntity(SyncRecordKind.tag, candidateTag),
            ),
          ),
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: candidateField.id,
              updatedAt: remoteStamp,
              deletedAt: null,
              existenceAt: remoteStamp,
              body: syncBodyForEntity(
                SyncRecordKind.customFieldDef,
                candidateField,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final rewritten = await (db.select(
        db.dances,
      )..where((row) => row.id.equals(dance.id))).getSingle();
      expect((await repositories.dances.getById(dance.id))!.tagIds, ['a-tag']);
      expect(
        (await repositories.dances.getById(
          dance.id,
        ))!.customFields.single.fieldId,
        'a-field',
      );
      expect(rewritten.updatedAt, isNot(before.updatedAt));
    },
  );

  test(
    'natural-key reconciliation chooses content only from the winning state',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = Choreographer(
        id: 'z-local-author',
        name: 'Same author',
        notes: 'deleted body',
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(local, at: stamp);

      final localTombstoneStamp = stamp.add(const Duration(minutes: 10));
      await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: local.id,
              updatedAt: localTombstoneStamp,
              deletedAt: localTombstoneStamp,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, local),
            ),
          ),
        ],
        storage: storage,
      );

      final incoming = Choreographer(
        id: 'a-remote-author',
        name: 'Same author',
        notes: 'live body',
      );
      final incomingStamp = stamp.add(const Duration(minutes: 2));
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: incoming.id,
              updatedAt: incomingStamp,
              deletedAt: null,
              existenceAt: incomingStamp,
              body: syncBodyForEntity(SyncRecordKind.choreographer, incoming),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final stored = await repositories.choreographers.getById(incoming.id);
      expect(stored, isNotNull);
      expect(stored!.notes, 'live body');
      expect(await repositories.choreographers.getById(local.id), isNull);
    },
  );

  test('natural-key body ties retain the pair in the review queue', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    final local = Choreographer(
      id: 'a-local-author',
      name: 'Same author',
      notes: 'local body',
    );
    // ignore: unused_result
    await repositories.choreographers.upsert(local, at: stamp);
    final incoming = Choreographer(
      id: 'z-remote-author',
      name: 'Same author',
      notes: 'remote body',
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.choreographer,
            id: incoming.id,
            updatedAt: stamp,
            deletedAt: null,
            existenceAt: stamp,
            body: syncBodyForEntity(SyncRecordKind.choreographer, incoming),
          ),
        ),
      ],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(result.reports, isEmpty);
    expect(
      (await repositories.syncLocal.listReviewQueue()).map(
        (row) => (row.recordId, row.counterpartId),
      ),
      [(incoming.id, local.id)],
    );
    expect(await repositories.choreographers.getById(local.id), isNotNull);
    expect(await repositories.choreographers.getById(incoming.id), isNull);
  });

  test('known UUID natural-key renames enter the review queue', () async {
    final stamp = DateTime.utc(2025, 1, 2, 12);
    // ignore: unused_result
    await repositories.choreographers.upsert(
      Choreographer(id: 'known-author', name: 'Original author'),
      at: stamp,
    );
    // ignore: unused_result
    await repositories.choreographers.upsert(
      Choreographer(id: 'other-author', name: 'Renamed author'),
      at: stamp,
    );

    final inbound = Choreographer(id: 'known-author', name: 'Renamed author');
    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: SyncRecordKind.choreographer,
            id: inbound.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: null,
            existenceAt: stamp.add(const Duration(minutes: 1)),
            body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
          ),
        ),
      ],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(result.reports, isEmpty);
    final review = await repositories.syncLocal.listReviewQueue();
    expect(review.map((row) => (row.recordId, row.counterpartId)), [
      ('known-author', 'other-author'),
    ]);
    expect(
      (await repositories.choreographers.getById('known-author'))!.name,
      'Original author',
    );
    expect(
      (await repositories.choreographers.getById('other-author'))!.name,
      'Renamed author',
    );
  });

  test(
    'canonical difficulty known-UUID conflicts enter the review queue',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      await (db.delete(
        db.difficultyLevels,
      )..where((row) => row.id.equals(DifficultyLevel.beginner.id))).go();
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(id: 'known-level', label: 'Renamed level', position: 0),
        at: stamp,
      );
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(
          id: 'other-level',
          label: DifficultyLevel.beginner.label,
          position: 1,
        ),
        at: stamp,
      );

      final inbound = DifficultyLevel(
        id: 'known-level',
        label: DifficultyLevel.beginner.label,
        position: 2,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.difficultyLevel,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.difficultyLevel, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports, isEmpty);
      expect(
        (await repositories.syncLocal.listReviewQueue()).map(
          (row) => (row.recordId, row.counterpartId),
        ),
        [('known-level', 'other-level')],
      );
      expect(
        (await repositories.difficultyLevels.getById('known-level'))!.label,
        'Renamed level',
      );
      expect(
        (await repositories.difficultyLevels.getById('other-level'))!.label,
        DifficultyLevel.beginner.label,
      );
      expect(
        await repositories.difficultyLevels.getById(
          DifficultyLevel.beginner.id,
        ),
        isNull,
      );
    },
  );

  test(
    'natural-key index chooses the smallest live legacy duplicate',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'a-author', name: 'Case duplicate'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'z-author', name: 'CASE DUPLICATE'),
        at: stamp,
      );
      final inbound = Choreographer(id: 'm-author', name: 'case duplicate');

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        (await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.choreographer,
          recordId: inbound.id,
        )),
        'a-author',
      );
      expect(await repositories.choreographers.getById('a-author'), isNotNull);
      expect(await repositories.choreographers.getById('z-author'), isNotNull);
    },
  );

  test(
    'shareability mismatch renames an inbound field without exposing private values',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final privateField = CustomFieldDef(
        id: 'private-field',
        key: 'private_key',
        label: 'Private key',
        type: CustomFieldType.text,
        shareable: false,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(privateField, at: stamp);
      final inbound = CustomFieldDef(
        id: 'shareable-field',
        key: privateField.key,
        label: privateField.label,
        type: privateField.type,
        shareable: true,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.customFieldDef, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final storedPrivate = await repositories.customFieldDefs.getById(
        privateField.id,
      );
      final storedInbound = await repositories.customFieldDefs.getById(
        inbound.id,
      );
      expect(storedPrivate, isNotNull);
      expect(storedPrivate!.key, privateField.key);
      expect(storedPrivate.shareable, isFalse);
      expect(storedInbound, isNotNull);
      expect(storedInbound!.key, isNot(privateField.key));
      expect(storedInbound.shareable, isTrue);

      final sameId = CustomFieldDef(
        id: privateField.id,
        key: privateField.key,
        label: privateField.label,
        type: privateField.type,
        shareable: true,
      );
      final sameIdResult = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: sameId.id,
              updatedAt: stamp.add(const Duration(minutes: 2)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 2)),
              body: syncBodyForEntity(SyncRecordKind.customFieldDef, sameId),
            ),
          ),
        ],
        storage: storage,
      );
      expect(sameIdResult.applied, isEmpty);
      expect(
        (await repositories.customFieldDefs.getById(
          privateField.id,
        ))!.shareable,
        isFalse,
      );
    },
  );

  test(
    'rejects a non-shareable definition before natural-key reconciliation',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = CustomFieldDef(
        id: 'z-local-shareable-field',
        key: 'shared_key',
        label: 'Shared key',
        type: CustomFieldType.text,
      );
      final inbound = CustomFieldDef(
        id: 'a-inbound-private-field',
        key: local.key,
        label: local.label,
        type: local.type,
        shareable: false,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(local, at: stamp);

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: archiveCustomFieldDefToJson(
                inbound,
                includeShareable: true,
                includeOptionalFields: true,
              ),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports.single.code, SyncReportCode.invalidClassification);
      final storedLocal = await repositories.customFieldDefs.getById(local.id);
      expect(storedLocal, isNotNull);
      expect(storedLocal!.key, local.key);
      expect(storedLocal.shareable, isTrue);
      expect(await repositories.customFieldDefs.getById(inbound.id), isNull);
      expect(await repositories.syncLocal.listAliases(), isEmpty);
    },
  );

  test(
    'malformed natural-key collisions do not mutate local identity state',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'z-local-field',
          key: 'shared_field',
          label: 'Shared field',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: 'a-inbound-field',
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: const {
                'id': 'a-inbound-field',
                'key': 'shared_field',
                'label': 'Shared field',
                'type': 'not-a-custom-field-type',
                'showInList': false,
                'searchable': false,
                'shareable': true,
              },
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports.single.code, SyncReportCode.malformedRecord);
      final local = await repositories.customFieldDefs.getById('z-local-field');
      expect(local, isNotNull);
      expect(local!.key, 'shared_field');
      expect(
        await repositories.customFieldDefs.getById('a-inbound-field'),
        isNull,
      );
      expect(await repositories.syncLocal.listAliases(), isEmpty);
    },
  );

  test(
    'custom-field type collisions retain both and stamp the renamed definition',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = CustomFieldDef(
        id: 'z-field-12345678',
        key: 'skill_level',
        label: 'Skill level',
        type: CustomFieldType.text,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        local,
        at: stamp,
      ); // ignore: unused_result
      final before = await (db.select(
        db.customFieldDefs,
      )..where((row) => row.id.equals(local.id))).getSingle();
      final inbound = CustomFieldDef(
        id: 'a-field-87654321',
        key: 'skill_level',
        label: 'Skill level',
        type: CustomFieldType.number,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.customFieldDef, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final renamed = await (db.select(
        db.customFieldDefs,
      )..where((row) => row.id.equals(local.id))).getSingle();
      expect(renamed.key, 'skill_level_zfield12');
      expect(renamed.updatedAt!.toUtc(), isNot(before.updatedAt!.toUtc()));
      expect(
        (await repositories.customFieldDefs.getById(inbound.id))!.key,
        'skill_level',
      );
    },
  );

  test(
    'custom-field type collisions escalate from an occupied short suffix',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = CustomFieldDef(
        id: '00000000-0000-0000-0000-000000000001',
        key: 'skill_level',
        label: 'Skill level',
        type: CustomFieldType.text,
      );
      final shortOccupier = CustomFieldDef(
        id: '00000000-0000-0000-0000-000000000002',
        key: 'skill_level_ffffffff',
        label: 'Occupied short suffix',
        type: CustomFieldType.text,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(local, at: stamp);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(shortOccupier, at: stamp);
      final incoming = CustomFieldDef(
        id: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
        key: 'skill_level',
        label: 'Skill level',
        type: CustomFieldType.number,
      );
      final candidate = SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.customFieldDef,
          id: incoming.id,
          updatedAt: stamp.add(const Duration(minutes: 1)),
          deletedAt: null,
          existenceAt: stamp.add(const Duration(minutes: 1)),
          body: syncBodyForEntity(SyncRecordKind.customFieldDef, incoming),
        ),
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [candidate],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final stored = await repositories.customFieldDefs.getById(incoming.id);
      expect(stored, isNotNull);
      expect(stored!.key, 'skill_level_ffffffffffffffffffffffffffffffff');
      final storedRow = await (db.select(
        db.customFieldDefs,
      )..where((row) => row.id.equals(incoming.id))).getSingle();
      expect(
        storedRow.updatedAt!.toUtc().isAfter(candidate.blob.updatedAt),
        isTrue,
      );
      final snapshot = await storage.snapshot();
      final publication =
          snapshot.publication[(
            kind: SyncRecordKind.customFieldDef,
            recordId: incoming.id,
          )];
      expect(publication, isNotNull);
      expect(publication!.wireHash, isNot(candidate.wireHash));
    },
  );

  test(
    'custom-field type collisions queue review when both suffixes are occupied',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: '00000000-0000-0000-0000-000000000011',
          key: 'skill_level',
          label: 'Skill level',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: '00000000-0000-0000-0000-000000000012',
          key: 'skill_level_ffffffff',
          label: 'Occupied short suffix',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: '00000000-0000-0000-0000-000000000013',
          key: 'skill_level_ffffffffffffffffffffffffffffffff',
          label: 'Occupied full suffix',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      final incoming = CustomFieldDef(
        id: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
        key: 'skill_level',
        label: 'Skill level',
        type: CustomFieldType.number,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.customFieldDef,
              id: incoming.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.customFieldDef, incoming),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports, isEmpty);
      final review = await repositories.syncLocal.listReviewQueue();
      expect(review, hasLength(1));
      expect(review.single.recordId, incoming.id);
      expect(
        review.single.counterpartId,
        '00000000-0000-0000-0000-000000000011',
      );
    },
  );

  test(
    'reconciles same-batch natural-key collisions before parent writes',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final first = Choreographer(id: 'z-author', name: 'Shared author');
      final second = Choreographer(id: 'a-author', name: 'Shared author');

      final result = await const SyncApplyEngine().apply(
        candidates: [
          for (final author in [first, second])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.choreographer,
                id: author.id,
                updatedAt: stamp,
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.choreographer, author),
              ),
            ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(result.applied, [
        (kind: SyncRecordKind.choreographer, recordId: 'a-author'),
      ]);
      expect(await repositories.choreographers.getById('a-author'), isNotNull);
      expect(await repositories.choreographers.getById('z-author'), isNull);
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.choreographer,
          recordId: 'z-author',
        ),
        'a-author',
      );
    },
  );

  test(
    'retains same-batch custom-field type collisions with a deterministic key',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final text = CustomFieldDef(
        id: 'z-field-12345678',
        key: 'shared_field',
        label: 'Shared field',
        type: CustomFieldType.text,
      );
      final number = CustomFieldDef(
        id: 'a-field-87654321',
        key: 'shared_field',
        label: 'Shared field',
        type: CustomFieldType.number,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          for (final field in [text, number])
            SyncMergeCandidate(
              blob: SyncRecordBlob(
                kind: SyncRecordKind.customFieldDef,
                id: field.id,
                updatedAt: stamp,
                deletedAt: null,
                existenceAt: stamp,
                body: syncBodyForEntity(SyncRecordKind.customFieldDef, field),
              ),
            ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        (await repositories.customFieldDefs.getById(number.id))!.key,
        'shared_field',
      );
      expect(
        (await repositories.customFieldDefs.getById(text.id))!.key,
        'shared_field_zfield12',
      );
    },
  );

  test(
    'remaps pending tombstones when a natural-key loser is migrated',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      final local = Choreographer(id: 'z-author', name: 'Shared author');
      // ignore: unused_result
      await repositories.choreographers.upsert(local, at: stamp);
      final dance = Dance(
        id: 'cited-dance',
        title: 'Cited dance',
        authorIds: [local.id],
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repositories.dances.create(dance);

      final tombstoneStamp = stamp.add(const Duration(minutes: 1));
      final tombstone = syncRecordBlobForEntity(
        SyncRecordKind.choreographer,
        local,
        updatedAt: tombstoneStamp,
        deletedAt: tombstoneStamp,
        existenceAt: tombstoneStamp,
      )!;
      final tombstoneJson = encodeSyncRecordBlob(tombstone);
      await repositories.syncLocal.upsertPendingDeletion(
        kind: SyncRecordKind.choreographer,
        recordId: local.id,
        tombstonedAt: tombstoneStamp,
        tombstoneHash: sha256Hex(utf8.encode(tombstoneJson)),
        tombstoneBlob: tombstoneJson,
      );
      final danceTombstone = syncRecordBlobForEntity(
        SyncRecordKind.dance,
        dance,
        updatedAt: tombstoneStamp,
        deletedAt: tombstoneStamp,
        existenceAt: tombstoneStamp,
      )!;
      final danceTombstoneUpdatedAt = danceTombstone.updatedAt;
      final danceTombstoneJson = encodeSyncRecordBlob(danceTombstone);
      await repositories.syncLocal.upsertPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: dance.id,
        tombstonedAt: tombstoneStamp,
        tombstoneHash: sha256Hex(utf8.encode(danceTombstoneJson)),
        tombstoneBlob: danceTombstoneJson,
      );

      final inbound = Choreographer(id: 'a-author', name: 'Shared author');
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 2)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 2)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: local.id,
        ),
        isNull,
      );
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: inbound.id,
        ),
        isNotNull,
      );
      final remappedDance = await repositories.syncLocal.getPendingDeletion(
        kind: SyncRecordKind.dance,
        recordId: dance.id,
      );
      expect(remappedDance, isNotNull);
      expect(
        decodeSyncRecordBlob(remappedDance!.tombstoneBlob).body['authorIds'],
        [inbound.id],
      );
      expect(
        decodeSyncRecordBlob(
          remappedDance.tombstoneBlob,
        ).updatedAt.toUtc().isAfter(danceTombstoneUpdatedAt.toUtc()),
        isTrue,
      );
    },
  );

  test(
    'remaps large alias closures with pending tombstones and markers',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      const total = 1001;
      await repositories.syncLocal.transaction((tx) async {
        for (var i = 0; i < total; i++) {
          await tx.upsertAlias(
            kind: SyncRecordKind.choreographer,
            losingId: 'chain-${i.toString().padLeft(4, '0')}',
            survivingId: 'chain-${(i + 1).toString().padLeft(4, '0')}',
          );
        }
        await tx.markPublished(
          kind: SyncRecordKind.choreographer,
          recordId: 'chain-0000',
        );
      });

      final local = Choreographer(id: 'chain-1001', name: 'Shared author');
      // ignore: unused_result
      await repositories.choreographers.upsert(local, at: stamp);
      final tombstone = syncRecordBlobForEntity(
        SyncRecordKind.choreographer,
        Choreographer(id: 'chain-0000', name: 'Shared author'),
        updatedAt: stamp.add(const Duration(minutes: 1)),
        deletedAt: stamp.add(const Duration(minutes: 1)),
        existenceAt: stamp.add(const Duration(minutes: 1)),
      )!;
      final tombstoneJson = encodeSyncRecordBlob(tombstone);
      await repositories.syncLocal.upsertPendingDeletion(
        kind: SyncRecordKind.choreographer,
        recordId: 'chain-0000',
        tombstonedAt: stamp.add(const Duration(minutes: 1)),
        tombstoneHash: sha256Hex(utf8.encode(tombstoneJson)),
        tombstoneBlob: tombstoneJson,
      );

      final inbound = Choreographer(id: 'a-author', name: 'Shared author');
      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 2)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 2)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(
        await repositories.syncLocal.getPendingDeletion(
          kind: SyncRecordKind.choreographer,
          recordId: 'a-author',
        ),
        isNotNull,
      );
      expect(
        await repositories.syncLocal.isPublished(
          kind: SyncRecordKind.choreographer,
          recordId: 'a-author',
        ),
        isTrue,
      );
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.choreographer,
          recordId: 'chain-0000',
        ),
        'a-author',
      );
    },
  );

  test(
    'timestamps inbound bodies changed by aliases for republication',
    () async {
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'a-author', name: 'Author'),
        at: stamp,
      );
      await repositories.syncLocal.upsertAlias(
        kind: SyncRecordKind.choreographer,
        losingId: 'z-author',
        survivingId: 'a-author',
      );
      final candidateStamp = stamp.add(const Duration(minutes: 1));
      final dance = Dance(
        id: 'alias-rewritten-dance',
        title: 'Alias rewritten',
        authorIds: const ['z-author'],
        createdAt: stamp,
        updatedAt: candidateStamp,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.dance,
              id: dance.id,
              updatedAt: candidateStamp,
              deletedAt: null,
              existenceAt: stamp,
              body: syncBodyForEntity(SyncRecordKind.dance, dance),
            ),
          ),
        ],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      final stored = await (db.select(
        db.dances,
      )..where((row) => row.id.equals(dance.id))).getSingle();
      expect(stored.updatedAt.toUtc().isAfter(candidateStamp), isTrue);
      expect((await repositories.dances.getById(dance.id))!.authorIds, [
        'a-author',
      ]);
    },
  );

  group('persisted sync review resolution', () {
    final stamp = DateTime.utc(2025, 1, 2, 12);

    Future<void> seedLocal(SyncRecordKind kind, String id, String key) async {
      switch (kind) {
        case SyncRecordKind.choreographer:
          // ignore: unused_result
          await repositories.choreographers.upsert(
            Choreographer(id: id, name: key),
            at: stamp,
          );
        case SyncRecordKind.tag:
          // ignore: unused_result
          await repositories.tags.upsert(
            Tag(id: id, name: key),
            at: stamp,
          );
        case SyncRecordKind.customFieldDef:
          // ignore: unused_result
          await repositories.customFieldDefs.upsert(
            CustomFieldDef(
              id: id,
              key: key,
              label: 'Local field',
              type: CustomFieldType.text,
            ),
            at: stamp,
          );
        case SyncRecordKind.difficultyLevel:
          // ignore: unused_result
          await repositories.difficultyLevels.upsert(
            DifficultyLevel(id: id, label: key, position: 99),
            at: stamp,
          );
        case SyncRecordKind.dance:
        case SyncRecordKind.program:
        case SyncRecordKind.publishedSource:
        case SyncRecordKind.venue:
        case SyncRecordKind.setting:
          throw StateError('unsupported test kind: $kind');
      }
    }

    SyncRecordBlob tombstoneFor(
      SyncRecordKind kind,
      String id,
      String key, {
      String? customFieldType,
    }) {
      final body = switch (kind) {
        SyncRecordKind.choreographer => syncBodyForEntity(
          kind,
          Choreographer(id: id, name: key),
        ),
        SyncRecordKind.tag => syncBodyForEntity(kind, Tag(id: id, name: key)),
        SyncRecordKind.customFieldDef =>
          customFieldType == null
              ? syncBodyForEntity(
                  kind,
                  CustomFieldDef(
                    id: id,
                    key: key,
                    label: 'Remote field',
                    type: CustomFieldType.text,
                  ),
                )
              : <String, Object?>{
                  'id': id,
                  'key': key,
                  'label': 'Remote field',
                  'type': customFieldType,
                  'showInList': false,
                  'searchable': false,
                  'shareable': true,
                },
        SyncRecordKind.difficultyLevel => syncBodyForEntity(
          kind,
          DifficultyLevel(id: id, label: key, position: 100),
        ),
        SyncRecordKind.dance ||
        SyncRecordKind.program ||
        SyncRecordKind.publishedSource ||
        SyncRecordKind.venue ||
        SyncRecordKind.setting => throw StateError('unsupported test kind'),
      };
      return SyncRecordBlob(
        kind: kind,
        id: id,
        updatedAt: stamp.add(const Duration(minutes: 1)),
        deletedAt: stamp.add(const Duration(minutes: 1)),
        existenceAt: stamp.add(const Duration(minutes: 1)),
        body: body,
      );
    }

    Future<SyncReviewQueueItem> enqueue(
      SyncRecordKind kind,
      String localId,
      SyncRecordBlob candidate, {
      String reason = syncBaselineAbsenceTombstoneReason,
    }) async {
      final candidateBlob = encodeSyncRecordBlob(candidate);
      final localHash =
          reason == syncBaselineAbsenceTombstoneReason ||
              reason == syncDanceChoreographyAmbiguityReason
          ? (await storage.snapshot())
                .local[(kind: kind, recordId: localId)]
                ?.wireHash
          : null;
      await repositories.syncLocal.enqueueReview(
        kind: kind,
        recordId: localId,
        counterpartId: candidate.id,
        reason: reason,
        candidateBlob: candidateBlob,
        candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(candidate)),
        localHash: localHash,
        queuedAt: stamp.add(const Duration(minutes: 2)),
      );
      return SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.listReviewQueue()).single,
      );
    }

    Future<void> expectLiveKey(
      SyncRecordKind kind,
      String id,
      String key,
    ) async {
      switch (kind) {
        case SyncRecordKind.choreographer:
          expect((await repositories.choreographers.getById(id))!.name, key);
        case SyncRecordKind.tag:
          expect((await repositories.tags.getById(id))!.name, key);
        case SyncRecordKind.customFieldDef:
          expect((await repositories.customFieldDefs.getById(id))!.key, key);
        case SyncRecordKind.difficultyLevel:
          expect((await repositories.difficultyLevels.getById(id))!.label, key);
        case SyncRecordKind.dance:
        case SyncRecordKind.program:
        case SyncRecordKind.publishedSource:
        case SyncRecordKind.venue:
        case SyncRecordKind.setting:
          throw StateError('unsupported test kind: $kind');
      }
    }

    Future<void> expectTombstone(SyncRecordKind kind, String id) async {
      switch (kind) {
        case SyncRecordKind.choreographer:
          expect(
            (await (db.select(
              db.choreographers,
            )..where((row) => row.id.equals(id))).getSingle()).deletedAt,
            isNotNull,
          );
        case SyncRecordKind.tag:
          expect(
            (await (db.select(
              db.tags,
            )..where((row) => row.id.equals(id))).getSingle()).deletedAt,
            isNotNull,
          );
        case SyncRecordKind.customFieldDef:
          expect(
            (await (db.select(
              db.customFieldDefs,
            )..where((row) => row.id.equals(id))).getSingle()).deletedAt,
            isNotNull,
          );
        case SyncRecordKind.difficultyLevel:
          expect(
            (await (db.select(
              db.difficultyLevels,
            )..where((row) => row.id.equals(id))).getSingle()).deletedAt,
            isNotNull,
          );
        case SyncRecordKind.dance:
        case SyncRecordKind.program:
        case SyncRecordKind.publishedSource:
        case SyncRecordKind.venue:
        case SyncRecordKind.setting:
          throw StateError('unsupported test kind: $kind');
      }
    }

    test(
      'keeps both for every supported natural-key kind and consumes the row',
      () async {
        for (final kind in syncNaturalKeyKinds) {
          final localId = 'local-${kind.name}';
          final remoteId = 'remote-${kind.name}';
          final localKey = 'Local ${kind.name}';
          final renamedKey = kind == SyncRecordKind.customFieldDef
              ? 'renamed_${kind.name}'
              : 'Renamed ${kind.name}';
          await seedLocal(kind, localId, localKey);
          final item = await enqueue(
            kind,
            localId,
            tombstoneFor(kind, remoteId, localKey),
          );

          await storage.resolveReviewQueue(
            expectedRow: item.row,
            action: SyncReviewAction.keepBoth,
            newNaturalKey: renamedKey,
          );

          await expectLiveKey(kind, localId, renamedKey);
          expect(
            await repositories.syncLocal.getReviewQueue(
              kind: kind,
              recordId: localId,
              counterpartId: remoteId,
            ),
            isNull,
          );
          await expectTombstone(kind, remoteId);
        }
      },
    );

    test(
      'reconciliation-produced tombstone rows use local and peer identities',
      () async {
        const kind = SyncRecordKind.choreographer;
        const localId = 'reconciled-local';
        const remoteId = 'reconciled-remote';
        const key = 'Reconciled author';
        await seedLocal(kind, localId, key);
        final candidate = tombstoneFor(kind, remoteId, key);

        final result = await const SyncApplyEngine().apply(
          candidates: [SyncMergeCandidate(blob: candidate)],
          storage: storage,
        );

        expect(result.applied, isEmpty);
        expect(result.reports, isEmpty);
        final item = SyncReviewQueueItem.fromRow(
          (await repositories.syncLocal.listReviewQueue()).single,
        );
        expect(item.row.recordId, localId);
        expect(item.row.counterpartId, remoteId);
        expect(item.isActionable, isTrue);

        await storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: 'Reconciled author (local)',
        );

        await expectLiveKey(kind, localId, 'Reconciled author (local)');
        await expectTombstone(kind, remoteId);
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );

    test(
      'canonical difficulty tombstone rows use local and peer identities',
      () async {
        await (db.delete(
          db.difficultyLevels,
        )..where((row) => row.id.equals(DifficultyLevel.beginner.id))).go();
        const kind = SyncRecordKind.difficultyLevel;
        const localId = 'reconciled-local-difficulty';
        const remoteId = 'reconciled-remote-difficulty';
        final key = DifficultyLevel.beginner.label;
        await seedLocal(kind, localId, key);
        final candidate = tombstoneFor(kind, remoteId, key);

        final result = await const SyncApplyEngine().apply(
          candidates: [SyncMergeCandidate(blob: candidate)],
          storage: storage,
        );

        expect(result.applied, isEmpty);
        expect(result.reports, isEmpty);
        final item = SyncReviewQueueItem.fromRow(
          (await repositories.syncLocal.listReviewQueue()).single,
        );
        expect(item.row.recordId, localId);
        expect(item.row.counterpartId, remoteId);
        expect(item.isActionable, isTrue);

        await storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: '$key (local)',
        );
        await expectLiveKey(kind, localId, '$key (local)');
        await expectTombstone(kind, remoteId);
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );

    test('survives a file-backed close and reopen before resolution', () async {
      final directory = await Directory.systemTemp.createTemp(
        'compendium-w14-',
      );
      final path = '${directory.path}/compendium.sqlite';
      CompendiumDatabase? fileDb;
      try {
        final initialDb = CompendiumDatabase(NativeDatabase(File(path)));
        fileDb = initialDb;
        final fileRepositories = CompendiumRepositories(
          initialDb,
          contraTaxonomy,
        );
        const kind = SyncRecordKind.choreographer;
        const localId = 'restart-local';
        const remoteId = 'restart-remote';
        const key = 'Restart author';
        // ignore: unused_result
        await fileRepositories.choreographers.upsert(
          Choreographer(id: localId, name: key),
          at: stamp,
        );
        final candidate = tombstoneFor(kind, remoteId, key);
        await fileRepositories.syncLocal.enqueueReview(
          kind: kind,
          recordId: localId,
          counterpartId: remoteId,
          reason: syncBaselineAbsenceTombstoneReason,
          candidateBlob: encodeSyncRecordBlob(candidate),
          candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(candidate)),
          localHash: (await CompendiumSyncStorage(
            fileRepositories,
          ).snapshot()).local[(kind: kind, recordId: localId)]!.wireHash,
          queuedAt: stamp.add(const Duration(minutes: 2)),
        );
        await initialDb.close();
        final reopenedDb = CompendiumDatabase(NativeDatabase(File(path)));
        fileDb = reopenedDb;
        final reopenedRepositories = CompendiumRepositories(
          reopenedDb,
          contraTaxonomy,
        );
        final reopenedStorage = CompendiumSyncStorage(reopenedRepositories);
        final row =
            (await reopenedRepositories.syncLocal.listReviewQueue()).single;

        await reopenedStorage.resolveReviewQueue(
          expectedRow: row,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: 'Restart author (local)',
        );

        expect(
          (await reopenedRepositories.choreographers.getById(localId))!.name,
          'Restart author (local)',
        );
        expect(
          await reopenedRepositories.choreographers.getById(remoteId),
          isNull,
        );
        final remoteRow = await (reopenedDb.select(
          reopenedDb.choreographers,
        )..where((table) => table.id.equals(remoteId))).getSingle();
        expect(remoteRow.deletedAt, isNotNull);
        expect(await reopenedRepositories.syncLocal.listReviewQueue(), isEmpty);
      } finally {
        await fileDb?.close();
        await directory.delete(recursive: true);
      }
    });

    test(
      'rolls back a keep-both rename when the production write seam fails',
      () async {
        final interceptor = _FailAfterNaturalKeyRenameInterceptor();
        final injectedDb = CompendiumDatabase(
          NativeDatabase.memory().interceptWith(interceptor),
        );
        addTearDown(injectedDb.close);
        final injectedRepositories = CompendiumRepositories(
          injectedDb,
          contraTaxonomy,
        );
        const kind = SyncRecordKind.choreographer;
        const localId = 'rollback-local';
        const remoteId = 'rollback-remote';
        const key = 'Rollback author';
        // ignore: unused_result
        await injectedRepositories.choreographers.upsert(
          Choreographer(id: localId, name: key),
          at: stamp,
        );
        final candidate = tombstoneFor(kind, remoteId, key);
        await injectedRepositories.syncLocal.enqueueReview(
          kind: kind,
          recordId: localId,
          counterpartId: remoteId,
          reason: syncBaselineAbsenceTombstoneReason,
          candidateBlob: encodeSyncRecordBlob(candidate),
          candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(candidate)),
          localHash: (await CompendiumSyncStorage(
            injectedRepositories,
          ).snapshot()).local[(kind: kind, recordId: localId)]!.wireHash,
          queuedAt: stamp.add(const Duration(minutes: 2)),
        );
        final item = SyncReviewQueueItem.fromRow(
          (await injectedRepositories.syncLocal.listReviewQueue()).single,
        );
        interceptor.arm();

        await expectLater(
          CompendiumSyncStorage(injectedRepositories).resolveReviewQueue(
            expectedRow: item.row,
            action: SyncReviewAction.keepBoth,
            newNaturalKey: 'Rollback author (local)',
          ),
          throwsA(isA<StateError>()),
        );

        expect(
          (await injectedRepositories.choreographers.getById(localId))!.name,
          key,
        );
        expect(
          await injectedRepositories.choreographers.getById(remoteId),
          isNull,
        );
        expect(await injectedRepositories.syncLocal.listAliases(), isEmpty);
        expect(
          await injectedRepositories.syncLocal.listReviewQueue(),
          hasLength(1),
        );
      },
    );

    test(
      'merge chooses the lexicographically smaller local identity',
      () async {
        const kind = SyncRecordKind.choreographer;
        const localId = 'merge-local';
        const remoteId = 'merge-remote';
        const key = 'Merge author';
        await seedLocal(kind, localId, key);
        final candidate = tombstoneFor(kind, remoteId, key);
        final item = await enqueue(kind, localId, candidate);

        await storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.merge,
        );

        expect(await repositories.choreographers.getById(localId), isNull);
        expect(
          await repositories.syncLocal.resolveAlias(
            kind: kind,
            recordId: remoteId,
          ),
          localId,
        );
        await expectTombstone(kind, localId);
        expect(await repositories.choreographers.getById(remoteId), isNull);
        final local = await (db.select(
          db.choreographers,
        )..where((row) => row.id.equals(localId))).getSingle();
        expect(local.updatedAt?.toUtc(), candidate.updatedAt);
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );

    test('merge keeps a shipped difficulty ID canonical', () async {
      const kind = SyncRecordKind.difficultyLevel;
      const localId = DifficultyLevel.beginnerId;
      const remoteId = 'a-merge-remote-difficulty';
      final key = DifficultyLevel.beginner.label;
      await seedLocal(kind, localId, key);
      final localRow = await (db.select(
        db.difficultyLevels,
      )..where((row) => row.id.equals(localId))).getSingle();
      final candidateStamp = localRow.existenceAt!.toUtc().add(
        const Duration(minutes: 1),
      );
      final baseCandidate = tombstoneFor(kind, remoteId, key);
      final candidate = SyncRecordBlob(
        v: baseCandidate.v,
        kind: baseCandidate.kind,
        id: baseCandidate.id,
        updatedAt: candidateStamp,
        deletedAt: candidateStamp,
        existenceAt: candidateStamp,
        body: baseCandidate.body,
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: candidate)],
        storage: storage,
      );

      expect(result.applied, isEmpty);
      expect(result.reports, isEmpty);
      final item = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.listReviewQueue()).single,
      );
      expect(item.row.recordId, localId);
      expect(item.row.counterpartId, remoteId);

      await storage.resolveReviewQueue(
        expectedRow: item.row,
        action: SyncReviewAction.merge,
      );

      expect(
        await repositories.syncLocal.resolveAlias(
          kind: kind,
          recordId: remoteId,
        ),
        localId,
      );
      await expectTombstone(kind, localId);
      expect(await repositories.difficultyLevels.getById(remoteId), isNull);
      final local = await (db.select(
        db.difficultyLevels,
      )..where((row) => row.id.equals(localId))).getSingle();
      expect(local.updatedAt?.toUtc(), candidate.updatedAt);
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    });

    test('merge chooses the lexicographically smaller peer identity', () async {
      const kind = SyncRecordKind.choreographer;
      const localId = 'z-merge-local';
      const remoteId = 'a-merge-remote';
      const key = 'Merge peer author';
      await seedLocal(kind, localId, key);
      final item = await enqueue(
        kind,
        localId,
        tombstoneFor(kind, remoteId, key),
      );

      await storage.resolveReviewQueue(
        expectedRow: item.row,
        action: SyncReviewAction.merge,
      );

      expect(await repositories.choreographers.getById(localId), isNull);
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: kind,
          recordId: localId,
        ),
        remoteId,
      );
      await expectTombstone(kind, remoteId);
      expect(await repositories.choreographers.getById(remoteId), isNull);
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    });

    test('merge applies the tombstone to the deterministic survivor', () async {
      const kind = SyncRecordKind.choreographer;
      const localId = 'merge-check-local';
      const remoteId = 'merge-check-remote';
      const key = 'Merge check author';
      await seedLocal(kind, localId, key);
      final item = await enqueue(
        kind,
        localId,
        tombstoneFor(kind, remoteId, key),
      );

      await storage.resolveReviewQueue(
        expectedRow: item.row,
        action: SyncReviewAction.merge,
      );

      final survivor = localId.compareTo(remoteId) < 0 ? localId : remoteId;
      final loser = survivor == localId ? remoteId : localId;
      expect(
        await repositories.syncLocal.resolveAlias(kind: kind, recordId: loser),
        survivor,
      );
      final row = await (db.select(
        db.choreographers,
      )..where((row) => row.id.equals(survivor))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
    });

    test(
      'rejects invalid names without changing or consuming the row',
      () async {
        const kind = SyncRecordKind.choreographer;
        const localId = 'invalid-name-local';
        const remoteId = 'invalid-name-remote';
        const key = 'Invalid name author';
        await seedLocal(kind, localId, key);
        final item = await enqueue(
          kind,
          localId,
          tombstoneFor(kind, remoteId, key),
        );

        await expectLater(
          storage.resolveReviewQueue(
            expectedRow: item.row,
            action: SyncReviewAction.keepBoth,
            newNaturalKey: '   ',
          ),
          throwsA(
            isA<SyncReviewException>().having(
              (error) => error.code,
              'code',
              SyncReviewFailureCode.nameRequired,
            ),
          ),
        );
        await expectLiveKey(kind, localId, key);
        expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
      },
    );

    test(
      'keep-both trims surrounding whitespace from renamed natural keys',
      () async {
        const kind = SyncRecordKind.choreographer;
        const localId = 'trimmed-name-local';
        const remoteId = 'trimmed-name-remote';
        const key = 'Trim target author';
        await seedLocal(kind, localId, key);
        final item = await enqueue(
          kind,
          localId,
          tombstoneFor(kind, remoteId, key),
        );

        await storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: '  Trimmed rename  ',
        );

        await expectLiveKey(kind, localId, 'Trimmed rename');
        await expectTombstone(kind, remoteId);
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );

    test(
      'rejects a tombstone when the local existence stamp is newer',
      () async {
        for (final action in SyncReviewAction.values) {
          final localId = 'stale-local-${action.name}';
          final remoteId = 'stale-remote-${action.name}';
          final key = 'Stale author ${action.name}';
          await seedLocal(SyncRecordKind.choreographer, localId, key);
          final item = await enqueue(
            SyncRecordKind.choreographer,
            localId,
            tombstoneFor(SyncRecordKind.choreographer, remoteId, key),
          );
          await repositories.choreographers.delete(
            localId,
            at: stamp.add(const Duration(minutes: 2)),
          );
          await repositories.choreographers.restore(
            localId,
            at: stamp.add(const Duration(minutes: 3)),
          );

          await expectLater(
            storage.resolveReviewQueue(
              expectedRow: item.row,
              action: action,
              newNaturalKey: action == SyncReviewAction.keepBoth
                  ? 'Restored author ${action.name}'
                  : null,
            ),
            throwsA(
              isA<SyncReviewException>().having(
                (error) => error.code,
                'code',
                SyncReviewFailureCode.candidateChanged,
              ),
            ),
          );
          await expectLiveKey(SyncRecordKind.choreographer, localId, key);
          expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
          await repositories.syncLocal.deleteReview(
            kind: SyncRecordKind.choreographer,
            recordId: localId,
            counterpartId: remoteId,
          );
        }
      },
    );

    test(
      'rejects an ordinary local edit even when existence is unchanged',
      () async {
        for (final action in SyncReviewAction.values) {
          const kind = SyncRecordKind.customFieldDef;
          final localId = 'ordinary-edit-local-${action.name}';
          final remoteId = 'ordinary-edit-remote-${action.name}';
          final key = 'ordinary_edit_${action.name}';
          await seedLocal(kind, localId, key);
          final item = await enqueue(
            kind,
            localId,
            tombstoneFor(kind, remoteId, key),
          );
          final before = await (db.select(
            db.customFieldDefs,
          )..where((row) => row.id.equals(localId))).getSingle();

          // ignore: unused_result
          await repositories.customFieldDefs.upsert(
            CustomFieldDef(
              id: localId,
              key: key,
              label: 'Edited field',
              type: CustomFieldType.text,
            ),
            at: stamp.add(const Duration(minutes: 3)),
          );
          final after = await (db.select(
            db.customFieldDefs,
          )..where((row) => row.id.equals(localId))).getSingle();
          expect(after.existenceAt, before.existenceAt);
          expect(after.updatedAt, isNot(before.updatedAt));

          await expectLater(
            storage.resolveReviewQueue(
              expectedRow: item.row,
              action: action,
              newNaturalKey: action == SyncReviewAction.keepBoth
                  ? 'ordinary_edit_${action.name}_renamed'
                  : null,
            ),
            throwsA(
              isA<SyncReviewException>().having(
                (error) => error.code,
                'code',
                SyncReviewFailureCode.candidateChanged,
              ),
            ),
          );
          expect(
            (await repositories.customFieldDefs.getById(localId))!.label,
            'Edited field',
          );
          expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
          await repositories.syncLocal.deleteReview(
            kind: kind,
            recordId: localId,
            counterpartId: remoteId,
          );
        }
      },
    );

    test('rejects legacy review rows without a local hash', () async {
      const kind = SyncRecordKind.choreographer;
      const localId = 'legacy-local';
      const remoteId = 'legacy-remote';
      const key = 'Legacy author';
      await seedLocal(kind, localId, key);
      final candidate = tombstoneFor(kind, remoteId, key);
      await repositories.syncLocal.enqueueReview(
        kind: kind,
        recordId: localId,
        counterpartId: remoteId,
        reason: syncBaselineAbsenceTombstoneReason,
        candidateBlob: encodeSyncRecordBlob(candidate),
        candidateHash: sha256Hex(encodeSyncRecordBlobUtf8(candidate)),
        queuedAt: stamp.add(const Duration(minutes: 2)),
      );
      final item = SyncReviewQueueItem.fromRow(
        (await repositories.syncLocal.listReviewQueue()).single,
      );
      expect(item.row.localHash, isNull);

      await expectLater(
        storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.merge,
        ),
        throwsA(
          isA<SyncReviewException>().having(
            (error) => error.code,
            'code',
            SyncReviewFailureCode.candidateChanged,
          ),
        ),
      );
      final retained = await repositories.syncLocal.listReviewQueue();
      expect(retained, hasLength(1));
      expect(retained.single.localHash, isNull);
      await expectLiveKey(kind, localId, key);
    });

    test(
      'rejects invalid custom-field keep-both keys without changing the row',
      () async {
        const kind = SyncRecordKind.customFieldDef;
        const localId = 'invalid-custom-key-local';
        const remoteId = 'invalid-custom-key-remote';
        const key = 'invalid_custom_key';
        await seedLocal(kind, localId, key);
        final item = await enqueue(
          kind,
          localId,
          tombstoneFor(kind, remoteId, key),
        );

        await expectLater(
          storage.resolveReviewQueue(
            expectedRow: item.row,
            action: SyncReviewAction.keepBoth,
            newNaturalKey: 'invalid custom key',
          ),
          throwsA(
            isA<SyncReviewException>().having(
              (error) => error.code,
              'code',
              SyncReviewFailureCode.invalidCustomFieldKey,
            ),
          ),
        );
        await expectLiveKey(kind, localId, key);
        expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
        expect(await repositories.customFieldDefs.getById(remoteId), isNull);
      },
    );

    test('retains unsupported reasons and malformed candidates', () async {
      const kind = SyncRecordKind.choreographer;
      const localId = 'retained-local';
      const remoteId = 'retained-remote';
      const key = 'Retained author';
      await seedLocal(kind, localId, key);
      final unsupported = await enqueue(
        kind,
        localId,
        tombstoneFor(kind, remoteId, key),
        reason: 'known UUID natural-key rename collides with another local row',
      );

      expect(unsupported.isActionable, isFalse);
      await expectLater(
        storage.resolveReviewQueue(
          expectedRow: unsupported.row,
          action: SyncReviewAction.merge,
        ),
        throwsA(
          isA<SyncReviewException>().having(
            (error) => error.code,
            'code',
            SyncReviewFailureCode.unsupportedReason,
          ),
        ),
      );
      expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));

      await repositories.syncLocal.deleteReview(
        kind: kind,
        recordId: localId,
        counterpartId: remoteId,
      );
      final malformed = await enqueue(
        SyncRecordKind.customFieldDef,
        'malformed-local',
        tombstoneFor(
          SyncRecordKind.customFieldDef,
          'malformed-remote',
          'malformed_field',
          customFieldType: 'not-a-type',
        ),
      );
      expect(malformed.isActionable, isFalse);
      await seedLocal(
        SyncRecordKind.customFieldDef,
        'malformed-local',
        'malformed_field',
      );
      await expectLater(
        storage.resolveReviewQueue(
          expectedRow: malformed.row,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: 'renamed_malformed_field',
        ),
        throwsA(
          isA<SyncReviewException>().having(
            (error) => error.code,
            'code',
            SyncReviewFailureCode.candidateInvalid,
          ),
        ),
      );
      await expectLiveKey(
        SyncRecordKind.customFieldDef,
        'malformed-local',
        'malformed_field',
      );
      expect(await repositories.syncLocal.listReviewQueue(), hasLength(1));
      expect(
        await repositories.customFieldDefs.getById('malformed-remote'),
        isNull,
      );
    });

    // Copilot review on PR #1327: the merge path derived its survivor from
    // `_canonicalDifficultyId` without resolving it, while `_adoptCollision`
    // resolves its own target — so a shipped ID an earlier collision had
    // already retired split one natural key across two rows.
    test(
      'merge resolves a retired shipped difficulty ID before adopting',
      () async {
        const kind = SyncRecordKind.difficultyLevel;
        await (db.delete(
          db.difficultyLevels,
        )..where((row) => row.id.equals(DifficultyLevel.beginnerId))).go();
        await seedLocal(kind, 'review-custom-level', 'Beginner');
        await repositories.syncLocal.upsertAlias(
          kind: kind,
          losingId: DifficultyLevel.beginnerId,
          survivingId: 'review-ghost-level',
        );

        final item = await enqueue(
          kind,
          'review-custom-level',
          tombstoneFor(kind, 'review-remote-level', 'Beginner'),
        );
        expect(item.isActionable, isTrue);

        await storage.resolveReviewQueue(
          expectedRow: item.row,
          action: SyncReviewAction.merge,
        );

        // One row for the natural key, at the end of the alias chain, and the
        // merged tombstone landed on it.
        final rows = await db.select(db.difficultyLevels).get();
        final beginners = [
          for (final row in rows)
            if (row.label == 'Beginner') row,
        ];
        expect(beginners, hasLength(1));
        expect(beginners.single.id, 'review-ghost-level');
        expect(beginners.single.deletedAt, isNotNull);
        expect(
          await repositories.syncLocal.resolveAlias(
            kind: kind,
            recordId: 'review-custom-level',
          ),
          'review-ghost-level',
        );
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );

    // The local-hash guard above only stays safe if re-observing the collision
    // re-queues the row. `insertOrIgnore` alone would pin the first
    // observation, leaving an actionable row that no decision could ever
    // satisfy and a peer tombstone that could never converge.
    test(
      're-queues a tombstone review after the local record changes',
      () async {
        const kind = SyncRecordKind.tag;
        final tombstone = tombstoneFor(kind, 'requeue-remote', 'Requeue tag');
        final candidate = SyncMergeCandidate(blob: tombstone);
        await seedLocal(kind, 'requeue-local', 'Requeue tag');

        await const SyncApplyEngine().apply(
          candidates: [candidate],
          storage: storage,
        );
        final first = (await repositories.syncLocal.listReviewQueue()).single;
        expect(first.reason, syncBaselineAbsenceTombstoneReason);
        expect(first.localHash, isNotNull);

        // Re-observing an unchanged collision must not churn the queue.
        await const SyncApplyEngine().apply(
          candidates: [candidate],
          storage: storage,
        );
        final unchanged =
            (await repositories.syncLocal.listReviewQueue()).single;
        expect(unchanged.queuedAt, first.queuedAt);
        expect(unchanged.localHash, first.localHash);

        // An ordinary local edit invalidates the captured hash.
        // ignore: unused_result
        await repositories.tags.upsert(
          Tag(id: 'requeue-local', name: 'Requeue tag', color: 0xFF0000),
          at: stamp.add(const Duration(minutes: 5)),
        );
        await const SyncApplyEngine().apply(
          candidates: [candidate],
          storage: storage,
        );

        final refreshed =
            (await repositories.syncLocal.listReviewQueue()).single;
        expect(refreshed.localHash, isNot(first.localHash));
        final item = SyncReviewQueueItem.fromRow(refreshed);
        expect(item.isActionable, isTrue);

        // The refreshed row resolves; the stale one never could.
        await storage.resolveReviewQueue(
          expectedRow: refreshed,
          action: SyncReviewAction.keepBoth,
          newNaturalKey: 'Requeue tag local',
        );
        await expectLiveKey(kind, 'requeue-local', 'Requeue tag local');
        expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
      },
    );
  });
}

final class _FailAfterNaturalKeyRenameInterceptor extends QueryInterceptor {
  var _armed = false;
  var _renameSeen = false;
  var _writesAfterRename = 0;

  void arm() {
    _armed = true;
  }

  void _observeWrite(String statement) {
    if (!_armed) return;
    final normalized = statement.toLowerCase();
    if (!_renameSeen &&
        normalized.startsWith('update') &&
        normalized.contains('choreographers')) {
      _renameSeen = true;
      _writesAfterRename = 1;
      return;
    }
    if (_renameSeen && ++_writesAfterRename == 2) {
      throw StateError('injected post-rename write failure');
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _observeWrite(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _observeWrite(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _observeWrite(statement);
    return super.runDelete(executor, statement, args);
  }
}
