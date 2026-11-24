import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Taxonomy v40: a pass is routed on write to the id its pass type names, and
/// keeps what each param it leaves out meant under the id it came with.
void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  Future<Figure> roundTrip(Figure figure) async {
    final now = DateTime.utc(2026, 1, 1);
    await dances.create(
      Dance(
        id: 'd',
        title: 'Pass',
        form: DanceForm.contra,
        formation: const Formation(FormationShape.dupleImproper),
        figures: [figure],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final read = (await dances.getById('d'))!;
    return (read.figuresSource as DecodedFigures).figures.single;
  }

  // Mutation caught: routing without `keepOmittedMeaning`, which stores the
  // pass by with `who` left out — read as neighbors — though the pass through
  // it was written as names no one.
  test('a pass through with pass type by is stored as a pass by that names '
      'no one', () async {
    final stored = await roundTrip(
      Figure(move: 'pass_through', params: const {'passType': 'by'}),
    );
    expect(stored.move, 'pass_by');
    expect(stored.params, isNot(contains('passType')));
    final effective = contraTaxonomy.effectiveParams(stored);
    expect(effective['who'], ParamVocab.unspecified);
    expect(effective['where'], 'along');
  });

  test('a pass through stores no pass type', () async {
    final stored = await roundTrip(
      Figure(
        move: 'pass_through',
        params: const {'passType': 'through', 'who': 'neighbors'},
      ),
    );
    expect(stored.move, 'pass_through');
    expect(stored.params, {'who': 'neighbors'});
  });
}
