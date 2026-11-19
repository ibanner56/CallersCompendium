import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_error_view.dart';

/// Loads the ECD migration preview; defaults to
/// [DanceRepository.previewEcdMigration]. A test seam.
typedef EcdMigrationPreviewLoader =
    Future<List<EcdMigrationPreview>> Function(CompendiumRepositories repos);

/// Applies the ECD migration to the given dance ids; defaults to
/// [DanceRepository.migrateEcdDances]. A test seam.
typedef EcdMigrationApplier =
    Future<int> Function(CompendiumRepositories repos, List<String> ids);

/// Settings → "Convert English dances": the opt-in migration of English
/// Country Dances stored with contra moves (ADR-006 §12.1 F5).
///
/// It lists each English dance the migration would change and what it would
/// change: contra moves that become their English twin, unrecognized lines
/// the English parser now reads, and the formation's English shape. The
/// person picks the dances (one, some or all; all are picked at first) and
/// confirms before anything is written. A move with no clear English meaning
/// is left as it is.
class EcdMigrationScreen extends StatefulWidget {
  const EcdMigrationScreen({super.key, this.previewLoader, this.applier});

  /// Test seam for the preview scan.
  final EcdMigrationPreviewLoader? previewLoader;

  /// Test seam for the apply write.
  final EcdMigrationApplier? applier;

  @override
  State<EcdMigrationScreen> createState() => _EcdMigrationScreenState();
}

class _EcdMigrationScreenState extends State<EcdMigrationScreen> {
  List<EcdMigrationPreview>? _previews;
  final Set<String> _selected = {};
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
        widget.previewLoader ??
        (r) => r.dances.previewEcdMigration(migrate: migrateEcdDanceForStorage);
    loader(repos)
        .then((previews) {
          if (!mounted) return;
          setState(() {
            _previews = previews;
            _selected
              ..clear()
              ..addAll(previews.map((p) => p.danceId));
            _loadError = null;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          logCaughtError(
            error,
            stackTrace,
            source: 'ecd_migration_screen._load',
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

  Future<void> _onApply() async {
    final previews = _previews;
    if (previews == null || _selected.isEmpty || _applying) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repos = RepositoriesScope.of(context);
    final l10n = AppLocalizations.of(context);
    final ids = [
      for (final p in previews)
        if (_selected.contains(p.danceId)) p.danceId,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.ecdMigrationConfirmTitle),
        content: Text(l10n.ecdMigrationConfirmBody(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('ecd-migration-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.ecdMigrationConfirmAction),
          ),
        ],
      ),
      animationStyle: AppMotion.styleFor(context),
    );
    if (confirmed != true) return;

    setState(() => _applying = true);
    final applier =
        widget.applier ??
        (r, danceIds) => r.dances.migrateEcdDances(
          danceIds,
          migrate: migrateEcdDanceForStorage,
          now: DateTime.now().toUtc(),
        );
    int changed;
    try {
      changed = await applier(repos, ids);
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'ecd_migration_screen._onApply',
      );
      // The batch is one transaction, so a failure wrote nothing.
      if (!mounted) return;
      setState(() => _applying = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.ecdMigrationFailed)));
      return;
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? l10n.ecdMigrationNothingSnack
              : l10n.ecdMigrationDoneSnack(changed),
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
        title: Text(AppLocalizations.of(context).ecdMigrationScreenTitle),
      ),
      body: _buildBody(context),
    );
  }

  String _summary(AppLocalizations l10n, EcdMigrationPreview preview) => [
    if (preview.movesConverted > 0)
      l10n.ecdMigrationPreviewMoves(preview.movesConverted),
    if (preview.linesReread > 0)
      l10n.ecdMigrationPreviewLines(preview.linesReread),
    if (preview.shapeChanged) l10n.ecdMigrationPreviewShape,
  ].join('\n');

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loadError != null) {
      return LoadErrorView(
        key: const ValueKey('ecd-migration-error'),
        icon: LoadErrorView.errorGlyph(context),
        message: l10n.ecdMigrationErrorTitle,
        body: l10n.reparseErrorBody,
        onRetry: _retryLoad,
      );
    }
    final previews = _previews;
    if (previews == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (previews.isEmpty) {
      return EmptyState(
        key: const ValueKey('ecd-migration-empty'),
        icon: Icon(
          Icons.check_circle_outline,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: l10n.ecdMigrationEmptyTitle,
        body: l10n.ecdMigrationEmptyBody,
      );
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.ecdMigrationIntro(previews.length),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('ecd-migration-list'),
            itemCount: previews.length,
            itemBuilder: (context, index) {
              final preview = previews[index];
              return CheckboxListTile(
                key: ValueKey('ecd-migration-dance-${preview.danceId}'),
                value: _selected.contains(preview.danceId),
                onChanged: _applying
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(preview.danceId);
                        } else {
                          _selected.remove(preview.danceId);
                        }
                      }),
                title: Text(preview.title),
                // One line per change; the tile grows to fit them.
                subtitle: Text(_summary(l10n, preview)),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              key: const ValueKey('ecd-migration-apply'),
              onPressed: _applying || _selected.isEmpty ? null : _onApply,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(l10n.ecdMigrationConvertButton(_selected.length)),
            ),
          ),
        ),
      ],
    );
  }
}
