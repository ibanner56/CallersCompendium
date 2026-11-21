import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/sync/sync_glossary_body.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// The user's glossary as Device Sync carries it (#709): the `glossaryEntry`
/// and `figureNote` record kinds.
void main() {
  // Two devices, each with its own in-memory database.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final created = DateTime.utc(2026, 9, 1, 12);
  final edited = DateTime.utc(2026, 9, 2, 12);
  final deleted = DateTime.utc(2026, 9, 3, 12);

  StoredUserGlossaryEntry storedEntry({
    String id = 'entry-1',
    String kind = 'compound',
    String? payloadJson = '{"params":[],"figures":[],"bindings":[]}',
  }) => StoredUserGlossaryEntry(
    id: id,
    kind: kind,
    name: 'role1s chain',
    definition: 'A chain for role1s.',
    description: 'All the way round.',
    keywords: const ['chain', 'grand'],
    notes: 'Mind the hands.',
    payloadJson: payloadJson,
    createdAt: created,
  );

  UserGlossaryEntry entry({String id = 'entry-1', DateTime? createdAt}) =>
      UserGlossaryEntry(
        id: id,
        kindName: 'compound',
        name: 'role1s chain',
        definition: 'A chain for role1s.',
        description: 'All the way round.',
        keywords: const ['chain'],
        notes: 'Mind the hands.',
        payload: const {
          'params': <Object?>[],
          'figures': <Object?>[],
          'bindings': <Object?>[],
        },
        createdAt: createdAt ?? created,
      );

  group('codec', () {
    test('a glossary entry round-trips through blob, encoding and body', () {
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.glossaryEntry,
        storedEntry(),
        updatedAt: edited,
        existenceAt: created,
      )!;
      final decoded = decodeSyncRecordBlob(encodeSyncRecordBlob(blob));
      expect(decoded.kind, SyncRecordKind.glossaryEntry);
      expect(encodeSyncRecordBlob(decoded), encodeSyncRecordBlob(blob));
      final back =
          decodeSyncRecordEntity(SyncRecordKind.glossaryEntry, decoded.body)
              as StoredUserGlossaryEntry;
      expect(syncGlossaryEntryBody(back), blob.body);
      expect(back.createdAt, created);
      expect(blob.body['payload'], isA<String>(), reason: 'carried as text');
    });

    test('a figure note round-trips, under the shipped figure\'s id', () {
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.figureNote,
        const FigureNote(figureId: 'swing', notes: 'Smooth.'),
        updatedAt: edited,
        existenceAt: created,
      )!;
      expect(blob.id, 'swing');
      final decoded = decodeSyncRecordBlob(encodeSyncRecordBlob(blob));
      expect(encodeSyncRecordBlob(decoded), encodeSyncRecordBlob(blob));
      final back =
          decodeSyncRecordEntity(SyncRecordKind.figureNote, decoded.body)
              as FigureNote;
      expect((back.figureId, back.notes), ('swing', 'Smooth.'));
    });

    test('a manifest naming both kinds decodes strictly; an unknown kind is '
        'still refused unless a peer manifest is read tolerantly', () {
      final manifest = SyncManifest(
        deviceId: 'd',
        epoch: 'e',
        writtenAt: created,
        records: {
          SyncRecordKind.glossaryEntry: {'entry-1': 'a' * 64},
          SyncRecordKind.figureNote: {'swing': 'b' * 64},
        },
      );
      final back = decodeSyncManifest(encodeSyncManifest(manifest));
      expect(back.records, manifest.records);
      final future = encodeSyncManifest(
        manifest,
      ).replaceFirst('"figureNote"', '"futureKind"');
      expect(() => decodeSyncManifest(future), throwsFormatException);
      expect(decodeSyncManifest(future, skipUnknownKinds: true).unknownKinds, {
        'futureKind',
      });
    });

    test('an unknown kind and a payload that does not decode are accepted '
        'as they are', () {
      final body = syncGlossaryEntryBody(
        storedEntry(kind: 'fromTheFuture', payloadJson: '{not json'),
      );
      final back = decodeSyncGlossaryEntryBody(body);
      expect(back.kind, 'fromTheFuture');
      expect(back.payloadJson, '{not json');
    });

    test('a description is optional on the wire: empty decodes, text over the '
        'bound does not', () {
      final body = syncGlossaryEntryBody(storedEntry());
      expect(
        decodeSyncGlossaryEntryBody({...body, 'description': ''}).description,
        isEmpty,
      );
      expect(
        () => decodeSyncGlossaryEntryBody({
          ...body,
          'description': 'd' * (maxUserGlossaryTextLength + 1),
        }),
        throwsFormatException,
      );
    });

    test('refuses what could not be stored as it came', () {
      Map<String, Object?> body([Map<String, Object?> change = const {}]) => {
        ...syncGlossaryEntryBody(storedEntry()),
        ...change,
      };
      for (final bad in <Map<String, Object?>>[
        {'name': ''},
        {'kind': null},
        {'keywords': 'chain'},
        {'payload': 42},
        // JSON, but not as storage writes it: storing it would change the
        // record under its peer's wire hash.
        {'payload': '{"params": []}'},
        {'createdAt': '2026-09-01T12:00:00.500Z'},
        {'createdAt': '2026-09-01T12:00:00'},
      ]) {
        expect(
          () => decodeSyncGlossaryEntryBody(body(bad)),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        () => decodeSyncFigureNoteBody(const {'id': 'swing', 'notes': ''}),
        throwsFormatException,
      );
    });

    test('accepts a creation time only as the encoder spells it, so a body '
        'it accepts encodes back to the same bytes', () {
      Map<String, Object?> at(String createdAt) => {
        ...syncGlossaryEntryBody(storedEntry()),
        'createdAt': createdAt,
      };
      expect(
        decodeSyncGlossaryEntryBody(at('2026-09-01T12:00:00.000Z')).createdAt,
        created,
      );
      for (final spelling in [
        '2026-09-01T12:00:00Z',
        '2026-09-01 12:00:00Z',
        '2026-09-01 12:00:00.000Z',
        '20260901T120000Z',
        '+002026-09-01T12:00:00.000Z',
        '2026-09-01T12:00:00.000000Z',
        '2026-09-01T12:00:00.000+00:00',
      ]) {
        expect(
          () => decodeSyncGlossaryEntryBody(at(spelling)),
          throwsFormatException,
          reason: spelling,
        );
      }
    });

    test('every key must be present, null or not', () {
      final full = syncGlossaryEntryBody(storedEntry());
      for (final key in full.keys) {
        expect(
          () => decodeSyncGlossaryEntryBody({...full}..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => decodeSyncFigureNoteBody(const {'id': 'swing'}),
        throwsFormatException,
      );
    });

    test('a payload JSON can spell but not hold is refused as malformed', () {
      expect(
        () => decodeSyncGlossaryEntryBody({
          ...syncGlossaryEntryBody(storedEntry()),
          'payload': '[1e400]',
        }),
        throwsFormatException,
      );
    });
  });

  group('apply through the real storage', () {
    late CompendiumRepositories a;
    late CompendiumRepositories b;
    setUp(() {
      a = CompendiumRepositories(openTestDatabase(), contraTaxonomy);
      b = CompendiumRepositories(openTestDatabase(), contraTaxonomy);
    });
    tearDown(() async {
      await a.db.close();
      await b.db.close();
    });

    Future<SyncMergeCandidate> held(
      CompendiumRepositories repos,
      SyncRecordAddress address,
    ) async => (await CompendiumSyncStorage(repos).snapshot()).local[address]!;

    Future<void> receive(SyncMergeCandidate candidate) async {
      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: candidate.blob)],
        storage: CompendiumSyncStorage(b),
      );
      expect(result.reports, isEmpty);
      expect(result.applied, [candidate.address]);
    }

    test('a glossary entry applies, and its deletion applies as a '
        'tombstone', () async {
      const address = (kind: SyncRecordKind.glossaryEntry, recordId: 'e1');
      await a.userGlossary.upsert(entry(id: 'e1'), at: edited);
      final live = await held(a, address);
      await receive(live);

      final applied = (await b.userGlossary.getById('e1'))!;
      expect(applied.name, 'role1s chain');
      expect(applied.createdAt, created);
      expect(applied.payload, {
        'params': <Object?>[],
        'figures': <Object?>[],
        'bindings': <Object?>[],
      });
      expect(
        (await held(b, address)).wireHash,
        live.wireHash,
        reason: 'the receiver publishes exactly what it received',
      );

      await a.userGlossary.delete('e1', at: deleted);
      final tombstone = await held(a, address);
      expect(tombstone.blob.deletedAt, deleted);
      await receive(tombstone);
      expect(await b.userGlossary.getById('e1'), isNull);
      final row = await (b.db.select(
        b.db.userGlossaryEntries,
      )..where((t) => t.id.equals('e1'))).getSingle();
      expect(row.deletedAt!.toUtc(), deleted);
      expect((await held(b, address)).wireHash, tombstone.wireHash);
    });

    test('a figure note applies, and its deletion applies as a '
        'tombstone', () async {
      const address = (kind: SyncRecordKind.figureNote, recordId: 'swing');
      await a.figureNotes.set('swing', 'role1s lead.', at: edited);
      final live = await held(a, address);
      await receive(live);
      expect((await b.figureNotes.get('swing'))!.notes, 'role1s lead.');
      expect((await held(b, address)).wireHash, live.wireHash);

      await a.figureNotes.delete('swing', at: deleted);
      final tombstone = await held(a, address);
      await receive(tombstone);
      expect(await b.figureNotes.get('swing'), isNull);
      expect(
        (await b.figureNotes.listAll(includeDeleted: true)).single.figureId,
        'swing',
      );
      expect((await held(b, address)).wireHash, tombstone.wireHash);
    });

    test('an entry of an unknown kind, or whose payload does not decode, '
        'arrives byte for byte', () async {
      await a.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'future',
          kindName: 'fromTheFuture',
          name: 'Spiral',
          definition: 'Something newer.',
          description: 'Made by a newer build.',
          payload: const {'z': 1, 'a': 2},
          createdAt: created,
        ),
        at: edited,
      );
      await a.userGlossary.upsert(entry(id: 'broken'), at: edited);
      await a.db.customStatement(
        "UPDATE user_glossary_entries SET payload_json = '{not json' "
        "WHERE id = 'broken'",
      );

      for (final id in ['future', 'broken']) {
        await receive(
          await held(a, (kind: SyncRecordKind.glossaryEntry, recordId: id)),
        );
      }

      Future<List<Map<String, Object?>>> rows(
        CompendiumRepositories r,
      ) async => [
        for (final row
            in await r.db
                .customSelect('SELECT * FROM user_glossary_entries ORDER BY id')
                .get())
          row.data,
      ];
      expect(await rows(b), await rows(a));
      expect((await rows(b)).map((r) => r['payload_json']), [
        '{not json',
        '{"z":1,"a":2}',
      ], reason: 'neither repaired nor re-sorted on the way');
      final read = (await b.userGlossary.getById('future'))!;
      expect(read.kind, isNull, reason: 'kept, shown as a newer version');
    });

    test('created_at travels unchanged, however much later the entry was '
        'edited', () async {
      const address = (kind: SyncRecordKind.glossaryEntry, recordId: 'e1');
      await a.userGlossary.upsert(entry(id: 'e1'), at: created);
      await a.userGlossary.upsert(
        entry(id: 'e1').copyWith(definition: 'Edited.'),
        at: deleted,
      );
      await receive(await held(a, address));
      final row = await (b.db.select(
        b.db.userGlossaryEntries,
      )..where((t) => t.id.equals('e1'))).getSingle();
      expect(row.createdAt.toUtc(), created);
      expect(row.updatedAt!.toUtc(), deleted);
    });
  });

  group('a tie that differs goes to review (sync-spec §6.3)', () {
    SyncMergeDecision decide(SyncRecordBlob mine, SyncRecordBlob theirs) =>
        const SyncMergeEngine()
            .plan(
              local: {
                (kind: mine.kind, recordId: mine.id):
                    SyncMergeCandidate.fromBlob(mine),
              },
              baseline: const {},
              peers: [
                {
                  (kind: theirs.kind, recordId: theirs.id):
                      SyncMergeCandidate.fromBlob(theirs, peerId: 'peer'),
                },
              ],
            )
            .decisions
            .single;
    SyncRecordBlob blob(SyncRecordKind kind, Object entity) =>
        syncRecordBlobForEntity(
          kind,
          entity,
          updatedAt: edited,
          existenceAt: created,
        )!;

    test('a glossary entry differing in its figures', () {
      final mine = blob(SyncRecordKind.glossaryEntry, storedEntry());
      final theirs = blob(
        SyncRecordKind.glossaryEntry,
        storedEntry(payloadJson: '{"params":[],"figures":[1],"bindings":[]}'),
      );
      expect(decide(mine, theirs).action, SyncMergeAction.review);
      expect(decide(theirs, mine).action, SyncMergeAction.review);
    });

    test('a figure note differing in its text', () {
      final mine = blob(
        SyncRecordKind.figureNote,
        const FigureNote(figureId: 'swing', notes: 'Mine.'),
      );
      final theirs = blob(
        SyncRecordKind.figureNote,
        const FigureNote(figureId: 'swing', notes: 'Theirs.'),
      );
      expect(decide(mine, theirs).action, SyncMergeAction.review);
    });
  });
}
