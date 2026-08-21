import 'dart:convert';

import 'package:compendium_app/src/published_collections/published_collection_config.dart';
import 'package:compendium_app/src/published_collections/published_collection_manifest.dart';
import 'package:compendium_app/src/published_collections/published_collection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires the archive digest to match the signed entry', () async {
    final archive = utf8.encode('archive');
    final service = PublishedCollectionService(
      bytesFetcher: (uri, maxBytes) async => archive,
      signatureVerifier: (bytes, signature) async => true,
    );
    final entry = PublishedCollectionEntry(
      id: 'test',
      version: '1',
      title: 'Test',
      archiveUrl: Uri.parse(
        'https://analect.callerscompendium.com/collections/test.json',
      ),
      archiveBytes: archive.length,
      sha256: List<String>.filled(64, 'a').join(),
      danceCount: 1,
      license: 'CC0-1.0',
      permission: const PublishedCollectionPermission(
        grantor: 'Publisher',
        holder: 'Publisher',
        basis: 'publisher',
        license: 'CC0-1.0',
        fields: [],
      ),
      requiredCapabilities: const [],
    );

    expect(
      () => service.fetchArchive(entry),
      throwsA(
        isA<PublishedCollectionFetchException>().having(
          (error) => error.code,
          'code',
          PublishedCollectionFetchFailure.digestMismatch,
        ),
      ),
    );
  });

  test('requires the archive body to end at the signed byte count', () async {
    final service = PublishedCollectionService(
      bytesFetcher: (uri, maxBytes) async => [1, 2],
    );
    final entry = PublishedCollectionEntry(
      id: 'test',
      version: '1',
      title: 'Test',
      archiveUrl: Uri.parse(
        'https://ibanner56.github.io/Compendium-Analect/collections/test.json',
      ),
      archiveBytes: 3,
      sha256: List<String>.filled(64, 'a').join(),
      danceCount: 1,
      license: 'CC0-1.0',
      permission: const PublishedCollectionPermission(
        grantor: 'Publisher',
        holder: 'Publisher',
        basis: 'publisher',
        license: 'CC0-1.0',
        fields: [],
      ),
      requiredCapabilities: const [],
    );

    expect(
      () => service.fetchArchive(entry),
      throwsA(
        isA<PublishedCollectionFetchException>().having(
          (error) => error.code,
          'code',
          PublishedCollectionFetchFailure.byteCountMismatch,
        ),
      ),
    );
  });

  test('does not fetch an archive requiring an unknown capability', () async {
    var archiveFetched = false;
    final service = PublishedCollectionService(
      bytesFetcher: (uri, maxBytes) async {
        if (uri.path.endsWith('.sig')) {
          return utf8.encode('signature');
        }
        if (uri.toString() == kPublishedCollectionManifestUrl) {
          return utf8.encode(
            jsonEncode({
              'manifestSchema': {'major': 1, 'minor': 0},
              'minReaderVersion': '0.1.0',
              'collections': [
                {
                  'id': 'future',
                  'version': '1',
                  'title': 'Future',
                  'archiveUrl':
                      'https://analect.callerscompendium.com/future.json',
                  'archiveBytes': 1,
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
                  'requiredCapabilities': ['futureCapability'],
                },
              ],
            }),
          );
        }
        archiveFetched = true;
        return [1];
      },
      signatureVerifier: (bytes, signature) async => true,
    );
    final manifest = await service.fetchCatalog();

    expect(manifest.collections.single.isSupported, isFalse);
    expect(
      () => service.fetchArchive(manifest.collections.single),
      throwsA(
        isA<PublishedCollectionFetchException>().having(
          (error) => error.code,
          'code',
          PublishedCollectionFetchFailure.unsupported,
        ),
      ),
    );
    expect(archiveFetched, isFalse);
  });
}
