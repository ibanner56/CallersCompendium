import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The tag-colour import boundary (issue #786).
///
/// `tags[].color` has always been decoded, but until tag colours rendered it
/// was inert data. Now it drives a painted chip, so an archive — a sharing
/// surface, and therefore untrusted — can influence what the user sees. These
/// cases pin the normalization at the boundary itself, not just in the helper.
String _archiveWith(Object? colorJson) => jsonEncode({
  'schemaVersion': 1,
  'exportedAt': '2026-01-01T00:00:00.000Z',
  'choreographers': <Object?>[],
  'publishedSources': <Object?>[],
  'tags': [
    // A null-aware element: passing null omits the key entirely, which is the
    // "archive carries no colour for this tag" case.
    {'id': 't1', 'name': 'chestnut', 'color': ?colorJson},
  ],
  'customFields': <Object?>[],
  'venues': <Object?>[],
  'dances': <Object?>[],
  'programs': <Object?>[],
});

Tag _decodeSingleTag(Object? colorJson) {
  final result = decodeArchive(_archiveWith(colorJson));
  expect(
    result.errors,
    isEmpty,
    reason: 'a malformed colour must never cost the user the tag itself',
  );
  expect(result.archive.tags, hasLength(1));
  return result.archive.tags.single;
}

void main() {
  group('archive tag colour', () {
    test('round-trips an opaque colour', () {
      expect(_decodeSingleTag(0xFF2196F3).color, 0xFF2196F3);
    });

    test('an absent colour decodes as "no colour assigned"', () {
      expect(_decodeSingleTag(null).color, isNull);
    });

    test('an explicit JSON null decodes as "no colour assigned"', () {
      final result = decodeArchive(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'tags': [
            {'id': 't1', 'name': 'chestnut', 'color': null},
          ],
          'dances': <Object?>[],
        }),
      );
      expect(result.errors, isEmpty);
      expect(result.archive.tags.single.color, isNull);
    });

    test('a transparent colour is forced opaque', () {
      // Alpha 0 would paint nothing: the chip would look uncoloured while the
      // stored value claimed otherwise.
      expect(_decodeSingleTag(0x00FF0000).color, 0xFFFF0000);
    });

    test('a string colour degrades to null and keeps the tag', () {
      final tag = _decodeSingleTag('#FF0000');
      expect(tag.color, isNull);
      expect(tag.name, 'chestnut');
    });

    test('a fractional colour degrades to null and keeps the tag', () {
      final tag = _decodeSingleTag(1.5);
      expect(tag.color, isNull);
      expect(tag.name, 'chestnut');
    });

    test('an out-of-range colour degrades to null and keeps the tag', () {
      final tag = _decodeSingleTag(0x1FFFF0000);
      expect(tag.color, isNull);
      expect(tag.name, 'chestnut');
    });

    test('a negative colour degrades to null and keeps the tag', () {
      final tag = _decodeSingleTag(-1);
      expect(tag.color, isNull);
      expect(tag.name, 'chestnut');
    });

    test('re-encoding a decoded archive is stable', () {
      // The codec's round-trip identity property: normalizing on read must not
      // make our own exports unstable. Opaque in, opaque out.
      final source = encodeArchive(
        CompendiumArchive(
          exportedAt: DateTime.utc(2026),
          tags: [Tag(id: 't1', name: 'chestnut', color: 0xFF2196F3)],
        ),
      );
      expect(encodeArchive(decodeArchive(source).archive), source);
    });
  });
}
