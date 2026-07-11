import 'package:compendium_core/src/storage/utc_datetime.dart';
import 'package:test/test.dart';

void main() {
  group('asUtc / asUtcOrNull', () {
    test('asUtc converts a local DateTime to the same instant in UTC', () {
      final local = DateTime.fromMillisecondsSinceEpoch(0, isUtc: false);
      final converted = asUtc(local);
      expect(converted.isUtc, isTrue);
      expect(converted.millisecondsSinceEpoch, 0);
    });

    test('asUtcOrNull passes through null', () {
      expect(asUtcOrNull(null), isNull);
    });

    test('asUtcOrNull converts a non-null value', () {
      final local = DateTime.fromMillisecondsSinceEpoch(0, isUtc: false);
      expect(asUtcOrNull(local)!.isUtc, isTrue);
    });
  });

  group('assertUtc / assertUtcOrNull', () {
    test('assertUtc throws for a non-UTC DateTime', () {
      expect(
        () => assertUtc(DateTime(2026), 'x'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assertUtc accepts a UTC DateTime', () {
      expect(() => assertUtc(DateTime.utc(2026), 'x'), returnsNormally);
    });

    test('assertUtcOrNull accepts null without throwing', () {
      expect(() => assertUtcOrNull(null, 'x'), returnsNormally);
    });

    test('assertUtcOrNull throws for a non-null, non-UTC DateTime', () {
      expect(
        () => assertUtcOrNull(DateTime(2026), 'x'),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
