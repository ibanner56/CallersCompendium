import 'package:flutter/material.dart';

import '../data/migration_guard.dart'
    show DatabaseDowngradeError, MigrationSnapshotAborted, SnapshotFailureCause;

/// Gates the app on a startup [future] — the schema migration / derived-index
/// back-fill run by `CompendiumRepositories.ensureMigrated()`. Shows a loading
/// screen while it runs (so nothing reads the derived indexes before they are
/// rebuilt), an error screen with retry if it fails, and [builder]'s content
/// once it completes.
///
/// One error is special-cased: a [DatabaseDowngradeError] (the on-disk data was
/// written by a newer build) shows that error's guidance and *no* Retry — the
/// only fix is to update the app, so retrying would just fail again.
class AppBootstrap extends StatelessWidget {
  const AppBootstrap({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
  });

  final Future<void> future;
  final WidgetBuilder builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Preparing your collection',
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is DatabaseDowngradeError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update_alt, size: 48),
                      const SizedBox(height: 8),
                      Text(error.message, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            );
          }
          // The user was asked to consent to migrating without a recoverable
          // backup (the pre-migration snapshot failed) and chose to abort, or
          // there was no way to ask (issue #442). Like the downgrade case this
          // is terminal with *no* Retry: retrying wouldn't create the backup —
          // the user must free space / fix the backups folder and reopen.
          if (error is MigrationSnapshotAborted) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_snapshotAbortedIcon(error.failure.cause), size: 48),
                      const SizedBox(height: 8),
                      Text(error.message, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  const Text('Could not prepare the collection.'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        return builder(context);
      },
    );
  }

  /// Picks a terminal-screen icon that reflects the *actual* snapshot-failure
  /// cause (issue #442 review): a storage glyph for a full disk, a
  /// folder-off glyph for an unwritable backups folder, and a generic warning
  /// otherwise — so the icon never misleads (it previously always showed
  /// `disc_full`, even for permission/unknown failures).
  IconData _snapshotAbortedIcon(SnapshotFailureCause cause) {
    switch (cause) {
      case SnapshotFailureCause.diskFull:
        return Icons.disc_full;
      case SnapshotFailureCause.unwritableBackupsDir:
        return Icons.folder_off_outlined;
      case SnapshotFailureCause.unknown:
        return Icons.warning_amber_rounded;
    }
  }
}
