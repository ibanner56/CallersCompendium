import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('parsePayMinorUnits', () {
    test('two-decimal currencies', () {
      expect(parsePayMinorUnits('250', 'USD'), 25000);
      expect(parsePayMinorUnits('250.5', 'USD'), 25050);
      expect(parsePayMinorUnits('250.05', 'USD'), 25005);
      expect(parsePayMinorUnits('1,250.00', 'EUR'), 125000);
      expect(parsePayMinorUnits('  .5 ', 'USD'), 50);
      expect(parsePayMinorUnits('0', 'USD'), 0);
      expect(parsePayMinorUnits('7.', 'USD'), 700);
    });

    test('currency exponent decides the fraction length', () {
      expect(parsePayMinorUnits('5000', 'JPY'), 5000);
      expect(parsePayMinorUnits('5000.5', 'JPY'), isNull);
      expect(parsePayMinorUnits('1.234', 'KWD'), 1234);
      expect(parsePayMinorUnits('1.234', 'USD'), isNull);
      expect(parsePayMinorUnits('1.5', 'ZZZ'), 150);
    });

    test('rejects empty, negative and non-numeric input', () {
      for (final bad in ['', '  ', '.', '-5', '+5', '12abc', '1.2.3', 'ten']) {
        expect(parsePayMinorUnits(bad, 'USD'), isNull, reason: bad);
      }
    });

    test('rejects decimal-comma and malformed thousands grouping', () {
      for (final bad in [
        '250,50',
        '1,,250.00',
        '1,25',
        ',250',
        '1,2500',
        '1250,000,0',
        '1,250,',
        '250.5,0',
        '1.250,00',
      ]) {
        expect(parsePayMinorUnits(bad, 'USD'), isNull, reason: bad);
      }
      expect(parsePayMinorUnits('1,250.00', 'USD'), 125000);
      expect(parsePayMinorUnits('12,345,678', 'USD'), 1234567800);
      expect(parsePayMinorUnits('250', 'USD'), 25000);
    });

    test('rejects an amount beyond exact integer range', () {
      expect(parsePayMinorUnits('99999999999999999999', 'USD'), isNull);
    });
  });

  group('formatPayMinorUnits', () {
    test('pads and places the decimal point', () {
      expect(formatPayMinorUnits(25050, 'USD'), '250.50');
      expect(formatPayMinorUnits(5, 'USD'), '0.05');
      expect(formatPayMinorUnits(0, 'USD'), '0.00');
      expect(formatPayMinorUnits(5000, 'JPY'), '5000');
      expect(formatPayMinorUnits(1234, 'KWD'), '1.234');
      expect(formatPayMinorUnits(1, 'KWD'), '0.001');
    });

    test('round-trips through parse', () {
      for (final c in ['USD', 'JPY', 'KWD']) {
        for (final n in [0, 1, 99, 100, 123456]) {
          expect(parsePayMinorUnits(formatPayMinorUnits(n, c), c), n);
        }
      }
    });
  });
}
