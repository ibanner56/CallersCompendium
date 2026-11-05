import 'package:compendium_app/src/export/program_share_bundle.dart';
import 'package:compendium_app/src/widgets/program_export_menu.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// A program citing a dance another device permanently deleted (row 49 of the
/// follow-ups triage; the maintainer chose option (a) on 2026-11-05).
///
/// That dance reaches this device blanked: titled "—", with no content. A
/// share used to send it as an empty live dance, so the receiver imported a
/// "—" dance, and the PDF's "Include figures" pages gave it a page of its own.
/// Now the share sends its slot as a "Deleted dance" text slot without the
/// dance, and the export leaves it out of the appended dances.
void main() {
  Dance live(String id, String title) => Dance(
    id: id,
    title: title,
    figures: [
      Figure(move: 'swing', params: {'beats': 16, 'who': 'partners'}),
    ],
    createdAt: _now,
    updatedAt: _now,
  );

  // As Device Sync stores a peer's blank.
  final blanked = Dance(
    id: 'gone',
    title: blankedRecordTitle,
    createdAt: _now,
    updatedAt: _now,
    deletedAt: permanentlyDeletedAt,
  );
  // A retention sweep keeps a cited dance's title under the same mark; that
  // one is not a blank and still travels (GIG-11).
  final sweptKeepingTitle = live(
    'kept',
    'Rory O\'More',
  ).copyWith(deletedAt: permanentlyDeletedAt);
  final catalog = {
    'd1': live('d1', 'Chorus Jig'),
    'gone': blanked,
    'kept': sweptKeepingTitle,
  };

  final program = Program(
    id: 'p1',
    title: 'Friday Contra',
    slots: [
      ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
      ProgramSlot(id: 's1', position: 1, danceId: 'gone'),
      ProgramSlot(id: 's2', position: 2, danceId: 'gone', text: 'Slow it'),
      ProgramSlot(id: 's3', position: 3, danceId: 'kept'),
    ],
    createdAt: _now,
    updatedAt: _now,
  );

  String share() => buildProgramShareBundle(
    program,
    blankedDanceSlotText: 'Deleted dance',
    danceFor: (id) => catalog[id],
    choreographerFor: (_) => null,
    venueFor: (_) => null,
    tagFor: (_) => null,
    publishedSourceFor: (_) => null,
    customFieldFor: (_) => null,
    now: _now,
  );

  test('the share sends a "Deleted dance" text slot, not the blank', () {
    final archive = decodeArchive(share()).archive;

    expect(archive.dances.map((d) => d.id), unorderedEquals(['d1', 'kept']));
    final slots = archive.programs.single.slots;
    expect(slots[0].danceId, 'd1');
    expect(slots[1].danceId, isNull);
    expect(slots[1].text, 'Deleted dance');
    expect(slots[1].isPurgedDance, isTrue);
    // A slot with a note keeps the note, as a purge leaves it.
    expect(slots[2].danceId, isNull);
    expect(slots[2].text, 'Slow it');
    expect(slots[3].danceId, 'kept');
  });

  test('the receiver imports no empty dance', () async {
    final repos = openTestRepositories();
    final json = share();
    final result = await CompendiumArchiveImporter(
      ImportPipeline(repos.dances, repos.choreographers),
      repos.programs,
      repos.venues,
      repositories: repos,
    ).import(json, decodeArchive(json).archive, now: DateTime.utc(2026, 7, 20));

    expect(result.primaryProgramId, isNotNull);
    final titles = (await repos.dances.listAll()).map((d) => d.title);
    expect(titles, isNot(contains(blankedRecordTitle)));
    expect(
      result.programIssues.where(
        (i) => i.code == 'archive_program_unresolved_dance',
      ),
      isEmpty,
    );
    final slots = (await repos.programs.listAll()).single.slots;
    expect(slots[1].danceId, isNull);
    expect(slots[1].text, 'Deleted dance');
  });

  test('the export\'s appended dances (PDF "Include figures") skip the '
      'blank', () {
    final appended = orderedProgramExportDances(program, (id) => catalog[id]);

    expect(appended.map((e) => e.dance.id), ['d1', 'kept']);
  });
}
