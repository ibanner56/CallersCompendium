import 'package:compendium_app/src/data/soft_delete_retention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('softDeleteRetentionFromStored', () {
    test('defaults to 30 days when unset (null)', () {
      expect(softDeleteRetentionFromStored(null), const Duration(days: 30));
    });

    test('resolves the 30- and 90-day options to their Duration', () {
      expect(softDeleteRetentionFromStored(30), const Duration(days: 30));
      expect(softDeleteRetentionFromStored(90), const Duration(days: 90));
    });

    test('resolves any positive day count to a Duration', () {
      expect(softDeleteRetentionFromStored(7), const Duration(days: 7));
    });

    test('returns null (never auto-purge) for the 0 sentinel', () {
      expect(softDeleteRetentionFromStored(kSoftDeleteRetentionNever), isNull);
      expect(softDeleteRetentionFromStored(0), isNull);
    });

    test('falls back to 30 days for garbage: negatives, non-ints, strings', () {
      expect(softDeleteRetentionFromStored(-5), const Duration(days: 30));
      expect(softDeleteRetentionFromStored(30.0), const Duration(days: 30));
      expect(softDeleteRetentionFromStored('90'), const Duration(days: 30));
      expect(
        softDeleteRetentionFromStored(<int>[90]),
        const Duration(days: 30),
      );
    });
  });

  group('soft-delete retention constants (G.4)', () {
    test('use their stable stored key and sentinel', () {
      expect(kSoftDeleteRetentionKey, 'soft_delete_retention_days');
      expect(kSoftDeleteRetentionNever, 0);
      expect(kSoftDeleteRetentionDefaultDays, 30);
      expect(kSoftDeleteRetentionDayOptions, <int>[30, 90]);
    });
  });
}
