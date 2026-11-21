/// Parsing and formatting of a program's pay (issue #1418).
///
/// Pay is stored as integer minor units plus an ISO 4217 code, so there is no
/// floating point anywhere on the path. These helpers translate between that
/// and the plain decimal string a person types or reads.
library;

/// Currencies whose minor-unit exponent is not 2. Anything absent uses 2; the
/// table covers the common codes and is not a full ISO 4217 registry, so an
/// unlisted three-decimal or zero-decimal currency is treated as two-decimal.
const Map<String, int> kPayCurrencyExponents = {
  // Zero decimal places.
  'JPY': 0, 'KRW': 0, 'VND': 0, 'CLP': 0, 'ISK': 0, 'UGX': 0,
  'XAF': 0, 'XOF': 0, 'XPF': 0, 'PYG': 0, 'RWF': 0,
  // Three decimal places.
  'BHD': 3, 'JOD': 3, 'KWD': 3, 'OMR': 3, 'TND': 3,
};

/// Number of decimal places of [currency]'s minor unit (2 unless listed in
/// [kPayCurrencyExponents]).
int payCurrencyExponent(String currency) =>
    kPayCurrencyExponents[currency] ?? 2;

/// Parses [input], a non-negative decimal amount such as `250`, `250.5` or
/// `1,250.00`, into minor units of [currency].
///
/// Returns `null` for empty input, a negative or non-numeric value, more
/// fraction digits than the currency has, or an amount too large to store
/// exactly. Whitespace around the value is ignored, as are `,` thousands
/// separators when correctly placed (`1,250` but not `250,50` or `1,,250`); `.` is the decimal separator. A bare `.5` is accepted.
int? parsePayMinorUnits(String input, String currency) {
  final trimmed = input.trim();
  // `,` is only a thousands separator: groups of exactly three digits after a
  // leading one to three. Anything else (`250,50`, `1,,250`) is rejected rather
  // than silently read as a different amount.
  final wholePart = trimmed.split('.').first;
  if (wholePart.contains(',') &&
      !RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(wholePart)) {
    return null;
  }
  if (trimmed.contains('.') &&
      trimmed.split('.').skip(1).any((part) => part.contains(','))) {
    return null;
  }
  final text = trimmed.replaceAll(',', '');
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text);
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  final exponent = payCurrencyExponent(currency);
  if (fraction.length > exponent) return null;
  final digits =
      '${whole.isEmpty ? '0' : whole}${fraction.padRight(exponent, '0')}';
  final value = int.tryParse(digits);
  // Dart web ints are doubles; stay inside the exactly representable range.
  if (value == null || value > 9007199254740991) return null;
  return value;
}

/// Formats [minorUnits] of [currency] as a plain decimal string with the
/// currency's full number of fraction digits and no grouping or symbol:
/// `format(25050, 'USD')` is `250.50`, `format(5000, 'JPY')` is `5000`.
/// The inverse of [parsePayMinorUnits].
String formatPayMinorUnits(int minorUnits, String currency) {
  final exponent = payCurrencyExponent(currency);
  if (exponent == 0) return '$minorUnits';
  final padded = minorUnits.toString().padLeft(exponent + 1, '0');
  final split = padded.length - exponent;
  return '${padded.substring(0, split)}.${padded.substring(split)}';
}
