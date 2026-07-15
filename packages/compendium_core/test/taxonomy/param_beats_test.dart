import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Param-value-dependent beat counts (ContraDB-sourced). Only a handful of
/// moves carry a [MoveDef.paramBeats] table; [Taxonomy.effectiveParams] derives
/// `beats` from the driver param's effective value when the figure does not
/// pin `beats`.
void main() {
  final tax = contraTaxonomy;

  int beatsFor(String move, [Map<String, Object?> params = const {}]) =>
      tax.effectiveParams(Figure(move: move, params: params))['beats'] as int;

  group('hey length -> beats (ContraDB heyLengthMeetTimes * 8)', () {
    test('lessThanHalf and half are 8 (meetTimes 1)', () {
      expect(beatsFor('hey', {'length': 'lessThanHalf'}), 8);
      expect(beatsFor('hey', {'length': 'half'}), 8);
    });

    test('betweenHalfAndFull and full are 16 (meetTimes 2)', () {
      expect(beatsFor('hey', {'length': 'betweenHalfAndFull'}), 16);
      expect(beatsFor('hey', {'length': 'full'}), 16);
    });

    test('default (half) derives the flat spec default of 8', () {
      expect(beatsFor('hey'), 8);
    });

    test('an explicit beats value wins over the derived count', () {
      expect(beatsFor('hey', {'length': 'full', 'beats': 12}), 12);
    });
  });

  group('figure_8 half -> beats (ContraDB half_or_full * 16)', () {
    test('half is 8, full is 16', () {
      expect(beatsFor('figure_8', {'half': 'half'}), 8);
      expect(beatsFor('figure_8', {'half': 'full'}), 16);
    });

    test('default (half) derives the flat spec default of 8', () {
      expect(beatsFor('figure_8'), 8);
    });

    test('an explicit beats value wins over the derived count', () {
      expect(beatsFor('figure_8', {'half': 'full', 'beats': 8}), 8);
    });
  });

  group('rory_o_more balance -> beats (ContraDB balance ? 8 : 4)', () {
    test('balanced is 8, unbalanced is 4', () {
      expect(beatsFor('rory_o_more', {'balance': true}), 8);
      expect(beatsFor('rory_o_more', {'balance': false}), 4);
    });

    test('default (balanced) derives the flat spec default of 8', () {
      expect(beatsFor('rory_o_more'), 8);
    });

    test('an explicit beats value wins over the derived count', () {
      expect(beatsFor('rory_o_more', {'balance': false, 'beats': 8}), 8);
    });
  });

  group('slice return -> beats (ContraDB none ? 4 : 8)', () {
    test('a returning slice is 8, no return is 4', () {
      expect(beatsFor('slice', {'return': 'straight'}), 8);
      expect(beatsFor('slice', {'return': 'diagonal'}), 8);
      expect(beatsFor('slice', {'return': 'none'}), 4);
    });

    test('default (straight) derives the flat spec default of 8', () {
      expect(beatsFor('slice'), 8);
    });
  });

  group('deferred moves keep a flat default (no paramBeats)', () {
    test('poussette, the places family, and turn_alone have no paramBeats', () {
      for (final id in const [
        'poussette',
        'circle',
        'star',
        'facing_star',
        'square_through',
        'turn_alone',
      ]) {
        expect(tax.resolve(id)!.paramBeats, isNull, reason: id);
      }
    });
  });

  group('paramBeats data shape', () {
    test('hey drives beats off its length param', () {
      final pb = tax.resolve('hey')!.paramBeats!;
      expect(pb.param, 'length');
      expect(pb.byValue, {
        'lessThanHalf': 8,
        'half': 8,
        'betweenHalfAndFull': 16,
        'full': 16,
      });
    });

    test('figure_8 drives beats off its half param', () {
      final pb = tax.resolve('figure_8')!.paramBeats!;
      expect(pb.param, 'half');
      expect(pb.byValue, {'half': 8, 'full': 16});
    });

    test('rory_o_more drives beats off its balance flag', () {
      final pb = tax.resolve('rory_o_more')!.paramBeats!;
      expect(pb.param, 'balance');
      expect(pb.byValue, {true: 8, false: 4});
    });

    test('slice drives beats off its return param', () {
      final pb = tax.resolve('slice')!.paramBeats!;
      expect(pb.param, 'return');
      expect(pb.byValue, {'straight': 8, 'diagonal': 8, 'none': 4});
    });

    test('a move with a flat default has no paramBeats', () {
      expect(tax.resolve('swing')!.paramBeats, isNull);
    });
  });
}
