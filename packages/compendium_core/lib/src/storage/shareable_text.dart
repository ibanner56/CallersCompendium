import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart';

import '../util/text_sanitizer.dart';

/// Raised when canonicalizing a JSON object would merge two distinct keys.
class ShareableJsonKeyCollision implements Exception {
  const ShareableJsonKeyCollision(this.normalizedKey);

  final String normalizedKey;

  @override
  String toString() =>
      'ShareableJsonKeyCollision: "$normalizedKey" has multiple source keys';
}

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
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key is String ? normalizeShareableText(entry.key as String) : throw ArgumentError.value(entry.key, 'key', 'JSON object keys must be strings');
      if (normalized.containsKey(key)) {
        throw ShareableJsonKeyCollision(key);
      }
      normalized[key] = normalizeShareableJson(entry.value);
    }
    return normalized;
  }
  return value;
}

/// Decodes, recursively canonicalizes, and re-encodes a JSON value.
String normalizeShareableJsonText(String value) {
  final decoded = jsonDecode(value);
  return jsonEncode(normalizeShareableJson(decoded));
}
