import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

import 'chain_follows_reach_test.dart' show heathersHop;

/// Chorus Jig (Caller's Box #3418), as the bridge reads it: a Duple Proper
/// dance whose last figure is "Ones swing; face up".
Map<String, Object?> chorusJig({String? endFacing = 'up'}) => {
  'title': 'Chorus Jig',
  'form': 'contra',
  'formation': {'shape': 'dupleProper'},
  'progression': 'single',
  'figures': [
    {
      'move': 'down_the_hall',
      'params': {'who': 'ones', 'moving': 'outsides', 'ender': 'none'},
    },
    {
      'move': 'up_the_hall',
      'params': {'who': 'ones', 'moving': 'outsides', 'ender': 'none'},
    },
    {
      'move': 'down_the_hall',
      'params': {'who': 'ones', 'moving': 'center', 'ender': 'turnAlone'},
    },
    {
      'move': 'up_the_hall',
      'params': {'who': 'ones', 'moving': 'center', 'ender': 'none'},
    },
    {
      'move': 'cast',
      'params': {'who': 'ones', 'direction': 'down', 'places': 1},
    },
    {
      'move': 'contra_corners',
      'params': {'who': 'ones'},
    },
    {
      'move': 'swing',
      'params': {'who': 'ones', 'prefix': 'balance', 'endFacing': ?endFacing},
      'progression': true,
    },
  ],
};

CompileResult _compile(Map<String, Object?> record) =>
    compile((parseDance(record) as Ok<Dance, DanceParseError>).value);

Map<String, Object?> _withShape(Map<String, Object?> record, String shape) => {
  ...record,
  'formation': {'shape': shape},
};

void main() {
  group('a Duple Proper dance starts proper (user-ruled 2026-11-24)', () {
    test("Heather's Hop Redux compiles", () {
      // "The dance is proper. The ones do end improper after they swing, and
      // the half figure eight at the end gets them proper again."
      expect(_compile(heathersHop()), isA<Compiled>());
    });

    test('the compile is discriminating: started improper, it mismatches', () {
      expect(
        _compile(_withShape(heathersHop(), 'dupleImproper')),
        isA<Mismatch>(),
      );
    });
  });

  group('a swing that ends "face up" finishes facing up', () {
    test('Chorus Jig compiles: the 1s swing back to proper', () {
      expect(_compile(chorusJig()), isA<Compiled>());
    });

    test('without the facing, the 1s end improper and it mismatches', () {
      expect(_compile(chorusJig(endFacing: null)), isA<Mismatch>());
    });
  });
}
