import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('colourSeedForTitle', () {
    // Seeds are stable ARGB ints; assert the matched hue by comparing against
    // the seed a bare colour word resolves to, so tests don't hard-code hex.
    int seedOf(String colour) => colourSeedForTitle(colour)!;

    test('matches the issue examples to the expected hue', () {
      expect(colourSeedForTitle('Baby Rose'), seedOf('rose'));
      expect(colourSeedForTitle('Sharon of the Green'), seedOf('green'));
      expect(colourSeedForTitle('Blue Boy'), seedOf('blue'));
      expect(colourSeedForTitle('Red Beard Reel'), seedOf('red'));
      expect(colourSeedForTitle('Blue-Haired Girl'), seedOf('blue'));
      expect(colourSeedForTitle('Jurassic Redheads'), seedOf('red'));
    });

    test('is case-insensitive', () {
      expect(colourSeedForTitle('BLUE boy'), seedOf('blue'));
      expect(colourSeedForTitle('bLuE-hAiReD gIrL'), seedOf('blue'));
      expect(colourSeedForTitle('GREEN'), seedOf('green'));
    });

    test('handles hyphenated and possessive forms', () {
      expect(colourSeedForTitle('Green-Sleeved Reel'), seedOf('green'));
      expect(colourSeedForTitle("Rose's Waltz"), seedOf('rose'));
      expect(colourSeedForTitle('The Silver-Tipped Star'), seedOf('silver'));
    });

    test('matches consonant-led compounds (plurals/compound words)', () {
      expect(colourSeedForTitle('Redheads'), seedOf('red'));
      expect(colourSeedForTitle('Bluebird'), seedOf('blue'));
      expect(colourSeedForTitle('Greenhouse'), seedOf('green'));
    });

    test('returns null for titles with no colour word', () {
      expect(colourSeedForTitle('The Nice Combination'), isNull);
      expect(colourSeedForTitle('Hull Reel'), isNull);
      expect(colourSeedForTitle(''), isNull);
      expect(colourSeedForTitle('12345'), isNull);
    });

    test('does not over-reach on English words sharing a colour prefix', () {
      // A vowel after the colour name means a shared prefix, not a compound.
      expect(colourSeedForTitle('Reduce the Set'), isNull);
      expect(colourSeedForTitle('Redeem'), isNull);
      expect(colourSeedForTitle('Bluff Point'), isNull);
    });

    test('recognises synonyms', () {
      expect(colourSeedForTitle('Pink Slipper'), seedOf('pink'));
      expect(colourSeedForTitle('Golden Slippers'), seedOf('gold'));
      expect(colourSeedForTitle('Grey Goose'), seedOf('gray'));
    });

    test('returns the first colour word left to right', () {
      // "green" appears before "blue" in reading order.
      expect(colourSeedForTitle('Green then Blue'), seedOf('green'));
    });
  });
}
