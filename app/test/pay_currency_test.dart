import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/pay_currency.dart';

void main() {
  const none = Locale('xx', 'ZZ');
  test('region wins', () {
    expect(
      defaultPayCurrency(const Locale('en', 'GB'), platformLocale: none),
      'GBP',
    );
    expect(
      defaultPayCurrency(const Locale('de', 'DE'), platformLocale: none),
      'EUR',
    );
  });

  test(
    'language-only locale uses the platform region when languages agree',
    () {
      expect(
        defaultPayCurrency(
          const Locale('en'),
          platformLocale: const Locale('en', 'AU'),
        ),
        'AUD',
      );
    },
  );

  test('a platform region does not override a different app language', () {
    expect(
      defaultPayCurrency(
        const Locale('ja'),
        platformLocale: const Locale('en', 'US'),
      ),
      'JPY',
    );
  });

  test('falls back to USD', () {
    expect(defaultPayCurrency(const Locale('en'), platformLocale: none), 'USD');
  });

  test('choices add an unlisted stored currency once', () {
    expect(payCurrencyChoices('USD'), kPayCurrencyChoices);
    expect(payCurrencyChoices('KWD').last, 'KWD');
  });
}
