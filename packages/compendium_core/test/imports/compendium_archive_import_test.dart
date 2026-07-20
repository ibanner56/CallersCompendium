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

/// A dance carrying choreography content (and optional authors), for the
/// content/author confidence tests below.
Dance _danceWith(
  String id,
  String title, {
  List<Figure> figures = const [],
  List<String> authorIds = const [],
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  figures: figures,
  provenance: provenance,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Figure _fig(String move, {int beats = 8}) =>
    Figure(move: move, params: {'beats': beats});

/// A one-slot program referencing [danceId], for the confidence tests.
Program _programRef(String danceId) => Program(
  id: 'orig-p1',
  title: 'Spring Fling',
  status: ProgramStatus.draft,
  slots: [ProgramSlot(id: 'orig-sl1', position: 0, danceId: danceId)],
  createdAt: DateTime.utc(2026, 4, 1),
  updatedAt: DateTime.utc(2026, 4, 1),
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

  test(
    'a crafted archive with duplicate program ids collapses to one program',
    () async {
      // Untrusted input: two programs sharing the same id (=> same provenance
      // externalId) within a single bundle must not insert twice.
      final d1 = _dance('orig-d1', 'Simplicity Swing');
      Program dup(String title) => Program(
        id: 'orig-dup',
        title: title,
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 'sl-$title', position: 0, danceId: 'orig-d1')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [d1],
        programs: [dup('First'), dup('Second')],
      );

      final result = await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      // Exactly one program persisted, carrying the last-seen state.
      final all = await programs.listAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Second');
      expect(result.programs, hasLength(1));
      expect(result.insertedProgramCount, 1);
      expect(result.updatedProgramCount, 0);

      // Undo removes it cleanly (the second occurrence was an in-commit update
      // of our own insert, so no bogus prior state was captured).
      await importer.undo(result);
      expect(await programs.listAll(), isEmpty);
    },
  );

  test('undo restores the true pre-import state when a re-import repeats an '
      'existing externalId', () async {
    // First import establishes a program in the DB (externalId "orig-dup").
    final d1 = _dance('orig-d1', 'Simplicity Swing');
    Program variant(String title) => Program(
      id: 'orig-dup',
      title: title,
      notes: title == 'Original' ? 'keep me' : 'edited notes',
      status: ProgramStatus.draft,
      slots: [ProgramSlot(id: 'sl-$title', position: 0, danceId: 'orig-d1')],
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    final first = CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 15),
      dances: [d1],
      programs: [variant('Original')],
    );
    await importer.import(
      encodeArchive(first),
      first,
      now: now,
      newId: sequentialIds('first'),
      newSlotId: sequentialIds('firstslot'),
    );
    final preImport = (await programs.listAll()).single;
    expect(preImport.title, 'Original');
    expect(preImport.notes, 'keep me');

    // Re-import: an (untrusted) archive that repeats the SAME externalId twice
    // against the pre-existing program.
    final second = CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 16),
      dances: [d1],
      programs: [variant('Edited A'), variant('Edited B')],
    );
    final result2 = await importer.import(
      encodeArchive(second),
      second,
      now: now.add(const Duration(days: 1)),
      newId: sequentialIds('second'),
      newSlotId: sequentialIds('secondslot'),
    );

    // One program, updated in place; the prior state was captured exactly once
    // (a single existing id, despite the duplicate in the bundle).
    expect(await programs.listAll(), hasLength(1));
    expect(result2.insertedProgramCount, 0);
    expect(result2.updatedProgramCount, 1);

    // Undo restores the TRUE pre-import state, not the intermediate "Edited A".
    await importer.undo(result2);
    final restored = (await programs.listAll()).single;
    expect(restored.id, preImport.id);
    expect(restored.title, 'Original');
    expect(restored.notes, 'keep me');
  });

  test('unresolved dance placeholder preserves any existing note', () async {
    final program = Program(
      id: 'orig-p1',
      title: 'Spring Fling',
      status: ProgramStatus.draft,
      slots: [
        ProgramSlot(
          id: 'orig-sl1',
          position: 0,
          danceId: 'orig-missing',
          text: 'Caller intro',
        ),
      ],
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    final archive = CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 15),
      dances: const [],
      programs: [program],
    );

    await importer.import(
      encodeArchive(archive),
      archive,
      now: now,
      newId: sequentialIds('new'),
      newSlotId: sequentialIds('slot'),
    );

    final slot = (await programs.listAll()).single.slots.single;
    expect(slot.danceId, isNull);
    // Original note kept AND the failed reference surfaced.
    expect(slot.text, contains('Caller intro'));
    expect(slot.text, contains('orig-missing'));
  });

  group('ambiguous share-receive dances resolve instead of skipping', () {
    test(
      'links each ambiguous dance to the receiver\'s identical existing copy — '
      'no duplicate, every slot resolves',
      () async {
        // The receiver already holds independent copies (different ids, NO
        // shared externalId) with IDENTICAL content to the bundle's dances.
        final figs1 = [
          _fig('balance_and_swing', beats: 16),
          _fig('circle_left'),
        ];
        final figs2 = [_fig('petronella_turn'), _fig('balance_and_swing')];
        await dances.create(
          _danceWith('recv-d1', 'Simplicity Swing', figures: figs1),
        );
        await dances.create(
          _danceWith('recv-d2', 'Petronella', figures: figs2),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [
            _danceWith('orig-d1', 'Simplicity Swing', figures: figs1),
            _danceWith('orig-d2', 'Petronella', figures: figs2),
          ],
          programs: [
            Program(
              id: 'orig-p1',
              title: 'Spring Fling',
              status: ProgramStatus.draft,
              slots: [
                ProgramSlot(id: 'orig-sl1', position: 0, danceId: 'orig-d1'),
                ProgramSlot(id: 'orig-sl2', position: 1, danceId: 'orig-d2'),
              ],
              createdAt: DateTime.utc(2026, 4, 1),
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        );

        final result = await importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

        // No new duplicates: still exactly the two existing copies.
        final all = await dances.listAll();
        expect(all, hasLength(2));
        expect(all.where((d) => d.title == 'Simplicity Swing'), hasLength(1));
        expect(all.where((d) => d.title == 'Petronella'), hasLength(1));

        // Both slots resolve to the EXISTING (linked) dance ids.
        final program = (await programs.listAll()).single;
        expect(program.slots[0].danceId, 'recv-d1');
        expect(program.slots[1].danceId, 'recv-d2');
        expect(program.slots.every((s) => s.danceId != null), isTrue);

        // No "Dance not imported" placeholders/issues.
        expect(
          result.programIssues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test(
      'imports a same-title but different-content dance as a duplicate — never '
      'mis-linked to the different existing dance',
      () async {
        await dances.create(
          _danceWith(
            'recv-x',
            'Simplicity Swing',
            figures: [_fig('circle_left'), _fig('do_si_do')],
          ),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [
            _danceWith(
              'orig-d1',
              'Simplicity Swing',
              figures: [_fig('balance_and_swing', beats: 16)],
            ),
          ],
          programs: [_programRef('orig-d1')],
        );

        final result = await importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

        // Two dances now share the title: the existing one + the new import.
        final all = await dances.listAll();
        expect(all.where((d) => d.title == 'Simplicity Swing'), hasLength(2));

        // The slot resolves to the NEWLY imported dance, not the different
        // existing one — and is a real dance reference, not a placeholder note.
        final slot = (await programs.listAll()).single.slots.single;
        expect(slot.danceId, isNotNull);
        expect(slot.danceId, isNot('recv-x'));
        expect(slot.text, isNull);
        expect(
          result.programIssues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test(
      'links on matching normalized title + author-set even when content differs',
      () async {
        await choreographers.upsert(Choreographer(id: 'alice', name: 'Alice'));
        await dances.create(
          _danceWith(
            'recv-d1',
            'Simplicity Swing',
            authorIds: ['alice'],
            figures: [_fig('circle_left')],
          ),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'alice', name: 'Alice')],
          dances: [
            _danceWith(
              'orig-d1',
              'Simplicity Swing',
              authorIds: ['alice'],
              figures: [_fig('do_si_do')],
            ),
          ],
          programs: [_programRef('orig-d1')],
        );

        final result = await importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

        // Linked onto the existing dance despite the differing figures.
        final all = await dances.listAll();
        expect(all.where((d) => d.title == 'Simplicity Swing'), hasLength(1));
        expect(
          (await programs.listAll()).single.slots.single.danceId,
          'recv-d1',
        );
        expect(
          result.programIssues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test(
      'a same-title dance with a DIFFERENT author and content is duplicated, '
      'not mis-linked',
      () async {
        await choreographers.upsert(Choreographer(id: 'alice', name: 'Alice'));
        // 'bob' exists on the receiver so the new duplicate\'s author FK holds.
        await choreographers.upsert(Choreographer(id: 'bob', name: 'Bob'));
        await dances.create(
          _danceWith(
            'recv-d1',
            'Simplicity Swing',
            authorIds: ['alice'],
            figures: [_fig('circle_left')],
          ),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          choreographers: [Choreographer(id: 'bob', name: 'Bob')],
          dances: [
            _danceWith(
              'orig-d1',
              'Simplicity Swing',
              authorIds: ['bob'],
              figures: [_fig('do_si_do')],
            ),
          ],
          programs: [_programRef('orig-d1')],
        );

        final result = await importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

        // A distinct dance sharing only the title -> duplicated, not linked.
        final all = await dances.listAll();
        expect(all.where((d) => d.title == 'Simplicity Swing'), hasLength(2));
        final slot = (await programs.listAll()).single.slots.single;
        expect(slot.danceId, isNotNull);
        expect(slot.danceId, isNot('recv-d1'));
        expect(
          result.programIssues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test(
      'an exact (source, externalId) match still reimports in place — untouched '
      'by auto-resolution',
      () async {
        // A dance previously received from a bundle carries (json, <origId>)
        // provenance; re-receiving it is an exact reimport, not an ambiguity.
        await dances.create(
          _danceWith(
            'recv-1',
            'Petronella',
            provenance: Provenance(
              source: ProvenanceSource.json,
              externalId: 'orig-d1',
              importedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [_danceWith('orig-d1', 'Petronella')],
          programs: [_programRef('orig-d1')],
        );

        final result = await importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

        // Reimported onto the existing dance; no duplicate; slot resolves to it.
        expect((await dances.listAll()), hasLength(1));
        expect(
          (await programs.listAll()).single.slots.single.danceId,
          'recv-1',
        );
        expect(
          result.programIssues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test('a genuinely missing dance (not in the bundle) still degrades to a '
        'placeholder + issue', () async {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: const [],
        programs: [_programRef('orig-absent')],
      );

      final result = await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      final slot = (await programs.listAll()).single.slots.single;
      expect(slot.danceId, isNull);
      expect(slot.text, contains('orig-absent'));
      expect(
        result.programIssues.any(
          (i) => i.code == 'archive_program_unresolved_dance',
        ),
        isTrue,
      );
    });
  });
}
