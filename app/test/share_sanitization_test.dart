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
      // `deceased` is classified deviceLocal in the privacy registry
      // ("personal data about someone who cannot exercise any rights over
      // it"), so it is redacted rather than preserved (issue #853).
      expect(sanitized.deceased, isFalse);
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

    test('keeps the descriptive fields and clears the postal address', () {
      final sanitized = sanitizeVenueForShare(fullVenue());

      expect(sanitized.id, 'v1');
      expect(sanitized.name, 'Town Hall');
      // Descriptive fields are classified shareable and survive.
      expect(sanitized.website, 'https://townhall.example');
      expect(sanitized.sponsor, 'Local Dance Society');
      expect(sanitized.eventName, 'Friday Contra');
      expect(sanitized.time, '8pm');
      expect(sanitized.genericSchedule, '1st & 3rd Fridays');
      expect(sanitized.price, '\$12');
      expect(sanitized.notes, 'Wooden floor.');

      // The postal address is classified deviceLocal in the privacy registry
      // (venues.address1 .. venues.plus4) and has no opt-in, so it is cleared
      // unconditionally (issue #853).
      expect(sanitized.address1, isNull);
      expect(sanitized.address2, isNull);
      expect(sanitized.city, isNull);
      expect(sanitized.stateProv, isNull);
      expect(sanitized.country, isNull);
      expect(sanitized.postalCode, isNull);
      expect(sanitized.plus4, isNull);
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

    test('clears the address even when there is no contact data', () {
      final sanitized = sanitizeVenueForShare(
        Venue(
          id: 'v1',
          name: 'Bare Hall',
          city: 'Montpelier',
          eventName: 'Friday Contra',
        ),
      );

      expect(sanitized.name, 'Bare Hall');
      expect(sanitized.eventName, 'Friday Contra');
      // Not a no-op: the address block goes regardless of contacts, because
      // it is withheld for what it is, not because a contact person is set.
      expect(sanitized.city, isNull);
      expect(populatedVenueContactFields(sanitized), isEmpty);
    });
  });

  group('venuesWithSanitizedContact', () {
    test(
      'replaces the linked venue with a contact-redacted copy by default',
      () {
        final result = venuesWithSanitizedContact({'v1': fullVenue()}, 'v1');

        final v = result['v1']!;
        // Descriptive fields survive; the address block and every contact
        // field are cleared.
        expect(v.name, 'Town Hall');
        expect(v.website, 'https://townhall.example');
        expect(v.address1, isNull);
        expect(v.city, isNull);
        expect(populatedVenueContactFields(v), isEmpty);
      },
    );

    test('honors include: only listed contact fields survive', () {
      final result = venuesWithSanitizedContact(
        {'v1': fullVenue()},
        'v1',
        include: {VenueContactField.contact1Email},
      );

      final v = result['v1']!;
      expect(v.contact1Email, 'alex@example.com');
      expect(v.contact1Name, isNull);
      expect(v.contact1Phone, isNull);
      expect(v.contact2Name, isNull);
      expect(v.contact2Phone, isNull);
      expect(v.contact2Email, isNull);
    });

    test('leaves other venues in the map untouched', () {
      final other = Venue(
        id: 'v2',
        name: 'Other Hall',
        contact1Email: 'x@example.com',
      );
      final result = venuesWithSanitizedContact({
        'v1': fullVenue(),
        'v2': other,
      }, 'v1');

      expect(identical(result['v2'], other), isTrue);
      expect(populatedVenueContactFields(result['v1']!), isEmpty);
    });

    test('returns the map unchanged for a null venueId', () {
      final map = {'v1': fullVenue()};

      expect(identical(venuesWithSanitizedContact(map, null), map), isTrue);
    });

    test('returns the map unchanged when the venueId is absent', () {
      final map = {'v1': fullVenue()};

      expect(
        identical(venuesWithSanitizedContact(map, 'missing'), map),
        isTrue,
      );
    });
  });
}
