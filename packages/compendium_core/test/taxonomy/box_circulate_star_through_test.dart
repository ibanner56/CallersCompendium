import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// PR5 (parser overhaul) — the new balance+twirl-family moves added in
/// contraTaxonomyVersion 11: `box_circulate` (ContraDB-sourced, modeled on
/// `box_the_gnat`) and `star_through` (modeled on `california_twirl` + a balance
/// flag). Both carry a neutral `balance` flag whose balanced beat count comes
/// only from the CallersBox cross-line merge, so neither takes `paramBeats`.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  test('contraTaxonomyVersion is 11', () {
    expect(contraTaxonomyVersion, 11);
    expect(tax.version, 11);
  });

  group('box_circulate', () {
    test('registers with box_the_gnat-style params and defaults', () {
      final def = tax.resolve('box_circulate');
      expect(def, isNotNull);
      expect(
        def!.params.keys,
        containsAll(['who', 'hand', 'balance', 'beats']),
      );
      expect(def.params.containsKey('places'), isFalse);
      final defaults = tax.effectiveParams(Figure(move: 'box_circulate'));
      expect(defaults['who'], 'partners');
      expect(defaults['hand'], 'right');
      expect(defaults['balance'], false);
      expect(defaults['beats'], 4);
    });

    test('default figure validates and renders', () {
      expect(
        tax.validateFigure(
          Figure(
            move: 'box_circulate',
            params: {...tax.effectiveParams(Figure(move: 'box_circulate'))},
          ),
        ),
        isEmpty,
      );
      expect(
        renderer.renderCanonical(Figure(move: 'box_circulate')),
        'partners box circulate',
      );
    });

    test(
      'has no paramBeats (balanced beats come from the cross-line merge)',
      () {
        expect(tax.resolve('box_circulate')!.paramBeats, isNull);
        expect(tax.resolve('box_circulate')!.goodBeats, [4]);
      },
    );

    test('rejects an out-of-domain hand', () {
      final issues = tax.validateFigure(
        Figure(move: 'box_circulate', params: {'hand': 'sideways'}),
      );
      expect(issues.any((i) => i.severity == ValidationSeverity.error), isTrue);
    });

    test('render → re-parse round-trips the recognizer', () {
      final f = Figure(move: 'box_circulate', params: {'who': 'neighbors'});
      final text = renderer.renderCanonical(f); // "neighbors box circulate"
      final reparsed = parseFigureLine(text);
      expect(reparsed, isNotNull);
      expect(reparsed!.isCustom, isFalse);
      expect(reparsed.move, 'box_circulate');
      expect(reparsed.params['who'], 'neighbors');
    });
  });
}
