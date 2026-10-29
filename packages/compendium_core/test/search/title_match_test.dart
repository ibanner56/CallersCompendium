import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  TitleMatchRank? rank(String title, String query, {bool articles = true}) =>
      rankTitleMatch(title, query, ignoreLeadingArticles: articles);

  group('foldForTitleMatch', () {
    test('lowercases and drops combining marks, precomposed or not', () {
      expect(foldForTitleMatch('École'), 'ecole');
      expect(foldForTitleMatch('Café'), 'cafe');
      expect(foldForTitleMatch('Über'), 'uber');
    });
  });

  group('rankTitleMatch', () {
    test('exact beats prefix beats substring', () {
      expect(rank('Hey', 'hey'), TitleMatchRank.exact);
      expect(rank('Heyday', 'hey'), TitleMatchRank.prefix);
      expect(rank('Cheyenne', 'hey'), TitleMatchRank.substring);
      expect(rank('Rolling Off a Log', 'zzz'), isNull);
    });

    test('folds diacritics on both sides', () {
      expect(rank('École Reel', 'ecole'), TitleMatchRank.prefix);
      expect(rank('Ecole Reel', 'ÉCOLE'), TitleMatchRank.prefix);
    });

    test(
      'a leading article is ignored for exact and prefix, not substring',
      () {
        expect(rank('The Nice Combination', 'nice'), TitleMatchRank.prefix);
        expect(rank('The Hey', 'hey'), TitleMatchRank.exact);
        expect(rank('The Nice Combination', 'the'), TitleMatchRank.prefix);
        expect(rank('Is The Nice One', 'nice'), TitleMatchRank.substring);
      },
    );

    test('keeps the article when the setting is off', () {
      expect(
        rank('The Nice Combination', 'nice', articles: false),
        TitleMatchRank.substring,
      );
    });

    test('an empty query matches everything', () {
      expect(rank('Anything', '  '), isNotNull);
    });
  });
}
