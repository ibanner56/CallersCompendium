import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/collection_refresh_scope.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_spacing.dart';

/// Signature for loading the re-parse preview; defaults to
/// [DanceRepository.previewImportGapReparse]. A test seam.
typedef ReparsePreviewLoader =
    Future<List<CustomReparsePreview>> Function(CompendiumRepositories repos);

/// Signature for applying the re-parse to the given dance ids; defaults to
/// [DanceRepository.reparseImportGapFiguresForMany]. A test seam.
typedef ReparseApplier =
    Future<int> Function(CompendiumRepositories repos, List<String> ids);

/// Settings → "Re-check custom figures" (issue #417).
///
/// Re-runs the current figure parser locally over the stored text of every
/// *import-gap* custom figure (customs that only exist because the parser
/// couldn't map them at import time, flagged by #398) and upgrades any that now
/// map to a structured taxonomy move — without deleting and re-importing, so
/// every tag, rating, note, tune, custom field, and link is preserved.
///
/// The screen is a dry-run first: it previews which dances (and how many
/// figures) would be upgraded and requires explicit confirmation before it
/// writes anything. User-entered customs and already-structured figures are
/// never touched, and applying is idempotent.
class ReparseCustomFiguresScreen extends StatefulWidget {
  const ReparseCustomFiguresScreen({
    super.key,
    this.previewLoader,
    this.applier,
  });

  /// Test seam for the preview scan; defaults to
  /// [DanceRepository.previewImportGapReparse].
  final ReparsePreviewLoader? previewLoader;

  /// Test seam for the apply write; defaults to
  /// [DanceRepository.reparseImportGapFiguresForMany] (stamped with `now`).
  final ReparseApplier? applier;

  @override
  State<ReparseCustomFiguresScreen> createState() =>
      _ReparseCustomFiguresScreenState();
}

class _ReparseCustomFiguresScreenState
    extends State<ReparseCustomFiguresScreen> {
  /// The dry-run result; `null` until the first scan resolves.
  List<CustomReparsePreview>? _previews;

  /// Set when the preview scan fails, so the body can offer a retry instead of
  /// spinning forever.
  Object? _loadError;
  bool _loadRequested = false;
  bool _applying = false;

  void _ensurePreviewLoaded() {
    if (_loadRequested) return;
    _loadRequested = true;
    _load();
  }

  void _load() {
    final repos = RepositoriesScope.of(context);
    final loader =
        widget.previewLoader ?? (r) => r.dances.previewImportGapReparse();
    loader(repos)
        .then((previews) {
          if (!mounted) return;
          setState(() {
            _previews = previews;
            _loadError = null;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          logCaughtError(
            error,
            stackTrace,
            source: 'reparse_custom_figures_screen._load',
          );
          if (!mounted) return;
          setState(() => _loadError = error);
        });
  }

  void _retryLoad() {
    setState(() {
      _previews = null;
      _loadError = null;
    });
    _load();
  }

  int get _totalFigures =>
      (_previews ?? const []).fold(0, (sum, p) => sum + p.upgradeCount);

  Future<void> _onApply() async {
    final previews = _previews;
    if (previews == null || previews.isEmpty || _applying) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repos = RepositoriesScope.of(context);
    final l10n = AppLocalizations.of(context);
    // Capture the refresh notifier BEFORE the await: if the user navigates Back
    // while the batch runs, this widget's context is defunct by the time the
    // write completes, so we must not read it (or bump via context) afterwards.
    final refresh = CollectionRefreshScope.maybeOf(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.reparseConfirmTitle),
        content: Text(l10n.reparseConfirmBody(_totalFigures, previews.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('reparse-confirm-apply'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.reparseConfirmUpgrade),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _applying = true);
    final ids = [for (final p in previews) p.danceId];
    final applier =
        widget.applier ??
        (r, danceIds) => r.dances.reparseImportGapFiguresForMany(
          danceIds,
          now: DateTime.now().toUtc(),
        );
    int changed;
    try {
      changed = await applier(repos, ids);
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'reparse_custom_figures_screen._onApply',
      );
      // Re-enable the button and tell the user; nothing was committed because
      // the batch is a single transaction (it rolls back as a whole).
      if (!mounted) return;
      setState(() => _applying = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.reparseFailed)));
      return;
    }

    // The write committed. Refresh the (possibly kept-alive) Collection tab via
    // the notifier we captured up front, so it re-loads even if this route has
    // since been popped.
    if (changed > 0) refresh?.value++;
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? l10n.reparseNothingUpgradedSnack
              : l10n.reparseUpgradedSnack(changed),
        ),
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    _ensurePreviewLoaded();
    return Scaffold(
      appBar: AppBar(
        key: const ValueKey('reparse-customs-appbar'),
        title: Text(AppLocalizations.of(context).reparseScreenTitle),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadError != null) {
      return _ErrorState(onRetry: _retryLoad);
    }
    final previews = _previews;
    if (previews == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (previews.isEmpty) {
      return _EmptyState();
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.reparseIntro(_totalFigures, previews.length),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('reparse-customs-list'),
            itemCount: previews.length,
            itemBuilder: (context, index) {
              final preview = previews[index];
              return ListTile(
                key: ValueKey('reparse-dance-${preview.danceId}'),
                leading: const Icon(Icons.auto_fix_high_outlined),
                title: Text(preview.title),
                subtitle: Text(l10n.reparsePreviewCount(preview.upgradeCount)),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              key: const ValueKey('reparse-customs-apply-button'),
              onPressed: _applying ? null : _onApply,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(l10n.reparseUpgradeButton(previews.length)),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('reparse-customs-empty'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.reparseEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.reparseEmptyBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('reparse-customs-error'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.reparseErrorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.reparseErrorBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              key: const ValueKey('reparse-customs-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
