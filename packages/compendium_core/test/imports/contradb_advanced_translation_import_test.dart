// What the importer does with ContraDB figures, as it bears on how the Advanced
// translator must ask ContraDB.
//
// These pin the LOCAL half of two claims in the translator's comments: an
// `allemande orbit` imports as `meanwhile[allemande, orbit]`, and a typed
// `A while B` line is structured locally. They say nothing about the other
// table entries (the alias split of `do_si_do`/`see_saw`, `pull_by`'s `or`).
// The ContraDB half comes from reading its `filter_dances.rb`; nothing here
// runs ContraDB, so a change on its side is not caught.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
  });
  tearDown(() => db.close());

  Future<void> store(String id, List<Figure> figures) => dances.create(
    Dance(
      id: id,
      title: id,
      figures: figures,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  List<Object?> translated(DanceFilter filter) =>
      (translateDanceFilterToContraDb(filter) as ContraDbAdvancedExpression)
          .expression;

  test('a real allemande orbit imports as meanwhile[allemande, orbit], so an '
      'allemande query asks ContraDB for both of its moves', () async {
    final figure = parseContraDbFigureLine(
      'ladles allemande left 1½ around while the gentlespoons orbit '
      'clockwise ½ around',
      beats: 8,
    );
    expect(figure, isNotNull);
    expect(figure!.isMeanwhile, isTrue);
    expect(figure.subFigures.map((s) => s.move), ['allemande', 'orbit']);

    await store('orbit-dance', [figure]);
    // Found locally through the flattened leaf (#590)...
    expect(await dances.search(FigureFilter.leaf('allemande')), [
      'orbit-dance',
    ]);
    // ...so the ContraDB side must also reach a figure whose move is
    // `allemande orbit`.
    expect(translated(FigureFilter.leaf('allemande')), [
      'or',
      ['figure', 'allemande'],
      ['figure', 'allemande orbit'],
    ]);
  });

  test('a typed custom "A while B" is structured locally, though ContraDB '
      'keeps it as one custom figure', () async {
    final figure = parseContraDbFigureLine(
      'ones swing while twos circle',
      beats: 8,
    );
    expect(figure, isNotNull);
    expect(figure!.isMeanwhile, isTrue);
    await store('typed', [figure]);
    // The Collection finds the swing inside it. ContraDB would file the whole
    // line under `custom`, which the translator cannot know from the query:
    // this is a documented difference, not something it can refuse up front.
    expect(await dances.search(FigureFilter.leaf('swing')), ['typed']);
  });
}
