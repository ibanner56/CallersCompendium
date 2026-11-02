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
import '../update/retirement_banner.dart' show kReleasesPageUrl;
import '../utils/launch_external_url.dart';

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
/// Four errors are terminal, with neither Retry nor "Check again" (maintainer
/// decision R2-check-again, 2026-10-30, which overrode the audit's suggestion
/// of Check again on the last two): whatever the user does to fix them, the app
/// has to be reopened afterwards, and each screen's copy says so. Each offers
/// **Copy details** and a link to the Releases page ([_TerminalScreen]).
/// - [DatabaseDowngradeError] (on-disk data written by a newer build): the only
///   fix is to update the app, so retrying would just fail again.
/// - [DatabaseBelowFloorError] (on-disk data written by a build older than the
///   minimum supported schema version): retrying cannot recover the data; the
///   user must run the bridge release to migrate it, or reset. [onBackUpAndReset]
///   and [onResetOnly] supply the recovery actions.
/// - [MigrationSnapshotAborted] (no backup could be written): free space or fix
///   the backups folder, then reopen.
/// - [DatabaseRelocationBlocked] (the library could not be moved safely): fix
///   the folders, then reopen.
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

  /// Called when the user confirms "Back up + reset" on the below-floor
  /// recovery screen. The implementation must: (1) write a snapshot using
  /// [snapshotBeforeMigrate] and surface any [SnapshotFailure] rather than
  /// proceeding; (2) only wipe the database if the snapshot succeeded.
  final Future<void> Function(DatabaseBelowFloorError error) onBackUpAndReset;

  /// Called when the user confirms "Reset only" on the below-floor recovery
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
            return _TerminalScreen(
              icon: Icons.system_update_alt,
              errorType: 'DatabaseDowngradeError',
              stackTrace: snapshot.stackTrace,
              typedDetails: [
                'fileVersion: ${error.fileVersion}',
                'appVersion: ${error.appVersion}',
              ],
              body: [
                Text(
                  databaseDowngradeMessage(l10n),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.migrationDowngradeVersions(
                    error.fileVersion,
                    error.appVersion,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }
          if (error is DatabaseBelowFloorError) {
            return _BelowFloorRecoveryScreen(
              error: error,
              stackTrace: snapshot.stackTrace,
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
            return _TerminalScreen(
              icon: _snapshotAbortedIcon(error.failure.cause),
              errorType: 'MigrationSnapshotAborted',
              stackTrace: snapshot.stackTrace,
              typedDetails: [
                'cause: ${error.failure.cause.name}',
                'fromVersion: ${error.failure.fromVersion}',
                'toVersion: ${error.failure.toVersion}',
              ],
              body: [
                Text(
                  migrationSnapshotAbortedMessage(l10n, error.failure),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          // The one-time move of the database out of Documents could not be
          // completed safely, or could not be ruled out (Documents
          // unreachable). Terminal, no Retry: nothing was deleted, and
          // opening a database now would create an empty one beside the real
          // library.
          if (error is DatabaseRelocationBlocked) {
            return _TerminalScreen(
              icon: Icons.folder_off_outlined,
              errorType: 'DatabaseRelocationBlocked',
              stackTrace: snapshot.stackTrace,
              typedDetails: [
                'reason: ${error.reason.name}',
                for (final copy in error.copies)
                  'copy: ${copy.location.name}, ${copy.bytes} bytes',
              ],
              body: [
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
        return Icons.warning_amber_outlined;
    }
  }
}

/// Terminal recovery screen shown when the on-disk database was written by a
/// build older than the minimum supported schema version floor (issue #841).
///
/// Like [DatabaseDowngradeError], this is terminal with *no* Retry — retrying
/// cannot apply retired migration steps. Two recovery paths are offered:
/// - **Back up + reset**: snapshot the database first (fail-closed — if the
///   snapshot cannot be written, the wipe is not performed), then wipe to a
///   fresh state.
/// - **Reset only**: wipe to a fresh state immediately, with no backup.
///
/// The primary message explains that the data *is* recoverable by running the
/// bridge release first, so the reset buttons are the fallback, not the only
/// offer.
class _BelowFloorRecoveryScreen extends StatefulWidget {
  const _BelowFloorRecoveryScreen({
    required this.error,
    required this.stackTrace,
    required this.onBackUpAndReset,
    required this.onResetOnly,
  });

  final DatabaseBelowFloorError error;
  final StackTrace? stackTrace;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 16),
              _TerminalHelpActions(
                details: _terminalDetails('DatabaseBelowFloorError', [
                  'fileVersion: ${widget.error.fileVersion}',
                  'minSupportedVersion: ${widget.error.minSupportedVersion}',
                  'bridgeTag: ${widget.error.bridgeTag}',
                ], widget.stackTrace),
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
class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({
    required this.errorType,
    required this.stackTrace,
    required this.onRetry,
  });

  final String errorType;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

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
                  l10n.appBootstrapLogHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
                const SizedBox(height: 8),
                _CopyDetailsButton(
                  details: _terminalDetails(errorType, const [], stackTrace),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The text behind every Copy details button on a startup screen: the error's
/// *type*, any typed discriminators in [typedDetails] (version numbers, enum
/// names — never the error's own message, which can carry paths or text from
/// the database that just failed), and the stack scrubbed by [CrashRedactor],
/// the same shape `CrashFallback` copies, so the stack's absolute paths are
/// collapsed before it reaches the clipboard.
String _terminalDetails(
  String errorType,
  List<String> typedDetails,
  StackTrace? stackTrace,
) {
  final buffer = StringBuffer(errorType);
  for (final line in typedDetails) {
    buffer.write('\n$line');
  }
  if (stackTrace != null) {
    buffer.write('\n\n${CrashRedactor().scrub(stackTrace.toString())}');
  }
  return buffer.toString();
}

/// One of the four terminal startup screens: an icon, [body], the log hint, and
/// [_TerminalHelpActions] (Copy details and the Releases link). There is no
/// Retry and no "Check again" — see [AppBootstrap].
class _TerminalScreen extends StatelessWidget {
  const _TerminalScreen({
    required this.icon,
    required this.errorType,
    required this.stackTrace,
    required this.typedDetails,
    required this.body,
  });

  final IconData icon;
  final String errorType;
  final StackTrace? stackTrace;
  final List<String> typedDetails;
  final List<Widget> body;

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
                Icon(icon, size: 48),
                const SizedBox(height: 8),
                ...body,
                const SizedBox(height: 16),
                Text(
                  l10n.appBootstrapLogHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _TerminalHelpActions(
                  details: _terminalDetails(
                    errorType,
                    typedDetails,
                    stackTrace,
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

/// Copy details and a link to the Releases page, shared by the four terminal
/// startup screens.
class _TerminalHelpActions extends StatelessWidget {
  const _TerminalHelpActions({required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CopyDetailsButton(details: details),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('bootstrap-releases-link'),
          onPressed: () => launchExternalUrl(context, kReleasesPageUrl),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.appBootstrapReleasesLink),
        ),
      ],
    );
  }
}

/// The Copy details button: copies [details] and says so.
class _CopyDetailsButton extends StatefulWidget {
  const _CopyDetailsButton({required this.details});

  final String details;

  @override
  State<_CopyDetailsButton> createState() => _CopyDetailsButtonState();
}

class _CopyDetailsButtonState extends State<_CopyDetailsButton> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.details));
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
    return OutlinedButton.icon(
      key: const ValueKey('bootstrap-copy-details'),
      onPressed: _copied ? null : _copy,
      icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
      label: Text(
        _copied ? l10n.appBootstrapCopiedDetails : l10n.appBootstrapCopyDetails,
      ),
    );
  }
}
