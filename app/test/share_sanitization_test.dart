import 'package:compendium_app/src/export/share_sanitization.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeChoreographerForShare', () {
    test('clears private contact fields (email + location)', () {
      final sanitized = sanitizeChoreographerForShare(
        Choreographer(
          id: 'c1',
          name: 'Cary Ravitz',
          email: 'cary@example.com',
          location: 'Lexington, KY',
        ),
      );

      expect(sanitized.email, isNull);
      expect(sanitized.location, isNull);
    });

    test('preserves public attribution fields and identity', () {
      final sanitized = sanitizeChoreographerForShare(
        Choreographer(
          id: 'c1',
          name: 'Cary Ravitz',
          website: 'https://ravitz.example',
          notes: 'Prolific New England composer.',
          email: 'cary@example.com',
          location: 'Lexington, KY',
          deceased: true,
        ),
      );

      expect(sanitized.id, 'c1');
      expect(sanitized.name, 'Cary Ravitz');
      expect(sanitized.website, 'https://ravitz.example');
      expect(sanitized.notes, 'Prolific New England composer.');
      expect(sanitized.deceased, isTrue);
    });

    test('is a no-op for a choreographer with no contact data', () {
      final sanitized = sanitizeChoreographerForShare(
        Choreographer(id: 'c1', name: 'Anonymous'),
      );

      expect(sanitized.email, isNull);
      expect(sanitized.location, isNull);
      expect(sanitized.name, 'Anonymous');
    });
  });

  Venue fullVenue() => Venue(
    id: 'v1',
    name: 'Town Hall',
    address1: '10 Main St',
    address2: 'Suite 2',
    city: 'Montpelier',
    stateProv: 'VT',
    country: 'USA',
    postalCode: '05602',
    plus4: '1234',
    website: 'https://townhall.example',
    sponsor: 'Local Dance Society',
    eventName: 'Friday Contra',
    time: '8pm',
    genericSchedule: '1st & 3rd Fridays',
    price: '\$12',
    notes: 'Wooden floor.',
    contact1Name: 'Alex Caller',
    contact1Phone: '555-0100',
    contact1Email: 'alex@example.com',
    contact2Name: 'Bo Booker',
    contact2Phone: '555-0200',
    contact2Email: 'bo@example.com',
  );

  group('populatedVenueContactFields', () {
    test('returns exactly the populated contact fields', () {
      final venue = Venue(
        id: 'v1',
        name: 'Town Hall',
        contact1Name: 'Alex Caller',
        contact1Email: 'alex@example.com',
        contact2Phone: '555-0200',
      );

      expect(populatedVenueContactFields(venue), {
        VenueContactField.contact1Name,
        VenueContactField.contact1Email,
        VenueContactField.contact2Phone,
      });
    });

    test('is empty for a venue with no contact fields', () {
      expect(
        populatedVenueContactFields(Venue(id: 'v1', name: 'Bare Hall')),
        isEmpty,
      );
    });
  });

  group('sanitizeVenueForShare', () {
    test('default clears all six contact fields', () {
      final sanitized = sanitizeVenueForShare(fullVenue());

      expect(sanitized.contact1Name, isNull);
      expect(sanitized.contact1Phone, isNull);
      expect(sanitized.contact1Email, isNull);
      expect(sanitized.contact2Name, isNull);
      expect(sanitized.contact2Phone, isNull);
      expect(sanitized.contact2Email, isNull);
    });

    test('keeps every descriptive field when clearing contacts', () {
      final sanitized = sanitizeVenueForShare(fullVenue());

      expect(sanitized.id, 'v1');
      expect(sanitized.name, 'Town Hall');
      expect(sanitized.address1, '10 Main St');
      expect(sanitized.address2, 'Suite 2');
      expect(sanitized.city, 'Montpelier');
      expect(sanitized.stateProv, 'VT');
      expect(sanitized.country, 'USA');
      expect(sanitized.postalCode, '05602');
      expect(sanitized.plus4, '1234');
      expect(sanitized.website, 'https://townhall.example');
      expect(sanitized.sponsor, 'Local Dance Society');
      expect(sanitized.eventName, 'Friday Contra');
      expect(sanitized.time, '8pm');
      expect(sanitized.genericSchedule, '1st & 3rd Fridays');
      expect(sanitized.price, '\$12');
      expect(sanitized.notes, 'Wooden floor.');
    });

    test('honors include: only listed contact fields survive', () {
      final sanitized = sanitizeVenueForShare(
        fullVenue(),
        include: {
          VenueContactField.contact1Name,
          VenueContactField.contact2Email,
        },
      );

      expect(sanitized.contact1Name, 'Alex Caller');
      expect(sanitized.contact2Email, 'bo@example.com');
      // Everything not in the include set is cleared.
      expect(sanitized.contact1Phone, isNull);
      expect(sanitized.contact1Email, isNull);
      expect(sanitized.contact2Name, isNull);
      expect(sanitized.contact2Phone, isNull);
    });

    test('is a no-op for a venue with no contact data', () {
      final sanitized = sanitizeVenueForShare(
        Venue(id: 'v1', name: 'Bare Hall', city: 'Montpelier'),
      );

      expect(sanitized.name, 'Bare Hall');
      expect(sanitized.city, 'Montpelier');
      expect(populatedVenueContactFields(sanitized), isEmpty);
    });
  });
}
