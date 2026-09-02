import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Encodes a parsed JSON value using RFC 8785's JSON Canonicalization Scheme.
///
/// Values must be in the JSON value domain: null, bool, finite num, String,
/// List, or Map with String keys. Strings are emitted exactly as supplied;
/// normalization belongs to the storage boundary.
String canonicalJson(Object? value) {
  final output = StringBuffer();
  final active = HashSet<Object>.identity();
  _writeValue(output, value, active, '');
  return output.toString();
}

/// Returns the UTF-8 bytes of [canonicalJson].
Uint8List canonicalJsonUtf8(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJson(value)));

/// Returns lowercase hexadecimal SHA-256 for [bytes].
String sha256Hex(Iterable<int> bytes) =>
    sha256.convert(bytes.toList()).toString().toLowerCase();

/// Hashes a complete sync content value.
String contentHash(Object? value) => sha256Hex(canonicalJsonUtf8(value));

/// Hashes a sync body value without adding an envelope around it.
String bodyHash(Object? body) => contentHash(body);

void _writeValue(
  StringBuffer output,
  Object? value,
  HashSet<Object> active,
  String path,
) {
  switch (value) {
    case null:
      output.write('null');
    case final bool boolean:
      output.write(boolean ? 'true' : 'false');
    case final num number:
      output.write(_formatNumber(number, path));
    case final String string:
      _writeString(output, string, path);
    case final List<Object?> list:
      _writeList(output, list, active, path);
    case final Map<Object?, Object?> map:
      _writeMap(output, map, active, path);
    default:
      throw FormatException('Unsupported JSON value at ${pathOrRoot(path)}');
  }
}

void _writeList(
  StringBuffer output,
  List<Object?> value,
  HashSet<Object> active,
  String path,
) {
  _enter(value, active, path);
  try {
    output.write('[');
    for (var index = 0; index < value.length; index++) {
      if (index > 0) output.write(',');
      _writeValue(output, value[index], active, '$path/$index');
    }
    output.write(']');
  } finally {
    active.remove(value);
  }
}

void _writeMap(
  StringBuffer output,
  Map<Object?, Object?> value,
  HashSet<Object> active,
  String path,
) {
  _enter(value, active, path);
  try {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw FormatException(
          'Object key is not a String at ${pathOrRoot(path)}',
        );
      }
      _validateString(key, '$path/${_pointerEscape(key)}');
      keys.add(key);
    }
    keys.sort(_compareUtf16);

    output.write('{');
    for (var index = 0; index < keys.length; index++) {
      if (index > 0) output.write(',');
      final key = keys[index];
      _writeString(output, key, '$path/${_pointerEscape(key)}');
      output.write(':');
      _writeValue(output, value[key], active, '$path/${_pointerEscape(key)}');
    }
    output.write('}');
  } finally {
    active.remove(value);
  }
}

void _enter(Object value, HashSet<Object> active, String path) {
  if (!active.add(value)) {
    throw FormatException('Cyclic JSON value at ${pathOrRoot(path)}');
  }
}

String _formatNumber(num value, String path) {
  final double ieee754;
  if (value is int) {
    ieee754 = value.toDouble();
    if (!ieee754.isFinite || ieee754.toInt() != value) {
      throw FormatException(
        'Integer is not exactly representable as an IEEE-754 double '
        'at ${pathOrRoot(path)}',
      );
    }
  } else {
    ieee754 = value.toDouble();
  }
  if (!ieee754.isFinite) {
    throw FormatException(
      'NaN and infinity are not JSON numbers at ${pathOrRoot(path)}',
    );
  }
  if (ieee754 == 0) return '0';

  // Dart supplies the shortest round-tripping coefficient. RFC 8785 differs
  // in presentation thresholds, so normalize that coefficient to the
  // ECMAScript fixed/exponent form rather than using it verbatim.
  final raw = ieee754.toString();
  final negative = raw.startsWith('-');
  final unsigned = negative ? raw.substring(1) : raw;
  final exponentMarker = unsigned.indexOf('e');
  final mantissa = exponentMarker < 0
      ? unsigned
      : unsigned.substring(0, exponentMarker);
  final explicitExponent = exponentMarker < 0
      ? 0
      : int.parse(unsigned.substring(exponentMarker + 1));
  final normalizedMantissa = mantissa.endsWith('.0')
      ? mantissa.substring(0, mantissa.length - 2)
      : mantissa;
  final decimalPoint = normalizedMantissa.indexOf('.');
  final digits = decimalPoint < 0
      ? normalizedMantissa
      : normalizedMantissa.substring(0, decimalPoint) +
            normalizedMantissa.substring(decimalPoint + 1);
  var decimalPosition =
      (decimalPoint < 0 ? normalizedMantissa.length : decimalPoint) +
      explicitExponent;
  var significantDigits = digits;
  while (significantDigits.length > 1 &&
      significantDigits.endsWith('0') &&
      decimalPosition >= significantDigits.length) {
    significantDigits = significantDigits.substring(
      0,
      significantDigits.length - 1,
    );
  }

  final decimalExponent = decimalPosition - 1;
  final body = decimalExponent >= -6 && decimalExponent < 21
      ? _fixedForm(significantDigits, decimalPosition)
      : _exponentForm(significantDigits, decimalExponent);
  return negative ? '-$body' : body;
}

String _fixedForm(String digits, int decimalPosition) {
  if (decimalPosition <= 0) {
    return '0.${'0' * -decimalPosition}$digits';
  }
  if (decimalPosition >= digits.length) {
    return '$digits${'0' * (decimalPosition - digits.length)}';
  }
  return '${digits.substring(0, decimalPosition)}.'
      '${digits.substring(decimalPosition)}';
}

String _exponentForm(String digits, int decimalExponent) {
  final mantissa = digits.length == 1
      ? digits
      : '${digits[0]}.${digits.substring(1)}';
  final sign = decimalExponent < 0 ? '-' : '+';
  return '${mantissa}e$sign${decimalExponent.abs()}';
}

void _writeString(StringBuffer output, String value, String path) {
  _validateString(value, path);
  output.write('"');
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    switch (codeUnit) {
      case 0x08:
        output.write(r'\b');
      case 0x09:
        output.write(r'\t');
      case 0x0a:
        output.write(r'\n');
      case 0x0c:
        output.write(r'\f');
      case 0x0d:
        output.write(r'\r');
      case 0x22:
        output.write(r'\"');
      case 0x5c:
        output.write(r'\\');
      default:
        if (codeUnit < 0x20) {
          output
            ..write(r'\u')
            ..write(codeUnit.toRadixString(16).padLeft(4, '0'));
        } else {
          output.writeCharCode(codeUnit);
        }
    }
  }
  output.write('"');
}

void _validateString(String value, String path) {
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      final hasLowPair =
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) >= 0xdc00 &&
          value.codeUnitAt(index + 1) <= 0xdfff;
      if (!hasLowPair) {
        throw FormatException(
          'String contains an unpaired high surrogate at '
          '${pathOrRoot(path)}',
        );
      }
      index++;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      throw FormatException(
        'String contains an unpaired low surrogate at ${pathOrRoot(path)}',
      );
    }
  }
}

int _compareUtf16(String first, String second) {
  final commonLength = first.length < second.length
      ? first.length
      : second.length;
  for (var index = 0; index < commonLength; index++) {
    final difference = first.codeUnitAt(index) - second.codeUnitAt(index);
    if (difference != 0) return difference;
  }
  return first.length - second.length;
}

String _pointerEscape(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

String pathOrRoot(String path) => path.isEmpty ? '<root>' : path;
