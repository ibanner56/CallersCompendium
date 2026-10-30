import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// [frontTrailingArticle] and its use by [mapCallersCompanionDance] (#1976
/// items 1 and 6).
void main() {
  group('frontTrailingArticle', () {
    test('moves each listed article to the front', () {
      expect(frontTrailingArticle('Baby Rose, The'), 'The Baby Rose');
      expect(frontTrailingArticle('Bastringue, La'), 'La Bastringue');
      expect(frontTrailingArticle('Thing of Trust, A'), 'A Thing of Trust');
      expect(frontTrailingArticle('Old Favorite, An'), 'An Old Favorite');
      expect(frontTrailingArticle('Petit Bal, Le'), 'Le Petit Bal');
      expect(frontTrailingArticle('Lanciers, Les'), 'Les Lanciers');
    });

    test("joins an elided L' without a space, either apostrophe", () {
      expect(frontTrailingArticle("Amour, L'"), "L'Amour");
      expect(frontTrailingArticle('Amour, L’'), 'L’Amour');
    });

    test('keeps a bracketed annotation at the end', () {
      expect(
        frontTrailingArticle('Baby Rose, The (var)'),
        'The Baby Rose (var)',
      );
      expect(
        frontTrailingArticle('Baby Rose, The [alt]'),
        'The Baby Rose [alt]',
      );
    });

    test('capitalises an article written in lower case', () {
      expect(frontTrailingArticle('Baby Rose, the'), 'The Baby Rose');
    });

    test('only the article after the last comma moves', () {
      expect(frontTrailingArticle('Rose, Rose, The'), 'The Rose, Rose');
    });

    test('leaves every other title unchanged', () {
      for (final title in [
        'The Baby Rose',
        'Sharks in the Pond (var)',
        'Hey, Ho',
        'Reel, A1',
        'Theme, Then',
        ', The',
        'Trip, The(let)',
        'Contra, Der',
        '',
      ]) {
        expect(frontTrailingArticle(title), title, reason: title);
      }
    });
  });

  group('mapCallersCompanionDance', () {
    test('fronts the article of a library-style title', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(name: 'Baby Rose, The', fromUsrColumns: true),
      );
      expect(mapping.dance.title, 'The Baby Rose');
    });

    test('the missing-title warning does not say the dance was pasted', () {
      final mapping = mapCallersCompanionDance(
        CcDanceRecord(name: '', fromUsrColumns: true),
      );
      final issue = mapping.issues.singleWhere(
        (i) => i.code == 'cc_missing_title',
      );
      expect(issue.message, isNot(contains('pasted')));
      expect(issue.message, contains(ccUntitledDanceTitle));
    });
  });
}
