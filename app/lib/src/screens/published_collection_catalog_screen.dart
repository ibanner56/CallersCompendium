import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../published_collections/published_collection_manifest.dart';
import '../published_collections/published_collection_service.dart';
import '../theme/app_spacing.dart';

typedef PublishedCollectionImportCallback =
    Future<void> Function(
      PublishedCollectionEntry entry,
      List<int> archiveBytes,
    );

class PublishedCollectionStatus {
  const PublishedCollectionStatus({
    required this.heldCount,
    required this.importedVersion,
  });

  final int heldCount;
  final String? importedVersion;
}

/// Full-screen route for the signed, immutable dance-collection catalog.
///
/// Settings keeps this route while Collection embeds [PublishedCollectionCatalog]
/// below its import-source selector.
class PublishedCollectionCatalogScreen extends StatelessWidget {
  const PublishedCollectionCatalogScreen({
    super.key,
    this.service,
    this.statusLoader,
    required this.onImport,
  });

  final PublishedCollectionService? service;
  final Future<PublishedCollectionStatus> Function(
    String collectionId,
    String version,
  )?
  statusLoader;
  final PublishedCollectionImportCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.publishedCollectionsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          PublishedCollectionCatalog(
            service: service,
            statusLoader: statusLoader,
            onImport: onImport,
          ),
        ],
      ),
    );
  }
}

/// Signed catalog content usable from either a full-screen route or an importer.
class PublishedCollectionCatalog extends StatefulWidget {
  const PublishedCollectionCatalog({
    super.key,
    this.service,
    this.statusLoader,
    required this.onImport,
  });

  final PublishedCollectionService? service;
  final Future<PublishedCollectionStatus> Function(
    String collectionId,
    String version,
  )?
  statusLoader;
  final PublishedCollectionImportCallback onImport;

  @override
  State<PublishedCollectionCatalog> createState() =>
      _PublishedCollectionCatalogState();
}

class _PublishedCollectionCatalogState
    extends State<PublishedCollectionCatalog> {
  late final PublishedCollectionService _service =
      widget.service ?? PublishedCollectionService();
  late final Future<PublishedCollectionManifest> _catalog = _service
      .fetchCatalog();
  final _statusByEntry =
      <(String, String), Future<PublishedCollectionStatus>>{};
  PublishedCollectionEntry? _loadingEntry;
  PublishedCollectionFetchFailure? _archiveError;
  PublishedCollectionEntry? _archiveErrorEntry;

  Future<void> _import(PublishedCollectionEntry entry) async {
    if (!entry.isSupported || _loadingEntry != null) return;
    setState(() {
      _loadingEntry = entry;
      _archiveError = null;
      _archiveErrorEntry = null;
    });
    try {
      final bytes = await _service.fetchArchive(entry);
      if (!mounted) return;
      await widget.onImport(entry, bytes);
      if (mounted) {
        _statusByEntry.removeWhere((key, _) => key.$1 == entry.id);
      }
    } on PublishedCollectionFetchException catch (error) {
      // diagnostics: silent — this expected typed failure is shown inline.
      if (!mounted) return;
      setState(() {
        _archiveError = error.code;
        _archiveErrorEntry = entry;
      });
    } finally {
      if (mounted) setState(() => _loadingEntry = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<PublishedCollectionManifest>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: Semantics(
                label: l10n.publishedCollectionsLoading,
                child: const CircularProgressIndicator(),
              ),
            ),
          );
        }
        final error = snapshot.error;
        if (error != null || !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.publishedCollectionsUnavailable,
              textAlign: TextAlign.center,
            ),
          );
        }
        final entries = snapshot.data!.collections;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.publishedCollectionsDescription,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final entry in entries) _buildEntry(context, entry),
          ],
        );
      },
    );
  }

  Widget _buildEntry(BuildContext context, PublishedCollectionEntry entry) {
    final l10n = AppLocalizations.of(context);
    final loading = _loadingEntry == entry;
    final unsupported = !entry.isSupported;
    final archiveError = _archiveError != null && _archiveErrorEntry == entry;
    final statusFuture = widget.statusLoader == null
        ? null
        : _statusByEntry.putIfAbsent((
            entry.id,
            entry.version,
          ), () => widget.statusLoader!(entry.id, entry.version));
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publishedCollectionDetails(
                entry.id,
                entry.version,
                entry.danceCount,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publishedCollectionPermission(
                entry.license,
                entry.permission.grantor,
                entry.permission.holder,
                entry.permission.basis,
                entry.permission.fields.isEmpty
                    ? l10n.publishedCollectionNoCoveredFields
                    : entry.permission.fields.join(', '),
              ),
            ),
            if (statusFuture != null)
              FutureBuilder<PublishedCollectionStatus>(
                future: statusFuture,
                builder: (context, snapshot) {
                  final status = snapshot.data;
                  if (status == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.publishedCollectionHeldCount(
                          status.heldCount,
                          entry.danceCount,
                        ),
                      ),
                      if (status.importedVersion != null)
                        Text(
                          l10n.publishedCollectionImportedVersion(
                            status.importedVersion!,
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (entry.supersedes != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.publishedCollectionSupersedes(entry.supersedes!)),
            ],
            if (unsupported) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.publishedCollectionUnsupported,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (archiveError) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.publishedCollectionsUnavailable,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: unsupported || _loadingEntry != null
                    ? null
                    : () => _import(entry),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(l10n.publishedCollectionImport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
