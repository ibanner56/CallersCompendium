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
/// Invisible/control characters are removed before NFC so canonically equivalent
/// input has one stored representation after the removed characters no longer
/// interrupt combining sequences.
String normalizeShareableText(String value) =>
    nfc(sanitizeShareableText(value));

/// The first half of [normalizeShareableText]: sanitized, but **not** composed.
///
/// This is what §4.1's collision carve-out means by storing a value
/// "un-normalised". Composition is what the carve-out defers — a row whose NFC
/// target another row already holds keeps its own bytes — and nothing else is.
/// Sanitisation is a different rule with no carve-out: `docs/design/sync-spec.md`
/// §4.6 binds it to *every* write path, on the grounds that a record's hash
/// must identify its visible text. Writing the caller's raw string instead would
/// let a normalisation collision smuggle a `U+200B` past the sanitiser, which is
/// a second defect wearing the first one's excuse.
///
/// Because [normalizeShareableText] is defined over this function, a value
/// stored through it always derives the same target it would have been
/// normalized to. That relationship is what makes the skip recorded alongside
/// it re-attemptable: the pass re-derives the target from the stored bytes.
String sanitizeShareableText(String value) =>
    sanitizeImportedText(value, allowLineBreaks: true);

/// Recursively canonicalizes JSON-compatible values, including object keys.
Object? normalizeShareableJson(Object? value) {
  if (value is String) return normalizeShareableText(value);
  if (value is List) {
    return [for (final item in value) normalizeShareableJson(item)];
  }
  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key is String
          ? normalizeShareableText(entry.key as String)
          : throw ArgumentError.value(
              entry.key,
              'key',
              'JSON object keys must be strings',
            );
      if (normalized.containsKey(key)) {
        throw ShareableJsonKeyCollision(key);
      }
      normalized[key] = normalizeShareableJson(entry.value);
    }
    return normalized;
  }
  return value;
}

/// [normalizeShareableJson] with composition deferred: every string —
/// including every object key — is sanitized, none is NFC-composed.
///
/// What a `shareable` settings value is stored as when its keys collide only
/// under NFC. §4.1's carve-out defers **composition**; §4.6 binds the sanitiser
/// to every write path with no carve-out at all, so keeping the caller's object
/// verbatim would persist a `U+200B` under a rule that says nothing about
/// invisible characters. Same relationship as [sanitizeShareableText] to
/// [normalizeShareableText], one level up.
///
/// Still throws [ShareableJsonKeyCollision] when two keys collide under the
/// **sanitiser alone** — a pair differing only by an invisible character. That
/// is not a normalisation collision and §4.1's carve-out does not reach it:
/// there is no sanitised form of the object that keeps both entries, so the
/// caller learns rather than silently losing one.
Object? sanitizeShareableJson(Object? value) {
  if (value is String) return sanitizeShareableText(value);
  if (value is List) {
    return [for (final item in value) sanitizeShareableJson(item)];
  }
  if (value is Map) {
    final sanitized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key is String
          ? sanitizeShareableText(entry.key as String)
          : throw ArgumentError.value(
              entry.key,
              'key',
              'JSON object keys must be strings',
            );
      if (sanitized.containsKey(key)) {
        throw ShareableJsonKeyCollision(key);
      }
      sanitized[key] = sanitizeShareableJson(entry.value);
    }
    return sanitized;
  }
  return value;
}

/// Decodes, recursively canonicalizes, and re-encodes a JSON value.
String normalizeShareableJsonText(String value) {
  final decoded = jsonDecode(value);
  return jsonEncode(normalizeShareableJson(decoded));
}
