import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../data/migration_error_labels.dart';
import '../data/migration_guard.dart'
    show
        DatabaseBelowFloorError,
        DatabaseDowngradeError,
        DatabaseRelocationBlocked,
        MigrationSnapshotAborted,
        SnapshotFailure,
        SnapshotFailureCause,
        snapshotBeforeMigrate;
import '../diagnostics/error_log.dart';

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
/// Two errors are terminal with *no* Retry:
/// - [DatabaseDowngradeError] (on-disk data written by a newer build): the only
///   fix is to update the app, so retrying would just fail again.
/// - [DatabaseBelowFloorError] (on-disk data written by a build older than the
///   minimum supported schema version): retrying cannot recover the data; the
///   user must run the bridge release to migrate it, or reset. [onBackUpAndReset]
///   and [onResetOnly] supply the recovery actions.
class AppBootstrap extends StatelessWidget {
  const AppBootstrap({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
    required this.onBackUpAndReset,
    required this.onResetOnly,
    this.rebuildProgress,
  });

  final Future<void> future;
  final WidgetBuilder builder;
  final VoidCallback onRetry;

  /// Called when the user confirms "Back Up + Reset" on the below-floor
  /// recovery screen. The implementation must: (1) write a snapshot using
  /// [snapshotBeforeMigrate] and surface any [SnapshotFailure] rather than
  /// proceeding; (2) only wipe the database if the snapshot succeeded.
  final Future<void> Function(DatabaseBelowFloorError error) onBackUpAndReset;

  /// Called when the user confirms "Reset Only" on the below-floor recovery
  /// screen. This action is unrecoverable; the implementation is responsible
  /// for any confirmation friction the maintainer has specified.
  final Future<void> Function(DatabaseBelowFloorError error) onResetOnly;

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
                      Text(
                        databaseDowngradeMessage(l10n),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (error is DatabaseBelowFloorError) {
            return _BelowFloorRecoveryScreen(
              error: error,
              onBackUpAndReset: () => onBackUpAndReset(error),
              onResetOnly: () => onResetOnly(error),
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
                      Text(
                        migrationSnapshotAbortedMessage(l10n, error.failure),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          // The one-time move of the database out of Documents could not be
          // completed safely. Terminal, no Retry: nothing was deleted, and
          // opening a database now would create an empty one beside the real
          // library.
          if (error is DatabaseRelocationBlocked) {
            return Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_off_outlined, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        databaseRelocationMessage(l10n, error.reason),
                        textAlign: TextAlign.center,
                      ),
                      // Which copy is the library is the user's call: give
                      // them each copy's size and last change to decide by.
                      // Plain Text, so screen readers announce every value.
                      if (error.copies.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.migrationRelocationCopiesHeading,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        for (final copy in error.copies)
                          Text(
                            databaseCopyDetails(l10n, copy),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }
          return _BootstrapErrorScreen(
            errorType: '${error.runtimeType}',
            stackTrace: snapshot.stackTrace,
            onRetry: onRetry,
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

/// Terminal recovery screen shown when the on-disk database was written by a
/// build older than the minimum supported schema version floor (issue #841).
///
/// Like [DatabaseDowngradeError], this is terminal with *no* Retry — retrying
/// cannot apply retired migration steps. Two recovery paths are offered:
/// - **Back Up + Reset**: snapshot the database first (fail-closed — if the
///   snapshot cannot be written, the wipe is not performed), then wipe to a
///   fresh state.
/// - **Reset Only**: wipe to a fresh state immediately, with no backup.
///
/// The primary message explains that the data *is* recoverable by running the
/// bridge release first, so the reset buttons are the fallback, not the only
/// offer.
class _BelowFloorRecoveryScreen extends StatefulWidget {
  const _BelowFloorRecoveryScreen({
    required this.error,
    required this.onBackUpAndReset,
    required this.onResetOnly,
  });

  final DatabaseBelowFloorError error;
  final Future<void> Function() onBackUpAndReset;
  final Future<void> Function() onResetOnly;

  @override
  State<_BelowFloorRecoveryScreen> createState() =>
      _BelowFloorRecoveryScreenState();
}

class _BelowFloorRecoveryScreenState extends State<_BelowFloorRecoveryScreen> {
  bool _inFlight = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_inFlight) return;
    setState(() => _inFlight = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_edu_outlined, size: 48),
              const SizedBox(height: 8),
              Text(
                databaseBelowFloorHeadline(l10n),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                databaseBelowFloorBody(l10n, widget.error.bridgeTag),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _inFlight
                    ? null
                    : () => _run(widget.onBackUpAndReset),
                child: Text(databaseBelowFloorBackUpAndReset(l10n)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _inFlight ? null : () => _run(widget.onResetOnly),
                child: Text(databaseBelowFloorResetOnly(l10n)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The generic startup-failure screen: the error's *type* (never its message),
/// a Copy details control, where the log lives, and Retry.
///
/// The message is withheld on purpose. It can carry file paths or text derived
/// from the database that just failed (#1469, CWE-209), and scrubbing needs
/// `SensitiveTerms`, which is gathered from that same database. The full record
/// is in the on-device crash log (source `main.bootstrap`).
class _BootstrapErrorScreen extends StatefulWidget {
  const _BootstrapErrorScreen({
    required this.errorType,
    required this.stackTrace,
    required this.onRetry,
  });

  final String errorType;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

  @override
  State<_BootstrapErrorScreen> createState() => _BootstrapErrorScreenState();
}

class _BootstrapErrorScreenState extends State<_BootstrapErrorScreen> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: '${widget.errorType}\n\n${widget.stackTrace}'),
      );
      if (mounted) setState(() => _copied = true);
    } catch (error, stackTrace) {
      // A clipboard failure is new information (the bootstrap failure itself is
      // already logged). logCaughtError is exception-proof, so a broken
      // diagnostics store cannot make this screen throw.
      logCaughtError(error, stackTrace, source: 'app_bootstrap._copy');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 8),
                Text(l10n.appBootstrapError, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  l10n.appBootstrapErrorType(widget.errorType),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.appBootstrapLogHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: Text(l10n.commonRetry),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('bootstrap-copy-details'),
                  onPressed: _copied ? null : _copy,
                  icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                  label: Text(
                    _copied
                        ? l10n.appBootstrapCopiedDetails
                        : l10n.appBootstrapCopyDetails,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
