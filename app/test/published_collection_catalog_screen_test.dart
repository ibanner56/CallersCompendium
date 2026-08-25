import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/published_collections/published_collection_config.dart';
import 'package:compendium_app/src/published_collections/published_collection_service.dart';
import 'package:compendium_app/src/screens/published_collection_catalog_screen.dart';

import 'support/l10n_harness.dart';

void main() {
  testWidgets('refreshes every version status after an import', (tester) async {
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
        {
          'id': 'foda-1-1',
          'version': '2.0.0',
          'title': 'FODA updated',
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
    final statusRequests = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: PublishedCollectionCatalogScreen(
          service: service,
          statusLoader: (collectionId, version) async {
            statusLoads++;
            statusRequests.add('$collectionId/$version');
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
    expect(statusLoads, 2);
    expect(
      statusRequests,
      containsAll(<String>['foda-1-1/1.0.0', 'foda-1-1/2.0.0']),
    );
    expect(find.textContaining('License: CC0-1.0'), findsNWidgets(2));
    expect(
      find.textContaining('Permission: Grantor grants Holder'),
      findsNWidgets(2),
    );
    expect(find.textContaining('Covered fields: none'), findsNWidgets(2));

    await tester.tap(find.text('Import collection').first);
    await tester.pumpAndSettle();
    expect(statusLoads, 4);
  });

  testWidgets('disables every import while an archive is loading', (
    tester,
  ) async {
    final archiveBytes = utf8.encode('{}');
    final digest = sha256.convert(archiveBytes).toString();
    final manifest = jsonEncode({
      'manifestSchema': {'major': 1, 'minor': 0},
      'minReaderVersion': '0.0.1',
      'collections': [
        for (final version in ['1.0.0', '2.0.0'])
          {
            'id': 'foda-1-1',
            'version': version,
            'title': 'FODA $version',
            'archiveUrl':
                'https://analect.callerscompendium.com/collections/$version.json',
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
    final archiveFetch = Completer<List<int>>();
    final service = PublishedCollectionService(
      bytesFetcher: (uri, _) async {
        if (uri.toString() == kPublishedCollectionManifestUrl) {
          return utf8.encode(manifest);
        }
        if (uri.toString() == kPublishedCollectionSignatureUrl) {
          return utf8.encode('signature');
        }
        return archiveFetch.future;
      },
      signatureVerifier: (_, _) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: PublishedCollectionCatalogScreen(
          service: service,
          onImport: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import collection').first);
    await tester.pump();

    final buttons = tester.widgetList<FilledButton>(
      find.widgetWithText(FilledButton, 'Import collection'),
    );
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => button.onPressed == null), isTrue);

    archiveFetch.complete(archiveBytes);
    await tester.pumpAndSettle();
  });
}
