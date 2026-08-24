import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fake_adapter.dart';
import 'support/fmp_fixture_builder.dart';

String Function() sequentialIds() {
  var n = 0;
  return () => 'id-${++n}';
}

/// Builds a minimal but structurally real CC `.USR` byte image with two dances,
/// one set, and set items that reference dances by their CC `zk_Dance_ID` field
/// values (`4`, `7`) — plus a text-only break and an item pointing at a dance
/// id (`99`) that is not in the file. Mirrors the real CC schema
/// (record id ≠ `zk_*_ID`) so the importer's FK resolution is exercised
/// end-to-end.
Uint8List _ccUsrBytes() => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
    rows: [
      MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
      MapEntry(11, {1: '7', 2: 'Petronella', 3: 'Trad'}),
    ],
  ),
  FmpFixtureTable(
    index: 2,
    name: 'Set',
    columnNames: ['zk_Set_ID', 'Date', 'Location', 'Band', 'Caller', 'Notes'],
    rows: [
      MapEntry(20, {
        1: '1',
        2: '3/14/2020',
        3: 'Grange Hall',
        4: 'The Band',
        5: 'Jane',
        6: 'a good night',
      }),
    ],
  ),
  FmpFixtureTable(
    index: 3,
    name: 'SetItem',
    columnNames: [
      'zk_Set_ID',
      'zk_SetItem_ID',
      'zk_Dance_ID',
      'Order',
      'Time',
      'Break',
    ],
    rows: [
      MapEntry(30, {1: '1', 2: '101', 3: '4', 4: '1', 5: '8'}),
      MapEntry(31, {1: '1', 2: '102', 3: '7', 4: '2'}),
      MapEntry(32, {1: '1', 2: '103', 4: '3', 6: 'Waltz break'}),
      MapEntry(33, {1: '1', 2: '104', 3: '99', 4: '4'}),
    ],
  ),
]);

