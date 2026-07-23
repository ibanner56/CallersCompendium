import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../data/soft_delete_retention.dart';

/// Per-entity configuration for [RecentlyDeletedScreen].
///
/// Captures everything that differs between the dances and programs
/// "Recently Deleted" screens — the entity accessors, the repository calls,
/// the retention window, and the copy — so the screen itself stays generic and
/// the two entry points ([RecentlyDeletedScreen.dances] /
/// [RecentlyDeletedScreen.programs]) are thin wrappers over the shared shape.
@immutable
class RecentlyDeletedConfig<T> {
  const RecentlyDeletedConfig({
    required this.pluralNoun,
    required this.initialRetention,
    this.loadRetention,
    required this.loadDeleted,
    required this.restore,
    required this.permanentlyDelete,
    required this.idOf,
    required this.titleOf,
    required this.deletedAtOf,
    required this.restoredMessage,
    required this.loadingLabel,
    this.emptyKept,
    required this.emptyRetention,
  });

  /// Developer-only lower-case plural entity noun ("dances" / "programs") used
  /// in the debug assert message below. Not user-facing (never localized).
  final String pluralNoun;

  /// Retention window shown on the first frame, before [loadRetention] (if any)
  /// resolves. `null` means "never auto-purge" (no countdown).
  final Duration? initialRetention;

  /// Optional resolver for the user-configurable retention window. When `null`
  /// the [initialRetention] is used unchanged (a fixed window).
  final Future<Duration?> Function(CompendiumRepositories repos)? loadRetention;

  /// Loads the soft-deleted items (those with a non-null `deletedAt`).
  ///
  /// Contract: implementations MUST filter out non-deleted items — the screen
  /// renders each item's purge-ETA from its `deletedAt` and asserts it is
  /// non-null.
  final Future<List<T>> Function(CompendiumRepositories repos) loadDeleted;

  /// Restores [item] to the active collection.
  final Future<void> Function(CompendiumRepositories repos, T item) restore;

  /// Hard-deletes [item] via the standard purge machinery.
  final Future<void> Function(CompendiumRepositories repos, T item)
  permanentlyDelete;

  final String Function(T item) idOf;
  final String Function(T item) titleOf;

  /// The item's soft-delete timestamp. Guaranteed non-null for every item
  /// [loadDeleted] returns; the screen asserts this before using it.
  final DateTime? Function(T item) deletedAtOf;

  /// Snackbar copy shown after a successful restore, given the item title.
  final String Function(AppLocalizations l10n, String title) restoredMessage;

  /// Accessibility label for the loading spinner (whole localized phrase).
  final String Function(AppLocalizations l10n) loadingLabel;

  /// Empty-state copy when auto-purge is off ("Never"). `null` for kinds whose
  /// retention window is fixed and can never be "Never" (they always render
  /// [emptyRetention]).
  final String Function(AppLocalizations l10n)? emptyKept;

  /// Empty-state copy given the configured retention window in days.
  final String Function(AppLocalizations l10n, int days) emptyRetention;
}

/// Shows soft-deleted items with their purge-ETA and individual Restore and
/// Permanently delete actions (`docs/design/ux.md` cross-cutting rule:
/// "undo/soft-delete everywhere, restore within the retention window").
///
/// A single generic implementation backs both the dances
/// ([RecentlyDeletedScreen.dances]) and programs
/// ([RecentlyDeletedScreen.programs]) screens; the per-entity differences live
/// in [RecentlyDeletedConfig].
///
/// For dances the retention window is the user-configurable one (ROADMAP G.4):
/// 30 / 90 days, or "Never" (kept until manually removed). The purge-ETA and
/// empty-state copy reflect the configured window so they never contradict what
/// the startup sweep actually does. Programs use a fixed 30-day window.
///
/// An empty state is shown when no items are pending deletion.
class RecentlyDeletedScreen<T> extends StatefulWidget {
  const RecentlyDeletedScreen({super.key, required this.config});

  final RecentlyDeletedConfig<T> config;

