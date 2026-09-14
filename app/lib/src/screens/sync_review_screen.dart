import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_spacing.dart';

/// Displays persisted sync decisions and exposes only the W14-supported
/// tombstone resolution actions.
class SyncReviewScreen extends StatefulWidget {
  const SyncReviewScreen({super.key});

  @override
  State<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends State<SyncReviewScreen> {
  late SyncReviewQueueResolver _resolver;
  Future<List<SyncReviewQueueItem>>? _future;
  String? _busyKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    final repositories = RepositoriesScope.of(context);
    _resolver = SyncReviewQueueResolver(CompendiumSyncStorage(repositories));
    _reload();
  }

  Future<List<SyncReviewQueueItem>> _load() async {
    try {
      return await _resolver.list();
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_review_screen._load');
      rethrow;
    }
  }

  void _reload() {
    final future = _load();
    if (!mounted) return;
    setState(() {
      _future = future;
    });
  }

  String _itemKey(SyncReviewQueueItem item) =>
      '${item.row.kind.name}:${item.row.recordId}:${item.row.counterpartId}';

  String _kindLabel(AppLocalizations l10n, SyncRecordKind kind) =>
      switch (kind) {
        SyncRecordKind.choreographer => l10n.syncReviewKindChoreographer,
        SyncRecordKind.tag => l10n.syncReviewKindTag,
        SyncRecordKind.customFieldDef => l10n.syncReviewKindCustomField,
        SyncRecordKind.difficultyLevel => l10n.syncReviewKindDifficulty,
        SyncRecordKind.dance => l10n.syncReviewKindDance,
        SyncRecordKind.program => l10n.syncReviewKindProgram,
        SyncRecordKind.publishedSource => l10n.syncReviewKindPublishedSource,
        SyncRecordKind.venue => l10n.syncReviewKindVenue,
        SyncRecordKind.setting => l10n.syncReviewKindSetting,
      };

  String _candidateIdentity(AppLocalizations l10n, SyncReviewQueueItem item) {
    final label = item.candidateLabel;
    final id = item.row.counterpartId;
    return label == null ? id : '$label ($id)';
  }

  Future<String?> _askForDistinctName(
    BuildContext context,
    SyncReviewQueueItem item,
  ) => showDialog<String>(
    context: context,
    builder: (_) => _DistinctNameDialog(currentNaturalKey: item.naturalKey),
  );

  Future<void> _resolve(
    SyncReviewQueueItem item,
    SyncReviewAction action,
  ) async {
    final distinctName = action == SyncReviewAction.keepBoth
        ? await _askForDistinctName(context, item)
        : null;
    if (action == SyncReviewAction.keepBoth && distinctName == null) return;
    if (!mounted) return;

    final key = _itemKey(item);
    setState(() {
      _busyKey = key;
    });
    final l10n = AppLocalizations.of(context);
    try {
      await _resolver.resolve(
        item: item,
        action: action,
        newNaturalKey: distinctName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.syncReviewResolved)));
      _reload();
    } on SyncReviewException catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_review_screen._resolve');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_failureMessage(l10n, error))));
    } on Object catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'sync_review_screen._resolve');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.syncReviewActionFailed)));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  String _failureMessage(
    AppLocalizations l10n,
    SyncReviewException error,
  ) => switch (error.code) {
    SyncReviewFailureCode.candidateInvalid => l10n.syncReviewCandidateInvalid,
    SyncReviewFailureCode.candidateChanged => l10n.syncReviewCandidateChanged,
    SyncReviewFailureCode.unsupportedReason => l10n.syncReviewUnsupportedReason,
    SyncReviewFailureCode.targetMissing => l10n.syncReviewTargetMissing,
    SyncReviewFailureCode.candidateAlreadyPresent =>
      l10n.syncReviewCandidateAlreadyPresent,
    SyncReviewFailureCode.nameRequired => l10n.syncReviewNameRequired,
    SyncReviewFailureCode.nameNotDistinct => l10n.syncReviewNameNotDistinct,
  };

  Widget _buildItem(BuildContext context, SyncReviewQueueItem item) {
    final l10n = AppLocalizations.of(context);
    final key = _itemKey(item);
    final busy = _busyKey == key;
    final actionable = item.isActionable;
    return Card(
      key: ValueKey('sync-review-item-$key'),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _kindLabel(l10n, item.row.kind),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.syncReviewLocalRecord(item.row.recordId),
              key: ValueKey('sync-review-local-$key'),
            ),
            Text(
              l10n.syncReviewPeerRecord(_candidateIdentity(l10n, item)),
              key: ValueKey('sync-review-peer-$key'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              actionable
                  ? l10n.syncReviewTombstoneReason
                  : l10n.syncReviewUnsupportedReason,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!actionable)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  l10n.syncReviewUnsupportedAction,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (actionable)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    FilledButton.tonal(
                      key: ValueKey('sync-review-merge-$key'),
                      onPressed: busy
                          ? null
                          : () => _resolve(item, SyncReviewAction.merge),
                      child: Text(l10n.syncReviewMergeAction),
                    ),
                    OutlinedButton(
                      key: ValueKey('sync-review-keep-both-$key'),
                      onPressed: busy
                          ? null
                          : () => _resolve(item, SyncReviewAction.keepBoth),
                      child: Text(l10n.syncReviewKeepBothAction),
                    ),
                  ],
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncReviewTitle)),
      body: FutureBuilder<List<SyncReviewQueueItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: l10n.syncReviewLoading,
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.syncReviewLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      key: const ValueKey('sync-review-retry'),
                      onPressed: _reload,
                      child: Text(l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = snapshot.data ?? const <SyncReviewQueueItem>[];
          if (items.isEmpty) {
            return Center(
              key: const ValueKey('sync-review-empty'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(l10n.syncReviewEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            key: const ValueKey('sync-review-list'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Text(l10n.syncReviewIntro),
              ),
              for (final item in items) _buildItem(context, item),
            ],
          );
        },
      ),
    );
  }
}

class _DistinctNameDialog extends StatefulWidget {
  const _DistinctNameDialog({required this.currentNaturalKey});

  final String? currentNaturalKey;

  @override
  State<_DistinctNameDialog> createState() => _DistinctNameDialogState();
}

class _DistinctNameDialogState extends State<_DistinctNameDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.syncReviewKeepBothTitle),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.syncReviewNewNameLabel),
          validator: (value) {
            final normalized = value == null ? '' : value.trim();
            if (normalized.isEmpty) return l10n.syncReviewNameRequired;
            final current = widget.currentNaturalKey;
            if (current != null &&
                normalizeShareableText(normalized).toLowerCase() == current) {
              return l10n.syncReviewNameNotDistinct;
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('sync-review-keep-both-confirm'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text);
            }
          },
          child: Text(l10n.syncReviewKeepBothAction),
        ),
      ],
    );
  }
}
