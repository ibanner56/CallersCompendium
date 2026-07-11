import 'dart:math';

/// Minimal RFC 4122 v4 UUID generator.
///
/// Kept dependency-free on purpose: the core package should not pull in
/// third-party packages for 30 lines of bit twiddling. Entity IDs throughout
/// the domain model are plain strings produced by [uuidV4].
final Random _random = Random.secure();

String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
