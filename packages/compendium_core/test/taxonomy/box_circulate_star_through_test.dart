import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// PR5 (parser overhaul) added `box_circulate` (ContraDB-sourced, modeled on
/// `box_the_gnat`) and `star_through` in contraTaxonomyVersion 11. `box_circulate`
/// carries a neutral `balance` flag whose balanced beat count comes only from the
/// CallersBox cross-line merge, so it takes no `paramBeats`. v12: `star_through`
/// now mirrors `california_twirl` (who + beats only, no balance) per product
/// decision. v14: the legacy `form_an_ocean_wave` MoveDef was removed (its #290
/// split replacements remain), with stored figures migrated by schema v12.
/// v15: adds the TCB rotation-gate figure kind `rotation_gate` (issue #294).
/// v16: adds the additive `endFacing` param to `swing` (issue #543).
/// v17: adds the additive `meetTarget` param to `hey` (issue #576).
/// v18: adds the additive `singleFile` flag to `promenade` and `circle`, plus
/// extends `give_and_take.goodBeats` with `2` (issue #634).
/// v19: splits the fused `allemande_orbit` into a first-class `orbit` move; the
/// combined figure is now modeled as `meanwhile[allemande, orbit]` and stored
/// fused figures are migrated by schema v18 (issue #295).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  test('contraTaxonomyVersion is 32', () {
    expect(contraTaxonomyVersion, 32);
    expect(tax.version, 32);
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
          testFigure(
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
        // invalid-fixture: value is deliberately out of domain — rejects an out-of-domain hand
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

  group('star_through', () {
    test('registers as a california_twirl-style move (no balance param)', () {
      final def = tax.resolve('star_through');
      expect(def, isNotNull);
      expect(def!.params.keys, containsAll(['who', 'beats']));
      expect(
        def.params.containsKey('balance'),
        isFalse,
        reason: 'v12: star through mirrors california twirl — no balance param',
      );
      expect(
        def.params.containsKey('hand'),
        isFalse,
        reason: 'star through handedness is role-fixed, like california twirl',
      );
      final defaults = tax.effectiveParams(Figure(move: 'star_through'));
      expect(defaults['who'], 'partners');
      expect(defaults.containsKey('balance'), isFalse);
      expect(defaults['beats'], 4);
    });

    test('default figure validates and renders', () {
      expect(
        tax.validateFigure(
          testFigure(
            move: 'star_through',
            params: {...tax.effectiveParams(Figure(move: 'star_through'))},
          ),
        ),
        isEmpty,
      );
      expect(
        renderer.renderCanonical(Figure(move: 'star_through')),
        'partners star through',
      );
    });

    test('has no paramBeats (fixed 4-beat move, like california twirl)', () {
      expect(tax.resolve('star_through')!.paramBeats, isNull);
      expect(tax.resolve('star_through')!.goodBeats, [4]);
    });

    test('a parsed "star through" carries no balance param', () {
      final reparsed = parseFigureLine('star through');
      expect(reparsed, isNotNull);
      expect(reparsed!.isCustom, isFalse);
      expect(reparsed.move, 'star_through');
      expect(reparsed.params.containsKey('balance'), isFalse);
    });

    test('render → re-parse round-trips the recognizer', () {
      final f = Figure(move: 'star_through', params: {'who': 'neighbors'});
      final text = renderer.renderCanonical(f);
      final reparsed = parseFigureLine(text);
      expect(reparsed, isNotNull);
      expect(reparsed!.isCustom, isFalse);
      expect(reparsed.move, 'star_through');
      expect(reparsed.params['who'], 'neighbors');
    });
  });
}
