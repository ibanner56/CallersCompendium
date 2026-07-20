import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseInlineEmphasis', () {
    test('plain text is a single unstyled span', () {
      expect(parseInlineEmphasis('neighbors allemande left'), const [
        EmphasisSpan(text: 'neighbors allemande left'),
      ]);
    });

    test('empty input yields no spans', () {
      expect(parseInlineEmphasis(''), isEmpty);
    });

    test('bold', () {
      expect(parseInlineEmphasis('say *this* loud'), const [
        EmphasisSpan(text: 'say '),
        EmphasisSpan(text: 'this', bold: true),
        EmphasisSpan(text: ' loud'),
      ]);
    });

    test('underline', () {
      expect(parseInlineEmphasis('_key_ words'), const [
        EmphasisSpan(text: 'key', underline: true),
        EmphasisSpan(text: ' words'),
      ]);
    });

    test('bold and underline in one string', () {
      expect(parseInlineEmphasis('*a* and _b_'), const [
        EmphasisSpan(text: 'a', bold: true),
        EmphasisSpan(text: ' and '),
        EmphasisSpan(text: 'b', underline: true),
      ]);
    });

    test('nested bold + underline sets both flags', () {
      expect(parseInlineEmphasis('*_x_*'), const [
        EmphasisSpan(text: 'x', bold: true, underline: true),
      ]);
    });

    test('nested emphasis toggles independently within a bold span', () {
      // Bold spans the whole phrase; an underline nests on "b" inside it.
      expect(parseInlineEmphasis('*a _b_ c*'), const [
        EmphasisSpan(text: 'a ', bold: true),
        EmphasisSpan(text: 'b', bold: true, underline: true),
        EmphasisSpan(text: ' c', bold: true),
      ]);
    });

    group('escaping', () {
      test('escaped star is literal', () {
        expect(parseInlineEmphasis(r'2 \* 3'), const [
          EmphasisSpan(text: '2 * 3'),
        ]);
      });

      test('escaped underscore is literal', () {
        expect(parseInlineEmphasis(r'a\_b'), const [EmphasisSpan(text: 'a_b')]);
      });

      test('escaped backslash is literal', () {
        expect(parseInlineEmphasis(r'a\\b'), const [
          EmphasisSpan(text: r'a\b'),
        ]);
      });

      test('trailing backslash is literal', () {
        expect(parseInlineEmphasis(r'path\'), const [
          EmphasisSpan(text: r'path\'),
        ]);
      });

      test('escaped delimiter does not close a pair', () {
        // The first * opens; the escaped \* is literal; nothing closes -> the
        // opening * is emitted literally.
        expect(stripInlineEmphasis(r'*a\*'), '*a*');
      });
    });

    group('malformed / adversarial input never throws', () {
      final samples = <String>[
        '*abc',
        '_abc',
        'abc*',
        'abc_',
        '*',
        '_',
        '***',
        '___',
        '****',
        '*_*_',
        '_*_*',
        r'\\\\',
        r'\\\*',
        '*' * 5000,
        '_' * 5000,
        '*_' * 5000,
        List.filled(2000, r'a\').join(),
        'emoji 😀 *bold 🎶* end',
        'café _naïve_ résumé',
        '\u0000 null \u0000',
      ];
      for (var i = 0; i < samples.length; i++) {
        test('sample #$i does not throw', () {
          expect(() => parseInlineEmphasis(samples[i]), returnsNormally);
          expect(() => stripInlineEmphasis(samples[i]), returnsNormally);
        });
      }
    });

    test('unterminated delimiters render literally', () {
      expect(stripInlineEmphasis('*abc'), '*abc');
      expect(stripInlineEmphasis('_abc'), '_abc');
      expect(stripInlineEmphasis('a*b'), 'a*b');
    });

    test('spans are never empty and adjacent same-style runs coalesce', () {
      final spans = parseInlineEmphasis('*a**b*');
      expect(spans.every((s) => s.text.isNotEmpty), isTrue);
      // *a* -> a(bold); ** -> toggles bold off then on (empty run dropped);
      // b -> bold. Result is a single coalesced bold "ab".
      expect(spans, const [EmphasisSpan(text: 'ab', bold: true)]);
    });

    group('flanking guards protect pre-existing note text (issue #369)', () {
      test('intra-word underscores stay literal (do_si_do)', () {
        expect(parseInlineEmphasis('do_si_do'), const [
          EmphasisSpan(text: 'do_si_do'),
        ]);
      });

      test('single intra-word underscore stays literal', () {
        expect(parseInlineEmphasis('allemande_left'), const [
          EmphasisSpan(text: 'allemande_left'),
        ]);
        expect(parseInlineEmphasis('star_thru'), const [
          EmphasisSpan(text: 'star_thru'),
        ]);
        expect(parseInlineEmphasis('gents_do_si_do'), const [
          EmphasisSpan(text: 'gents_do_si_do'),
        ]);
      });

      test('space-flanked asterisks stay literal (star * 2 * couples)', () {
        expect(parseInlineEmphasis('star * 2 * couples'), const [
          EmphasisSpan(text: 'star * 2 * couples'),
        ]);
      });

      test('bare/space-flanked asterisk stays literal (hey * 4)', () {
        expect(parseInlineEmphasis('hey * 4'), const [
          EmphasisSpan(text: 'hey * 4'),
        ]);
      });

      test('word-boundary emphasis still works', () {
        expect(parseInlineEmphasis('*bold*'), const [
          EmphasisSpan(text: 'bold', bold: true),
        ]);
        expect(parseInlineEmphasis('_underline_'), const [
          EmphasisSpan(text: 'underline', underline: true),
        ]);
        expect(parseInlineEmphasis('word *bold* word'), const [
          EmphasisSpan(text: 'word '),
          EmphasisSpan(text: 'bold', bold: true),
          EmphasisSpan(text: ' word'),
        ]);
        expect(parseInlineEmphasis('see _this_ move'), const [
          EmphasisSpan(text: 'see '),
          EmphasisSpan(text: 'this', underline: true),
          EmphasisSpan(text: ' move'),
        ]);
      });

      test('nesting and escaping still work after flanking guards', () {
        expect(parseInlineEmphasis('*_x_*'), const [
          EmphasisSpan(text: 'x', bold: true, underline: true),
        ]);
        expect(stripInlineEmphasis(r'\*'), '*');
        expect(stripInlineEmphasis(r'\_'), '_');
      });
    });
  });

  group('stripInlineEmphasis', () {
    test('equals concatenation of parsed span text', () {
      const inputs = [
        'plain',
        '*bold* and _under_',
        r'esc \* \_ \\',
        '*unterminated',
        '*_nested_*',
      ];
      for (final input in inputs) {
        final joined = parseInlineEmphasis(input).map((s) => s.text).join();
        expect(stripInlineEmphasis(input), joined, reason: input);
      }
    });
  });

  group('round-trip through figure_codec is byte-identical', () {
    test('markup in note and custom text survives encode/decode', () {
      final figures = <Figure>[
        Figure(
          move: 'swing',
          note: 'say *this* and _that_',
          params: const {'beats': 16},
        ),
        Figure(
          move: customMove,
          params: const {'text': r'gents \* _ladies_ *cross*', 'beats': 8},
        ),
      ];
      final encoded = encodeFigures(figures);
      final decoded = decodeFigures(encoded);
      expect(decoded, figures);
      expect(decoded[0].note, 'say *this* and _that_');
      expect(decoded[1].params['text'], r'gents \* _ladies_ *cross*');
      // Re-encoding is byte-stable.
      expect(encodeFigures(decoded), encoded);
    });
  });
}
