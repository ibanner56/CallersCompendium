import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:unorm_dart/unorm_dart.dart';

import 'eff_long_wordlist.dart';

/// The number of words in a sync ID.
const int syncIdWordCount = 4;

/// The maximum number of Unicode code points in one normalized word.
const int syncIdMaxWordCodePoints = 32;

/// The maximum total number of Unicode code points in a normalized ID.
const int syncIdMaxCodePoints = 131;

/// The strength at which the client should show its advisory warning.
const double syncIdStrengthWarningBits = 40;

/// A normalized, structurally valid Device Sync identifier.
class SyncId {
  SyncId._(this.value, this.words);

  /// Parses and normalizes [raw], or throws [FormatException].
  factory SyncId.parse(String raw) {
    final normalized = normalizeSyncId(raw);
    validateSyncId(normalized);
    return SyncId._(normalized, List.unmodifiable(normalized.split('-')));
  }

  /// Returns a parsed ID, or `null` when [raw] is structurally invalid.
  static SyncId? tryParse(String raw) {
    try {
      return SyncId.parse(raw);
    } on FormatException {
      return null;
    }
  }

  /// The normalized ID that is used for authentication and storage.
  final String value;

  /// The normalized words in [value].
  final List<String> words;

  /// An advisory estimate; callers must never use it as an acceptance gate.
  double get strengthBits => estimateSyncIdStrengthBits(value);

  /// Whether the advisory strength warning should be shown.
  bool get isBelowStrengthWarning => strengthBits < syncIdStrengthWarningBits;

  @override
  String toString() => value;
}

/// Trims, NFC-normalizes, and lowercases a sync ID.
///
/// This is the one definition imported by both the client and Athenaeum server.
String normalizeSyncId(String value) => nfc(value.trim()).toLowerCase();

/// Validates the structural sync-ID rule after normalization.
void validateSyncId(String value) {
  final normalized = normalizeSyncId(value);
  final words = normalized.split('-');
  if (words.length != syncIdWordCount) {
    throw const FormatException(
      'sync ID must contain exactly four hyphen-separated words',
    );
  }
  if (normalized.runes.length > syncIdMaxCodePoints) {
    throw const FormatException(
      'sync ID must not exceed 131 Unicode code points',
    );
  }
  for (final word in words) {
    final codePoints = word.runes.toList();
    if (codePoints.isEmpty || codePoints.length > syncIdMaxWordCodePoints) {
      throw const FormatException(
        'sync ID words must contain 1 to 32 Unicode code points',
      );
    }
    for (final codePoint in codePoints) {
      if (_isControl(codePoint) ||
          String.fromCharCode(codePoint).trim().isEmpty) {
        throw const FormatException(
          'sync ID words cannot contain whitespace or control characters',
        );
      }
    }
  }
}

/// Returns whether [value] is a valid normalized sync ID.
bool isValidSyncId(String value) {
  try {
    validateSyncId(value);
    return true;
  } on FormatException {
    return false;
  }
}

/// Generates a cryptographically random four-word EFF long-list ID.
SyncId generateSyncId() {
  return _generateSyncId(Random.secure());
}

/// Deterministic source hook for package tests; intentionally not barrel-exported.
@internal
SyncId generateSyncIdFromRandom(Random source) => _generateSyncId(source);

SyncId _generateSyncId(Random source) {
  while (true) {
    final words = <String>[];
    while (words.length < syncIdWordCount) {
      final word = effLongWordlist[source.nextInt(effLongWordlist.length)];
      if (word.contains('-')) continue;
      words.add(word);
    }
    final id = SyncId.parse(words.join('-'));
    if (!id.isBelowStrengthWarning) return id;
  }
}

/// Estimates the guess-rank strength of a structurally valid ID in bits.
///
/// This deliberately remains a warning-only heuristic. It is computed over the
/// normalized whole ID, so repeated words do not receive independent entropy.
/// It is not used by [SyncId.parse] or [validateSyncId].
double estimateSyncIdStrengthBits(String value) {
  final normalized = normalizeSyncId(value);
  if (!isValidSyncId(normalized)) return 0;
  final words = normalized.split('-');
  final uniqueWords = words.toSet();
  return uniqueWords
      .map(_estimateWordGuessBits)
      .fold<double>(0, (sum, bits) => sum + bits);
}

double _estimateWordGuessBits(String word) {
  const alphabetBits = 4.7;
  const maxWordBits = 13.0;
  final codePoints = word.runes.length;
  final distinctCodePoints = word.runes.toSet().length;
  final lengthBits = min(maxWordBits, codePoints * alphabetBits);

  // A repeated character is cheap to guess regardless of its length. This
  // keeps the meter useful for human-chosen words without rejecting them.
  if (distinctCodePoints == 1) return min(2.0, lengthBits);
  if (distinctCodePoints * 2 <= codePoints) return lengthBits * 0.65;
  return lengthBits;
}

/// Encodes the normalized ID as an unpadded RFC 4648 base64url token.
String encodeSyncCredential(String syncId) {
  final normalized = normalizeSyncId(syncId);
  validateSyncId(normalized);
  return base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
}

/// Decodes and normalizes an unpadded base64url credential.
String decodeSyncCredential(String credential) {
  if (credential.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(credential) ||
      credential.length % 4 == 1) {
    throw const FormatException('malformed sync credential');
  }
  try {
    final padding = (4 - credential.length % 4) % 4;
    final bytes = base64Url.decode('$credential${'=' * padding}');
    final decoded = utf8.decode(bytes, allowMalformed: false);
    final normalized = normalizeSyncId(decoded);
    validateSyncId(normalized);
    return normalized;
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('malformed sync credential');
  }
}

/// Derives the server-side storage key from [pepper] and a normalized ID.
///
/// The client never calls this function and never holds the server pepper.
String deriveSyncIdKey(String syncId, List<int> pepper) {
  final normalized = normalizeSyncId(syncId);
  validateSyncId(normalized);
  return Hmac(sha256, pepper).convert(utf8.encode(normalized)).toString();
}

bool _isControl(int codePoint) =>
    codePoint <= 0x1f || (codePoint >= 0x7f && codePoint <= 0x9f);