  /// The dances "Recently Deleted" screen.
  static RecentlyDeletedScreen<Dance> dances({Key? key}) =>
      RecentlyDeletedScreen<Dance>(
        key: key,
        config: danceRecentlyDeletedConfig,
      );

  /// The programs "Recently Deleted" screen.
  static RecentlyDeletedScreen<Program> programs({Key? key}) =>
      RecentlyDeletedScreen<Program>(
        key: key,
        config: programRecentlyDeletedConfig,
      );

  @override
  State<RecentlyDeletedScreen<T>> createState() =>
      _RecentlyDeletedScreenState<T>();
}

class _RecentlyDeletedScreenState<T> extends State<RecentlyDeletedScreen<T>> {
  /// The configured retention window, or `null` for "never auto-purge". Seeded
  /// with [RecentlyDeletedConfig.initialRetention] so the first frame is
  /// correct for the common case; replaced once the persisted setting resolves
  /// (when the config supplies a resolver).
  Duration? _retention;

  late CompendiumRepositories _repos;
  Future<List<T>>? _future;

  RecentlyDeletedConfig<T> get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _retention = widget.config.initialRetention;
  }

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
    final loader = _config.loadRetention;
    if (loader == null) return;
    loader(_repos)
        .then((resolved) {
          if (!mounted) return;
          setState(() => _retention = resolved);
        })
        .catchError((_) {
          /* keep the seeded default */
        });
  }

  void _reload() {
    final future = _config.loadDeleted(_repos);
    setState(() {
      _future = future;
    });
  }

  Future<void> _restore(T item) async {
    await _config.restore(_repos, item);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_config.restoredMessage(l10n, _config.titleOf(item))),
      ),
    );
    _reload();
  }

  Future<void> _permanentDelete(T item) async {
    final l10n = AppLocalizations.of(context);
    final title = _config.titleOf(item);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.recentlyDeletedDeleteTitle),
        content: Text(l10n.recentlyDeletedDeleteBody(title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('confirm-permanent-delete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.recentlyDeletedDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _config.permanentlyDelete(_repos, item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.recentlyDeletedDeletedSnack(title))),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recentlyDeletedTitle)),
      body: FutureBuilder<List<T>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: _config.loadingLabel(l10n),
              ),
            );
          }
          final deleted = snapshot.data ?? <T>[];
          if (deleted.isEmpty) {
            final retention = _retention;
            return Center(
              key: const ValueKey('empty-state'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  retention == null
                      ? _config.emptyKept!(l10n)
                      : _config.emptyRetention(l10n, retention.inDays),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: deleted.length,
            itemBuilder: (context, index) {
              final item = deleted[index];
              final deletedAt = _config.deletedAtOf(item);
              // Invariant: loadDeleted only ever yields soft-deleted items, so
              // deletedAt is non-null here. Assert (debug-only) so a
              // misconfigured config surfaces with a clear message in dev/tests
              // instead of an opaque null-check crash.
              assert(
                deletedAt != null,
                'RecentlyDeletedConfig.loadDeleted must return only '
                'soft-deleted items (deletedAt != null); got a '
                '${_config.pluralNoun} item with a null deletedAt.',
              );
              return _DeletedItemTile(
                title: _config.titleOf(item),
                id: _config.idOf(item),
                deletedAt: deletedAt!,
                retention: _retention,
                onRestore: () => _restore(item),
                onPermanentDelete: () => _permanentDelete(item),
              );
            },
          );
        },
      ),
    );
  }
}

