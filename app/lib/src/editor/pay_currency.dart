import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:compendium_core/compendium_core.dart';

/// Currencies offered in the program editor's pay selector (issue #1418).
/// A program may already carry any ISO 4217 code (from sync or an archive);
/// [payCurrencyChoices] adds that code so it is never silently replaced.
const List<String> kPayCurrencyChoices = [
  'USD',
  'EUR',
  'GBP',
  'CAD',
  'AUD',
  'NZD',
  'CHF',
  'DKK',
  'NOK',
  'SEK',
  'JPY',
  'MXN',
  'BRL',
  'ZAR',
];

const Map<String, String> _kCurrencyByRegion = {
  'US': 'USD',
  'CA': 'CAD',
  'GB': 'GBP',
  'AU': 'AUD',
  'NZ': 'NZD',
  'CH': 'CHF',
  'DK': 'DKK',
  'NO': 'NOK',
  'SE': 'SEK',
  'JP': 'JPY',
  'MX': 'MXN',
  'BR': 'BRL',
  'ZA': 'ZAR',
  'FR': 'EUR',
  'DE': 'EUR',
  'NL': 'EUR',
  'BE': 'EUR',
  'IE': 'EUR',
  'ES': 'EUR',
  'IT': 'EUR',
  'AT': 'EUR',
  'FI': 'EUR',
  'PT': 'EUR',
};

const Map<String, String> _kCurrencyByLanguage = {
  'da': 'DKK',
  'ja': 'JPY',
  'fr': 'EUR',
  'de': 'EUR',
  'nl': 'EUR',
};

/// The currency a new pay amount defaults to: the region of [locale], else of
/// the platform locale (the app locale is often language-only), else its
/// language, else `USD`. Always a valid ISO-shaped code.
String defaultPayCurrency(Locale locale, {Locale? platformLocale}) {
  final fromRegion = _kCurrencyByRegion[locale.countryCode];
  if (fromRegion != null) return fromRegion;
  final platform = platformLocale ?? PlatformDispatcher.instance.locale;
  // Only trust the platform's region when the app locale does not contradict
  // it by language (an app set to French on an en-US phone is not in the US).
  if (platform.languageCode == locale.languageCode) {
    final fromPlatform = _kCurrencyByRegion[platform.countryCode];
    if (fromPlatform != null) return fromPlatform;
  }
  return _kCurrencyByLanguage[locale.languageCode] ?? 'USD';
}

/// [kPayCurrencyChoices] plus [current] when it is not already listed.
List<String> payCurrencyChoices(String current) => [
  ...kPayCurrencyChoices,
  if (!kPayCurrencyChoices.contains(current) &&
      Program.isValidPayCurrency(current))
    current,
];
