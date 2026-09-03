import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Issue #290 — split the overloaded `form_an_ocean_wave` into a default
/// short-wave `form_short_waves` ("form a wave") and a distinct
/// `pass_the_ocean` ("pass the ocean"). Both inherit the legacy move's sourced
/// params MINUS `passThru`; neither invents a beat count. As of taxonomy v14 the
/// legacy `form_an_ocean_wave` MoveDef is REMOVED; stored figures that reference
/// it are rewritten onto the split moves by the schema-v12 migration (see
/// database.dart / migration_test.dart). This file asserts the split moves and
/// that the legacy id is gone from the taxonomy.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const splitMoves = ['form_short_waves', 'pass_the_ocean'];

  // The sourced param set both new moves inherit from form_an_ocean_wave,
  // minus `passThru` (intrinsic to pass_the_ocean, absent from the short wave).
  const inheritedParams = [
    'dir',
    'balance',
    'center',
    'centerHand',
    'sides',
    'beats',
  ];

  group('registration & defaults', () {
    for (final id in splitMoves) {
      test('$id resolves and validates with all defaults populated', () {
        expect(tax.resolve(id)?.id, id, reason: '$id should be registered');
        final defaults = tax.effectiveParams(testFigure(move: id));
        expect(
          tax.validateFigure(testFigure(move: id, params: defaults)),
          isEmpty,
          reason: '$id default param values must all be in-domain',
        );
      });

      test('$id inherits form_an_ocean_wave params minus passThru', () {
        final params = tax.resolve(id)!.params;
        expect(
          params.keys.toSet(),
          inheritedParams.toSet(),
          reason: '$id should carry exactly the inherited param set',
        );
        expect(
          params.containsKey('passThru'),
          isFalse,
          reason: 'passThru is intrinsic/absent, never a param on $id',
        );
      });

      test('$id keeps the intended split-move defaults', () {
        final shortWave = tax.resolve('form_short_waves')!.params;
        final passTheOcean = tax.resolve('pass_the_ocean')!.params;
        for (final key in inheritedParams.where((key) => key != 'centerHand')) {
          expect(
            shortWave[key]!.defaultValue,
            passTheOcean[key]!.defaultValue,
            reason: '$key remains shared by the split moves',
          );
        }
        const expectedCenterHand = 'left';
        expect(
          tax.resolve(id)!.params['centerHand']!.defaultValue,
          expectedCenterHand,
        );
      });

      test(
        '$id accepts any beats (param-dependent, unencoded like legacy)',
        () {
          expect(tax.resolve(id)!.goodBeats, anyOf(isNull, isEmpty));
          expect(
            tax.validateFigure(testFigure(move: id, params: {'beats': 8})),
            isEmpty,
          );
        },
      );
    }
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'form short waves': Figure(move: 'form_short_waves'),
      'pass the ocean': Figure(move: 'pass_the_ocean'),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });

    test(
      'both accept the balance flag without changing the canonical text',
      () {
        for (final id in splitMoves) {
          final expected = renderer.renderCanonical(testFigure(move: id));
          expect(
            renderer.renderCanonical(
              testFigure(move: id, params: {'balance': true}),
            ),
            expected,
            reason: 'balance is structured-only for $id',
          );
        }
      },
    );
  });

  group('legacy form_an_ocean_wave removed (v14 / schema v12 migration)', () {
    test('no longer resolves in the taxonomy', () {
      expect(tax.resolve('form_an_ocean_wave'), isNull);
    });

    test('an unknown-move figure renders losslessly via the #358 fallback', () {
      // Stored figures are migrated away by schema v12; any that somehow slip
      // through resolve to the non-throwing raw-id fallback (issue #358) rather
      // than crashing.
      // invalid-fixture: move is deliberately outside the taxonomy — an unknown-move figure renders losslessly via the #358 fallback
      final figure = Figure(move: 'form_an_ocean_wave');
      expect(renderer.renderCanonical(figure), 'form_an_ocean_wave');
    });

    test('no alias resurrects the legacy id', () {
      expect(tax.aliases.containsKey('form_an_ocean_wave'), isFalse);
    });
  });
}
