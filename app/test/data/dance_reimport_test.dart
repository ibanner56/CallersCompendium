import 'package:compendium_app/src/data/dance_reimport.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  test('JSON planning requires exactly one planned dance', () async {
    final repos = openTestRepositories();
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
    expect(planned.draft.dance.title, 'Dance one');
    await expectLater(
      planSingleDanceJson(repos, payload(const [])),
      throwsA(isA<DanceReimportJsonException>()),
    );
    await expectLater(
      planSingleDanceJson(repos, payload([dance('one'), dance('two')])),
      throwsA(isA<DanceReimportJsonException>()),
    );
    await expectLater(
      planSingleDanceJson(repos, '{ not JSON'),
      throwsA(isA<DanceReimportJsonException>()),
    );
    await expectLater(
      planSingleDanceJson(repos, '[]'),
      throwsA(isA<DanceReimportJsonException>()),
    );
  });

  test('JSON planning rejects archives containing programs', () async {
    final repos = openTestRepositories();
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
