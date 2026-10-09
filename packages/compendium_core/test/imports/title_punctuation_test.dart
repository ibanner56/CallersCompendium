import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the online-source title punctuation helpers. The punctuation each
/// source stores was measured live; see `title_punctuation.dart`.
void main() {
  group('foldTitlePunctuation', () {
    test('folds every apostrophe variant to ASCII', () {
      for (final c in [
        '\u2019',
        '\u2018',
        '\u201B',
        '\u02BC',
        '\u02BB',
        '\u2032',
        '`',
        '\u00B4',
      ]) {
        expect(
          foldTitlePunctuation('Rory O${c}More'),
          "Rory O'More",
          reason: c,
        );
      }
    });

    test('folds double quotes, dashes, the ellipsis and odd spaces', () {
      expect(
        foldTitlePunctuation('\u201CRevolving Poussette\u201D'),
        '"Revolving Poussette"',
      );
      expect(foldTitlePunctuation('\u201EBy George\u201F'), '"By George"');
      for (final c in [
        '\u2010',
        '\u2011',
        '\u2012',
        '\u2013',
        '\u2014',
        '\u2015',
        '\u2212',
      ]) {
        expect(foldTitlePunctuation('Merry${c}Go'), 'Merry-Go', reason: c);
      }
      expect(foldTitlePunctuation('Backwards\u2026'), 'Backwards...');
      expect(
        foldTitlePunctuation('Money\u00A0Musk\u202FReel'),
        'Money Musk Reel',
      );
    });

    test('leaves letters, accents, case and ASCII punctuation alone', () {
      const title = "D\u00E9j\u00E0 Vu (Bob's \"Var\") - A&B #2!";
      expect(foldTitlePunctuation(title), title);
    });
  });

  group('titleMatchKey', () {
    test('equates titles differing only in case, spacing or quote style', () {
      expect(
        titleMatchKey("  Rory  O'More "),
        titleMatchKey('rory o\u2019more'),
      );
      expect(
        titleMatchKey('\u201CRevolving Poussette\u201D'),
        titleMatchKey('"revolving poussette"'),
      );
    });

    test('keeps the punctuation and articles that make titles distinct', () {
      expect(titleMatchKey('The Archive'), isNot(titleMatchKey('Archive')));
      expect(titleMatchKey("Bob's Reel"), isNot(titleMatchKey('Bobs Reel')));
    });
  });

  group('contraDbTitleQueryVariants', () {
    test('a query without quotes is sent once, folded', () {
      expect(contraDbTitleQueryVariants('Petronella'), ['Petronella']);
      expect(contraDbTitleQueryVariants('Merry\u2013Go'), ['Merry-Go']);
    });

    test('an apostrophe is sent straight and curly, whichever was typed', () {
      const both = ["Eleanor's Reel", 'Eleanor\u2019s Reel'];
      expect(contraDbTitleQueryVariants("Eleanor's Reel"), both);
      expect(contraDbTitleQueryVariants('Eleanor\u2019s Reel'), both);
    });

    test('double quotes curl as opening or closing by position', () {
      expect(contraDbTitleQueryVariants('"Revolving Poussette"'), [
        '"Revolving Poussette"',
        '\u201CRevolving Poussette\u201D',
      ]);
      expect(contraDbTitleQueryVariants("Lawn (\"Rod's\" var)"), [
        "Lawn (\"Rod's\" var)",
        'Lawn (\u201CRod\u2019s\u201D var)',
      ]);
    });
  });

  test('canonicalContraDbFigureQuery accepts a curly apostrophe', () {
    expect(canonicalContraDbFigureQuery('Rory O\u2019More'), "Rory O'More");
  });
}
