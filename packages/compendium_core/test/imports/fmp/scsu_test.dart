import 'package:compendium_core/src/imports/fmp/scsu.dart';
import 'package:test/test.dart';

/// Unit tests for the pure-Dart SCSU decoder ([decodeScsu]) used to read
/// FileMaker 12 string values. SCSU passes ASCII through unchanged, maps the
/// initial dynamic window to Latin-1, and normalises line breaks/tabs.
void main() {
  group('decodeScsu', () {
    test('passes ASCII bytes through unchanged', () {
      expect(decodeScsu('Hello, world!'.codeUnits), 'Hello, world!');
    });

    test('decodes Latin-1 via the initial dynamic window', () {
      // Default active window 0 has offset 0x0080, so 0xE9 → U+00E9 (é).
      expect(decodeScsu([0x63, 0x61, 0x66, 0xE9]), 'café');
    });

    test('maps CR to LF (one line break per control byte)', () {
      expect(decodeScsu([0x61, 0x0D, 0x62]), 'a\nb');
      // CR then LF are two separate control bytes → two breaks (faithful to
      // the reference); higher layers split on \n and drop empty lines.
      expect(decodeScsu([0x61, 0x0D, 0x0A, 0x62]), 'a\n\nb');
    });

    test('encodes tab as a space (matching the reference)', () {
      expect(decodeScsu([0x61, 0x09, 0x62]), 'a b');
    });

    test('empty input yields empty string, never throws', () {
      expect(decodeScsu(const []), '');
    });

    test('a truncated trailing sequence stops gracefully', () {
      // 0x0E (SQU) expects two more bytes; only one follows → decode stops.
      expect(() => decodeScsu([0x41, 0x0E, 0x00]), returnsNormally);
    });
  });
}