/// Same base fixture as [_ccUsrBytes], plus a `Dance_Related` table carrying
/// [relatedRows] (each a `(zk_Dance1_ID, zk_Dance2_ID)` pair) — for issue #688
/// related-dance import tests.
Uint8List _ccUsrBytesWithRelated(List<(String, String)> relatedRows) =>
    buildFmp12Fixture([
      FmpFixtureTable(
        index: 1,
        name: 'Dance',
        columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
        rows: [
          MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
          MapEntry(11, {1: '7', 2: 'Petronella', 3: 'Trad'}),
        ],
      ),
      FmpFixtureTable(
        index: 2,
        name: 'Set',
        columnNames: [
          'zk_Set_ID',
          'Date',
          'Location',
          'Band',
          'Caller',
          'Notes',
        ],
        rows: [
          MapEntry(20, {
            1: '1',
            2: '3/14/2020',
            3: 'Grange Hall',
            4: 'The Band',
            5: 'Jane',
            6: 'a good night',
          }),
        ],
      ),
      FmpFixtureTable(
        index: 3,
        name: 'SetItem',
        columnNames: [
          'zk_Set_ID',
          'zk_SetItem_ID',
          'zk_Dance_ID',
          'Order',
          'Time',
          'Break',
        ],
        rows: [
          MapEntry(30, {1: '1', 2: '101', 3: '4', 4: '1', 5: '8'}),
          MapEntry(31, {1: '1', 2: '102', 3: '7', 4: '2'}),
        ],
      ),
      FmpFixtureTable(
        index: 4,
        name: 'Dance_Related',
        columnNames: [
          'zk_DanceRelatedID',
          'zk_Dance1_ID',
          'zk_Dance2_ID',
          'zk_DanceRelatedID_PairID',
        ],
        rows: [
          for (var i = 0; i < relatedRows.length; i++)
            MapEntry(900 + i, {
              1: '${i + 1}',
              2: relatedRows[i].$1,
              3: relatedRows[i].$2,
              4: '${i + 1}',
            }),
        ],
      ),
    ]);

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late ProgramRepository programs;
  late VenueRepository venues;
  late ImportPipeline pipeline;
  late CallersCompanionUsrImporter importer;
  late String Function() nextId;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    programs = ProgramRepository(db);
    venues = VenueRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    importer = CallersCompanionUsrImporter(pipeline, programs, venues);
    nextId = sequentialIds();
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 15);

  Future<int> programExistenceStamp(String id) async {
    final rows = await db
        .customSelect(
          'SELECT existence_at AS v FROM programs WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.single.read<int>('v');
  }

  Future<Map<String, String>> danceIdByExternalId(ImportSession session) async {
    final map = <String, String>{};
    for (final id in session.insertedDanceIds) {
      final dance = await dances.getById(id);
      map[dance!.provenance!.externalId!] = id;
    }
    return map;
  }

  group('import (end-to-end from .USR bytes)', () {
    test('commits dances and persists FK-mapped programs', () async {
      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: nextId,
        newSlotId: sequentialIds(),
      );

      // Both dances committed via the real pipeline.
      expect(result.danceSession.committedCount, 2);
      expect(await dances.listAll(), hasLength(2));
      final byExternal = await danceIdByExternalId(result.danceSession);

      // Exactly one program, persisted (not just built).
      expect(result.programs, hasLength(1));
      final loaded = await programs.getById(result.programs.single.id);
      expect(loaded, isNotNull);
      expect(loaded!.title, 'Grange Hall');
      expect(loaded.eventDate, DateTime.utc(2020, 3, 14));
      expect(loaded.slots, hasLength(4));

      // Slots resolve to the *new* Compendium dance ids the commit minted.
      expect(loaded.slots[0].danceId, byExternal['4']);
      expect(loaded.slots[1].danceId, byExternal['7']);
      // Text-only break slot.
      expect(loaded.slots[2].danceId, isNull);
      expect(loaded.slots[2].text, 'Waltz break');
      // Reference to a dance absent from the file degrades to a placeholder.
      expect(loaded.slots[3].danceId, isNull);
      expect(loaded.slots[3].text, contains('99'));
      expect(
        result.programIssues.any(
          (i) => i.code == 'cc_program_unresolved_dance',
        ),
        isTrue,
      );
    });

    test('undo removes both the programs and the dances (symmetric)', () async {
      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );

      expect(await programs.listAll(), isNotEmpty);
      expect(await dances.listAll(), isNotEmpty);

      await importer.undo(result);

      expect(result.isUndone, isTrue);
      expect(
        await programs.listAll(includeDeleted: true),
        isEmpty,
        reason: 'imported programs are hard-deleted',
      );
      expect(
        await dances.listAll(includeDeleted: true),
        isEmpty,
        reason: 'imported dances are hard-deleted',
      );

      // Idempotent: a second undo is a no-op.
      await importer.undo(result);
      expect(await programs.listAll(includeDeleted: true), isEmpty);
    });
  });

  group('commit (FK map robustness)', () {
    test('a dance skipped mid-batch does not misalign the FK map', () async {
      // Three dances planned in order; the MIDDLE one (id '7') is skipped at
      // commit. A positional/index-aligned map would shift dance '13' into '7'
      // s slot and mis-resolve the program FKs — this asserts the map is keyed
      // by each committed record's own external id, so #1 and #3 stay correct.
      final adapter = FakeSourceAdapter([
        {'id': '4', 'title': 'Simplicity Swing'},
        {'id': '7', 'title': 'Petronella'},
        {'id': '13', 'title': 'Chorus Jig'},
      ]);
      final planned = await pipeline.plan(adapter, const ImportRequest());
      final committing = ImportBatchResult(
        records: [
          planned.records[0],
          ImportRecordPlan(
            draft: planned.records[1].draft,
            verdict: DedupeVerdict.ambiguous(const []),
          ),
          planned.records[2],
        ],
      );

      final archive = CcUsrArchive(
        dances: const [],
        sets: [
          CcSet(
            recordId: '1',
            location: 'Grange Hall',
            items: [
              CcSetItem(order: 1, danceRecordId: '4'),
              CcSetItem(order: 2, danceRecordId: '7'),
              CcSetItem(order: 3, danceRecordId: '13'),
            ],
          ),
        ],
        warnings: const [],
      );

      final result = await importer.commit(
        committing,
        archive,
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );

      // Only '4' and '13' committed; '7' was skipped.
      expect(result.danceSession.committedCount, 2);
      final byExternal = await danceIdByExternalId(result.danceSession);
      expect(byExternal.keys, containsAll(['4', '13']));
      expect(byExternal.containsKey('7'), isFalse);

      final program = result.programs.single;
      // #1 and #3 resolve to the correct new ids; the skipped middle degrades.
      expect(program.slots[0].danceId, byExternal['4']);
      expect(program.slots[1].danceId, isNull);
      expect(program.slots[1].text, contains('7'));
      expect(program.slots[2].danceId, byExternal['13']);
    });

    test('a dance skipped at commit is excluded from the map', () async {
      // Plan two dances through the real pipeline, then commit only the first —
      // the second is left ambiguous with no resolution, so it is skipped.
      final adapter = FakeSourceAdapter([
        {'id': '4', 'title': 'Simplicity Swing'},
        {'id': '7', 'title': 'Petronella'},
      ]);
      final planned = await pipeline.plan(adapter, const ImportRequest());
      final committing = ImportBatchResult(
        records: [
          planned.records[0],
          ImportRecordPlan(
            draft: planned.records[1].draft,
            verdict: DedupeVerdict.ambiguous(const []),
          ),
        ],
      );

      final archive = CcUsrArchive(
        dances: const [],
        sets: [
          CcSet(
            recordId: '1',
            location: 'Grange Hall',
            items: [
              CcSetItem(order: 1, danceRecordId: '4'),
              CcSetItem(order: 2, danceRecordId: '7'),
            ],
          ),
        ],
        warnings: const [],
      );

      final result = await importer.commit(
        committing,
        archive,
        now: now,
        venueEntityMode: false,
        newId: nextId,
      );

      // Only dance '4' was committed.
      expect(result.danceSession.committedCount, 1);
      final byExternal = await danceIdByExternalId(result.danceSession);
      expect(byExternal.keys, ['4']);

      final program = result.programs.single;
      // The committed dance resolves; the skipped one degrades to a placeholder.
      expect(program.slots[0].danceId, byExternal['4']);
      expect(program.slots[1].danceId, isNull);
      expect(program.slots[1].text, contains('7'));
      expect(
        result.programIssues.any(
          (i) => i.code == 'cc_program_unresolved_dance',
        ),
        isTrue,
      );

      // Undo still reverts the one dance and the program.
      await importer.undo(result);
      expect(await programs.listAll(includeDeleted: true), isEmpty);
      expect(await dances.listAll(includeDeleted: true), isEmpty);
    });
  });

  group('commit (compensating rollback)', () {
    test(
      'a program-persist failure reverts the already-committed dances',
      () async {
        final failing = _FailingProgramRepository(db);
        final rollbackImporter = CallersCompanionUsrImporter(
          pipeline,
          failing,
          venues,
        );

        await expectLater(
          rollbackImporter.import(
            _ccUsrBytes(),
            now: now,
            venueEntityMode: false,
            newId: nextId,
          ),
          throwsA(isA<StateError>()),
        );

        // The dances committed before the failure were rolled back, so the DB is
        // left clean (all-or-nothing).
        expect(await dances.listAll(includeDeleted: true), isEmpty);
        expect(await programs.listAll(includeDeleted: true), isEmpty);
      },
    );
  });

  group('program dedupe on re-import', () {
    test('re-importing the same .USR updates in place (no duplicate)', () async {
      final first = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      expect(first.programs, hasLength(1));
      expect(first.insertedProgramCount, 1);
      expect(first.updatedProgramCount, 0);
      final firstId = first.programs.single.id;

      // Re-import the identical archive with a *fresh* id minter — a naive
      // insert would mint a new program id and duplicate. Dedupe must reuse the
      // existing program keyed on (callersCompanion, zk_Set_ID).
      final second = await importer.import(
        _ccUsrBytes(),
        now: DateTime.utc(2026, 8, 1),
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      expect(second.insertedProgramCount, 0);
      expect(second.updatedProgramCount, 1);
      expect(second.programs.single.id, firstId, reason: 'same program reused');

      // Exactly one program in the DB, still carrying its provenance.
      final all = await programs.listAll();
      expect(all, hasLength(1));
      expect(all.single.id, firstId);
      expect(all.single.provenance!.externalId, '1');
      expect(all.single.provenance!.source, ProvenanceSource.callersCompanion);
      // Dances also deduped via the pipeline: still just the two.
      expect(await dances.listAll(), hasLength(2));
    });

    test('re-importing a deleted program restores existence ordering and undo '
        're-tombstones it', () async {
      final first = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: nextId,
        newSlotId: sequentialIds(),
      );
      final programId = first.programs.single.id;
      await programs.softDelete(
        programId,
        at: now.add(const Duration(days: 1)),
      );
      final tombstone = await programExistenceStamp(programId);

      final importedAt = now.add(const Duration(days: 2));
      final second = await importer.import(
        _ccUsrBytes(),
        now: importedAt,
        venueEntityMode: false,
        newId: nextId,
        newSlotId: sequentialIds(),
      );

      expect(second.restoredProgramIds, [programId]);
      final revived = await programs.getById(programId);
      expect(revived, isNotNull);
      expect(revived!.id, programId);
      final revivedStamp = await programExistenceStamp(programId);
      expect(revivedStamp, greaterThan(tombstone));

      await importer.undo(second);
      final undone = await programs.getById(programId, includeDeleted: true);
      expect(undone, isNotNull);
      expect(undone!.deletedAt, isNotNull);
      expect(
        await programExistenceStamp(programId),
        greaterThan(revivedStamp),
        reason: 'undo must create a later causal tombstone',
      );
    });

    test(
      're-import preserves a venueId linked after the first import',
      () async {
        final first = await importer.import(
          _ccUsrBytes(),
          now: now,
          venueEntityMode: false,
          newId: sequentialIds(),
          newSlotId: sequentialIds(),
        );
        final programId = first.programs.single.id;

        // Simulate a user linking the imported program to a venue entity (the
        // work PR B wires into the UI). `.USR` data can never supply this id.
        await venues.upsert(Venue(id: 'v1', name: 'Guiding Star Grange'));
        final imported = await programs.getById(programId);
        await programs.update(imported!.copyWith(venueId: 'v1'));

        // Re-import the identical archive: the provenance-matched rebuild must
        // carry the app-local venueId forward rather than overwriting it with
        // null (a silent link loss).
        final second = await importer.import(
          _ccUsrBytes(),
          now: DateTime.utc(2026, 8, 1),
          venueEntityMode: false,
          newId: sequentialIds(),
          newSlotId: sequentialIds(),
        );
        expect(second.updatedProgramCount, 1);

        final reloaded = await programs.getById(programId);
        expect(reloaded!.venueId, 'v1', reason: 'venueId survives re-import');
      },
    );

    test('undo after a re-import restores the prior program state', () async {
      await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      final before = (await programs.listAll()).single;

      final second = await importer.import(
        _ccUsrBytes(),
        now: DateTime.utc(2026, 8, 1),
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      expect(second.updatedProgramCount, 1);

      await importer.undo(second);
      expect(second.isUndone, isTrue);

      // The program is restored (not deleted) to its pre-re-import state.
      final restored = await programs.getById(before.id);
      expect(restored, isNotNull);
      expect(restored!.id, before.id);
      expect(restored.title, before.title);
      expect(restored.updatedAt, before.updatedAt);
      expect(restored.createdAt, before.createdAt);
      expect(restored.slots.length, before.slots.length);
      // Dances the re-import updated are rolled back too; still the two.
      expect(await dances.listAll(), hasLength(2));
    });

    test('a null-provenance user program is never matched', () async {
      // A user-created program with no provenance must never be overwritten by
      // a CC import, even if it shares a title/venue.
      await programs.create(
        Program(
          id: 'user-prog',
          title: 'Grange Hall',
          createdAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
        ),
      );

      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      // The CC program was inserted fresh; the user program is untouched.
      expect(result.insertedProgramCount, 1);
      expect(result.updatedProgramCount, 0);
      expect(await programs.listAll(), hasLength(2));
      final user = await programs.getById('user-prog');
      expect(user!.provenance, isNull);
      expect(user.updatedAt, DateTime.utc(2025));
    });
  });

  group('venue-entity linking (issue #687)', () {
    test('toggle off: no venue reads/writes, venueId stays null (today\'s '
        'behavior exactly)', () async {
      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      expect(result.insertedVenueIds, isEmpty);
      expect(result.insertedVenueCount, 0);
      final program = result.programs.single;
      expect(program.venueId, isNull);
      expect(program.venue, 'Grange Hall', reason: 'text venue unchanged');
      expect(await venues.listAll(), isEmpty, reason: 'no venue touched');
    });

    test(
      'mode on, no existing venues: mints a fresh venue and links it',
      () async {
        final result = await importer.import(
          _ccUsrBytes(),
          now: now,
          venueEntityMode: true,
          newId: sequentialIds(),
          newSlotId: sequentialIds(),
        );

        expect(result.insertedVenueIds, hasLength(1));
        expect(result.insertedVenueCount, 1);
        final program = result.programs.single;
        expect(program.venueId, result.insertedVenueIds.single);
        expect(program.venue, 'Grange Hall', reason: 'text kept as fallback');

        final minted = await venues.getById(result.insertedVenueIds.single);
        expect(minted!.name, 'Grange Hall');
      },
    );

    test('the ordinary bare-location .USR case never reads the venue '
        'repository (lazy fingerprint index: a name-only candidate is always '
        'weak-key, so the fingerprint index is never built/seeded)', () async {
      final countingVenues = _CountingVenueRepository(db);
      final spiedImporter = CallersCompanionUsrImporter(
        pipeline,
        programs,
        countingVenues,
      );

      final result = await spiedImporter.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      // A venue is still minted (the mint path itself only ever writes),
      // but resolving it must never have paid a listAll() read.
      expect(result.insertedVenueIds, hasLength(1));
      expect(
        countingVenues.listAllCallCount,
        0,
        reason:
            'a bare-name candidate is always weak-key; the fingerprint '
            'index must never be built/seeded for it',
      );
    });

    test('two sets sharing the same location within one import collapse to '
        'one minted venue', () async {
      final archive = CcUsrArchive(
        dances: const [],
        sets: [
          CcSet(
            recordId: '1',
            location: 'Grange Hall',
            items: [CcSetItem(order: 1, danceRecordId: '4')],
          ),
          CcSet(
            recordId: '2',
            location: '  GRANGE   Hall ',
            items: [CcSetItem(order: 1, danceRecordId: '7')],
          ),
        ],
        warnings: const [],
      );
      final adapter = FakeSourceAdapter([
        {'id': '4', 'title': 'Simplicity Swing'},
        {'id': '7', 'title': 'Petronella'},
      ]);
      final planned = await pipeline.plan(adapter, const ImportRequest());
      final result = await importer.commit(
        planned,
        archive,
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
      );

      expect(
        result.insertedVenueIds,
        hasLength(1),
        reason: 'same normalized location text collapses to one venue',
      );
      expect(result.programs, hasLength(2));
      final ids = result.programs.map((p) => p.venueId).toSet();
      expect(ids, {result.insertedVenueIds.single});
    });

    test('a unique fingerprint match links to the existing venue instead of '
        'minting (exercises the shared VenueFingerprintIndex branch — a bare '
        '.USR location alone can never produce a strong key, so this seeds a '
        'venue descriptive enough to match, matching the generic branch rather '
        'than a naturally-arising .USR scenario)', () async {
      // Seed an existing venue whose fingerprint (name + city) a location-
      // only candidate can't itself produce — this test exercises the
      // matchFor->link branch generically, wiring it in via a pre-seeded
      // index entry that shares venueFingerprint's normalized name.
      await venues.upsert(
        Venue(id: 'existing-venue', name: 'Grange Hall', city: 'Anytown'),
      );

      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      // A bare-text candidate has a null fingerprint (no city/address), so
      // matchFor can't fire from `.USR` data alone here; this asserts the
      // realistic .USR outcome (fresh mint, existing venue left alone) —
      // the matchFor->link branch itself is covered at the
      // VenueFingerprintIndex level in venue_dedupe_test.dart.
      expect(result.insertedVenueIds, hasLength(1));
      expect(await venues.listAll(), hasLength(2));
      final existing = await venues.getById('existing-venue');
      expect(existing!.name, 'Grange Hall');
    });

    test('two existing venues sharing a fingerprint (poisoned/ambiguous) are '
        'never guessed onto — a fresh venue is minted instead. The ambiguous- '
        'match branch itself (matchFor returning null + isAmbiguous true) is '
        'exercised generically in venue_dedupe_test.dart, since a bare .USR '
        'location can never itself produce a fingerprint strong enough to '
        'reach that branch (no city/address1); this test only asserts the '
        'realistic .USR-side consequence: neither existing venue is touched '
        'or overwritten', () async {
      // Two distinct venues that share a fingerprint (poisoning it) can
      // only arise from directly-seeded storage, not from `.USR` text
      // alone — construct that state at the repository level.
      await venues.upsert(Venue(id: 'a', name: 'Grange Hall', city: 'Anytown'));
      await venues.upsert(Venue(id: 'b', name: 'Grange Hall', city: 'Anytown'));

      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      // Bare `.USR` text alone can't reach the poisoned fingerprint (no
      // city/address on the candidate), so this asserts the realistic
      // .USR outcome: a third, fresh venue is minted, and neither existing
      // (poisoned) venue is touched.
      expect(result.insertedVenueIds, hasLength(1));
      expect(
        result.insertedVenueIds.single,
        isNot(anyOf('a', 'b')),
        reason: 'never guesses between the two poisoned candidates',
      );
      expect(await venues.listAll(), hasLength(3));
      expect((await venues.getById('a'))!.name, 'Grange Hall');
      expect((await venues.getById('b'))!.name, 'Grange Hall');
    });

    test('re-import of an already-linked program mints zero new venues and '
        'preserves the priorVenueId', () async {
      final first = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      expect(first.insertedVenueIds, hasLength(1));
      final programId = first.programs.single.id;
      final linkedVenueId = first.insertedVenueIds.single;

      // Re-import the identical archive with venue-entity mode still on: the
      // program already carries a venueId, so resolution must be skipped
      // entirely for it rather than minting an orphan venue nobody links to.
      final second = await importer.import(
        _ccUsrBytes(),
        now: DateTime.utc(2026, 8, 1),
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );

      expect(second.updatedProgramCount, 1);
      expect(
        second.insertedVenueIds,
        isEmpty,
        reason: 'no orphan venue minted on re-import',
      );
      expect(await venues.listAll(), hasLength(1));

      final reloaded = await programs.getById(programId);
      expect(reloaded!.venueId, linkedVenueId);
    });

    test('undo removes the venues minted by that import', () async {
      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      expect(result.insertedVenueIds, hasLength(1));

      await importer.undo(result);

      expect(await venues.listAll(), isEmpty);
      expect(await venues.getById(result.insertedVenueIds.single), isNull);
    });

    test('undo leaves a minted venue in place when a surviving program still '
        'links to it', () async {
      final result = await importer.import(
        _ccUsrBytes(),
        now: now,
        venueEntityMode: true,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      final mintedVenueId = result.insertedVenueIds.single;

      // A second, independently-created program also links to the same
      // minted venue (simulating another import/user action deduping onto
      // it after the fact).
      await programs.create(
        Program(
          id: 'other-prog',
          title: 'Other Dance',
          venueId: mintedVenueId,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await importer.undo(result);

      // The venue survives because 'other-prog' still references it; the
      // imported program itself is gone.
      expect(await venues.getById(mintedVenueId), isNotNull);
      expect(await programs.getById(result.programs.single.id), isNull);
    });
  });

  group('related-dance links (issue #688)', () {
    test('both endpoints imported: adds a directed relatedDance link on the '
        'source dance, targeting the other new Compendium dance id', () async {
      final result = await importer.import(
        _ccUsrBytesWithRelated([('4', '7')]),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
      );

      expect(result.relatedDanceLinkIssues, isEmpty);
      final byExternal = await danceIdByExternalId(result.danceSession);
      final source = await dances.getById(byExternal['4']!);
      final target = await dances.getById(byExternal['7']!);

      expect(source!.links, hasLength(1));
      final link = source.links.single;
      expect(link.kind, LinkKind.relatedDance);
      expect(link.targetDanceId, byExternal['7']);
      // Directional only: the target dance gets no reciprocal link.
      expect(target!.links, isEmpty);
    });

    test('a mirrored pair of rows in the archive yields two independent '
        'directed links (never synthesized by us)', () async {
      final result = await importer.import(
        _ccUsrBytesWithRelated([('4', '7'), ('7', '4')]),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
      );

      expect(result.relatedDanceLinkIssues, isEmpty);
      final byExternal = await danceIdByExternalId(result.danceSession);
      final dance4 = await dances.getById(byExternal['4']!);
      final dance7 = await dances.getById(byExternal['7']!);

      expect(dance4!.links.single.targetDanceId, byExternal['7']);
      expect(dance7!.links.single.targetDanceId, byExternal['4']);
    });

    test('a related row whose target dance was not imported is skipped with a '
        'non-fatal warning and creates NO dangling targetDanceId', () async {
      final result = await importer.import(
        _ccUsrBytesWithRelated([('4', '999')]), // '999' is not in the file
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
      );

      expect(result.relatedDanceLinkIssues, hasLength(1));
      expect(
        result.relatedDanceLinkIssues.single.code,
        'cc_related_dance_unresolved',
      );
      final byExternal = await danceIdByExternalId(result.danceSession);
      final source = await dances.getById(byExternal['4']!);
      expect(
        source!.links,
        isEmpty,
        reason: 'never a link with an unresolved/dangling targetDanceId',
      );
    });

    test('re-importing the same archive does not duplicate the link', () async {
      final bytes = _ccUsrBytesWithRelated([('4', '7')]);
      final first = await importer.import(
        bytes,
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
      );
      final byExternal = await danceIdByExternalId(first.danceSession);

      final second = await importer.import(
        bytes,
        now: DateTime.utc(2026, 8, 1),
        venueEntityMode: false,
        newId: sequentialIds(),
      );
      expect(second.relatedDanceLinkIssues, isEmpty);

      // Dances deduped via the pipeline (same provenance) — still the two
      // originals, same ids, and still exactly one relatedDance link.
      final source = await dances.getById(byExternal['4']!);
      expect(source!.links, hasLength(1));
      expect(source.links.single.targetDanceId, byExternal['7']);
    });

    test('undo removes the created link (freshly-inserted dances vanish '
        'entirely)', () async {
      final result = await importer.import(
        _ccUsrBytesWithRelated([('4', '7')]),
        now: now,
        venueEntityMode: false,
        newId: sequentialIds(),
      );

      await importer.undo(result);

      expect(await dances.listAll(includeDeleted: true), isEmpty);
    });

    test(
      'regression: a dance matched via a "link" resolution (not inserted, not '
      'field-updated by a straightforward reimport) still has its '
      'related-dance link fully reverted on undo, alongside every other '
      'field, because ImportPipeline.undo restores its full pre-commit '
      'snapshot',
      () async {
        // Seed a pre-existing dance whose title fuzzy-matches (but does not
        // exactly match) the incoming CC dance '4' — "The X" vs "X" is the
        // same near-miss shape `import_pipeline_test.dart` uses to force an
        // `ambiguous` verdict (never an automatic `reimport`, since this
        // dance carries no provenance at all).
        final priorLink = DanceLink(
          id: 'prior-source-link',
          kind: LinkKind.source,
          url: 'https://example.com/prior',
        );
        final existing = Dance(
          id: 'existing-dance',
          title: 'The Simplicity Swing',
          createdAt: DateTime.utc(2019),
          updatedAt: DateTime.utc(2019),
          links: [priorLink],
        );
        await dances.create(existing);

        final bytes = _ccUsrBytesWithRelated([('4', '7')]);
        final batch = await importer.plan(bytes);
        expect(
          batch.records[0].verdict.isAmbiguous,
          isTrue,
          reason:
              'the fuzzy near-match must be ambiguous, not auto-resolved, '
              'so the test actually exercises CommitAction.link',
        );

        final archive = readCcUsrArchive(bytes);
        final result = await importer.commit(
          batch,
          archive,
          now: now,
          venueEntityMode: false,
          newId: sequentialIds(),
          resolutions: {0: DedupeResolution.link('existing-dance')},
        );
        expect(
          result.danceSession.records[0].action,
          CommitAction.link,
          reason: 'sanity-check the resolution actually took the link path',
        );

        // The pipeline's `link`/`reimport` rebuild replaces dance CONTENT
        // wholesale from the incoming draft (a CC `.USR` draft never carries
        // links) — so the seeded prior link is gone the instant `commit`
        // rebuilds the dance, same as every other field (title, etc.);
        // that's pre-existing pipeline behavior, unrelated to #688. Our
        // related-dance-link step then appends its ONE new link on top of
        // that already-rebuilt (link-less) dance.
        final afterCommit = await dances.getById('existing-dance');
        expect(afterCommit!.links, hasLength(1));
        expect(afterCommit.links.single.kind, LinkKind.relatedDance);
        // The imported title overwrote the seeded one (link = update in
        // place) — the interesting bit for undo to prove it reverts.
        expect(afterCommit.title, 'Simplicity Swing');

        await importer.undo(result);
        expect(result.isUndone, isTrue);

        // Not hard-deleted — this dance pre-existed the import.
        final afterUndo = await dances.getById('existing-dance');
        expect(afterUndo, isNotNull);
        expect(
          afterUndo!.title,
          'The Simplicity Swing',
          reason: 'full prior snapshot restored, not just the links',
        );
        expect(
          afterUndo.links,
          [priorLink],
          reason:
              'the related-dance link this commit appended is gone; the '
              'pre-existing link is back — closing the "undo gap" '
              'concern raised during planning (which further code-reading '
              'showed does not actually exist: ImportPipeline.undo already '
              'captures/restores a full pre-commit Dance snapshot for '
              'link-matched dances, and DanceRepository fully replaces '
              '`dance_links` on every update).',
        );
      },
    );
  });
}

/// A [ProgramRepository] whose [create] always throws, to exercise the
/// importer's compensating rollback when program persistence fails after the
/// dances have already committed. [hardDelete] (used by the rollback) keeps its
/// real behavior.
class _FailingProgramRepository extends ProgramRepository {
  _FailingProgramRepository(super.db);

  @override
  Future<void> create(Program program, {LiveVenueIds? knownVenueIds}) async =>
      throw StateError('simulated program persist failure');
}

/// A [VenueRepository] that counts [listAll] calls, to assert the venue-
/// resolution path in [CallersCompanionUsrImporter.commit] never reads the
/// venue table when every candidate's fingerprint is weak/absent (the
/// ordinary `.USR` case — a bare `Location` string has only `name`, never a
/// city/address1) — a lazy-index-build regression should be caught here.
class _CountingVenueRepository extends VenueRepository {
  _CountingVenueRepository(super.db);

  int listAllCallCount = 0;

  @override
  Future<List<Venue>> listAll() {
    listAllCallCount++;
    return super.listAll();
  }
}
