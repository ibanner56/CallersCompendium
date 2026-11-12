import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/published_collections/published_collection_config.dart';
import 'package:compendium_app/src/published_collections/published_collection_manifest.dart';
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
          'id': 'foda-2',
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
      containsAll(<String>['foda-1-1/1.0.0', 'foda-2/2.0.0']),
    );
    expect(find.textContaining('License: CC0-1.0'), findsNWidgets(2));
    expect(
      find.textContaining('Permission: Grantor grants Holder'),
      findsNWidgets(2),
    );
    expect(find.textContaining('Covered fields: none'), findsNWidgets(2));

    await tester.tap(find.text('Import collection').first);
    await tester.pumpAndSettle();
    // Only the imported id's status is refreshed.
    expect(statusLoads, 3);
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
            'id': 'foda-$version',
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

  group('only the newest version of a collection is importable (SUPPLY-2)', () {
    final archiveBytes = utf8.encode('{}');
    final digest = sha256.convert(archiveBytes).toString();
    final manifest = jsonEncode({
      'manifestSchema': {'major': 1, 'minor': 0},
      'minReaderVersion': '0.0.1',
      'collections': [
        for (final version in ['2.0.0', '1.0.0', '10.0.0-rc.1', '1.9.0'])
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
    PublishedCollectionService service() => PublishedCollectionService(
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

    Future<void> pump(
      WidgetTester tester, {
      String? importedVersion,
      required List<String> imported,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: PublishedCollectionCatalogScreen(
            service: service(),
            statusLoader: (_, _) async => PublishedCollectionStatus(
              heldCount: 0,
              importedVersion: importedVersion,
            ),
            onImport: (entry, _) async => imported.add(entry.version),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a catalog listing several versions offers only the newest', (
      tester,
    ) async {
      final imported = <String>[];
      await pump(tester, imported: imported);

      expect(find.text('FODA 10.0.0-rc.1'), findsOneWidget);
      expect(find.text('FODA 2.0.0'), findsNothing);
      expect(find.text('FODA 1.0.0'), findsNothing);
      expect(find.text('FODA 1.9.0'), findsNothing);
      expect(find.text('Import collection'), findsOneWidget);
      await tester.tap(find.text('Import collection'));
      await tester.pumpAndSettle();
      expect(imported, ['10.0.0-rc.1']);
    });

    testWidgets('an entry older than the imported version cannot be imported', (
      tester,
    ) async {
      final imported = <String>[];
      await pump(tester, importedVersion: '11.0.0', imported: imported);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import collection'),
      );
      expect(button.onPressed, isNull);
      expect(imported, isEmpty);
    });
  });

  test('latestPublishedCollectionEntries keeps the highest version per id', () {
    PublishedCollectionEntry entry(String id, String version) =>
        PublishedCollectionEntry(
          id: id,
          version: version,
          title: 't',
          archiveUrl: Uri.parse('https://example.com/a.json'),
          archiveBytes: 1,
          sha256: 'a' * 64,
          danceCount: 0,
          license: 'l',
          permission: const PublishedCollectionPermission(
            grantor: 'g',
            holder: 'h',
            basis: 'b',
            license: 'l',
            fields: [],
          ),
          requiredCapabilities: const [],
        );
    final latest = latestPublishedCollectionEntries([
      entry('a', '1.0.0'),
      entry('b', '1.0.0'),
      entry('a', '2.0.0'),
      entry('a', '1.5.0'),
    ]);
    expect(latest.map((e) => '${e.id}@${e.version}'), ['a@2.0.0', 'b@1.0.0']);
    expect(isOlderThanImportedPublishedVersion('1.0.0', '2.0.0'), isTrue);
    expect(isOlderThanImportedPublishedVersion('2.0.0', '2.0.0'), isFalse);
    expect(isOlderThanImportedPublishedVersion('2.0.0', null), isFalse);
  });

  group('catalog and archive failures', () {
    final archiveBytes = utf8.encode('{}');
    final digest = sha256.convert(archiveBytes).toString();
    String manifest({int major = 1}) => jsonEncode({
      'manifestSchema': {'major': major, 'minor': 0},
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

    late _RecordingSink sink;
    setUp(() {
      sink = _RecordingSink();
      installCaughtErrorLog(sink);
    });
    tearDown(resetCaughtErrorLogForTesting);

    Future<void> pump(
      WidgetTester tester,
      PublishedCollectionService service,
    ) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: PublishedCollectionCatalogScreen(
          service: service,
          onImport: (_, _) async {},
        ),
      ),
    );

    testWidgets('offline reads as offline, offers Retry, and is logged once', (
      tester,
    ) async {
      var online = false;
      final service = PublishedCollectionService(
        bytesFetcher: (uri, _) async {
          if (!online) throw const SocketException('no route');
          return uri.toString() == kPublishedCollectionManifestUrl
              ? utf8.encode(manifest())
              : utf8.encode('signature');
        },
        signatureVerifier: (_, _) async => true,
      );
      await pump(tester, service);
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be reached'), findsOneWidget);
      expect(find.textContaining('temporarily unavailable'), findsNothing);
      expect(sink.sources, [
        'published_collection_catalog_screen._loadCatalog',
      ]);
      expect(sink.errors.single, contains('unavailable'));

      // A rebuild does not log again; Retry fetches again and recovers.
      online = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('FODA'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(sink.sources, hasLength(1));
    });

    testWidgets('a newer catalog format says the app needs updating', (
      tester,
    ) async {
      final service = PublishedCollectionService(
        bytesFetcher: (uri, _) async =>
            uri.toString() == kPublishedCollectionManifestUrl
            ? utf8.encode(manifest(major: 2))
            : utf8.encode('signature'),
        signatureVerifier: (_, _) async => true,
      );
      await pump(tester, service);
      await tester.pumpAndSettle();

      expect(find.textContaining('need a newer app version'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(sink.errors.single, contains('unsupported'));
    });

    testWidgets('an integrity failure stays "temporarily unavailable"', (
      tester,
    ) async {
      final service = PublishedCollectionService(
        bytesFetcher: (uri, _) async =>
            uri.toString() == kPublishedCollectionManifestUrl
            ? utf8.encode(manifest())
            : utf8.encode('signature'),
        signatureVerifier: (_, _) async => false,
      );
      await pump(tester, service);
      await tester.pumpAndSettle();

      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(sink.errors.single, contains('invalidSignature'));
    });

    testWidgets('a failed archive download is classified, logged, and can be '
        'retried', (tester) async {
      var archiveOnline = false;
      final service = PublishedCollectionService(
        bytesFetcher: (uri, _) async {
          if (uri.toString() == kPublishedCollectionManifestUrl) {
            return utf8.encode(manifest());
          }
          if (uri.toString() == kPublishedCollectionSignatureUrl) {
            return utf8.encode('signature');
          }
          if (!archiveOnline) throw const SocketException('no route');
          return archiveBytes;
        },
        signatureVerifier: (_, _) async => true,
      );
      var imports = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: PublishedCollectionCatalogScreen(
            service: service,
            onImport: (_, _) async => imports++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import collection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be reached'), findsOneWidget);
      expect(sink.sources, ['published_collection_catalog_screen._import']);

      archiveOnline = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(imports, 1);
      expect(find.textContaining('could not be reached'), findsNothing);
    });
  });
}

class _RecordingSink implements CrashLogSink {
  final List<String> sources = [];
  final List<String> errors = [];

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    sources.add(source);
    errors.add(error.toString());
  }
}
