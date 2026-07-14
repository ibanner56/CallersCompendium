import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/repositories_scope.dart';

/// Soft-deleted programs with purge-ETA plus Restore and Permanently-delete
/// actions. Mirrors `recently_deleted_screen.dart` (dances) for programs
/// (`docs/design/ux.md` cross-cutting rule: restore within 30 days).
class ProgramsRecentlyDeletedScreen extends StatefulWidget {
  const ProgramsRecentlyDeletedScreen({super.key});

  @override
  State<ProgramsRecentlyDeletedScreen> createState() =>
      _ProgramsRecentlyDeletedScreenState();
}

class _ProgramsRecentlyDeletedScreenState
    extends State<ProgramsRecentlyDeletedScreen> {
  static const Duration _retention = Duration(days: 30);

  late CompendiumRepositories _repos;
  Future<List<Program>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) {
      _repos = RepositoriesScope.of(context);
      _reload();
    }
  }

  void _reload() {
    final future = _repos.programs
        .listAll(includeDeleted: true)
        .then((all) => all.where((p) => p.deletedAt != null).toList());
    setState(() {
      _future = future;
    });
  }

  Future<void> _restore(Program program) async {
    await _repos.programs.restore(program.id, at: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"${program.title}" restored.')));
    _reload();
  }

  Future<void> _permanentDelete(Program program) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '"${program.title}" will be deleted immediately and cannot be recovered.',
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
    // Push deletedAt beyond retention, then run the standard purge (FK cascade
    // handles slots) — same safe path the dances screen uses.
    await _repos.programs.softDelete(program.id, at: DateTime.utc(1970));
    await _repos.programs.purgeDeleted(now: DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${program.title}" permanently deleted.')),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recently Deleted')),
      body: FutureBuilder<List<Program>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading recently deleted programs',
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
                  'Nothing in the trash. Deleted programs appear here for 30 days before being removed.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: deleted.length,
            itemBuilder: (context, index) => _DeletedProgramTile(
              program: deleted[index],
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

class _DeletedProgramTile extends StatelessWidget {
  const _DeletedProgramTile({
    required this.program,
    required this.retention,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final Program program;
  final Duration retention;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deletedAt = program.deletedAt!;
    final purgeAt = deletedAt.add(retention);
    final daysLeft = purgeAt.difference(DateTime.now().toUtc()).inDays;
    final purgeLabel = daysLeft > 0
        ? 'Auto-deleted in $daysLeft ${daysLeft == 1 ? "day" : "days"}'
        : 'Scheduled for deletion';

    return ListTile(
      title: Text(program.title),
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
            key: ValueKey('restore-${program.id}'),
            onPressed: onRestore,
            child: const Text('Restore'),
          ),
          IconButton(
            key: ValueKey('permanent-delete-${program.id}'),
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
