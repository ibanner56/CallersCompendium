import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #290 — split the overloaded `form_an_ocean_wave` into a default
/// short-wave `form_a_short_wave` ("form a wave") and a distinct
/// `pass_the_ocean` ("pass the ocean"). Both inherit the legacy move's sourced
/// params MINUS `passThru`; neither invents a beat count. The legacy move is
/// RETAINED unchanged so stored figures keep rendering byte-identically
/// (additive taxonomy bump v12 -> v13; no schemaVersion / DB migration).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  const splitMoves = ['form_a_short_wave', 'pass_the_ocean'];

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
        final defaults = tax.effectiveParams(Figure(move: id));
        expect(
          tax.validateFigure(Figure(move: id, params: defaults)),
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

      test('$id mirrors the legacy move param specs (no invented values)', () {
        final legacy = tax.resolve('form_an_ocean_wave')!.params;
        final params = tax.resolve(id)!.params;
        for (final key in inheritedParams) {
          expect(
            params[key]!.defaultValue,
            legacy[key]!.defaultValue,
            reason: '$id.$key default must match form_an_ocean_wave',
          );
        }
      });

      test(
        '$id accepts any beats (param-dependent, unencoded like legacy)',
        () {
          expect(tax.resolve(id)!.goodBeats, anyOf(isNull, isEmpty));
          expect(
            tax.validateFigure(Figure(move: id, params: {'beats': 8})),
            isEmpty,
          );
        },
      );
    }
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'form a wave': Figure(move: 'form_a_short_wave'),
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
          final expected = renderer.renderCanonical(Figure(move: id));
          expect(
            renderer.renderCanonical(
              Figure(move: id, params: {'balance': true}),
            ),
            expected,
            reason: 'balance is structured-only for $id',
          );
        }
      },
    );
  });

  group('backward compatibility — legacy form_an_ocean_wave retained', () {
    test('still resolves with passThru default true (unchanged)', () {
      final def = tax.resolve('form_an_ocean_wave');
      expect(def?.id, 'form_an_ocean_wave');
      expect(def!.params['passThru']!.defaultValue, true);
    });

    test('bare legacy figure renders byte-identically', () {
      expect(
        renderer.renderCanonical(Figure(move: 'form_an_ocean_wave')),
        'form an ocean wave',
      );
    });

    test('legacy figure with stored params still validates and renders', () {
      final figure = Figure(
        move: 'form_an_ocean_wave',
        params: {
          'passThru': false,
          'dir': 'rightDiagonal',
          'centerHand': 'left',
          'center': 'role1s',
          'sides': 'partners',
          'balance': true,
          'beats': 8,
        },
      );
      expect(tax.validateFigure(figure), isEmpty);
      expect(renderer.renderCanonical(figure), 'form an ocean wave');
    });

    test('no alias hijacks the legacy id to a new move', () {
      expect(tax.resolve('form_an_ocean_wave')!.id, 'form_an_ocean_wave');
    });
  });
}
