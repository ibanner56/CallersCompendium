import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('toFtsMatchQuery', () {
    test('wraps a single term in a phrase', () {
      expect(toFtsMatchQuery('swing'), '"swing"');
    });

    test('quotes each whitespace token, preserving implicit AND', () {
      expect(toFtsMatchQuery('right left'), '"right" "left"');
    });

    test(
      'neutralizes hyphens so contra terms never reach FTS as operators',
      () {
        expect(toFtsMatchQuery('do-si-do'), '"do-si-do"');
        expect(toFtsMatchQuery('right-and-left'), '"right-and-left"');
      },
    );

    test('neutralizes apostrophes', () {
      expect(toFtsMatchQuery("O'Neill"), '"O\'Neill"');
    });

    test('escapes embedded double quotes by doubling', () {
      expect(toFtsMatchQuery('foo"'), '"foo"""');
      expect(toFtsMatchQuery('a"b'), '"a""b"');
    });

    test('treats operator keywords as literal phrases', () {
      expect(toFtsMatchQuery('AND'), '"AND"');
      expect(toFtsMatchQuery('NEAR OR NOT'), '"NEAR" "OR" "NOT"');
    });

    test('collapses runs of whitespace and trims', () {
      expect(toFtsMatchQuery('  swing   partners  '), '"swing" "partners"');
    });

    test('empty or whitespace-only yields the safe empty phrase', () {
      expect(toFtsMatchQuery(''), '""');
      expect(toFtsMatchQuery('   '), '""');
    });
  });
}
