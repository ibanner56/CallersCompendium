import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/published_collections/published_collection_config.dart';
import 'package:compendium_app/src/published_collections/published_collection_service.dart';
import 'package:compendium_app/src/screens/published_collection_catalog_screen.dart';

import 'support/l10n_harness.dart';

void main() {
  testWidgets('caches collection status while the entry rebuilds', (
    tester,
  ) async {
    final archiveBytes = utf8.encode('{}');
    final digest = sha256.convert(archiveBytes).toString();
    final manifest = jsonEncode({
      'manifestSchema': {'major': 1, 'minor': 0},
      'minReaderVersion': '0.0.1',
      'collections': [
        {
          'id': 'foda-1-1',
          'version': '1.0.0',
          'title': 'FODA',
          'archiveUrl':
              'https://analect.callerscompendium.com/collections/foda.json',
          'archiveBytes': archiveBytes.length,
          'sha256': digest,
          'danceCount': 0,
          'license': 'CC0-1.0',
          'permission': {
            'grantor': 'Grantor',
            'holder': 'Holder',
            'basis': 'Basis',
            'license': 'CC0-1.0',
            'fields': <String>[],
          },
          'requiredCapabilities': <String>[],
        },
      ],
    });
    final service = PublishedCollectionService(
      bytesFetcher: (uri, _) async {
        if (uri.toString() == kPublishedCollectionManifestUrl) {
          return utf8.encode(manifest);
        }
        if (uri.toString() == kPublishedCollectionSignatureUrl) {
          return utf8.encode('signature');
        }
        return archiveBytes;
      },
      signatureVerifier: (_, _) async => true,
    );
    var statusLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: PublishedCollectionCatalogScreen(
          service: service,
          statusLoader: (_) async {
            statusLoads++;
            return const PublishedCollectionStatus(
              heldCount: 0,
              importedVersion: null,
            );
          },
          onImport: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(statusLoads, 1);

    await tester.tap(find.text('Import collection'));
    await tester.pumpAndSettle();
    expect(statusLoads, 1);
  });
}
