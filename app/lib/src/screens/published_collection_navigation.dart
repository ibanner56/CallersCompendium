import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/import_io.dart';
import '../data/repositories_scope.dart';
import '../published_collections/published_collection_manifest.dart';
import 'import_review_screen.dart';
import 'published_collection_catalog_screen.dart';

/// Opens the signed catalog from either Collection or Settings.
Future<void> pushPublishedCollectionCatalog(BuildContext context) async {
  final navigator = Navigator.of(context);
  final repositories = RepositoriesScope.of(context);
  Future<List<CollectionImportEvent>> eventsFuture = repositories
      .collectionImports
      .listAll();
  Future<Map<(String, String), int>>? heldCountsFuture;
  await navigator.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PublishedCollectionCatalogScreen(
        statusLoader: (collectionId, version) async {
          final events = await eventsFuture;
          final heldCounts = await (heldCountsFuture ??= repositories
              .collectionImports
              .heldCounts(
                events.map((event) => (event.collectionId, event.version)),
              ));
          final matching = events
              .where((event) => event.collectionId == collectionId)
              .map((event) => event.version)
              .toList();
          return PublishedCollectionStatus(
            heldCount: heldCounts[(collectionId, version)] ?? 0,
            importedVersion: matching.isEmpty
                ? null
                : matching.reduce(
                    (a, b) =>
                        comparePublishedCollectionVersions(a, b) >= 0 ? a : b,
                  ),
          );
        },
        onImport: (entry, archiveBytes) async {
          final json = utf8.decode(archiveBytes);
          final metadata = PublishedCollectionMetadata(
            collectionId: entry.id,
            collectionVersion: entry.version,
            archiveDigest: entry.sha256,
            permission: entry.permission.declaration,
            license: entry.license,
          );
          final source = ImportSource(
            kind: ImportSourceKind.publishedCollection,
            adapterFactory: () => PublishedCollectionAdapter(metadata),
            preselected: true,
          );
          await navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ImportReviewScreen(
                sources: [source],
                publishedCollection: PublishedCollectionSeed(
                  json: json,
                  metadata: metadata,
                ),
              ),
            ),
          );
          eventsFuture = repositories.collectionImports.listAll();
          heldCountsFuture = null;
        },
      ),
    ),
  );
}
