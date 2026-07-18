import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #347 — revolving-door **text parity** with ContraDB.
///
/// ContraDB #2443 renders the figure clearly: "revolving door - ladles take
/// right hands and drop off partners on other side". Our previous terse render
/// ("ones revolving door left neighbors") had the wrong hand and vague dancers.
/// These tests pin the corrected canonical figure: RIGHT hands, the ladles
/// (role2s) leading, dropping off partners, plus the ContraDB-parity outcome
/// clarifier surfaced by [FigureRenderer.renderSummary].
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  test('default hand is right (was left) and validates cleanly', () {
    final def = tax.resolve('revolving_door')!;
    expect(def.params['hand']!.defaultValue, 'right');
    expect(def.params['who']!.defaultValue, 'role2s');
    expect(def.params['whom']!.defaultValue, 'partners');
    expect(tax.validateFigure(Figure(move: 'revolving_door')), isEmpty);
  });

  test('canonical render uses right hand + the ladles/partners defaults', () {
    expect(
      renderer.renderCanonical(Figure(move: 'revolving_door')),
      'role2s revolving door right partners',
    );
  });

  test('display render maps role tokens under a dialect', () {
    expect(
      renderer.render(Figure(move: 'revolving_door'), Dialect.larksRobins),
      'robins revolving door right partners',
    );
  });

  test('renderSummary adds the ContraDB-parity drop-off clarifier', () {
    final summary = renderer.renderSummary(
      Figure(move: 'revolving_door'),
      Dialect.canonical,
    );
    expect(
      summary,
      'role2s revolving door right partners — drop off on the other side',
    );
  });

  test(
    'an explicit left-hand value is still honored (param not hard-coded)',
    () {
      expect(
        renderer.renderCanonical(
          Figure(move: 'revolving_door', params: {'hand': 'left'}),
        ),
        'role2s revolving door left partners',
      );
    },
  );

  test('atypical beats stay a warning, source beats preserved', () {
    final issues = tax.validateFigure(
      Figure(move: 'revolving_door', params: {'beats': 6}),
    );
    expect(issues.single.severity, ValidationSeverity.warning);
  });
}
