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

/// The user-initiated catalog for signed, immutable dance collections.
class PublishedCollectionCatalogScreen extends StatefulWidget {
  const PublishedCollectionCatalogScreen({
    super.key,
    this.service,
    this.statusLoader,
    required this.onImport,
  });

  final PublishedCollectionService? service;
  final Future<PublishedCollectionStatus> Function(String collectionId)?
  statusLoader;
  final PublishedCollectionImportCallback onImport;

  @override
  State<PublishedCollectionCatalogScreen> createState() =>
      _PublishedCollectionCatalogScreenState();
}

class _PublishedCollectionCatalogScreenState
    extends State<PublishedCollectionCatalogScreen> {
  late final PublishedCollectionService _service =
      widget.service ?? PublishedCollectionService();
  late final Future<PublishedCollectionManifest> _catalog = _service
      .fetchCatalog();
  final _statusByCollectionId = <String, Future<PublishedCollectionStatus>>{};
  PublishedCollectionEntry? _loadingEntry;
  PublishedCollectionFetchFailure? _archiveError;
  PublishedCollectionEntry? _archiveErrorEntry;

  Future<void> _import(PublishedCollectionEntry entry) async {
    if (!entry.isSupported) return;
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
        _statusByCollectionId.remove(entry.id);
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.publishedCollectionsTitle)),
      body: FutureBuilder<PublishedCollectionManifest>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Semantics(
                label: l10n.publishedCollectionsLoading,
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final error = snapshot.error;
          if (error != null || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.publishedCollectionsUnavailable,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final entries = snapshot.data!.collections;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
      ),
    );
  }

  Widget _buildEntry(BuildContext context, PublishedCollectionEntry entry) {
    final l10n = AppLocalizations.of(context);
    final loading = _loadingEntry == entry;
    final unsupported = !entry.isSupported;
    final archiveError = _archiveError != null && _archiveErrorEntry == entry;
    final statusFuture = widget.statusLoader == null
        ? null
        : _statusByCollectionId.putIfAbsent(
            entry.id,
            () => widget.statusLoader!(entry.id),
          );
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
                onPressed: unsupported || loading ? null : () => _import(entry),
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
