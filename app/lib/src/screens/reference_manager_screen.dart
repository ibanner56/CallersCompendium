import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../diagnostics/error_log.dart';
import '../widgets/author_details_flow.dart';
import '../widgets/load_error_view.dart';
import '../widgets/published_source_details_dialog.dart';
import 'settings/library_manager_list.dart';

/// The Authors and Sources managers (LIFE-5, `docs/design/tags-and-people.md`
/// T3), on the list the Tags manager shares. Reached from Settings › General
/// › Library (D-N2-3).
///
/// Each row offers **Rename**, **Merge into…**, **Edit details…**, and
/// **Delete** only when no live dance uses the entry: an entry in use is
/// merged, never deleted, so no dance loses its credit (D-N2-4). A merge
/// fills the survivor's empty details from the other entry and, when both
/// hold different values, lists the ones it drops before it runs (D-N2-2).
///
/// Rename, merge and delete write at once and offer Undo in a snackbar, the
/// only Undo there is (D-N2-5), so a delete has no confirm. **Edit details…**
/// opens the dialog the dance editor uses, and saves as it does, with no Undo.
///
/// The list is live, through the repository's `watchAll` and
/// [ReferenceEditRepository.watchLiveDanceCounts], so an edit made anywhere,
/// a sync pass included, reaches it.
class ReferenceManagerScreen extends StatefulWidget {
  /// The Authors manager. Stored as `choreographers`; the screen says
  /// "author" (D-3).
  const ReferenceManagerScreen.authors({super.key})
    : kind = ReferenceKind.author;

  /// The Sources manager.
  const ReferenceManagerScreen.sources({super.key})
    : kind = ReferenceKind.source;

  /// [ReferenceKind.author] or [ReferenceKind.source]; tags have their own
  /// screen, for their colours.
  final ReferenceKind kind;

  @override
  State<ReferenceManagerScreen> createState() => _ReferenceManagerScreenState();
}

class _ReferenceManagerScreenState extends State<ReferenceManagerScreen> {
  late CompendiumRepositories _repos;
  bool _started = false;

  /// Live authors or sources, by id, in the order the repository lists them.
  Map<String, Object>? _rows;
  Map<String, int>? _counts;
  Object? _loadError;

  StreamSubscription<List<Object>>? _rowsSub;
  StreamSubscription<Map<String, int>>? _countsSub;

  bool get _authors => widget.kind == ReferenceKind.author;

