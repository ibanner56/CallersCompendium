import 'package:compendium_app/src/data/dance_reimport.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  test(
    're-import preserves collection metadata and replaces choreography',
    () async {
      final repos = openTestRepositories();
      addTearDown(repos.db.close);
      final original = Dance(
        id: 'saved',
        title: 'My edited title',
        formation: const Formation(FormationShape.dupleImproper),
        progression: Progression.single,
        figures: [
          Figure(move: customMove, params: {'text': 'old'}),
        ],
        callingNotes: 'Keep this note',
        rating: 5,
        tagIds: const [],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await repos.dances.create(original);
      final incoming = Dance(
        id: 'remote',
        title: 'Remote title',
        formation: const Formation(FormationShape.becketCw),
        progression: Progression.double,
        figures: [
          Figure(move: customMove, params: {'text': 'new'}),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      expect(
        await replaceDanceChoreography(
          repos,
          targetDanceId: original.id,
          incoming: incoming,
          now: DateTime.utc(2026, 2),
        ),
        DanceReimportResult.replaced,
      );

      final saved = await repos.dances.getById(original.id);
      expect(saved!.title, original.title);
      expect(saved.callingNotes, original.callingNotes);
      expect(saved.rating, original.rating);
      expect(saved.formation, incoming.formation);
      expect(saved.progression, incoming.progression);
      expect(saved.figures, incoming.figures);
      expect(saved.updatedAt, DateTime.utc(2026, 2));
    },
  );

  test('re-import reports a target deleted while previewing', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final incoming = Dance(
      id: 'remote',
      title: 'Remote',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(
      await replaceDanceChoreography(
        repos,
        targetDanceId: 'missing',
        incoming: incoming,
      ),
      DanceReimportResult.targetMissing,
    );
  });

  test('JSON planning requires exactly one planned dance', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    Dance dance(String id) => Dance(
      id: id,
      title: 'Dance $id',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    String payload(List<Dance> dances) => encodeArchive(
      CompendiumArchive(exportedAt: DateTime.utc(2026), dances: dances),
    );

    final planned = await planSingleDanceJson(repos, payload([dance('one')]));
    expect(planned?.draft.dance.title, 'Dance one');
    await expectLater(
      planSingleDanceJson(repos, payload(const [])),
      throwsA(isA<DanceReimportJsonException>()),
    );
    await expectLater(
      planSingleDanceJson(repos, payload([dance('one'), dance('two')])),
      throwsA(isA<DanceReimportJsonException>()),
    );
  });

  test('JSON planning rejects archives containing programs', () async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final dance = Dance(
      id: 'dance',
      title: 'Dance',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final program = Program(
      id: 'program',
      title: 'Program',
      slots: [ProgramSlot(id: 'slot', position: 0, text: 'Break')],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final payload = encodeArchive(
      CompendiumArchive(
        exportedAt: DateTime.utc(2026),
        dances: [dance],
        programs: [program],
      ),
    );

    await expectLater(
      planSingleDanceJson(repos, payload),
      throwsA(
        predicate<DanceReimportJsonException>((error) => error.programBearing),
      ),
    );
  });
}
