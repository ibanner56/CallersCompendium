import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('venueFingerprint', () {
    test('normalizes case, surrounding and internal whitespace', () {
      final a = Venue(id: 'a', name: 'Guiding Star Grange', city: 'Greenfield');
      final b = Venue(
        id: 'b',
        name: '  guiding   STAR  grange ',
        city: ' GREENFIELD ',
      );
      expect(venueFingerprint(a), isNotNull);
      expect(venueFingerprint(a), venueFingerprint(b));
    });

    test('is stable across the excluded contact/notes/price/website fields', () {
      final a = Venue(id: 'a', name: 'Grange', address1: '123 Main St');
      final b = Venue(
        id: 'b',
        name: 'Grange',
        address1: '123 Main St',
        contact1Name: 'Alice',
        contact1Phone: '555-1234',
        contact1Email: 'alice@example.com',
        notes: 'call ahead',
        price: '\$10',
        website: 'https://example.com',
        genericSchedule: '2nd Saturdays',
      );
      // #515 strips contact PII on share; the fingerprint must ignore it (plus
      // notes/price/website/schedule) so a shared venue still matches a local one.
      expect(venueFingerprint(a), venueFingerprint(b));
    });

    test('distinguishes different descriptive fields', () {
      final base = Venue(id: 'a', name: 'Grange', city: 'Greenfield');
      expect(
        venueFingerprint(base),
        isNot(
          venueFingerprint(Venue(id: 'b', name: 'Grange', city: 'Amherst')),
        ),
      );
      expect(
        venueFingerprint(base),
        isNot(
          venueFingerprint(
            Venue(id: 'c', name: 'Grange', city: 'Greenfield', stateProv: 'MA'),
          ),
        ),
      );
      expect(
        venueFingerprint(base),
        isNot(
          venueFingerprint(
            Venue(id: 'd', name: 'Town Hall', city: 'Greenfield'),
          ),
        ),
      );
    });

    test('field boundaries are unambiguous (no separator collision)', () {
      // "Foo" + city "Bar" must not collide with "Foo Bar" + no city.
      final a = Venue(id: 'a', name: 'Foo', city: 'Bar');
      final b = Venue(id: 'b', name: 'Foo Bar', address1: 'x');
      expect(venueFingerprint(a), isNot(venueFingerprint(b)));
    });

    group('strong-key threshold', () {
      test('name-only venue is a weak key (null)', () {
        expect(venueFingerprint(Venue(id: 'a', name: 'Town Hall')), isNull);
      });

      test('name + city is a strong key', () {
        expect(
          venueFingerprint(Venue(id: 'a', name: 'Grange', city: 'Greenfield')),
          isNotNull,
        );
      });

      test('name + address1 is a strong key', () {
        expect(
          venueFingerprint(Venue(id: 'a', name: 'Grange', address1: '1 Main')),
          isNotNull,
        );
      });

      test('stateProv alone (no city/address) is still a weak key', () {
        expect(
          venueFingerprint(Venue(id: 'a', name: 'Grange', stateProv: 'MA')),
          isNull,
        );
      });
    });
  });

  group('VenueFingerprintIndex', () {
    Venue v(
      String id, {
      String? city,
      String? address1,
      String name = 'Grange',
    }) => Venue(id: id, name: name, city: city, address1: address1);

    test('matches a fingerprint-equal venue to the existing id', () {
      final index = VenueFingerprintIndex([v('existing', city: 'Greenfield')]);
      expect(index.matchFor(v('incoming', city: 'greenfield')), 'existing');
    });

    test('returns null for a weak-key venue', () {
      final index = VenueFingerprintIndex([v('existing', city: 'Greenfield')]);
      expect(index.matchFor(Venue(id: 'incoming', name: 'Grange')), isNull);
    });

    test('returns null when nothing matches', () {
      final index = VenueFingerprintIndex([v('existing', city: 'Greenfield')]);
      expect(index.matchFor(v('incoming', city: 'Amherst')), isNull);
    });

    test('poisons an ambiguous fingerprint (>1 existing id)', () {
      final index = VenueFingerprintIndex([
        v('a', city: 'Amherst'),
        v('b', city: 'Amherst'),
      ]);
      expect(index.matchFor(v('incoming', city: 'Amherst')), isNull);
    });

    test('folds in an added venue so a later equal venue matches it', () {
      final index = VenueFingerprintIndex();
      expect(index.matchFor(v('incoming', city: 'Greenfield')), isNull);
      index.add('minted-1', v('minted', city: 'Greenfield'));
      expect(index.matchFor(v('incoming', city: 'greenfield')), 'minted-1');
    });

    test('re-adding the same id for a fingerprint stays unambiguous', () {
      final index = VenueFingerprintIndex();
      index.add('same', v('same', city: 'Greenfield'));
      index.add('same', v('same', city: 'Greenfield'));
      expect(index.matchFor(v('incoming', city: 'Greenfield')), 'same');
    });

    test('ignores a weak-key venue on add', () {
      final index = VenueFingerprintIndex();
      index.add('weak', Venue(id: 'weak', name: 'Town Hall'));
      expect(index.matchFor(Venue(id: 'incoming', name: 'Town Hall')), isNull);
    });
  });
}