/// Config for the dances "Recently Deleted" screen. Dances honor the
/// user-configurable retention window (ROADMAP G.4), so [loadRetention] reads
/// the persisted setting.
final RecentlyDeletedConfig<Dance> danceRecentlyDeletedConfig =
    RecentlyDeletedConfig<Dance>(
      pluralNoun: 'dances',
      initialRetention: const Duration(days: kSoftDeleteRetentionDefaultDays),
      loadRetention: (repos) => repos.settings
          .get(kSoftDeleteRetentionKey)
          .then(softDeleteRetentionFromStored),
      loadDeleted: (repos) => repos.dances
          .listAll(includeDeleted: true)
          .then((all) => all.where((d) => d.deletedAt != null).toList()),
      restore: (repos, dance) =>
          repos.dances.restore(dance.id, at: DateTime.now().toUtc()),
      permanentlyDelete: (repos, dance) async {
        // Purge by setting deletedAt well in the past (beyond retention), then
        // calling purgeDeleted. This is the safe path that goes through the
        // existing purge machinery (FK cascade, FTS cleanup, slot nulling).
        await repos.dances.softDelete(dance.id, at: DateTime.utc(1970));
        await repos.dances.purgeDeleted(now: DateTime.now().toUtc());
      },
      idOf: (dance) => dance.id,
      titleOf: (dance) => dance.title,
      deletedAtOf: (dance) => dance.deletedAt,
      restoredMessage: (l10n, title) =>
          l10n.recentlyDeletedRestoredDance(title),
      loadingLabel: (l10n) => l10n.recentlyDeletedLoadingDances,
      emptyKept: (l10n) => l10n.recentlyDeletedEmptyDancesKept,
      emptyRetention: (l10n, days) =>
          l10n.recentlyDeletedEmptyDancesRetention(days),
    );

/// Config for the programs "Recently Deleted" screen. Programs use a fixed
/// 30-day retention window (no user-configurable setting), so [loadRetention]
/// is omitted and the seeded [initialRetention] is used unchanged.
final RecentlyDeletedConfig<Program> programRecentlyDeletedConfig =
    RecentlyDeletedConfig<Program>(
      pluralNoun: 'programs',
      initialRetention: const Duration(days: 30),
      loadDeleted: (repos) => repos.programs
          .listAll(includeDeleted: true)
          .then((all) => all.where((p) => p.deletedAt != null).toList()),
      restore: (repos, program) =>
          repos.programs.restore(program.id, at: DateTime.now().toUtc()),
      permanentlyDelete: (repos, program) async {
        // Push deletedAt beyond retention, then run the standard purge (FK
        // cascade handles slots) — same safe path the dances screen uses.
        await repos.programs.softDelete(program.id, at: DateTime.utc(1970));
        await repos.programs.purgeDeleted(now: DateTime.now().toUtc());
      },
      idOf: (program) => program.id,
      titleOf: (program) => program.title,
      deletedAtOf: (program) => program.deletedAt,
      restoredMessage: (l10n, title) =>
          l10n.recentlyDeletedRestoredProgram(title),
      loadingLabel: (l10n) => l10n.recentlyDeletedLoadingPrograms,
      emptyRetention: (l10n, days) =>
          l10n.recentlyDeletedEmptyProgramsRetention(days),
    );

class _DeletedItemTile extends StatelessWidget {
  const _DeletedItemTile({
    required this.title,
    required this.id,
    required this.deletedAt,
    required this.retention,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final String title;
  final String id;
  final DateTime deletedAt;

  /// The configured retention window, or `null` when auto-purge is off
  /// ("Never") — in which case no countdown is shown.
  final Duration? retention;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final retention = this.retention;
    final String purgeLabel;
    final bool urgent;
    if (retention == null) {
      purgeLabel = l10n.recentlyDeletedPurgeKept;
      urgent = false;
    } else {
      final purgeAt = deletedAt.add(retention);
      final daysLeft = purgeAt.difference(DateTime.now().toUtc()).inDays;
      purgeLabel = daysLeft > 0
          ? l10n.recentlyDeletedPurgeCountdown(daysLeft)
          : l10n.recentlyDeletedPurgeScheduled;
      urgent = daysLeft <= 3;
    }

    return ListTile(
      title: Text(title),
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
            key: ValueKey('restore-$id'),
            onPressed: onRestore,
            child: Text(l10n.recentlyDeletedRestore),
          ),
          IconButton(
            key: ValueKey('permanent-delete-$id'),
            tooltip: l10n.recentlyDeletedDeleteConfirm,
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
