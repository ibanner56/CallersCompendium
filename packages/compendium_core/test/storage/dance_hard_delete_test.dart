import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';
import 'fixtures.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ProgramRepository programs;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    programs = ProgramRepository(db);
  });

  tearDown(() => db.close());

  test('hardDelete removes dances immediately and clears FTS', () async {
    final a = sampleDance(id: 'a', title: 'Alpha');
    final b = sampleDance(id: 'b', title: 'Bravo');
    await dances.create(a);
    await dances.create(b);

    await dances.hardDelete(['a']);

    expect(await dances.getById('a', includeDeleted: true), isNull);
    expect(await dances.getById('b'), isNotNull);
    // FTS row for the removed dance is gone.
    expect(await dances.searchText('Alpha'), isNot(contains('a')));
    expect(await dances.searchText('Bravo'), contains('b'));
  });

  test('hardDelete ignores unknown ids and an empty list', () async {
    await dances.create(sampleDance(id: 'a', title: 'Alpha'));
    await dances.hardDelete(const []);
    await dances.hardDelete(['does-not-exist']);
    expect(await dances.getById('a'), isNotNull);
  });

  test('hardDelete tombstones a dance-only program slot with the dance title '
      '(#429, import-undo path)', () async {
    // Mirrors the purgeDeleted tombstone case for the separate hardDelete
    // (import-session undo) path: a slot whose ONLY content is its dance.
    // Without the cleanup, hardDelete's SET NULL would leave (danceId, text)
    // = (null, null) and corrupt every Programs load.
    await dances.create(sampleDance(id: 'd1', title: 'Doomed Dance'));
    await programs.create(
      Program(
        id: 'p1',
        title: 'Evening set',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await dances.hardDelete(['d1']);

    final program = await programs.getById('p1');
    expect(program, isNotNull);
    expect(program!.slots.single.danceId, isNull);
    expect(program.slots.single.text, 'Doomed Dance');

    // No dangling references remain after the import-undo hard delete.
    final fkViolations = await db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(fkViolations, isEmpty);
  });

  test('hardDelete removes a surviving owner\'s relatedDance link when its '
      'target is deleted (#466, import-undo path)', () async {
    // Owner A links to target B via a relatedDance link. Hard-deleting only
    // B (the owner survives) must drop the now-meaningless orphan link rather
    // than leaving (relatedDance, targetDanceId=null), which corrupts A's
    // load.
    await dances.create(sampleDance(id: 'b', title: 'Target'));
    await dances.create(
      sampleDance(
        id: 'a',
        title: 'Owner',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.relatedDance, targetDanceId: 'b'),
        ],
      ),
    );

    await dances.hardDelete(['b']);

    final owner = await dances.getById('a');
    expect(owner, isNotNull);
    expect(owner!.links, isEmpty);

    // listAll (batched link hydration) also succeeds, and no FK dangles.
    final all = await dances.listAll();
    expect(all.map((d) => d.id), ['a']);
    expect(all.single.links, isEmpty);
    final fkViolations = await db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(fkViolations, isEmpty);
  });
}
