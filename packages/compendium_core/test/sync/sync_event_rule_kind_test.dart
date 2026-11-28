import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/sync/sync_event_rule_body.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Event rules as Device Sync carries them (#2340): the `eventRule` record
/// kind, and a program's applied rule ids on the program's own record.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final created = DateTime.utc(2026, 9, 1, 12);
  final edited = DateTime.utc(2026, 9, 2, 12);
  final deleted = DateTime.utc(2026, 9, 3, 12);

  EventRule rule({
    String id = 'r1',
    String quantifier = 'atMost',
    String scope = 'wholeProgram',
    String? nickname = 'Few squares',
  }) => EventRule(
    id: id,
    savedSearchId: 'search-1',
    quantifierName: quantifier,
    count: 1,
    scopeName: scope,
    nickname: nickname,
    position: 4,
  );

  group('codec', () {
    test('a rule round-trips through blob, encoding and body', () {
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.eventRule,
        rule(),
        updatedAt: edited,
        existenceAt: created,
      )!;
      final decoded = decodeSyncRecordBlob(encodeSyncRecordBlob(blob));
      expect(decoded.kind, SyncRecordKind.eventRule);
      expect(encodeSyncRecordBlob(decoded), encodeSyncRecordBlob(blob));
      expect(
        decodeSyncRecordEntity(SyncRecordKind.eventRule, decoded.body),
        rule(),
      );
    });

    test('a nickname is sent only when the rule has one', () {
      expect(
        syncEventRuleBody(rule(nickname: null)).containsKey('nickname'),
        isFalse,
      );
      expect(
        decodeSyncEventRuleBody(
          syncEventRuleBody(rule(nickname: null)),
        ).nickname,
        isNull,
      );
    });

    test('a quantifier or scope a newer build wrote is kept as it came, and '
        'the rule is not readable', () {
      final back = decodeSyncEventRuleBody(
        syncEventRuleBody(rule(quantifier: 'exactly', scope: 'lastHour')),
      );
      expect((back.quantifierName, back.scopeName), ('exactly', 'lastHour'));
      expect(back.isReadable, isFalse);
    });

    test('refuses what could not be stored as it came', () {
      final full = syncEventRuleBody(rule());
      for (final bad in <Map<String, Object?>>[
        {'savedSearchId': ''},
        {'quantifier': null},
        {'count': -1},
        {'count': maxEventRuleCount + 1},
        {'count': '2'},
        {'scope': 7},
        {'nickname': ''},
        {'nickname': 'n' * (maxEventRuleNicknameLength + 1)},
        {'position': -1},
      ]) {
        expect(
          () => decodeSyncEventRuleBody({...full, ...bad}),
          throwsFormatException,
          reason: '$bad',
        );
      }
      for (final key in ['id', 'savedSearchId', 'quantifier', 'count']) {
        expect(
          () => decodeSyncEventRuleBody({...full}..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('a field a newer build adds to a rule is kept and put back '
        'exactly (sync-spec §6.7)', () {
      final body = syncEventRuleBody(rule())..['addedLater'] = 'x';
      final split = partitionInboundRecordBody(SyncRecordKind.eventRule, body);
      expect(split.refusedPath, isNull);
      expect(split.retained, isNotNull);
      expect(
        canonicalJson(mergeRetainedFields(split.known, split.retained!)),
        canonicalJson(body),
      );
    });

    // An older build (0.10.0 and earlier) does not know `eventRuleIds`, and
    // this build's allow-list is generated from its own registry, so it
    // cannot be told to forget the key. What an older build does with it is
    // what this build does with any top-level program key it does not know:
    // this stands in for it, with the same shape (a list of rule ids).
    test("an older build keeps a program's applied rule ids whole and puts "
        'them back exactly, as it keeps any top-level key it does not know '
        '(sync-spec §6.7)', () {
      final body = syncBodyForEntity(
        SyncRecordKind.program,
        Program(
          id: 'p1',
          title: 'Saturday',
          createdAt: created,
          updatedAt: edited,
        ),
      )..['eventRuleIdsFromALaterBuild'] = ['r1', 'r2'];
      final split = partitionInboundRecordBody(SyncRecordKind.program, body);
      expect(split.refusedPath, isNull);
      expect(split.retained?.keys, ['eventRuleIdsFromALaterBuild']);
      expect(split.known.containsKey('eventRuleIdsFromALaterBuild'), isFalse);
      expect(
        canonicalJson(mergeRetainedFields(split.known, split.retained!)),
        canonicalJson(body),
      );
    });

    test("a program's applied rule ids travel on the program's own record, "
        'as a part this build syncs', () {
      final body = syncBodyForEntity(
        SyncRecordKind.program,
        Program(
          id: 'p1',
          title: 'Saturday',
          eventRuleIds: const ['r1', 'r2'],
          createdAt: created,
          updatedAt: edited,
        ),
      );
      expect(body['eventRuleIds'], ['r1', 'r2']);
      final split = partitionInboundRecordBody(SyncRecordKind.program, body);
      expect(split.refusedPath, isNull);
      expect(split.known['eventRuleIds'], ['r1', 'r2']);
      final back =
          decodeSyncRecordEntity(SyncRecordKind.program, split.known)
              as Program;
      expect(back.eventRuleIds, ['r1', 'r2']);
      // A program with none sends no key, so its body (and wire hash) is
      // what an older build already sends.
      final none = syncBodyForEntity(
        SyncRecordKind.program,
        Program(
          id: 'p2',
          title: 'Plain',
          createdAt: created,
          updatedAt: edited,
        ),
      );
      expect(none.containsKey('eventRuleIds'), isFalse);
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

    test('a rule applies, and its deletion applies as a tombstone', () async {
      await storeSavedSearches(a.settings, ['search-1']);
      await a.eventRules.save(rule(), at: edited);
      const address = (kind: SyncRecordKind.eventRule, recordId: 'r1');
      final live = await held(a, address);
      await receive(live);
      expect(await b.eventRules.get('r1'), rule());
      expect((await held(b, address)).wireHash, live.wireHash);

      await a.eventRules.delete('r1', at: deleted);
      final tombstone = await held(a, address);
      expect(tombstone.blob.deletedAt, deleted);
      await receive(tombstone);
      expect(await b.eventRules.get('r1'), isNull);
      expect((await held(b, address)).wireHash, tombstone.wireHash);
    });

    test(
      "a conflict choice shows when this device last changed a rule",
      () async {
        // `SyncReviewResolver` labels this device's version with it.
        await storeSavedSearches(a.settings, ['search-1']);
        await a.eventRules.save(rule(), at: edited);
        const address = (kind: SyncRecordKind.eventRule, recordId: 'r1');
        expect(
          (await CompendiumSyncStorage(a).recordUpdatedAt(address))!.toUtc(),
          edited,
        );
        expect(
          await CompendiumSyncStorage(
            a,
          ).recordUpdatedAt((kind: SyncRecordKind.eventRule, recordId: 'none')),
          isNull,
        );
      },
    );

    test('a rule a newer build wrote arrives byte for byte', () async {
      await a.eventRules.writeFromSync(
        rule(quantifier: 'exactly', scope: 'lastHour'),
        at: edited,
      );
      const address = (kind: SyncRecordKind.eventRule, recordId: 'r1');
      final live = await held(a, address);
      await receive(live);
      final stored = (await b.eventRules.get('r1'))!;
      expect(
        (stored.quantifierName, stored.scopeName),
        ('exactly', 'lastHour'),
      );
      expect((await held(b, address)).wireHash, live.wireHash);
    });

    test("a program's applied rule ids apply with the program", () async {
      await a.programs.create(
        Program(
          id: 'p1',
          title: 'Saturday',
          eventRuleIds: const ['r1'],
          createdAt: created,
          updatedAt: edited,
        ),
      );
      const address = (kind: SyncRecordKind.program, recordId: 'p1');
      final live = await held(a, address);
      await receive(live);
      expect((await b.programs.getById('p1'))!.eventRuleIds, ['r1']);
      expect((await held(b, address)).wireHash, live.wireHash);
    });
  });
}
