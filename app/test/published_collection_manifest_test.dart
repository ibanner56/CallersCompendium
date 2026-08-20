import 'dart:convert';

import 'package:compendium_app/src/published_collections/published_collection_manifest.dart';
import 'package:compendium_app/src/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a signed collection entry and ignores metadata fields', () {
    final manifest = PublishedCollectionManifest.parse(
      jsonEncode({
        'manifestSchema': {'major': 1, 'minor': 0},
        'minReaderVersion': '0.1.0',
        'publisher': {'name': 'Analect'},
        'collections': [
          {
            'id': 'foda-1-1',
            'version': '1.1',
            'title': 'FODA 1.1',
            'archiveUrl':
                'https://analect.callerscompendium.com/collections/'
                'foda-1-1.json',
            'archiveBytes': 800,
            'sha256': List<String>.filled(64, 'a').join(),
            'danceCount': 800,
            'license': 'CC BY-SA 4.0',
            'permission': {
              'grantor': 'The publisher',
              'holder': 'The choreographer',
              'basis': 'author',
              'license': 'CC BY-SA 4.0',
              'fields': ['commentary'],
            },
            'requiredCapabilities': ['compositePhraseStructureV1'],
            'supersedes': null,
            'metadata': 'ignored',
          },
        ],
      }),
      readerVersion: SemVerForTest.current,
    );

    expect(manifest.collections, hasLength(1));
    expect(manifest.collections.single.id, 'foda-1-1');
    expect(
      manifest.collections.single.permission.fields,
      contains('commentary'),
    );
  });

  test('rejects unsupported schema major before accepting entries', () {
    expect(
      () => PublishedCollectionManifest.parse(
        jsonEncode({
          'manifestSchema': {'major': 2, 'minor': 0},
          'minReaderVersion': '0.1.0',
          'collections': const <Object?>[],
        }),
        readerVersion: SemVerForTest.current,
      ),
      throwsA(isA<PublishedCollectionFormatException>()),
    );
  });

  test('rejects an archive larger than the transport ceiling', () {
    expect(
      () => PublishedCollectionManifest.parse(
        jsonEncode({
          'manifestSchema': {'major': 1, 'minor': 0},
          'minReaderVersion': '0.1.0',
          'collections': [
            {
              'id': 'large',
              'version': '1',
              'title': 'Large',
              'archiveUrl': 'https://analect.callerscompendium.com/large.json',
              'archiveBytes': 1024 * 1024 * 1024 + 1,
              'sha256': List<String>.filled(64, 'a').join(),
              'danceCount': 1,
              'license': 'CC0-1.0',
              'permission': {
                'grantor': 'Publisher',
                'holder': 'Publisher',
                'basis': 'publisher',
                'license': 'CC0-1.0',
                'fields': const <Object?>[],
              },
            },
          ],
        }),
        readerVersion: SemVerForTest.current,
      ),
      throwsA(isA<PublishedCollectionFormatException>()),
    );
  });
}

/// Keeps the fixture independent of update-service construction while using
/// the same SemVer implementation as production parsing.
abstract final class SemVerForTest {
  static final current = SemVer.tryParse('0.1.0')!;
}
