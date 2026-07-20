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
}
