// Where the Collection and ContraDB MUST disagree about the same dance.
//
// These are not translator defects and cannot be refused up front: the
// translator sees only the query, while the difference is in how a particular
// ContraDB figure arrives in the Collection. Each case pins the disagreement
// (which side finds the dance) so that a change to the importer, the derived
// `dance_figures` table or ContraDB's semantics shows up here rather than as a
// silent shift in what an online Advanced search means.
//
// Every figure is given as ContraDB holds it (`move`) and as ContraDB renders
// it (`text`); the Collection side is the real importer's output.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../../storage/test_database.dart';
import 'contradb_reference.dart';
import 'corpus.dart';

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  final cases = <String, List<ContraFig>>{};

  // ContraDB figure, rendered text, the figures it becomes in the Collection.
  const swing = ContraFig('swing', 'swing', 'neighbors swing', ['swing']);
  const chain = ContraFig('chain', 'chain', 'ladles chain', ['chain']);

  // A user-typed `custom` figure: ContraDB keeps move == 'custom'; the importer
  // structures the text.
  const customWhile = ContraFig(
    'custom-while',
    'custom',
    'ones swing while twos circle',
    null,
  );
  const customBalanceAndSwing = ContraFig(
    'custom-balance-and-swing',
    'custom',
    'neighbors balance and swing',
    null,
  );
  // One ContraDB figure, two Collection figures (the importer splits the
  // balance off an ocean wave, `contradb_html_adapter.dart`).
  const oceanWaveBalance = ContraFig(
    'ocean-wave-balance',
    'form an ocean wave',
    'form an ocean wave & balance - ladles by right hands and neighbors by left hands',
    null,
  );
  // ContraDB `chain` the importer does not recognise.
  const wildChain = ContraFig(
    'wild-chain',
    'chain',
    'ladles *-hand chain',
    null,
  );
  const starPromenade = ContraFig(
    'star-promenade',
    'star promenade',
    'star promenade left ½',
    null,
  );
  const allemandeOrbit = ContraFig(
    'allemande-orbit',
    'allemande orbit',
    'allemande orbit - ones left and twos right',
    null,
  );

  setUpAll(() async {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    cases.addAll({
      'while': [customWhile],
      'balance-and-swing': [customBalanceAndSwing],
      'ocean': [oceanWaveBalance],
      'wild-chain': [wildChain],
      'star-promenade': [starPromenade],
      'orbit': [allemandeOrbit],
      'plain-swing': [swing],
      'plain-chain': [chain],
    });
    for (final e in cases.entries) {
      final figures = await importedFigures(contraDbPage(e.key, 'C', e.value));
      await dances.create(
        Dance(
          id: e.key,
          title: e.key,
          figures: figures,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  });
  tearDownAll(() => db.close());

  Future<(Set<String>, Set<String>)> run(DanceFilter filter) async {
    final t = translateDanceFilterToContraDb(filter);
    expect(t, isA<ContraDbAdvancedExpression>());
    final local = (await dances.search(filter)).toSet();
    final contra = contraDbMatchingIds(
      (t as ContraDbAdvancedExpression).expression,
      [
        for (final e in cases.entries)
          ContraDbDance(
            id: e.key,
            moves: [for (final f in e.value) f.move],
            aliases: [for (final f in e.value) f.alias],
          ),
      ],
    ).toSet();
    return (local, contra);
  }

  test(
    'a custom "A while B" is one ContraDB figure but two Collection leaves',
    () async {
      final (local, contra) = await run(FigureFilter.leaf('swing'));
      expect(local, contains('while'), reason: 'meanwhile is flattened (#590)');
      expect(
        contra,
        isNot(contains('while')),
        reason: "ContraDB: move is 'custom'",
      );
      expect(local, containsAll(['plain-swing']));
      expect(contra, {'plain-swing'});
    },
  );

  test('a custom line the importer structures is found locally only', () async {
    final (local, contra) = await run(FigureFilter.leaf('balance'));
    expect(local, contains('balance-and-swing'));
    expect(contra, isEmpty);
  });

  test(
    'an ocean wave & balance is one ContraDB figure, two Collection figures',
    () async {
      final (local, contra) = await run(FigureFilter.leaf('balance'));
      expect(local, contains('ocean'));
      expect(contra, isNot(contains('ocean')));
    },
  );

  test(
    'a ContraDB chain the importer cannot read is invisible locally',
    () async {
      final (local, contra) = await run(FigureFilter.leaf('chain'));
      expect(contra, containsAll(['wild-chain', 'plain-chain']));
      expect(local, {'plain-chain'});
    },
  );

  test(
    'ContraDB moves with no Collection counterpart fall out of "has no figure"',
    () async {
      // Both sides agree there is no `star_promenade`/`allemande_orbit` query
      // (the translator refuses them), so the only visible effect is on negation:
      // the Collection sees a `custom` leaf where ContraDB sees a real move.
      final (local, contra) = await run(
        FigureFilter(FigureNot(FigureLeaf('swing'))),
      );
      expect(contra, containsAll(['star-promenade', 'orbit']));
      expect(local, containsAll(['star-promenade', 'orbit']));
    },
  );
}
