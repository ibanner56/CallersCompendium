import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Guards [normalizeArgb], the hardening applied to every stored or imported
/// tag colour (issue #786).
///
/// A tag colour becomes attacker-influenced the moment tag colours render,
/// because archives are a sharing surface and the colour drives a painted
/// element. These cases pin the rules that keep a hostile or corrupt value from
/// producing an invisible or nonsensical chip.
void main() {
  group('normalizeArgb', () {
    test('passes an opaque colour through unchanged', () {
      expect(normalizeArgb(0xFF2196F3), 0xFF2196F3);
    });

    test('forces a transparent colour opaque so a chip cannot vanish', () {
      // The hostile case: alpha 0 would paint nothing at all, leaving a chip
      // that looks unset while the stored value says otherwise.
      expect(normalizeArgb(0x00FF0000), 0xFFFF0000);
      expect(normalizeArgb(0x11223344), 0xFF223344);
    });

    test('treats a missing or null value as "no colour assigned"', () {
      expect(normalizeArgb(null), isNull);
    });

    test('rejects non-numeric values rather than throwing', () {
      // Degrading beats throwing: the name is the meaningful data, so a bad
      // colour must cost the tint and not the tag.
      expect(normalizeArgb('#FF0000'), isNull);
      expect(normalizeArgb(true), isNull);
      expect(normalizeArgb(<String, Object?>{'r': 1}), isNull);
      expect(normalizeArgb(<Object?>[255, 0, 0]), isNull);
    });

    test('rejects non-finite and fractional numbers', () {
      expect(normalizeArgb(double.nan), isNull);
      expect(normalizeArgb(double.infinity), isNull);
      expect(normalizeArgb(double.negativeInfinity), isNull);
      expect(normalizeArgb(1.5), isNull);
    });

    test('accepts a double that is exactly integral', () {
      // JSON numbers can decode as doubles; an integral one is a valid colour.
      expect(normalizeArgb(4278190080.0), 0xFF000000);
    });

    test('rejects values outside the 32-bit ARGB range', () {
      expect(normalizeArgb(-1), isNull);
      expect(normalizeArgb(0x1FFFFFFFF), isNull);
      expect(normalizeArgb(1e30), isNull);
    });

    test('does not wrap an out-of-range value into a different colour', () {
      // Masking (`& 0xFFFFFFFF`) would turn this into opaque red, inventing a
      // colour the archive never expressed.
      expect(normalizeArgb(0x1FFFF0000), isNull);
    });

    test('accepts the range endpoints', () {
      expect(normalizeArgb(0), 0xFF000000);
      expect(normalizeArgb(0xFFFFFFFF), 0xFFFFFFFF);
    });
  });
}
