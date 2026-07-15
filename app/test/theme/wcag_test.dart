import 'package:compendium_app/src/theme/wcag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Wcag', () {
    test('black on white is the maximum 21:1', () {
      expect(
        Wcag.contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
    });

    test('identical colors are 1:1', () {
      expect(
        Wcag.contrastRatio(const Color(0xFF3366CC), const Color(0xFF3366CC)),
        closeTo(1.0, 0.001),
      );
    });

    test('ratio is order-independent', () {
      final a = Wcag.contrastRatio(
        const Color(0xFF222222),
        const Color(0xFFDDDDDD),
      );
      final b = Wcag.contrastRatio(
        const Color(0xFFDDDDDD),
        const Color(0xFF222222),
      );
      expect(a, closeTo(b, 0.0001));
    });

    test('meetsAA uses 4.5 for text and 3.0 for non-text', () {
      // A pair around ~3.45:1 — fails text AA but passes non-text AA.
      const fg = Color(0xFF8A8A8A);
      const bg = Color(0xFFFFFFFF);
      final ratio = Wcag.contrastRatio(fg, bg);
      expect(ratio, greaterThan(3.0));
      expect(ratio, lessThan(4.5));
      expect(Wcag.meetsAA(fg, bg), isFalse);
      expect(Wcag.meetsAA(fg, bg, largeOrNonText: true), isTrue);
    });
  });
}
