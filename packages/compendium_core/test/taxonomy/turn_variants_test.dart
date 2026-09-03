import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  test('taxonomy v33 registers both turn variants', () {
    expect(contraTaxonomyVersion, 33);
    expect(tax.version, 33);
    expect(tax.resolve('turn_as_couples')?.id, 'turn_as_couples');
    expect(tax.resolve('two_hand_turn')?.id, 'two_hand_turn');
  });

  test('turn as couples mirrors star through', () {
    final def = tax.resolve('turn_as_couples')!;
    expect(def.params.keys, containsAll(['who', 'beats']));
    expect(def.params.containsKey('hand'), isFalse);
    expect(def.params.containsKey('turn'), isFalse);
    expect(tax.effectiveParams(Figure(move: 'turn_as_couples')), {
      'who': 'partners',
      'beats': 4,
    });
    expect(
      renderer.renderCanonical(Figure(move: 'turn_as_couples')),
      'partners turn as couples',
    );
  });

  test('two hand turn mirrors allemande without hand', () {
    final def = tax.resolve('two_hand_turn')!;
    expect(def.params.keys, containsAll(['who', 'turn', 'beats']));
    expect(def.params.containsKey('hand'), isFalse);
    expect(tax.effectiveParams(Figure(move: 'two_hand_turn')), {
      'who': 'partners',
      'turn': 1.0,
      'beats': 8,
    });
    expect(
      renderer.renderCanonical(Figure(move: 'two_hand_turn')),
      'partners two hand turn once',
    );
  });

  test('both defaults validate', () {
    for (final move in ['turn_as_couples', 'two_hand_turn']) {
      final seed = testFigure(move: move);
      final figure = testFigure(move: move, params: tax.effectiveParams(seed));
      expect(tax.validateFigure(figure), isEmpty);
    }
  });

  test('shared parser recognizes both standalone phrases', () {
    final turnAsCouples = parseFigureLine('Neighbor turn as couples');
    expect(turnAsCouples?.move, 'turn_as_couples');
    expect(turnAsCouples?.params['who'], 'neighbors');

    final twoHandTurn = parseFigureLine('Partner two hand turn 1/2');
    expect(twoHandTurn?.move, 'two_hand_turn');
    expect(twoHandTurn?.params, {'who': 'partners', 'turn': 0.5});
  });

  test('turn as couples does not claim trailing choreography', () {
    final figure = parseFigureLine('Neighbor turn as couples then promenade');
    expect(figure?.isCustom, isTrue);
  });
}