  /// Keys: `author-…` or `source-…`, as the Tags manager's are `tag-…`.
  String get _keyPrefix => _authors ? 'author' : 'source';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repos = RepositoriesScope.of(context);
    _subscribe();
  }

  void _subscribe() {
    void onError(Object e, StackTrace stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'reference_manager_screen._subscribe',
      );
      if (!mounted) return;
      setState(() => _loadError = e);
    }

    final Stream<List<Object>> rows = _authors
        ? _repos.choreographers.watchAll()
        : _repos.publishedSources.watchAll();
    _rowsSub = rows.listen((rows) {
      if (!mounted) return;
      setState(() => _rows = {for (final row in rows) _id(row): row});
    }, onError: onError);
    _countsSub = _repos.references.watchLiveDanceCounts(widget.kind).listen((
      counts,
    ) {
      if (!mounted) return;
      setState(() => _counts = counts);
    }, onError: onError);
  }

  /// A stream that failed may have closed, so both are re-opened rather than
  /// waiting for an emit that will not come.
  void _retry() {
    unawaited(_rowsSub?.cancel());
    unawaited(_countsSub?.cancel());
    setState(() {
      _rows = null;
      _counts = null;
      _loadError = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_rowsSub?.cancel());
    unawaited(_countsSub?.cancel());
    super.dispose();
  }

  static String _id(Object row) => switch (row) {
    Choreographer() => row.id,
    PublishedSource() => row.id,
    _ => throw ArgumentError.value(row, 'row'),
  };

  static String _name(Object row) => switch (row) {
    Choreographer() => row.name,
    PublishedSource() => row.title,
    _ => throw ArgumentError.value(row, 'row'),
  };

  /// A source's author and year, which tell apart sources with one title.
  static String? _detail(Object row) {
    if (row is! PublishedSource) return null;
    final parts = [?row.author, ?row.year?.toString()];
    return parts.isEmpty ? null : parts.join(', ');
  }

  LibraryManagerEntry _entry(Object row) => LibraryManagerEntry(
    id: _id(row),
    name: _name(row),
    liveDanceCount: _counts?[_id(row)] ?? 0,
    detail: _detail(row),
  );

  List<LibraryManagerEntry> get _entries => [
    for (final row in (_rows ?? const <String, Object>{}).values) _entry(row),
  ];

  String _searchHint(AppLocalizations l10n) =>
      _authors ? l10n.authorManagerSearchHint : l10n.sourceManagerSearchHint;

  List<LibraryManagerAction> _actionsFor(LibraryManagerEntry entry) {
    final l10n = AppLocalizations.of(context);
    return [
      LibraryManagerAction(
        id: 'rename',
        label: l10n.libraryManagerRename,
        icon: Icons.edit_outlined,
        onSelected: () => unawaited(_rename(entry)),
      ),
      LibraryManagerAction(
        id: 'merge',
        label: l10n.libraryManagerMergeInto,
        icon: Icons.merge_type,
        onSelected: () => unawaited(_mergeInto(entry)),
      ),
      LibraryManagerAction(
        id: 'details',
        label: l10n.libraryManagerEditDetails,
        icon: Icons.info_outline,
        onSelected: () => unawaited(_editDetails(entry)),
      ),
      // D-N2-4: only an entry no live dance uses can go. One in use is merged
      // instead, so no dance is left without its credit.
      if (entry.liveDanceCount == 0)
        LibraryManagerAction(
          id: 'delete',
          label: l10n.commonDelete,
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => unawaited(_delete(entry)),
        ),
    ];
  }

  /// [initialText] re-opens the dialog with the name typed last time, after
  /// the user chose **Keep editing** in the merge offer.
  Future<void> _rename(LibraryManagerEntry entry, {String? initialText}) async {
    final l10n = AppLocalizations.of(context);
    final name = await showLibraryRenameDialog(
      context,
      currentName: entry.name,
      fieldLabel: _authors
          ? l10n.authorManagerNameLabel
          : l10n.sourceManagerTitleLabel,
      initialText: initialText,
    );
    if (name == null || !mounted) return;
    List<String> taken;
    try {
      final edit = await _repos.references.rename(widget.kind, entry.id, name);
      _offerUndo(edit, l10n.libraryManagerRenamedSnack(entry.name, name));
      return;
    } on ReferenceNameTakenException catch (e) {
      // diagnostics: silent — not a failure: the name is taken (authors only;
      // a source's title is not unique), and the merge offer is the answer.
      taken = e.liveIds;
    } catch (e, stackTrace) {
      logCaughtError(e, stackTrace, source: 'reference_manager_screen._rename');
      _showEditFailed();
      return;
    }
    final from = _rows?[entry.id];
    if (from is! Choreographer || !mounted) return;
    final AuthorMerge? merge;
    try {
      merge = await offerAuthorMerge(
        context,
        _repos,
        fromName: entry.name,
        from: from,
        typedName: name,
        liveIds: taken,
      );
    } catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'reference_manager_screen._rename.merge',
      );
      _showEditFailed();
      return;
    }
    if (merge == null) {
      if (mounted) await _rename(entry, initialText: name);
      return;
    }
    if (!mounted) return;
    _offerUndo(merge.undo, merge.snackText(l10n, entry.name));
  }

  Future<void> _mergeInto(LibraryManagerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final into = await showLibraryMergePicker(
      context,
      from: entry,
      candidates: _entries,
      searchHint: _searchHint(l10n),
    );
    if (into == null || !mounted) return;
    final from = _rows?[entry.id];
    final target = _rows?[into.id];
    if (from == null || target == null) return;
    final dropped = droppedDetailLines(l10n, switch ((target, from)) {
      (final Choreographer t, final Choreographer f) => authorMergeConflicts(
        t,
        [f],
      ),
      (final PublishedSource t, final PublishedSource f) =>
        sourceMergeConflicts(t, [f]),
      _ => const <ReferenceMergeConflict>[],
    });
    if (dropped.isNotEmpty &&
        !await showLibraryMergeConfirm(
          context,
          fromName: entry.name,
          intoName: into.name,
          dropped: dropped,
        )) {
      return;
    }
    if (!mounted) return;
    try {
      final edit = await _repos.references.merge(
        widget.kind,
        intoId: into.id,
        otherIds: [entry.id],
      );
      _offerUndo(edit, l10n.libraryManagerMergedSnack(entry.name, into.name));
    } catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'reference_manager_screen._mergeInto',
      );
      _showEditFailed();
    }
  }

  Future<void> _editDetails(LibraryManagerEntry entry) async {
    final row = _rows?[entry.id];
    final l10n = AppLocalizations.of(context);
    try {
      switch (row) {
        case Choreographer():
          final outcome = await editAuthorDetails(context, _repos, row);
          if (outcome case AuthorDetailsMerged(:final merge)) {
            _offerUndo(merge.undo, merge.snackText(l10n, entry.name));
          }
        case PublishedSource():
          final updated = await PublishedSourceDetailsDialog.show(context, row);
          if (updated == null) return;
          await _repos.publishedSources.upsert(updated, localUserEdit: true);
      }
    } catch (e, stackTrace) {
      logCaughtError(
        e,
        stackTrace,
        source: 'reference_manager_screen._editDetails',
      );
      _showEditFailed();
    }
    // No local splice: every write above lands in the table this screen
    // watches, so the new values arrive through the stream.
  }

  Future<void> _delete(LibraryManagerEntry entry) async {
    final l10n = AppLocalizations.of(context);
    try {
      final edit = await _repos.references.deleteUnused(widget.kind, entry.id);
      _offerUndo(edit, l10n.libraryManagerDeletedSnack(entry.name));
    } catch (e, stackTrace) {
      // A dance may have started using it since the list was drawn; the
      // guard refused, and nothing was written.
      logCaughtError(e, stackTrace, source: 'reference_manager_screen._delete');
      _showEditFailed();
    }
  }

  void _offerUndo(ReferenceEditUndo edit, String message) {
    if (!mounted) return;
    final repos = _repos;
    showLibraryUndoSnackBar(
      context,
      keyPrefix: '$_keyPrefix-manager',
      message: message,
      onUndo: () => repos.references.undo(edit),
    );
  }

  void _showEditFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).libraryManagerEditFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loading = _rows == null || _counts == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _authors ? l10n.authorManagerTitle : l10n.sourceManagerTitle,
        ),
      ),
      body: _loadError != null
          ? LoadErrorView(
              message: _authors
                  ? l10n.authorManagerLoadError
                  : l10n.sourceManagerLoadError,
              onRetry: _retry,
            )
          : loading
          ? const Center(child: CircularProgressIndicator())
          : LibraryManagerList(
              keyPrefix: _keyPrefix,
              entries: _entries,
              searchHint: _searchHint(l10n),
              emptyMessage: _authors
                  ? l10n.authorManagerEmpty
                  : l10n.sourceManagerEmpty,
              actionsFor: _actionsFor,
            ),
    );
  }
}
