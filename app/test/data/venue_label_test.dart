import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/venue_label.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({String? venue, String? venueId}) => Program(
  id: 'p1',
  title: 'Spring Fling',
  venue: venue,
  venueId: venueId,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Venue _venue({
  String id = 'grange-hall',
  String name = 'Grange Hall',
  String? city,
  String? stateProv,
}) => Venue(id: id, name: name, city: city, stateProv: stateProv);

void main() {
  group('resolveVenueLabel', () {
    test('returns the linked venue display name when venueId resolves', () {
      final byId = {'grange-hall': _venue(city: 'Amherst', stateProv: 'MA')};
      final label = resolveVenueLabel(
        _program(venue: 'ignored free text', venueId: 'grange-hall'),
        byId,
      );
      expect(label, 'Grange Hall, Amherst, MA');
    });

    test('falls back to free text when there is no venueId', () {
      final label = resolveVenueLabel(_program(venue: 'The Barn'), const {});
      expect(label, 'The Barn');
    });

    test('falls back to free text when venueId does not resolve', () {
      final label = resolveVenueLabel(
        _program(venue: 'The Barn', venueId: 'missing'),
        {'other': _venue(id: 'other', name: 'Other')},
      );
      expect(label, 'The Barn');
    });

    test('returns null when neither a resolved venue nor free text exists', () {
      expect(resolveVenueLabel(_program(venueId: 'missing'), const {}), isNull);
      expect(resolveVenueLabel(_program(), const {}), isNull);
    });

    test('trims free text and treats whitespace-only as absent', () {
      expect(resolveVenueLabel(_program(venue: '  Hall  '), const {}), 'Hall');
    });
  });
}
