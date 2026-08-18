import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
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

Figure _fig(String move, {int beats = 8}) => invalidTestFigure(
  move: move,
  params: {'beats': beats},
  reason:
      'archive fixtures carry move ids straight from untrusted import content, including unknown ones',
);

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
  late VenueRepository venues;
  late ImportPipeline pipeline;
  late CompendiumArchiveImporter importer;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    programs = ProgramRepository(db);
    venues = VenueRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    importer = CompendiumArchiveImporter(pipeline, programs, venues);
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
        // ignore: unused_result
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
        // ignore: unused_result
        await choreographers.upsert(Choreographer(id: 'alice', name: 'Alice'));
        // 'bob' exists on the receiver so the new duplicate\'s author FK holds.
        // ignore: unused_result
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

  group('venue wiring (community import path)', () {
    CompendiumArchive bundleWithVenue({
      String? programVenueId,
      List<Venue> venues = const [],
    }) {
      final d1 = _dance('orig-d1', 'Simplicity Swing');
      final program = Program(
        id: 'orig-p1',
        title: 'Spring Fling',
        venueId: programVenueId,
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 'orig-sl1', position: 0, danceId: 'orig-d1')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      return CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [d1],
        programs: [program],
        venues: venues,
      );
    }

    Future<CompendiumArchiveImportResult> run(CompendiumArchive archive) =>
        importer.import(
          encodeArchive(archive),
          archive,
          now: now,
          newId: sequentialIds('new'),
          newSlotId: sequentialIds('slot'),
        );

    test('persists bundled venues and remaps the program venueId', () async {
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(id: 'orig-v1', name: 'Guiding Star Grange', city: 'Greenfield'),
          Venue(id: 'orig-v2', name: 'Town Hall'),
        ],
      );
      final result = await run(archive);

      final allVenues = await venues.listAll();
      expect(
        allVenues.map((v) => v.name),
        containsAll(<String>['Guiding Star Grange', 'Town Hall']),
      );
      expect(result.insertedVenueCount, 2);

      final program = (await programs.listAll()).single;
      // The link is remapped to the newly-inserted venue, never the untrusted
      // bundle id (which could otherwise clobber an existing venue).
      expect(program.venueId, isNotNull);
      expect(program.venueId, isNot('orig-v1'));
      final linked = await venues.getById(program.venueId!);
      expect(linked, isNotNull);
      expect(linked!.name, 'Guiding Star Grange');
      expect(linked.city, 'Greenfield');
    });

    test(
      'does not overwrite an existing venue that shares the bundle id',
      () async {
        // A venue the receiver already holds under the same id the (untrusted)
        // bundle reuses must survive untouched — the import inserts a fresh copy.
        await venues.upsert(
          Venue(id: 'orig-v1', name: 'Receiver Hall', city: 'Local'),
        );
        final archive = bundleWithVenue(
          programVenueId: 'orig-v1',
          venues: [Venue(id: 'orig-v1', name: 'Bundle Grange')],
        );
        await run(archive);

        final existing = await venues.getById('orig-v1');
        expect(existing?.name, 'Receiver Hall');
        // A distinct new venue was inserted for the bundle's record.
        expect(
          (await venues.listAll()).map((v) => v.name),
          containsAll(<String>['Receiver Hall', 'Bundle Grange']),
        );
      },
    );

    test(
      'nulls a program venueId absent from the bundle (dangling ref)',
      () async {
        final archive = bundleWithVenue(
          programVenueId: 'orig-missing',
          venues: [Venue(id: 'orig-v2', name: 'Town Hall')],
        );
        final result = await run(archive);

        final program = (await programs.listAll()).single;
        // OWASP: an unresolvable reference is nulled, never persisted dangling.
        expect(program.venueId, isNull);
        // The drop is surfaced as a non-fatal issue, not silently swallowed.
        expect(
          result.programIssues.map((i) => i.code),
          contains('archive_program_unresolved_venue'),
        );
        // The unrelated bundled venue still landed.
        expect((await venues.listAll()).map((v) => v.name), ['Town Hall']);
      },
    );

    test('a legacy bundle with no venues imports cleanly', () async {
      final result = await run(bundleWithVenue());

      expect(await venues.listAll(), isEmpty);
      expect(result.insertedVenueCount, 0);
      expect((await programs.listAll()).single.venueId, isNull);
    });

    test('undo removes the venues the import inserted', () async {
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [Venue(id: 'orig-v1', name: 'Guiding Star Grange')],
      );
      final result = await run(archive);
      expect(await venues.listAll(), hasLength(1));

      await importer.undo(result);
      expect(await venues.listAll(), isEmpty);
      expect(await programs.listAll(), isEmpty);
      // Idempotent — a second undo is a no-op.
      await importer.undo(result);
      expect(await venues.listAll(), isEmpty);
    });

    test('undo retains an imported venue a surviving program references', () async {
      // After a successful import a user program can link to an imported venue.
      // Undo must NOT hard-delete that venue out from under the survivor (which
      // would orphan its venueId); the guarded delete retains it.
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [Venue(id: 'orig-v1', name: 'Guiding Star Grange')],
      );
      final result = await run(archive);
      final importedVenueId = (await venues.listAll()).single.id;

      await programs.create(
        Program(
          id: 'user-p1',
          title: 'Local Dance',
          venueId: importedVenueId,
          status: ProgramStatus.draft,
          slots: const [],
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );

      await importer.undo(result);

      // The imported program is reverted, but the venue survives because the
      // user program still references it — no dangling venueId.
      final survivor = await programs.getById('user-p1');
      expect(survivor, isNotNull);
      expect(survivor!.venueId, importedVenueId);
      expect(await venues.getById(importedVenueId), isNotNull);
    });

    test('collapses duplicate venue ids within one bundle (no orphan)', () async {
      // Untrusted input: two venue entries sharing the same original id must
      // collapse to a single minted row (last-seen content wins), never leaving
      // an orphaned extra venue.
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(id: 'orig-v1', name: 'First Name'),
          Venue(id: 'orig-v1', name: 'Second Name'),
        ],
      );
      final result = await run(archive);

      final all = await venues.listAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'Second Name');
      expect(result.insertedVenueCount, 1);
      expect((await programs.listAll()).single.venueId, all.single.id);
    });

    test('re-importing a strong-key venue dedupes — no duplicate (#456)', () async {
      // Regression for #456: a strong-key venue (name + a locating field) is
      // matched by content fingerprint on re-import, so the second import mints
      // ZERO venues and repoints the (provenance-deduped) program at the venue
      // already imported — no cross-import duplicate.
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(id: 'orig-v1', name: 'Guiding Star Grange', city: 'Greenfield'),
        ],
      );
      final result1 = await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('first'),
        newSlotId: sequentialIds('firstslot'),
      );
      expect(result1.insertedVenueCount, 1);

      final result2 = await importer.import(
        encodeArchive(archive),
        archive,
        now: now.add(const Duration(days: 1)),
        newId: sequentialIds('second'),
        newSlotId: sequentialIds('secondslot'),
      );

      // The program deduped by provenance (updated in place, not re-inserted)...
      final programsAfter = await programs.listAll();
      expect(programsAfter, hasLength(1));
      expect(result2.insertedProgramCount, 0);
      expect(result2.updatedProgramCount, 1);
      // ...and the venue deduped by fingerprint: no new venue, one row total.
      expect(result2.insertedVenueCount, 0);
      final venuesAfter = await venues.listAll();
      expect(venuesAfter, hasLength(1));
      // The surviving program still links to that single existing venue.
      expect(programsAfter.single.venueId, venuesAfter.single.id);
    });

    test(
      're-importing a weak-key (name-only) venue dedupes by provenance (#899)',
      () async {
        // A name-only venue lacks the content fields for a fingerprint match, so
        // it cannot dedupe across senders. But re-importing the *same bundle* now
        // dedupes by provenance (issue #899): the first import stamps a
        // (source=json, externalId=orig-v1) provenance row, and the second import
        // finds it by exact-id lookup — no duplicate.
        final archive = bundleWithVenue(
          programVenueId: 'orig-v1',
          venues: [Venue(id: 'orig-v1', name: 'Town Hall')],
        );
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

        // Provenance match fires: no new venue minted on the re-import.
        expect(result2.insertedVenueCount, 0);
        expect(await venues.listAll(), hasLength(1));
      },
    );

    test('local-only venue with no provenance row is never matched by an '
        'incoming bundle id (no false provenance-match)', () async {
      // A locally-created venue (not imported from any bundle) has no
      // venue_provenance row. An incoming bundle that happens to carry the
      // same id string must NOT provenance-match it — the lookup is
      // keyed on rows that actually exist in venue_provenance, and a
      // locally-minted venue has none. The importer fresh-mints a new
      // venue for the bundle, leaving the local one untouched.
      //
      // This guards the "id collision by coincidence" hazard: a bundle
      // from an external sender might carry an id that matches a local
      // UUID by chance (unlikely) or, more critically, a malicious bundle
      // might replay a known local id to attempt a provenance shortcut.
      // Neither can fire without an actual provenance row in the DB.
      final localVenue = Venue(id: 'local-hall', name: 'Local Hall');
      await venues.upsert(localVenue);
      // That local venue has no provenance row, so a bundle arriving with
      // externalId 'local-hall' must NOT match it.
      final bundleWithLocalId = bundleWithVenue(
        programVenueId: 'local-hall',
        venues: [Venue(id: 'local-hall', name: 'Bundle Hall')],
      );
      final result = await importer.import(
        encodeArchive(bundleWithLocalId),
        bundleWithLocalId,
        now: now.add(const Duration(days: 2)),
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('newslot'),
      );
      // A new venue was minted (the local venue has no provenance, so no
      // provenance match fires despite the id collision attempt).
      expect(result.insertedVenueCount, 1);
      final named = (await venues.listAll())
          .where((v) => v.name == 'Bundle Hall')
          .toList();
      expect(named, hasLength(1));
      expect(named.single.id, isNot('local-hall'));
    });

    test('dedupe never overwrites the matched venue\'s fields', () async {
      // The receiver already holds a venue; a later bundle carries a
      // fingerprint-equal venue with DIFFERENT contact/address2/notes. Matching
      // must repoint only — never mutate the existing record — preserving the
      // untrusted-bundle guarantee.
      await venues.upsert(
        Venue(
          id: 'local-v1',
          name: 'Guiding Star Grange',
          city: 'Greenfield',
          address2: 'Room A',
          contact1Name: 'Local Contact',
          notes: 'local notes',
        ),
      );
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(
            id: 'orig-v1',
            name: 'GUIDING STAR GRANGE', // case/space differences still match
            city: 'greenfield',
            address2: 'Basement',
            contact1Name: 'Bundle Contact',
            notes: 'bundle notes',
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

      expect(result.insertedVenueCount, 0);
      final all = await venues.listAll();
      expect(all, hasLength(1));
      final existing = all.single;
      expect(existing.id, 'local-v1');
      expect(existing.address2, 'Room A', reason: 'never overwritten');
      expect(
        existing.contact1Name,
        'Local Contact',
        reason: 'never overwritten',
      );
      expect(existing.notes, 'local notes', reason: 'never overwritten');
      expect((await programs.listAll()).single.venueId, 'local-v1');
    });

    test('an ambiguous fingerprint match fresh-mints (never guesses)', () async {
      // Two existing venues share a fingerprint (e.g. an earlier weak-key merge
      // was never applied). An incoming venue that fingerprint-equals both is
      // ambiguous, so the importer mints a fresh venue rather than guessing.
      await venues.upsert(
        Venue(id: 'local-a', name: 'Grange', city: 'Amherst'),
      );
      await venues.upsert(
        Venue(id: 'local-b', name: 'Grange', city: 'Amherst'),
      );
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [Venue(id: 'orig-v1', name: 'Grange', city: 'Amherst')],
      );
      final result = await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      expect(result.insertedVenueCount, 1);
      final program = (await programs.listAll()).single;
      expect(program.venueId, isNot('local-a'));
      expect(program.venueId, isNot('local-b'));
      expect(await venues.listAll(), hasLength(3));
    });

    test(
      'two fingerprint-equal venues within one bundle collapse to one',
      () async {
        // Distinct original ids, identical descriptive fields: the first is
        // minted and folded into the index, so the second dedupes to it.
        final d1 = _dance('orig-d1', 'Simplicity Swing');
        final pA = Program(
          id: 'orig-pA',
          title: 'A',
          venueId: 'orig-v1',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 'orig-slA', position: 0, danceId: 'orig-d1')],
          createdAt: DateTime.utc(2026, 4, 1),
          updatedAt: DateTime.utc(2026, 4, 1),
        );
        final pB = Program(
          id: 'orig-pB',
          title: 'B',
          venueId: 'orig-v2',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 'orig-slB', position: 0, danceId: 'orig-d1')],
          createdAt: DateTime.utc(2026, 4, 1),
          updatedAt: DateTime.utc(2026, 4, 1),
        );
        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [d1],
          programs: [pA, pB],
          venues: [
            Venue(
              id: 'orig-v1',
              name: 'Guiding Star Grange',
              city: 'Greenfield',
            ),
            Venue(
              id: 'orig-v2',
              name: 'Guiding Star Grange',
              city: 'Greenfield',
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

        expect(result.insertedVenueCount, 1);
        final all = await venues.listAll();
        expect(all, hasLength(1));
        final progs = await programs.listAll();
        expect(progs, hasLength(2));
        expect(progs.map((p) => p.venueId).toSet(), {all.single.id});
      },
    );

    test(
      'a repeated deduped id never overwrites another id\'s minted venue',
      () async {
        // Untrusted bundle: id B mints a venue; id A (fingerprint-equal) dedupes
        // onto B's minted row; then A repeats with DIFFERENT content. A never
        // minted, so its repeat must be a no-op — it must not clobber the row B
        // (and A's first occurrence) resolved to. Guards the non-deterministic
        // "deduped id later mutates a shared minted venue" hazard.
        final archive = bundleWithVenue(
          programVenueId: 'B',
          venues: [
            Venue(id: 'B', name: 'Guiding Star Grange', city: 'Greenfield'),
            // A fingerprint-equals B → dedupes onto B's minted row.
            Venue(id: 'A', name: 'Guiding Star Grange', city: 'Greenfield'),
            // A repeats with hijacked content: must NOT overwrite the row.
            Venue(id: 'A', name: 'Evil Hall', city: 'Nowhere'),
          ],
        );
        final result = await run(archive);

        expect(result.insertedVenueCount, 1);
        final all = await venues.listAll();
        expect(all, hasLength(1));
        expect(all.single.name, 'Guiding Star Grange', reason: 'not clobbered');
        expect(all.single.city, 'Greenfield', reason: 'not clobbered');
      },
    );

    test('a repeated minting id still refreshes to last-seen content', () async {
      // Counterpart to the above: an id that actually MINTED its row keeps the
      // documented within-bundle "last-seen wins" refresh.
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(id: 'orig-v1', name: 'Guiding Star Grange', city: 'Greenfield'),
          Venue(id: 'orig-v1', name: 'Guiding Star Grange', city: 'Amherst'),
        ],
      );
      final result = await run(archive);

      expect(result.insertedVenueCount, 1);
      final all = await venues.listAll();
      expect(all, hasLength(1));
      expect(all.single.city, 'Amherst', reason: 'last-seen wins for a minter');
    });

    test('undo after a dedupe deletes only newly-minted venues', () async {
      // The receiver already holds a venue; a bundle dedupes to it. Undo must
      // remove nothing — the matched venue is pre-existing, never in
      // insertedVenueIds, so undo can't delete a venue the user already had.
      await venues.upsert(
        Venue(id: 'local-v1', name: 'Guiding Star Grange', city: 'Greenfield'),
      );
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [
          Venue(id: 'orig-v1', name: 'Guiding Star Grange', city: 'Greenfield'),
        ],
      );
      final result = await run(archive);
      expect(result.insertedVenueCount, 0);

      await importer.undo(result);

      // The pre-existing venue survives undo untouched.
      final survivor = await venues.getById('local-v1');
      expect(survivor, isNotNull);
      expect(survivor!.name, 'Guiding Star Grange');
      expect(await venues.listAll(), hasLength(1));
    });

    test('validates venueIds against the minted set (no per-program venue '
        'SELECT)', () async {
      final counter = VenueSelectCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final countingPrograms = ProgramRepository(countingDb);
      final countingVenues = VenueRepository(countingDb);
      final countingImporter = CompendiumArchiveImporter(
        ImportPipeline(
          DanceRepository(countingDb, contraTaxonomy),
          ChoreographerRepository(countingDb),
        ),
        countingPrograms,
        countingVenues,
      );

      Program p(String id, String venueId) => Program(
        id: id,
        title: 'P $id',
        venueId: venueId,
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: '$id-s0', position: 0, danceId: 'orig-d1')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [_dance('orig-d1', 'Simplicity Swing')],
        programs: [
          p('orig-p1', 'orig-v1'),
          p('orig-p2', 'orig-v2'),
          p('orig-p3', 'orig-v1'),
        ],
        venues: [
          // Strong keys (name + city) so the dedupe preload actually runs; the
          // point of this test is that it runs *once*, not per program.
          Venue(id: 'orig-v1', name: 'Grange A', city: 'Amherst'),
          Venue(id: 'orig-v2', name: 'Grange B', city: 'Northampton'),
        ],
      );

      counter.reset();
      await countingImporter.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      // The only venue SELECT the import issues is the single fingerprint-index
      // preload (one `listAll` before the venue loop — O(1), not per-venue). The
      // program write phase then validates each `venueId` against the in-memory
      // known set, adding no per-program venue existence SELECT; with 3 programs
      // an N+1 regression would push this to 4+.
      expect(counter.count, 1);
      expect(await countingPrograms.listAll(), hasLength(3));
    });

    test('a weak-key-only bundle skips the dedupe preload (zero venue '
        'SELECTs)', () async {
      // No bundled venue clears the strong-key threshold, so cross-import
      // dedupe is impossible and the `listAll` preload must be skipped entirely.
      final counter = VenueSelectCounter();
      final countingDb = openCountingTestDatabase(counter);
      addTearDown(countingDb.close);
      final countingImporter = CompendiumArchiveImporter(
        ImportPipeline(
          DanceRepository(countingDb, contraTaxonomy),
          ChoreographerRepository(countingDb),
        ),
        ProgramRepository(countingDb),
        VenueRepository(countingDb),
      );
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [_dance('orig-d1', 'Simplicity Swing')],
        programs: [
          Program(
            id: 'orig-p1',
            title: 'P1',
            venueId: 'orig-v1',
            status: ProgramStatus.draft,
            slots: [ProgramSlot(id: 'p1-s0', position: 0, danceId: 'orig-d1')],
            createdAt: DateTime.utc(2026, 4, 1),
            updatedAt: DateTime.utc(2026, 4, 1),
          ),
        ],
        // Name-only venue: below the strong-key threshold (null fingerprint).
        venues: [Venue(id: 'orig-v1', name: 'Town Hall')],
      );

      counter.reset();
      await countingImporter.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('new'),
        newSlotId: sequentialIds('slot'),
      );

      expect(counter.count, 0);
    });

    test(
      'preserves a user-linked venueId when re-importing a pre-venue archive',
      () async {
        // A program first imported from a pre-venue (venue-less) bundle: its
        // requiredSchemaVersion is the base version, so the importer treats it as
        // unable to express `venueId`.
        final preVenue = bundleWithVenue();
        await run(preVenue);
        final imported = (await programs.listAll()).single;
        expect(imported.venueId, isNull);

        // The user later links that program to a venue locally.
        await venues.upsert(Venue(id: 'user-v1', name: 'User Hall'));
        await programs.update(imported.copyWith(venueId: 'user-v1'));

        // Re-importing the SAME pre-venue bundle must NOT clobber that link: the
        // source cannot express `venueId`, so the rebuilt program's null is
        // "unknown", not "explicitly cleared" — mirroring the `.USR` re-import.
        await importer.import(
          encodeArchive(preVenue),
          preVenue,
          now: now.add(const Duration(days: 1)),
          newId: sequentialIds('second'),
          newSlotId: sequentialIds('secondslot'),
        );

        final after = (await programs.listAll()).single;
        expect(after.id, imported.id, reason: 'deduped in place, not inserted');
        expect(after.venueId, 'user-v1', reason: 'app-local link preserved');
        expect(await venues.getById('user-v1'), isNotNull);
      },
    );

    test('a venue-aware re-import honors an explicit cleared venueId', () async {
      // A program imported from a venue-aware bundle, linked to a venue.
      final withVenue = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [Venue(id: 'orig-v1', name: 'Guiding Star Grange')],
      );
      await run(withVenue);
      final imported = (await programs.listAll()).single;
      expect(imported.venueId, isNotNull);

      // Re-import a bundle that is still venue-aware (it carries venue records)
      // but whose SAME program now has no venue link. Because the source *can*
      // express venue semantics, the explicit absence overwrites the match —
      // the link is cleared, unlike the pre-venue case above.
      final cleared = bundleWithVenue(
        venues: [Venue(id: 'orig-v2', name: 'Town Hall')],
      );
      await importer.import(
        encodeArchive(cleared),
        cleared,
        now: now.add(const Duration(days: 1)),
        newId: sequentialIds('second'),
        newSlotId: sequentialIds('secondslot'),
      );

      final after = (await programs.listAll()).single;
      expect(after.id, imported.id, reason: 'deduped in place, not inserted');
      expect(after.venueId, isNull, reason: 'v2 explicit clear honored');
    });

    test('re-importing a shared (address-redacted) bundle dedupes venue by '
        'provenance (#899)', () async {
      // Regression guard for issue #899 / PR #882 accepted-limitation fix.
      //
      // Share bundles redact the postal address, so venueFingerprint returns
      // null and the content-fingerprint path cannot fire. Before issue #899
      // this meant every re-import of the same shared bundle minted a second
      // venue record. The provenance-based path (introduced in #899) fires
      // first: the first import stamps (source=json, externalId=orig-v1) on
      // the minted venue, and the second import finds it by that exact key.
      final sharedVenue = Venue(
        id: 'orig-v1',
        name: 'Guiding Star Grange',
        // Address intentionally absent — simulates sanitizeVenueForShare().
      );
      final archive = bundleWithVenue(
        programVenueId: 'orig-v1',
        venues: [sharedVenue],
      );

      // First import mints the venue.
      final result1 = await importer.import(
        encodeArchive(archive),
        archive,
        now: now,
        newId: sequentialIds('first'),
        newSlotId: sequentialIds('firstslot'),
      );
      expect(result1.insertedVenueCount, 1);
      final mintedId = (await venues.listAll()).single.id;

      // Second import (re-import of the same bundle) must dedupe by provenance,
      // not mint a second row.
      final result2 = await importer.import(
        encodeArchive(archive),
        archive,
        now: now.add(const Duration(days: 1)),
        newId: sequentialIds('second'),
        newSlotId: sequentialIds('secondslot'),
      );

      expect(
        result2.insertedVenueCount,
        0,
        reason: 'provenance path fires; no new venue minted',
      );
      final allVenues = await venues.listAll();
      expect(allVenues, hasLength(1));
      expect(allVenues.single.id, mintedId);

      // The program still links to the single existing venue.
      final prog = (await programs.listAll()).single;
      expect(prog.venueId, mintedId);
    });
  });
}
