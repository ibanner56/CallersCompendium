import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
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

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late ProgramRepository programs;
  late ImportPipeline pipeline;
  late CallersCompanionUsrImporter importer;
  late String Function() nextId;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    programs = ProgramRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    importer = CallersCompanionUsrImporter(pipeline, programs);
    nextId = sequentialIds();
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 15);

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
        final rollbackImporter = CallersCompanionUsrImporter(pipeline, failing);

        await expectLater(
          rollbackImporter.import(_ccUsrBytes(), now: now, newId: nextId),
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

    test('undo after a re-import restores the prior program state', () async {
      await importer.import(
        _ccUsrBytes(),
        now: now,
        newId: sequentialIds(),
        newSlotId: sequentialIds(),
      );
      final before = (await programs.listAll()).single;

      final second = await importer.import(
        _ccUsrBytes(),
        now: DateTime.utc(2026, 8, 1),
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
}

/// A [ProgramRepository] whose [create] always throws, to exercise the
/// importer's compensating rollback when program persistence fails after the
/// dances have already committed. [hardDelete] (used by the rollback) keeps its
/// real behavior.
class _FailingProgramRepository extends ProgramRepository {
  _FailingProgramRepository(super.db);

  @override
  Future<void> create(Program program) async =>
      throw StateError('simulated program persist failure');
}
