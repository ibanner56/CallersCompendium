import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeImportedText strips control characters', () {
    test('removes C0 controls but keeps tab/newline/carriage-return', () {
      final input = 'a\u0000b\u0007c\td\ne\rf\u001Fg';
      expect(sanitizeImportedText(input), 'abc\td\ne\rfg');
    });

    test('removes the vertical tab and form feed', () {
      expect(sanitizeImportedText('a\u000Bb\u000Cc'), 'abc');
    });

    test('removes DEL and the C1 control block', () {
      expect(sanitizeImportedText('x\u007Fy\u0085z\u009Fw'), 'xyzw');
    });

    test('strips tab/newline when line breaks are disallowed', () {
      expect(
        sanitizeImportedText('a\tb\nc\rd', allowLineBreaks: false),
        'abcd',
      );
    });
  });

  group('sanitizeImportedText strips bidi controls', () {
    test('removes an RTL-override spoof sequence', () {
      // "gnp.exe" disguised as "exe.png" via a right-to-left override.
      final spoof = 'gnp.\u202Eexe';
      expect(sanitizeImportedText(spoof), 'gnp.exe');
    });

    test('removes embeddings, overrides, isolates and marks', () {
      final input =
          'a\u202Ab\u202Bc\u202Cd\u202Ee\u2066f\u2069g\u200Eh\u200Fi\u061Cj';
      expect(sanitizeImportedText(input), 'abcdefghij');
    });
  });

  group('sanitizeImportedText strips invisible/format characters', () {
    test('removes the zero-width space and word joiner', () {
      // ZWSP (U+200B) and the word joiner (U+2060) are stripped; the shaping
      // joiners ZWNJ (U+200C) and ZWJ (U+200D) between them are preserved.
      final input = 'a\u200Bb\u200Cc\u200Dd\u2060e';
      expect(sanitizeImportedText(input), 'ab\u200Cc\u200Dde');
    });

    test('removes the byte-order mark and interlinear anchors', () {
      expect(sanitizeImportedText('\uFEFFTitle\uFFF9x\uFFFBy'), 'Titlexy');
    });

    test('removes line and paragraph separators', () {
      expect(sanitizeImportedText('a\u2028b\u2029c'), 'abc');
    });

    test('removes tag-block characters used for spoofing', () {
      final input = 'a\u{E0041}\u{E007F}b';
      expect(sanitizeImportedText(input), 'ab');
    });

    test('removes Arabic-script and per-plane noncharacters', () {
      expect(sanitizeImportedText('a\uFDD0b\uFFFEc\u{1FFFF}d'), 'abcd');
    });
  });

  group('sanitizeImportedText preserves legitimate content', () {
    test('leaves clean text unchanged and returns the same instance', () {
      const clean = 'Petronella — a becket-CW dance, 32 bars\nwith notes';
      expect(identical(sanitizeImportedText(clean), clean), isTrue);
    });

    test('keeps accented and non-Latin letters', () {
      const input = 'Café Crète Ölçek Москва 東京';
      expect(sanitizeImportedText(input), input);
    });

    test('keeps emoji and variation selectors', () {
      const input = 'Dance \u2764\uFE0F 🎻';
      expect(sanitizeImportedText(input), input);
    });

    test('preserves an emoji ZWJ sequence intact', () {
      // The zero-width joiner (U+200D) is a shaping control, not a spoofing
      // vector, so a family emoji ZWJ sequence must survive unchanged.
      const family = '👨\u200D👩\u200D👧';
      expect(sanitizeImportedText(family), family);
    });

    test('preserves ZWNJ used for script shaping', () {
      // Zero-width non-joiner (U+200C) is required by e.g. Persian rendering.
      const input = 'می\u200Cخواهم';
      expect(sanitizeImportedText(input), input);
    });

    test('still strips ZWSP and bidi override even beside joiners', () {
      // ZWSP (U+200B) and RLO (U+202E) are stripped; the ZWJ (U+200D) is kept.
      final input = 'a\u200Bb\u202Ec\u200Dd';
      expect(sanitizeImportedText(input), 'abc\u200Dd');
    });

    test('returns an empty string untouched', () {
      expect(sanitizeImportedText(''), '');
    });
  });

  group('containsDisallowedText flags without mutating', () {
    test('true when a disallowed character is present', () {
      expect(containsDisallowedText('safe\u202Eevil'), isTrue);
    });

    test('false for clean text', () {
      expect(containsDisallowedText('perfectly safe title'), isFalse);
    });

    test('respects allowLineBreaks', () {
      expect(containsDisallowedText('a\nb'), isFalse);
      expect(containsDisallowedText('a\nb', allowLineBreaks: false), isTrue);
    });
  });
}
