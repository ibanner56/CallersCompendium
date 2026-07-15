import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('titleSortKey', () {
    test('strips a leading "the"', () {
      expect(titleSortKey('The Nice Combination'), 'nice combination');
    });

    test('strips a leading "a"', () {
      expect(titleSortKey('A Fine Romance'), 'fine romance');
    });

    test('strips a leading "an"', () {
      expect(titleSortKey('An Dro'), 'dro');
    });

    test('is case-insensitive for the article', () {
      expect(titleSortKey('THE Rose'), 'rose');
      expect(titleSortKey('the rose'), 'rose');
    });

    test('does not strip an article without a following space', () {
      expect(titleSortKey('Anaconda'), 'anaconda');
      expect(titleSortKey('Answer'), 'answer');
      expect(titleSortKey('Alpha'), 'alpha');
    });

    test('does not strip when nothing would remain', () {
      expect(titleSortKey('The'), 'the');
      expect(titleSortKey('A'), 'a');
      expect(titleSortKey('An'), 'an');
      expect(titleSortKey('The   '), 'the');
    });

    test('only strips the first leading article', () {
      expect(titleSortKey('The A Team'), 'a team');
    });

    test('trims surrounding whitespace', () {
      expect(titleSortKey('  The Rose  '), 'rose');
      expect(titleSortKey('  Rose  '), 'rose');
    });

    test('leaves titles without a leading article unchanged (lowercased)', () {
      expect(titleSortKey('Petronella'), 'petronella');
      expect(titleSortKey('A1 Balance'), 'a1 balance');
    });
  });
}
