import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Roadmap PR3b — the additive taxonomy changes that back the CallersBox
/// cross-line merge: a `balance` flag on `box_the_gnat` (inherited by
/// `swat_the_flea` through its target) and a `bendTheLine` value on the down/up
/// the hall `ender`. Both are additive — no existing figure's derived output
/// changes.
void main() {
  final tax = contraTaxonomy;

  bool hasInvalidValue(Figure f) =>
      tax.validateFigure(f).any((i) => i.code == 'invalid_param_value');

  group('box_the_gnat balance flag', () {
    test('box_the_gnat exposes a balance flag defaulting to false', () {
      final def = tax.resolve('box_the_gnat');
      expect(def?.params.containsKey('balance'), isTrue);
      expect(
        tax.effectiveParams(Figure(move: 'box_the_gnat'))['balance'],
        isFalse,
      );
    });

    test('box_the_gnat validates with balance: true', () {
      expect(
        tax.validateFigure(
          Figure(move: 'box_the_gnat', params: {'balance': true}),
        ),
        isEmpty,
      );
    });

    test('box_the_gnat has no paramBeats (stays on the deferral list)', () {
      expect(tax.resolve('box_the_gnat')?.paramBeats, isNull);
    });
  });

  group('swat_the_flea inherits the balance flag', () {
    test('effectiveParams surface the inherited balance (default false) '
        'alongside the pinned left hand', () {
      final params = tax.effectiveParams(Figure(move: 'swat_the_flea'));
      expect(params.containsKey('balance'), isTrue);
      expect(params['balance'], isFalse);
      expect(params['hand'], 'left');
    });

    test('swat_the_flea validates with balance: true', () {
      expect(
        tax.validateFigure(
          Figure(move: 'swat_the_flea', params: {'balance': true}),
        ),
        isEmpty,
      );
    });
  });

  group('bendTheLine ender', () {
    test('down_the_hall accepts bendTheLine as an ender', () {
      expect(
        hasInvalidValue(
          Figure(move: 'down_the_hall', params: {'ender': 'bendTheLine'}),
        ),
        isFalse,
      );
    });

    test('up_the_hall accepts bendTheLine as an ender', () {
      expect(
        hasInvalidValue(
          Figure(move: 'up_the_hall', params: {'ender': 'bendTheLine'}),
        ),
        isFalse,
      );
    });
  });
}
