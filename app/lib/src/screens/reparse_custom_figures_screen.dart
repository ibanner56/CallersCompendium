import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/collection_refresh_scope.dart';
import '../data/repositories_scope.dart';
import '../theme/app_spacing.dart';

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
  const ReparseCustomFiguresScreen({super.key});

  @override
  State<ReparseCustomFiguresScreen> createState() =>
      _ReparseCustomFiguresScreenState();
}

class _ReparseCustomFiguresScreenState
    extends State<ReparseCustomFiguresScreen> {
  /// The dry-run result; `null` until the first scan resolves.
  List<CustomReparsePreview>? _previews;
  bool _loadRequested = false;
  bool _applying = false;

  void _ensurePreviewLoaded() {
    if (_loadRequested) return;
    _loadRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.dances.previewImportGapReparse().then((previews) {
      if (!mounted) return;
      setState(() => _previews = previews);
    });
  }

  int get _totalFigures =>
      (_previews ?? const []).fold(0, (sum, p) => sum + p.upgradeCount);

  Future<void> _onApply() async {
    final previews = _previews;
    if (previews == null || previews.isEmpty || _applying) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repos = RepositoriesScope.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upgrade custom figures?'),
        content: Text(
          'This will re-parse ${_figuresLabel(_totalFigures)} in '
          '${_dancesLabel(previews.length)}. Your tags, ratings, notes, and '
          'everything else on each dance are kept exactly as they are. This '
          'only replaces figures that now recognise a known move.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('reparse-confirm-apply'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _applying = true);
    final ids = [for (final p in previews) p.danceId];
    final changed = await repos.dances.reparseImportGapFiguresForMany(
      ids,
      now: DateTime.now().toUtc(),
    );
    if (!mounted) return;

    if (changed > 0) CollectionRefreshScope.bump(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? 'Nothing to upgrade.'
              : 'Upgraded custom figures in ${_dancesLabel(changed)}.',
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
        title: const Text('Re-check custom figures'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final previews = _previews;
    if (previews == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (previews.isEmpty) {
      return _EmptyState();
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Improved figure parsing can upgrade '
            '${_figuresLabel(_totalFigures)} in '
            '${_dancesLabel(previews.length)}. Review below, then confirm — '
            'nothing changes until you do, and all your tags, ratings, and '
            'notes are preserved.',
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
                subtitle: Text(
                  '${_figuresLabel(preview.upgradeCount)} to upgrade',
                ),
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
              label: Text('Upgrade ${_dancesLabel(previews.length)}'),
            ),
          ),
        ),
      ],
    );
  }

  static String _dancesLabel(int n) => n == 1 ? '1 dance' : '$n dances';

  static String _figuresLabel(int n) => n == 1 ? '1 figure' : '$n figures';
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              'Nothing to upgrade',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'None of your custom figures from imports can be recognised as a '
              'known move right now. Check back after a future update improves '
              'figure parsing.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
