import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('validation', () {
    test('requires a non-empty name', () {
      expect(() => Venue(id: 'v1', name: ''), throwsA(isA<ArgumentError>()));
      expect(() => Venue(id: 'v1', name: '   '), throwsA(isA<ArgumentError>()));
    });

    test('accepts a minimal venue with just id + name', () {
      final v = Venue(id: 'v1', name: 'Guiding Star Grange');
      expect(v.id, 'v1');
      expect(v.name, 'Guiding Star Grange');
      expect(v.city, isNull);
      expect(v.contact1Email, isNull);
    });
  });

  group('_normalize', () {
    test('maps empty/whitespace optional strings to null', () {
      final v = Venue(
        id: 'v1',
        name: 'Hall',
        address1: '',
        city: '   ',
        notes: '\t\n',
        contact1Email: '',
      );
      expect(v.address1, isNull);
      expect(v.city, isNull);
      expect(v.notes, isNull);
      expect(v.contact1Email, isNull);
    });

    test('trims surrounding whitespace on kept values', () {
      final v = Venue(id: 'v1', name: 'Hall', city: '  Greenfield  ');
      expect(v.city, 'Greenfield');
    });

    test('does not trim the required name (kept verbatim once non-empty)', () {
      // The name is validated (non-empty) but not normalized/trimmed.
      final v = Venue(id: 'v1', name: '  The Grange  ');
      expect(v.name, '  The Grange  ');
    });
  });

  group('copyWith', () {
    final base = Venue(
      id: 'v1',
      name: 'Hall',
      city: 'Greenfield',
      stateProv: 'MA',
      contact1Name: 'Pat',
      contact1Email: 'pat@example.com',
    );

    test('replaces provided fields and keeps the rest', () {
      final updated = base.copyWith(name: 'New Hall', city: 'Amherst');
      expect(updated.name, 'New Hall');
      expect(updated.city, 'Amherst');
      expect(updated.stateProv, 'MA');
      expect(updated.contact1Name, 'Pat');
      expect(updated.id, 'v1');
    });

    test('clear* flags null the field', () {
      final updated = base.copyWith(clearCity: true, clearContact1Email: true);
      expect(updated.city, isNull);
      expect(updated.contact1Email, isNull);
      expect(updated.stateProv, 'MA');
    });

    test('clear* flag wins over a value passed for the same field', () {
      final updated = base.copyWith(city: 'Ignored', clearCity: true);
      expect(updated.city, isNull);
    });

    test('normalizes values passed through copyWith', () {
      final updated = base.copyWith(stateProv: '   ');
      // An all-whitespace value normalizes to null rather than being kept.
      expect(updated.stateProv, isNull);
    });
  });

  group('displayName', () {
    test(
      'joins name + address1 + city + stateProv + country, skipping nulls',
      () {
        final v = Venue(
          id: 'v1',
          name: 'Guiding Star Grange',
          address1: '401 Chapman St',
          city: 'Greenfield',
          stateProv: 'MA',
          country: 'USA',
        );
        expect(
          v.displayName,
          'Guiding Star Grange, 401 Chapman St, Greenfield, MA, USA',
        );
      },
    );

    test('omits missing components', () {
      final v = Venue(id: 'v1', name: 'Hall', city: 'Greenfield');
      expect(v.displayName, 'Hall, Greenfield');
    });

    test('is just the name when no location fields are set', () {
      final v = Venue(id: 'v1', name: 'Hall');
      expect(v.displayName, 'Hall');
    });

    test('does not include non-location fields (sponsor/notes/contacts)', () {
      final v = Venue(
        id: 'v1',
        name: 'Hall',
        sponsor: 'CDSS',
        notes: 'bring water',
        contact1Name: 'Pat',
      );
      expect(v.displayName, 'Hall');
    });
  });

  group('== / hashCode', () {
    test('equal venues compare equal and share a hashCode', () {
      final a = Venue(id: 'v1', name: 'Hall', city: 'Greenfield');
      final b = Venue(id: 'v1', name: 'Hall', city: 'Greenfield');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differ when any field differs', () {
      final a = Venue(id: 'v1', name: 'Hall', city: 'Greenfield');
      expect(a, isNot(equals(a.copyWith(city: 'Amherst'))));
      expect(a, isNot(equals(a.copyWith(name: 'Other'))));
      expect(
        a,
        isNot(equals(Venue(id: 'v2', name: 'Hall', city: 'Greenfield'))),
      );
    });

    test('normalized-empty equals explicit null', () {
      final a = Venue(id: 'v1', name: 'Hall', address2: '  ');
      final b = Venue(id: 'v1', name: 'Hall');
      expect(a, equals(b));
    });
  });
}
