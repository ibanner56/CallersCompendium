import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('scrubFigureText normalizes the hyphenated do-si-do', () {
    test('rewrites "do-si-do" to "do si do"', () {
      // The Caller's Box hyphenates it exclusively (e.g. dance ids 7348,
      // 16767); the figure parser only matches the space-separated form.
      expect(scrubFigureText('do-si-do'), 'do si do');
    });

    test('rewrites it inside a full figure line', () {
      expect(scrubFigureText('Do-si-do neighbor'), 'do si do neighbor');
    });

    test('is case-insensitive', () {
      expect(scrubFigureText('Do-Si-Do'), 'do si do');
      expect(scrubFigureText('DO-SI-DO'), 'do si do');
    });

    test('leaves an already-correct "do si do" untouched', () {
      expect(scrubFigureText('do si do'), 'do si do');
      expect(scrubFigureText('neighbors do si do'), 'neighbors do si do');
    });
  });

  group('scrubFigureText canonicalizes gendered role terms', () {
    test('scrubs a Men figure line to canonical role tokens', () {
      // "(8) Men allemande left 1" from The Caller's Box (ids 5010, 9616,
      // 14387) must reach the recognizer as canonical role1s.
      expect(
        scrubFigureText('(8) Men allemande left 1'),
        '(8) role1s allemande left 1',
      );
    });

    test('scrubs singular Man/Woman and plural Women', () {
      expect(scrubFigureText('Man'), 'role1');
      expect(scrubFigureText('Women'), 'role2s');
      expect(
        scrubFigureText('Women chain to the Men'),
        'role2s chain to the role1s',
      );
    });
  });
}
