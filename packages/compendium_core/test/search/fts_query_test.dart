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

    test('neutralizes grouping, prefix, column, and caret syntax', () {
      // The doc comment promises `( ) : * ^` are all defused; each stays inside
      // its quoted phrase so FTS5 can never read it as grouping, a prefix query,
      // a column filter, or an initial-token match.
      expect(toFtsMatchQuery('(swing)'), '"(swing)"');
      expect(toFtsMatchQuery('swing*'), '"swing*"');
      expect(toFtsMatchQuery('title:swing'), '"title:swing"');
      expect(toFtsMatchQuery('^swing'), '"^swing"');
    });

    test('quotes an unbalanced parenthesis token rather than grouping', () {
      // A lone `(` or `)` is FTS5 grouping syntax that would otherwise be an
      // unbalanced-parens syntax error.
      expect(toFtsMatchQuery('(swing'), '"(swing"');
      expect(toFtsMatchQuery('swing)'), '"swing)"');
    });

    test('collapses runs of whitespace and trims', () {
      expect(toFtsMatchQuery('  swing   partners  '), '"swing" "partners"');
    });

    test('empty or whitespace-only yields the safe empty phrase', () {
      expect(toFtsMatchQuery(''), '""');
      expect(toFtsMatchQuery('   '), '""');
    });
  });

  group('scoped query builders', () {
    test('builds safe token prefixes', () {
      expect(toFtsPrefixMatchQuery('Al'), '"Al"*');
      expect(toFtsPrefixMatchQuery('right left'), '"right"* "left"*');
      expect(toFtsPrefixMatchQuery('foo"'), '"foo"""*');
    });

    test('keeps a long substring query as one literal phrase', () {
      expect(toFtsSubstringMatchQuery('man {alter'), '"man {alter"');
      expect(toFtsSubstringMatchQuery('foo"bar'), '"foo""bar"');
    });

    test('counts trimmed Unicode scalar values', () {
      expect(ftsQueryScalarLength('  Al  '), 2);
      expect(ftsQueryScalarLength('é'), 1);
      expect(ftsQueryScalarLength(''), 0);
    });
  });
}
