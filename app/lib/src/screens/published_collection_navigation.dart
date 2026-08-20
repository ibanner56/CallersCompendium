import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/import_io.dart';
import '../data/repositories_scope.dart';
import 'import_review_screen.dart';
import 'published_collection_catalog_screen.dart';

/// Opens the signed catalog from either Collection or Settings.
Future<void> pushPublishedCollectionCatalog(BuildContext context) async {
  final navigator = Navigator.of(context);
  final repositories = RepositoriesScope.of(context);
  await navigator.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PublishedCollectionCatalogScreen(
        statusLoader: (collectionId) async {
          final events = await repositories.collectionImports.listAll();
          final matching = events
              .where((event) => event.collectionId == collectionId)
              .map((event) => event.version)
              .toList();
          final held = await repositories.collectionImports.heldCount(
            collectionId,
          );
          return PublishedCollectionStatus(
            heldCount: held,
            importedVersion: matching.isEmpty
                ? null
                : matching.reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
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
        },
      ),
    ),
  );
}
