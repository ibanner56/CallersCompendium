import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';
import '../data/soft_delete_retention.dart';

/// Shows soft-deleted dances with their purge-ETA and individual Restore and
/// Permanently delete actions (`docs/design/ux.md` cross-cutting rule:
/// "undo/soft-delete everywhere, restore within the retention window").
///
/// The retention window is the user-configurable one (ROADMAP G.4): 30 / 90
/// days, or "Never" (kept until manually removed). The purge-ETA and empty-state
/// copy reflect the configured window so they never contradict what the startup
/// sweep actually does.
///
/// Reachable from the Collection screen app bar via the
/// `restore_from_trash_outlined` icon button (`recently-deleted` key).
/// An empty state is shown when no dances are pending deletion.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  /// The configured retention window, or `null` for "never auto-purge". Seeded
  /// with the historical 30-day default so the first frame is correct for the
  /// common case; replaced once the persisted setting resolves.
  Duration? _retention = const Duration(days: kSoftDeleteRetentionDefaultDays);

  late CompendiumRepositories _repos;
  Future<List<Dance>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _loadRetention();
      _reload();
    }
  }

  void _loadRetention() {
    _repos.settings
        .get(kSoftDeleteRetentionKey)
        .then((stored) {
          if (!mounted) return;
          setState(() => _retention = softDeleteRetentionFromStored(stored));
        })
        .catchError((_) {
          /* keep the 30-day default */
        });
  }

  void _reload() {
    final future = _repos.dances
        .listAll(includeDeleted: true)
        .then((all) => all.where((d) => d.deletedAt != null).toList());
    setState(() {
      _future = future;
    });
  }

  Future<void> _restore(Dance dance) async {
    await _repos.dances.restore(dance.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${dance.title}" restored to your collection.')),
    );
    _reload();
  }

  Future<void> _permanentDelete(Dance dance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '"${dance.title}" will be deleted immediately and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-permanent-delete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Purge by setting deletedAt well in the past (beyond retention), then
    // calling purgeDeleted. This is the safe path that goes through the
    // existing purge machinery (FK cascade, FTS cleanup, slot nulling).
    final longAgo = DateTime.utc(1970);
    await _repos.dances.softDelete(dance.id, at: longAgo);
    await _repos.dances.purgeDeleted(now: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${dance.title}" permanently deleted.')),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recently Deleted')),
      body: FutureBuilder<List<Dance>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading recently deleted dances',
              ),
            );
          }
          final deleted = snapshot.data ?? [];
          if (deleted.isEmpty) {
            final retention = _retention;
            return Center(
              key: const ValueKey('empty-state'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  retention == null
                      ? 'Nothing in the trash. Deleted dances are kept here '
                            'until you remove them.'
                      : 'Nothing in the trash. Deleted dances appear here for '
                            '${retention.inDays} days before being removed.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: deleted.length,
            itemBuilder: (context, index) => _DeletedDanceTile(
              dance: deleted[index],
              retention: _retention,
              onRestore: () => _restore(deleted[index]),
              onPermanentDelete: () => _permanentDelete(deleted[index]),
            ),
          );
        },
      ),
    );
  }
}

class _DeletedDanceTile extends StatelessWidget {
  const _DeletedDanceTile({
    required this.dance,
    required this.retention,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final Dance dance;

  /// The configured retention window, or `null` when auto-purge is off
  /// ("Never") — in which case no countdown is shown.
  final Duration? retention;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retention = this.retention;
    final String purgeLabel;
    final bool urgent;
    if (retention == null) {
      purgeLabel = 'Kept until you delete it';
      urgent = false;
    } else {
      final purgeAt = dance.deletedAt!.add(retention);
      final daysLeft = purgeAt.difference(DateTime.now().toUtc()).inDays;
      purgeLabel = daysLeft > 0
          ? 'Auto-deleted in $daysLeft ${daysLeft == 1 ? "day" : "days"}'
          : 'Scheduled for deletion';
      urgent = daysLeft <= 3;
    }

    return ListTile(
      title: Text(dance.title),
      subtitle: Text(
        purgeLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: urgent
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: ValueKey('restore-${dance.id}'),
            onPressed: onRestore,
            child: const Text('Restore'),
          ),
          IconButton(
            key: ValueKey('permanent-delete-${dance.id}'),
            tooltip: 'Delete permanently',
            icon: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            onPressed: onPermanentDelete,
          ),
        ],
      ),
    );
  }
}
