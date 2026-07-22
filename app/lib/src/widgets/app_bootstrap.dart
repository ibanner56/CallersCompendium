import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/migration_guard.dart'
    show DatabaseDowngradeError, MigrationSnapshotAborted, SnapshotFailureCause;

/// Gates the app on a startup [future] — the schema migration / derived-index
/// back-fill run by `CompendiumRepositories.ensureMigrated()`. Shows a loading
/// screen while it runs (so nothing reads the derived indexes before they are
/// rebuilt), an error screen with retry if it fails, and [builder]'s content
/// once it completes.
///
/// While the derived-index rebuild runs, [rebuildProgress] (when supplied and
/// reporting a non-empty collection) drives a determinate progress indicator so
/// a large post-migration rebuild shows how far along it is instead of an
/// indeterminate spinner that can look hung (#440). Ordinary launches (no
/// rebuild owed) keep the plain spinner.
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
    this.rebuildProgress,
  });

  final Future<void> future;
  final WidgetBuilder builder;
  final VoidCallback onRetry;

  /// Optional live progress of the derived-index rebuild step of [future]. When
  /// `null` (the default) or reporting an empty collection, the loading screen
  /// shows an indeterminate spinner.
  final ValueListenable<DerivedRebuildProgress?>? rebuildProgress;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoading(context);
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
                  Text(l10n.appBootstrapError),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
          );
        }
        return builder(context);
      },
    );
  }

  /// The loading screen shown while [future] runs. Uses an indeterminate
  /// spinner unless [rebuildProgress] reports an in-progress rebuild over a
  /// non-empty collection, in which case it shows a determinate indicator and a
  /// percentage label (#440).
  Widget _buildLoading(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = rebuildProgress;
    if (progress == null) return _indeterminateLoading(l10n);
    return ValueListenableBuilder<DerivedRebuildProgress?>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value == null || value.total == 0) {
          return _indeterminateLoading(l10n);
        }
        final percent = (value.fraction * 100).round();
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: value.fraction,
                    semanticsLabel: l10n.appBootstrapRebuildingIndex,
                    semanticsValue: '$percent%',
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.appBootstrapRebuildingIndexProgress(percent)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _indeterminateLoading(AppLocalizations l10n) => Scaffold(
    body: Center(
      child: CircularProgressIndicator(
        semanticsLabel: l10n.appBootstrapPreparing,
      ),
    ),
  );

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
