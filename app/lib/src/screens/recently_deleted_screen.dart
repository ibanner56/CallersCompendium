import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';

/// Shows soft-deleted dances with their purge-ETA and individual Restore and
/// Permanently delete actions (`docs/design/ux.md` cross-cutting rule:
/// "undo/soft-delete everywhere, restore within 30 days").
///
/// Reachable from the Collection screen app-bar overflow menu. An empty state
/// is shown when no dances are pending deletion.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  static const Duration _retention = Duration(days: 30);

  late CompendiumRepositories _repos;
  Future<List<Dance>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _reload();
    }
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
            return const Center(
              key: ValueKey('empty-state'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing in the trash. Deleted dances appear here for 30 days before being removed.',
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
  final Duration retention;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deletedAt = dance.deletedAt!;
    final purgeAt = deletedAt.add(retention);
    final daysLeft = purgeAt.difference(DateTime.now().toUtc()).inDays;
    final purgeLabel = daysLeft > 0
        ? 'Auto-deleted in $daysLeft ${daysLeft == 1 ? "day" : "days"}'
        : 'Scheduled for deletion';

    return ListTile(
      title: Text(dance.title),
      subtitle: Text(
        purgeLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: daysLeft <= 3
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
