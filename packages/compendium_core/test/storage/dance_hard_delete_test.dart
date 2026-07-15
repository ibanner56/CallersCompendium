import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';
import 'fixtures.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
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
}
