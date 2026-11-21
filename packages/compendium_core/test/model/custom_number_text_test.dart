import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  test('a whole number reads as a caller types it', () {
    expect(customNumberText(3.0), '3');
    expect(customNumberText(-3.0), '-3');
    expect(customNumberText(0.0), '0');
    expect(customNumberText(-0.0), '0');
    expect(customNumberText(3), '3');
    expect(customNumberText(999999999999999.0), '999999999999999');
  });

  test('a fraction keeps its digits', () {
    expect(customNumberText(2.5), '2.5');
    expect(customNumberText(-0.25), '-0.25');
    expect(customNumberText(1e-7), '1e-7');
  });

  test('a whole number past 2^63 keeps its own digits', () {
    // `toInt` clamps from 2^63 on the VM, so each of these once read
    // 9223372036854775807.
    expect(customNumberText(1e20), '100000000000000000000');
    expect(customNumberText(-1e20), '-100000000000000000000');
    expect(customNumberText(9.3e18), '9300000000000000000');
    // `toString` writes exponent form from 1e21; that stays.
    expect(customNumberText(1e21), '1e+21');
  });
}
