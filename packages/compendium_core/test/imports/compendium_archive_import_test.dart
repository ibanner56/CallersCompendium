import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

String Function() sequentialIds(String prefix) {
  var n = 0;
  return () => '$prefix-${++n}';
}

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// An archive carrying one program whose slots reference two dances present in
/// the bundle, a note-only slot, and a slot referencing a dance id that is NOT
/// in the bundle (so the importer's graceful degradation is exercised).
CompendiumArchive _bundle() {
  final d1 = _dance('orig-d1', 'Simplicity Swing');
  final d2 = _dance('orig-d2', 'Petronella');
  final program = Program(
    id: 'orig-p1',
    title: 'Spring Fling',
    venue: 'Grange Hall',
    band: 'The Fiddleheads',
    caller: 'Alice',
    notes: 'sound check at 6',
    status: ProgramStatus.performed,
    slots: [
      ProgramSlot(id: 'orig-sl1', position: 0, danceId: 'orig-d1'),
      ProgramSlot(id: 'orig-sl2', position: 1, text: 'Waltz break'),
      ProgramSlot(
        id: 'orig-sl3',
        position: 2,
        danceId: 'orig-d2',
        isAlt: true,
        guestCaller: 'Bob',
        plannedMinutes: 8,
      ),
      // References a dance that is not carried by the bundle.
      ProgramSlot(id: 'orig-sl4', position: 3, danceId: 'orig-missing'),
    ],
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 20),
  );
  return CompendiumArchive(
    exportedAt: DateTime.utc(2026, 7, 15),
    dances: [d1, d2],
    programs: [program],
  );
}

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late ProgramRepository programs;
  late ImportPipeline pipeline;
  late CompendiumArchiveImporter importer;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    programs = ProgramRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    importer = CompendiumArchiveImporter(pipeline, programs);
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 18);

  test('imports the program AND its referenced dances', () async {
    final archive = _bundle();
    final result = await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('new'),
      newSlotId: sequentialIds('slot'),
    );

    // Both bundled dances landed.
    final allDances = await dances.listAll();
    expect(
      allDances.map((d) => d.title),
      containsAll(<String>['Simplicity Swing', 'Petronella']),
    );

    // The program landed, once.
    final allPrograms = await programs.listAll();
    expect(allPrograms, hasLength(1));
    expect(result.insertedProgramCount, 1);
    expect(result.updatedProgramCount, 0);

    final program = allPrograms.single;
    expect(program.title, 'Spring Fling');
    expect(program.venue, 'Grange Hall');
    expect(program.band, 'The Fiddleheads');
    expect(program.caller, 'Alice');
    expect(program.status, ProgramStatus.performed);
    // Provenance keyed on the original program id, for dedupe on re-receive.
    expect(program.provenance?.source, ProvenanceSource.json);
    expect(program.provenance?.externalId, 'orig-p1');
  });

  test(
    'remaps slot dance references to the newly-committed dance ids',
    () async {
      final archive = _bundle();
      await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      final program = (await programs.listAll()).single;
      final byTitle = {for (final d in await dances.listAll()) d.title: d.id};

      // Slot 0 -> Simplicity Swing's NEW id (not the original 'orig-d1').
      expect(program.slots[0].danceId, byTitle['Simplicity Swing']);
      expect(program.slots[0].danceId, isNot('orig-d1'));
      // Slot 2 (alt) -> Petronella's NEW id, structured fields preserved.
      expect(program.slots[2].danceId, byTitle['Petronella']);
      expect(program.slots[2].isAlt, isTrue);
      expect(program.slots[2].guestCaller, 'Bob');
      expect(program.slots[2].plannedMinutes, 8);
    },
  );

  test('preserves slot order and note-only slots verbatim', () async {
    final archive = _bundle();
    await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('new'),
      newSlotId: sequentialIds('slot'),
    );

    final program = (await programs.listAll()).single;
    expect(program.slots, hasLength(4));
    expect(program.slots.map((s) => s.position), [0, 1, 2, 3]);
    // The note-only slot kept its text and carries no dance.
    expect(program.slots[1].danceId, isNull);
    expect(program.slots[1].text, 'Waltz break');
  });

  test('degrades an unresolved dance reference to a text placeholder', () async {
    final archive = _bundle();
    final result = await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('new'),
      newSlotId: sequentialIds('slot'),
    );

    final program = (await programs.listAll()).single;
    // Slot 3 referenced a dance not in the bundle -> kept as a placeholder note.
    expect(program.slots[3].danceId, isNull);
    expect(program.slots[3].text, contains('orig-missing'));
    expect(
      result.programIssues.any(
        (i) => i.code == 'archive_program_unresolved_dance',
      ),
      isTrue,
    );
  });

  test('re-importing the same bundle dedupes — no duplicates', () async {
    final archive = _bundle();
    await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('first'),
      newSlotId: sequentialIds('firstslot'),
    );

    final result2 = await importer.import(
      encodeArchive(archive),
      archive,
      now: now.add(const Duration(days: 1)),
      newId: sequentialIds('second'),
      newSlotId: sequentialIds('secondslot'),
    );

    // Still one program and two dances after the second import.
    expect(await programs.listAll(), hasLength(1));
    final titles = (await dances.listAll()).map((d) => d.title).toList();
    expect(titles.where((t) => t == 'Simplicity Swing'), hasLength(1));
    expect(titles.where((t) => t == 'Petronella'), hasLength(1));
    // The program was updated in place, not inserted again.
    expect(result2.updatedProgramCount, 1);
    expect(result2.insertedProgramCount, 0);
  });

  test('undo reverts the imported program and dances', () async {
    final archive = _bundle();
    final result = await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('new'),
      newSlotId: sequentialIds('slot'),
    );

    expect(await programs.listAll(), hasLength(1));
    await importer.undo(result);

    expect(await programs.listAll(), isEmpty);
    expect(await dances.listAll(), isEmpty);
    // Idempotent.
    await importer.undo(result);
    expect(await programs.listAll(), isEmpty);
  });
}
