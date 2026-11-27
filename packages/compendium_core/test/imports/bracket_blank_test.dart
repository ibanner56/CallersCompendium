import 'dart:math';

import 'package:compendium_core/src/imports/bracket_blank.dart';
import 'package:test/test.dart';

/// The regular expressions [blankBracketedAnnotations] replaces (pre-release
/// audit SEC-04): it must give exactly their result.
String _byRegExp(String text) => text
    .replaceAll(RegExp(r'\([^)]*\)'), ' ')
    .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');

void main() {
  test('blanks annotations exactly as the regular expressions did', () {
    for (final text in [
      '',
      'partners swing',
      'balance and swing (NR)',
      'circle left [3 places] (once)',
      '(a (b) c)',
      '[a [b] c]',
      '((((',
      '[[[[',
      '))))(',
      '(a]b)[c)d]',
      'x(y',
      'x)y(z)',
      '([)]',
    ]) {
      expect(blankBracketedAnnotations(text), _byRegExp(text), reason: text);
    }
    // Seeded, so a failure names a reproducible string.
    final random = Random(2026);
    const alphabet = '()[] ab';
    for (var i = 0; i < 5000; i++) {
      final text = String.fromCharCodes([
        for (var j = random.nextInt(24); j > 0; j--)
          alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ]);
      expect(blankBracketedAnnotations(text), _byRegExp(text), reason: text);
    }
  });

  test('returns a line with nothing to blank unchanged', () {
    const text = '(((( no closing bracket';
    expect(identical(blankBracketedAnnotations(text), text), isTrue);
  });
}
