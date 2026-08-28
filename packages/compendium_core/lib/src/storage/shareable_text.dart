import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart';

import '../util/text_sanitizer.dart';

/// Canonicalizes text before it crosses a shareable persistence boundary.
///
/// NFC is applied before sanitizing so canonically equivalent input has one
/// stored representation while invisible/control characters are removed.
String normalizeShareableText(String value) =>
    sanitizeImportedText(nfc(value), allowLineBreaks: true);

/// Recursively canonicalizes JSON-compatible values, including object keys.
Object? normalizeShareableJson(Object? value) {
  if (value is String) return normalizeShareableText(value);
  if (value is List) {
    return [for (final item in value) normalizeShareableJson(item)];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        normalizeShareableText(entry.key.toString()): normalizeShareableJson(
          entry.value,
        ),
    };
  }
  return value;
}

/// Decodes, recursively canonicalizes, and re-encodes a JSON value.
String normalizeShareableJsonText(String value) {
  final decoded = jsonDecode(value);
  return jsonEncode(normalizeShareableJson(decoded));
}
